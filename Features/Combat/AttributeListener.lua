-- AttributeListener module.
local AttributeListener = {
	lastParry = nil,
	lastParryAttempt = nil,
	lastParrySuccess = nil,
	lastDash = nil,
	lastKnock = nil,
	hudParryLastPath = nil,
	hudParryLastScanAt = 0,
	hudParryLastSeenAt = nil,
	hudParryRemainingMs = nil,
	hudParrySeenEver = false,
	hudParryText = nil,
	stateValues = {},
}

---@modules Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Features.Combat.TimingHarvester
local TimingHarvester = require("Features/Combat/TimingHarvester")

---@module Features.Combat.ParryCooldownProbe
local ParryCooldownProbe = require("Features/Combat/ParryCooldownProbe")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

-- Services.
local players = game:GetService("Players")

-- Top-level maid (CharacterAdded / CharacterRemoving signals).
local attributeMaid = Maid.new()

-- Per-character maid; cleaned on CharacterRemoving. Holds watchers on CharacterState BoolValues.
local stateMaid = Maid.new()

local DEFAULT_SYNTHETIC_PARRY_COOLDOWN_MS = 500
local DASH_COOLDOWN_S = 1750 / 1000
local HUD_PARRY_SCAN_INTERVAL_S = 0.10

---@return number
local function parryCooldownSeconds()
	local cooldownMs = Configuration.expectOptionValue("SyntheticParryCooldownMs")

	if type(cooldownMs) ~= "number" or cooldownMs < 0 then
		cooldownMs = DEFAULT_SYNTHETIC_PARRY_COOLDOWN_MS
	end

	return cooldownMs / 1000
end

---@return Folder?
local function cooldownsFolder()
	local localPlayer = players.LocalPlayer
	local folder = localPlayer and localPlayer:FindFirstChild("Cooldowns")

	if folder and folder:IsA("Folder") then
		return folder
	end

	return nil
end

---@param cooldownName string
---@return Instance?, string?, boolean
local function cooldownEntry(cooldownName)
	local folder = cooldownsFolder()
	if not folder then
		return nil, nil, false
	end

	for _, child in ipairs(folder:GetChildren()) do
		if string.lower(child.Name) == string.lower(cooldownName) then
			return child, child:GetFullName(), true
		end
	end

	return nil, string.format("%s.%s", folder:GetFullName(), cooldownName), true
end

---@param instance Instance?
---@return number?
local function cooldownRemainingMs(instance)
	if not instance then
		return nil
	end

	local raw = nil
	if instance:IsA("NumberValue") or instance:IsA("IntValue") then
		raw = instance.Value
	elseif instance:IsA("StringValue") then
		raw = tonumber(instance.Value)
	else
		raw = instance:GetAttribute("Remaining")
			or instance:GetAttribute("Cooldown")
			or instance:GetAttribute("TimeLeft")
			or instance:GetAttribute("Value")
	end

	if type(raw) ~= "number" then
		return nil
	end

	if raw > 100 then
		return math.max(0, math.round(raw))
	end

	return math.max(0, math.round(raw * 1000))
end

---@param instance Instance?
---@return boolean
local function guiTreeVisible(instance)
	local current = instance

	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end

		if current:IsA("ScreenGui") and not current.Enabled then
			return false
		end

		current = current.Parent
	end

	return true
end

---@param text string?
---@return number?, number
local function parseHudParryText(text)
	if type(text) ~= "string" or text == "" then
		return nil, 0
	end

	local exact = text:match("^%s*Parry%s*%(([%d%.]+)%)%s*$")
	if exact then
		return tonumber(exact), 20
	end

	local partial = text:match("[Pp]arry%s*%(([%d%.]+)%)")
	if partial then
		return tonumber(partial), 10
	end

	return nil, 0
end

---@return number?, string?, string?, boolean
local function hudParryCooldown()
	local now = tick()
	if now - AttributeListener.hudParryLastScanAt < HUD_PARRY_SCAN_INTERVAL_S then
		return AttributeListener.hudParryRemainingMs,
			AttributeListener.hudParryText,
			AttributeListener.hudParryLastPath,
			AttributeListener.hudParrySeenEver
	end

	AttributeListener.hudParryLastScanAt = now

	local localPlayer = players.LocalPlayer
	local playerGui = localPlayer and localPlayer:FindFirstChild("PlayerGui")
	local bestRemainingMs, bestText, bestPath, bestScore = nil, nil, nil, -1

	if playerGui then
		for _, descendant in ipairs(playerGui:GetDescendants()) do
			if (descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox")) and guiTreeVisible(descendant) then
				local seconds, score = parseHudParryText(descendant.Text)
				if seconds and score > bestScore then
					bestScore = score
					bestRemainingMs = math.max(0, math.round(seconds * 1000))
					bestText = descendant.Text
					bestPath = descendant:GetFullName()
				end
			end
		end
	end

	AttributeListener.hudParryRemainingMs = bestRemainingMs
	AttributeListener.hudParryText = bestText
	AttributeListener.hudParryLastPath = bestPath or AttributeListener.hudParryLastPath

	if bestRemainingMs ~= nil then
		AttributeListener.hudParrySeenEver = true
		AttributeListener.hudParryLastSeenAt = now
	end

	return AttributeListener.hudParryRemainingMs,
		AttributeListener.hudParryText,
		AttributeListener.hudParryLastPath,
		AttributeListener.hudParrySeenEver
end

-- BoolValues under character.CharacterState that we care about. When the .Value flips true,
-- the paired callback fires. Mashle splits state across many BoolValues instead of using
-- Type Soul's single CurrentState string attribute.
local WATCHED = {
	Parry = function()
		AttributeListener.lastParry = nil
		AttributeListener.lastParrySuccess = tick()
		ParryCooldownProbe.onParryResult("Parry")
		TimingHarvester.onParryResult(false)
	end,
	PerfectParry = function()
		AttributeListener.lastParry = nil
		AttributeListener.lastParrySuccess = tick()
		ParryCooldownProbe.onParryResult("PerfectParry")
		TimingHarvester.onParryResult(true)
	end,
	DashDodge = function()
		AttributeListener.lastDash = tick()
	end,
	Ragdoll = function()
		AttributeListener.lastKnock = tick()
	end,
	Stun = function()
		AttributeListener.lastKnock = tick()
	end,
}

---Read a CharacterState BoolValue from any character. Returns false when missing.
---@param character Model?
---@param name string
---@return boolean
function AttributeListener.csOn(character, name)
	if not character then
		return false
	end

	local state = character:FindFirstChild("CharacterState")
	if not state then
		return false
	end

	local bv = state:FindFirstChild(name)
	if not bv or not bv:IsA("BoolValue") then
		return false
	end

	return bv.Value
end

---Start the local parry cooldown from a parry attempt.
function AttributeListener.markParryAttempt()
	local now = tick()
	local parryCooldownS = parryCooldownSeconds()
	AttributeListener.lastParryAttempt = now
	ParryCooldownProbe.onParryAttempt("script")

	-- Do not extend the synthetic cooldown when we are already locked out. That makes
	-- repeated checks drift farther away from the real game cooldown.
	if not AttributeListener.lastParry or now - AttributeListener.lastParry >= parryCooldownS then
		AttributeListener.lastParry = now
	end
end

---Clear the local parry cooldown when the game confirms a successful parry.
function AttributeListener.clearParryCooldown()
	AttributeListener.lastParry = nil
	AttributeListener.lastParrySuccess = tick()
	ParryCooldownProbe.onParryResult("ParryEffect")
end

---Read a CharacterState BoolValue on the local character.
---@param name string
---@return boolean
function AttributeListener.cs(name)
	local localPlayer = players.LocalPlayer
	return AttributeListener.csOn(localPlayer and localPlayer.Character, name)
end

---Hook a BoolValue so true transitions call onTrue.
---@param bv BoolValue
---@param onTrue function
local function watchBool(bv, onTrue)
	AttributeListener.stateValues[bv.Name] = bv.Value

	local signal = Signal.new(bv:GetPropertyChangedSignal("Value"))
	stateMaid:add(signal:connect("AttributeListener_CSValue_" .. bv.Name, function()
		AttributeListener.stateValues[bv.Name] = bv.Value

		if bv.Value then
			onTrue()
		end
	end))
end

---Attach watchers to every BoolValue we care about under a CharacterState folder, and handle
---late-added ones via ChildAdded.
---@param characterState Instance
local function attachStateWatches(characterState)
	for _, child in ipairs(characterState:GetChildren()) do
		if child:IsA("BoolValue") then
			watchBool(child, WATCHED[child.Name] or function() end)
		end
	end

	local childAdded = Signal.new(characterState.ChildAdded)
	stateMaid:add(childAdded:connect("AttributeListener_OnCSChildAdded", function(child)
		if child:IsA("BoolValue") then
			watchBool(child, WATCHED[child.Name] or function() end)
		end
	end))
end

---On character added.
---@param character Model
local function onCharacterAdded(character)
	stateMaid:clean()

	task.spawn(function()
		local cs = character:WaitForChild("CharacterState", 10)
		if cs then
			attachStateWatches(cs)
		end
	end)
end

---On character removing.
---@param character Model
local function onCharacterRemoving(character)
	stateMaid:clean()
	AttributeListener.lastParry = nil
	AttributeListener.lastParryAttempt = nil
	AttributeListener.lastParrySuccess = nil
	AttributeListener.lastDash = nil
	AttributeListener.lastKnock = nil
	AttributeListener.hudParryLastPath = nil
	AttributeListener.hudParryLastScanAt = 0
	AttributeListener.hudParryLastSeenAt = nil
	AttributeListener.hudParryRemainingMs = nil
	AttributeListener.hudParrySeenEver = false
	AttributeListener.hudParryText = nil
	AttributeListener.stateValues = {}
end

---Knocked recently?
---@return boolean
function AttributeListener.krecently()
	local localPlayer = players.LocalPlayer
	local character = localPlayer.Character
	if not character then
		return false
	end

	return AttributeListener.lastKnock and tick() - AttributeListener.lastKnock <= 0.250
end

---Milliseconds remaining on the synthetic parry cooldown.
---@return number
function AttributeListener.parryRemainingMs()
	if not AttributeListener.lastParry then
		return 0
	end

	local parryCooldownS = parryCooldownSeconds()

	return math.max(0, math.round((parryCooldownS - (tick() - AttributeListener.lastParry)) * 1000))
end

---Active CharacterState BoolValues on the local character.
---@return string[]
function AttributeListener.activeStates()
	local active = {}

	for name, value in pairs(AttributeListener.stateValues) do
		if value then
			table.insert(active, name)
		end
	end

	table.sort(active)
	return active
end

---Current active entries inside the player's Cooldowns folder.
---@return string[]
function AttributeListener.activeCooldowns()
	local folder = cooldownsFolder()
	local active = {}

	if not folder then
		return active
	end

	for _, child in ipairs(folder:GetChildren()) do
		table.insert(active, child.Name)
	end

	table.sort(active)
	return active
end

---Milliseconds remaining on the synthetic dash cooldown.
---@return number
function AttributeListener.dashRemainingMs()
	if not AttributeListener.lastDash then
		return 0
	end

	return math.max(0, math.round((DASH_COOLDOWN_S - (tick() - AttributeListener.lastDash)) * 1000))
end

---Current local parry availability snapshot.
---@return table
function AttributeListener.parryStatus()
	local now = tick()
	local parryCooldown, cooldownPath, hasCooldownFolder = cooldownEntry("Parry")

	if hasCooldownFolder then
		return {
			canParry = parryCooldown == nil,
			reason = parryCooldown and "cooldowns-folder" or "cooldowns-ready",
			remainingMs = cooldownRemainingMs(parryCooldown) or 0,
			sinceAttemptMs = AttributeListener.lastParryAttempt and math.round((now - AttributeListener.lastParryAttempt) * 1000)
				or nil,
			sinceSuccessMs = AttributeListener.lastParrySuccess and math.round((now - AttributeListener.lastParrySuccess) * 1000)
				or nil,
			activeStates = AttributeListener.activeStates(),
			cooldownName = parryCooldown and parryCooldown.Name or "Parry",
			cooldownPath = cooldownPath,
			hudPath = nil,
			hudText = nil,
		}
	end

	local hudRemainingMs, hudText, hudPath, hudSeenEver = hudParryCooldown()

	if hudSeenEver then
		return {
			canParry = hudRemainingMs == nil or hudRemainingMs <= 0,
			reason = hudRemainingMs and hudRemainingMs > 0 and "hud-cooldown" or "hud-ready",
			remainingMs = hudRemainingMs or 0,
			sinceAttemptMs = AttributeListener.lastParryAttempt and math.round((now - AttributeListener.lastParryAttempt) * 1000)
				or nil,
			sinceSuccessMs = AttributeListener.lastParrySuccess and math.round((now - AttributeListener.lastParrySuccess) * 1000)
				or nil,
			activeStates = AttributeListener.activeStates(),
			cooldownName = hudText,
			cooldownPath = hudPath,
			hudPath = hudPath,
			hudText = hudText,
		}
	end

	local remainingMs = AttributeListener.parryRemainingMs()
	local activeStates = AttributeListener.activeStates()
	local reason = remainingMs > 0 and "fallback-cooldown" or "fallback-ready"

	return {
		canParry = remainingMs <= 0,
		reason = reason,
		remainingMs = remainingMs,
		sinceAttemptMs = AttributeListener.lastParryAttempt and math.round((now - AttributeListener.lastParryAttempt) * 1000)
			or nil,
		sinceSuccessMs = AttributeListener.lastParrySuccess and math.round((now - AttributeListener.lastParrySuccess) * 1000)
			or nil,
		activeStates = activeStates,
		cooldownName = "SyntheticParryCooldown",
		cooldownPath = nil,
		hudPath = hudPath,
		hudText = hudText,
	}
end

---Current local dash availability snapshot.
---@return table
function AttributeListener.dashStatus()
	local dashCooldown, cooldownPath, hasCooldownFolder = cooldownEntry("Dash")

	if hasCooldownFolder then
		return {
			canDash = dashCooldown == nil,
			reason = dashCooldown and "cooldowns-folder" or "cooldowns-ready",
			remainingMs = cooldownRemainingMs(dashCooldown) or 0,
			activeStates = AttributeListener.activeStates(),
			cooldownName = dashCooldown and dashCooldown.Name or "Dash",
			cooldownPath = cooldownPath,
		}
	end

	local remainingMs = AttributeListener.dashRemainingMs()
	local reason = remainingMs > 0 and "fallback-cooldown" or "fallback-ready"

	return {
		canDash = remainingMs <= 0,
		reason = reason,
		remainingMs = remainingMs,
		activeStates = AttributeListener.activeStates(),
		cooldownName = "SyntheticDashCooldown",
		cooldownPath = nil,
	}
end

---Can we parry?
---@return boolean
function AttributeListener.cparry()
	local localPlayer = players.LocalPlayer
	local character = localPlayer.Character
	if not character then
		return false
	end

	return AttributeListener.parryStatus().canParry
end

---Can we dash?
---@return boolean
function AttributeListener.cdash()
	local localPlayer = players.LocalPlayer
	local character = localPlayer.Character
	if not character then
		return false
	end

	return AttributeListener.dashStatus().canDash
end

---Initialize AttributeListener module.
function AttributeListener.init()
	local localPlayer = players.LocalPlayer
	local characterAddedSignal = Signal.new(localPlayer.CharacterAdded)
	local characterRemovingSignal = Signal.new(localPlayer.CharacterRemoving)

	attributeMaid:add(characterAddedSignal:connect("AttributeListener_OnCharacterAdded", function(character)
		onCharacterAdded(character)
	end))

	attributeMaid:add(characterRemovingSignal:connect("AttributeListener_OnCharacterRemoving", function(character)
		onCharacterRemoving(character)
	end))

	if localPlayer.Character then
		onCharacterAdded(localPlayer.Character)
	end
end

---Detach AttributeListener module.
function AttributeListener.detach()
	stateMaid:clean()
	attributeMaid:clean()
end

-- Return AttributeListener module.
return AttributeListener
