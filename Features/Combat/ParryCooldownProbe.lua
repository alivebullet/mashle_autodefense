local ParryCooldownProbe = { active = nil, token = 0, _debugLog = {} }

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module GUI.Library
local Library = require("GUI/Library")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Game.Keybinding
local Keybinding = require("Game/Keybinding")

local players = game:GetService("Players")
local userInputService = game:GetService("UserInputService")

local MAX_RESULTS = 10
local MAX_DEBUG_LINES = 160
local PROBE_DURATION_S = 2.5
local KEYWORDS = {
	"parry",
	"block",
	"cooldown",
	"cd",
	"skill",
	"ability",
	"slot",
	"hotbar",
	"guard",
}
local PROPERTY_WEIGHTS = {
	visible = 8,
	text = 8,
	enabled = 7,
	size = 5,
	absSize = 5,
	imageTransparency = 4,
	backgroundTransparency = 4,
	offset = 4,
	rotation = 2,
	created = 6,
	removed = 6,
}

local probeMaid = Maid.new()

local function appendLog(line)
	table.insert(ParryCooldownProbe._debugLog, line)

	while #ParryCooldownProbe._debugLog > MAX_DEBUG_LINES do
		table.remove(ParryCooldownProbe._debugLog, 1)
	end

	Library:AddTelemetryEntry("%s", line)
	Logger.warn("%s", line)
end

local function trunc(value)
	local used = tostring(value)

	if #used > 80 then
		return used:sub(1, 77) .. "..."
	end

	return used
end

local function pathFor(instance, root)
	local names = {}
	local current = instance

	while current and current ~= root do
		table.insert(names, 1, current.Name)
		current = current.Parent
	end

	return string.format("%s.%s", root and root.Name or "<nil>", table.concat(names, "."))
end

local function readInstanceState(instance)
	if instance:IsA("GuiObject") then
		local state = {
			class = instance.ClassName,
			visible = tostring(instance.Visible),
			size = tostring(instance.Size),
			absSize = string.format("%dx%d", math.round(instance.AbsoluteSize.X), math.round(instance.AbsoluteSize.Y)),
			backgroundTransparency = string.format("%.2f", instance.BackgroundTransparency),
		}

		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			state.text = instance.Text
		end

		if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			state.imageTransparency = string.format("%.2f", instance.ImageTransparency)
		end

		return state
	end

	if instance:IsA("UIGradient") then
		return {
			class = instance.ClassName,
			enabled = tostring(instance.Enabled),
			offset = tostring(instance.Offset),
			rotation = tostring(instance.Rotation),
		}
	end

	return nil
end

local function captureSnapshot()
	local localPlayer = players.LocalPlayer
	local playerGui = localPlayer and localPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil, nil
	end

	local snapshot = {}

	for _, descendant in next, playerGui:GetDescendants() do
		local state = readInstanceState(descendant)
		if state then
			snapshot[pathFor(descendant, playerGui)] = state
		end
	end

	return snapshot, playerGui
end

local function keywordScore(path)
	local score = 0
	local lowerPath = string.lower(path)

	for _, keyword in ipairs(KEYWORDS) do
		if string.find(lowerPath, keyword, 1, true) then
			score = score + 10
		end
	end

	return score
end

local function addChange(changes, path, className, property, firstValue, lastValue)
	local key = string.format("%s::%s", path, property)
	local entry = changes[key]

	if not entry then
		entry = {
			path = path,
			className = className,
			property = property,
			firstValue = tostring(firstValue),
			lastValue = tostring(lastValue),
			count = 0,
			score = keywordScore(path) + (PROPERTY_WEIGHTS[property] or 1),
		}
		changes[key] = entry
	end

	entry.count = entry.count + 1
	entry.lastValue = tostring(lastValue)
	entry.score = entry.score + 1
end

local function collectChanges(previous, current, changes)
	for path, currentState in pairs(current) do
		local previousState = previous[path]

		if not previousState then
			addChange(changes, path, currentState.class, "created", "<missing>", currentState.class)
		else
			for property, value in pairs(currentState) do
				if property ~= "class" and previousState[property] ~= value then
					addChange(changes, path, currentState.class, property, previousState[property], value)
				end
			end
		end
	end

	for path, previousState in pairs(previous) do
		if not current[path] then
			addChange(changes, path, previousState.class, "removed", previousState.class, "<missing>")
		end
	end
	end

local function reportActiveProbe(active)
	local results = {}

	for _, change in pairs(active.changes) do
		table.insert(results, change)
	end

	table.sort(results, function(left, right)
		if left.score == right.score then
			if left.count == right.count then
				return left.path < right.path
			end

			return left.count > right.count
		end

		return left.score > right.score
	end)

	appendLog(
		string.format(
			"[ParryProbe #%d] source=%s sampled=%.1fs playerGuiChanges=%d",
			active.token,
			active.source,
			os.clock() - active.startedAt,
			#results
		)
	)

	for _, event in ipairs(active.events) do
		appendLog(string.format("[ParryProbe #%d] event=%s at +%dms", active.token, event.label, event.ms))
	end

	if #results == 0 then
		appendLog(string.format("[ParryProbe #%d] no PlayerGui candidates changed.", active.token))
		return
	end

	for index = 1, math.min(MAX_RESULTS, #results) do
		local result = results[index]
		appendLog(
			string.format(
				"[ParryProbe #%d] candidate %s [%s] %s: %s -> %s (x%d)",
				active.token,
				result.path,
				result.className,
				result.property,
				trunc(result.firstValue),
				trunc(result.lastValue),
				result.count
			)
		)
	end
end

local function startProbe(source)
	if not Configuration.expectToggleValue("EnableParryCooldownProbe") then
		return
	end

	local snapshot = nil
	snapshot = select(1, captureSnapshot())
	if not snapshot then
		appendLog("[ParryProbe] unable to capture PlayerGui snapshot.")
		return
	end

	ParryCooldownProbe.token = ParryCooldownProbe.token + 1

	local active = {
		token = ParryCooldownProbe.token,
		source = source,
		startedAt = os.clock(),
		endTime = os.clock() + PROBE_DURATION_S,
		previous = snapshot,
		changes = {},
		events = {},
	}

	ParryCooldownProbe.active = active

	task.spawn(function()
		while ParryCooldownProbe.active and ParryCooldownProbe.active.token == active.token do
			if os.clock() >= active.endTime then
				reportActiveProbe(active)
				if ParryCooldownProbe.active and ParryCooldownProbe.active.token == active.token then
					ParryCooldownProbe.active = nil
				end
				return
			end

			task.wait(0.1)

			local current = select(1, captureSnapshot())
			if current then
				collectChanges(active.previous, current, active.changes)
				active.previous = current
			end
		end
	end)
end

function ParryCooldownProbe.onParryAttempt(source)
	startProbe(source or "script")
end

function ParryCooldownProbe.onParryResult(label)
	local active = ParryCooldownProbe.active
	if not active then
		return
	end

	table.insert(active.events, {
		label = label,
		ms = math.round((os.clock() - active.startedAt) * 1000),
	})
end

function ParryCooldownProbe.getDebugLog()
	return table.concat(ParryCooldownProbe._debugLog, "\n")
end

function ParryCooldownProbe.clearDebugLog()
	table.clear(ParryCooldownProbe._debugLog)
end

function ParryCooldownProbe.init()
	local inputBegan = Signal.new(userInputService.InputBegan)

	probeMaid:add(inputBegan:connect("ParryCooldownProbe_OnInputBegan", function(input)
		local blockParryKey = Keybinding.info["Block / Parry"] or Enum.KeyCode.F

		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == blockParryKey then
			startProbe("manual-key")
		end
	end))
end

function ParryCooldownProbe.detach()
	ParryCooldownProbe.token = ParryCooldownProbe.token + 1
	ParryCooldownProbe.active = nil
	probeMaid:clean()
end

return ParryCooldownProbe