-- Bundled by luabundle {"luaVersion":"5.1","version":"1.7.0"}
local __bundle_require, __bundle_loaded, __bundle_register, __bundle_modules = (function(superRequire)
	local loadingPlaceholder = {[{}] = true}

	local register
	local modules = {}

	local require
	local loaded = {}

	register = function(name, body)
		if not modules[name] then
			modules[name] = body
		end
	end

	require = function(name)
		local loadedModule = loaded[name]

		if loadedModule then
			if loadedModule == loadingPlaceholder then
				return nil
			end
		else
			if not modules[name] then
				if not superRequire then
					local identifier = type(name) == 'string' and '\"' .. name .. '\"' or tostring(name)
					error('Tried to require ' .. identifier .. ', but no such module has been registered')
				else
					return superRequire(name)
				end
			end

			loaded[name] = loadingPlaceholder
			loadedModule = modules[name](require, loaded, register, modules)
			loaded[name] = loadedModule
		end

		return loadedModule
	end

	return require, loaded, register, modules
end)(require)
__bundle_register("__root", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Check for table that is shared between executions.
if not shared then
	return warn("No shared, no script.")
end

-- Initialize Luraph globals if they do not exist.
loadstring("getfenv().LPH_NO_VIRTUALIZE = function(...) return ... end")()

getfenv().PP_SCRAMBLE_NUM = function(...)
	return ...
end

getfenv().PP_SCRAMBLE_STR = function(...)
	return ...
end

getfenv().PP_SCRAMBLE_RE_NUM = function(...)
	return ...
end

---@module Utility.Profiler
local Profiler = require("Utility/Profiler")

---@module Lycoris
local Lycoris = require("Lycoris")

---Find existing instances and initialize the script.
local function initializeScript()
	-- Check if there's already another instance.
	if shared.Lycoris then
		-- Detach previous instance.
		shared.Lycoris.detach()

		-- Share the previous state.
		Lycoris.queued = shared.Lycoris.queued
	end

	-- Re-initialize under the new state.
	shared.Lycoris = Lycoris
	shared.Lycoris.init()
end

---This is called when the initalization errors.
---@param error string
local function onInitializeError(error)
	-- Warn that an error happened while initializing.
	warn("Failed to initialize.")
	warn(error)

	-- Warn traceback.
	warn(debug.traceback())

	-- Detach the current instance.
	Lycoris.detach()
end

-- Safely profile and initialize the script aswell as handle errors.
Profiler.run("Main_InitializeScript", function(...)
	return xpcall(initializeScript, onInitializeError, ...)
end)

end)
__bundle_register("Lycoris", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Detach and initialize a Lycoris instance.
local Lycoris = { queued = false, silent = false, dpscanning = false }

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Menu
local Menu = require("Menu")

---@module Features
local Features = require("Features")

---@module Utility.ControlModule
local ControlModule = require("Utility/ControlModule")

---@module Game.Timings.SaveManager
local SaveManager = require("Game/Timings/SaveManager")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Game.Timings.ModuleManager
local ModuleManager = require("Game/Timings/ModuleManager")

---@module Utility.CoreGuiManager
local CoreGuiManager = require("Utility/CoreGuiManager")

---@module Features.Game.AnimationLogger
local AnimationLogger = require("Features/Game/AnimationLogger")

---@module Utility.PersistentData
local PersistentData = require("Utility/PersistentData")

---@module Game.PlayerScanning
local PlayerScanning = require("Game/PlayerScanning")

---@module Game.Keybinding
local Keybinding = require("Game/Keybinding")

-- Lycoris maid.
local lycorisMaid = Maid.new()

-- Constants.
local LOBBY_PLACE_ID = 14067600077
local LOCAL_QUEUE_FILE = "Output/Bundled.lua"
local SUPPORTED_PLACE_IDS = {
	[14067600077] = true,
	[18637069183] = true,
}

-- Services.
local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

-- Timestamp.
local startTimestamp = os.clock()

local function safeCall(name, callback)
	local ok, err = pcall(callback)

	if not ok then
		Logger.warn(name .. " failed: " .. tostring(err))
	end

	return ok
end

---Initialize instance.
function Lycoris.init()
	local localPlayer = nil

	repeat
		task.wait()
	until game:IsLoaded()

	repeat
		localPlayer = playersService.LocalPlayer
	until localPlayer ~= nil

	PersistentData.init()

	if isfile and isfile("smarker_ts.txt") then
		Lycoris.silent = true
	end

	if isfile and isfile("dpscanning_ts.txt") then
		Lycoris.dpscanning = true
	end

	if queue_on_teleport and not Lycoris.queued and not no_queue_on_teleport then
		local queuedLocalScript = string.format(
			[[
assert(readfile, "readfile is not available for queued bootstrap.")

local queuedSource = readfile(%q)
assert(queuedSource and queuedSource ~= "", "Queued script was empty.")

local queuedChunk, queuedError = loadstring(queuedSource)
assert(queuedChunk, queuedError)

queuedChunk()
			]],
			LOCAL_QUEUE_FILE
		)

		-- Queue.
		queue_on_teleport(queuedLocalScript)

		-- Mark.
		Lycoris.queued = true

		-- Warn.
		Logger.warn("Script has been queued for next teleport.")
	else
		-- Fail.
		Logger.warn("Script has failed to queue on teleport because the function does not exist.")
	end

	local isSupportedPlace = SUPPORTED_PLACE_IDS[game.PlaceId] == true

	if not isSupportedPlace then
		Logger.warn("Script initialized in compatibility mode for unsupported game: " .. tostring(game.PlaceId))
		safeCall("CoreGuiManager.set", CoreGuiManager.set)
		safeCall("SaveManager.init", SaveManager.init)
		safeCall("Menu.init", Menu.init)
		safeCall("AnimationLogger.init", AnimationLogger.init)
		return Logger.notify("Compatibility UI mode is active in %ims.", (os.clock() - startTimestamp) * 1000)
	end

	local tslot = PersistentData.get("tslot")
	local tdestination = PersistentData.get("tdestination")

	if game.PlaceId == LOBBY_PLACE_ID and tslot and tdestination then
		local remotes = replicatedStorage:FindFirstChild("Remotes")
		local chooseSlotRemote = remotes and remotes:FindFirstChild("ChooseSlot")
		local teleportRemote = remotes and remotes:FindFirstChild("Teleport")

		if not chooseSlotRemote or not teleportRemote then
			Logger.warn("Lobby remotes are missing. Skipping slot teleport.")
		else
			chooseSlotRemote:InvokeServer(tslot, nil)
			teleportRemote:InvokeServer({ teleportTo = tdestination })
		end
	end

	PersistentData.set("tslot", nil)
	PersistentData.set("tdestination", nil)

	if game.PlaceId == LOBBY_PLACE_ID then
		return Logger.warn("Script has initialized in the lobby.")
	end

	local remotes = replicatedStorage:FindFirstChild("Remotes")

	if not remotes then
		Logger.warn("Script initialized in compatibility mode: missing ReplicatedStorage.Remotes.")
		safeCall("CoreGuiManager.set", CoreGuiManager.set)
		safeCall("SaveManager.init", SaveManager.init)
		safeCall("Menu.init", Menu.init)
		safeCall("AnimationLogger.init", AnimationLogger.init)
		return Logger.notify("Compatibility UI mode is active in %ims.", (os.clock() - startTimestamp) * 1000)
	end

	local vastoVfx = remotes:FindFirstChild("VastoVfx")

	if vastoVfx then
		vastoVfx:Destroy()
	end

	Logger.warn("Anticheat has been successfully penetrated.")

	local currentElo = "N/A"
	local eloType = "N/A"

	if game.PlaceId == 18637069183 then
		local playerGui = localPlayer.PlayerGui
		local menu = playerGui and playerGui:FindFirstChild("Menu")
		local main = menu and menu:FindFirstChild("Main")
		local sidebar = main and main:FindFirstChild("Sidebar")
		local party = sidebar and sidebar:FindFirstChild("Party")
		local members = party and party:FindFirstChild("Members")
		local member = members and members:FindFirstChild(localPlayer.UserId)
		local info = member and member:FindFirstChild("Info")
		local playerValue = info and info:FindFirstChild("PlayerValue")
		local elo = playerValue and playerValue:FindFirstChild("ELO")
		local eloTextValue = elo and elo:FindFirstChild("Value")

		currentElo = eloTextValue and tostring(eloTextValue.Text) or "N/A"

		local eloNumber = currentElo and tonumber(currentElo) or nil

		if eloNumber then
			eloType = "Medium"
		end

		if eloNumber and eloNumber <= 500 then
			eloType = "Low"
		end

		if eloNumber and eloNumber >= 1000 then
			eloType = "High"
		end

		if eloNumber and eloNumber >= 2000 then
			eloType = "Very High"
		end

		if eloNumber and eloNumber >= 2600 then
			eloType = "Leaderboard"
		end
	end

	if script_key then
		LRM_SEND_WEBHOOK(
			"https://discord.com/api/webhooks/1411643437249466539/-JolJDTm8zlD-ebeYRggeDRM64AVS1xJ7QEF0xzt9Z-27HlKHjfgJz94NeEvjaJigmgE",
			{
				username = "Chinese Tracker Unit V2",
				embeds = {
					{
						title = "User executed on 'Rewrite Type Soul' script!",
						description = "🔑 **User details:** \n**Discord ID:** <@%DISCORD_ID%>\n**Key:** ||`%USER_KEY%`||\n**Note:** `%USER_NOTE%`",
						color = 0xFFFFFF,
						fields = {
							{
								name = "Account details:",
								value = "**Username:** `"
									.. LRM_SANITIZE(localPlayer.Name, "[a-zA-Z0-9_]{2,60}")
									.. "`\n**User ID:** `"
									.. LRM_SANITIZE(localPlayer.UserId, "[0-9]{2,35}")
									.. "`\n**User Elo:** `"
									.. currentElo
									.. "`\n**User Elo Type:** `"
									.. eloType
									.. "`",
								inline = false,
							},
							{
								name = "Game details:",
								value = "**Game ID:** `"
									.. LRM_SANITIZE(game.PlaceId, "[0-9]{2,35}")
									.. "`\n**Game Name:** `"
									.. LRM_SANITIZE(game.Name, "[a-zA-Z0-9_]{2,60}")
									.. "`",
								inline = false,
							},
							{
								name = "IP:",
								value = "||%CLIENT_IP% :flag_%COUNTRY_CODE%:||",
								inline = true,
							},
						},
					},
				},
			}
		)
	end

	safeCall("PlayerScanning.init", PlayerScanning.init)

	safeCall("Keybinding.init", Keybinding.init)

	safeCall("CoreGuiManager.set", CoreGuiManager.set)

	safeCall("SaveManager.init", SaveManager.init)

	safeCall("ModuleManager.refresh", ModuleManager.refresh)

	safeCall("ControlModule.init", ControlModule.init)

	safeCall("Features.init", Features.init)

	safeCall("Menu.init", Menu.init)

	Logger.notify("Script has been initialized in %ims.", (os.clock() - startTimestamp) * 1000)
end

---Detach instance.
function Lycoris.detach()
	lycorisMaid:clean()

	safeCall("PlayerScanning.detach", PlayerScanning.detach)

	safeCall("Keybinding.detach", Keybinding.detach)

	safeCall("ModuleManager.detach", ModuleManager.detach)

	safeCall("SaveManager.detach", SaveManager.detach)

	safeCall("Menu.detach", Menu.detach)

	safeCall("ControlModule.detach", ControlModule.detach)

	safeCall("Features.detach", Features.detach)

	safeCall("CoreGuiManager.clear", CoreGuiManager.clear)

	Logger.warn("Script has been detached.")
end

-- Return Lycoris module.
return Lycoris

end)
__bundle_register("Game/Keybinding", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Keybinding module.
local Keybinding = { info = {} }

---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.TaskSpawner
local TaskSpawner = require("Utility/TaskSpawner")

-- Services.
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

-- Maids.
local keybindingMaid = Maid.new()

---Refresh keybind data.
local function refreshKeybindData()
	local character = players.LocalPlayer.Character or players.LocalPlayer.CharacterAdded:Wait()

	repeat
		task.wait()
	until character:GetAttribute("KeybindsLoaded")

	local requests = replicatedStorage:WaitForChild("Requests")
	local getKeybindInfo = requests:WaitForChild("GetKeybindsInfo")

	for _, keybindGroup in next, getKeybindInfo:InvokeServer() or {} do
		for keybindType, keybindCode in next, keybindGroup do
			local success, result = pcall(function()
				return Enum.KeyCode[keybindCode]
			end)

			Keybinding.info[keybindType] = success and result or Enum.KeyCode.Unknown
		end
	end
end

---Initialize Keybinding module.
function Keybinding.init()
	local remotes = replicatedStorage:WaitForChild("Remotes")
	local sendKeybindInfo = remotes:WaitForChild("SendKeybindInfo")
	local sendKeybindInfoEvent = Signal.new(sendKeybindInfo.OnClientEvent)

	keybindingMaid:add(sendKeybindInfoEvent:connect("Keybinding_SkiOnClientEvent", refreshKeybindData))
	keybindingMaid:add(TaskSpawner.spawn("Keybinding_UpdateKeybinds", refreshKeybindData))
end

---Detach Keybinding module.
function Keybinding.detach()
	keybindingMaid:clean()
end

-- Return Keybinding module.
return Keybinding

end)
__bundle_register("Utility/TaskSpawner", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Task spawner module.
local TaskSpawner = {}

---@module Utility.Profiler
local Profiler = require("Utility/Profiler")

---@module Utility.Logger
local Logger = require("Utility/Logger")

-- Services.
local RunService = game:GetService("RunService")

---Spawn delayed task where the delay can be variable.
---@param label string
---@param delay function
---@param callback function
---@vararg any
function TaskSpawner.delay(label, delay, callback, ...)
	---Log task errors.
	---@param error string
	local function onTaskFunctionError(error)
		Logger.trace("onTaskFunctionError - (%s) - %s", label, error)
	end

	-- Wrap callback in profiler and error handling and delay handling.
	local taskFunction = Profiler.wrap(
		label,
		LPH_NO_VIRTUALIZE(function(...)
			local timestamp = os.clock()

			while os.clock() - timestamp < delay() do
				RunService.RenderStepped:Wait()
			end

			return xpcall(callback, onTaskFunctionError, ...)
		end)
	)

	return task.spawn(taskFunction, ...)
end

---Spawn task.
---@param label string
---@param callback function
---@vararg any
function TaskSpawner.spawn(label, callback, ...)
	---Log task errors.
	---@param error string
	local function onTaskFunctionError(error)
		Logger.trace("onTaskFunctionError - (%s) - %s", label, error)
	end

	-- Wrap callback in profiler and error handling.
	local taskFunction = Profiler.wrap(
		label,
		LPH_NO_VIRTUALIZE(function(...)
			return xpcall(callback, onTaskFunctionError, ...)
		end)
	)

	-- Return reference.
	return task.spawn(taskFunction, ...)
end

-- Return TaskSpawner module.
return TaskSpawner

end)
__bundle_register("Utility/Logger", function(require, _LOADED, __bundle_register, __bundle_modules)
return LPH_NO_VIRTUALIZE(function()
	-- Logger module.
	local Logger = {}
	Logger.__index = Logger

	---@module GUI.Library
	local Library = require("GUI/Library")

	---Build a string with a prefix.
	---@param str string
	---@return string
	local function buildPrefixString(str)
		return string.format("[%s %s] [Lycoris Recode]: %s", os.date("%x"), os.date("%X"), str)
	end

	---Create a manually managed notification.
	---@param str string
	---@return function
	function Logger.mnnotify(str, ...)
		return Library:ManuallyManagedNotify(string.format(str, ...))
	end

	---Notify message with a default short cooldown to create consistent cooldowns between files.
	---@param str string
	function Logger.notify(str, ...)
		Library:Notify(string.format(str, ...), 3.0)
	end

	---Notify message with a default long cooldown to create consistent cooldowns between files.
	---@param str string
	function Logger.longNotify(str, ...)
		Library:Notify(string.format(str, ...), 30.0)
	end

	---Warn message.
	---@param str string
	function Logger.warn(str, ...)
		if shared.Lycoris.silent then
			return
		end

		warn(string.format(buildPrefixString(str), ...))
	end

	---Trace & warn message.
	---@param str string
	function Logger.trace(str, ...)
		if shared.Lycoris.silent then
			return
		end

		Logger.warn(str, ...)
		warn(debug.traceback(2))
	end

	-- Return Logger module.
	return Logger
end)()

end)
__bundle_register("GUI/Library", function(require, _LOADED, __bundle_register, __bundle_modules)
local Profiler = require("Utility/Profiler")
local CoreGuiManager = require("Utility/CoreGuiManager")

return LPH_NO_VIRTUALIZE(function()
	local InputService = game:GetService("UserInputService")
	local TextService = game:GetService("TextService")
	local Teams = game:GetService("Teams")
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local TweenService = game:GetService("TweenService")

	repeat
		task.wait()
	until Players.LocalPlayer

	local RenderStepped = RunService.RenderStepped
	local LocalPlayer = Players.LocalPlayer
	local Mouse = LocalPlayer:GetMouse()

	local ProtectGui = protectgui or (syn and syn.protect_gui) or function() end
	local ScreenGui = CoreGuiManager.imark(Instance.new("ScreenGui"))

	ProtectGui(ScreenGui)

	ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global

	local Toggles = {}
	local Options = {}
	local ColorPickers = {}
	local Entries = {}
	local ContextMenus = {}
	local Tooltips = {}
	local ModeSelectFrames = {}
	local UpdateTimestamp = os.clock()
	local Toggled = false
	local NeedsRefresh = false

	pcall(function()
		getgenv().Toggles = Toggles
		getgenv().Options = Options
	end)

	local Library = {
		Registry = {},
		RegistryMap = {},

		HudRegistry = {},

		FontColor = Color3.fromRGB(255, 255, 255),
		MainColor = Color3.fromRGB(28, 28, 28),
		BackgroundColor = Color3.fromRGB(20, 20, 20),
		AccentColor = Color3.fromRGB(0, 85, 255),
		OutlineColor = Color3.fromRGB(50, 50, 50),
		RiskColor = Color3.fromRGB(255, 50, 50),

		Black = Color3.new(0, 0, 0),
		Font = Font.fromEnum(Enum.Font.RobotoMono),

		OpenedFrames = {},
		DependencyBoxes = {},

		Signals = {},
		ScreenGui = ScreenGui,
	}

	local RainbowStep = 0
	local Hue = 0

	table.insert(
		Library.Signals,
		RenderStepped:Connect(function(Delta)
			if Toggles.ShowLoggerWindow and not Toggles.ShowLoggerWindow.Value then
				Entries = {}
			end

			local NextIndex, NextEntry = next(Entries)

			if NextIndex and NextEntry then
				Entries[NextIndex] = nil
				NextEntry()
			end

			RainbowStep = RainbowStep + Delta

			if RainbowStep >= (1 / 60) then
				RainbowStep = 0

				Hue = Hue + (1 / 400)

				if Hue > 1 then
					Hue = 0
				end

				Library.CurrentRainbowHue = Hue
				Library.CurrentRainbowColor = Color3.fromHSV(Hue, 0.8, 1)

				for _, ColorPicker in next, ColorPickers do
					if ColorPicker.Rainbow then
						ColorPicker:Display()
					end
				end
			end

			local LocalPlayer = game:GetService("Players").LocalPlayer
			local PlayerGui = LocalPlayer and LocalPlayer.PlayerGui
			local CursorGui = PlayerGui and PlayerGui:FindFirstChild("CursorGui")
			local Cursor = CursorGui and CursorGui:FindFirstChild("Cursor")

			if Cursor then
				Cursor.Visible = false
				game:GetService("UserInputService").MouseIconEnabled = true
			end
		end)
	)

	local function GetPlayersString()
		local PlayerList = Players:GetPlayers()

		for i = 1, #PlayerList do
			PlayerList[i] = PlayerList[i].Name
		end

		table.sort(PlayerList, function(str1, str2)
			return str1 < str2
		end)

		return PlayerList
	end

	local function GetTeamsString()
		local TeamList = Teams:GetTeams()

		for i = 1, #TeamList do
			TeamList[i] = TeamList[i].Name
		end

		table.sort(TeamList, function(str1, str2)
			return str1 < str2
		end)

		return TeamList
	end

	function Library:SafeCallback(label, f, ...)
		if not f then
			return
		end

		xpcall(Profiler.wrap(label, f), function(err)
			warn(string.format("Library:SafeCallback - failed on label %s - %s", label, err))
			warn(debug.traceback())
		end, ...)
	end

	function Library:AttemptSave()
		if Library.SaveManager then
			Library.SaveManager:Save()
		end
	end

	function Library:Create(Class, Properties)
		local _Instance = Class

		if type(Class) == "string" then
			_Instance = Instance.new(Class)
		end

		for Property, Value in next, Properties do
			_Instance[Property] = Value
		end

		return _Instance
	end

	function Library:KeyBlacklists()
		local tbl = {}

		for key, val in next, Library.InfoLoggerData.KeyBlacklistList do
			if not val then
				continue
			end

			tbl[#tbl + 1] = key
		end

		return tbl
	end

	function Library:RefreshInfoLogger()
		local CurrentTypeCycle = Library.InfoLoggerCycles[Library.InfoLoggerCycle]
		local Blacklist = Library.InfoLoggerData.KeyBlacklistList

		for Idx, Entry in next, Library.InfoLoggerData.MissingDataEntries do
			if not Blacklist[Entry.Key] then
				continue
			end

			table.remove(Library.InfoLoggerData.MissingDataEntries, Idx)

			pcall(Entry.Label.Destroy, Entry.Label)
		end

		for Idx, Entry in next, Library.InfoLoggerData.MissingDataEntries do
			Entry.Label.Parent = Entry.Type == CurrentTypeCycle and Library.InfoLoggerContainer or nil
			Entry.Label.LayoutOrder = Idx
		end

		Library.InfoLoggerLabel.Text = string.format("Info Logger (%s)", CurrentTypeCycle)

		local YSize = 0
		local XSize = 0

		for _, Entry in next, Library.InfoLoggerData.MissingDataEntries do
			if not Entry.Label.Parent then
				continue
			end

			YSize = YSize + Entry.Label.TextBounds.Y + 2

			if Entry.Label.TextBounds.X <= XSize then
				continue
			end

			XSize = Entry.Label.TextBounds.X
		end

		XSize = XSize + 20
		YSize = YSize + 22

		Library.InfoLoggerFrame.Size = UDim2.new(0, math.clamp(XSize, 210, 800), 0, math.clamp(YSize, 24, 180))
	end

	function Library:AddTelemetryEntry(str, ...)
		local type = "Telemetry"
		local lolll = string.format(str, ...)
		local ts = os.clock()

		local ifd = Library.InfoLoggerData
		local mde = ifd.MissingDataEntries

		table.insert(Entries, 1, function()
			debug.profilebegin("Library:AddTelemetryEntry")

			local function getEntriesForThisType()
				local entries = {}

				for Idx, Entry in next, mde do
					if Entry.Type == type then
						table.insert(entries, { [1] = Entry, [2] = Idx })
					end
				end

				return entries
			end

			-- Pop the last element if we're under 30 entries for this type.
			-- Max of 30 entries per type; in total - 120 for all types.

			local entries = getEntriesForThisType()
			local last = entries[#entries]

			if #entries > 30 and last then
				last[1].Label:Destroy()

				table.remove(mde, last[2])
			end

			-- Create a new label.
			---@type TextLabel
			local label = Library:CreateLabel({
				Text = lolll,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 14),
				LayoutOrder = 1,
				TextSize = 12,
				Visible = true,
				ZIndex = 306,
				Parent = nil,
			}, true)

			Library:AddToRegistry(label, {
				TextColor3 = "FontColor",
			}, true)

			-- entry
			local entry = { Timestamp = ts, Label = label, Key = tostring(math.random()), Type = type }

			-- Copy & blacklist.
			label.InputBegan:Connect(function(Input)
				if Input.KeyCode == Enum.KeyCode.T then
					setclipboard(tostring(entry.Timestamp))
					Library:Notify("Copied timestamp to clipboard.")
				end
			end)

			-- Create a new entry for later destroying.
			table.insert(mde, 1, entry)

			-- Refresh.
			Library:RefreshInfoLogger()

			debug.profileend()
		end)
	end

	function Library:AddKeyFrameEntry(distance, key, name, position, flag)
		local ifd = Library.InfoLoggerData
		local mde = ifd.MissingDataEntries
		local bl = ifd.KeyBlacklistList
		local ts = tick()

		if bl[key] then
			return
		end

		local type = "Keyframe"

		table.insert(Entries, 1, function()
			debug.profilebegin("Library:AddKeyFrameEntry")

			local function getEntriesForThisType()
				local entries = {}

				for Idx, Entry in next, mde do
					if Entry.Type == type then
						table.insert(entries, { [1] = Entry, [2] = Idx })
					end
				end

				return entries
			end

			-- Pop the last element if we're under 30 entries for this type.
			-- Max of 30 entries per type; in total - 120 for all types.

			local entries = getEntriesForThisType()
			local last = entries[#entries]

			if #entries > 30 and last then
				last[1].Label:Destroy()

				table.remove(mde, last[2])
			end

			local SaveManager = require("Game/Timings/SaveManager")
			local asdf = SaveManager.as:index(key)

			-- Create a new label.
			---@type TextLabel
			local label = Library:CreateLabel({
				-- (52.4m away) (HitStart) Animation 'rbxassetid://124453535' reached keyframe at position 0.69.
				Text = string.format(
					"(%.2fm away) %s '%s' %s '%s' at '%.3f' time position.",
					distance,
					asdf and "Timing" or "Animation",
					asdf and PP_SCRAMBLE_STR(asdf.name) or key,
					flag and "will reach" or "reached",
					name,
					position
				),
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 14),
				LayoutOrder = 1,
				TextSize = 12,
				Visible = true,
				ZIndex = 306,
				Parent = nil,
			}, true)

			Library:AddToRegistry(label, {
				TextColor3 = "FontColor",
			}, true)

			-- entry
			local entry = { Timestamp = ts, Label = label, Key = key, Type = type }

			-- Copy & blacklist.
			label.InputBegan:Connect(function(Input)
				if Input.UserInputType == Enum.UserInputType.MouseButton1 then
					setclipboard(key)
					Library:Notify(string.format("Copied key '%s' to clipboard.", key))
				end

				if Input.KeyCode == Enum.KeyCode.T then
					setclipboard(tostring(entry.Timestamp))
					Library:Notify(string.format("Copied timestamp for '%s' to clipboard.", key))
				end

				if Input.UserInputType == Enum.UserInputType.MouseButton2 then
					ifd.KeyBlacklistList[key] = true
					ifd.KeyBlacklistHistory[#ifd.KeyBlacklistHistory + 1] = key
					Library:RefreshInfoLogger()
					if Options and Options.BlacklistedKeys then
						Options.BlacklistedKeys:SetValues(Library:KeyBlacklists())
					end
					Library:Notify(string.format("Blacklisted key '%s' from list.", key))
				end
			end)

			-- Create a new entry for later destroying.
			table.insert(mde, 1, entry)

			-- Refresh.
			Library:RefreshInfoLogger()

			debug.profileend()
		end)
	end

	function Library:AddExistAnimEntry(name, distance, timing)
		local ifd = Library.InfoLoggerData
		local mde = ifd.MissingDataEntries
		local bl = ifd.KeyBlacklistList
		local ts = tick()
		local key = timing.name

		if bl[key] then
			return
		end

		local type = "Existing Anim"

		table.insert(Entries, 1, function()
			debug.profilebegin("Library:AddExistAnimEntry")

			local function getEntriesForThisType()
				local entries = {}

				for Idx, Entry in next, mde do
					if Entry.Type == type then
						table.insert(entries, { [1] = Entry, [2] = Idx })
					end
				end

				return entries
			end

			-- Pop the last element if we're under 30 entries for this type.
			-- Max of 30 entries per type; in total - 120 for all types.

			local entries = getEntriesForThisType()
			local last = entries[#entries]

			if #entries > 30 and last then
				last[1].Label:Destroy()

				table.remove(mde, last[2])
			end

			-- Create a new label.
			---@type TextLabel
			local label = Library:CreateLabel({
				Text = string.format("(%.2fm away) Animation timing '%s' from '%s' was played.", distance, key, name),
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 14),
				LayoutOrder = 1,
				TextSize = 12,
				Visible = true,
				ZIndex = 306,
				Parent = nil,
			}, true)

			Library:AddToRegistry(label, {
				TextColor3 = "FontColor",
			}, true)

			-- entry
			local entry = { Timestamp = ts, Label = label, Key = key, Type = type }

			-- Copy & blacklist.
			label.InputBegan:Connect(function(Input)
				if Input.UserInputType == Enum.UserInputType.MouseButton1 then
					setclipboard(key)
					Library:Notify(string.format("Copied key '%s' to clipboard.", key))
				end

				if Input.KeyCode == Enum.KeyCode.T then
					setclipboard(tostring(entry.Timestamp))
					Library:Notify(string.format("Copied timestamp for '%s' to clipboard.", key))
				end

				if Input.UserInputType == Enum.UserInputType.MouseButton2 then
					ifd.KeyBlacklistList[key] = true
					ifd.KeyBlacklistHistory[#ifd.KeyBlacklistHistory + 1] = key
					Library:RefreshInfoLogger()
					if Options and Options.BlacklistedKeys then
						Options.BlacklistedKeys:SetValues(Library:KeyBlacklists())
					end
					Library:Notify(string.format("Blacklisted key '%s' from list.", key))
				end
			end)

			-- Create a new entry for later destroying.
			table.insert(mde, 1, entry)

			-- Refresh.
			Library:RefreshInfoLogger()

			debug.profileend()
		end)
	end

	function Library:AddMissEntry(type, key, name, distance, parent)
		local ifd = Library.InfoLoggerData
		local mde = ifd.MissingDataEntries
		local bl = ifd.KeyBlacklistList
		local ts = tick()

		if bl[key] then
			return
		end

		table.insert(Entries, 1, function()
			debug.profilebegin("Library:AddMissEntry")

			local function getEntriesForThisType()
				local entries = {}

				for Idx, Entry in next, mde do
					if Entry.Type == type then
						table.insert(entries, { [1] = Entry, [2] = Idx })
					end
				end

				return entries
			end

			-- Pop the last element if we're under 30 entries for this type.
			-- Max of 30 entries per type; in total - 120 for all types.

			local entries = getEntriesForThisType()
			local last = entries[#entries]

			if #entries > 30 and last then
				last[1].Label:Destroy()

				table.remove(mde, last[2])
			end

			local asset = typeof(key) == "string" and tonumber(key:sub(14, 40)) or nil

			-- Create a new label.
			---@type TextLabel
			local label = Library:CreateLabel({
				Text = name and string.format("(%.2fm away) Key '%s' from '%s' is missing.", distance, key, name)
					or string.format("(%.2fm away) Key '%s' is missing.", distance, key),
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 14),
				LayoutOrder = 1,
				TextSize = 12,
				Visible = true,
				ZIndex = 306,
				Parent = nil,
			}, true)

			if parent then
				label.Text = string.format("(%s) %s", parent, label.Text)
			end

			Library:AddToRegistry(label, {
				TextColor3 = "FontColor",
			}, true)

			if asset then
				task.spawn(function()
					pcall(function()
						local lol = game:GetService("MarketplaceService"):GetProductInfo(asset)
						if not lol then
							return
						end

						label.Text = string.format("(%s) %s", lol.Name, label.Text)
					end)
				end)
			end

			-- entry
			local entry = { Timestamp = ts, Label = label, Key = key, Type = type }

			-- Copy & blacklist.
			label.InputBegan:Connect(function(Input)
				if Input.UserInputType == Enum.UserInputType.MouseButton1 then
					setclipboard(key)
					Library:Notify(string.format("Copied key '%s' to clipboard.", key))
				end

				if Input.KeyCode == Enum.KeyCode.T then
					setclipboard(tostring(entry.Timestamp))
					Library:Notify(string.format("Copied timestamp for '%s' to clipboard.", key))
				end

				if Input.UserInputType == Enum.UserInputType.MouseButton2 then
					ifd.KeyBlacklistList[key] = true
					ifd.KeyBlacklistHistory[#ifd.KeyBlacklistHistory + 1] = key
					Library:RefreshInfoLogger()
					if Options and Options.BlacklistedKeys then
						Options.BlacklistedKeys:SetValues(Library:KeyBlacklists())
					end
					Library:Notify(string.format("Blacklisted key '%s' from list.", key))
				end
			end)

			-- Create a new entry for later destroying.
			table.insert(mde, 1, entry)

			-- Refresh.
			Library:RefreshInfoLogger()

			debug.profileend()
		end)
	end

	function Library:ApplyTextStroke(Inst)
		Inst.TextStrokeTransparency = 1

		--[[
		Library:Create("UIStroke", {
			Color = Color3.new(0, 0, 0),
			Thickness = 1,
			LineJoinMode = Enum.LineJoinMode.Miter,
			Parent = Inst,
		})
		]]
		--
	end

	function Library:CreateLabel(Properties, IsHud)
		local _Instance = Library:Create("TextLabel", {
			BackgroundTransparency = 1,
			FontFace = Library.Font,
			TextColor3 = Library.FontColor,
			TextSize = 16,
			TextStrokeTransparency = 0,
		})

		Library:ApplyTextStroke(_Instance)

		Library:AddToRegistry(_Instance, {
			TextColor3 = "FontColor",
		}, IsHud)

		if Properties.TextSize then
			Properties.TextSize = Properties.TextSize + 1
		end

		return Library:Create(_Instance, Properties)
	end

	function Library:MakeDraggable(Instance, Cutoff)
		Instance.Active = true

		Instance.InputBegan:Connect(function(Input)
			if
				Input.UserInputType == Enum.UserInputType.MouseButton1
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				local ObjPos = Vector2.new(Mouse.X - Instance.AbsolutePosition.X, Mouse.Y - Instance.AbsolutePosition.Y)

				if ObjPos.Y > (Cutoff or 40) then
					return
				end

				while
					InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
					or InputService:IsMouseButtonPressed(Enum.UserInputType.Touch)
				do
					Instance.Position = UDim2.new(
						0,
						Mouse.X - ObjPos.X + (Instance.Size.X.Offset * Instance.AnchorPoint.X),
						0,
						Mouse.Y - ObjPos.Y + (Instance.Size.Y.Offset * Instance.AnchorPoint.Y)
					)

					RenderStepped:Wait()
				end
			end
		end)
	end

	function Library:AddToolTip(InfoStr, HoverInstance)
		local X, Y = Library:GetTextBounds(InfoStr, Library.Font, 14)
		local Tooltip = Library:Create("Frame", {
			BackgroundColor3 = Library.MainColor,
			BorderColor3 = Library.OutlineColor,

			Size = UDim2.fromOffset(X + 5, Y + 4),
			ZIndex = 100,
			Parent = Library.ScreenGui,

			Visible = false,
		})

		local Label = Library:CreateLabel({
			Position = UDim2.fromOffset(3, 1),
			Size = UDim2.fromOffset(X, Y),
			TextSize = 14,
			Text = InfoStr,
			TextColor3 = Library.FontColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = Tooltip.ZIndex + 1,

			Parent = Tooltip,
		})

		Library:AddToRegistry(Tooltip, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "OutlineColor",
		})

		Library:AddToRegistry(Label, {
			TextColor3 = "FontColor",
		})

		Tooltips[#Tooltips + 1] = Tooltip

		local IsHovering = false

		HoverInstance.MouseEnter:Connect(function()
			if Library:MouseIsOverOpenedFrame() then
				return
			end

			IsHovering = true

			Tooltip.Position = UDim2.fromOffset(Mouse.X + 15, Mouse.Y + 12)
			Tooltip.Visible = true

			while IsHovering do
				RunService.Heartbeat:Wait()
				Tooltip.Position = UDim2.fromOffset(Mouse.X + 15, Mouse.Y + 12)
			end
		end)

		HoverInstance.MouseLeave:Connect(function()
			IsHovering = false
			Tooltip.Visible = false
		end)
	end

	function Library:OnHighlight(HighlightInstance, Instance, Properties, PropertiesDefault)
		HighlightInstance.MouseEnter:Connect(function()
			local Reg = Library.RegistryMap[Instance]

			for Property, ColorIdx in next, Properties do
				Instance[Property] = Library[ColorIdx] or ColorIdx

				if Reg and Reg.Properties[Property] then
					Reg.Properties[Property] = ColorIdx
				end
			end
		end)

		HighlightInstance.MouseLeave:Connect(function()
			local Reg = Library.RegistryMap[Instance]

			for Property, ColorIdx in next, PropertiesDefault do
				Instance[Property] = Library[ColorIdx] or ColorIdx

				if Reg and Reg.Properties[Property] then
					Reg.Properties[Property] = ColorIdx
				end
			end
		end)
	end

	function Library:MouseIsOverOpenedFrame()
		for Frame, _ in next, Library.OpenedFrames do
			local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize

			if
				Mouse.X >= AbsPos.X
				and Mouse.X <= AbsPos.X + AbsSize.X
				and Mouse.Y >= AbsPos.Y
				and Mouse.Y <= AbsPos.Y + AbsSize.Y
			then
				return true
			end
		end
	end

	function Library:IsMouseOverFrame(Frame)
		local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize

		if
			Mouse.X >= AbsPos.X
			and Mouse.X <= AbsPos.X + AbsSize.X
			and Mouse.Y >= AbsPos.Y
			and Mouse.Y <= AbsPos.Y + AbsSize.Y
		then
			return true
		end
	end

	function Library:UpdateDependencyBoxes()
		for _, Depbox in next, Library.DependencyBoxes do
			Depbox:Update()
		end
	end

	function Library:MapValue(Value, MinA, MaxA, MinB, MaxB)
		return (1 - ((Value - MinA) / (MaxA - MinA))) * MinB + ((Value - MinA) / (MaxA - MinA)) * MaxB
	end

	function Library:GetTextBounds(Text, Font, Size, Resolution)
		local Bounds = TextService:GetTextSize(Text, Size, "RobotoMono", Resolution or Vector2.new(1920, 1080))
		return Bounds.X, Bounds.Y
	end

	function Library:GetDarkerColor(Color)
		local H, S, V = Color3.toHSV(Color)
		return Color3.fromHSV(H, S, V / 1.5)
	end
	Library.AccentColorDark = Library:GetDarkerColor(Library.AccentColor)

	function Library:AddToRegistry(Instance, Properties, IsHud)
		local Idx = #Library.Registry + 1
		local Data = {
			Instance = Instance,
			Properties = Properties,
			Idx = Idx,
		}

		table.insert(Library.Registry, Data)
		Library.RegistryMap[Instance] = Data

		if IsHud then
			table.insert(Library.HudRegistry, Data)
		end
	end

	function Library:RemoveFromRegistry(Instance)
		local Data = Library.RegistryMap[Instance]

		if Data then
			for Idx = #Library.Registry, 1, -1 do
				if Library.Registry[Idx] == Data then
					table.remove(Library.Registry, Idx)
				end
			end

			for Idx = #Library.HudRegistry, 1, -1 do
				if Library.HudRegistry[Idx] == Data then
					table.remove(Library.HudRegistry, Idx)
				end
			end

			Library.RegistryMap[Instance] = nil
		end
	end

	function Library:UpdateColorsUsingRegistry()
		-- TODO: Could have an 'active' list of objects
		-- where the active list only contains Visible objects.

		-- IMPL: Could setup .Changed events on the AddToRegistry function
		-- that listens for the 'Visible' propert being changed.
		-- Visible: true => Add to active list, and call UpdateColors function
		-- Visible: false => Remove from active list.

		-- The above would be especially efficient for a rainbow menu color or live color-changing.

		for Idx, Object in next, Library.Registry do
			for Property, ColorIdx in next, Object.Properties do
				if type(ColorIdx) == "string" then
					Object.Instance[Property] = Library[ColorIdx]
				elseif type(ColorIdx) == "function" then
					Object.Instance[Property] = ColorIdx()
				end
			end
		end
	end

	function Library:GiveSignal(Signal)
		-- Only used for signals not attached to library instances, as those should be cleaned up on object destruction by Roblox
		table.insert(Library.Signals, Signal)
	end

	function Library:Unload()
		-- Unload all of the signals
		for Idx = #Library.Signals, 1, -1 do
			local Connection = table.remove(Library.Signals, Idx)
			Connection:Disconnect()
		end

		-- Call our unload callback, maybe to undo some hooks etc
		if Library.OnUnload then
			Library.OnUnload()
		end

		ScreenGui:Destroy()
	end

	function Library:OnUnload(Callback)
		Library.OnUnload = Callback
	end

	Library:GiveSignal(ScreenGui.DescendantRemoving:Connect(function(Instance)
		if Library.RegistryMap[Instance] then
			Library:RemoveFromRegistry(Instance)
		end
	end))

	local BaseAddons = {}

	do
		local Funcs = {}

		function Funcs:AddColorPicker(Idx, Info)
			local ToggleLabel = self.TextLabel
			-- local Container = self.Container;

			assert(Info.Default, "AddColorPicker: Missing default value.")

			local ColorPicker = {
				Value = Info.Default,
				Transparency = Info.Transparency or 0,
				Type = "ColorPicker",
				Title = type(Info.Title) == "string" and Info.Title or "Color picker",
				Callback = Info.Callback or function(Color) end,
				Rainbow = Info.Rainbow or false,
			}

			function ColorPicker:SetHSVFromRGB(Color)
				local H, S, V = Color3.toHSV(Color)

				ColorPicker.Hue = H
				ColorPicker.Sat = S
				ColorPicker.Vib = V
			end

			ColorPicker:SetHSVFromRGB(ColorPicker.Value)

			local DisplayFrame = Library:Create("Frame", {
				BackgroundColor3 = ColorPicker.Value,
				BorderColor3 = Library:GetDarkerColor(ColorPicker.Value),
				BorderMode = Enum.BorderMode.Inset,
				Size = UDim2.new(0, 28, 0, 14),
				ZIndex = 6,
				Parent = ToggleLabel,
			})

			-- Transparency image taken from https://github.com/matas3535/SplixPrivateDrawingLibrary/blob/main/Library.lua cus i'm lazy
			local CheckerFrame = Library:Create("ImageLabel", {
				BorderSizePixel = 0,
				Size = UDim2.new(0, 27, 0, 13),
				ZIndex = 5,
				Image = "http://www.roblox.com/asset/?id=12977615774",
				Visible = not not Info.Transparency,
				Parent = DisplayFrame,
			})

			-- 1/16/23
			-- Rewrote this to be placed inside the Library ScreenGui
			-- There was some issue which caused RelativeOffset to be way off
			-- Thus the color picker would never show

			local PickerFrameOuter = Library:Create("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderColor3 = Color3.new(0, 0, 0),
				Position = UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 18),
				Size = UDim2.fromOffset(230, Info.Transparency and 271 or 253),
				Visible = false,
				ZIndex = 15,
				Parent = ScreenGui,
			})

			DisplayFrame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
				PickerFrameOuter.Position =
					UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 18)
			end)

			local PickerFrameInner = Library:Create("Frame", {
				BackgroundColor3 = Library.BackgroundColor,
				BorderColor3 = Library.OutlineColor,
				BorderMode = Enum.BorderMode.Inset,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 16,
				Parent = PickerFrameOuter,
			})

			local Highlight = Library:Create("Frame", {
				BackgroundColor3 = Library.AccentColor,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 2),
				ZIndex = 17,
				Parent = PickerFrameInner,
			})

			local SatVibMapOuter = Library:Create("Frame", {
				BorderColor3 = Color3.new(0, 0, 0),
				Position = UDim2.new(0, 4, 0, 25),
				Size = UDim2.new(0, 200, 0, 200),
				ZIndex = 17,
				Parent = PickerFrameInner,
			})

			local SatVibMapInner = Library:Create("Frame", {
				BackgroundColor3 = Library.BackgroundColor,
				BorderColor3 = Library.OutlineColor,
				BorderMode = Enum.BorderMode.Inset,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 18,
				Parent = SatVibMapOuter,
			})

			local SatVibMap = Library:Create("ImageLabel", {
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 18,
				Image = "rbxassetid://4155801252",
				Parent = SatVibMapInner,
			})

			local CursorOuter = Library:Create("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.new(0, 6, 0, 6),
				BackgroundTransparency = 1,
				Image = "http://www.roblox.com/asset/?id=9619665977",
				ImageColor3 = Color3.new(0, 0, 0),
				ZIndex = 19,
				Parent = SatVibMap,
			})

			local CursorInner = Library:Create("ImageLabel", {
				Size = UDim2.new(0, CursorOuter.Size.X.Offset - 2, 0, CursorOuter.Size.Y.Offset - 2),
				Position = UDim2.new(0, 1, 0, 1),
				BackgroundTransparency = 1,
				Image = "http://www.roblox.com/asset/?id=9619665977",
				ZIndex = 20,
				Parent = CursorOuter,
			})

			local HueSelectorOuter = Library:Create("Frame", {
				BorderColor3 = Color3.new(0, 0, 0),
				Position = UDim2.new(0, 208, 0, 25),
				Size = UDim2.new(0, 15, 0, 200),
				ZIndex = 17,
				Parent = PickerFrameInner,
			})

			local HueSelectorInner = Library:Create("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 18,
				Parent = HueSelectorOuter,
			})

			local HueCursor = Library:Create("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				AnchorPoint = Vector2.new(0, 0.5),
				BorderColor3 = Color3.new(0, 0, 0),
				Size = UDim2.new(1, 0, 0, 1),
				ZIndex = 18,
				Parent = HueSelectorInner,
			})

			local HueBoxOuter = Library:Create("Frame", {
				BorderColor3 = Color3.new(0, 0, 0),
				Position = UDim2.fromOffset(4, 228),
				Size = UDim2.new(0.5, -6, 0, 20),
				ZIndex = 18,
				Parent = PickerFrameInner,
			})

			local HueBoxInner = Library:Create("Frame", {
				BackgroundColor3 = Library.MainColor,
				BorderColor3 = Library.OutlineColor,
				BorderMode = Enum.BorderMode.Inset,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 18,
				Parent = HueBoxOuter,
			})

			Library:Create("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212)),
				}),
				Rotation = 90,
				Parent = HueBoxInner,
			})

			local HueBox = Library:Create("TextBox", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 5, 0, 0),
				Size = UDim2.new(1, -5, 1, 0),
				FontFace = Library.Font,
				PlaceholderColor3 = Color3.fromRGB(190, 190, 190),
				PlaceholderText = "Hex color",
				Text = "#FFFFFF",
				TextColor3 = Library.FontColor,
				TextSize = 14,
				TextStrokeTransparency = 0,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 20,
				Parent = HueBoxInner,
			})

			Library:ApplyTextStroke(HueBox)

			local RgbBoxBase = Library:Create(HueBoxOuter:Clone(), {
				Position = UDim2.new(0.5, 2, 0, 228),
				Size = UDim2.new(0.5, -6, 0, 20),
				Parent = PickerFrameInner,
			})

			local RgbBox = Library:Create(RgbBoxBase.Frame:FindFirstChild("TextBox"), {
				Text = "255, 255, 255",
				PlaceholderText = "RGB color",
				TextColor3 = Library.FontColor,
			})

			local TransparencyBoxOuter, TransparencyBoxInner, TransparencyCursor

			if Info.Transparency then
				TransparencyBoxOuter = Library:Create("Frame", {
					BorderColor3 = Color3.new(0, 0, 0),
					Position = UDim2.fromOffset(4, 251),
					Size = UDim2.new(1, -8, 0, 15),
					ZIndex = 19,
					Parent = PickerFrameInner,
				})

				TransparencyBoxInner = Library:Create("Frame", {
					BackgroundColor3 = ColorPicker.Value,
					BorderColor3 = Library.OutlineColor,
					BorderMode = Enum.BorderMode.Inset,
					Size = UDim2.new(1, 0, 1, 0),
					ZIndex = 19,
					Parent = TransparencyBoxOuter,
				})

				Library:AddToRegistry(TransparencyBoxInner, { BorderColor3 = "OutlineColor" })

				Library:Create("ImageLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					Image = "http://www.roblox.com/asset/?id=12978095818",
					ZIndex = 20,
					Parent = TransparencyBoxInner,
				})

				TransparencyCursor = Library:Create("Frame", {
					BackgroundColor3 = Color3.new(1, 1, 1),
					AnchorPoint = Vector2.new(0.5, 0),
					BorderColor3 = Color3.new(0, 0, 0),
					Size = UDim2.new(0, 1, 1, 0),
					ZIndex = 21,
					Parent = TransparencyBoxInner,
				})
			end

			local DisplayLabel = Library:CreateLabel({
				Size = UDim2.new(1, 0, 0, 14),
				Position = UDim2.fromOffset(5, 5),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = 14,
				Text = ColorPicker.Title, --Info.Default;
				TextWrapped = false,
				ZIndex = 16,
				Parent = PickerFrameInner,
			})

			local ContextMenu = {}
			do
				ContextMenu.Options = {}
				ContextMenu.Container = Library:Create("Frame", {
					BorderColor3 = Color3.new(),
					ZIndex = 14,
					Visible = false,
					Parent = ScreenGui,
				})

				ContextMenu.Inner = Library:Create("Frame", {
					BackgroundColor3 = Library.BackgroundColor,
					BorderColor3 = Library.OutlineColor,
					BorderMode = Enum.BorderMode.Inset,
					Size = UDim2.fromScale(1, 1),
					ZIndex = 15,
					Parent = ContextMenu.Container,
				})

				ContextMenus[#ContextMenus + 1] = ContextMenu

				Library:Create("UIListLayout", {
					Name = "Layout",
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Parent = ContextMenu.Inner,
				})

				Library:Create("UIPadding", {
					Name = "Padding",
					PaddingLeft = UDim.new(0, 4),
					Parent = ContextMenu.Inner,
				})

				local function updateMenuPosition()
					ContextMenu.Container.Position = UDim2.fromOffset(
						(DisplayFrame.AbsolutePosition.X + DisplayFrame.AbsoluteSize.X) + 4,
						DisplayFrame.AbsolutePosition.Y + 1
					)
				end

				local function updateMenuSize()
					local menuWidth = 60
					for i, label in next, ContextMenu.Inner:GetChildren() do
						if label:IsA("TextLabel") then
							menuWidth = math.max(menuWidth, label.TextBounds.X)
						end
					end

					ContextMenu.Container.Size =
						UDim2.fromOffset(menuWidth + 8, ContextMenu.Inner.Layout.AbsoluteContentSize.Y + 4)
				end

				DisplayFrame:GetPropertyChangedSignal("AbsolutePosition"):Connect(updateMenuPosition)
				ContextMenu.Inner.Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateMenuSize)

				task.spawn(updateMenuPosition)
				task.spawn(updateMenuSize)

				Library:AddToRegistry(ContextMenu.Inner, {
					BackgroundColor3 = "BackgroundColor",
					BorderColor3 = "OutlineColor",
				})

				function ContextMenu:Show()
					self.Container.Visible = true
				end

				function ContextMenu:Hide()
					self.Container.Visible = false
				end

				function ContextMenu:AddOption(Str, Callback)
					if type(Callback) ~= "function" then
						Callback = function() end
					end

					local Button = Library:CreateLabel({
						Active = false,
						Size = UDim2.new(1, 0, 0, 15),
						TextSize = 13,
						Text = Str,
						ZIndex = 16,
						Parent = self.Inner,
						TextXAlignment = Enum.TextXAlignment.Left,
					})

					Library:OnHighlight(Button, Button, { TextColor3 = "AccentColor" }, { TextColor3 = "FontColor" })

					Button.InputBegan:Connect(function(Input)
						if
							Input.UserInputType ~= Enum.UserInputType.Touch
							and Input.UserInputType ~= Enum.UserInputType.MouseButton1
						then
							return
						end

						Callback()
					end)
				end

				ContextMenu:AddOption("Rainbow toggle", function()
					ColorPicker.Rainbow = not ColorPicker.Rainbow
					ColorPicker:Display()
				end)

				ContextMenu:AddOption("Copy color", function()
					Library.ColorClipboard = ColorPicker.Value
					Library:Notify("Copied color!", 2)
				end)

				ContextMenu:AddOption("Paste color", function()
					if not Library.ColorClipboard then
						return Library:Notify("You have not copied a color!", 2)
					end
					ColorPicker:SetValueRGB(Library.ColorClipboard)
				end)

				ContextMenu:AddOption("Copy HEX", function()
					pcall(setclipboard, ColorPicker.Value:ToHex())
					Library:Notify("Copied hex code to clipboard!", 2)
				end)

				ContextMenu:AddOption("Copy RGB", function()
					pcall(
						setclipboard,
						table.concat({
							math.floor(ColorPicker.Value.R * 255),
							math.floor(ColorPicker.Value.G * 255),
							math.floor(ColorPicker.Value.B * 255),
						}, ", ")
					)
					Library:Notify("Copied RGB values to clipboard!", 2)
				end)
			end

			Library:AddToRegistry(
				PickerFrameInner,
				{ BackgroundColor3 = "BackgroundColor", BorderColor3 = "OutlineColor" }
			)
			Library:AddToRegistry(Highlight, { BackgroundColor3 = "AccentColor" })
			Library:AddToRegistry(
				SatVibMapInner,
				{ BackgroundColor3 = "BackgroundColor", BorderColor3 = "OutlineColor" }
			)

			Library:AddToRegistry(HueBoxInner, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" })
			Library:AddToRegistry(RgbBoxBase.Frame, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" })
			Library:AddToRegistry(RgbBox, { TextColor3 = "FontColor" })
			Library:AddToRegistry(HueBox, { TextColor3 = "FontColor" })

			local SequenceTable = {}

			for Hue = 0, 1, 0.1 do
				table.insert(SequenceTable, ColorSequenceKeypoint.new(Hue, Color3.fromHSV(Hue, 1, 1)))
			end

			local HueSelectorGradient = Library:Create("UIGradient", {
				Color = ColorSequence.new(SequenceTable),
				Rotation = 90,
				Parent = HueSelectorInner,
			})

			HueBox.FocusLost:Connect(function(enter)
				if enter then
					local success, result = pcall(Color3.fromHex, HueBox.Text)
					if success and typeof(result) == "Color3" then
						ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(result)
					end
				end

				ColorPicker:Display()
			end)

			RgbBox.FocusLost:Connect(function(enter)
				if enter then
					local r, g, b = RgbBox.Text:match("(%d+),%s*(%d+),%s*(%d+)")
					if r and g and b then
						ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(Color3.fromRGB(r, g, b))
					end
				end

				ColorPicker:Display()
			end)

			function ColorPicker:Display()
				ColorPicker.Value = Color3.fromHSV(ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib)
				SatVibMap.BackgroundColor3 = Color3.fromHSV(ColorPicker.Hue, 1, 1)

				if ColorPicker.Rainbow then
					ColorPicker.Value = Library.CurrentRainbowColor
				end

				Library:Create(DisplayFrame, {
					BackgroundColor3 = ColorPicker.Value,
					BackgroundTransparency = ColorPicker.Transparency,
					BorderColor3 = Library:GetDarkerColor(ColorPicker.Value),
				})

				if TransparencyBoxInner then
					TransparencyBoxInner.BackgroundColor3 = ColorPicker.Value
					TransparencyCursor.Position = UDim2.new(1 - ColorPicker.Transparency, 0, 0, 0)
				end

				CursorOuter.Position = UDim2.new(ColorPicker.Sat, 0, 1 - ColorPicker.Vib, 0)
				HueCursor.Position = UDim2.new(0, 0, ColorPicker.Hue, 0)

				HueBox.Text = "#" .. ColorPicker.Value:ToHex()
				RgbBox.Text = table.concat({
					math.floor(ColorPicker.Value.R * 255),
					math.floor(ColorPicker.Value.G * 255),
					math.floor(ColorPicker.Value.B * 255),
				}, ", ")

				Library:SafeCallback(
					"ColorPicker_Callback" .. "_" .. (Idx or ""),
					ColorPicker.Callback,
					ColorPicker.Value
				)
				Library:SafeCallback(
					"ColorPicker_Changed" .. "_" .. (Idx or ""),
					ColorPicker.Changed,
					ColorPicker.Value
				)
			end

			function ColorPicker:OnChanged(Func)
				ColorPicker.Changed = Func
				Func(ColorPicker.Value)
			end

			function ColorPicker:Show()
				for Frame, Val in next, Library.OpenedFrames do
					if Frame.Name == "Color" then
						Frame.Visible = false
						Library.OpenedFrames[Frame] = nil
					end
				end

				PickerFrameOuter.Visible = true
				Library.OpenedFrames[PickerFrameOuter] = true
			end

			function ColorPicker:Hide()
				PickerFrameOuter.Visible = false
				Library.OpenedFrames[PickerFrameOuter] = nil
			end

			function ColorPicker:SetValue(HSV, Transparency)
				local Color = Color3.fromHSV(HSV[1], HSV[2], HSV[3])

				ColorPicker.Transparency = Transparency or 0
				ColorPicker:SetHSVFromRGB(Color)
				ColorPicker:Display()
			end

			function ColorPicker:SetValueRGB(Color, Transparency)
				ColorPicker.Transparency = Transparency or 0
				ColorPicker:SetHSVFromRGB(Color)
				ColorPicker:Display()
			end

			SatVibMap.InputBegan:Connect(function(Input)
				if
					Input.UserInputType == Enum.UserInputType.Touch
					or Input.UserInputType == Enum.UserInputType.MouseButton1
				then
					while
						InputService:IsMouseButtonPressed(Enum.UserInputType.Touch)
						or InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
					do
						local MinX = SatVibMap.AbsolutePosition.X
						local MaxX = MinX + SatVibMap.AbsoluteSize.X
						local MouseX = math.clamp(Mouse.X, MinX, MaxX)

						local MinY = SatVibMap.AbsolutePosition.Y
						local MaxY = MinY + SatVibMap.AbsoluteSize.Y
						local MouseY = math.clamp(Mouse.Y, MinY, MaxY)

						ColorPicker.Sat = (MouseX - MinX) / (MaxX - MinX)
						ColorPicker.Vib = 1 - ((MouseY - MinY) / (MaxY - MinY))
						ColorPicker:Display()

						RenderStepped:Wait()
					end

					Library:AttemptSave()
				end
			end)

			HueSelectorInner.InputBegan:Connect(function(Input)
				if
					Input.UserInputType == Enum.UserInputType.Touch
					or Input.UserInputType == Enum.UserInputType.MouseButton1
				then
					while
						InputService:IsMouseButtonPressed(Enum.UserInputType.Touch)
						or InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
					do
						local MinY = HueSelectorInner.AbsolutePosition.Y
						local MaxY = MinY + HueSelectorInner.AbsoluteSize.Y
						local MouseY = math.clamp(Mouse.Y, MinY, MaxY)

						ColorPicker.Hue = ((MouseY - MinY) / (MaxY - MinY))
						ColorPicker:Display()

						RenderStepped:Wait()
					end

					Library:AttemptSave()
				end
			end)

			DisplayFrame.InputBegan:Connect(function(Input)
				if
					(
						Input.UserInputType == Enum.UserInputType.Touch
						or Input.UserInputType == Enum.UserInputType.MouseButton1
					) and not Library:MouseIsOverOpenedFrame()
				then
					if PickerFrameOuter.Visible then
						ColorPicker:Hide()
					else
						ContextMenu:Hide()
						ColorPicker:Show()
					end
				elseif
					(
						Input.UserInputType == Enum.UserInputType.Touch
						or Input.UserInputType == Enum.UserInputType.MouseButton1
					) and not Library:MouseIsOverOpenedFrame()
				then
					ContextMenu:Show()
					ColorPicker:Hide()
				end
			end)

			if TransparencyBoxInner then
				TransparencyBoxInner.InputBegan:Connect(function(Input)
					if
						Input.UserInputType == Enum.UserInputType.Touch
						or Input.UserInputType == Enum.UserInputType.MouseButton1
					then
						while
							InputService:IsMouseButtonPressed(Enum.UserInputType.Touch)
							or InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
						do
							local MinX = TransparencyBoxInner.AbsolutePosition.X
							local MaxX = MinX + TransparencyBoxInner.AbsoluteSize.X
							local MouseX = math.clamp(Mouse.X, MinX, MaxX)

							ColorPicker.Transparency = 1 - ((MouseX - MinX) / (MaxX - MinX))

							ColorPicker:Display()

							RenderStepped:Wait()
						end

						Library:AttemptSave()
					end
				end)
			end

			Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
				if Input.UserInputType == Enum.UserInputType.MouseButton1 then
					local AbsPos, AbsSize = PickerFrameOuter.AbsolutePosition, PickerFrameOuter.AbsoluteSize

					if
						Mouse.X < AbsPos.X
						or Mouse.X > AbsPos.X + AbsSize.X
						or Mouse.Y < (AbsPos.Y - 20 - 1)
						or Mouse.Y > AbsPos.Y + AbsSize.Y
					then
						ColorPicker:Hide()
					end

					if not Library:IsMouseOverFrame(ContextMenu.Container) then
						ContextMenu:Hide()
					end
				end

				if Input.UserInputType == Enum.UserInputType.MouseButton2 and ContextMenu.Container.Visible then
					if
						not Library:IsMouseOverFrame(ContextMenu.Container)
						and not Library:IsMouseOverFrame(DisplayFrame)
					then
						ContextMenu:Hide()
					end
				end
			end))

			ColorPicker:Display()
			ColorPicker.DisplayFrame = DisplayFrame

			if Idx then
				Options[Idx] = ColorPicker
				ColorPickers[Idx] = ColorPicker
			end

			return self
		end

		function Funcs:AddKeyPicker(Idx, Info)
			local ParentObj = self
			local ToggleLabel = self.TextLabel
			local Container = self.Container

			assert(Info.Default, "AddKeyPicker: Missing default value.")

			local KeyPicker = {
				Value = Info.Default,
				Toggled = false,
				Mode = Info.Mode or "Toggle", -- Always, Toggle, Hold
				Type = "KeyPicker",
				Callback = Info.Callback or function(Value) end,
				ChangedCallback = Info.ChangedCallback or function(New) end,
				SyncToggleState = Info.SyncToggleState or false,
			}

			if KeyPicker.SyncToggleState then
				Info.Modes = { "Toggle", "Hold" }
				Info.Mode = "Toggle"
			end

			local PickOuter = Library:Create("Frame", {
				BackgroundColor3 = Color3.new(0, 0, 0),
				BorderColor3 = Color3.new(0, 0, 0),
				Size = UDim2.new(0, 28, 0, 15),
				ZIndex = 6,
				Parent = ToggleLabel,
			})

			local PickInner = Library:Create("Frame", {
				BackgroundColor3 = Library.BackgroundColor,
				BorderColor3 = Library.OutlineColor,
				BorderMode = Enum.BorderMode.Inset,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 7,
				Parent = PickOuter,
			})

			Library:AddToRegistry(PickInner, {
				BackgroundColor3 = "BackgroundColor",
				BorderColor3 = "OutlineColor",
			})

			local DisplayLabel = Library:CreateLabel({
				Size = UDim2.new(1, 0, 1, 0),
				TextSize = 13,
				Text = Info.Default,
				TextWrapped = true,
				ZIndex = 8,
				Parent = PickInner,
			})

			local ModeSelectOuter = Library:Create("Frame", {
				BorderColor3 = Color3.new(0, 0, 0),
				Position = UDim2.fromOffset(
					ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 4,
					ToggleLabel.AbsolutePosition.Y + 1
				),
				Size = UDim2.new(0, 60, 0, 60 + 2),
				Visible = false,
				ZIndex = 14,
				Parent = ScreenGui,
			})

			ModeSelectFrames[#ModeSelectFrames + 1] = ModeSelectOuter

			ToggleLabel:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
				ModeSelectOuter.Position = UDim2.fromOffset(
					ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 4,
					ToggleLabel.AbsolutePosition.Y + 1
				)
			end)

			local ModeSelectInner = Library:Create("Frame", {
				BackgroundColor3 = Library.BackgroundColor,
				BorderColor3 = Library.OutlineColor,
				BorderMode = Enum.BorderMode.Inset,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 15,
				Parent = ModeSelectOuter,
			})

			Library:AddToRegistry(ModeSelectInner, {
				BackgroundColor3 = "BackgroundColor",
				BorderColor3 = "OutlineColor",
			})

			Library:Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = ModeSelectInner,
			})

			local ContainerLabel = Library:CreateLabel({
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 18),
				TextSize = 13,
				Visible = false,
				ZIndex = 110,
				Parent = Library.KeybindContainer,
			}, true)

			local Modes = Info.Modes or { "Always", "Toggle", "Hold", "Off" }
			local ModeButtons = {}

			function KeyPicker:DoClick()
				if KeyPicker.Mode == "Toggle" and ParentObj.Type == "Toggle" and KeyPicker.SyncToggleState then
					ParentObj:SetValue(not ParentObj.Value)
				end

				if KeyPicker.Mode == "Hold" and ParentObj.Type == "Toggle" and KeyPicker.SyncToggleState then
					ParentObj:SetValue(KeyPicker.Toggled)
				end

				Library:SafeCallback("KeyPicker_Callback" .. "_" .. (Idx or ""), KeyPicker.Callback, KeyPicker.Toggled)
				Library:SafeCallback("KeyPicker_Clicked" .. "_" .. (Idx or ""), KeyPicker.Clicked, KeyPicker.Toggled)
			end

			for Idx, Mode in next, Modes do
				local ModeButton = {}

				local Label = Library:CreateLabel({
					Active = false,
					Size = UDim2.new(1, 0, 0, 15),
					TextSize = 13,
					Text = Mode,
					ZIndex = 16,
					Parent = ModeSelectInner,
				})

				function ModeButton:Select()
					for _, Button in next, ModeButtons do
						Button:Deselect()
					end

					if Mode == "Always" then
						KeyPicker.Toggled = true
						KeyPicker:DoClick()
					end

					if Mode == "Off" then
						KeyPicker.Toggled = false
						KeyPicker:DoClick()
					end

					KeyPicker.Mode = Mode

					Label.TextColor3 = Library.AccentColor
					Library.RegistryMap[Label].Properties.TextColor3 = "AccentColor"

					ModeSelectOuter.Visible = false
				end

				function ModeButton:Deselect()
					KeyPicker.Mode = nil

					Label.TextColor3 = Library.FontColor
					Library.RegistryMap[Label].Properties.TextColor3 = "FontColor"
				end

				Label.InputBegan:Connect(function(Input)
					if Input.UserInputType == Enum.UserInputType.MouseButton1 then
						ModeButton:Select()
						Library:AttemptSave()
					end
				end)

				if Mode == KeyPicker.Mode then
					ModeButton:Select()
				end

				ModeButtons[Mode] = ModeButton
			end

			function KeyPicker:Update()
				if Info.NoUI then
					return
				end

				local State = KeyPicker:GetState()

				ContainerLabel.Text = string.format("[%s] %s (%s)", KeyPicker.Value, Info.Text, KeyPicker.Mode)

				ContainerLabel.Visible = true
				ContainerLabel.TextColor3 = State and Library.AccentColor or Library.FontColor

				Library.RegistryMap[ContainerLabel].Properties.TextColor3 = State and "AccentColor" or "FontColor"

				local YSize = 0
				local XSize = 0

				for _, Label in next, Library.KeybindContainer:GetChildren() do
					if Label:IsA("TextLabel") and Label.Visible then
						YSize = YSize + 18
						if Label.TextBounds.X > XSize then
							XSize = Label.TextBounds.X
						end
					end
				end

				Library.KeybindFrame.Size = UDim2.new(0, math.max(XSize + 10, 210), 0, YSize + 23)
			end

			function KeyPicker:GetState()
				if KeyPicker.Mode == "Always" then
					return true
				elseif KeyPicker.Mode == "Off" then
					return false
				elseif KeyPicker.Mode == "Hold" then
					if KeyPicker.Value == "N/A" then
						return false
					end

					local Key = KeyPicker.Value

					if Key == "MB1" then
						return InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
							or InputService.TouchEnabled and #InputService.Touches > 0
					elseif Key == "MB2" then
						return InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
							or InputService.TouchEnabled and #InputService.Touches > 1
					else
						return InputService:IsKeyDown(Enum.KeyCode[KeyPicker.Value])
					end
				else
					return KeyPicker.Toggled
				end
			end

			function KeyPicker:SetValue(Data)
				local Key, Mode = Data[1], Data[2]
				DisplayLabel.Text = Key
				KeyPicker.Value = Key
				ModeButtons[Mode]:Select()
				KeyPicker:Update()
			end

			function KeyPicker:OnClick(Callback)
				KeyPicker.Clicked = Callback
			end

			function KeyPicker:OnChanged(Callback)
				KeyPicker.Changed = Callback
				Callback(KeyPicker.Value)
			end

			if ParentObj.Addons then
				table.insert(ParentObj.Addons, KeyPicker)
			end

			local Picking = false

			PickOuter.InputBegan:Connect(function(Input)
				if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
					Picking = true

					DisplayLabel.Text = ""

					local Break
					local Text = ""

					task.spawn(function()
						while not Break do
							if Text == "..." then
								Text = ""
							end

							Text = Text .. "."
							DisplayLabel.Text = Text

							wait(0.4)
						end
					end)

					wait(0.2)

					local Event
					Event = InputService.InputBegan:Connect(function(Input)
						local Key

						if
							Input.UserInputType == Enum.UserInputType.Keyboard
							or Input.UserInputType == Enum.UserInputType.Touch
						then
							Key = Input.KeyCode.Name
						elseif Input.UserInputType == Enum.UserInputType.MouseButton1 then
							Key = "MB1"
						elseif Input.UserInputType == Enum.UserInputType.MouseButton2 then
							Key = "MB2"
						end

						if Input.KeyCode == Enum.KeyCode.Escape or Input.KeyCode == Enum.KeyCode.Backspace then
							Key = "N/A"
						end

						Break = true
						Picking = false

						DisplayLabel.Text = Key
						KeyPicker.Value = Key

						Library:SafeCallback(
							"KeyPicker_ChangedCallback" .. "_" .. (Idx or ""),
							KeyPicker.ChangedCallback,
							Input.KeyCode or Input.UserInputType
						)

						Library:SafeCallback(
							"KeyPicker_Changed" .. "_" .. (Idx or ""),
							KeyPicker.Changed,
							Input.KeyCode or Input.UserInputType
						)

						Library:AttemptSave()

						Event:Disconnect()
					end)
				elseif
					Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame()
				then
					ModeSelectOuter.Visible = true
				end
			end)

			Library:GiveSignal(InputService.InputBegan:Connect(function(Input, ProcessedByGame)
				local textChatService = game:GetService("TextChatService")
				local userInputService = game:GetService("UserInputService")
				local chatInputBarConfiguration = textChatService:FindFirstChildOfClass("ChatInputBarConfiguration")

				if userInputService:GetFocusedTextBox() or chatInputBarConfiguration.IsFocused then
					return
				end

				if not Picking then
					if KeyPicker.Mode == "Toggle" then
						local Key = KeyPicker.Value

						if Key == "MB1" or Key == "MB2" then
							if
								Key == "MB1" and Input.UserInputType == Enum.UserInputType.MouseButton1
								or Key == "MB2" and Input.UserInputType == Enum.UserInputType.MouseButton2
							then
								KeyPicker.Toggled = not KeyPicker.Toggled
								KeyPicker:DoClick()
							end
						elseif Input.UserInputType == Enum.UserInputType.Keyboard then
							if Input.KeyCode.Name == Key then
								KeyPicker.Toggled = not KeyPicker.Toggled
								KeyPicker:DoClick()
							end
						elseif Input.UserInputType == Enum.UserInputType.Touch then
							if Input.KeyCode.Name == Key then
								KeyPicker.Toggled = not KeyPicker.Toggled
								KeyPicker:DoClick()
							end
						end
					end

					if KeyPicker.Mode == "Hold" then
						pcall(function()
							local Key = KeyPicker.Value

							if Key == "MB1" then
								KeyPicker.Toggled = InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
							elseif Key == "MB2" then
								KeyPicker.Toggled = InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
							end

							if Key == "MB1" or Key == "MB2" then
								KeyPicker:DoClick()
							else
								KeyPicker.Toggled = InputService:IsKeyDown(Enum.KeyCode[Key])
								KeyPicker:DoClick()
							end
						end)
					end

					KeyPicker:Update()
				end

				if
					Input.UserInputType == Enum.UserInputType.Touch
					or Input.UserInputType == Enum.UserInputType.MouseButton1
				then
					local AbsPos, AbsSize = ModeSelectOuter.AbsolutePosition, ModeSelectOuter.AbsoluteSize

					if
						Mouse.X < AbsPos.X
						or Mouse.X > AbsPos.X + AbsSize.X
						or Mouse.Y < (AbsPos.Y - 20 - 1)
						or Mouse.Y > AbsPos.Y + AbsSize.Y
					then
						ModeSelectOuter.Visible = false
					end
				end
			end))

			Library:GiveSignal(InputService.InputEnded:Connect(function(Input, ProcessedByGame)
				if not Picking then
					if KeyPicker.Mode == "Hold" then
						pcall(function()
							local Key = KeyPicker.Value

							if Key == "MB1" then
								KeyPicker.Toggled = InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
							elseif Key == "MB2" then
								KeyPicker.Toggled = InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
							end

							if Key == "MB1" or Key == "MB2" then
								KeyPicker:DoClick()
							else
								KeyPicker.Toggled = InputService:IsKeyDown(Enum.KeyCode[Key])
								KeyPicker:DoClick()
							end
						end)
					end

					KeyPicker:Update()
				end
			end))

			if Info.Mode == "Always" then
				KeyPicker.Toggled = true
				KeyPicker:DoClick()
			end

			if Info.Mode == "Off" then
				KeyPicker.Toggled = false
				KeyPicker:DoClick()
			end

			KeyPicker:Update()

			if Idx then
				Options[Idx] = KeyPicker
			end

			return self
		end

		BaseAddons.__index = Funcs
		BaseAddons.__namecall = function(Table, Key, ...)
			return Funcs[Key](...)
		end
	end

	local BaseGroupbox = {}

	do
		local Funcs = {}

		function Funcs:AddBlank(Size)
			local Groupbox = self
			local Container = Groupbox.Container

			Library:Create("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, Size),
				ZIndex = 1,
				Parent = Container,
			})
		end

		function Funcs:AddLabel(Text, DoesWrap)
			local Label = {}

			local Groupbox = self
			local Container = Groupbox.Container

			local TextLabel = Library:CreateLabel({
				Size = UDim2.new(1, -4, 0, 15),
				TextSize = 14,
				Text = Text,
				TextWrapped = DoesWrap or false,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 5,
				Parent = Container,
			})

			if DoesWrap then
				local Y = select(
					2,
					Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge))
				)
				TextLabel.Size = UDim2.new(1, -4, 0, Y)
			else
				Library:Create("UIListLayout", {
					Padding = UDim.new(0, 4),
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Parent = TextLabel,
				})
			end

			Label.TextLabel = TextLabel
			Label.Container = Container

			function Label:SetText(Text)
				TextLabel.Text = Text

				if DoesWrap then
					local Y = select(
						2,
						Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge))
					)
					TextLabel.Size = UDim2.new(1, -4, 0, Y)
				end

				Groupbox:Resize()
			end

			if not DoesWrap then
				setmetatable(Label, BaseAddons)
			end

			Groupbox:AddBlank(5)
			Groupbox:Resize()

			return Label
		end

		function Funcs:AddButton(...)
			-- TODO: Eventually redo this
			local Button = {}
			local function ProcessButtonParams(Class, Obj, ...)
				local Props = select(1, ...)
				if type(Props) == "table" then
					Obj.Text = Props.Text
					Obj.Func = Props.Func
					Obj.DoubleClick = Props.DoubleClick
					Obj.DoubleClickText = Props.DoubleClickText
					Obj.Tooltip = Props.Tooltip
				else
					Obj.Text = select(1, ...)
					Obj.Func = select(2, ...)
				end

				assert(type(Obj.Func) == "function", "AddButton: `Func` callback is missing.")
			end

			ProcessButtonParams("Button", Button, ...)

			local Groupbox = self
			local Container = Groupbox.Container

			local function CreateBaseButton(Button)
				local Outer = Library:Create("Frame", {
					BackgroundColor3 = Color3.new(0, 0, 0),
					BorderColor3 = Color3.new(0, 0, 0),
					Size = UDim2.new(1, -4, 0, 20),
					ZIndex = 5,
				})

				local Inner = Library:Create("Frame", {
					BackgroundColor3 = Library.MainColor,
					BorderColor3 = Library.OutlineColor,
					BorderMode = Enum.BorderMode.Inset,
					Size = UDim2.new(1, 0, 1, 0),
					ZIndex = 6,
					Parent = Outer,
				})

				local Label = Library:CreateLabel({
					Size = UDim2.new(1, 0, 1, 0),
					TextSize = 14,
					Text = Button.Text,
					ZIndex = 6,
					Parent = Inner,
				})

				Library:Create("UIGradient", {
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212)),
					}),
					Rotation = 90,
					Parent = Inner,
				})

				Library:AddToRegistry(Outer, {
					BorderColor3 = "Black",
				})

				Library:AddToRegistry(Inner, {
					BackgroundColor3 = "MainColor",
					BorderColor3 = "OutlineColor",
				})

				Library:OnHighlight(Outer, Outer, { BorderColor3 = "AccentColor" }, { BorderColor3 = "Black" })

				return Outer, Inner, Label
			end

			local function InitEvents(Button)
				local function WaitForEvent(event, timeout, validator)
					local bindable = Instance.new("BindableEvent")
					local connection = event:Once(function(...)
						if type(validator) == "function" and validator(...) then
							bindable:Fire(true)
						else
							bindable:Fire(false)
						end
					end)
					task.delay(timeout, function()
						connection:disconnect()
						bindable:Fire(false)
					end)
					return bindable.Event:Wait()
				end

				local function ValidateClick(Input)
					if Library:MouseIsOverOpenedFrame() then
						return false
					end

					if
						Input.UserInputType ~= Enum.UserInputType.MouseButton1
						and Input.UserInputType ~= Enum.UserInputType.Touch
					then
						return false
					end

					return true
				end

				Button.Outer.InputBegan:Connect(function(Input)
					if not ValidateClick(Input) then
						return
					end
					if Button.Locked then
						return
					end

					if Button.DoubleClick then
						Library:RemoveFromRegistry(Button.Label)
						Library:AddToRegistry(Button.Label, { TextColor3 = "AccentColor" })

						Button.Label.TextColor3 = Library.AccentColor
						Button.Label.Text = Button.DoubleClickText or "Are you sure?"
						Button.Locked = true

						local clicked = WaitForEvent(Button.Outer.InputBegan, 2, ValidateClick)

						Library:RemoveFromRegistry(Button.Label)
						Library:AddToRegistry(Button.Label, { TextColor3 = "FontColor" })

						Button.Label.TextColor3 = Library.FontColor
						Button.Label.Text = Button.Text
						task.defer(rawset, Button, "Locked", false)

						if clicked then
							Library:SafeCallback("Button" .. "_" .. Button.Label.Text, Button.Func)
						end

						return
					end

					Library:SafeCallback("Button" .. "_" .. Button.Label.Text, Button.Func)
				end)
			end

			Button.Outer, Button.Inner, Button.Label = CreateBaseButton(Button)
			Button.Outer.Parent = Container

			InitEvents(Button)

			function Button:AddTooltip(tooltip)
				if type(tooltip) == "string" then
					Library:AddToolTip(tooltip, self.Outer)
				end
				return self
			end

			function Button:AddButton(...)
				local SubButton = {}

				ProcessButtonParams("SubButton", SubButton, ...)

				self.Outer.Size = UDim2.new(0.5, -2, 0, 20)

				SubButton.Outer, SubButton.Inner, SubButton.Label = CreateBaseButton(SubButton)

				SubButton.Outer.Position = UDim2.new(1, 3, 0, 0)
				SubButton.Outer.Size = UDim2.fromOffset(self.Outer.AbsoluteSize.X - 2, self.Outer.AbsoluteSize.Y)
				SubButton.Outer.Parent = self.Outer

				function SubButton:AddTooltip(tooltip)
					if type(tooltip) == "string" then
						Library:AddToolTip(tooltip, self.Outer)
					end
					return SubButton
				end

				if type(SubButton.Tooltip) == "string" then
					SubButton:AddTooltip(SubButton.Tooltip)
				end

				InitEvents(SubButton)
				return SubButton
			end

			if type(Button.Tooltip) == "string" then
				Button:AddTooltip(Button.Tooltip)
			end

			Groupbox:AddBlank(5)
			Groupbox:Resize()

			return Button
		end

		function Funcs:AddDivider()
			local Groupbox = self
			local Container = self.Container

			local Divider = {
				Type = "Divider",
			}

			Groupbox:AddBlank(2)
			local DividerOuter = Library:Create("Frame", {
				BackgroundColor3 = Color3.new(0, 0, 0),
				BorderColor3 = Color3.new(0, 0, 0),
				Size = UDim2.new(1, -4, 0, 5),
				ZIndex = 5,
				Parent = Container,
			})

			local DividerInner = Library:Create("Frame", {
				BackgroundColor3 = Library.MainColor,
				BorderColor3 = Library.OutlineColor,
				BorderMode = Enum.BorderMode.Inset,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 6,
				Parent = DividerOuter,
			})

			Library:AddToRegistry(DividerOuter, {
				BorderColor3 = "Black",
			})

			Library:AddToRegistry(DividerInner, {
				BackgroundColor3 = "MainColor",
				BorderColor3 = "OutlineColor",
			})

			Groupbox:AddBlank(9)
			Groupbox:Resize()
		end

		---Add input function.
		---@param Idx string
		---@param Info table
		---@return any
		function Funcs:AddInput(Idx, Info)
			assert(Info.Text, "AddInput: Missing `Text` string.")

			local Textbox = {
				Value = Info.Default or "",
				Numeric = Info.Numeric or false,
				Finished = Info.Finished or false,
				Type = "Input",
				Callback = Info.Callback or function(Value) end,
			}

			local Groupbox = self
			local Container = Groupbox.Container

			local InputLabel = Library:CreateLabel({
				Size = UDim2.new(1, 0, 0, 15),
				TextSize = 14,
				Text = Info.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 5,
				Parent = Container,
			})

			Groupbox:AddBlank(1)

			local TextBoxOuter = Library:Create("Frame", {
				BackgroundColor3 = Color3.new(0, 0, 0),
				BorderColor3 = Color3.new(0, 0, 0),
				Size = UDim2.new(1, -4, 0, 20),
				ZIndex = 5,
				Parent = Container,
			})

			local TextBoxInner = Library:Create("Frame", {
				BackgroundColor3 = Library.MainColor,
				BorderColor3 = Library.OutlineColor,
				BorderMode = Enum.BorderMode.Inset,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 6,
				Parent = TextBoxOuter,
			})

			Library:AddToRegistry(TextBoxInner, {
				BackgroundColor3 = "MainColor",
				BorderColor3 = "OutlineColor",
			})

			Library:OnHighlight(
				TextBoxOuter,
				TextBoxOuter,
				{ BorderColor3 = "AccentColor" },
				{ BorderColor3 = "Black" }
			)

			if type(Info.Tooltip) == "string" then
				Library:AddToolTip(Info.Tooltip, TextBoxOuter)
			end

			Library:Create("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212)),
				}),
				Rotation = 90,
				Parent = TextBoxInner,
			})

			local Container = Library:Create("Frame", {
				BackgroundTransparency = 1,
				ClipsDescendants = true,

				Position = UDim2.new(0, 5, 0, 0),
				Size = UDim2.new(1, -5, 1, 0),

				ZIndex = 7,
				Parent = TextBoxInner,
			})

			local Box = Library:Create("TextBox", {
				BackgroundTransparency = 1,

				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.fromScale(5, 1),

				FontFace = Library.Font,
				PlaceholderColor3 = Color3.fromRGB(190, 190, 190),
				PlaceholderText = Info.Placeholder or "",

				Text = Info.Default or "",
				TextColor3 = Library.FontColor,
				TextSize = 14,
				TextStrokeTransparency = 0,
				TextXAlignment = Enum.TextXAlignment.Left,

				ZIndex = 7,
				Parent = Container,
			})

			Library:ApplyTextStroke(Box)

			local Connection = nil

			function Textbox:SetRawValue(Text)
				if Info.MaxLength and #Text > Info.MaxLength then
					Text = Text:sub(1, Info.MaxLength)
				end

				if Textbox.Numeric then
					if (not tonumber(Text)) and Text:len() > 0 then
						Text = Textbox.Value
					end
				end

				Textbox.Value = Text
				Box.Text = Text
			end

			function Textbox:SetValue(Text)
				if Info.MaxLength and #Text > Info.MaxLength then
					Text = Text:sub(1, Info.MaxLength)
				end

				if Textbox.Numeric then
					if (not tonumber(Text)) and Text:len() > 0 then
						Text = Textbox.Value
					end
				end

				Textbox.Value = Text
				Box.Text = Text

				Library:SafeCallback("Textbox_Callback" .. "_" .. (Idx or ""), Textbox.Callback, Textbox.Value)
				Library:SafeCallback("Textbox_Changed" .. "_" .. (Idx or ""), Textbox.Changed, Textbox.Value)
			end

			if Textbox.Finished then
				Connection = Box.FocusLost:Connect(function(enter)
					if not enter then
						return
					end

					Textbox:SetValue(Box.Text)
					Library:AttemptSave()
				end)
			else
				Connection = Box:GetPropertyChangedSignal("Text"):Connect(function()
					Textbox:SetValue(Box.Text)
					Library:AttemptSave()
				end)
			end

			-- https://devforum.roblox.com/t/how-to-make-textboxes-follow-current-cursor-position/1368429/6
			-- thank you nicemike40 :)

			local function Update()
				local PADDING = 2
				local reveal = Container.AbsoluteSize.X

				if not Box:IsFocused() or Box.TextBounds.X <= reveal - 2 * PADDING then
					-- we aren't focused, or we fit so be normal
					Box.Position = UDim2.new(0, PADDING, 0, 0)
				else
					-- we are focused and don't fit, so adjust position
					local cursor = Box.CursorPosition
					if cursor ~= -1 then
						-- calculate pixel width of text from start to cursor
						local subtext = string.sub(Box.Text, 1, cursor - 1)
						local width = TextService:GetTextSize(
							subtext,
							Box.TextSize,
							Box.Font,
							Vector2.new(math.huge, math.huge)
						).X

						-- check if we're inside the box with the cursor
						local currentCursorPos = Box.Position.X.Offset + width

						-- adjust if necessary
						if currentCursorPos < PADDING then
							Box.Position = UDim2.fromOffset(PADDING - width, 0)
						elseif currentCursorPos > reveal - PADDING - 1 then
							Box.Position = UDim2.fromOffset(reveal - width - PADDING - 1, 0)
						end
					end
				end
			end

			task.spawn(Update)

			Box:GetPropertyChangedSignal("Text"):Connect(Update)
			Box:GetPropertyChangedSignal("CursorPosition"):Connect(Update)
			Box.FocusLost:Connect(Update)
			Box.Focused:Connect(Update)

			Box.InputBegan:Connect(function(Input)
				if Input.UserInputType == Enum.UserInputType.MouseButton2 then
					Library:Notify("Text copied to clipboard!", 2.5)
					setclipboard(Box.Text)
				end
			end)

			Library:AddToRegistry(Box, {
				TextColor3 = "FontColor",
			})

			function Textbox:OnChanged(Func)
				Textbox.Changed = Func
				Func(Textbox.Value)
			end

			Groupbox:AddBlank(5)
			Groupbox:Resize()

			if Idx then
				Options[Idx] = Textbox
			end

			return Textbox
		end

		function Funcs:AddToggle(Idx, Info)
			assert(Info.Text, "AddInput: Missing `Text` string.")

			local Toggle = {
				Value = Info.Default or false,
				Type = "Toggle",

				Callback = Info.Callback or function(Value) end,
				Addons = {},
				Risky = Info.Risky,
			}

			local Groupbox = self
			local Container = Groupbox.Container

			local ToggleOuter = Library:Create("Frame", {
				BackgroundColor3 = Color3.new(0, 0, 0),
				BorderColor3 = Color3.new(0, 0, 0),
				Size = UDim2.new(0, 13, 0, 13),
				ZIndex = 5,
				Parent = Container,
			})

			Library:AddToRegistry(ToggleOuter, {
				BorderColor3 = "Black",
			})

			local ToggleInner = Library:Create("Frame", {
				BackgroundColor3 = Library.MainColor,
				BorderColor3 = Library.OutlineColor,
				BorderMode = Enum.BorderMode.Inset,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 6,
				Parent = ToggleOuter,
			})

			Library:AddToRegistry(ToggleInner, {
				BackgroundColor3 = "MainColor",
				BorderColor3 = "OutlineColor",
			})

			local ToggleLabel = Library:CreateLabel({
				Size = UDim2.new(0, 216, 1, 0),
				Position = UDim2.new(1, 6, 0, 0),
				TextSize = 14,
				Text = Info.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 6,
				Parent = ToggleInner,
			})

			Library:Create("UIListLayout", {
				Padding = UDim.new(0, 4),
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = ToggleLabel,
			})

			local ToggleRegion = Library:Create("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 170, 1, 0),
				ZIndex = 8,
				Parent = ToggleOuter,
			})

			Library:OnHighlight(
				ToggleRegion,
				ToggleOuter,
				{ BorderColor3 = "AccentColor" },
				{ BorderColor3 = "Black" }
			)

			function Toggle:UpdateColors()
				Toggle:Display()
			end

			if type(Info.Tooltip) == "string" then
				Library:AddToolTip(Info.Tooltip, ToggleRegion)
			end

			function Toggle:Display()
				ToggleInner.BackgroundColor3 = Toggle.Value and Library.AccentColor or Library.MainColor
				ToggleInner.BorderColor3 = Toggle.Value and Library.AccentColorDark or Library.OutlineColor

				Library.RegistryMap[ToggleInner].Properties.BackgroundColor3 = Toggle.Value and "AccentColor"
					or "MainColor"
				Library.RegistryMap[ToggleInner].Properties.BorderColor3 = Toggle.Value and "AccentColorDark"
					or "OutlineColor"
			end

			function Toggle:OnChanged(Func)
				Toggle.Changed = Func
				Func(Toggle.Value)
			end

			function Toggle:SetRawValue(Bool)
				Bool = not not Bool

				Toggle.Value = Bool
				Toggle:Display()

				for _, Addon in next, Toggle.Addons do
					if Addon.Type == "KeyPicker" and Addon.SyncToggleState then
						Addon.Toggled = Bool
						Addon:Update()
					end
				end

				Library:UpdateDependencyBoxes()
			end

			function Toggle:SetValue(Bool)
				Bool = not not Bool

				Toggle.Value = Bool
				Toggle:Display()

				for _, Addon in next, Toggle.Addons do
					if Addon.Type == "KeyPicker" and Addon.SyncToggleState then
						Addon.Toggled = Bool
						Addon:Update()
					end
				end

				Library:SafeCallback("Toggle_Callback" .. "_" .. (Idx or ""), Toggle.Callback, Toggle.Value)
				Library:SafeCallback("Toggle_Changed" .. "_" .. (Idx or ""), Toggle.Changed, Toggle.Value)
				Library:UpdateDependencyBoxes()
			end

			ToggleRegion.InputBegan:Connect(function(Input)
				if
					(
						Input.UserInputType == Enum.UserInputType.MouseButton1
						or Input.UserInputType == Enum.UserInputType.Touch
					) and not Library:MouseIsOverOpenedFrame()
				then
					Toggle:SetValue(not Toggle.Value) -- Why was it not like this from the start?
					Library:AttemptSave()
				end
			end)

			if Toggle.Risky then
				Library:RemoveFromRegistry(ToggleLabel)
				ToggleLabel.TextColor3 = Library.RiskColor
				Library:AddToRegistry(ToggleLabel, { TextColor3 = "RiskColor" })
			end

			Toggle:Display()
			Groupbox:AddBlank(Info.BlankSize or 5 + 2)
			Groupbox:Resize()

			Toggle.TextLabel = ToggleLabel
			Toggle.Container = Container
			setmetatable(Toggle, BaseAddons)

			if Idx then
				Toggles[Idx] = Toggle
			end

			Library:UpdateDependencyBoxes()

			return Toggle
		end

		function Funcs:AddSlider(Idx, Info)
			assert(Info.Default, "AddSlider: Missing default value.")
			assert(Info.Text, "AddSlider: Missing slider text.")
			assert(Info.Min, "AddSlider: Missing minimum value.")
			assert(Info.Max, "AddSlider: Missing maximum value.")
			assert(Info.Rounding, "AddSlider: Missing rounding value.")

			local Slider = {
				Value = Info.Default,
				Min = Info.Min,
				Max = Info.Max,
				Rounding = Info.Rounding,
				MaxSize = 232,
				Type = "Slider",
				Callback = Info.Callback or function(Value) end,
			}

			local Groupbox = self
			local Container = Groupbox.Container

			if not Info.Compact then
				Library:CreateLabel({
					Size = UDim2.new(1, 0, 0, 10),
					TextSize = 14,
					Text = Info.Text,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Bottom,
					ZIndex = 5,
					Parent = Container,
				})

				Groupbox:AddBlank(3)
			end

			local SliderOuter = Library:Create("Frame", {
				BackgroundColor3 = Color3.new(0, 0, 0),
				BorderColor3 = Color3.new(0, 0, 0),
				Size = UDim2.new(1, -4, 0, 13),
				ZIndex = 5,
				Parent = Container,
			})

			Library:AddToRegistry(SliderOuter, {
				BorderColor3 = "Black",
			})

			local SliderInner = Library:Create("Frame", {
				BackgroundColor3 = Library.MainColor,
				BorderColor3 = Library.OutlineColor,
				BorderMode = Enum.BorderMode.Inset,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 6,
				Parent = SliderOuter,
			})

			Library:AddToRegistry(SliderInner, {
				BackgroundColor3 = "MainColor",
				BorderColor3 = "OutlineColor",
			})

			local Fill = Library:Create("Frame", {
				BackgroundColor3 = Library.AccentColor,
				BorderColor3 = Library.AccentColorDark,
				Size = UDim2.new(0, 0, 1, 0),
				ZIndex = 7,
				Parent = SliderInner,
			})

			Library:AddToRegistry(Fill, {
				BackgroundColor3 = "AccentColor",
				BorderColor3 = "AccentColorDark",
			})

			local HideBorderRight = Library:Create("Frame", {
				BackgroundColor3 = Library.AccentColor,
				BorderSizePixel = 0,
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.new(0, 1, 1, 0),
				ZIndex = 8,
				Parent = Fill,
			})

			Library:AddToRegistry(HideBorderRight, {
				BackgroundColor3 = "AccentColor",
			})

			local DisplayLabel = Library:CreateLabel({
				Size = UDim2.new(1, 0, 1, 0),
				TextSize = 14,
				Text = "Infinite",
				ZIndex = 9,
				Parent = SliderInner,
			})

			Library:OnHighlight(
				SliderOuter,
				SliderOuter,
				{ BorderColor3 = "AccentColor" },
				{ BorderColor3 = "Black" }
			)

			if type(Info.Tooltip) == "string" then
				Library:AddToolTip(Info.Tooltip, SliderOuter)
			end

			function Slider:UpdateColors()
				Fill.BackgroundColor3 = Library.AccentColor
				Fill.BorderColor3 = Library.AccentColorDark
			end

			function Slider:Display()
				local Suffix = Info.Suffix or ""

				if Info.Compact then
					DisplayLabel.Text = Info.Text .. ": " .. Slider.Value .. Suffix
				elseif Info.HideMax then
					DisplayLabel.Text = string.format("%s", Slider.Value .. Suffix)
				else
					DisplayLabel.Text = string.format("%s/%s", Slider.Value .. Suffix, Slider.Max .. Suffix)
				end

				local X = math.ceil(Library:MapValue(Slider.Value, Slider.Min, Slider.Max, 0, Slider.MaxSize))
				Fill.Size = UDim2.new(0, X, 1, 0)

				HideBorderRight.Visible = not (X == Slider.MaxSize or X == 0)
			end

			function Slider:OnChanged(Func)
				Slider.Changed = Func
				Func(Slider.Value)
			end

			local function Round(Value)
				if Slider.Rounding == 0 then
					return math.floor(Value)
				end

				return tonumber(string.format("%." .. Slider.Rounding .. "f", Value))
			end

			function Slider:GetValueFromXOffset(X)
				return Round(Library:MapValue(X, 0, Slider.MaxSize, Slider.Min, Slider.Max))
			end

			function Slider:SetRawValue(Value)
				local Num = tonumber(Value)

				if not Num then
					return
				end

				Num = math.clamp(Num, Slider.Min, Slider.Max)

				Slider.Value = Num
				Slider:Display()
			end

			function Slider:SetValue(Str)
				local Num = tonumber(Str)

				if not Num then
					return
				end

				Num = math.clamp(Num, Slider.Min, Slider.Max)

				Slider.Value = Num
				Slider:Display()

				Library:SafeCallback("Slider_Callback" .. "_" .. (Idx or ""), Slider.Callback, Slider.Value)
				Library:SafeCallback("Slider_Changed" .. "_" .. (Idx or ""), Slider.Changed, Slider.Value)
			end

			local CurrentAmount = 0.01
			local isInputChangedConnected = true
			local isInputEndedConnected = false

			SliderInner.InputBegan:Connect(function(Input)
				isInputEndedConnected = false

				if
					(
						Input.UserInputType == Enum.UserInputType.MouseButton1
						or Input.UserInputType == Enum.UserInputType.Touch
					) and not Library:MouseIsOverOpenedFrame()
				then
					local isTouch = Input.UserInputType == Enum.UserInputType.Touch
					local startPos = isTouch and Input.Position.X or Mouse.X
					local startFillPos = Fill.Size.X.Offset
					local diff = startPos - (Fill.AbsolutePosition.X + startFillPos)

					while isInputChangedConnected and not isInputEndedConnected do
						local newPos = isTouch and Input.Position.X or Mouse.X
						local newX = math.clamp(startFillPos + (newPos - startPos) + diff, 0, Slider.MaxSize)

						local newValue = Slider:GetValueFromXOffset(newX)
						local oldValue = Slider.Value
						Slider.Value = newValue

						Slider:Display()

						if newValue ~= oldValue then
							Library:SafeCallback("Slider_Callback" .. "_" .. (Idx or ""), Slider.Callback, Slider.Value)
							Library:SafeCallback("Slider_Changed" .. "_" .. (Idx or ""), Slider.Changed, Slider.Value)
						end

						RenderStepped:Wait()
					end

					Library:AttemptSave()
				end

				if Input.KeyCode == Enum.KeyCode.Minus then
					CurrentAmount = math.max(CurrentAmount / 10, 0.00001)
				end

				if Input.KeyCode == Enum.KeyCode.Equals and (CurrentAmount * 10) <= Slider.Max then
					CurrentAmount = CurrentAmount * 10
				end

				if Input.KeyCode == Enum.KeyCode.Right then
					Slider:SetValue(Slider.Value + CurrentAmount)
				end

				if Input.KeyCode == Enum.KeyCode.Left then
					Slider:SetValue(Slider.Value - CurrentAmount)
				end
			end)

			SliderInner.InputEnded:Connect(function()
				isInputEndedConnected = true
			end)

			Slider:Display()
			Groupbox:AddBlank(Info.BlankSize or 6)
			Groupbox:Resize()

			if Idx then
				Options[Idx] = Slider
			end

			return Slider
		end

		function Funcs:AddDropdown(Idx, Info)
			if Info.SpecialType == "Player" then
				Info.Values = GetPlayersString()
				Info.AllowNull = true
			elseif Info.SpecialType == "Team" then
				Info.Values = GetTeamsString()
				Info.AllowNull = true
			end

			assert(Info.Values, "AddDropdown: Missing dropdown value list.")
			assert(
				Info.AllowNull or Info.Default,
				"AddDropdown: Missing default value. Pass `AllowNull` as true if this was intentional."
			)

			if not Info.Text then
				Info.Compact = true
			end

			local Dropdown = {
				Values = Info.Values,
				Value = Info.Multi and {},
				SaveValues = Info.SaveValues or false,
				Multi = Info.Multi,
				Type = "Dropdown",
				SpecialType = Info.SpecialType, -- can be either 'Player' or 'Team'
				Callback = Info.Callback or function(Value) end,
			}

			local Groupbox = self
			local Container = Groupbox.Container

			local RelativeOffset = 0

			if not Info.Compact then
				local DropdownLabel = Library:CreateLabel({
					Size = UDim2.new(1, 0, 0, 10),
					TextSize = 14,
					Text = Info.Text,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Bottom,
					ZIndex = 5,
					Parent = Container,
				})

				Groupbox:AddBlank(3)
			end

			for _, Element in next, Container:GetChildren() do
				if not Element:IsA("UIListLayout") then
					RelativeOffset = RelativeOffset + Element.Size.Y.Offset
				end
			end

			local DropdownOuter = Library:Create("Frame", {
				BackgroundColor3 = Color3.new(0, 0, 0),
				BorderColor3 = Color3.new(0, 0, 0),
				Size = UDim2.new(1, -4, 0, 20),
				ZIndex = 5,
				Parent = Container,
			})

			Library:AddToRegistry(DropdownOuter, {
				BorderColor3 = "Black",
			})

			local DropdownInner = Library:Create("Frame", {
				BackgroundColor3 = Library.MainColor,
				BorderColor3 = Library.OutlineColor,
				BorderMode = Enum.BorderMode.Inset,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 6,
				Parent = DropdownOuter,
			})

			Library:AddToRegistry(DropdownInner, {
				BackgroundColor3 = "MainColor",
				BorderColor3 = "OutlineColor",
			})

			Library:Create("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212)),
				}),
				Rotation = 90,
				Parent = DropdownInner,
			})

			local DropdownArrow = Library:Create("ImageLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Position = UDim2.new(1, -16, 0.5, 0),
				Size = UDim2.new(0, 12, 0, 12),
				Image = "http://www.roblox.com/asset/?id=6282522798",
				ZIndex = 8,
				Parent = DropdownInner,
			})

			local ItemList = Library:CreateLabel({
				Position = UDim2.new(0, 5, 0, 0),
				Size = UDim2.new(1, -5, 1, 0),
				TextSize = 14,
				Text = "--",
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				ZIndex = 7,
				Parent = DropdownInner,
			})

			Library:OnHighlight(
				DropdownOuter,
				DropdownOuter,
				{ BorderColor3 = "AccentColor" },
				{ BorderColor3 = "Black" }
			)

			if type(Info.Tooltip) == "string" then
				Library:AddToolTip(Info.Tooltip, DropdownOuter)
			end

			local MAX_DROPDOWN_ITEMS = 8

			local ListOuter = Library:Create("Frame", {
				BackgroundColor3 = Color3.new(0, 0, 0),
				BorderColor3 = Color3.new(0, 0, 0),
				ZIndex = 20,
				Visible = false,
				Name = "ListOuter",
				Parent = ScreenGui,
			})

			local function RecalculateListPosition()
				ListOuter.Position = UDim2.fromOffset(
					DropdownOuter.AbsolutePosition.X,
					DropdownOuter.AbsolutePosition.Y + DropdownOuter.Size.Y.Offset + 1
				)
			end

			local function RecalculateListSize(YSize)
				ListOuter.Size = UDim2.fromOffset(DropdownOuter.AbsoluteSize.X, YSize or (MAX_DROPDOWN_ITEMS * 20 + 2))
			end

			RecalculateListPosition()
			RecalculateListSize()

			DropdownOuter:GetPropertyChangedSignal("AbsolutePosition"):Connect(RecalculateListPosition)

			local ListInner = Library:Create("Frame", {
				BackgroundColor3 = Library.MainColor,
				BorderColor3 = Library.OutlineColor,
				BorderMode = Enum.BorderMode.Inset,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 21,
				Parent = ListOuter,
			})

			Library:AddToRegistry(ListInner, {
				BackgroundColor3 = "MainColor",
				BorderColor3 = "OutlineColor",
			})

			local Scrolling = Library:Create("ScrollingFrame", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(0, 0, 0, 0),
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 21,
				Parent = ListInner,

				TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
				BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",

				ScrollBarThickness = 3,
				ScrollBarImageColor3 = Library.AccentColor,
			})

			Library:AddToRegistry(Scrolling, {
				ScrollBarImageColor3 = "AccentColor",
			})

			Library:Create("UIListLayout", {
				Padding = UDim.new(0, 0),
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = Scrolling,
			})

			function Dropdown:Display()
				local Values = Dropdown.Values
				local Str = ""

				if Info.Multi then
					for Idx, Value in next, Values do
						if Dropdown.Value[Value] then
							Str = Str .. Value .. ", "
						end
					end

					Str = Str:sub(1, #Str - 2)
				else
					Str = Dropdown.Value or ""
				end

				ItemList.Text = (Str == "" and "--" or Str)
			end

			function Dropdown:GetActiveValues()
				if Info.Multi then
					local T = {}

					for Value, Bool in next, Dropdown.Value do
						table.insert(T, Value)
					end

					return T
				else
					return Dropdown.Value and 1 or 0
				end
			end

			function Dropdown:BuildDropdownList()
				local Values = Dropdown.Values
				local Buttons = {}

				for _, Element in next, Scrolling:GetChildren() do
					if not Element:IsA("UIListLayout") then
						Element:Destroy()
					end
				end

				local Count = 0

				for Idx, Value in next, Values do
					local Table = {}

					Count = Count + 1

					local Button = Library:Create("Frame", {
						BackgroundColor3 = Library.MainColor,
						BorderColor3 = Library.OutlineColor,
						BorderMode = Enum.BorderMode.Middle,
						Size = UDim2.new(1, -1, 0, 20),
						ZIndex = 23,
						Active = true,
						Parent = Scrolling,
					})

					Library:AddToRegistry(Button, {
						BackgroundColor3 = "MainColor",
						BorderColor3 = "OutlineColor",
					})

					local ButtonLabel = Library:CreateLabel({
						Active = false,
						Size = UDim2.new(1, -6, 1, 0),
						Position = UDim2.new(0, 6, 0, 0),
						TextSize = 14,
						Text = Value,
						TextXAlignment = Enum.TextXAlignment.Left,
						ZIndex = 25,
						Parent = Button,
					})

					Library:OnHighlight(
						Button,
						Button,
						{ BorderColor3 = "AccentColor", ZIndex = 24 },
						{ BorderColor3 = "OutlineColor", ZIndex = 23 }
					)

					local Selected

					if Info.Multi then
						Selected = Dropdown.Value[Value]
					else
						Selected = Dropdown.Value == Value
					end

					function Table:UpdateButton()
						if Info.Multi then
							Selected = Dropdown.Value[Value]
						else
							Selected = Dropdown.Value == Value
						end

						ButtonLabel.TextColor3 = Selected and Library.AccentColor or Library.FontColor
						Library.RegistryMap[ButtonLabel].Properties.TextColor3 = Selected and "AccentColor"
							or "FontColor"
					end

					ButtonLabel.InputBegan:Connect(function(Input)
						if
							Input.UserInputType == Enum.UserInputType.MouseButton1
							or Input.UserInputType == Enum.UserInputType.Touch
						then
							local Try = not Selected

							if Dropdown:GetActiveValues() == 1 and not Try and not Info.AllowNull then
							else
								if Info.Multi then
									Selected = Try

									if Selected then
										Dropdown.Value[Value] = true
									else
										Dropdown.Value[Value] = nil
									end
								else
									Selected = Try

									if Selected then
										Dropdown.Value = Value
									else
										Dropdown.Value = nil
									end

									for _, OtherButton in next, Buttons do
										OtherButton:UpdateButton()
									end

									Library:UpdateDependencyBoxes()
								end

								Table:UpdateButton()
								Dropdown:Display()

								Library:SafeCallback(
									"Dropdown_Callback" .. "_" .. (Idx or ""),
									Dropdown.Callback,
									Dropdown.Value
								)
								Library:SafeCallback(
									"Dropdown_Changed" .. "_" .. (Idx or ""),
									Dropdown.Changed,
									Dropdown.Value
								)

								Library:AttemptSave()
							end
						end
					end)

					Table:UpdateButton()
					Dropdown:Display()

					Buttons[Button] = Table
				end

				Scrolling.CanvasSize = UDim2.fromOffset(0, (Count * 20) + 1)

				local Y = math.clamp(Count * 20, 0, MAX_DROPDOWN_ITEMS * 20) + 1
				RecalculateListSize(Y)
			end

			function Dropdown:SetValues(NewValues)
				if NewValues then
					Dropdown.Values = NewValues
				end

				Dropdown:BuildDropdownList()
			end

			function Dropdown:OpenDropdown()
				ListOuter.Visible = true
				Library.OpenedFrames[ListOuter] = true
				DropdownArrow.Rotation = 180
			end

			function Dropdown:CloseDropdown()
				ListOuter.Visible = false
				Library.OpenedFrames[ListOuter] = nil
				DropdownArrow.Rotation = 0
			end

			function Dropdown:OnChanged(Func)
				Dropdown.Changed = Func
				Func(Dropdown.Value)
			end

			function Dropdown:SetRawValue(Val)
				if Dropdown.Multi then
					local nTable = {}

					for Value, Bool in next, Val do
						if table.find(Dropdown.Values, Value) then
							nTable[Value] = true
						end
					end

					Dropdown.Value = nTable
				else
					if not Val then
						Dropdown.Value = nil
					elseif table.find(Dropdown.Values, Val) then
						Dropdown.Value = Val
					end
				end

				Dropdown:BuildDropdownList()
			end

			function Dropdown:SetValue(Val)
				if Dropdown.Multi then
					local nTable = {}

					for Value, Bool in next, Val do
						if table.find(Dropdown.Values, Value) then
							nTable[Value] = true
						end
					end

					Dropdown.Value = nTable
				else
					if not Val then
						Dropdown.Value = nil
					elseif table.find(Dropdown.Values, Val) then
						Dropdown.Value = Val
					end
				end

				Dropdown:BuildDropdownList()

				Library:SafeCallback("Dropdown_Callback" .. "_" .. (Idx or ""), Dropdown.Callback, Dropdown.Value)
				Library:SafeCallback("Dropdown_Changed" .. "_" .. (Idx or ""), Dropdown.Changed, Dropdown.Value)
			end

			DropdownOuter.InputBegan:Connect(function(Input)
				if
					(
						Input.UserInputType == Enum.UserInputType.Touch
						or Input.UserInputType == Enum.UserInputType.MouseButton1
					) and not Library:MouseIsOverOpenedFrame()
				then
					if ListOuter.Visible then
						Dropdown:CloseDropdown()
					else
						Dropdown:OpenDropdown()
					end
				end
			end)

			InputService.InputBegan:Connect(function(Input)
				if
					Input.UserInputType == Enum.UserInputType.Touch
					or Input.UserInputType == Enum.UserInputType.MouseButton1
				then
					local AbsPos, AbsSize = ListOuter.AbsolutePosition, ListOuter.AbsoluteSize

					if
						Mouse.X < AbsPos.X
						or Mouse.X > AbsPos.X + AbsSize.X
						or Mouse.Y < (AbsPos.Y - 20 - 1)
						or Mouse.Y > AbsPos.Y + AbsSize.Y
					then
						Dropdown:CloseDropdown()
					end
				end
			end)

			Dropdown:BuildDropdownList()
			Dropdown:Display()

			local Defaults = {}

			if type(Info.Default) == "string" then
				local Idx = table.find(Dropdown.Values, Info.Default)
				if Idx then
					table.insert(Defaults, Idx)
				end
			elseif type(Info.Default) == "table" then
				for _, Value in next, Info.Default do
					local Idx = table.find(Dropdown.Values, Value)
					if Idx then
						table.insert(Defaults, Idx)
					end
				end
			elseif type(Info.Default) == "number" and Dropdown.Values[Info.Default] ~= nil then
				table.insert(Defaults, Info.Default)
			end

			if next(Defaults) then
				for i = 1, #Defaults do
					local Index = Defaults[i]
					if Info.Multi then
						Dropdown.Value[Dropdown.Values[Index]] = true
					else
						Dropdown.Value = Dropdown.Values[Index]
					end

					if not Info.Multi then
						break
					end
				end

				Dropdown:BuildDropdownList()
				Dropdown:Display()
			end

			Groupbox:AddBlank(Info.BlankSize or 5)
			Groupbox:Resize()

			if Idx then
				Options[Idx] = Dropdown
			end

			return Dropdown
		end

		function Funcs:AddDependencyBox()
			local Depbox = {
				Dependencies = {},
			}

			local Groupbox = self
			local Container = Groupbox.Container

			local Holder = Library:Create("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				Visible = false,
				Parent = Container,
			})

			local Frame = Library:Create("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Visible = true,
				Parent = Holder,
			})

			local Layout = Library:Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = Frame,
			})

			function Depbox:Resize()
				Holder.Size = UDim2.new(1, 0, 0, Layout.AbsoluteContentSize.Y)
				Groupbox:Resize()
			end

			Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				Depbox:Resize()
			end)

			Holder:GetPropertyChangedSignal("Visible"):Connect(function()
				Depbox:Resize()
			end)

			function Depbox:Update()
				for _, Dependency in next, Depbox.Dependencies do
					local Elem = Dependency[1]
					local Value = Dependency[2]

					if Elem.Type == "Toggle" and Elem.Value ~= Value then
						Holder.Visible = false
						Depbox:Resize()
						return
					end

					if Elem.Type == "Dropdown" and Elem.Value ~= Value then
						Holder.Visible = false
						Depbox:Resize()
						return
					end
				end

				Holder.Visible = true
				Depbox:Resize()
			end

			function Depbox:SetupDependencies(Dependencies)
				for _, Dependency in next, Dependencies do
					assert(type(Dependency) == "table", "SetupDependencies: Dependency is not of type `table`.")
					assert(Dependency[1], "SetupDependencies: Dependency is missing element argument.")
					assert(Dependency[2] ~= nil, "SetupDependencies: Dependency is missing value argument.")
				end

				Depbox.Dependencies = Dependencies
				Depbox:Update()
			end

			Depbox.Container = Frame

			setmetatable(Depbox, BaseGroupbox)

			table.insert(Library.DependencyBoxes, Depbox)

			return Depbox
		end

		BaseGroupbox.__index = Funcs
		BaseGroupbox.__namecall = function(Table, Key, ...)
			return Funcs[Key](...)
		end
	end

	-- < Create other UI elements >
	do
		Library.NotificationArea = Library:Create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0, 40),
			Size = UDim2.new(0, 300, 0, 200),
			ZIndex = 100,
			Parent = ScreenGui,
		})

		Library:Create("UIListLayout", {
			Padding = UDim.new(0, 4),
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = Library.NotificationArea,
		})

		local WatermarkOuter = Library:Create("Frame", {
			BorderColor3 = Color3.new(0, 0, 0),
			Position = UDim2.new(0, 100, 0, -25),
			Size = UDim2.new(0, 213, 0, 20),
			ZIndex = 200,
			Visible = false,
			Parent = ScreenGui,
		})

		local WatermarkInner = Library:Create("Frame", {
			BackgroundColor3 = Library.MainColor,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 201,
			Parent = WatermarkOuter,
		})

		Library:AddToRegistry(WatermarkInner, {
			BorderColor3 = "OutlineColor",
		})

		local ColorFrame = Library:Create("Frame", {
			BackgroundColor3 = Library.AccentColor,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 2),
			ZIndex = 204,
			Parent = WatermarkInner,
		})

		Library:AddToRegistry(ColorFrame, {
			BackgroundColor3 = "AccentColor",
		}, true)

		local InnerFrame = Library:Create("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Position = UDim2.new(0, 1, 0, 1),
			Size = UDim2.new(1, -2, 1, -2),
			ZIndex = 202,
			Parent = WatermarkInner,
		})

		local Gradient = Library:Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
				ColorSequenceKeypoint.new(1, Library.MainColor),
			}),
			Rotation = -90,
			Parent = InnerFrame,
		})

		Library:AddToRegistry(Gradient, {
			Color = function()
				return ColorSequence.new({
					ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
					ColorSequenceKeypoint.new(1, Library.MainColor),
				})
			end,
		})

		local WatermarkLabel = Library:CreateLabel({
			Position = UDim2.new(0, 5, 0, 1),
			Size = UDim2.new(1, -4, 1, 0),
			TextColor3 = Library.AccentColor,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 203,
			Parent = InnerFrame,
		})

		Library:AddToRegistry(WatermarkLabel, {
			TextColor3 = "AccentColor",
		}, true)

		Library.Watermark = WatermarkOuter
		Library.Watermark.Visible = false
		Library.WatermarkText = WatermarkLabel
		Library:MakeDraggable(Library.Watermark)

		local InfoLoggerOuter = Library:Create("Frame", {
			BorderColor3 = Color3.new(0, 0, 0),
			Position = UDim2.new(0, 15, 0.5, 0),
			Size = UDim2.new(0, 210, 0, 20),
			Visible = false,
			ZIndex = 287,
			Parent = ScreenGui,
		})

		local InfoLoggerInner = Library:Create("Frame", {
			BackgroundColor3 = Library.MainColor,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 288,
			Parent = InfoLoggerOuter,
		})

		Library:AddToRegistry(InfoLoggerInner, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "OutlineColor",
		}, true)

		local InfoColorFrame = Library:Create("Frame", {
			BackgroundColor3 = Library.AccentColor,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 2),
			ZIndex = 299,
			Parent = InfoLoggerInner,
		})

		Library:AddToRegistry(InfoColorFrame, {
			BackgroundColor3 = "AccentColor",
		}, true)

		local InfoLoggerLabel = Library:CreateLabel({
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromOffset(5, 2),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Library.AccentColor,
			Text = "Info Logger",
			TextSize = 14,
			ZIndex = 300,
			Parent = InfoLoggerInner,
		})

		Library:AddToRegistry(InfoLoggerLabel, {
			TextColor3 = "AccentColor",
		}, true)

		local InfoLoggerContainer = Library:Create("ScrollingFrame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -20),
			Position = UDim2.new(0, 0, 0, 20),
			ZIndex = 1,
			ScrollBarThickness = 0,
			Parent = InfoLoggerInner,
		})

		local InfoUIListLayout = Library:Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = InfoLoggerContainer,
		})

		InfoUIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			InfoLoggerContainer.CanvasSize = UDim2.fromOffset(0, InfoUIListLayout.AbsoluteContentSize.Y)
		end)

		Library:Create("UIPadding", {
			PaddingLeft = UDim.new(0, 5),
			Parent = InfoLoggerContainer,
		})

		---@param InputObject InputObject
		Library:GiveSignal(InfoLoggerOuter.InputBegan:Connect(function(InputObject)
			if InputObject.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end

			if

				InputObject.KeyCode == Enum.KeyCode.Z
				and game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.LeftControl)
			then
				local kbh = Library.InfoLoggerData.KeyBlacklistHistory
				local kbl = Library.InfoLoggerData.KeyBlacklistList
				local front = kbh[1]
				if not front then
					return
				end

				kbl[front] = nil

				table.remove(kbh, 1)

				Library:RefreshInfoLogger()
				if Options and Options.BlacklistedKeys then
					Options.BlacklistedKeys:SetValues(Library:KeyBlacklists())
				end
				Library:Notify(string.format("Re-whitelisted key '%s' into list.", front))
			end

			if InputObject.KeyCode == Enum.KeyCode.Q then
				Library.InfoLoggerCycle = math.max(Library.InfoLoggerCycle - 1, 1)
				Library:RefreshInfoLogger()
			end

			if InputObject.KeyCode == Enum.KeyCode.E then
				Library.InfoLoggerCycle = math.min(Library.InfoLoggerCycle + 1, #Library.InfoLoggerCycles)
				Library:RefreshInfoLogger()
			end
		end))

		-- default cycle is animation.
		Library.InfoLoggerLabel = InfoLoggerLabel
		Library.InfoLoggerFrame = InfoLoggerOuter
		Library.InfoLoggerContainer = InfoLoggerContainer
		Library.InfoLoggerCycle = 1
		Library.InfoLoggerCycles = {
			"Animation",
			"Existing Anim",
			"Keyframe",
			"Telemetry",
			"Part",
			"Sound",
		}
		Library.InfoLoggerData = {
			MissingDataEntries = {},
			KeyBlacklistHistory = {},
			KeyBlacklistList = {},
		}

		Library:MakeDraggable(InfoLoggerOuter)
		Library:RefreshInfoLogger()

		local KeybindOuter = Library:Create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			BorderColor3 = Color3.new(0, 0, 0),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.new(0, 210, 0, 20),
			Visible = false,
			ZIndex = 100,
			Parent = ScreenGui,
		})

		local KeybindInner = Library:Create("Frame", {
			BackgroundColor3 = Library.MainColor,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 101,
			Parent = KeybindOuter,
		})

		Library:AddToRegistry(KeybindInner, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "OutlineColor",
		}, true)

		local ColorFrame = Library:Create("Frame", {
			BackgroundColor3 = Library.AccentColor,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 2),
			ZIndex = 102,
			Parent = KeybindInner,
		})

		Library:AddToRegistry(ColorFrame, {
			BackgroundColor3 = "AccentColor",
		}, true)

		local KeybindLabel = Library:CreateLabel({
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromOffset(5, 2),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 14,
			TextColor3 = Library.AccentColor,
			Text = "Keybind List",
			ZIndex = 104,
			Parent = KeybindInner,
		})

		Library:AddToRegistry(KeybindLabel, {
			TextColor3 = "AccentColor",
		}, true)

		local KeybindContainer = Library:Create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -20),
			Position = UDim2.new(0, 0, 0, 20),
			ZIndex = 1,
			Parent = KeybindInner,
		})

		Library:Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = KeybindContainer,
		})

		Library:Create("UIPadding", {
			PaddingLeft = UDim.new(0, 5),
			Parent = KeybindContainer,
		})

		Library.KeybindFrame = KeybindOuter
		Library.KeybindFrame.Visible = false
		Library.KeybindContainer = KeybindContainer
		Library:MakeDraggable(KeybindOuter)
	end

	function Library:SetWatermarkVisibility(Bool)
		Library.Watermark.Visible = Bool
	end

	function Library:SetWatermark(Text)
		local X, Y = Library:GetTextBounds(Text, Library.Font, 14)
		Library.WatermarkText.Text = Text
		Library.Watermark.Size = UDim2.new(0, X + 15, 0, (Y * 1.5) + 3)
	end

	function Library:ManuallyManagedNotify(Text)
		if shared.Lycoris.silent then
			return
		end

		local XSize, YSize = Library:GetTextBounds(Text, Library.Font, 14)

		YSize = YSize + 7

		local NotifyOuter = Library:Create("Frame", {
			BorderColor3 = Color3.new(0, 0, 0),
			Position = UDim2.new(0, 100, 0, 10),
			Size = UDim2.new(0, 0, 0, YSize),
			ClipsDescendants = true,
			ZIndex = 100,
			Parent = Library.NotificationArea,
		})

		local NotifyInner = Library:Create("Frame", {
			BackgroundColor3 = Library.MainColor,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 101,
			Parent = NotifyOuter,
		})

		Library:AddToRegistry(NotifyInner, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "OutlineColor",
		}, true)

		local InnerFrame = Library:Create("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Position = UDim2.new(0, 1, 0, 1),
			Size = UDim2.new(1, -2, 1, -2),
			ZIndex = 102,
			Parent = NotifyInner,
		})

		local Gradient = Library:Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
				ColorSequenceKeypoint.new(1, Library.MainColor),
			}),
			Rotation = -90,
			Parent = InnerFrame,
		})

		Library:AddToRegistry(Gradient, {
			Color = function()
				return ColorSequence.new({
					ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
					ColorSequenceKeypoint.new(1, Library.MainColor),
				})
			end,
		})

		local NotifyLabel = Library:CreateLabel({
			Position = UDim2.new(0, 4, 0, 0),
			Size = UDim2.new(1, -4, 1, 0),
			Text = Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 14,
			ZIndex = 103,
			Parent = InnerFrame,
		})

		local LeftColor = Library:Create("Frame", {
			BackgroundColor3 = Library.AccentColor,
			BorderSizePixel = 0,
			Position = UDim2.new(0, -1, 0, -1),
			Size = UDim2.new(0, 3, 1, 2),
			ZIndex = 104,
			Parent = NotifyOuter,
		})

		Library:AddToRegistry(LeftColor, {
			BackgroundColor3 = "AccentColor",
		}, true)

		pcall(NotifyOuter.TweenSize, NotifyOuter, UDim2.new(0, XSize + 8 + 4, 0, YSize), "Out", "Quad", 0.4, true)

		local TweenOutCalled = false

		local function TweenOut()
			if TweenOutCalled then
				return
			end

			TweenOutCalled = true

			pcall(NotifyOuter.TweenSize, NotifyOuter, UDim2.new(0, 0, 0, YSize), "Out", "Quad", 0.4, true)

			task.wait(0.4)

			NotifyOuter:Destroy()
		end

		local Connection = nil
		local Connection2 = nil

		Connection = InnerFrame.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				TweenOut()
				Connection:Disconnect()
			end
		end)

		Connection2 = InnerFrame.MouseEnter:Connect(function()
			if game:GetService("UserInputService"):IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				TweenOut()
				Connection2:Disconnect()
			end
		end)

		return TweenOut
	end

	function Library:Notify(Text, Time)
		if shared.Lycoris.silent then
			return
		end

		local XSize, YSize = Library:GetTextBounds(Text, Library.Font, 14)

		YSize = YSize + 7

		local NotifyOuter = Library:Create("Frame", {
			BorderColor3 = Color3.new(0, 0, 0),
			Position = UDim2.new(0, 100, 0, 10),
			Size = UDim2.new(0, 0, 0, YSize),
			ClipsDescendants = true,
			ZIndex = 100,
			Parent = Library.NotificationArea,
		})

		local NotifyInner = Library:Create("Frame", {
			BackgroundColor3 = Library.MainColor,
			BorderColor3 = Library.OutlineColor,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 101,
			Parent = NotifyOuter,
		})

		Library:AddToRegistry(NotifyInner, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "OutlineColor",
		}, true)

		local InnerFrame = Library:Create("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Position = UDim2.new(0, 1, 0, 1),
			Size = UDim2.new(1, -2, 1, -2),
			ZIndex = 102,
			Parent = NotifyInner,
		})

		local Gradient = Library:Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
				ColorSequenceKeypoint.new(1, Library.MainColor),
			}),
			Rotation = -90,
			Parent = InnerFrame,
		})

		Library:AddToRegistry(Gradient, {
			Color = function()
				return ColorSequence.new({
					ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
					ColorSequenceKeypoint.new(1, Library.MainColor),
				})
			end,
		})

		local NotifyLabel = Library:CreateLabel({
			Position = UDim2.new(0, 4, 0, 0),
			Size = UDim2.new(1, -4, 1, 0),
			Text = Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 14,
			ZIndex = 103,
			Parent = InnerFrame,
		})

		local LeftColor = Library:Create("Frame", {
			BackgroundColor3 = Library.AccentColor,
			BorderSizePixel = 0,
			Position = UDim2.new(0, -1, 0, -1),
			Size = UDim2.new(0, 3, 1, 2),
			ZIndex = 104,
			Parent = NotifyOuter,
		})

		Library:AddToRegistry(LeftColor, {
			BackgroundColor3 = "AccentColor",
		}, true)

		pcall(NotifyOuter.TweenSize, NotifyOuter, UDim2.new(0, XSize + 8 + 4, 0, YSize), "Out", "Quad", 0.4, true)

		local function TweenOut()
			pcall(NotifyOuter.TweenSize, NotifyOuter, UDim2.new(0, 0, 0, YSize), "Out", "Quad", 0.4, true)

			task.wait(0.4)

			NotifyOuter:Destroy()
		end

		local Connection = nil
		local Connection2 = nil

		Connection = InnerFrame.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				TweenOut()
				Connection:Disconnect()
			end
		end)

		Connection2 = InnerFrame.MouseEnter:Connect(function()
			if game:GetService("UserInputService"):IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				TweenOut()
				Connection2:Disconnect()
			end
		end)

		task.spawn(function()
			task.wait(Time or 5)

			TweenOut()
		end)
	end

	function Library:CreateWindow(...)
		local Arguments = { ... }
		local Config = { AnchorPoint = Vector2.zero }

		if type(...) == "table" then
			Config = ...
		else
			Config.Title = Arguments[1]
			Config.AutoShow = Arguments[2] or false
		end

		if type(Config.Title) ~= "string" then
			Config.Title = "No title"
		end
		if type(Config.TabPadding) ~= "number" then
			Config.TabPadding = 0
		end
		if type(Config.MenuFadeTime) ~= "number" then
			Config.MenuFadeTime = 0.2
		end

		if typeof(Config.Position) ~= "UDim2" then
			Config.Position = UDim2.fromOffset(175, 50)
		end
		if typeof(Config.Size) ~= "UDim2" then
			Config.Size = UDim2.fromOffset(550, 600)
		end

		if Config.Center then
			Config.AnchorPoint = Vector2.new(0.5, 0.5)
			Config.Position = UDim2.fromScale(0.5, 0.5)
		end

		local Window = {
			Tabs = {},
		}

		local Outer = Library:Create("Frame", {
			AnchorPoint = Config.AnchorPoint,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			Position = Config.Position,
			Size = Config.Size,
			Visible = false,
			ZIndex = 1,
			Parent = ScreenGui,
		})

		Library:MakeDraggable(Outer, 25)

		local Inner = Library:Create("Frame", {
			BackgroundColor3 = Library.MainColor,
			BorderColor3 = Library.AccentColor,
			BorderMode = Enum.BorderMode.Inset,
			Position = UDim2.new(0, 1, 0, 1),
			Size = UDim2.new(1, -2, 1, -2),
			ZIndex = 1,
			Parent = Outer,
		})

		Library:AddToRegistry(Inner, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "AccentColor",
		})

		local WindowLabel = Library:CreateLabel({
			Position = UDim2.new(0, 7, 0, 0),
			Size = UDim2.new(0, 0, 0, 25),
			Text = Config.Title or "",
			TextColor3 = Library.AccentColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 1,
			Parent = Inner,
		})

		Library:AddToRegistry(WindowLabel, {
			TextColor3 = "AccentColor",
		})

		local MainSectionOuter = Library:Create("Frame", {
			BackgroundColor3 = Library.BackgroundColor,
			BorderColor3 = Library.OutlineColor,
			Position = UDim2.new(0, 8, 0, 25),
			Size = UDim2.new(1, -16, 1, -33),
			ZIndex = 1,
			Parent = Inner,
		})

		Library:AddToRegistry(MainSectionOuter, {
			BackgroundColor3 = "BackgroundColor",
			BorderColor3 = "OutlineColor",
		})

		local MainSectionInner = Library:Create("Frame", {
			BackgroundColor3 = Library.BackgroundColor,
			BorderColor3 = Color3.new(0, 0, 0),
			BorderMode = Enum.BorderMode.Inset,
			Position = UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 1,
			Parent = MainSectionOuter,
		})

		Library:AddToRegistry(MainSectionInner, {
			BackgroundColor3 = "BackgroundColor",
		})

		local TabArea = Library:Create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 8, 0, 8),
			Size = UDim2.new(1, -16, 0, 21),
			ZIndex = 1,
			Parent = MainSectionInner,
		})

		local TabListLayout = Library:Create("UIListLayout", {
			Padding = UDim.new(0, Config.TabPadding),
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = TabArea,
		})

		local TabContainer = Library:Create("Frame", {
			BackgroundColor3 = Library.MainColor,
			BorderColor3 = Library.OutlineColor,
			Position = UDim2.new(0, 8, 0, 30),
			Size = UDim2.new(1, -16, 1, -38),
			ZIndex = 2,
			Parent = MainSectionInner,
		})

		Library:AddToRegistry(TabContainer, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "OutlineColor",
		})

		function Window:SetWindowTitle(Title)
			WindowLabel.Text = Title
		end

		---Add a tab to the window.
		---@param Name string
		---@return table
		function Window:AddTab(Name)
			local Tab = {
				GroupboxCount = 0,
				TabboxCount = 0,
				Groupboxes = {},
				Tabboxes = {},
			}

			local TabButtonWidth = Library:GetTextBounds(Name, Library.Font, 16)

			local TabButton = Library:Create("Frame", {
				BackgroundColor3 = Library.BackgroundColor,
				BorderColor3 = Library.OutlineColor,
				Size = UDim2.new(0, TabButtonWidth + 8 + 4, 1, 0),
				ZIndex = 1,
				Parent = TabArea,
			})

			Library:AddToRegistry(TabButton, {
				BackgroundColor3 = "BackgroundColor",
				BorderColor3 = "OutlineColor",
			})

			local TabButtonLabel = Library:CreateLabel({
				Position = UDim2.new(0, 0, 0, 0),
				Size = UDim2.new(1, 0, 1, -1),
				Text = Name,
				ZIndex = 1,
				Parent = TabButton,
			})

			local Blocker = Library:Create("Frame", {
				BackgroundColor3 = Library.MainColor,
				BorderSizePixel = 0,
				Position = UDim2.new(0, 0, 1, 0),
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundTransparency = 1,
				ZIndex = 3,
				Parent = TabButton,
			})

			Library:AddToRegistry(Blocker, {
				BackgroundColor3 = "MainColor",
			})

			local TabFrame = Library:Create("Frame", {
				Name = "TabFrame",
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 0, 0, 0),
				Size = UDim2.new(1, 0, 1, 0),
				Visible = false,
				ZIndex = 2,
				Parent = TabContainer,
			})

			local LeftSide = Library:Create("ScrollingFrame", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.new(0, 8 - 1, 0, 8 - 1),
				Size = UDim2.new(0.5, -12 + 2, 0, 507 + 2),
				CanvasSize = UDim2.new(0, 0, 0, 0),
				BottomImage = "",
				TopImage = "",
				ScrollBarThickness = 0,
				ZIndex = 2,
				Parent = TabFrame,
			})

			local RightSide = Library:Create("ScrollingFrame", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.new(0.5, 4 + 1, 0, 8 - 1),
				Size = UDim2.new(0.5, -12 + 2, 0, 507 + 2),
				CanvasSize = UDim2.new(0, 0, 0, 0),
				BottomImage = "",
				TopImage = "",
				ScrollBarThickness = 0,
				ZIndex = 2,
				Parent = TabFrame,
			})

			Library:Create("UIListLayout", {
				Padding = UDim.new(0, 8),
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Parent = LeftSide,
			})

			Library:Create("UIListLayout", {
				Padding = UDim.new(0, 8),
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Parent = RightSide,
			})

			for _, Side in next, { LeftSide, RightSide } do
				Side:WaitForChild("UIListLayout"):GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
					Side.CanvasSize = UDim2.fromOffset(0, Side.UIListLayout.AbsoluteContentSize.Y)
				end)
			end

			function Tab:ShowTab()
				for _, Tab in next, Window.Tabs do
					Tab:HideTab()
				end

				Blocker.BackgroundTransparency = 0
				TabButton.BackgroundColor3 = Library.MainColor
				Library.RegistryMap[TabButton].Properties.BackgroundColor3 = "MainColor"
				TabFrame.Visible = true
			end

			function Tab:HideTab()
				Blocker.BackgroundTransparency = 1
				TabButton.BackgroundColor3 = Library.BackgroundColor
				Library.RegistryMap[TabButton].Properties.BackgroundColor3 = "BackgroundColor"
				TabFrame.Visible = false
			end

			function Tab:SetLayoutOrder(Position)
				TabButton.LayoutOrder = Position
				TabListLayout:ApplyLayout()
			end

			function Tab:AddGroupbox(Info)
				local Groupbox = { Name = Info.Name }

				local BoxOuter = Library:Create("Frame", {
					BackgroundColor3 = Library.BackgroundColor,
					BorderColor3 = Library.OutlineColor,
					BorderMode = Enum.BorderMode.Inset,
					Size = UDim2.new(1, 0, 0, 507 + 2),
					ZIndex = 2,
					Parent = Info.Side == 1 and LeftSide or RightSide,
				})

				Library:AddToRegistry(BoxOuter, {
					BackgroundColor3 = "BackgroundColor",
					BorderColor3 = "OutlineColor",
				})

				local BoxInner = Library:Create("Frame", {
					BackgroundColor3 = Library.BackgroundColor,
					BorderColor3 = Color3.new(0, 0, 0),
					-- BorderMode = Enum.BorderMode.Inset;
					Size = UDim2.new(1, -2, 1, -2),
					Position = UDim2.new(0, 1, 0, 1),
					ZIndex = 4,
					Parent = BoxOuter,
				})

				Library:AddToRegistry(BoxInner, {
					BackgroundColor3 = "BackgroundColor",
				})

				local Highlight = Library:Create("Frame", {
					BackgroundColor3 = Library.AccentColor,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 2),
					ZIndex = 5,
					Parent = BoxInner,
				})

				Library:AddToRegistry(Highlight, {
					BackgroundColor3 = "AccentColor",
				})

				local GroupboxLabel = Library:CreateLabel({
					Size = UDim2.new(1, 0, 0, 18),
					Position = UDim2.new(0, 4, 0, 2),
					TextSize = 14,
					Text = Info.Name,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 5,
					Parent = BoxInner,
				})

				local Container = Library:Create("Frame", {
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 4, 0, 20),
					Size = UDim2.new(1, -4, 1, -20),
					ZIndex = 1,
					Parent = BoxInner,
				})

				Library:Create("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Parent = Container,
				})

				function Groupbox:Resize()
					local Size = 0

					for _, Element in next, Groupbox.Container:GetChildren() do
						if (not Element:IsA("UIListLayout")) and Element.Visible then
							Size = Size + Element.Size.Y.Offset
						end
					end

					BoxOuter.Size = UDim2.new(1, 0, 0, 20 + Size + 2 + 2)
				end

				Groupbox.Container = Container
				setmetatable(Groupbox, BaseGroupbox)

				Groupbox:AddBlank(3)
				Groupbox:Resize()

				Tab.GroupboxCount = Tab.GroupboxCount + 1
				Tab.Groupboxes[Info.Name] = Groupbox

				return Groupbox
			end

			function Tab:AddDynamicGroupbox(Name)
				if (Tab.GroupboxCount + Tab.TabboxCount) % 2 == 0 then
					return Tab:AddLeftGroupbox(Name)
				else
					return Tab:AddRightGroupbox(Name)
				end
			end

			function Tab:AddLeftGroupbox(Name)
				return Tab:AddGroupbox({ Side = 1, Name = Name })
			end

			function Tab:AddRightGroupbox(Name)
				return Tab:AddGroupbox({ Side = 2, Name = Name })
			end

			function Tab:AddTabbox(Info)
				local Tabbox = {
					Tabs = {},
				}

				local BoxOuter = Library:Create("Frame", {
					BackgroundColor3 = Library.BackgroundColor,
					BorderColor3 = Library.OutlineColor,
					BorderMode = Enum.BorderMode.Inset,
					Size = UDim2.new(1, 0, 0, 0),
					ZIndex = 2,
					Parent = Info.Side == 1 and LeftSide or RightSide,
				})

				Library:AddToRegistry(BoxOuter, {
					BackgroundColor3 = "BackgroundColor",
					BorderColor3 = "OutlineColor",
				})

				local BoxInner = Library:Create("Frame", {
					BackgroundColor3 = Library.BackgroundColor,
					BorderColor3 = Color3.new(0, 0, 0),
					-- BorderMode = Enum.BorderMode.Inset;
					Size = UDim2.new(1, -2, 1, -2),
					Position = UDim2.new(0, 1, 0, 1),
					ZIndex = 4,
					Parent = BoxOuter,
				})

				Library:AddToRegistry(BoxInner, {
					BackgroundColor3 = "BackgroundColor",
				})

				local Highlight = Library:Create("Frame", {
					BackgroundColor3 = Library.AccentColor,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 2),
					ZIndex = 10,
					Parent = BoxInner,
				})

				Library:AddToRegistry(Highlight, {
					BackgroundColor3 = "AccentColor",
				})

				local TabboxButtons = Library:Create("Frame", {
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 0, 0, 1),
					Size = UDim2.new(1, 0, 0, 18),
					ZIndex = 5,
					Parent = BoxInner,
				})

				Library:Create("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Left,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Parent = TabboxButtons,
				})

				function Tabbox:AddTab(Name)
					local Tab = {}

					local Button = Library:Create("Frame", {
						BackgroundColor3 = Library.MainColor,
						BorderColor3 = Color3.new(0, 0, 0),
						Size = UDim2.new(0.5, 0, 1, 0),
						ZIndex = 6,
						Parent = TabboxButtons,
					})

					Library:AddToRegistry(Button, {
						BackgroundColor3 = "MainColor",
					})

					local ButtonLabel = Library:CreateLabel({
						Size = UDim2.new(1, 0, 1, 0),
						TextSize = 14,
						Text = Name,
						TextXAlignment = Enum.TextXAlignment.Center,
						ZIndex = 7,
						Parent = Button,
					})

					local Block = Library:Create("Frame", {
						BackgroundColor3 = Library.BackgroundColor,
						BorderSizePixel = 0,
						Position = UDim2.new(0, 0, 1, 0),
						Size = UDim2.new(1, 0, 0, 1),
						Visible = false,
						ZIndex = 9,
						Parent = Button,
					})

					Library:AddToRegistry(Block, {
						BackgroundColor3 = "BackgroundColor",
					})

					local Container = Library:Create("Frame", {
						BackgroundTransparency = 1,
						Position = UDim2.new(0, 4, 0, 20),
						Size = UDim2.new(1, -4, 1, -20),
						ZIndex = 1,
						Visible = false,
						Parent = BoxInner,
					})

					Library:Create("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Parent = Container,
					})

					function Tab:Show()
						for _, Tab in next, Tabbox.Tabs do
							Tab:Hide()
						end

						Container.Visible = true
						Block.Visible = true

						Button.BackgroundColor3 = Library.BackgroundColor
						Library.RegistryMap[Button].Properties.BackgroundColor3 = "BackgroundColor"

						Tab:Resize()
					end

					function Tab:Hide()
						Container.Visible = false
						Block.Visible = false

						Button.BackgroundColor3 = Library.MainColor
						Library.RegistryMap[Button].Properties.BackgroundColor3 = "MainColor"
					end

					function Tab:Resize()
						local TabCount = 0

						for _, Tab in next, Tabbox.Tabs do
							TabCount = TabCount + 1
						end

						for _, Button in next, TabboxButtons:GetChildren() do
							if not Button:IsA("UIListLayout") then
								Button.Size = UDim2.new(1 / TabCount, 0, 1, 0)
							end
						end

						if not Container.Visible then
							return
						end

						local Size = 0

						for _, Element in next, Tab.Container:GetChildren() do
							if (not Element:IsA("UIListLayout")) and Element.Visible then
								Size = Size + Element.Size.Y.Offset
							end
						end

						BoxOuter.Size = UDim2.new(1, 0, 0, 20 + Size + 2 + 2)
					end

					Button.InputBegan:Connect(function(Input)
						if
							(
								Input.UserInputType == Enum.UserInputType.Touch
								or Input.UserInputType == Enum.UserInputType.MouseButton1
							) and not Library:MouseIsOverOpenedFrame()
						then
							Tab:Show()
							Tab:Resize()
						end
					end)

					Tab.Container = Container
					Tabbox.Tabs[Name] = Tab

					setmetatable(Tab, BaseGroupbox)

					Tab:AddBlank(3)
					Tab:Resize()

					-- Show first tab (number is 2 cus of the UIListLayout that also sits in that instance)
					if #TabboxButtons:GetChildren() == 2 then
						Tab:Show()
					end

					return Tab
				end

				Tab.Tabboxes[Info.Name or ""] = Tabbox
				Tab.TabboxCount = Tab.TabboxCount + 1

				return Tabbox
			end

			function Tab:AddLeftTabbox(Name)
				return Tab:AddTabbox({ Name = Name, Side = 1 })
			end

			function Tab:AddRightTabbox(Name)
				return Tab:AddTabbox({ Name = Name, Side = 2 })
			end

			function Tab:AddDynamicTabbox(Name)
				if (Tab.GroupboxCount + Tab.TabboxCount) % 2 == 0 then
					return Tab:AddLeftTabbox(Name)
				else
					return Tab:AddRightTabbox(Name)
				end
			end

			TabButton.InputBegan:Connect(function(Input)
				if
					Input.UserInputType == Enum.UserInputType.Touch
					or Input.UserInputType == Enum.UserInputType.MouseButton1
				then
					Tab:ShowTab()
				end
			end)

			-- This was the first tab added, so we show it by default.
			if #TabContainer:GetChildren() == 1 then
				Tab:ShowTab()
			end

			Window.Tabs[Name] = Tab
			return Tab
		end

		local ModalElement = Library:Create("TextButton", {
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 0, 0, 0),
			Visible = true,
			Text = "",
			Modal = false,
			Parent = ScreenGui,
		})

		local TransparencyCache = {}
		local Fading = false
		local FirstTime = false

		function Library:Toggle()
			if Fading then
				return
			end

			local FadeTime = Config.MenuFadeTime
			local ShouldFade = FadeTime > 0.01

			if ShouldFade then
				Fading = true
			end

			Toggled = not Toggled
			ModalElement.Modal = Toggled

			if Toggled then
				Outer.Visible = true
			end

			if not Toggled then
				for _, ColorPicker in next, ColorPickers do
					ColorPicker:Hide()
				end

				for _, ContextMenu in next, ContextMenus do
					ContextMenu:Hide()
				end

				for _, Tooltip in next, Tooltips do
					Tooltip.Visible = false
				end

				for _, ModeSelectFrame in next, ModeSelectFrames do
					ModeSelectFrame.Visible = false
				end
			end

			if ShouldFade or not FirstTime then
				for _, Desc in next, Outer:GetDescendants() do
					local Properties = {}

					if Desc:IsA("ImageLabel") then
						table.insert(Properties, "ImageTransparency")
						table.insert(Properties, "BackgroundTransparency")
					elseif Desc:IsA("TextLabel") or Desc:IsA("TextBox") then
						table.insert(Properties, "TextTransparency")
					elseif Desc:IsA("Frame") or Desc:IsA("ScrollingFrame") then
						table.insert(Properties, "BackgroundTransparency")
					elseif Desc:IsA("UIStroke") then
						table.insert(Properties, "Transparency")
					end

					local Cache = TransparencyCache[Desc]

					if not Cache then
						Cache = {}
						TransparencyCache[Desc] = Cache
					end

					for _, Prop in next, Properties do
						if not Cache[Prop] then
							Cache[Prop] = Desc[Prop]
						end

						if Cache[Prop] == 1 then
							continue
						end

						TweenService:Create(
							Desc,
							TweenInfo.new(FadeTime, Enum.EasingStyle.Linear),
							{ [Prop] = Toggled and Cache[Prop] or 1 }
						):Play()
					end
				end

				task.wait(FadeTime)

				FirstTime = true
			end

			Outer.Visible = Toggled

			Fading = false
		end

		Library:GiveSignal(InputService.InputBegan:Connect(function(Input, Processed)
			if type(Library.ToggleKeybind) == "table" and Library.ToggleKeybind.Type == "KeyPicker" then
				if
					(
						Input.UserInputType == Enum.UserInputType.Touch
						or Input.UserInputType == Enum.UserInputType.Keyboard
					) and Input.KeyCode.Name == Library.ToggleKeybind.Value
				then
					task.spawn(Library.Toggle)
				end
			elseif
				Input.KeyCode == Enum.KeyCode.RightControl
				or (Input.KeyCode == Enum.KeyCode.RightShift and not Processed)
			then
				task.spawn(Library.Toggle)
			end
		end))

		if Config.AutoShow then
			task.spawn(Library.Toggle)
		end

		Library.KeybindFrame.Visible = not shared.Lycoris.silent
		Library.Watermark.Visible = not shared.Lycoris.silent
		Window.Holder = Outer

		return Window
	end

	local function OnPlayerChange()
		local PlayerList = GetPlayersString()

		for _, Value in next, Options do
			if Value.Type == "Dropdown" and Value.SpecialType == "Player" then
				Value:SetValues(PlayerList)
			end
		end
	end

	Players.PlayerAdded:Connect(OnPlayerChange)
	Players.PlayerRemoving:Connect(OnPlayerChange)

	return Library
end)()

end)
__bundle_register("Game/Timings/SaveManager", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Game.Timings.TimingSave
local TimingSave = require("Game/Timings/TimingSave")

---@module Game.Timings.TimingContainerPair
local TimingContainerPair = require("Game/Timings/TimingContainerPair")

---@module Game.Timings.TimingContainer
local TimingContainer = require("Game/Timings/TimingContainer")

---@module Game.Timings.AnimationTiming
local AnimationTiming = require("Game/Timings/AnimationTiming")

---@module Game.Timings.PartTiming
local PartTiming = require("Game/Timings/PartTiming")

---@module Game.Timings.SoundTiming
local SoundTiming = require("Game/Timings/SoundTiming")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.Signal
local Signal = require("Utility/Signal")

-- SaveManager module.
local SaveManager = { llc = nil, llcn = nil, lct = nil }

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Utility.Filesystem
local Filesystem = require("Utility/Filesystem")

---@module Utility.Deserializer
local Deserializer = require("Utility/Deserializer")

---@module Utility.String
local String = require("Utility/String")

---@module Utility.Serializer
local Serializer = require("Utility/Serializer")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Game.Timings.InternalTimingData
local InternalTimingData = require("Game/Timings/InternalTimingData")

-- Manager filesystem.
local fs = Filesystem.new("Lycoris-Rewrite-TypeSoul-Timings")

-- Current timing save.
local config = TimingSave.new()

-- Services.
local runService = game:GetService("RunService")

-- Maids.
local saveMaid = Maid.new()

---Try loading embedded internal timing data (generated at build time by embed_timings.js).
---@param animationContainer TimingContainer
---@param partContainer TimingContainer
---@param soundContainer TimingContainer
---@return boolean
local function loadEmbeddedInternalTimings(animationContainer, partContainer, soundContainer)
	local rawData = InternalTimingData
	if not rawData or type(rawData) ~= "string" or #rawData == 0 then
		return false
	end

	local decodeOk, decodeResult = pcall(Deserializer.unmarshal_one, String.tba(rawData))
	if not decodeOk or typeof(decodeResult) ~= "table" then
		Logger.warn("Failed to deserialize embedded timing data: %s", tostring(decodeResult))
		return false
	end
	local loadOk, loadErr = pcall(function()
		animationContainer:load(decodeResult.animation or {})
		partContainer:load(decodeResult.part or {})
		soundContainer:load(decodeResult.sound or {})
	end)

	if not loadOk then
		Logger.warn("Failed to load embedded timing data: %s", tostring(loadErr))
		return false
	end

	Logger.notify("Internal timing seed loaded from embedded data.")
	return true
end

---Get save files list.
---@return table
function SaveManager.list()
	local list = fs:list(true)
	local out = {}

	for idx = 1, #list do
		local file = list[idx]

		if file:sub(-4) ~= ".txt" then
			continue
		end

		local pos = file:find(".txt", 1, true)
		local char = file:sub(pos, pos)
		local start = pos

		while char ~= "/" and char ~= "\\" and char ~= "" do
			pos = pos - 1
			char = file:sub(pos, pos)
		end

		if char == "/" or char == "\\" then
			table.insert(out, file:sub(pos + 1, start - 1))
		end
	end

	return out
end

---Merge with current config.
---@param name string
---@param type MergeType
function SaveManager.merge(name, type)
	if not name or #name <= 0 then
		return Logger.longNotify("Config name cannot be empty.")
	end

	local success, result = pcall(fs.read, fs, name .. ".txt")

	if not success then
		Logger.longNotify("Failed to read config file %s.", name)

		return Logger.warn("Timing manager ran into the error '%s' while attempting to read config %s.", result, name)
	end

	success, result = pcall(Deserializer.unmarshal_one, String.tba(result))

	if not success then
		Logger.longNotify("Failed to deserialize config file %s.", name)

		return Logger.warn(
			"Timing manager ran into the error '%s' while attempting to deserialize config %s.",
			result,
			name
		)
	end

	if typeof(result) ~= "table" then
		Logger.longNotify("Failed to load config file %s.", name)

		return Logger.warn("Timing manager failed to load config %s with result %s.", name, tostring(result))
	end

	config:merge(TimingSave.new(result), type)

	Logger.notify("Config file %s has merged with the loaded one.", name)
end

---Refresh dropdown values with timing data.
---@param dropdown table
function SaveManager.refresh(dropdown)
	dropdown:SetValues(SaveManager.list())
end

---Set config name as auto-load.
---@param name string
function SaveManager.autoload(name)
	if not name or #name <= 0 then
		return Logger.longNotify("Config name cannot be empty.")
	end

	local success, result = pcall(fs.write, fs, "autoload.txt", name)

	if not success then
		Logger.longNotify("Failed to write autoload file %s.", name)

		return Logger.warn(
			"Timing manager ran into the error '%s' while attempting to write autoload file %s.",
			result,
			name
		)
	end

	Logger.notify("Config file %s has set to auto-load.", name)
end

---Create timing as config name.
---@param name string
function SaveManager.create(name)
	if not name or #name <= 0 then
		return Logger.longNotify("Config name cannot be empty.")
	end

	if fs:file(name .. ".txt") then
		return Logger.longNotify("Config file %s already exists.", name)
	end

	SaveManager.write(name)
end

---Save timing as config name.
---@param name string
function SaveManager.save(name)
	if not name or #name <= 0 then
		return Logger.longNotify("Config name cannot be empty.")
	end

	if not fs:file(name .. ".txt") then
		return Logger.longNotify("Config file %s does not exist.", name)
	end

	SaveManager.write(name)
end

---Write timing as config name.
---@param name string
---@return number
function SaveManager.write(name)
	if not name or #name <= 0 then
		return -1, Logger.longNotify("Config name cannot be empty.")
	end

	local success, result = pcall(Serializer.marshal, config:serialize())

	if not success then
		Logger.longNotify("Failed to serialize config file %s.", name)

		return -2,
			Logger.warn("Timing manager ran into the error '%s' while attempting to serialize config %s.", result, name)
	end

	success, result = pcall(fs.write, fs, name .. ".txt", result)

	if not success then
		Logger.longNotify("Failed to write config file %s.", name)

		return -3,
			Logger.warn("Timing manager ran into the error '%s' while attempting to write config %s.", result, name)
	end

	Logger.notify("Config file %s has written to.", name)

	return 0
end

---Clear config from config name.
---@param name string
function SaveManager.clear(name)
	if not name or #name <= 0 then
		return Logger.longNotify("Config name cannot be empty.")
	end

	local success, result = pcall(Serializer.marshal, TimingSave.new():serialize())

	if not success then
		Logger.longNotify("Failed to serialize config file %s.", name)

		return Logger.warn(
			"Timing manager ran into the error '%s' while attempting to serialize config %s.",
			result,
			name
		)
	end

	success, result = pcall(fs.write, fs, name .. ".txt", result)

	if not success then
		Logger.longNotify("Failed to write config file %s.", name)

		return Logger.warn("Timing manager ran into the error '%s' while attempting to write config %s.", result, name)
	end

	Logger.notify("Config file %s has cleared.", name)
end

---Load timing from config name.
---@param name string
function SaveManager.load(name)
	local timestamp = os.clock()

	if not name or #name <= 0 then
		return Logger.longNotify("Config name cannot be empty.")
	end

	local success, result = pcall(fs.read, fs, name .. ".txt")

	if not success then
		Logger.longNotify("Failed to read config file %s.", name)

		return Logger.warn("Timing manager ran into the error '%s' while attempting to read config %s.", result, name)
	end

	success, result = pcall(Deserializer.unmarshal_one, String.tba(result))

	if not success then
		Logger.longNotify("Failed to deserialize config file %s.", name)

		return Logger.warn(
			"Timing manager ran into the error '%s' while attempting to deserialize config %s.",
			result,
			name
		)
	end

	if typeof(result) ~= "table" then
		Logger.longNotify("Failed to process config file %s.", name)

		return Logger.warn("Timing manager failed to process config %s with result %s.", name, tostring(result))
	end

	config:clear()

	success, result = pcall(config.load, config, result)

	if not success then
		Logger.longNotify("Failed to load config file %s.", name)

		return Logger.warn("Timing manager ran into the error '%s' while attempting to load config %s.", result, name)
	end

	Logger.notify(
		"Config file %s has loaded with %i timings in %.2f seconds.",
		name,
		config:count(),
		os.clock() - timestamp
	)

	SaveManager.llc = config:clone()
	SaveManager.llcn = name
end

---Initialize SaveManager.
function SaveManager.init()
	local timestamp = os.clock()
	local preRenderSignal = Signal.new(runService.PreRender)

	-- Create internal timing containers.
	local internalAnimationContainer = TimingContainer.new(AnimationTiming.new())
	local internalPartContainer = TimingContainer.new(PartTiming.new())
	local internalSoundContainer = TimingContainer.new(SoundTiming.new())

	-- Seed from embedded timing data when available; otherwise keep empty internal timings.
	if not loadEmbeddedInternalTimings(internalAnimationContainer, internalPartContainer, internalSoundContainer) then
		internalAnimationContainer:load({})
		internalPartContainer:load({})
		internalSoundContainer:load({})
	end

	-- Count up internal timings.
	local internalCount = internalAnimationContainer:count()
		+ internalPartContainer:count()
		+ internalSoundContainer:count()

	Logger.notify(
		"Internal timings have loaded with %i timings in %.2f seconds.",
		internalCount,
		os.clock() - timestamp
	)

	-- Attempt to read auto-load config.
	local success, result = pcall(fs.read, fs, "autoload.txt")

	-- Load auto-load config if it exists.
	if success and result then
		SaveManager.load(result)
	end

	-- Animation stack.
	SaveManager.as = TimingContainerPair.new(internalAnimationContainer, config:get().animation)

	-- Part stack.
	SaveManager.ps = TimingContainerPair.new(internalPartContainer, config:get().part)

	-- Sound stack.
	SaveManager.ss = TimingContainerPair.new(internalSoundContainer, config:get().sound)

	-- Run auto save.
	saveMaid:add(preRenderSignal:connect("SaveManager_AutoSave", function()
		local llc = SaveManager.llc
		if not llc then
			return
		end

		local llcn = SaveManager.llcn
		if not llcn then
			return
		end

		if not Configuration.expectToggleValue("PeriodicAutoSave") then
			return
		end

		if
			SaveManager.lct
			and os.clock() - SaveManager.lct < (Configuration.expectOptionValue("PeriodicAutoSaveInterval") or 60)
		then
			return
		end

		SaveManager.lct = os.clock()

		if config:equals(llc) then
			return
		end

		Logger.warn("Auto-saving timings to '%s' config file.", SaveManager.llcn)

		SaveManager.write(SaveManager.llcn)

		SaveManager.llc = config:clone()

		Logger.notify("Timing auto-save has completed successfully.")
	end))
end

---Detach SaveManager.
function SaveManager.detach()
	saveMaid:clean()
end

-- Return SaveManager module.
return SaveManager

end)
__bundle_register("Game/Timings/InternalTimingData", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Auto-generated by embed_timings.js. Do not edit.
-- Source: Timings/truth.txt (338500 bytes)
local b64 = [=[hKRwYXJ03ABA3gATpHVtb2HCpXBuYW1lsUluaXRpYWxUaWRlSGl0Ym94pHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWRChWBChWheqcHVuaXNoYWJsZQCkbmFtZbFJbml0aWFsVGlkZUhpdGJveKRpbXhka6NzbW7Co2ZoYsOkaW1kZB2jdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZbBHcmFuUmV5RXhwbG9zaW9upHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZzKChWMzIoVrMyKR3aGVuzQPUpGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMKkc3JwbsKkYWF0a8KmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lsEdyYW5SZXlFeHBsb3Npb26kaW14ZGCjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWTeABOkdW1vYcKlcG5hbWWvQmFua2FpRmluYWxXYXZlpHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWRmhWCihWhSqcHVuaXNoYWJsZQCkbmFtZa9CYW5rYWlGaW5hbFdhdmWkaW14ZFajc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWTeABOkdW1vYcKlcG5hbWWvV2luZENyb3duSHRpYm94pHNtb2SjTi9Bp2FjdGlvbnOShaVfdHlwZatTdGFydCBCbG9ja6RuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwoWlX3R5cGWpRW5kIEJsb2NrpG5hbWWhMqZoaXRib3iDoVnNASyhWM0BLKFazQEspHdoZW7NAfSkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkUoVgUoVooqnB1bmlzaGFibGUApG5hbWWvV2luZENyb3duSHRpYm94pGlteGR2o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lq05lbENyaXRpY2FspHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZMqFYCqFaCqR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWTihWAqhWgqqcHVuaXNoYWJsZQCkbmFtZatOZWxDcml0aWNhbKRpbXhka6NzbW7Co2ZoYsKkaW1kZBKjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZa9HZW50bGVWZWlsU2xhc2ikc21vZKNOL0GnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkAoVgAoVoApHdoZW4ApGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMOkc3JwbsKkYWF0a8KmaGl0Ym94g6FZKqFYKqFaKqpwdW5pc2hhYmxlAKRuYW1lr0dlbnRsZVZlaWxTbGFzaKRpbXhkzKGjc21uwqNmaGLDpGltZGQdo3RhZ6lVbmRlZmluZWTeABOkdW1vYcKlcG5hbWWrQm9yZWFTcGhlcmWkc21vZKNOL0GnYWN0aW9uc5KFpV90eXBlq1N0YXJ0IEJsb2NrpG5hbWWhMaZoaXRib3iDoVkAoVgAoVoApHdoZW7NAaSkaWhiY8KFpV90eXBlqUVuZCBCbG9ja6RuYW1loTKmaGl0Ym94g6FZSKFYSaFaSKR3aGVuzQGkpGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMOkc3JwbsKkYWF0a8KmaGl0Ym94g6FZKqFYKaFaKKpwdW5pc2hhYmxlAKRuYW1lq0JvcmVhU3BoZXJlpGlteGR2o3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lr0ZpcmVrbmlnaHRzcGVhcqRzbW9ko04vQadhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkJoVgJoVpiqnB1bmlzaGFibGUApG5hbWWvRmlyZWtuaWdodHNwZWFypGlteGTMrKNzbW7Co2ZoYsKkaW1kZE2jdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZaRCYWxhpHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiw6VhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWQmhWAmhWiCqcHVuaXNoYWJsZQCkbmFtZaRCYWxhpGlteGTNAU6jc21uwqNmaGLCpGltZGQSo3RhZ6lVbmRlZmluZWTeABOkdW1vYcKlcG5hbWWsVF9Qcm9qZWN0aWxlpHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWSGhWCChWiCqcHVuaXNoYWJsZQCkbmFtZadEaWFtb25kpGlteGTMzKNzbW7Co2ZoYsOkaW1kZBmjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZatJY2VTaHVyaWtlbqRzbW9ko04vQadhY3Rpb25zkoWlX3R5cGWrU3RhcnQgQmxvY2ukbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KFpV90eXBlqUVuZCBCbG9ja6RuYW1loTKmaGl0Ym94g6FZX6FYY6FaY6R3aGVuzQRMpGloYmPCpG5kZmLCpWFmdGVyAKN1aGPCqXNjcmFtYmxlZMKkZHVpaMOkc3JwbsKkYWF0a8KmaGl0Ym94g6FZC6FYPqFaFKpwdW5pc2hhYmxlAKRuYW1lq0ljZVNodXJpa2VupGlteGTMlqNzbW7Co2ZoYsKkaW1kZCSjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZalQdWxzZUJhbGykc21vZKNOL0GnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkAoVgAoVoApHdoZW4ApGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMOkc3JwbsKkYWF0a8KmaGl0Ym94g6FZH6FYH6FaH6pwdW5pc2hhYmxlAKRuYW1lqVB1bHNlQmFsbKRpbXhka6NzbW7Co2ZoYsKkaW1kZBSjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZbBSb2NrZXRQcm9qZWN0aWxlpHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWQqhWAqhWgaqcHVuaXNoYWJsZQCkbmFtZaVIZWFydKRpbXhka6NzbW7Co2ZoYsOkaW1kZAOjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZatWZXJzY2hBcnJvd6RzbW9ko04vQadhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkKoVgKoVo8qnB1bmlzaGFibGUApG5hbWWrVmVyc2NoQXJyb3ekaW14ZMzMo3NtbsKjZmhiw6RpbWRkRKN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lq0Nlcm9GaXJlZmx5pHNtb2SjTi9Bp2FjdGlvbnOShaVfdHlwZatTdGFydCBCbG9ja6RuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwoWlX3R5cGWpRW5kIEJsb2NrpG5hbWWhMqZoaXRib3iDoVlxoVhwoVpxpHdoZW7NAiakaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkOoVgLoVoOqnB1bmlzaGFibGUApG5hbWWrQ2Vyb0ZpcmVmbHmkaW14ZGujc21uwqNmaGLDpGltZGQCo3RhZ6lVbmRlZmluZWTeABOkdW1vYcKlcG5hbWWoMXN0IHJpbmekc21vZKNOL0GnYWN0aW9uc5GFpV90eXBlpERhc2ikbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkUoVgUoVoUqnB1bmlzaGFibGUApG5hbWWoMXN0IHJpbmekaW14ZGujc21uwqNmaGLCpGltZGQFo3RhZ6lVbmRlZmluZWTeABOkdW1vYcKlcG5hbWWpVm9sbGV5VG9wpHNtb2SjTi9Bp2FjdGlvbnOShaVfdHlwZatTdGFydCBCbG9ja6RuYW1loTGmaGl0Ym94g6FZSKFYKaFaKKR3aGVuZKRpaGJjwoWlX3R5cGWpRW5kIEJsb2NrpG5hbWWhMqZoaXRib3iDoVnMoaFYzKShWsykpHdoZW7NCcSkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlowqRzcnBuwqRhYXRrwqZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWmVm9sbGV5pGlteGR2o3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lpVRob3JupHNtb2SjTi9Bp2FjdGlvbnOShaVfdHlwZatTdGFydCBCbG9ja6RuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwoWlX3R5cGWpRW5kIEJsb2NrpG5hbWWhMqZoaXRib3iDoVlJoVhMoVpLpHdoZW7NASykaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkHoVgJoVoJqnB1bmlzaGFibGUApG5hbWWlVGhvcm6kaW14ZFajc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWTeABOkdW1vYcKlcG5hbWW4TWVzaGVzL3VudF9QbGFuZS4wMDEgKDYppHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZHaFYY6FaY6R3aGVuzQH0pGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMKkc3JwbsKkYWF0a8KmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1luE1lc2hlcy91bnRfUGxhbmUuMDAxICg2KaRpbXhkYKNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZatDZXJvQ3ljbG9uZaRzbW9ko04vQadhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkyoVgboVoqqnB1bmlzaGFibGUApG5hbWWrQ2Vyb0N5Y2xvbmWkaW14ZM0BLaNzbW7Co2ZoYsKkaW1kZBCjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZbJDZXJvRmxvb3JJbmRpY2F0b3Kkc21vZKNOL0GnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkqoVgqoVrMyKR3aGVuzQGupGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMKkc3JwbsKkYWF0a8KmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lskNlcm9GbG9vckluZGljYXRvcqRpbXhkzIyjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWTeABOkdW1vYcKlcG5hbWWtRXh0cmljYXRlQmFsbKRzbW9ko04vQadhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkJoVgJoVoJqnB1bmlzaGFibGUApG5hbWWtRXh0cmljYXRlQmFsbKRpbXhkYKNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZapOdWxsaWZ5T3JipHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWRShWBShWstAMAAAIAAAAKpwdW5pc2hhYmxlAKRuYW1lqk51bGxpZnlPcmKkaW14ZM0Br6NzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZbNQdXJnYWJhbGxQcm9qZWN0aWxlpHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWR+hWB+hWjWqcHVuaXNoYWJsZQCkbmFtZadIb2x5T3JipGlteGTMjKNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZa52ZXJ0aWNhbCBzbGFzaKRzbW9ko04vQadhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkooVgUoVoQqnB1bmlzaGFibGUApG5hbWWudmVydGljYWwgc2xhc2ikaW14ZMyso3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lqFphbmdlcmlupHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWQ6hWBKhWhSqcHVuaXNoYWJsZQCkbmFtZahaYW5nZXJpbqRpbXhkdqNzbW7Co2ZoYsOkaW1kZA6jdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZapTbGFzaFRlbXBvpHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWRShWBShWhSqcHVuaXNoYWJsZQCkbmFtZapTbGFzaFRlbXBvpGlteGTM4qNzbW7Co2ZoYsKkaW1kZB2jdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZa1TUktlbmRvU2xhc2gzpHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWRShWB+hWhKqcHVuaXNoYWJsZQCkbmFtZa1TUktlbmRvU2xhc2gzpGlteGRro3NtbsKjZmhiw6RpbWRkEqN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lr1BheWRheVByZVNwaGVyZaRzbW9ko04vQadhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWTyhWDyhWjykd2hlbsyWpGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMKkc3JwbsKkYWF0a8KmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lr1BheWRheVByZVNwaGVyZaRpbXhkVqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZb5UaHVuZGVyQm9sdDEgKyBMaWdodG5pbmdfVHJhaWykc21vZKNOL0GnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkAoVgAoVoApHdoZW4ApGloYmPCpG5kZmLCpWFmdGVyAKN1aGPCqXNjcmFtYmxlZMKkZHVpaMOkc3JwbsKkYWF0a8KmaGl0Ym94g6FZC6FYzIKhWguqcHVuaXNoYWJsZQCkbmFtZb5UaHVuZGVyQm9sdDEgKyBMaWdodG5pbmdfVHJhaWykaW14ZMzio3NtbsKjZmhiwqRpbWRkRKN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lpGNyaXSkc21vZKNOL0GnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkAoVgAoVoApHdoZW4ApGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMOkc3JwbsKkYWF0a8KmaGl0Ym94g6FZD6FYD6FaEqpwdW5pc2hhYmxlAKRuYW1lpGNyaXSkaW14ZGujc21uwqNmaGLDpGltZGQOo3RhZ6lVbmRlZmluZWTeABOkdW1vYcKlcG5hbWWuQ29uc3VtaW5nV2luZHOkc21vZKNOL0GnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkAoVgAoVoApHdoZW7NBbSkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkpoVgpoVopqnB1bmlzaGFibGUApG5hbWWuQ29uc3VtaW5nV2luZHOkaW14ZGCjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWTeABOkdW1vYcKlcG5hbWWwVGVwcHVzYXRzdVdpbmR1cKRzbW9ko04vQadhY3Rpb25zkoWlX3R5cGWrU3RhcnQgQmxvY2ukbmFtZaExpmhpdGJveIOhWRehWB+hWh+kd2hlbs0EsKRpaGJjwoWlX3R5cGWpRW5kIEJsb2NrpG5hbWWhMqZoaXRib3iDoVljoVhjoVpjpHdoZW7NB9CkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlowqRzcnBuwqRhYXRrwqZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWwVGVwcHVzYXRzdVdpbmR1cKRpbXhkNaNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZahHaWZ0QmFsbKRzbW9ko04vQadhY3Rpb25zkoWlX3R5cGWrU3RhcnQgQmxvY2ukbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KFpV90eXBlqUVuZCBCbG9ja6RuYW1loTKmaGl0Ym94g6FZSKFYTKFaS6R3aGVuzQJYpGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMOkc3JwbsKkYWF0a8KmaGl0Ym94g6FZCqFYBqFaEqpwdW5pc2hhYmxlAKRuYW1lqEdpZnRCYWxspGlteGRro3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lrEdsb3J5VG9ybmFkb6RzbW9ko04vQadhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkfoVgfoVoVqnB1bmlzaGFibGUApG5hbWWsR2xvcnlUb3JuYWRvpGlteGTM16NzbW7Co2ZoYsOkaW1kZBSjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZapGb2NhbFBvaW50pHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjwqlzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWQKhWAKhWg+qcHVuaXNoYWJsZQCkbmFtZapGb2NhbFBvaW50pGlteGRgo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1ltUt1eW9TaGliYXJpUHJvamVjdGlsZaRzbW9ko04vQadhY3Rpb25zkoWlX3R5cGWrU3RhcnQgQmxvY2ukbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KFpV90eXBlqUVuZCBCbG9ja6RuYW1loTKmaGl0Ym94g6FZMqFYMqFaMqR3aGVuzQH0pGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMOkc3JwbsKkYWF0a8KmaGl0Ym94g6FZCqFYCqFaFapwdW5pc2hhYmxlAKRuYW1ltUt1eW9TaGliYXJpUHJvamVjdGlsZaRpbXhkzIGjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWTeABOkdW1vYcKlcG5hbWWtU1JLZW5kb1NsYXNoMaRzbW9ko04vQadhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkUoVgfoVoSqnB1bmlzaGFibGUApG5hbWWtU1JLZW5kb1NsYXNoMaRpbXhka6NzbW7Co2ZoYsOkaW1kZBKjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZa9IZWF2ZW5seUNhbm5vbjGkc21vZKNOL0GnYWN0aW9uc5GFpV90eXBlpERhc2ikbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkYoVgVoVofqnB1bmlzaGFibGUApG5hbWWvSGVhdmVubHlDYW5ub24xpGlteGTMzKNzbW7Co2ZoYsOkaW1kZBCjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZalMaWdodG5pbmekc21vZKNOL0GnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkAoVgAoVoApHdoZW7NARikaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkUoVgPoVooqnB1bmlzaGFibGUApG5hbWWpTGlnaHRuaW5npGlteGRro3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lrUFjaWRCYWxsU21hbGykc21vZKNOL0GnYWN0aW9uc5KFpV90eXBlq1N0YXJ0IEJsb2NrpG5hbWWhMaZoaXRib3iDoVkAoVgAoVoApHdoZW4ApGloYmPChaVfdHlwZalFbmQgQmxvY2ukbmFtZaEypmhpdGJveIOhWcyMoVjMjKFazIykd2hlbs0CWKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWWShWGShWmSqcHVuaXNoYWJsZQCkbmFtZa1BY2lkQmFsbFNtYWxspGlteGTMgaNzbW7Co2ZoYsKkaW1kZAqjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZaRCYWxspHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWRChWBChWhyqcHVuaXNoYWJsZQCkbmFtZaRCYWxspGlteGRgo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lrUhhaWVuRmlyZWJhbGykc21vZKNOL0GnYWN0aW9uc5GFpV90eXBlpERhc2ikbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Kpc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkPoVgPoVoPqnB1bmlzaGFibGUApG5hbWWtSGFpZW5GaXJlYmFsbKRpbXhka6NzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZbNDZXJvQ29ybmVhSW5kaWNhdG9ypHNtb2SjTi9Bp2FjdGlvbnOShaVfdHlwZalFbmQgQmxvY2ukbmFtZaExpmhpdGJveIOhWV6hWF6hWl+kd2hlbs0CHKRpaGJjwoWlX3R5cGWrU3RhcnQgQmxvY2ukbmFtZaEypmhpdGJveIOhWV6hWF6hWl+kd2hlbs0BVKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjCpHNycG7CpGFhdGvCpmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZbNDZXJvQ29ybmVhSW5kaWNhdG9ypGlteGRLo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lrVNSS2VuZG9TbGFzaDKkc21vZKNOL0GnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkAoVgAoVoApHdoZW4ApGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMOkc3JwbsKkYWF0a8KmaGl0Ym94g6FZFKFYH6FaEqpwdW5pc2hhYmxlAKRuYW1lrVNSS2VuZG9TbGFzaDKkaW14ZGujc21uwqNmaGLDpGltZGQSo3RhZ6lVbmRlZmluZWTeABOkdW1vYcKlcG5hbWWqU2xpZGVBcnJvd6RzbW9ko04vQadhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQuhWAuhWimkd2hlbszIpGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMOkc3JwbsKkYWF0a8KmaGl0Ym94g6FZB6FYCqFaJKpwdW5pc2hhYmxlAKRuYW1lqlNsaWRlQXJyb3ekaW14ZMyho3NtbsKjZmhiw6RpbWRkDKN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lqVZlaWxTbGFzaKRzbW9ko04vQadhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkSoVgqoVoXqnB1bmlzaGFibGUApG5hbWWpVmVpbFNsYXNopGlteGTM4qNzbW7Co2ZoYsOkaW1kZB2jdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZahGYWxsaW5nVqRzbW9ko04vQadhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVnM56FYzJahWsyXqnB1bmlzaGFibGUApG5hbWWoRmFsbGluZ1akaW14ZM0BmaNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZapCb25lTmVlZGxlpHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWQehWAehWiSqcHVuaXNoYWJsZQCkbmFtZapCb25lTmVlZGxlpGlteGTM16NzbW7Co2ZoYsOkaW1kZBmjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZa9Lb2pha3VDcml0QXJyb3ekc21vZKNOL0GnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkAoVgAoVoApHdoZW4ApGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMOkc3JwbsKkYWF0a8KmaGl0Ym94g6FZC6FYC6FaJKpwdW5pc2hhYmxlAKRuYW1lr0tvamFrdUNyaXRBcnJvd6RpbXhka6NzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZadCaWdab3JupHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWQqhWAqhWgSqcHVuaXNoYWJsZQCkbmFtZadCaWdab3JupGlteGRgo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lsVJldmVyc2VUaWRlSGl0Ym94pHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaREYXNopG5hbWWhMaZoaXRib3iDoVkAoVgAoVoApHdoZW4ApGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMOkc3JwbsKkYWF0a8KmaGl0Ym94g6FZFKFYGaFaF6pwdW5pc2hhYmxlAKRuYW1lsVJldmVyc2VUaWRlSGl0Ym94pGlteGRro3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lqUJhbGFEcml2ZaRzbW9ko04vQadhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkKoVgKoVrLQDAAACAAAACqcHVuaXNoYWJsZQCkbmFtZalCYWxhRHJpdmWkaW14ZMzio3NtbsKjZmhiw6RpbWRkHaN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lqG5ld1NoYXJrpHNtb2SjTi9Bp2FjdGlvbnOShaVfdHlwZatTdGFydCBCbG9ja6RuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwoWlX3R5cGWpRW5kIEJsb2NrpG5hbWWhMqZoaXRib3iDoVlkoVhkoVpkpHdoZW7NAfSkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkPoVgSoVotqnB1bmlzaGFibGUApG5hbWWobmV3U2hhcmukaW14ZMzBo3NtbsKjZmhiwqRpbWRkCqN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lplNoZUppbqRzbW9ko04vQadhY3Rpb25zkYWlX3R5cGWkRGFzaKRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWRmhWBmhWiKqcHVuaXNoYWJsZQCkbmFtZaZTaGVKaW6kaW14ZMzMo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lqVdvcmxkSGFuZKRzbW9ko04vQadhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkyoVgfoVoKqnB1bmlzaGFibGUApG5hbWWpV29ybGRIYW5kpGlteGR2o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVk3gATpHVtb2HCpXBuYW1lslJlaXNoaVN0cmluZ1Jld29ya6RzbW9ko04vQadhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KkbmRmYsKlYWZ0ZXIAo3VoY8Opc2NyYW1ibGVkwqRkdWlow6RzcnBuwqRhYXRrwqZoaXRib3iDoVkOoVgOoVoXqnB1bmlzaGFibGUApG5hbWWyUmVpc2hpU3RyaW5nUmV3b3JrpGlteGRgo3NtbsKjZmhiw6RpbWRky0A6EeuFHrhNo3RhZ6lVbmRlZmluZWTeABOkdW1vYcKlcG5hbWWrU2Fua3RBcnJvd3Okc21vZKNOL0GnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkgoVgfoVohpHdoZW4ApGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMOkc3JwbsKkYWF0a8KmaGl0Ym94g6FZFKFYFKFaH6pwdW5pc2hhYmxlAKRuYW1lq1Nhbmt0QXJyb3dzpGlteGTMgaNzbW7Co2ZoYsOkaW1kZAejdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZa5WaXNpb25hcnlHdW4xMqRzbW9ko04vQadhY3Rpb25zkoWlX3R5cGWrU3RhcnQgQmxvY2ukbmFtZaExpmhpdGJveIOhWRmhWB+hWimkd2hlbszNpGloYmPChaVfdHlwZalFbmQgQmxvY2ukbmFtZaEypmhpdGJveIOhWVChWFChWlCkd2hlbs0F3KRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjCpHNycG7CpGFhdGvCpmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZa5WaXNpb25hcnlHdW4xMqRpbXhkQKNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZadUb3JwZWRvpHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWRuhWBuhWgqqcHVuaXNoYWJsZQCkbmFtZadUb3JwZWRvpGlteGTM7aNzbW7Co2ZoYsOkaW1kZB+jdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZaRQYXdupHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWSihWCihWiqqcHVuaXNoYWJsZQCkbmFtZaRQYXdupGlteGTMrKNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZbJXYXZlc2hvdFByb2plY3RpbGWkc21vZKNOL0GnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkAoVgAoVoApHdoZW4ApGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMOkc3JwbsKkYWF0a8KmaGl0Ym94g6FZBqFYBqFaF6pwdW5pc2hhYmxlAKRuYW1lqFdhdmVzaG90pGlteGTMzKNzbW7Co2ZoYsOkaW1kZAyjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZapKdWdyYW1Dcml0pHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZD6FYD6FaFaR3aGVuAKRpaGJjwqRuZGZiwqVhZnRlcgCjdWhjw6lzY3JhbWJsZWTCpGR1aWjDpHNycG7CpGFhdGvCpmhpdGJveIOhWQ+hWA+hWhSqcHVuaXNoYWJsZQCkbmFtZapKdWdyYW1Dcml0pGlteGTMgaNzbW7Co2ZoYsOkaW1kZAyjdGFnqVVuZGVmaW5lZN4AE6R1bW9hwqVwbmFtZa5XaW5kUHJpc29uQmFsbKRzbW9ko04vQadhY3Rpb25zkoWlX3R5cGWrU3RhcnQgQmxvY2ukbmFtZaExpmhpdGJveIOhWQChWAChWgCkd2hlbgCkaWhiY8KFpV90eXBlqUVuZCBCbG9ja6RuYW1loTKmaGl0Ym94g6FZzJuhWMyWoVrMmKR3aGVuzQH0pGloYmPCpG5kZmLCpWFmdGVyAKN1aGPDqXNjcmFtYmxlZMKkZHVpaMOkc3JwbsKkYWF0a8KmaGl0Ym94g6FZPKFYPKFaPKpwdW5pc2hhYmxlAKRuYW1lrldpbmRQcmlzb25CYWxspGlteGR2o3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkpXNvdW5kk94AFaNyc2QApHVtb2HCo3JwZACkc21vZKNOL0GnYWN0aW9uc5GFpV90eXBlpERhc2ikbmFtZaExpmhpdGJveIOhWczQoVg8oVrMy6R3aGVuzRLApGloYmPCpG5kZmLCpGR1aWjCpWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzEwNjQ4OTUzNDAyqXNjcmFtYmxlZMKkcnB1ZcKkc3JwbsKkYWF0a8KmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lqU1lbm9zQ2Vyb6RpbXhkzQEto3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVk3gAVo3JzZACkdW1vYcKjcnBkAKRzbW9ko04vQadhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWR2hWDOhWjOkd2hlbs0EaqRpaGJjwqRuZGZiwqRkdWlowqVhZnRlcgCjX2lkvHJieGFzc2V0aWQ6Ly8xMzg3NTk1NTI4NTQwOTWpc2NyYW1ibGVkwqRycHVlwqRzcnBuwqRhYXRrwqZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWrVGlja2luZ0JvbWKkaW14ZEujc21uwqNmaGLCpGltZGQDo3RhZ6lVbmRlZmluZWTeABWjcnNkAKR1bW9hwqNycGQApHNtb2SjTi9Bp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZGaFYGaFaLaR3aGVuzQGupGloYmPCpG5kZmLCpGR1aWjCpWFmdGVyAKNfaWS8cmJ4YXNzZXRpZDovLzEyMzA2NDQ5NjE5MjkwMalzY3JhbWJsZWTCpHJwdWXCpHNycG7CpGFhdGvCpmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZatDU2Vjb25kUGFydKRpbXhkVqNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKd2ZXJzaW9uAalhbmltYXRpb27cBCfeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlw6RpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkLoVgLoVobpHdoZW7NAu6kaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcxNzAzNDA3o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lq1N0aWxsU2lsdmVypGlteGR2o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kvEhGXzE0MDcwMjcwMDg0X0F1dG9HZW5lcmF0ZWSkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzAyNzAwODSjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWW8SEZfMTQwNzAyNzAwODRfQXV0b0dlbmVyYXRlZKRpbXhkMqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWRShWBShWjKkd2hlbs0CWKRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTg2ODYxNzYwMzWjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWuVW5zdGFibGVTUkNyaXSkaW14ZFajc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkOoVgOoVoMpHdoZW7NAa6kaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS8cmJ4YXNzZXRpZDovLzExMjQxNDI2NTg5MjU3NaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaZDbG91ZDGkaW14ZDWjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2TZIEhGXzEyNzQ2NzU2OTk2MDI5OV9BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS8cmJ4YXNzZXRpZDovLzEyNzQ2NzU2OTk2MDI5OaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZdkgSEZfMTI3NDY3NTY5OTYwMjk5X0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVlXoVhRoVpRpHdoZW7NAa6kaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS7cmJ4YXNzZXRpZDovLzkyNDQ5NDMyMzUzODQ2o21hdM0H0KRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWmU3RvbXAypGlteGR2o3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2Fj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WgCqcHVuaXNoYWJsZQCkbmFtZaZTbGFzaDOkaW14ZCCjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkPoVgSoVpRpHdoZW7NAdakaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcwNTE0NTc5o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lpUNlcm8zpGlteGRgo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kv0hGXzg0MDAwNDU5ODQxNzk0X0F1dG9HZW5lcmF0ZWSkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLtyYnhhc3NldGlkOi8vODQwMDA0NTk4NDE3OTSjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWW/SEZfODQwMDA0NTk4NDE3OTRfQXV0b0dlbmVyYXRlZKRpbXhkMqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZLBTcGxpdHRpbmdUaHVuZGVypGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkPoVgOoVoypHdoZW7NAhykaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MjMxNDk4NzUxo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZ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c21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXDpGllYWXDomhhwqRkdWlow6dhY3Rpb25zkoWlX3R5cGWrU3RhcnQgQmxvY2ukbmFtZaExpmhpdGJveIOhWQuhWAuhWiqkd2hlbs0CWKRpaGJjwoWlX3R5cGWpRW5kIEJsb2NrpG5hbWWhMqZoaXRib3iDoVlmoVhkoVpmpHdoZW7NBdykaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcxNTk3OTY1o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lq0JhbGFCYXJyYWdlpGlteGRLo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZFKFYM6FaM6R3aGVuzQGGpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNzUwODg4NTE0N6NtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZa5TcGVhcldlaXJkQ3JpdKRpbXhkQKNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQ6hWA6hWgykd2hlbs0BQKRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTg4NjkyMDEwOTajbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWnRmlyZUdTNaRpbXhkK6NzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZLxIRl8xNDA3MTY1NTgxMF9BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcxNjU1ODEwo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lvEhGXzE0MDcxNjU1ODEwX0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMOnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkPoVgPoVoOpHdoZW7NArykaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE1NDM0OTgxMzc1o21hdM0H0KRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkQoVgQoVoZqnB1bmlzaGFibGUApG5hbWWoUG9sdXRpb26kaW14ZHajc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkMoVgPoVoLpHdoZW7NATakaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS7cmJ4YXNzZXRpZDovLzg1NTIzMjI4NDY1NDk5o21hdM0H0KRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWlSG9mZjKkaW14ZCujc21uwqNmaGLDpGlt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pHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZalDcmVhdGlvbkOkaW14ZEujc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2S8SEZfMTQwNzAyNTc5MzBfQXV0b0dlbmVyYXRlZKRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOQo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA3MDI1NzkzMKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZbxIRl8xNDA3MDI1NzkzMF9BdXRvR2VuZXJhdGVkpGlteGQyo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDKFYDKFaD6R3aGVuzNykaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE4MjcyNDMwMTk3o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lp0dpbnJlaTOkaW14ZDWjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkMoVgOoVoOpHdoZW7NAbikaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE2OTkwOTY1MzYzo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lpEdTMTKkaW14ZEujc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkLoVgMoVoUpHdoZW7NAgikaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDgwMzE2ODM3o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lp1F1aW5jeTKkaW14ZDWjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2SpVml6b3JDZXJvpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkZoVgZoVrMlqR3aGVuzQOEpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA3MTcxMDc5MKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZalWaXpvckNlcm+kaW14ZGujc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5KFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkQoVgboVobpHdoZW7NAwykaWhiY8KFpV90eXBlpVBhcnJ5pG5hbWWhMqZoaXRib3iDoVkQoVgMoVoMpHdoZW7NASykaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS8cmJ4YXNzZXRpZDovLzEwMDMxOTcyODcyNzUyMqNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZa1GdWxsYnJpbmdDcml0pGlteGRro3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDKFYEqFaKKR3aGVuzQLkpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lku3JieGFzc2V0aWQ6Ly83Njg2MzAzOTQwOTQ1M6NtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZa1BZGRpY3Rpb25TaG90pGlteGQ1o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kvEhGXzE0MDcxNTU2OTc2X0F1dG9HZW5lcmF0ZWSkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzE1NTY5NzajbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWW8SEZfMTQwNzE1NTY5NzZfQXV0b0dlbmVyYXRlZKRpbXhkMqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQ6hWBKhWh+kd2hlbs0B9KRpaGJjwqNwZmjCpG5kZmLCo3JzZACl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cGZowqRuZGZiwqNyc2TNAoClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzE2NjQ1NTKjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkUoVgUoVokqnB1bmlzaGFibGUApG5hbWWpR2FraVJla2tvpGlteGRWo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOShaVfdHlwZatTdGFydCBCbG9ja6RuYW1loTGmaGl0Ym94g6FZE6FYH6FaH6R3aGVuzQGGpGloYmPChaVfdHlwZalFbmQgQmxvY2ukbmFtZaEypmhpdGJveIOhWWqhWGuhWm2kd2hlbs0D6KRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzEzNTQ4ODCjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWpV2luZFRoaW5npGlteGRAo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDKFYDKFaFKR3aGVuzNykaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MTQ4OTIwNjMxo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lp0Nhc2NhZGGkaW14ZCujc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2TZIEhGXzExNjU5NTE1MDQ0MTA4NV9BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFt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kYWlX3R5cGWlUGFycnmkbmFtZadSZWxlYXNlpmhpdGJveIOhWRShWCmhWimkd2hlbs0DDKRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQ2OTY5NTQ4MzajbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWxRGFnZ2VyQmFua2FpQ3JpdA2kaW14ZMyho3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kr1JpbmdHcm91bmRQdW5jaKRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHDpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZS6FYZqFaZqR3aGVuzQO2pGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkvHJieGFzc2V0aWQ6Ly8xMzM3NzI3NTUxMzcwMjejbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWvUmluZ0dyb3VuZFB1bmNopGlteGTM7aNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQuhWAyhWg6kd2hlbs0BmqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNjkzOTY0NDajbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWlRHVhbDKkaW14ZDWjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxl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YcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkLoVgLoVoLpHdoZW7NAZCkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDY5NDUxODc1o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lpUZpc3QypGlteGQ1o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZFaFYJKFaJKR3aGVuzQMgpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lku3JieGFzc2V0aWQ6Ly83NzIzMjk1MDg4OTQ2N6NtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZa1SYXBpZXJDcml0QU9FpGlteGRAo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kvEhGXzE0MDY5MDU4OTE1X0F1dG9HZW5lcmF0ZWSkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNjkwNTg5MTWjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWW8SEZfMTQwNjkwNTg5MTVfQXV0b0dlbmVyYXRlZKRpbXhkMqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZKVNdXJhMaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1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Y3Rpb25zkoWlX3R5cGWrU3RhcnQgQmxvY2ukbmFtZaExpmhpdGJveIOhWQuhWAuhWiikd2hlbs0CJqRpaGJjwoWlX3R5cGWpRW5kIEJsb2NrpG5hbWWhMqZoaXRib3iDoVnMkqFYzI+hWsyOpHdoZW7NBRSkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE3MjEwNjY1MDU0o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZDqFYDqFaKKpwdW5pc2hhYmxlAKRuYW1lp01pbmlndW6kaW14ZDWjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2S8SEZfMTQwNzAzMzc3MDBfQXV0b0dlbmVyYXRlZKRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOQo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA3MDMzNzcwMKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZbxIRl8xNDA3MDMzNzcwMF9BdXRvR2VuZXJhdGVkpGlteGQyo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kpU1hZ21hpGFhdGvCqXNjcmFtYmxlZMKjaWFlw6RpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS8cmJ4YXNzZXRpZDovLzEwNjc1NTU5MzE2MjI1NqNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZapNYWdtYVBsdW1lpGlteGR2o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHD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aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDKFYD6FaGKR3aGVuzQHqpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lku3JieGFzc2V0aWQ6Ly84NzMwNzEzNjU4Nzg3NKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaRBc2hapGlteGQ1o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kvEhGXzE0MDY5MDYzMjMwX0F1dG9HZW5lcmF0ZWSkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNjkwNjMyMzCjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWW8SEZfMTQwNjkwNjMyMzBfQXV0b0dlbmVyYXRlZKRpbXhkMqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQ6hWA6hWg6kd2hlbs0BmqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzAxODYyNTKjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWqSWNlUmFwaWVyNaRpbXhkNaNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZKtDb25mbGljdGlvbqRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjD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YcOjcnBkAKRzbW9kvEhGXzE0MDcwMjU1Nzc5X0F1dG9HZW5lcmF0ZWSkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzAyNTU3NzmjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWW8SEZfMTQwNzAyNTU3NzlfQXV0b0dlbmVyYXRlZKRpbXhkMqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQ6hWA+hWhWkd2hlbs0DPqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLtyYnhhc3NldGlkOi8vOTcyMDQ2MTI0OTQ0NzGjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWpRWxEaXJlY3RvpGlteGRLo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDKFYDKFaDqR3aGVuzQHWpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA2OTk2NzAyNqNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZadIYW1tZXIypGlteGQro3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRz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ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzEwNTk3NTajbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWmU29uaWRvpGlteGTMgaNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZLxIRl8xNzA3MTE0NjE1M19BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE3MDcxMTQ2MTUzo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lvEhGXzE3MDcxMTQ2MTUzX0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVlkoVhdoVpdpHdoZW7NCmmkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE1NDA0MDQwODY0o21hdM0H0KRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWnRHVtYmVsbKRpbXhkdqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWROhWCShWjGkd2hlbs0CCKRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhh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oVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWsSGFycmliZWxDcml0pGlteGR2o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kvEhGXzE0MDcwMzI1ODUxX0F1dG9HZW5lcmF0ZWSkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzAzMjU4NTGjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWW8SEZfMTQwNzAzMjU4NTFfQXV0b0dlbmVyYXRlZKRpbXhkMqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQyhWAyhWgykd2hlbs0BNqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTc0MzgzODc4MTKjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWkWWFtM6RpbXhkNaNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQ6hWA+hWiukd2hlbs0BuKRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLxyYnhhc3NldGlkOi8vMTAxMDYwNTk0MjQxNTEzo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lpUFjdXRlpGlteGQ1o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZD6FYDqFaEKR3aGVuzQEEpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lku3JieGFzc2V0aWQ6Ly84NDM1NTE3OTk5MTQ2NaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZahUcmluaXR5MqRpbXhkK6NzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZLxIRl8xNDA3MDMzNjU0Ml9BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcwMzM2NTQyo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lvEhGXzE0MDcwMzM2NTQyX0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkLoVgLoVoLpHdoZW7NAUqkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDY5OTM4Njc4o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxl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qnB1bmlzaGFibGUApG5hbWWqRmxvd2VyQ3JpdKRpbXhkS6NzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQyhWA6hWg6kd2hlbs0BhqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLtyYnhhc3NldGlkOi8vOTk1NDU1NjY3NjIyNjSjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWkWmFuMqRpbXhkNaNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZKdQaG9lbml4pGFhdGvCqXNjcmFtYmxlZMKjaWFlw6RpZWFlw6JoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0ODEwMDMxNjg4o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lq1Bob2VuaXhEaXZlpGlteGTMwaNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZLxIRl8xNDA3MDI1NDcyNF9BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcwMjU0NzI0o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lvEhGXzE0MDcwMjU0NzI0X0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkLoVgMoVoOpHdoZW7NAZqkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS8cmJ4YXNzZXRpZDovLzEyMzA1MTcwNjE5NjkxM6NtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaZEZWphbDOkaW14ZDWjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2SnUGlsbGFyc6RhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZIKFYeaFaeaR3aGVuzQIwpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xODg2NDMzNjMxOKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaxWaXNpb25QaWxsYXKkaW14ZMyMo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kqktpc3VrZU1vdmWkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQyhWA6hWgykd2hlbs0BIqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzExODQ2MzKjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWrS2lzdWtlTW92ZTSkaW14ZDWjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkQoVgSoVoSpHdoZW7NAjCkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS8cmJ4YXNzZXRpZDovLzEyNzg5MTQzODAxMDAwM6NtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZa5JbnNlcnRQcmVzZW5jZaRpbXhkS6NzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQuhWAuhWg6kd2hlbs0BkKRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTc1MDY3MDg0MzGjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWmU3BlYXI0pGlteGRAo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcOkaWVhZcKiaGHCpGR1aWjDp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZAKFYAKFaAKR3aGVuzQWgpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDgxMDAyMTg2OaNtYXTNB9CkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZKqFYLqFaLqpwdW5pc2hhYmxlAKRuYW1lq1Bob2VuaXhTbGFtpGlteGTMt6NzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQqhWAuhWgukd2hlbs0BmqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzAwNzQ2ODijbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWrU2hpbmlTd29yZDOkaW14ZDWjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2S8SEZfMTQwNzEzNjE0NDFfQXV0b0dlbmVyYXRlZKRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOQo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA3MTM2MTQ0MaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZbxIRl8xNDA3MTM2MTQ0MV9BdXRvR2VuZXJhdGVkpGlteGQyo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDqFYDKFaDKR3aGVuzQFopGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA2OTIzNzg3N6NtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZahDdXRsYXNzMaRpbXhkS6NzbW7Co2Zo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pHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaVQaGFzZaRpbXhkK6NzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZLxIRl8xNzA3MTAxMDcxM19BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE3MDcxMDEwNzEzo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lvEhGXzE3MDcxMDEwNzEzX0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpERhc2ikbmFtZaExpmhpdGJveIOhWRShWBShWjykd2hlbs0E4qRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzA3OTc3OTijbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWqSmFja2FsQ2Vyb6RpbXhkdqNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQyhWAyhWgykd2hlbs0BcqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQ2NjM5ODU3MjKjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZo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pG5hbWWkTmVsM6RpbXhkIKNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZL9IRl85NTEzNzYzNjQxNjg2Nl9BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS7cmJ4YXNzZXRpZDovLzk1MTM3NjM2NDE2ODY2o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lv0hGXzk1MTM3NjM2NDE2ODY2X0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkMoVgOoVoMpHdoZW7M3KRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTg2MTQ5NDE3MjCjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWmQmxhY2sypGlteGQgo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZFKFYFKFaFKR3aGVuzQGapGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lku3JieGFzc2V0aWQ6Ly84OTI0NTcwNDM2MjI0MqNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZapS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YWJsZQCkbmFtZadTY3l0aGU1pGlteGQ1o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDKFYDqFaDKR3aGVuzQG4pGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA4OTc3NjE1NqNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaVEaXNrMaRpbXhkQKNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQyhWA6hWgykd2hlbs0BXqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTg2MTcyNDE5NTOjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWjU1I0pGlteGQgo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kvEhGXzE0MDY5MDM0OTE1X0F1dG9HZW5lcmF0ZWSkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNjkwMzQ5MTWjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWW8SEZfMTQwNjkwMzQ5MTVfQXV0b0dlbmVyYXRlZKRp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aXKkaW14ZCCjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2S8SEZfMTQwNjk0MTg5NzhfQXV0b0dlbmVyYXRlZKRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOQo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA2OTQxODk3OKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZbxIRl8xNDA2OTQxODk3OF9BdXRvR2VuZXJhdGVkpGlteGQyo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZC6FYC6FaDKR3aGVuzQFUpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xODYyNDExMjc1M6NtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZahQaWVyY2VyMqRpbXhkK6NzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQyhWA6hWgykd2hlbszcpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xODYxNDk0NTQ0OKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaZCbGFjazOkaW14ZCCjc21uwqNm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AKFaAKpwdW5pc2hhYmxlAKRuYW1lqUNlcm9TYWx2b6RpbXhkzIGjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkMoVgMoVoMpHdoZW7NATakaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE3NDM4Mzc0OTA2o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lpFlhbTKkaW14ZDWjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkVoVgZoVofpHdoZW7NAQ6kaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcxMDc4Njkzo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lpVN0b2NrpGlteGRLo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kvEhGXzE0MDcwMzM4OTg4X0F1dG9HZW5lcmF0ZWSkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzAzMzg5ODijbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWW8SEZfMTQwNzAzMzg5ODhfQXV0b0dlbmVyYXRlZKRpbXhkMqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQ+hWA6hWg6kd2hlbs0BLKRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTc3NzI2Mjc3MjajbWF0zQfQpHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZapCaW9uaWNHcmFipGlteGQ1o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kv0hGXzcyMTI1NDc2ODEzNzQyX0F1dG9HZW5lcmF0ZWSkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLtyYnhhc3NldGlkOi8vNzIxMjU0NzY4MTM3NDKjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWW/SEZfNzIxMjU0NzY4MTM3NDJfQXV0b0dlbmVyYXRlZKRpbXhkMqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQ6hWBShWhykd2hlbs0BcqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzEyOTIxMjmjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUA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o21hdM0H0KRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWlSG9mZjSkaW14ZCujc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2SqRmlyZUdTQ3JpdKRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDqFYD6FaH6R3aGVuzQJ2pGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xODgzODM3OTMxMaNtYXTNB9CkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lqkZpcmVHU0NyaXSkaW14ZECjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SnUGFzc2FnZaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjDp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZD6FYEqFaFKR3aGVuzQLupGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA3MTYzNTI3MKNtYXTNB9CkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZDqFYDqFaG6pwdW5pc2hhYmxlAKRuYW1lrUZsb3dlclBhc3NhZ2WkaW14ZMzMo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZCqFYCqFaDKR3aGVuzQEspGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0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dWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQ6hWBihWhikd2hlbs0CdqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLtyYnhhc3NldGlkOi8vODI5OTQ1NjM3NzUxNTCjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWnWmFuQ3JpdKRpbXhkNaNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZLxIRl8xNDg0MzI4ODMxNl9BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0ODQzMjg4MzE2o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lvEhGXzE0ODQzMjg4MzE2X0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2S8SEZfMTc1ODU0Mzc4NTNfQXV0b0dlbmVyYXRlZKRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOQo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNzU4NTQzNzg1M6NtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZbxIRl8xNzU4NTQzNzg1M19BdXRvR2VuZXJhdGVkpGlteGQyo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaREYXNopG5hbWWhMaZoaXRib3iDoVkcoVhkoVpkpHdoZW7NAmKkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS8cmJ4YXNzZXRpZDovLzEyMTk4Njk5MDg5OTAzMKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZatKYWlsaW5nUm9kc6RpbXhka6NzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQyhWAyhWg6kd2hlbs0BXqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNjkwMTAzODmjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWmU2xhc2gypGlteGQgo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDKFYDqFaEKR3aGVuzQFopGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNzQ0MTkzMzI3MKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZadPZGFjaGkypGlteGQro3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZD6FYD6FaDqR3aGVuzQJspGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA3MTI2MTcwNqNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZadCaWZyb3N0pGlteGRAo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDKFYDKFaDKR3aGVuzQEOpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNzYyODUzMzc3MaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaVUYWVrM6RpbXhkNaNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZKZWZXJzY2ikYWF0a8Kpc2NyYW1ibGVkwqNpYWXDpGllYWXDomhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQyhWA6hWhWkd2hlbs0BXqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTgyMTYyMTEwODmjbWF0zQZApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaZWZXJzY2ikaW14ZHajc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkMoVgMoVoQpHdoZW7NAbikaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcxNjU3NDg4o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lrFZlcnRpY2FsRG93bqRpbXhkQKNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQ+hWBShWh+kd2hlbs0B6qRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTcyMTMyNzYzMjijbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWmU3Rvcm01pGlteGRAo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDqFYDqFaCqR3aGVuzQEEpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkvHJieGFzc2V0aWQ6Ly8xMTY5NDI5MjY1OTE0NzmjbWF0zQfQpHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZadLYXJhdGUxpGlteGQgo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOShaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZNqFYH6FaK6R3aGVuzQV4pGloYmPChaVfdHlwZaVQYXJyeaRuYW1loTKmaGl0Ym94g6FZDqFYD6FaDqR3aGVuzQGQpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lku3JieGFzc2V0aWQ6Ly85MTk5NDgyNjAxNjEzOKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZahTaG9tZXRzdaRpbXhkQKNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZadSZWxlYXNlpmhpdGJveIOhWRShWBOhWhSkd2hlbsz6pGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA2OTMxMzM1MqNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZbNEYWdnZXJCYW5rYWlTd2luZzMNpGlteGTMoaNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWSChWCChWhmkd2hlbs0BO6RpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTU0MjIwNDIxMjWjbWF0zQfQpHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZatEaWFtb25kUnVzaKRpbXhkNaNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZKpSYXBpZXJDcml0pGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkOoVgOoVoUpHdoZW7NAVSkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE4NTAwMDczMjcxo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lq1JhcGllckNyaXQxpGlteGQro3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZC6FYC6FaDKR3aGVuzQEYpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNjg3NTQyMjAxNqNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaRGYW40pGlteGQgo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDKFYDqFaEKR3aGVuzQFopGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNzQ0MTkzMjYyMaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZadPZGFjaGkxpGlteGQro3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDqFYDqFaDqR3aGVuzQFopGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA3MDE4NDk3NqNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZapJY2VSYXBpZXI0pGlteGQ1o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZD6FYD6FaHaR3aGVuAKRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLtyYnhhc3NldGlkOi8vODI4MjYyMTMzNzAxNDijbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWxVGltZVRlbGxzQ3JpdGljYWykaW14ZEGjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5OFpV90eXBlq1N0YXJ0IEJsb2NrpG5hbWWhMaZoaXRib3iDoVkQoVgtoVotpHdoZW7NAZ+kaWhiY8KFpV90eXBlqUVuZCBCbG9ja6RuYW1loTOmaGl0Ym94g6FZUKFYUKFaUKR3aGVuzQK8pGloYmPChaVfdHlwZaVQYXJyeaRuYW1loTKmaGl0Ym94g6FZEKFYLaFaLaR3aGVuzQRqpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNjg2MjE5NzY0OKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZalGbGFtZVdoaXCkaW14ZGujc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlw6RpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkQoVggoVp4pHdoZW7NBaqkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcxNzAxOTE0o21hdM0H0KRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWpQmx1ZUxpZ2h0pGlteGR2o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDKFYDKFaDKR3aGVuzQFypGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDY2NDEzMjQ2NKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQyhWAyhWhmqcHVuaXNoYWJsZQCkbmFtZadRdWlsZ2U0pGlteGQ1o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kqERhZ2dlck0xpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkKoVgLoVoMpHdoZW7NAcykaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcwMDAyNTcxo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lp0RhZ2dlcjOkaW14ZCujc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkUoVgSoVoipHdoZW7NAsakaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcxNjUzNTg2o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lqVN1aWthd2FyaaRpbXhkS6NzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQ+hWA+hWstAIAAAIAAAAKR3aGVuzQH0pGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkvHJieGFzc2V0aWQ6Ly8xMDEyNjc0MDg4NDA1OTCjbWF0zQfQpHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaVIZWxsNKRpbXhkNaNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZKhMb3dSdWxlcqRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOQo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA4MTE4ODA2NaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZalBdXRob3JpdHmkaW14ZMyWo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZEKFYR6FaR6R3aGVuzQFypGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkvHJieGFzc2V0aWQ6Ly8xMTc0MzM2Nzc3NDQ0MDCjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWrUmVpYXRzdVB1bGykaW14ZGujc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2S8SEZfMTc5MDAyNzUwNDJfQXV0b0dlbmVyYXRlZKRhYXRrwqlzY3JhbWJsZWTCo2lhZcOkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOQo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNzkwMDI3NTA0MqNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZbxIRl8xNzkwMDI3NTA0Ml9BdXRvR2VuZXJhdGVkpGlteGQyo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kvEhGXzE4MjcxNzc0NDgzX0F1dG9HZW5lcmF0ZWSkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTgyNzE3NzQ0ODOjbWF0zQfQpHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZbxIRl8xODI3MTc3NDQ4M19BdXRvR2VuZXJhdGVkpGlteGQyo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZEKFYEqFaEqR3aGVuzQH0pGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNzA3NDQ2MjU2NqNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZatDcmF6ZWRCbGl0eqRpbXhkIKNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZLxIRl8xNDA3MDMwMjA5OF9BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcwMzAyMDk4o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lvEhGXzE0MDcwMzAyMDk4X0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkMoVgLoVoLpHdoZW7NAUqkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDY5Mjg1NTQyo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lqERhZ2dlcjE0pGlteGQ1o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHDpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZHKFYKKFaJqR3aGVuzQQzpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA3MDc5ODczOKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZapKYWNrYWxDcml0pGlteGRAo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZH6FYZKFaZKR3aGVuzQNmpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNzEyMzQ3NDY3NqNtYXTNB9CkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lqUJsYXN0TW92ZaRpbXhkdqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWRShWBihWhikd2hlbs0B6qRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzE3ODg5NDSjbWF0zQfQpHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZalUcnVlR3Jhc3CkaW14ZFajc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkOoVgMoVoMpHdoZW7NAXKkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE4MTQxMzE1ODQ0o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lplNoYXJkMqRpbXhkK6NzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQyhWAyhWh+kd2hlbs0B6qRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzE2NTQ2NzGjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWwUmFuZG9tU2hpbmlNb3ZlMqRpbXhkYKNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZLxIRl8xNDA2OTA2MTI4MF9BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDY5MDYxMjgwo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lvEhGXzE0MDY5MDYxMjgwX0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkOoVgOoVoKpHdoZW7NAQSkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS7cmJ4YXNzZXRpZDovLzg1OTM2OTQxMzM4OTc1o21hdM0H0KRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWnS2FyYXRlNKRpbXhkIKNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQqhWAuhWgykd2hlbs0BfKRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNjkzNTQ1MzWjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWmU3dvcmQzpGlteGQro3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDqFYDqFaDKR3aGVuzQGapGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkvHJieGFzc2V0aWQ6Ly8xMDE1NDA0NzcyMDM2MDajbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWmQ2xvdWQ1pGlteGQ1o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kpkRlc2dhcqRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZEKFYEqFaIKR3aGVuzQJ2pGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNjczODQwMTQzMqNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZalEZXNnYXJyb26kaW14ZGCjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2SsUmVpYXRzdVNwaWtlpGFhdGvCqXNjcmFtYmxlZMKjaWFlw6RpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkAoVgAoVoApHdoZW4ApGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lku3JieGFzc2V0aWQ6Ly84MjI2ODgxNTE1OTUwOKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaxSZWlhdHN1U3Bpa2WkaW14ZHajc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2SqS2lzdWtlTW92ZaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDKFYDqFaDKR3aGVuzQEipGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA3MTE4MDU0OaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZatLaXN1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X3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWXihWHihWnikd2hlbs0CiqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTY3MjU1MDA0MTGjbWF0zQfQpHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaVTcG9ya6RpbXhkzJajc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2TZIEhGXzExNjgxMTQ2OTE4MDY5OV9BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS8cmJ4YXNzZXRpZDovLzExNjgxMTQ2OTE4MDY5OaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZdkgSEZfMTE2ODExNDY5MTgwNjk5X0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkMoVgMoVoMpHdoZW7NAZqkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcwMDM5NzU2o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lqEJhbGFuY2UypGlteGQro3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZC6FYC6FaDKR3aGVuzQFopGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA2OTE4Njk4MKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaVDbGF3MqRpbXhkNaNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZKRLaWNrpGFhdGvCqXNjcmFtYmxlZMKjaWFlw6RpZWFlw6JoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS8cmJ4YXNzZXRpZDovLzExNTI0NjQ3NTE2MzE0NKNtYXTNBwikcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lqUV4cGxvc2lvbqRpbXhkzIyjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkVoVgXoVoVpHdoZW7NAamkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcxNjE0Njg1o21hdM0H0KRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWoQ2Vyb0dyYWKkaW14ZEujc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkUoVgzoVobpHdoZW7NBOKkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE2Njk0MDA5NTIyo21hdM0H0KRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWpSW5vcmdhbmljpGlteGRgo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDKFYC6FaC6R3aGVuzQFKpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA2OTI4MTk1OaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZahEYWdnZXIxMqRpbXhkNaNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWRShWBihWh+kd2hlbs0CJqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTcyMjQ4NTE0OTGjbWF0zQfQpHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaxGbGFtZXRocm93ZXKkaW14ZFajc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkXoVgyoVoypHdoZW7NAXykaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS7cmJ4YXNzZXRpZDovLzgyNDE1Mzg1MTExMTcwo21hdM0H0KRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWrV2VpZ2h0U2xhc2ikaW14ZGujc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkyoVgmoVompHdoZW7NAVSkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE3MzAyMTA1OTYwo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lq0FlcmlhbEdyYWNlpGlteGRgo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kvEhGXzE4ODY5MzUwMzg1X0F1dG9HZW5lcmF0ZWSkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTg4NjkzNTAzODWjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWW8SEZfMTg4NjkzNTAzODVfQXV0b0dlbmVyYXRlZKRpbXhkMqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZGSkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlow6dhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQyhWAqhWgukd2hlbs0CHKRp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LzE0MDY5OTMzNzg5o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lpUdyaW0xpGlteGQ1o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kvEhGXzE0MDcwMjQ0ODQyX0F1dG9HZW5lcmF0ZWSkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzAyNDQ4NDKjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWW8SEZfMTQwNzAyNDQ4NDJfQXV0b0dlbmVyYXRlZKRpbXhkMqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWVChWFChWlCkd2hlbs0CnqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzAzMTAxODijbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWqU25ha2VSb2FlcqRpbXhka6NzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWTKhWB+hWiKkd2hlbs0DNKRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTgxMDQ0MjA3MDaj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X0F1dG9HZW5lcmF0ZWSkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzAzNDAwMzejbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWW8SEZfMTQwNzAzNDAwMzdfQXV0b0dlbmVyYXRlZKRpbXhkMqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkoWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWTOhWDKhWjOkd2hlbs0GY6RpaGJjwoWlX3R5cGWlUGFycnmkbmFtZaEypmhpdGJveIOhWTOhWBihWjKkd2hlbs0D6KRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLtyYnhhc3NldGlkOi8vNzQxMDE3OTU5NzY2NDOjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWvSGVhdmVubHlEZXNjZW50pGlteGRAo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZD6FYD6FaDKR3aGVuzQEOpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xODE4NDU1ODczN6NtYXTNB9CkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lqFRodW5kZXIzpGlteGQro3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRw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dGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkMoVgPoVoMpHdoZW7NAWikaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcwODY2MzA1o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lqEZyaXNrZXIypGlteGQ1o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kq0Nlcm9Pc2N1cmFzpGFhdGvCqXNjcmFtYmxlZMKjaWFlw6RpZWFlw6JoYcKkZHVpaMKnYWN0aW9uc5KFpV90eXBlq1N0YXJ0IEJsb2NrpG5hbWWhMaZoaXRib3iDoVkdoVgioVp4pHdoZW7NA4SkaWhiY8KFpV90eXBlqUVuZCBCbG9ja6RuYW1loTKmaGl0Ym94g6FZzMyhWMzMoVrMzKR3aGVuzQUUpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA3MTYxNjk1NqNtYXTNB9CkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lq1Nlcm9Pc2N1cmFzpGlteGTMjKNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWSKhWCShWiGkd2hlbs0BpKRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzE2NTEzMTejbWF0zQfQpHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZapTb25hdGFGbG93pGlteGRWo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDKFYDKFaDqR3aGVuzQFUpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA3MDcxNDIzMKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaVWb2x0M6RpbXhkK6NzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZKVNdXJhM6RhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZC6FYDKFaDqR3aGVuzQHWpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xODk1MzYzMzE2M6NtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaVNdXJhM6RpbXhkNaNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZKlQcmlzbWF0aWOkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWTKhWDKhWjKkd2hlbs0BIqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTcwMDEzMDQ5ODSjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWuUHJpc21hdGljQm9sdHOkaW14ZEujc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2TZIEhGXzExMTAyMDM1MzAxMDU5OF9BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS8cmJ4YXNzZXRpZDovLzExMTAyMDM1MzAxMDU5OKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZdkgSEZfMTExMDIwMzUzMDEwNTk4X0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkPoVgVoVoXpHdoZW7NAcykaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcwNjYzNDAyo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lq1Vub2hhbmFNb3ZlpGlteGRAo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDqFYKKFaKKR3aGVuzQJEpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNzYwNjEyOTYyN6NtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaxPbnNsYXVnaHRI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qXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkUoVgUoVoUpHdoZW7NAcKkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS7cmJ4YXNzZXRpZDovLzg4MTI3NjgyMzU3MTkyo21hdM0H0KRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWW3QnJpbGxpYW5jZVNsYXNoRm9sbG93dXCkaW14ZGujc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2TZIEhGXzEwOTI4MzYwNzUwNjU4OF9BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS8cmJ4YXNzZXRpZDovLzEwOTI4MzYwNzUwNjU4OKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZdkgSEZfMTA5MjgzNjA3NTA2NTg4X0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcOkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkooVgcoVofpHdoZW7NA8qkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcwODk1NDYyo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lrUppZGFuYm9TbGFzaDGkaW14ZHajc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhk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o3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZEKFYIaFaIaR3aGVuzQK8pGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNzUwMzU2NTUzNaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZatUaGlyZFN0ZXA0NaRpbXhkNaNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZLxIRl8xODg2OTMzNTY3MV9BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE4ODY5MzM1Njcxo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lvEhGXzE4ODY5MzM1NjcxX0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SsVGhyb3dpbmdSb2RzpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5KFpV90eXBlq1N0YXJ0IEJsb2NrpG5hbWWnUmVsZWFzZaZoaXRib3iDoVkUoVhkoVpkpHdoZW7NASykaWhiY8KFpV90eXBlqUVuZCBCbG9ja6RuYW1loTKmaGl0Ym94g6FZFKFYzMihWszIpHdoZW7NBLCkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS7cmJ4YXNzZXRpZDovLzk5NTkyMzYzNDkzNzQ3o21hdM0CvKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWsVGhyb3dpbmdSb2RzpGlteGTMoaNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQyhWA6hWg6kd2hlbs0BpKRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLxyYnhhc3NldGlkOi8vMTM4NTc4MzcyOTUzMzk4o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lpFphbjGkaW14ZDWjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlw6RpZWFlw6JoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkooVgooVozpHdoZW7NBSikaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcxNjg2ODc1o21hdM0FeKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWqTGljaHRSZWdlbqRpbXhkzIGjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkPoVgUoVoUpHdoZW5kpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lku3JieGFzc2V0aWQ6Ly85NzMyNjg3OTg4MTU4N6NtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZahUcmluaXR5M6RpbXhkK6NzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQ+hWBehWhekd2hlbs0B9KRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLxyYnhhc3NldGlkOi8vMTIxNTU0ODMwODQ5ODU0o21hdM0H0KRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWoQXhlQ3JpdDGkaW14ZGCjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkMoVgOoVoOpHdoZW7NAQ6kaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE3MjA5NjY3MjMyo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lp0d1aXRhcjKkaW14ZDWjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkLoVgMoVoOpHdoZW7NAXKkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0Nzc0NzY4ODc2o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lp0p1Z3JhbTKkaW14ZDWjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkPoVgOoVofpHdoZW7NAcekaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE3MDAxNzgzNzc1o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lqERlbW9uUGF3pGlteGRgo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDqFYDqFaDKR3aGVuzQFopGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA3MDY3NTMwN6NtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZahVbm9oYW5hMqRpbXhkK6NzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQ6hWAyhWg+kd2hlbs0BkKRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLxyYnhhc3NldGlkOi8vMTM2MzM5NTgzNjY4NjIwo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lqURlc3RlbGxvM6RpbXhkIKNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWRmhWBuhWjOkd2hlbs0C0KRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLtyYnhhc3NldGlkOi8vODQ0NDQ1Nzg4MDIwNTCjbWF0zQfQpHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZahIb2ZmQ3JpdKRpbXhkS6NzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQuhWAuhWgykd2hlbs0BIqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTg0OTk4MDE5MzejbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWoUmFwaWVyMTSkaW14ZCujc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkVoVgZoVofpHdoZW7NBAakaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0NzcwNjkyNjExo21hdM0H0KRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWoVHVybW9pbDOkaW14ZECjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2S8SEZfMTQwNjkwNjUxNjVfQXV0b0dlbmVyYXRlZKRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOQo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA2OTA2NTE2NaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZbxIRl8xNDA2OTA2NTE2NV9BdXRvR2VuZXJhdGVkpGlteGQyo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDqFYDKFaDKR3aGVuzQFopGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA2OTI0MzQ1NaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZahDdXRsYXNzNaRpbXhkS6NzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWRShWBehWhekd2hlbsyWpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkvHJieGFzc2V0aWQ6Ly8xMTczMDIzMDA0NjkwNzSjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5h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o19pZLhyYnhhc3NldGlkOi8vMTQwNzE3MTk2NTejbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWoWmFuZ2VyaW6kaW14ZHajc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkPoVgPoVoPpHdoZW7NASykaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE3Mzg3Nzg1MDczo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lu1NoaWthaU9kYWNoaUNyaXRpY2FsM3JkUGFydKRpbXhkQaNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZKtHYWx2YW5vQmVhbaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZEKFYD6FaKKR3aGVuzQImpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDIzMTQ3OTgzM6NtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaxHYWx2YW5vQmxhc3SkaW14ZEujc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5KFpV90eXBlq1N0YXJ0IEJsb2NrpG5hbWWhMaZoaXRib3iDoVkyoVg+oVpHpHdoZW7N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bXhkK6NzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZKVNdXJhNaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZC6FYDKFaDqR3aGVuzQEipGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xODk0NjU0NzExOKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaVNdXJhNaRpbXhkNaNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQyhWBChWiikd2hlbszIpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xODk4NzQ3OTQ0MqNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZbBEcmFnb25GbGFzaEluc3RhpGlteGRgo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kvEhGXzE0MDcwMjU3MDI5X0F1dG9HZW5lcmF0ZWSkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzAyNTcwMjmjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWW8SEZfMTQwNzAyNTcwMjlfQXV0b0dlbmVyYXRlZKRpbXhkMqNz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o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lp0ZhbkNyaXSkaW14ZECjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2S8SEZfMTQwNzAzMzUzMTVfQXV0b0dlbmVyYXRlZKRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOQo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA3MDMzNTMxNaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZbxIRl8xNDA3MDMzNTMxNV9BdXRvR2VuZXJhdGVkpGlteGQyo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZC6FYC6FaDKR3aGVuzQEYpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNjg3NTQwNTk2N6NtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaRGYW4xpGlteGQgo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kp1NoaWJhcmmkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLxyYnhhc3NldGlkOi8vMTAxNjQ1NTg1NTA2MTgzo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lp1No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ZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkMoVgMoVoOpHdoZW7NAXKkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcwNTUzMDg1o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lpkR1YWxiM6RpbXhkIKNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZLxIRl8xNzA3MTA0NTE3OF9BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE3MDcxMDQ1MTc4o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lvEhGXzE3MDcxMDQ1MTc4X0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2S8SEZfMTQwNzAyNTMzNDlfQXV0b0dlbmVyYXRlZKRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOQo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA3MDI1MzM0OaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZbxIRl8xNDA3MDI1MzM0OV9BdXRvR2VuZXJhdGVkpGlteGQyo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAe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c2NyYW1ibGVkwqNpYWXCpGllYWXComhhw6RkdWlowqdhY3Rpb25zkYWlX3R5cGWkRGFzaKRuYW1loTGmaGl0Ym94g6FZD6FYD6FaD6R3aGVuzQEipGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xODYwMTY1MTg4MaNtYXTNB9CkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lqkJsYWNrZmxhc2ikaW14ZDWjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2S8SEZfMTQwNjk0MTMzMDRfQXV0b0dlbmVyYXRlZKRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOQo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA2OTQxMzMwNKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZbxIRl8xNDA2OTQxMzMwNF9BdXRvR2VuZXJhdGVkpGlteGQyo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZD6FYD6FaD6R3aGVuzQE2pGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA3MTU0MDExNaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZbBHcmFuZEVudHJhbmNlQWlypGlteGRWo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlz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ZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDqFYDqFaDKR3aGVuzQFypGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNDA3MDI5ODc2OaNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaVJbmsxMqRpbXhkK6NzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQyhWAyhWgukd2hlbs0BVKRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzk1NjEzNTmjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWmRHJha28ypGlteGQ1o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9k2SBIRl8xMjIzMzQxNzc1NTI4OTFfQXV0b0dlbmVyYXRlZKRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOQo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkvHJieGFzc2V0aWQ6Ly8xMjIzMzQxNzc1NTI4OTGjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWXZIEhGXzEyMjMzNDE3NzU1Mjg5MV9BdXRvR2VuZXJhdGVkpGlteGQyo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTC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o2lhZcOkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOQo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xODg1MTY2OTExMKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZahEaWdnaW1vbqRpbXhkdqNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQ+hWB+hWhSkd2hlbs0BaKRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTg5NTU5NzYzMDCjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWmU3dpcGUxpGlteGRLo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9kvEhGXzE0MDY5NDE0MTc4X0F1dG9HZW5lcmF0ZWSkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkKNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNjk0MTQxNzijbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWW8SEZfMTQwNjk0MTQxNzhfQXV0b0dlbmVyYXRlZKRpbXhkMqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQuhWAyh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YWNrYWwzpGlteGQ1o3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcOjcnBkAKRzbW9k2SBIRl8xMzM3MDg0OTY0MDQ5MTZfQXV0b0dlbmVyYXRlZKRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOQo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkvHJieGFzc2V0aWQ6Ly8xMzM3MDg0OTY0MDQ5MTajbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWXZIEhGXzEzMzcwODQ5NjQwNDkxNl9BdXRvR2VuZXJhdGVkpGlteGQyo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZC6FYC6FaDKR3aGVuzQEYpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNjg3NTQxMjc1M6NtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaRGYW4ypGlteGQgo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaREYXNopG5hbWWhMaZoaXRib3iDoVkXoVhkoVoppHdoZW7NAu6kaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE2OTc4MDAzNzc1o21hdM0H0KRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWpRmluYWxQbGF5pGlteGRLo3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcOkaWVhZcOiaGHCpGR1aWjDp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZFKFYH6FaKqR3aGVuzQH0pGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNzA1ODkwNTc4NaNtYXTNBdykcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZH6FYH6FaOKpwdW5pc2hhYmxlAKRuYW1lpVNvbmljpGlteGRro3NtbsKjZmhiwqRpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnORhaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZDKFYDqFaDKR3aGVuzQFepGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xODYxNzI2NDE1OKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZaNTUjWkaW14ZCCjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkMoVgMoVoOpHdoZW7NAXKkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcwNTU0MjQxo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lpkR1YWxiNKRpbXhkIKNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZLxIRl8xNDA3MDMwMTE3MV9BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcwMzAxMTcxo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lvEhGXzE0MDcwMzAxMTcxX0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkOoVgXoVokpHdoZW7NAjqkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0ODA5OTk0NzE1o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lqlBob2VuaXhVbHSkaW14ZGCjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hw6NycGQApHNtb2S8SEZfMTg4NjkzMTgzMzhfQXV0b0dlbmVyYXRlZKRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOQo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xODg2OTMxODMzOKNtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZbxIRl8xODg2OTMxODMzOF9BdXRvR2VuZXJhdGVkpGlteGQyo3NtbsKjZmhiwqRpbWRkAKN0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bW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HDo3JwZACkc21vZLxIRl8xNDA3MDI5NzYxMV9BdXRvR2VuZXJhdGVkpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5CjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcwMjk3NjExo21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lvEhGXzE0MDcwMjk3NjExX0F1dG9HZW5lcmF0ZWSkaW14ZDKjc21uwqNmaGLCpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5GFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkOoVgToVoSpHdoZW7NAaSkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcxODAzMzI0o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lr0Zsb2F0aW5nU3RyaWtlc6RpbXhkQKNzbW7Co2ZoYsOkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNpYWXCpGllYWXComhhwqRkdWlowqdhY3Rpb25zkYWlX3R5cGWlUGFycnmkbmFtZaExpmhpdGJveIOhWQ6hWA6hWg6kd2hlbs0BSqRpaGJjwqNwZmjCpG5kZmLCo3JzZAClYWZ0ZXIAo19pZLhyYnhhc3NldGlkOi8vMTQwNzA4Mzc0ODGjbWF0AKRycHVlwqRzcnBuwqRwaGRzAKZoaXRib3iDoVkAoVgAoVoAqnB1bmlzaGFibGUApG5hbWWpRmlzaGJvbmUypGlteGQ1o3NtbsKj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AKFaAKpwdW5pc2hhYmxlAKRuYW1lrUJsYXN0R3JhYk1vdmWkaW14ZECjc21uwqNmaGLDpGltZGQAo3RhZ6lVbmRlZmluZWSiZHDCpHBmaHTLP8MzMzMzMzPeAB6jcGhkwqR1bW9hwqNycGQApHNtb2SjTi9BpGFhdGvCqXNjcmFtYmxlZMKjaWFlwqRpZWFlwqJoYcKkZHVpaMKnYWN0aW9uc5OFpV90eXBlpVBhcnJ5pG5hbWWhMaZoaXRib3iDoVkYoVgXoVoYpHdoZW7NAQ6kaWhiY8KFpV90eXBlpVBhcnJ5pG5hbWWhM6ZoaXRib3iDoVkYoVgXoVoYpHdoZW7NBQCkaWhiY8KFpV90eXBlpVBhcnJ5pG5hbWWhMqZoaXRib3iDoVkYoVgXoVoYpHdoZW7NAjCkaWhiY8KjcGZowqRuZGZiwqNyc2QApWFmdGVyAKNfaWS4cmJ4YXNzZXRpZDovLzE0MDcxMzI0NDU5o21hdACkcnB1ZcKkc3JwbsKkcGhkcwCmaGl0Ym94g6FZAKFYAKFaAKpwdW5pc2hhYmxlAKRuYW1lsVNoYWRvd0JhbmthaVNsYXNopGlteGRAo3NtbsKjZmhiw6RpbWRkAKN0YWepVW5kZWZpbmVkomRwwqRwZmh0yz/DMzMzMzMz3gAeo3BoZMKkdW1vYcKjcnBkAKRzbW9ko04vQaRhYXRrwqlzY3JhbWJsZWTCo2lhZcKkaWVhZcKiaGHCpGR1aWjCp2FjdGlvbnOShaVfdHlwZaVQYXJyeaRuYW1loTGmaGl0Ym94g6FZIqFYE6FaMqR3aGVuzQQkpGloYmPChaVfdHlwZaVQYXJyeaRuYW1loTKmaGl0Ym94g6FZIqFYHKFaKaR3aGVuzQGQpGloYmPCo3BmaMKkbmRmYsKjcnNkAKVhZnRlcgCjX2lkuHJieGFzc2V0aWQ6Ly8xNjg4OTY4MDczM6NtYXQApHJwdWXCpHNycG7CpHBoZHMApmhpdGJveIOhWQChWAChWgCqcHVuaXNoYWJsZQCkbmFtZa1GbG93aW5nUGV0YWxzpGlteGTMlqNzbW7Co2ZoYsKkaW1kZACjdGFnqVVuZGVmaW5lZKJkcMKkcGZodMs/wzMzMzMzM94AHqNwaGTCpHVtb2HCo3JwZACkc21vZKNOL0GkYWF0a8Kpc2NyYW1ibGVkwqNp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]=]
local function decode_b64(data)
    local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local result = {}
    data = data:gsub("[^" .. b .. "=]", "")
    for i = 1, #data, 4 do
        local a, b2, c, d =
            b:find(data:sub(i, i), 1, true) or 0,
            b:find(data:sub(i + 1, i + 1), 1, true) or 0,
            b:find(data:sub(i + 2, i + 2), 1, true) or 0,
            b:find(data:sub(i + 3, i + 3), 1, true) or 0
        a, b2, c, d = (a or 1) - 1, (b2 or 1) - 1, (c or 1) - 1, (d or 1) - 1
        local n = a * 262144 + b2 * 4096 + c * 64 + d
        local c1 = string.char(math.floor(n / 65536) % 256)
        local c2 = string.char(math.floor(n / 256) % 256)
        local c3 = string.char(n % 256)
        table.insert(result, c1)
        if data:sub(i + 2, i + 2) ~= "=" then table.insert(result, c2) end
        if data:sub(i + 3, i + 3) ~= "=" then table.insert(result, c3) end
    end
    return table.concat(result)
end
return decode_b64(b64)

end)
__bundle_register("Utility/Serializer", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[
 * MessagePack serializer / decode (0.6.1) written in pure Lua 5.3 / Lua 5.4
 * written by Sebastian Steinhauer <s.steinhauer@yahoo.de>
 * modified by the Lycoris Team <discord.gg/lyc>
 *
 * This is free and unencumbered software released into the public domain.
 *
 * Anyone is free to copy, modify, publish, use, compile, sell, or
 * distribute this software, either in source code form or as a compiled
 * binary, for any purpose, commercial or non-commercial, and by any
 * means.
 *
 * In jurisdictions that recognize copyright laws, the author or authors
 * of this software dedicate any and all copyright interest in the
 * software to the public domain. We make this dedication for the benefit
 * of the public at large and to the detriment of our heirs and
 * successors. We intend this dedication to be an overt act of
 * relinquishment in perpetuity of all present and future rights to this
 * software under copyright law.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
 * OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
 * ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 *
 * For more information, please refer to <http://unlicense.org/>
]]

-- Serializer module.
local Serializer = {}

---Does a specified table match the layout of an array.
---@param tbl table
---@return boolean
local function isAnArray(tbl)
	local expected = 1

	for k in next, tbl do
		if k ~= expected then
			return false
		end

		expected = expected + 1
	end

	return true
end

---Serialize number to a float.
---@param value number
---@return string
local function serializeFloat(value)
	local serializedFloat = string.unpack("f", string.pack("f", value))
	if serializedFloat == value then
		return string.pack(">Bf", 0xca, value)
	end

	return string.pack(">Bd", 0xcb, value)
end

---Serialize number to a signed int.
---@param value number
---@return string
local function serializeSignedInt(value)
	if value < 128 then
		return string.pack("B", value)
	elseif value <= 0xff then
		return string.pack("BB", 0xcc, value)
	elseif value <= 0xffff then
		return string.pack(">BI2", 0xcd, value)
	elseif value <= 0xffffffff then
		return string.pack(">BI4", 0xce, value)
	end

	return string.pack(">BI8", 0xcf, value)
end

---Serialize number to a unsigned int.
---@param value number
---@return string
local function serializeUnsignedInt(value)
	if value >= -32 then
		return string.pack("B", 0xe0 + (value + 32))
	elseif value >= -128 then
		return string.pack("Bb", 0xd0, value)
	elseif value >= -32768 then
		return string.pack(">Bi2", 0xd1, value)
	elseif value >= -2147483648 then
		return string.pack(">Bi4", 0xd2, value)
	end

	return string.pack(">Bi8", 0xd3, value)
end

---Serialize string to a UTF8 string.
---@param value string
---@return string
local function serializeUtf8(value)
	local len = #value

	if len < 32 then
		return string.pack("B", 0xa0 + len) .. value
	elseif len < 256 then
		return string.pack(">Bs1", 0xd9, value)
	elseif len < 65536 then
		return string.pack(">Bs2", 0xda, value)
	end

	return string.pack(">Bs4", 0xdb, value)
end

---Serialize string to a string of bytes.
---@param value string
---@return string
local function serializeStringBytes(value)
	local len = #value

	if len < 256 then
		return string.pack(">Bs1", 0xc4, value)
	elseif len < 65536 then
		return string.pack(">Bs2", 0xc5, value)
	end

	return string.pack(">Bs4", 0xc6, value)
end

---Serialize table to a array.
---@param value table
---@return string
local function serializeArray(value)
	local elements = {}

	for i, v in pairs(value) do
		if type(v) ~= "function" and type(v) ~= "thread" and type(v) ~= "userdata" then
			elements[i] = Serializer.marshal(v)
		end
	end

	local result = table.concat(elements)
	local length = #elements

	if length < 16 then
		return string.pack(">B", 0x90 + length) .. result
	elseif length < 65536 then
		return string.pack(">BI2", 0xdc, length) .. result
	end

	return string.pack(">BI4", 0xdd, length) .. result
end

---Serialize table to a map.
---@param value table
---@return string
local function serializeMap(value)
	local elements = {}

	for k, v in pairs(value) do
		if type(v) ~= "function" and type(v) ~= "thread" and type(v) ~= "userdata" then
			elements[#elements + 1] = Serializer.marshal(k)
			elements[#elements + 1] = Serializer.marshal(v)
		end
	end

	local length = math.floor(#elements / 2)
	if length < 16 then
		return string.pack(">B", 0x80 + length) .. table.concat(elements)
	elseif length < 65536 then
		return string.pack(">BI2", 0xde, length) .. table.concat(elements)
	end

	return string.pack(">BI4", 0xdf, length) .. table.concat(elements)
end

---Serialize nil to a binary string.
---@return string
local function serializeNil()
	return string.pack("B", 0xc0)
end

---serialize table to a binary string
---@param value table
---@return string
local function serializeTable(value)
	return isAnArray(value) and serializeArray(value) or serializeMap(value)
end

---serialize boolean to a binary string
---@param value boolean
---@return string
local function serializeBoolean(value)
	return string.pack("B", value and 0xc3 or 0xc2)
end

---serialize int to a binary string
---@param value number
---@return string
local function serializeInt(value)
	return value >= 0 and serializeSignedInt(value) or serializeUnsignedInt(value)
end

---serialize number to a binary string
---@param value number
---@return string
local function serializeNumber(value)
	return value % 1 == 0 and serializeInt(value) or serializeFloat(value)
end

---serialize string to a binary string
---@param value number
---@return string
local function serializeString(value)
	return utf8.len(value) and serializeUtf8(value) or serializeStringBytes(value)
end

-- Types mapping to functions that serialize it.
local typeToSerializeMap = {
	["nil"] = serializeNil,
	["boolean"] = serializeBoolean,
	["number"] = serializeNumber,
	["string"] = serializeString,
	["table"] = serializeTable,
}

---Marshal a value into a binary string.
---@param value any
---@return string
function Serializer.marshal(value)
	return typeToSerializeMap[type(value)](value)
end

-- Return Serializer module.
return Serializer

end)
__bundle_register("Utility/String", function(require, _LOADED, __bundle_register, __bundle_modules)
local String = {}

-- Generate mapping.
local charByteMap = {}

for idx = 0, 255 do
	charByteMap[string.char(idx)] = idx
end

---String to byte array.
---@param str string
---@return table
function String.tba(str)
	local chars = {}
	local idx = 1

	if #str == 0 then
		return {}
	end

	repeat
		chars[idx] = charByteMap[str:sub(idx, idx)]
		idx = idx + 1
	until idx == #str + 1

	return chars
end

-- Return String module.
return String

end)
__bundle_register("Utility/Deserializer", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Deserializer module.
local Deserializer = {}

---@module Utility.DeserializerStream
local DeserializerStream = require("Utility/DeserializerStream")

-- Deserialization data map.
local byteToDataMap = {
	[0xc0] = nil,
	[0xc2] = false,
	[0xc3] = true,
	[0xc4] = DeserializerStream.byte,
	[0xc5] = DeserializerStream.short,
	[0xc6] = DeserializerStream.int,
	[0xca] = DeserializerStream.float,
	[0xcb] = DeserializerStream.double,
	[0xcc] = DeserializerStream.byte,
	[0xcd] = DeserializerStream.unsignedShort,
	[0xce] = DeserializerStream.unsignedInt,
	[0xcf] = DeserializerStream.unsignedLong,
	[0xd0] = DeserializerStream.byte,
	[0xd1] = DeserializerStream.short,
	[0xd2] = DeserializerStream.int,
	[0xd3] = DeserializerStream.long,
	[0xd9] = DeserializerStream.byte,
	[0xda] = DeserializerStream.unsignedShort,
	[0xdb] = DeserializerStream.unsignedInt,
	[0xdc] = DeserializerStream.unsignedShort,
	[0xdd] = DeserializerStream.unsignedInt,
	[0xde] = DeserializerStream.unsignedShort,
	[0xdf] = DeserializerStream.unsignedInt,
}

---Decode array with a specific length and recursively read.
---@param stream DeserializerStream
---@param length number
---@return table
local function decodeArray(stream, length)
	local elements = {}

	for i = 1, length do
		elements[i] = Deserializer.at(stream)
	end

	return elements
end

---Decode map with a specific length and recursively read.
---@param stream DeserializerStream
---@param length number
---@return table, number
local function decodeMap(stream, length)
	local elements = {}

	for _ = 1, length do
		elements[Deserializer.at(stream)] = Deserializer.at(stream)
	end

	return elements
end

---Deserialize the data at a specific position.
---@param stream DeserializerStream
---@return any
function Deserializer.at(stream)
	local byte = stream:byte()
	local byteData = byteToDataMap[byte] or function()
		error("Unhandled byte data: " .. byte)
	end

	if byte == 0xde or byte == 0xdf then
		return decodeMap(stream, byteData(stream))
	end

	if byte >= 0x80 and byte <= 0x8f then
		return decodeMap(stream, byte - 0x80)
	end

	if byte >= 0x90 and byte <= 0x9f then
		return decodeArray(stream, byte - 0x90)
	end

	if byte == 0xdc or byte == 0xdd then
		return decodeArray(stream, byteData(stream))
	end

	if byte == 0xc4 or byte == 0xc5 or byte == 0xc6 then
		return stream:leReadBytes(byteData(stream))
	end

	if byte == 0xd9 or byte == 0xda or byte == 0xdb then
		return stream:string(byteData(stream))
	end

	if byte >= 0xa0 and byte <= 0xbf then
		return stream:string(byte - 0xa0)
	end

	if byte == 0xc0 or byte == 0xc1 or byte == 0xc2 then
		return byteToDataMap[byte]
	end

	if byte >= 0x00 and byte <= 0x7f then
		return byte
	end

	if byte >= 0xe0 and byte <= 0xff then
		return -32 + (byte - 0xe0)
	end

	return typeof(byteData) == "function" and byteData(stream) or byteData
end

---Starts recursively deserializing the data from the first index one time.
---@param data table
---@return any
function Deserializer.unmarshal_one(data)
	return Deserializer.at(DeserializerStream.new(data))
end

-- Return Deseralizer module.
return Deserializer

end)
__bundle_register("Utility/DeserializerStream", function(require, _LOADED, __bundle_register, __bundle_modules)
---@class DeserializerStream
---@field source table
---@field index number
local DeserializerStream = {}
DeserializerStream.__index = DeserializerStream

---Read bytes in little endian.
---@param len number
---@return number[]
function DeserializerStream:leReadBytes(len)
	local bytes = {}

	for idx = self.index + 1, self.index + len do
		bytes[#bytes + 1] = self.source[idx]
	end

	self.index = self.index + len

	if self.index > #self.source then
		return error("leReadBytes - read overflow")
	end

	return bytes
end

---Read bytes in big endianess format.
---@param len number
---@return number[]
function DeserializerStream:beReadBytes(len)
	local bytes = {}

	for idx = self.index + len, self.index + 1, -1 do
		bytes[#bytes + 1] = self.source[idx]
	end

	self.index = self.index + len

	if self.index > #self.source then
		return error("beReadBytes - read overflow")
	end

	return bytes
end

---Read string.
---@param len number
---@return string
function DeserializerStream:string(len)
	local src = self.source
	local buf = buffer.create(len)

	for idx = self.index + 1, self.index + len do
		buffer.writeu8(buf, idx - self.index - 1, src[idx])
	end

	self.index = self.index + len

	---@note: Inlined leReadBytes.
	if self.index > #self.source then
		return error("string - read overflow")
	end

	return buffer.readstring(buf, 0, len)
end

---Read unsigned long.
---@return number
function DeserializerStream:unsignedLong()
	local bytes = self:beReadBytes(8)
	local p1 = bit32.bor(bytes[1], bit32.lshift(bytes[2], 8), bit32.lshift(bytes[3], 16), bit32.lshift(bytes[4], 24))
	local p2 = bit32.bor(bytes[5], bit32.lshift(bytes[6], 8), bit32.lshift(bytes[7], 16), bit32.lshift(bytes[8], 24))
	return bit32.bor(p1, bit32.lshift(p2, 32))
end

---Read unsigned int.
---@return number
function DeserializerStream:unsignedInt()
	local bytes = self:beReadBytes(4)
	return bit32.bor(bytes[1], bit32.lshift(bytes[2], 8), bit32.lshift(bytes[3], 16), bit32.lshift(bytes[4], 24))
end

---Read unsigned short.
---@return number
function DeserializerStream:unsignedShort()
	local bytes = self:beReadBytes(2)
	return bit32.bor(bytes[1], bit32.lshift(bytes[2], 8))
end

---Read float.
---@return number
function DeserializerStream:float()
	local bytes = self:beReadBytes(4)
	local sign = (-1) ^ bit32.rshift(bytes[4], 7)
	local exp = bit32.rshift(bytes[3], 7) + bit32.lshift(bit32.band(bytes[4], 0x7F), 1)
	local frac = bytes[1] + bit32.lshift(bytes[2], 8) + bit32.lshift(bit32.band(bytes[3], 0x7F), 16)
	local normal = 1

	if exp == 0 then
		if frac == 0 then
			return sign * 0
		else
			normal = 0
			exp = 1
		end
	elseif exp == 0x7F then
		if frac == 0 then
			return sign * (1 / 0)
		else
			return sign * (0 / 0)
		end
	end

	return sign * 2 ^ (exp - 127) * (1 + normal / 2 ^ 23)
end

---Read double.
---@return number
function DeserializerStream:double()
	local bytes = self:beReadBytes(8)
	local sign = (-1) ^ bit32.rshift(bytes[8], 7)
	local exp = bit32.lshift(bit32.band(bytes[8], 0x7F), 4) + bit32.rshift(bytes[7], 4)
	local frac = bit32.band(bytes[7], 0x0F) * 2 ^ 48
	local normal = 1

	frac = frac
		+ (bytes[6] * 2 ^ 40)
		+ (bytes[5] * 2 ^ 32)
		+ (bytes[4] * 2 ^ 24)
		+ (bytes[3] * 2 ^ 16)
		+ (bytes[2] * 2 ^ 8)
		+ bytes[1]

	if exp == 0 then
		if frac == 0 then
			return sign * 0
		else
			normal = 0
			exp = 1
		end
	elseif exp == 0x7FF then
		if frac == 0 then
			return sign * (1 / 0)
		else
			return sign * (0 / 0)
		end
	end

	return sign * 2 ^ (exp - 1023) * (normal + frac / 2 ^ 52)
end

---Read long.
---@return number
function DeserializerStream:long()
	local value = self:unsignedLong()

	if bit32.band(value, 0x8000000000000000) ~= 0x0 then
		value = value - 0x800000000000000
	end

	return value
end

---Read int.
---@return number
function DeserializerStream:int()
	local value = self:unsignedInt()

	if bit32.band(value, 0x80000000) ~= 0 then
		value = value - 0x100000000
	end

	return value
end

---Read short.
---@return number
function DeserializerStream:short()
	local value = self:unsignedShort()

	if bit32.band(value, 0x8000) ~= 0 then
		value = value - 0x10000
	end

	return value
end

---Read byte.
---@return number
function DeserializerStream:byte()
	local bytes = self:leReadBytes(1)
	return bytes[1]
end

---Create new DeserializerStream object.
---@param source table
---@return DeserializerStream
function DeserializerStream.new(source)
	local self = setmetatable({}, DeserializerStream)
	self.source = source
	self.index = 0
	return self
end

-- Return DeserializerStream module.
return DeserializerStream

end)
__bundle_register("Utility/Filesystem", function(require, _LOADED, __bundle_register, __bundle_modules)
return LPH_NO_VIRTUALIZE(function()
	---@class Filesystem
	---@field _path string
	local Filesystem = {}
	Filesystem.__index = Filesystem

	---Create and get the current path.
	---@return string
	function Filesystem:path()
		if not isfolder(self._path) then
			makefolder(self._path)
		end

		return self._path
	end

	---Append path to current path.
	---@param path string
	---@return string
	function Filesystem:append(path)
		return self:path() .. "\\" .. path
	end

	---Check if filename is a file.
	---@param filename string
	---@return boolean
	function Filesystem:file(filename)
		return isfile(self:append(filename))
	end

	---Read file from path.
	---@param filename string
	---@return string
	function Filesystem:read(filename)
		if not self:file(filename) then
			return error("File does not exist or is a folder.", 2)
		end

		return readfile(self:append(filename))
	end

	---Delete file.
	---@param filename string
	---@return string
	function Filesystem:delete(filename)
		if not self:file(filename) then
			return error("File does not exist or is a folder.", 2)
		end

		return delfile(self:append(filename))
	end

	---Write file to workspace folder.
	---@param filename string
	---@param contents string?
	function Filesystem:write(filename, contents)
		writefile(self:append(filename), contents and contents or "")
	end

	---List files.
	---@param raw boolean?
	---@return table
	function Filesystem:list(raw)
		local list = listfiles(self:path())
		if not list then
			return error("File list does not exist.", 2)
		end

		local new = {}

		for idx, path in next, list do
			---@note: Solara returns full paths.
			--- C:/Users/brean/Downloads/Workspace/(path_here)/(file_here)
			--- We must get rid of the C:/Users/brean/Downloads/Workspace and have that be fully dynamic and not break
			if getexecutorname and getexecutorname():match("Solara") then
				path = string.sub(path, #listfiles()[1] + 2, #path)
			end

			---@note: Non-raw weird behavior where the path is never detected in the string. Let's manually index remove it.
			new[idx] = raw and path or string.sub(path, #(self:path() .. "\\") + 1, #path)
		end

		return new
	end

	---Create new Filesystem object.
	---@param path string
	---@return Filesystem
	function Filesystem.new(path)
		local self = setmetatable({}, Filesystem)
		self._path = path
		return self
	end

	-- Return Filesystem module.
	return Filesystem
end)()

end)
__bundle_register("Utility/Configuration", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Safe configuration getter methods.
-- The menu is the last thing initialized in the script.
local Configuration = {}

---Expect toggle value.
---@param key string
---@return any?
Configuration.expectToggleValue = LPH_NO_VIRTUALIZE(function(key)
	if not Toggles then
		return nil
	end

	local toggle = Toggles[key]

	if not toggle then
		return nil
	end

	return toggle.Value
end)

---Expect option value.
---@param key string
---@return any?
Configuration.expectOptionValue = LPH_NO_VIRTUALIZE(function(key)
	if not Options then
		return nil
	end

	local option = Options[key]

	if not option then
		return nil
	end

	return option.Value
end)

---Identify element.
---@param identifier string
---@param topLevelIdentifier string
---@return string
Configuration.identify = LPH_NO_VIRTUALIZE(function(identifier, topLevelIdentifier)
	return identifier .. topLevelIdentifier
end)

---Fetch toggle value.
---@param identifier string
---@param topLevelIdentifier string
---@return any
Configuration.idToggleValue = LPH_NO_VIRTUALIZE(function(identifier, topLevelIdentifier)
	if not Toggles then
		return nil
	end

	local toggle = Toggles[identifier .. topLevelIdentifier]
	if not toggle then
		return nil
	end

	return toggle.Value
end)

---Fetch option value.
---@param identifier string
---@param topLevelIdentifier string
---@return any
Configuration.idOptionValue = LPH_NO_VIRTUALIZE(function(identifier, topLevelIdentifier)
	if not Options then
		return nil
	end

	local option = Options[identifier .. topLevelIdentifier]
	if not option then
		return nil
	end

	return option.Value
end)

---Fetch option values.
---@param identifier string
---@param topLevelIdentifier string
---@return any
Configuration.idOptionValues = LPH_NO_VIRTUALIZE(function(identifier, topLevelIdentifier)
	if not Options then
		return nil
	end

	local option = Options[identifier .. topLevelIdentifier]
	if not option then
		return nil
	end

	return option.Values
end)

-- Return Configuration module.
return Configuration

end)
__bundle_register("Utility/Signal", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Wrapper for Roblox's signals for safe connections to signals.
-- Automatically profiles signals & wraps them in a safe alternative.
---@class Signal
---@field signal RBXScriptSignal Underlying roblox script signal
local Signal = {}
Signal.__index = Signal

---@module Utility.Profiler
local Profiler = require("Utility/Profiler")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---Safely connect to Roblox's signal.
---@param label string
---@param eventFunction function
---@return RBXScriptConnection
function Signal:connect(label, eventFunction)
	---Log event errors.
	---@param error string
	local function onEventFunctionError(error)
		Logger.trace("onEventFunctionError - (%s) - %s", label, error)
	end

	-- Connect to signal. Wrap function with profiler and error handling.
	local connection = self.signal:Connect(Profiler.wrap(
		label,
		LPH_NO_VIRTUALIZE(function(...)
			return xpcall(eventFunction, onEventFunctionError, ...)
		end)
	))

	-- Return connection.
	return connection
end

---Create new wrapper signal object.
---@param robloxSignal RBXScriptSignal
---@return Signal
function Signal.new(robloxSignal)
	-- Create new wrapper signal object.
	local self = setmetatable({}, Signal)
	self.signal = robloxSignal

	-- Return new wrapper signal object.
	return self
end

-- Return Signal module.
return Signal

end)
__bundle_register("Utility/Profiler", function(require, _LOADED, __bundle_register, __bundle_modules)
return LPH_NO_VIRTUALIZE(function()
	-- Profile code time.
	-- Determine what parts of our script are lagging us through the microprofiler.
	local Profiler = {}

	---Runs a function with a specified profiler label.
	---@param label string
	---@param functionToProfile function
	function Profiler.run(label, functionToProfile, ...)
		-- Profile under label.
		debug.profilebegin(label)

		-- Call function to profile.
		local ret_values = table.pack(functionToProfile(...))

		-- End most recent profiling.
		debug.profileend()

		-- Return values.
		return unpack(ret_values)
	end

	---Wrap function in a profiler statement with label.
	---@param label string
	---@param functionToProfile function
	---@return function
	function Profiler.wrap(label, functionToProfile)
		return function(...)
			return Profiler.run(label, functionToProfile, ...)
		end
	end

	-- Return profiler module.
	return Profiler
end)()

end)
__bundle_register("Utility/Maid", function(require, _LOADED, __bundle_register, __bundle_modules)
-- https://github.com/Quenty/NevermoreEngine/blob/version2/Modules/Shared/Events/Maid.lua
---@class Maid
local Maid = {}
Maid.__type = "maid"

---Create new Maid object.
---@return Maid
Maid.new = LPH_NO_VIRTUALIZE(function()
	return setmetatable({
		_tasks = {},
	}, Maid)
end)

---Return maid[key] - if not, it's not apart of the maid metatable - so we return the relevant task.
-- @return value
Maid.__index = LPH_NO_VIRTUALIZE(function(self, index)
	if Maid[index] then
		return Maid[index]
	else
		return self._tasks[index]
	end
end)

---Clean or add a task with a specific key.
---@param index any
---@param newTask any
Maid.__newindex = LPH_NO_VIRTUALIZE(function(self, index, newTask)
	if Maid[index] ~= nil then
		return warn(("'%s' is reserved"):format(tostring(index)), 2)
	end

	local tasks = self._tasks
	local oldTask = tasks[index]

	if oldTask == newTask then
		return
	end

	tasks[index] = newTask

	if oldTask then
		if typeof(oldTask) == "thread" then
			return coroutine.status(oldTask) == "suspended" and task.cancel(oldTask) or nil
		end

		if type(oldTask) == "function" then
			oldTask()
		elseif typeof(oldTask) == "RBXScriptConnection" then
			oldTask:Disconnect()
		elseif typeof(oldTask) == "Instance" and oldTask:IsA("Tween") then
			oldTask:Pause()
			oldTask:Cancel()
			oldTask:Destroy()
		elseif oldTask.Destroy then
			oldTask:Destroy()
		elseif oldTask.detach then
			oldTask:detach()
		end
	end
end)

---Add a task without a specific ID and return the task.
---@param task any
---@return any
Maid.mark = LPH_NO_VIRTUALIZE(function(self, task)
	self:add(task)
	return task
end)

---Get a unique ID for a task.
---@return number
Maid.uid = LPH_NO_VIRTUALIZE(function(self)
	return #self._tasks + 1
end)

---Add a task without a specific ID.
---@param task any
---@return number
Maid.add = LPH_NO_VIRTUALIZE(function(self, task)
	if not task then
		return error("task cannot be false or nil", 2)
	end

	local taskId = self:uid()
	self[taskId] = task

	return taskId
end)

---Remove task without cleaning it.
---@param taskId number
Maid.removeTask = LPH_NO_VIRTUALIZE(function(self, taskId)
	local tasks = self._tasks
	tasks[taskId] = nil
end)

---Clean up all tasks.
Maid.clean = LPH_NO_VIRTUALIZE(function(self)
	local tasks = self._tasks

	-- Disconnect all events first - as we know this is safe.
	for index, task in pairs(tasks) do
		if typeof(task) == "RBXScriptConnection" then
			tasks[index] = nil
			task:Disconnect()
		end
	end

	-- Clear out tasks table completely, even if clean up tasks add more tasks to the maid.
	local index, _task = next(tasks)

	while _task ~= nil do
		tasks[index] = nil

		if typeof(_task) == "thread" then
			if coroutine.status(_task) == "suspended" then
				task.cancel(_task)
			end
		else
			if type(_task) == "function" then
				_task()
			elseif typeof(_task) == "RBXScriptConnection" then
				_task:Disconnect()
			elseif typeof(_task) == "Instance" and _task:IsA("Tween") then
				_task:Pause()
				_task:Cancel()
				_task:Destroy()
			elseif typeof(_task) == "Instance" and _task:IsA("AnimationTrack") then
				_task:Stop()
			elseif _task.Destroy then
				_task:Destroy()
			elseif _task.detach then
				_task:detach()
			end
		end

		index, _task = next(tasks)
	end
end)

-- Return Maid module.
return Maid

end)
__bundle_register("Game/Timings/SoundTiming", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Game.Timings.Timing
local Timing = require("Game/Timings/Timing")

---@class SoundTiming: Timing
---@field id string Sound ID.
---@field rpue boolean Repeat parry until end.
---@field _rsd number Repeat start delay in miliseconds. Never access directly.
---@field _rpd number Delay between each repeat parry in miliseconds. Never access directly.
local SoundTiming = setmetatable({}, { __index = Timing })
SoundTiming.__index = SoundTiming

---Timing ID.
---@return string
function SoundTiming:id()
	return self._id
end

-- Getter for repeat start delay in seconds.
---@return number
function SoundTiming:rsd()
	return PP_SCRAMBLE_NUM(self._rsd) / 1000
end

-- Getter for repeat start delay in seconds.
---@return number
function SoundTiming:rpd()
	return PP_SCRAMBLE_NUM(self._rpd) / 1000
end

---Load from partial values.
---@param values table
function SoundTiming:load(values)
	Timing.load(self, values)

	if typeof(values._id) == "string" then
		self._id = values._id
	end

	if type(values.rsd) == "number" then
		self._rsd = values.rsd
	end

	if typeof(values.rpue) == "boolean" then
		self.rpue = values.rpue
	end

	if typeof(values.rpd) == "number" then
		self._rpd = values.rpd
	end
end

---Clone timing.
---@return SoundTiming
function SoundTiming:clone()
	local clone = setmetatable(Timing.clone(self), SoundTiming)

	clone._rpd = self._rpd
	clone.rpue = self.rpue
	clone._rsd = self._rsd
	clone._id = self._id

	return clone
end

---Return a serializable table.
---@return SoundTiming
function SoundTiming:serialize()
	local serializable = Timing.serialize(self)

	serializable._id = self._id
	serializable.rpue = self.rpue
	serializable.rsd = self._rsd
	serializable.rpd = self._rpd

	return serializable
end

---Create a new sound timing.
---@param values table?
---@return SoundTiming
function SoundTiming.new(values)
	local self = setmetatable(Timing.new(), SoundTiming)

	self._id = ""
	self.rpue = false
	self._rsd = 0
	self._rpd = 0

	if values then
		self:load(values)
	end

	return self
end

-- Return SoundTiming module.
return SoundTiming

end)
__bundle_register("Game/Timings/Timing", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Game.Timings.ActionContainer
local ActionContainer = require("Game/Timings/ActionContainer")

---@class Timing
---@field name string
---@field tag string
---@field imdd number Initial minimum distance from position.
---@field imxd number Initial maximum distance from position.
---@field punishable number Punishable window in seconds.
---@field after number After window in seconds.
---@field duih boolean Delay until in hitbox.
---@field actions ActionContainer
---@field hitbox Vector3
---@field umoa boolean Use module over actions.
---@field smn boolean Skip module notification.
---@field srpn boolean Skip repeat notification.
---@field smod string Selected module string.
---@field aatk boolean Allow attacking.
---@field fhb boolean Hitbox facing offset.
---@field ndfb boolean No dash fallback.
---@field scrambled boolean Scrambled?
local Timing = {}
Timing.__index = Timing

---Timing ID. Override me.
---@return string
function Timing:id()
	return self.name
end

---Set timing ID. Override me.
---@param id string
function Timing:set(id)
	self.name = id
end

---Load from partial values.
---@param values table
function Timing:load(values)
	if typeof(values.name) == "string" then
		self.name = values.name
	end

	if typeof(values.tag) == "string" then
		self.tag = values.tag
	end

	if typeof(values.imdd) == "number" then
		self.imdd = values.imdd
	end

	if typeof(values.imxd) == "number" then
		self.imxd = values.imxd
	end

	if typeof(values.duih) == "boolean" then
		self.duih = values.duih
	end

	if typeof(values.punishable) == "number" then
		self.punishable = values.punishable
	end

	if typeof(values.after) == "number" then
		self.after = values.after
	end

	if typeof(values.actions) == "table" then
		self.actions:load(values.actions)
	end

	if typeof(values.smn) == "boolean" then
		self.smn = values.smn
	end

	if typeof(values.hitbox) == "table" then
		self.hitbox = Vector3.new(values.hitbox.X or 0, values.hitbox.Y or 0, values.hitbox.Z or 0)
	end

	if typeof(values.umoa) == "boolean" then
		self.umoa = values.umoa
	end

	if typeof(values.srpn) == "boolean" then
		self.srpn = values.srpn
	end

	if typeof(values.smod) == "string" then
		self.smod = values.smod
	end

	if typeof(values.aatk) == "boolean" then
		self.aatk = values.aatk
	end

	if typeof(values.fhb) == "boolean" then
		self.fhb = values.fhb
	end

	if typeof(values.ndfb) == "boolean" then
		self.ndfb = values.ndfb
	end

	if typeof(values.scrambled) == "boolean" then
		self.scrambled = values.scrambled
	end
end

---Equals check.
---@param other Timing
---@return boolean
function Timing:equals(other)
	if self.name ~= other.name then
		return false
	end

	if self.tag ~= other.tag then
		return false
	end

	if self.imdd ~= other.imdd then
		return false
	end

	if self.imxd ~= other.imxd then
		return false
	end

	if self.duih ~= other.duih then
		return false
	end

	if self.punishable ~= other.punishable then
		return false
	end

	if self.after ~= other.after then
		return false
	end

	if not self.actions:equals(other.actions) then
		return false
	end

	if self.smn ~= other.smn then
		return false
	end

	if self.hitbox ~= other.hitbox then
		return false
	end

	if self.umoa ~= other.umoa then
		return false
	end

	if self.srpn ~= other.srpn then
		return false
	end

	if self.smod ~= other.smod then
		return false
	end

	if self.aatk ~= other.aatk then
		return false
	end

	if self.fhb ~= other.fhb then
		return false
	end

	if self.ndfb ~= other.ndfb then
		return false
	end

	if self.scrambled ~= other.scrambled then
		return false
	end

	return true
end

---Clone timing.
---@return Timing
function Timing:clone()
	local clone = Timing.new()

	clone.name = self.name
	clone.tag = self.tag
	clone.duih = self.duih
	clone.imdd = self.imdd
	clone.imxd = self.imxd
	clone.smn = self.smn
	clone.punishable = self.punishable
	clone.after = self.after
	clone.actions = self.actions:clone()
	clone.hitbox = self.hitbox
	clone.umoa = self.umoa
	clone.srpn = self.srpn
	clone.smod = self.smod
	clone.aatk = self.aatk
	clone.fhb = self.fhb
	clone.ndfb = self.ndfb
	clone.scrambled = self.scrambled

	return clone
end

---Return a serializable table.
---@return table
function Timing:serialize()
	return {
		name = self.name,
		tag = self.tag,
		imdd = self.imdd,
		imxd = self.imxd,
		duih = self.duih,
		punishable = self.punishable,
		smn = self.smn,
		after = self.after,
		actions = self.actions:serialize(),
		hitbox = {
			X = self.hitbox.X,
			Y = self.hitbox.Y,
			Z = self.hitbox.Z,
		},
		srpn = self.srpn,
		umoa = self.umoa,
		smod = self.smod,
		aatk = self.aatk,
		fhb = self.fhb,
		ndfb = self.ndfb,
		scrambled = self.scrambled,
		phd = self.phd,
		pfh = self.pfh,
	}
end

---Create new Timing object.
---@param values table?
---@return Timing
function Timing.new(values)
	local self = setmetatable({}, Timing)

	self.tag = "Undefined"
	self.name = "N/A"
	self.imdd = 0
	self.imxd = 0
	self.smn = false
	self.punishable = 0
	self.after = 0
	self.duih = false
	self.actions = ActionContainer.new()
	self.hitbox = Vector3.zero
	self.umoa = false
	self.srpn = false
	self.smod = "N/A"
	self.aatk = false
	self.fhb = true
	self.ndfb = false
	self.scrambled = false

	if values then
		self:load(values)
	end

	return self
end

-- Return Timing module.
return Timing

end)
__bundle_register("Game/Timings/ActionContainer", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Game.Timings.Action
local Action = require("Game/Timings/Action")

---@class ActionContainer
---@field _data table<string, Action>
local ActionContainer = {}
ActionContainer.__index = ActionContainer

---Clone action container.
---@return ActionContainer
function ActionContainer:clone()
	local clone = ActionContainer.new()

	for _, action in next, self._data do
		clone:push(action:clone())
	end

	return clone
end

---Equal check.
---@param other ActionContainer
---@return boolean
function ActionContainer:equals(other)
	if self:count() ~= other:count() then
		return false
	end

	for name, action in next, self._data do
		local otherAction = other:find(name)
		if not otherAction then
			return false
		end

		if not action:equals(otherAction) then
			return false
		end
	end

	return true
end

---Find a action from name.
---@param name string
---@return Action?
function ActionContainer:find(name)
	return self._data[name]
end

---Remove a action from the list.
---@param action Action
function ActionContainer:remove(action)
	self._data[action.name] = nil
	self._count = self._count - 1
end

---Push a action to the list.
---@param action Action
function ActionContainer:push(action)
	local name = action.name

	---@note: Action array keys must all be unique.
	if self._data[name] then
		return error(string.format("Action name '%s' already exists in container.", name))
	end

	self._data[name] = action
	self._count = self._count + 1
end

---Load from partial values.
---@param values table
function ActionContainer:load(values)
	for _, data in next, values do
		self:push(Action.new(data))
	end
end

---List all action names.
---@return string[]
function ActionContainer:names()
	local names = {}

	for name, _ in next, self._data do
		table.insert(names, name)
	end

	return names
end

---Get action count.
---@return number
function ActionContainer:count()
	return self._count
end

---Clear actions.
function ActionContainer:clear()
	self._data = {}
end

---Get action data.
---@return table<string, Action>
function ActionContainer:get()
	return self._data
end

---Return a serializable table.
---@return table
function ActionContainer:serialize()
	local data = {}

	for _, action in next, self._data do
		table.insert(data, action:serialize())
	end

	return data
end

---Create new ActionContainer object.
---@param values table?
---@return ActionContainer
function ActionContainer.new(values)
	local self = setmetatable({}, ActionContainer)

	self._data = {}
	self._count = 0

	if values then
		self:load(values)
	end

	return self
end

-- Return ActionContainer module.
return ActionContainer

end)
__bundle_register("Game/Timings/Action", function(require, _LOADED, __bundle_register, __bundle_modules)
---@class Action
---@field _type string
---@field _when number When the action will occur in miliseconds. Never access directly.
---@field hitbox Vector3 The hitbox of the action.
---@field ihbc boolean Ignore hitbox check.
---@field name string The name of the action.
---@field tp number Time position. Never accessible unless inside of a module or inside of real code. This is never serialized.
local Action = {}
Action.__index = Action

---Getter for when in seconds.
---@return number
function Action:when()
	return PP_SCRAMBLE_NUM(self._when) / 1000
end

---Load from partial values.
---@param values table
function Action:load(values)
	if typeof(values._type) == "string" then
		self._type = values._type
	end

	if typeof(values.when) == "number" then
		self._when = values.when
	end

	if typeof(values.name) == "string" then
		self.name = values.name
	end

	if typeof(values.hitbox) == "table" then
		self.hitbox = Vector3.new(values.hitbox.X, values.hitbox.Y, values.hitbox.Z)
	end

	if typeof(values.ihbc) == "boolean" then
		self.ihbc = values.ihbc
	end
end

---Equals check.
---@param other Action
---@return boolean
function Action:equals(other)
	if self._type ~= other._type then
		return false
	end

	if self._when ~= other._when then
		return false
	end

	if self.name ~= other.name then
		return false
	end

	if self.hitbox ~= other.hitbox then
		return false
	end

	if self.ihbc ~= other.ihbc then
		return false
	end

	return true
end

---Clone action.
---@return Action
function Action:clone()
	local clone = Action.new()

	clone._type = self._type
	clone._when = self._when
	clone.name = self.name
	clone.hitbox = self.hitbox
	clone.ihbc = self.ihbc

	return clone
end

---Return a serializable table.
---@return table
function Action:serialize()
	return {
		_type = self._type,
		when = self._when,
		name = self.name,
		hitbox = {
			X = self.hitbox.X,
			Y = self.hitbox.Y,
			Z = self.hitbox.Z,
		},
		ihbc = self.ihbc,
	}
end

---Create new Action object.
---@param values table?
---@return Action
function Action.new(values)
	local self = setmetatable({}, Action)

	self._type = "N/A"
	self._when = 0
	self.name = ""
	self.hitbox = Vector3.zero
	self.ihbc = false
	self.tp = 0

	if values then
		self:load(values)
	end

	return self
end

-- Return Action module.
return Action

end)
__bundle_register("Game/Timings/PartTiming", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Game.Timings.Timing
local Timing = require("Game/Timings/Timing")

---@class PartTiming: Timing
---@field pname string Part name.
---@field uhc boolean Use hitbox CFrame.
local PartTiming = setmetatable({}, { __index = Timing })
PartTiming.__index = PartTiming

---Timing ID.
---@return string
function PartTiming:id()
	return self.pname
end

---Load from partial values.
---@param values table
function PartTiming:load(values)
	Timing.load(self, values)

	if typeof(values.pname) == "string" then
		self.pname = values.pname
	end

	if typeof(values.uhc) == "boolean" then
		self.uhc = values.uhc
	end
end

---Clone timing.
---@return PartTiming
function PartTiming:clone()
	local clone = setmetatable(Timing.clone(self), PartTiming)

	clone.pname = self.pname
	clone.uhc = self.uhc

	return clone
end

---Return a serializable table.
---@return PartTiming
function PartTiming:serialize()
	local serializable = Timing.serialize(self)

	serializable.pname = self.pname
	serializable.uhc = self.uhc

	return serializable
end

---Create a new part timing.
---@param values table?
---@return PartTiming
function PartTiming.new(values)
	local self = setmetatable(Timing.new(), PartTiming)

	self.pname = ""
	self.uhc = false

	if values then
		self:load(values)
	end

	return self
end

-- Return PartTiming module.
return PartTiming

end)
__bundle_register("Game/Timings/AnimationTiming", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Game.Timings.Timing
local Timing = require("Game/Timings/Timing")

---@class AnimationTiming: Timing
---@field id string Animation ID.
---@field rpue boolean Repeat parry until end.
---@field _rsd number Repeat start delay in miliseconds. Never access directly.
---@field _rpd number Delay between each repeat parry in miliseconds. Never access directly.
---@field ha boolean Flag to see whether or not this timing can be cancelled by a hit.
---@field iae boolean Flag to see whether or not this timing should ignore animation end.
---@field phd boolean Past hitbox detection.
---@field pfh boolean Predict hitboxes facing.
---@field phds number History seconds for past hitbox detection.
---@field pfht number Extrapolation time for hitbox prediction.
---@field ieae boolean Flag to see whether or not this timing should ignore early animation end.
---@field mat number Max animation timeout in milliseconds.
---@field dp boolean Disable prediction.
local AnimationTiming = setmetatable({}, { __index = Timing })
AnimationTiming.__index = AnimationTiming

---Timing ID.
---@return string
function AnimationTiming:id()
	return self._id
end

---Getter for repeat start delay in seconds
---@return number
function AnimationTiming:rsd()
	return PP_SCRAMBLE_NUM(self._rsd) / 1000
end

---Getter for repeat parry delay in seconds.
---@return number
function AnimationTiming:rpd()
	return PP_SCRAMBLE_NUM(self._rpd) / 1000
end

---Load from partial values.
---@param values table
function AnimationTiming:load(values)
	Timing.load(self, values)

	if typeof(values._id) == "string" then
		self._id = values._id
	end

	if typeof(values.rsd) == "string" then
		self._rsd = tonumber(values.rsd) or 0.0
	end

	if typeof(values.rpd) == "string" then
		self._rpd = tonumber(values.rpd) or 0.0
	end

	if typeof(values.rsd) == "number" then
		self._rsd = values.rsd
	end

	if typeof(values.rpd) == "number" then
		self._rpd = values.rpd
	end

	if typeof(values.rpue) == "boolean" then
		self.rpue = values.rpue
	end

	if typeof(values.ha) == "boolean" then
		self.ha = values.ha
	end

	if typeof(values.iae) == "boolean" then
		self.iae = values.iae
	end

	if typeof(values.ieae) == "boolean" then
		self.ieae = values.ieae
	end

	if typeof(values.mat) == "number" then
		self.mat = values.mat
	end

	if typeof(values.phd) == "boolean" then
		self.phd = values.phd
	end

	if typeof(values.pfh) == "boolean" then
		self.pfh = values.pfh
	end

	if typeof(values.phds) == "number" then
		self.phds = values.phds
	end

	if typeof(values.pfht) == "number" then
		self.pfht = values.pfht
	end

	if typeof(values.dp) == "boolean" then
		self.dp = values.dp
	end
end

---Clone timing.
---@return AnimationTiming
function AnimationTiming:clone()
	local clone = setmetatable(Timing.clone(self), AnimationTiming)

	clone._rsd = self._rsd
	clone._rpd = self._rpd
	clone._id = self._id
	clone.rpue = self.rpue
	clone.ha = self.ha
	clone.iae = self.iae
	clone.ieae = self.ieae
	clone.mat = self.mat
	clone.phd = self.phd
	clone.pfh = self.pfh
	clone.phds = self.phds
	clone.pfht = self.pfht
	clone.dp = self.dp

	return clone
end

---Return a serializable table.
---@return AnimationTiming
function AnimationTiming:serialize()
	local serializable = Timing.serialize(self)

	serializable._id = self._id
	serializable.rsd = self._rsd
	serializable.rpd = self._rpd
	serializable.rpue = self.rpue
	serializable.ha = self.ha
	serializable.iae = self.iae
	serializable.ieae = self.ieae
	serializable.mat = self.mat
	serializable.phd = self.phd
	serializable.pfh = self.pfh
	serializable.phds = self.phds
	serializable.pfht = self.pfht
	serializable.dp = self.dp

	return serializable
end

---Create a new animation timing.
---@param values table?
---@return AnimationTiming
function AnimationTiming.new(values)
	local self = setmetatable(Timing.new(), AnimationTiming)

	self.dp = false
	self._id = ""
	self._rsd = 0
	self._rpd = 0
	self.rpue = false
	self.ha = false
	self.iae = false
	self.ieae = false
	self.mat = 2000
	self.phd = false
	self.pfh = false
	self.phds = 0
	self.pfht = 0.15

	if values then
		self:load(values)
	end

	return self
end

-- Return AnimationTiming module.
return AnimationTiming

end)
__bundle_register("Game/Timings/TimingContainer", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Utility.Logger
local Logger = require("Utility/Logger")

---@class TimingContainer
---@field timings table<string, Timing>
---@field module Timing
local TimingContainer = {}
TimingContainer.__index = TimingContainer

---Merge timing container.
---@param other TimingContainer
---@param type MergeType
function TimingContainer:merge(other, type)
	assert(type ~= 1 and type ~= 2, "Invalid timing table merge type")

	for idx, timing in next, other.timings do
		if type == 1 and timing[idx] then
			continue
		end

		self.timings[idx] = timing
	end
end

---Find a timing from name.
---@param name string
---@return Timing?
function TimingContainer:find(name)
	for _, timing in next, self.timings do
		if timing.name ~= name then
			continue
		end

		return timing
	end
end

---Clone timing container.
---@return TimingContainer
function TimingContainer:clone()
	local container = TimingContainer.new(self.module)

	for _, timing in next, self.timings do
		container:push(timing:clone())
	end

	return container
end

---List all timings.
---@return Timing[]
function TimingContainer:list()
	local timings = {}

	for _, timing in next, self.timings do
		timings[#timings + 1] = timing
	end

	return timings
end

---Get names of all timings.
---@return string[]
function TimingContainer:names()
	local names = {}

	for _, timing in next, self.timings do
		names[#names + 1] = timing.name
	end

	table.sort(names)

	return names
end

---Remove a timing from the list.
---@param timing Timing
function TimingContainer:remove(timing)
	local id = timing:id()
	if not id then
		return
	end

	self.timings[id] = nil
end

---Push a timing to the list.
---@param timing Timing
function TimingContainer:push(timing)
	local id = timing:id()
	if not id then
		return
	end

	---@note: Timing array keys must all be unique.
	if self.timings[id] then
		return error(string.format("Timing identifier '%s' already exists in container.", id))
	end

	---@note: Every timing must have unique names.
	if self:find(timing.name) then
		return error(string.format("Timing name '%s' already exists in container.", timing.name))
	end

	self.timings[id] = timing
end

---Equals check.
---@param other TimingContainer
---@return boolean
function TimingContainer:equals(other)
	if self:count() ~= other:count() then
		return false
	end

	for id, timing in next, self.timings do
		local otherTiming = other.timings[id]
		if not otherTiming then
			return false
		end

		if not timing:equals(otherTiming) then
			return false
		end
	end

	return true
end

---Clear all timings.
function TimingContainer:clear()
	self.timings = {}
end

---Get timing count.
---@return number
function TimingContainer:count()
	local count = 0

	for _ in next, self.timings do
		count = count + 1
	end

	return count
end

---Load from partial values.
---@param values table
function TimingContainer:load(values)
	for _, value in next, values do
		local timing = self.module.new(value)
		if not timing then
			continue
		end

		local id = timing:id()
		if not id then
			continue
		end

		---@note: Timing array keys must all be unique.
		if self.timings[id] then
			return error(string.format("Timing identifier '%s' already exists in container.", id))
		end

		---@note: Every timing must have unique names.
		if self:find(timing.name) then
			return error(string.format("Timing name '%s' already exists in container.", timing.name))
		end

		---@note: Why are the stored timing keys different from what's loaded?
		--- Internally, all timings are stored by their identifiers.
		--- This helps to quickly find a timing by its identifier. Example - an animation ID.
		--- Although, this does not mean each identifier must have a meaning. It can be random.

		self.timings[id] = timing
	end
end

---Return a serializable table.
---@return table
function TimingContainer:serialize()
	local out = {}

	for _, timing in next, self.timings do
		out[#out + 1] = timing:serialize()
	end

	return out
end

---Create new TimingContainer object.
---@param module Timing
---@return TimingContainer
function TimingContainer.new(module)
	local self = setmetatable({}, TimingContainer)
	self.timings = {}
	self.module = module
	return self
end

-- Return TimingContainer module.
return TimingContainer

end)
__bundle_register("Game/Timings/TimingContainerPair", function(require, _LOADED, __bundle_register, __bundle_modules)
---@class TimingContainerPair
---@note The configs are always prioritized over the internal timings.
---@field internal TimingContainer
---@field config TimingContainer
local TimingContainerPair = {}
TimingContainerPair.__index = TimingContainerPair

---Create new TimingContainerPair object.
---@param internal TimingContainer
---@param config TimingContainer
---@return TimingContainerPair
function TimingContainerPair.new(internal, config)
	local self = setmetatable({}, TimingContainerPair)
	self.internal = internal
	self.config = config
	return self
end

---Index timing container.
---@param key any?
---@return Timing?
function TimingContainerPair:index(key)
	key = PP_SCRAMBLE_STR(key)
	return self.config.timings[key] or self.internal.timings[key]
end

---Find timing from name.
---@param name string
---@return Timing?
function TimingContainerPair:find(name)
	return self.config:find(name) or self.internal:find(name)
end

---List all timings.
---@return Timing[]
function TimingContainerPair:list()
	local timings = {}

	for _, timing in next, self.config:list() do
		table.insert(timings, timing)
	end

	for _, timing in next, self.internal:list() do
		table.insert(timings, timing)
	end

	return timings
end

-- Return TimingContainerStack module.
return TimingContainerPair

end)
__bundle_register("Game/Timings/TimingSave", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Game.Timings.TimingContainer
local TimingContainer = require("Game/Timings/TimingContainer")

---@module Game.Timings.AnimationTiming
local AnimationTiming = require("Game/Timings/AnimationTiming")

---@module Game.Timings.PartTiming
local PartTiming = require("Game/Timings/PartTiming")

---@module Game.Timings.SoundTiming
local SoundTiming = require("Game/Timings/SoundTiming")

---@class TimingSave
---@field _data TimingContainer[]
local TimingSave = {}
TimingSave.__index = TimingSave

---Timing save version constant.
---@note: Increment me when the data structure changes and we need to add backwards compatibility.
local TIMING_SAVE_VERSION = 1

---@alias MergeType
---| '1' # Only add new timings
---| '2' # Overwrite and add everything

---Get timing save.
---@return TimingContainer[]
function TimingSave:get()
	return self._data
end

---Clear timing containers.
function TimingSave:clear()
	for _, container in next, self._data do
		container:clear()
	end
end

---Merge with another TimingSave object.
---@param save TimingSave The other save.
---@param type MergeType
function TimingSave:merge(save, type)
	for idx, other in next, save._data do
		local container = self._data[idx]
		if not container then
			continue
		end

		container:merge(other, type)
	end
end

---Load from partial values.
---@param values table
function TimingSave:load(values)
	local data = self._data

	if typeof(values.animation) == "table" then
		data.animation:load(values.animation)
	end

	if typeof(values.part) == "table" then
		data.part:load(values.part)
	end

	if typeof(values.sound) == "table" then
		data.sound:load(values.sound)
	end
end

---Clone timing save.
---@return TimingSave
function TimingSave:clone()
	local save = TimingSave.new()

	for idx, container in next, self._data do
		save._data[idx] = container:clone()
	end

	return save
end

---Equal timing saves.
---@param other TimingSave
---@return boolean
function TimingSave:equals(other)
	if not other or typeof(other) ~= "table" then
		return false
	end

	for idx, container in next, self._data do
		local otherContainer = other._data[idx]
		if not otherContainer then
			return false
		end

		if not container:equals(otherContainer) then
			return false
		end
	end

	return true
end

---Get timing save count.
---@return number
function TimingSave:count()
	local count = 0

	for _, container in next, self._data do
		count = count + container:count()
	end

	return count
end

---Return a serializable table.
---@return table
function TimingSave:serialize()
	local data = self._data

	return {
		version = TIMING_SAVE_VERSION,
		animation = data.animation:serialize(),
		part = data.part:serialize(),
		sound = data.sound:serialize(),
	}
end

---Create new TimingSave object.
---@param values table?
---@return TimingSave
function TimingSave.new(values)
	local self = setmetatable({}, TimingSave)

	self._data = {
		animation = TimingContainer.new(AnimationTiming),
		part = TimingContainer.new(PartTiming),
		sound = TimingContainer.new(SoundTiming),
	}

	if values then
		self:load(values)
	end

	return self
end

-- Return TimingSave module.
return TimingSave

end)
__bundle_register("Utility/CoreGuiManager", function(require, _LOADED, __bundle_register, __bundle_modules)
---@note: We need to be careful where we use CoreGui because exploits have this weird permission issue. We need consistent setting of the parent.
---@note: All scripts that must access this module should require it at the top of the file where it gets loaded.
local CoreGuiManager = {}

-- Instance list.
local instances = {}

---Mark an instance to be parented to CoreGui at initialization.
---@param instance Instance
---@return Instance
function CoreGuiManager.imark(instance)
	instances[#instances + 1] = instance
	return instance
end

---Consistently and safely parent(s) all instances to CoreGui.
---@return table
function CoreGuiManager.set()
	local coreGui = game:GetService("CoreGui")

	for _, instance in next, instances do
		instance.Parent = coreGui
	end

	return instances
end

---Remove all stored instances.
function CoreGuiManager.clear()
	for _, instance in next, instances do
		instance:Destroy()
	end

	instances = {}
end

---Return CoreGuiManager module.
return CoreGuiManager

end)
__bundle_register("Game/PlayerScanning", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Player scanning is handled here.
local PlayerScanning = {
	scanQueue = {},
	scanDataCache = {},
	friendCache = {},
	waitingForLoad = {},
	readyList = {},
	scanning = false,
}

---@module Utility.CoreGuiManager
local CoreGuiManager = require("Utility/CoreGuiManager")

---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

-- Services.
local players = game:GetService("Players")
local httpService = game:GetService("HttpService")
local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")

-- Instances.
local moderatorSound = CoreGuiManager.imark(Instance.new("Sound"))

-- Maid.
local playerScanningMaid = Maid.new()

-- Timestamp.
local lastRateLimit = nil

---Fetch name.
local function fetchName(player)
	local spoofName = Configuration.expectToggleValue("InfoSpoofing")
		and Configuration.expectToggleValue("SpoofOtherPlayers")

	return spoofName and "[REDACTED]"
		or string.format("(%s) %s", player:GetAttribute("CharacterName") or "Unknown Character Name", player.Name)
end

---Run player scans.
local runPlayerScans = LPH_NO_VIRTUALIZE(function()
	local localPlayer = players.LocalPlayer
	if not localPlayer then
		return
	end

	for player, _ in next, PlayerScanning.scanQueue do
		if shared.Lycoris.dpscanning then
			continue
		end

		if not PlayerScanning.scanDataCache[player] then
			local handledSuccess, handledResult = nil, nil

			local unhandledSuccess, unhandledResult = pcall(function()
				handledSuccess, handledResult = PlayerScanning.getStaffRank(player)
			end)

			if not unhandledSuccess then
				Logger.warn(
					"Scan player %s ran into error '%s' while getting staff rank.",
					player.Name,
					unhandledResult
				)

				Logger.longNotify("Failed to scan player %s for moderator status.", fetchName(player), unhandledResult)

				PlayerScanning.scanQueue[player] = nil

				continue
			end

			if not handledSuccess then
				continue
			end

			if Configuration.expectToggleValue("NotifyMod") and handledResult then
				Logger.longNotify("%s is a staff member with the rank '%s' in group.", fetchName(player), handledResult)

				if Configuration.expectToggleValue("NotifyModSound") then
					moderatorSound.SoundId = "rbxassetid://6045346303"
					moderatorSound.PlaybackSpeed = 1
					moderatorSound.Volume = Configuration.expectToggleValue("NotifyModSoundVolume") or 10
					moderatorSound:Play()
				end
			end

			PlayerScanning.scanDataCache[player] = { staffRank = handledResult }
		end

		PlayerScanning.scanQueue[player] = nil

		PlayerScanning.friendCache[player] = localPlayer:GetFriendStatus(player) == Enum.FriendStatus.Friend

		Logger.warn("Player scanning finished scanning %s in queue.", fetchName(player))
	end
end)

---Are there moderators in the server?
---@return table
function PlayerScanning.hasModerators()
	for _, scanData in next, PlayerScanning.scanDataCache do
		if not scanData.staffRank then
			continue
		end

		return true
	end

	return false
end

---Is a player an ally?
---@param player Player
---@return boolean
function PlayerScanning.isAlly(player)
	return PlayerScanning.friendCache[player]
end

---Fetch roblox data.
---@param url string
---@return boolean, string?
local function fetchRobloxData(url)
	if lastRateLimit and os.clock() - lastRateLimit <= 30 then
		return false, "On rate-limit cooldown."
	end

	local response = request({
		Url = url,
		Method = "GET",
		Headers = {
			["Content-Type"] = "application/json",
		},
	})

	if response.StatusCode == 429 then
		Logger.longNotify("Player scanning is being rate-limited and results will be delayed.")
		Logger.longNotify("Please stay in the server with caution.")

		lastRateLimit = os.clock()

		return false, "Rate-limited."
	end

	if not response then
		return error("Failed to fetch Roblox data.")
	end

	if not response.Success then
		return error(
			string.format("Failed to successfully fetch Roblox data with status code %i.", response.StatusCode)
		)
	end

	if not response.Body then
		return error("Failed to find Roblox data.")
	end

	return true, httpService:JSONDecode(response.Body)
end

---Get staff rank - nil if they're not a staff.
---@param player Player
---@return boolean, string?
function PlayerScanning.getStaffRank(player)
	local responseSuccess, responseData =
		fetchRobloxData(("https://groups.roblox.com/v2/users/%i/groups/roles?includeLocked=true"):format(player.UserId))

	if not responseSuccess then
		return false, responseData
	end

	local character = player.Character

	if character and character:GetAttribute("ContentCreator") then
		return true, "Content Creator"
	end

	for _, groupData in next, responseData.data do
		if groupData.group.id ~= 32740991 and groupData.group.id ~= 13077028 then
			continue
		end

		if groupData.role.rank <= 0 then
			continue
		end

		return true, groupData.role.name
	end

	return true, nil
end

---Update player scanning.
---@note: Request will yield - so we need a debounce to prevent multiple scan loops.
---@note: We must defer the error back to the caller and reset the scanning debounce so errors will not break the scanning loop.
function PlayerScanning.update()
	if PlayerScanning.scanning then
		return
	end

	PlayerScanning.scanning = true

	local success, result = pcall(runPlayerScans)

	PlayerScanning.scanning = false

	if success then
		return
	end

	return error(result)
end

---On friend status changed.
---@param player Player
---@param status Enum.FriendStatus
function PlayerScanning.friend(player, status)
	PlayerScanning.friendCache[player] = status == Enum.FriendStatus.Friend
end

---On player added.
---@param player Player
function PlayerScanning.onPlayerAdded(player)
	if player == players.LocalPlayer then
		return
	end

	PlayerScanning.scanQueue[player] = true
end

---On player removing.
---@param player Player
function PlayerScanning.onPlayerRemoving(player)
	PlayerScanning.scanQueue[player] = nil
	PlayerScanning.scanDataCache[player] = nil
	PlayerScanning.friendCache[player] = nil
	PlayerScanning.waitingForLoad[player] = nil
end

---Initialize PlayerScanning.
function PlayerScanning.init()
	-- Signals.
	local playerAddedSignal = Signal.new(players.PlayerAdded)
	local playerRemovingSignal = Signal.new(players.PlayerRemoving)
	local renderSteppedSignal = Signal.new(runService.RenderStepped)
	local friendStatusChanged = Signal.new(players.LocalPlayer.FriendStatusChanged)

	-- Connect events.
	playerScanningMaid:add(friendStatusChanged:connect("PlayerScanning_OnFriendStatusChanged", PlayerScanning.friend))
	playerScanningMaid:add(renderSteppedSignal:connect("PlayerScanning_Update", PlayerScanning.update))
	playerScanningMaid:add(playerAddedSignal:connect("PlayerScanning_OnPlayerAdded", PlayerScanning.onPlayerAdded))
	playerScanningMaid:add(
		playerRemovingSignal:connect("PlayerScanning_OnPlayerRemoving", PlayerScanning.onPlayerRemoving)
	)

	-- Run event(s) for existing players.
	for _, player in next, players:GetPlayers() do
		PlayerScanning.onPlayerAdded(player)
	end
end

---Detach PlayerScanning.
function PlayerScanning.detach()
	playerScanningMaid:clean()
end

-- Return PlayerScanning module.
return PlayerScanning

end)
__bundle_register("Utility/PersistentData", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Utility.Serializer
local Serializer = require("Utility/Serializer")

---@module Utility.Deserializer
local Deserializer = require("Utility/Deserializer")

---@module Utility.String
local String = require("Utility/String")

---@module Utility.Logger
local Logger = require("Utility/Logger")

-- PersistentData module.
local PersistentData = {
	_data = {
		-- Teleport data.
		tslot = nil,
		tdestination = nil,
	},
}

-- Services.
local memStorageService = game:GetService("MemStorageService")

---Get a field in the persistent data.
---@param field string
---@return any
function PersistentData.get(field)
	return PersistentData._data[field]
end

---Change a field in the persistent data.
---@param field string
---@param value any
function PersistentData.set(field, value)
	-- Set persistent field.
	PersistentData._data[field] = value

	-- Save the persistent data.
	local saveSuccess, saveResult = pcall(
		memStorageService.SetItem,
		memStorageService,
		"LYCORIS_PERSISTENT_DATA",
		Serializer.marshal(PersistentData._data)
	)

	if not saveSuccess then
		return Logger.warn("(%s) Failed to set PersistentData snapshot.", tostring(saveResult))
	end

	Logger.warn("(%s) Successfully set PersistentData snapshot.", tostring(saveResult))
end

---Initialize PersistentData module.
function PersistentData.init()
	local hasSuccess, hasResult = pcall(memStorageService.HasItem, memStorageService, "LYCORIS_PERSISTENT_DATA")
	if not hasSuccess then
		return hasResult and Logger.warn("(%s) Failed to check for PersistentData snapshot.", tostring(hasResult))
	end

	local itemSuccess, itemResult = pcall(memStorageService.GetItem, memStorageService, "LYCORIS_PERSISTENT_DATA")
	if not itemSuccess then
		return Logger.warn("(%s) Failed to get PersistentData snapshot", tostring(itemResult))
	end

	if itemResult == nil or itemResult == "" then
		return Logger.warn("PersistentData snapshot is missing or empty.")
	end

	local success, result = pcall(Deserializer.unmarshal_one, String.tba(itemResult))
	if not success then
		return Logger.warn("(%s) Failed to deserialize PersistentData snapshot.", tostring(result))
	end

	Logger.warn("(%s) Successfully loaded PersistentData snapshot.", tostring(result))

	PersistentData._data = result
end

-- Return PersistentData module.
return PersistentData

end)
__bundle_register("Features/Game/AnimationLogger", function(require, _LOADED, __bundle_register, __bundle_modules)
return LPH_NO_VIRTUALIZE(function()
	-- Universal Animation Logger module.
	-- Monitors all nearby Animators and logs animation plays/keyframes to the Info Logger.
	-- Also captures animation data for auto-generating timings.
	local AnimationLogger = {}

	---@module Utility.Maid
	local Maid = require("Utility/Maid")

	---@module GUI.Library
	local Library = require("GUI/Library")

	---@module Utility.Configuration
	local Configuration = require("Utility/Configuration")

	---@module Game.Timings.AnimationTiming
	local AnimationTiming = require("Game/Timings/AnimationTiming")

	---@module Game.Timings.Action
	local Action = require("Game/Timings/Action")

	---@module Game.Timings.SaveManager
	local SaveManager = require("Game/Timings/SaveManager")

	---@module Utility.Logger
	local Logger = require("Utility/Logger")

	---@module Game.DynamicTiming
	local DynamicTiming = require("Game/DynamicTiming")

	-- Services.
	local players = game:GetService("Players")

	-- Logger maid.
	local loggerMaid = Maid.new()

	-- Tracked animators mapped to their cleanup maids.
	local trackedAnimators = {}
	local isInitialized = false

	-- Captured animation data for auto-generating timings.
	-- Key: animation ID, Value: { id, entityName, length, speed, keyframes = { { name, timePosition } }, capturedAt }
	local capturedAnimations = {}

	-- Animations currently playing on nearby entities (for damage-hit capture).
	-- Key: animation ID, Value: { track = AnimationTrack, entity = Model }
	-- Note: only the most recent track per aid is stored.
	local activePlayingTracks = {}

	---Get distance from local player to an entity.
	---@param entity Model
	---@return number
	local function getDistanceTo(entity)
		local localChar = players.LocalPlayer and players.LocalPlayer.Character
		if not localChar or not localChar.PrimaryPart then
			return math.huge
		end

		local targetPart = entity:IsA("Model") and entity.PrimaryPart
			or entity:FindFirstChildWhichIsA("BasePart", true)
		if not targetPart then
			return math.huge
		end

		return (localChar.PrimaryPart.Position - targetPart.Position).Magnitude
	end

	---Check if a distance is within the configured logger range.
	---@param distance number
	---@return boolean
	local function isInRange(distance)
		local minDist = Configuration.expectOptionValue("MinimumLoggerDistance") or 0
		local maxDist = Configuration.expectOptionValue("MaximumLoggerDistance") or 0

		-- A max of 0 means no distance filtering.
		if maxDist <= 0 then
			return true
		end

		return distance >= minDist and distance <= maxDist
	end

	---Check if a distance is within the capture-specific range.
	---@param distance number
	---@return boolean
	local function isInCaptureRange(distance)
		local minDist = Configuration.expectOptionValue("CaptureMinDistance") or 0
		local maxDist = Configuration.expectOptionValue("CaptureMaxDistance") or 0

		-- A max of 0 means no distance filtering.
		if maxDist <= 0 then
			return true
		end

		return distance >= minDist and distance <= maxDist
	end

	---Get the parent entity (Model) of an Animator.
	---@param animator Animator
	---@return Model?
	local function getEntityFromAnimator(animator)
		local current = animator.Parent
		while current do
			if current:IsA("Model") and current:FindFirstChildWhichIsA("Humanoid") then
				return current
			end
			current = current.Parent
		end
		return nil
	end

	---Track an animator and log its animations.
	---@param animator Animator
	---@param entity Model
	local function trackAnimator(animator, entity)
		if trackedAnimators[animator] then
			return
		end

		-- Skip the local player's own animator.
		local localChar = players.LocalPlayer and players.LocalPlayer.Character
		if localChar and entity == localChar then
			return
		end

		local animMaid = Maid.new()
		trackedAnimators[animator] = animMaid

		-- Listen for new animations being played.
		animMaid:add(animator.AnimationPlayed:Connect(function(track)
			local distance = getDistanceTo(entity)
			local inLogRange = isInRange(distance)
			local inCaptureRange = isInCaptureRange(distance)

			if not inLogRange and not inCaptureRange then
				return
			end

			local aid = track.Animation and track.Animation.AnimationId or "Unknown"

			-- Log the animation play event.
			if inLogRange then
				Library:AddTelemetryEntry(
					"(%.1fm) '%s' played '%s' (Speed: %.2f, Length: %.3f)",
					distance,
					entity.Name,
					aid,
					track.Speed,
					track.Length
				)
			end

			-- Capture animation data if enabled.
			if Configuration.expectToggleValue("EnableAnimationCapture") and inCaptureRange then
				if not capturedAnimations[aid] then
					capturedAnimations[aid] = {
						id = aid,
						entityName = entity.Name,
						length = track.Length,
						speed = track.Speed,
						keyframes = {},
						capturedAt = os.clock(),
					}
				end

				-- Register as an active playing track so damage-hit capture can snapshot it.
				activePlayingTracks[aid] = { track = track, entity = entity }

				-- Deregister when the track stops.
				animMaid:add(track.Stopped:Connect(function()
					if activePlayingTracks[aid] and activePlayingTracks[aid].track == track then
						activePlayingTracks[aid] = nil
					end
				end))
			end

			-- Listen for keyframes on this track.
			animMaid:add(track.KeyframeReached:Connect(function(kfName)
				if inLogRange then
					Library:AddKeyFrameEntry(getDistanceTo(entity), aid, kfName, track.TimePosition, false)
				end

				-- Capture keyframe data if enabled.
				if Configuration.expectToggleValue("EnableAnimationCapture") and inCaptureRange and capturedAnimations[aid] then
					local kfs = capturedAnimations[aid].keyframes
					local exists = false

					for _, kf in next, kfs do
						if kf.name == kfName then
							exists = true
							break
						end
					end

					if not exists then
						table.insert(kfs, {
							name = kfName,
							timePosition = track.TimePosition,
						})
					end
				end
			end))
		end))

		-- Clean up when the animator is removed from the game.
		animMaid:add(animator.Destroying:Connect(function()
			if trackedAnimators[animator] then
				trackedAnimators[animator]:clean()
				trackedAnimators[animator] = nil
			end
		end))
	end

	---Scan an entity for an Animator and start tracking it.
	---@param entity Model
	local function scanEntity(entity)
		if not entity then
			return
		end

		local animator = entity:FindFirstChildWhichIsA("Animator", true)
		if animator then
			trackAnimator(animator, entity)
		end
	end

	---Handle a player joining or their character spawning.
	---@param player Player
	local function onPlayer(player)
		if player == players.LocalPlayer then
			return
		end

		if player.Character then
			scanEntity(player.Character)
		end

		loggerMaid:add(player.CharacterAdded:Connect(function(char)
			-- Wait briefly for Animator to be added.
			task.defer(function()
				scanEntity(char)
			end)
		end))
	end

	---Handle a new Animator appearing anywhere in workspace (catches NPCs).
	---@param descendant Instance
	local function onDescendantAdded(descendant)
		if not descendant:IsA("Animator") then
			return
		end

		local entity = getEntityFromAnimator(descendant)
		if entity then
			trackAnimator(descendant, entity)
		end
	end

	---Get list of captured animation IDs.
	---@return string[]
	function AnimationLogger.capturedList()
		local list = {}

		for aid, data in next, capturedAnimations do
			table.insert(list, string.format("%s (%s)", data.entityName, aid))
		end

		table.sort(list)

		return list
	end

	---Get captured animation data by animation ID.
	---@param aid string
	---@return table?
	function AnimationLogger.getCaptured(aid)
		return capturedAnimations[aid]
	end

	---Get all captured animations.
	---@return table
	function AnimationLogger.getAllCaptured()
		return capturedAnimations
	end

	---Clear all captured animations.
	function AnimationLogger.clearCaptured()
		capturedAnimations = {}
	end

	---Generate an AnimationTiming from a captured animation and push it into the config.
	---@param aid string The animation ID to generate from.
	---@param timingName string? Optional custom name (defaults to entityName_shortened_id).
	---@return boolean, string
	function AnimationLogger.generateTiming(aid, timingName)
		local data = capturedAnimations[aid]
		if not data then
			return false, "No captured data for animation ID: " .. tostring(aid)
		end

		-- Check SaveManager is ready.
		if not SaveManager.as then
			return false, "SaveManager not initialized."
		end

		-- Check if timing already exists.
		local existing = SaveManager.as:index(aid)
		if existing then
			return false, string.format("Timing already exists for '%s' (%s).", aid, existing.name)
		end

		-- Generate a name if not provided.
		local name = timingName
		if not name or #name <= 0 then
			-- Use entityName + short ID.
			local shortId = aid:match("(%d+)$") or tostring(os.clock())
			name = string.format("%s_%s", data.entityName, shortId)
		end

		-- Check name uniqueness.
		local existingName = SaveManager.as:find(name)
		if existingName then
			return false, string.format("Timing name '%s' already exists.", name)
		end

		-- Create the timing.
		local timing = AnimationTiming.new()
		timing._id = aid
		timing.name = name
		timing.tag = "Undefined"
		timing.imdd = 0
		timing.imxd = 100
		timing.hitbox = Vector3.new(20, 20, 30)
		timing.fhb = true
		timing.pfh = true
		timing.pfht = 0.15

		-- ── Determine the best raw _when value ──────────────────────────────
		-- Priority: damage-hit capture > named keyframe > all keyframes > length fallback.

		if data.damageHitTime then
			-- Damage-hit capture: adjust for projectile travel time via DynamicTiming.
			local rawMs = data.damageHitTime.timePos * 1000
			local dist = data.damageHitTime.distance
			local adjMs = DynamicTiming.adjust(rawMs, dist, aid, nil)

			local action = Action.new()
			action.name = "Action_DamageHit_1"
			action._type = "Parry"
			action._when = PP_SCRAMBLE_RE_NUM(math.round(adjMs))
			action.hitbox = Vector3.new(20, 20, 30)
			action.ihbc = false

			timing.actions:push(action)

			Logger.notify(
				"[DynamicTiming] '%s': raw=%.0fms dist=%.1fst adj=%.0fms",
				name, rawMs, dist, adjMs
			)
		else
			-- Fallback: keyframe-based generation (original behaviour).
			local hitKeyframes = {}
			for _, kf in next, data.keyframes do
				local kfLower = string.lower(kf.name)
				if kfLower:find("hit") or kfLower:find("damage") or kfLower:find("attack") or kfLower:find("impact") then
					table.insert(hitKeyframes, kf)
				end
			end

			local actionKeyframes = #hitKeyframes > 0 and hitKeyframes or data.keyframes

			if #actionKeyframes > 0 then
				table.sort(actionKeyframes, function(a, b)
					return a.timePosition < b.timePosition
				end)

				for i, kf in next, actionKeyframes do
					local action = Action.new()
					action.name = string.format("Action_%s_%d", kf.name, i)
					action._type = "Parry"
					action._when = PP_SCRAMBLE_RE_NUM(math.round(kf.timePosition * 1000))
					action.hitbox = Vector3.new(20, 20, 30)
					action.ihbc = false

					timing.actions:push(action)
				end
			else
				-- No keyframes at all — use 60% of animation length.
				local action = Action.new()
				action.name = "Action_Default_1"
				action._type = "Parry"
				action._when = PP_SCRAMBLE_RE_NUM(math.round(data.length * 0.6 * 1000))
				action.hitbox = Vector3.new(20, 20, 30)
				action.ihbc = false

				timing.actions:push(action)
			end
		end

		-- Push into SaveManager config.
		local success, err = pcall(SaveManager.as.config.push, SaveManager.as.config, timing)
		if not success then
			return false, "Failed to push timing: " .. tostring(err)
		end

		Logger.notify("Generated timing '%s' for animation '%s' with %d action(s).", name, aid, timing.actions:count())

		return true, name
	end

	---Generate timings for ALL captured animations.
	---@return number, number
	function AnimationLogger.generateAll()
		local successCount = 0
		local failCount = 0

		for aid, _ in next, capturedAnimations do
			local success, _ = AnimationLogger.generateTiming(aid)

			if success then
				successCount = successCount + 1
			else
				failCount = failCount + 1
			end
		end

		Logger.notify("Generated %d timings (%d skipped/failed).", successCount, failCount)

		return successCount, failCount
	end

	---Hook the local player's Humanoid HealthChanged to capture damage-hit timestamps.
	---Called once per character spawn so it always targets the current Humanoid.
	---@param character Model
	local function hookLocalDamage(character)
		local humanoid = character:FindFirstChildWhichIsA("Humanoid")
		if not humanoid then
			return
		end

		local lastHealth = humanoid.Health

		loggerMaid:add(humanoid.HealthChanged:Connect(function(newHealth)
			-- Only care about damage (health decrease).
			if newHealth >= lastHealth then
				lastHealth = newHealth
				return
			end

			lastHealth = newHealth

			-- Snapshot every currently-active animation's time position and distance.
			-- This becomes the authoritative 'when' for auto-generated timings.
			if not Configuration.expectToggleValue("EnableAnimationCapture") then
				return
			end

			for aid, entry in next, activePlayingTracks do
				if not capturedAnimations[aid] then
					continue
				end

				local timePos = entry.track.TimePosition
				local dist = getDistanceTo(entry.entity)

				-- Only update if this snapshot is more recent (later in the animation).
				local existing = capturedAnimations[aid].damageHitTime
				if not existing or timePos > existing.timePos then
					capturedAnimations[aid].damageHitTime = {
						timePos = timePos,
						distance = dist,
					}

					Library:AddTelemetryEntry(
						"[DamageCap] '%s' hit at tp=%.3fs dist=%.1fst",
						capturedAnimations[aid].entityName,
						timePos,
						dist
					)
				end
			end
		end))
	end

	---Initialize AnimationLogger module.
	function AnimationLogger.init()
		if isInitialized then
			return
		end

		-- Hook local player damage on current and future characters.
		local localPlayer = players.LocalPlayer
		if localPlayer then
			if localPlayer.Character then
				hookLocalDamage(localPlayer.Character)
			end

			loggerMaid:add(localPlayer.CharacterAdded:Connect(function(char)
				task.defer(function()
					hookLocalDamage(char)
				end)
			end))
		end

		-- Track existing players.
		for _, player in next, players:GetPlayers() do
			onPlayer(player)
		end

		-- Track new players.
		loggerMaid:add(players.PlayerAdded:Connect(function(player)
			onPlayer(player)
		end))

		-- Track Animators appearing in workspace (NPCs, etc).
		loggerMaid:add(workspace.DescendantAdded:Connect(onDescendantAdded))

		-- Scan existing workspace descendants for Animators.
		for _, descendant in next, workspace:GetDescendants() do
			onDescendantAdded(descendant)
		end

		isInitialized = true
	end

	---Detach AnimationLogger module.
	function AnimationLogger.detach()
		for _, maid in next, trackedAnimators do
			maid:clean()
		end

		trackedAnimators = {}
		loggerMaid:clean()
		isInitialized = false
	end

	-- Return AnimationLogger module.
	return AnimationLogger
end)()

end)
__bundle_register("Game/DynamicTiming", function(require, _LOADED, __bundle_register, __bundle_modules)
-- DynamicTiming module.
-- Calculates a latency- and distance-compensated action trigger time from raw
-- observed data (keyframe timestamp or damage-hit timestamp).
--
-- Architecture note:
--   The AnimatorDefender already compensates for ping via its `offset` field
--   (set to `rdelay()` at init).  DynamicTiming's job is orthogonal: it
--   subtracts projectile travel-time from the raw `_when` so that stored
--   timings fire BEFORE the projectile arrives, not at impact.
--
--   For melee attacks the travel speed is effectively instant, so the
--   dictionary value should be a large number (e.g. 999) to make
--   travelTimeMs negligible.
--
-- Usage (inside AnimationLogger.generateTiming):
--   local adjMs = DynamicTiming.adjust(rawWhenMs, distanceStuds, aid, nil)
--   action._when = adjMs
local DynamicTiming = {}

-- Default fallback attack speed (studs / second).
-- Applies when no dictionary entry exists and no projectile part is supplied.
DynamicTiming.defaultSpeed = 40

-- Per-animation-ID attack speed overrides.  Keys are full rbxassetid:// strings.
-- Melee attacks should use a very large value so travel time is ~0.
-- Projectiles should use their actual stud/s travel speed.
local attackSpeedDictionary = {}

---Resolve the attack speed for a given animation ID and optional projectile part.
---@param aid string Full animation asset ID (e.g. "rbxassetid://123456").
---@param projectilePart BasePart? If the attack spawns a moving part, pass it here.
---@return number studs per second
local function resolveSpeed(aid, projectilePart)
	-- 1. Try live physics velocity from the projectile part.
	if projectilePart and projectilePart:IsA("BasePart") then
		local speed = projectilePart.AssemblyLinearVelocity.Magnitude
		if speed > 0.1 then
			return speed
		end
		-- Velocity was zero (anchored / not yet moving). Fall through.
	end

	-- 2. Dictionary lookup.
	local dictSpeed = attackSpeedDictionary[aid]
	if dictSpeed and dictSpeed > 0 then
		return dictSpeed
	end

	-- 3. Global default.
	return DynamicTiming.defaultSpeed
end

---Adjust a raw observed `_when` value (in milliseconds) to account for
---projectile travel time.
---
---Formula:
---  adjustedMs = rawWhenMs - (distanceStuds / attackSpeed) * 1000
---
---A negative result is clamped to 0 (fire as soon as animation plays).
---
---@param rawWhenMs number Raw `_when` in milliseconds (from damage-hit or keyframe).
---@param distanceStuds number Distance from attacker to defender at the time of
---                             capture, in studs.
---@param aid string Full animation asset ID string.
---@param projectilePart BasePart? Optional live projectile BasePart.
---@return number adjustedMs Adjusted `_when` in milliseconds, >= 0.
function DynamicTiming.adjust(rawWhenMs, distanceStuds, aid, projectilePart)
	local speed = resolveSpeed(aid, projectilePart)

	-- Time (seconds) for the attack to travel from attacker to defender.
	local travelTimeMs = (distanceStuds / speed) * 1000

	local adjusted = rawWhenMs - travelTimeMs

	return math.max(adjusted, 0)
end

---Set the attack speed for a specific animation ID.
---@param aid string Full animation asset ID string.
---@param speed number studs per second (use 999 for instant/melee).
function DynamicTiming.setSpeed(aid, speed)
	attackSpeedDictionary[aid] = speed
end

---Get the stored attack speed for a specific animation ID.
---Returns nil if no entry exists (defaultSpeed will be used at adjust-time).
---@param aid string
---@return number?
function DynamicTiming.getSpeed(aid)
	return attackSpeedDictionary[aid]
end

---Bulk-set speeds from a dictionary table { [aid] = speed }.
---@param dict table<string, number>
function DynamicTiming.loadSpeeds(dict)
	for aid, speed in next, dict do
		attackSpeedDictionary[aid] = speed
	end
end

-- Return module.
return DynamicTiming

end)
__bundle_register("Game/Timings/ModuleManager", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Internal modules if they exist, provided by to by preprocessor.
local INTERNAL_MODULES = {}
local INTERNAL_GLOBALS = {}

-- Module manager.
---@note: All globals get executed first but never ran. This gets set in the global environment of every future module after.
local ModuleManager = { modules = {}, globals = {} }

---@module Utility.Filesystem
local Filesystem = require("Utility/Filesystem")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Game.Timings.Action
local Action = require("Game/Timings/Action")

---@module Features.Combat.Objects.Task
local Task = require("Features/Combat/Objects/Task")

---@module Game.Timings.Timing
local Timing = require("Game/Timings/Timing")

---@module Utility.TaskSpawner
local TaskSpawner = require("Utility/TaskSpawner")

---@module Features.Combat.Targeting
local Targeting = require("Features/Combat/Targeting")

---@module Game.Timings.PartTiming
local PartTiming = require("Game/Timings/PartTiming")

---@module Features.Combat.Objects.HitboxOptions
local HitboxOptions = require("Features/Combat/Objects/HitboxOptions")

---@module Features.Combat.Objects.RepeatInfo
local RepeatInfo = require("Features/Combat/Objects/RepeatInfo")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.Signal
local Signal = require("Utility/Signal")

-- Module filesystem.
local fs = Filesystem.new("Lycoris-Rewrite-TypeSoul-Modules")
local gfs = Filesystem.new(fs:append("Globals"))

-- Detach table.
local tdetach = {}

---Execute module function.
---@param lf function
---@param id string
---@param file string?
---@param global boolean
function ModuleManager.execute(lf, id, file, global)
	---@module Features.Combat.Defense
	---@note: For some reason, it broke lol. Returned nil.
	-- Has to do with loadingPlaceholder issue. A very wide cyclic dependency where depdendencies rely on each other can break the bundler.
	local Defense = require("Features/Combat/Defense")

	-- Set function environment to allow for internal modules.
	getfenv(lf).Timing = Timing
	getfenv(lf).PartTiming = PartTiming
	getfenv(lf).Defense = Defense
	getfenv(lf).Action = Action
	getfenv(lf).Task = Task
	getfenv(lf).Maid = Maid
	getfenv(lf).Signal = Signal
	getfenv(lf).TaskSpawner = TaskSpawner
	getfenv(lf).Targeting = Targeting
	getfenv(lf).Logger = Logger
	getfenv(lf).HitboxOptions = HitboxOptions
	getfenv(lf).RepeatInfo = RepeatInfo

	-- Load globals if we should.
	for name, entry in next, (not global) and ModuleManager.globals or {} do
		getfenv(lf)[name] = entry
	end

	-- Run executable function to initialize it.
	local success, result = pcall(lf)
	if not success then
		return Logger.warn("Module '%s' failed to load due to error '%s' while executing.", file or id, result)
	end

	if global and typeof(result) ~= "table" then
		return Logger.warn("Global module '%s' is invalid because it does not return a table.", file or id)
	end

	-- Output table.
	local output = global and ModuleManager.globals or ModuleManager.modules

	-- Get the result as a function.
	output[id] = result

	-- If this is a global, the result is a table, and it has a detach function, store it for later.
	if typeof(result) == "table" and typeof(result.detach) == "function" then
		tdetach[#tdetach + 1] = result.detach
	end
end

---Load file modules from filesystem.
---@param tfs Filesystem The filesystem to load from.
---@param global boolean Whether we're loading global modules or not.
function ModuleManager.load(tfs, global)
	for _, file in next, tfs:list(false) do
		-- Check if it is .lua.
		if string.sub(file, #file - 3, #file) ~= ".lua" then
			continue
		end

		-- Get string to load.
		local ls = tfs:read(file)

		-- Get function that we can execute.
		local lf, lr = loadstring(ls)
		if not lf then
			Logger.warn("Module file '%s' failed to load due to error '%s' while loading.", file, lr)
			continue
		end

		ModuleManager.execute(lf, string.sub(file, 1, #file - 4), file, global)
	end
end

---List loaded modules.
---@return string[]
function ModuleManager.loaded()
	local out = {}

	for file, _ in next, ModuleManager.modules do
		table.insert(out, file)
	end

	return out
end

---Detach functions.
function ModuleManager.detach()
	for _, detach in next, tdetach do
		detach()
	end

	-- Clear detach table.
	tdetach = {}
end

---Refresh ModuleManager.
function ModuleManager.refresh()
	-- Detach all modules.
	ModuleManager.detach()

	-- Reset current list.
	ModuleManager.modules = {}
	ModuleManager.globals = {}

	for id, lf in next, INTERNAL_GLOBALS do
		ModuleManager.execute(lf, id, nil, true)
	end

	for id, lf in next, INTERNAL_MODULES do
		ModuleManager.execute(lf, id, nil, false)
	end

	-- Load all globals in our filesystem.
	ModuleManager.load(gfs, true)

	-- Load all modules in our filesystem.
	ModuleManager.load(fs, false)
end

-- Return ModuleManager module.
return ModuleManager

end)
__bundle_register("Features/Combat/Defense", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.OriginalStore
local OriginalStore = require("Utility/OriginalStore")

---@module Features.Combat.Objects.AnimatorDefender
local AnimatorDefender = require("Features/Combat/Objects/AnimatorDefender")

---@module Features.Combat.Objects.PartDefender
local PartDefender = require("Features/Combat/Objects/PartDefender")

---@module Features.Combat.Targeting
local Targeting = require("Features/Combat/Targeting")

---@module Features.Combat.Objects.SoundDefender
local SoundDefender = require("Features/Combat/Objects/SoundDefender")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Features.Combat.PositionHistory
local PositionHistory = require("Features/Combat/PositionHistory")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module GUI.Library
local Library = require("GUI/Library")

---@module Utility.TaskSpawner
local TaskSpawner = require("Utility/TaskSpawner")

-- Handle all defense related functions.
local Defense = {}

-- Services.
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

-- Auto rotate store.
local autoRotateStore = OriginalStore.new()

-- Maids.
local defenseMaid = Maid.new()

-- Defender objects.
local defenderObjects = {}
local defenderPartObjects = {}
local defenderAnimationObjects = {}

-- Stored deleted playback data.
local deletedPlaybackData = {}

-- Visualization updating.
local lastVisualizationUpdate = os.clock()

-- Last history updating.
local lastHistoryUpdate = os.clock()

-- Aim lock state.
local stickyTarget = nil

---Add animator defender.
---@param animator Animator
local addAnimatorDefender = LPH_NO_VIRTUALIZE(function(animator)
	local animationDefender = AnimatorDefender.new(animator)
	defenderObjects[animator] = animationDefender
	defenderAnimationObjects[animator] = animationDefender
end)

---Add sound defender.
---@param sound Sound
local addSoundDefender = LPH_NO_VIRTUALIZE(function(sound)
	---@note: If there's nothing to base the sound position off of, then I'm just gonna skip it bruh.
	local part = sound:FindFirstAncestorWhichIsA("BasePart")
	if not part then
		return
	end

	-- Add sound defender.
	defenderObjects[sound] = SoundDefender.new(sound, part)
end)

---Add parry log.
local addParryLog = LPH_NO_VIRTUALIZE(function(descendant)
	local localPlayer = players.LocalPlayer
	local character = localPlayer and localPlayer.Character
	if not character then
		return
	end

	local effectFolder = descendant:FindFirstAncestorWhichIsA("Folder")
	if not effectFolder then
		return
	end

	if effectFolder.Name ~= character.Name then
		return
	end

	Library:AddTelemetryEntry("(%s) Instance '%s' created in effect folder.", effectFolder.Name, descendant.Name)
end)

--- Add damage logger.
---@param player Player
local addDamageLogger = LPH_NO_VIRTUALIZE(function(player)
	local character = player.Character or player.CharacterAdded:Wait()

	---@type Humanoid
	local humanoid = character:WaitForChild("Humanoid")
	if not humanoid then
		return
	end

	local healthChanged = Signal.new(humanoid.HealthChanged)
	local currentHealth = humanoid.Health

	defenseMaid:add(healthChanged:connect("Defense_HumanoidHealthChange", function(health)
		if currentHealth <= health then
			return
		end

		local change = currentHealth - health

		Library:AddTelemetryEntry(
			string.format("(%.2f/%.2f) (%.2f) Humanoid health change detected.", health, humanoid.MaxHealth, change)
		)

		currentHealth = health
	end))
end)

---On player added.
local onPlayerAdded = LPH_NO_VIRTUALIZE(function(player)
	if player ~= players.LocalPlayer then
		return
	end

	defenseMaid:add(TaskSpawner.spawn("Defense_AddDamageLogger", addDamageLogger, player))
end)

---On game descendant added.
---@param descendant Instance
local onGameDescendantAdded = LPH_NO_VIRTUALIZE(function(descendant)
	if descendant:IsA("Animator") then
		return addAnimatorDefender(descendant)
	end

	if descendant:IsA("Sound") then
		return addSoundDefender(descendant)
	end

	if descendant:IsA("BasePart") then
		return descendant.Name == "ParryEffect" and addParryLog(descendant) or Defense.cdpo(descendant)
	end
end)

---On game descendant removed.
---@param descendant Instance
local onGameDescendantRemoved = LPH_NO_VIRTUALIZE(function(descendant)
	local object = defenderObjects[descendant]
	if not object then
		return
	end

	if object.rpbdata then
		deletedPlaybackData[descendant] = object.rpbdata
	end

	if defenderPartObjects[descendant] then
		defenderPartObjects[descendant] = nil
	end

	if defenderAnimationObjects[descendant] then
		defenderAnimationObjects[descendant] = nil
	end

	object:detach()
	object[descendant] = nil
end)

---Update history.
local updateHistory = LPH_NO_VIRTUALIZE(function()
	if os.clock() - lastHistoryUpdate <= 0.05 then
		return
	end

	lastHistoryUpdate = os.clock()

	local character = players.LocalPlayer.Character
	if not character then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	PositionHistory.add(players.LocalPlayer, humanoidRootPart.CFrame, tick())

	for _, player in next, players:GetPlayers() do
		if player == players.LocalPlayer then
			continue
		end

		local pcharacter = player.Character
		if not pcharacter then
			continue
		end

		local proot = pcharacter:FindFirstChild("HumanoidRootPart")
		if not proot then
			continue
		end

		PositionHistory.add(pcharacter, proot.CFrame, tick())
	end
end)

---Update visualization.
local updateVisualizations = LPH_NO_VIRTUALIZE(function()
	if os.clock() - lastVisualizationUpdate <= 5.0 then
		return
	end

	lastVisualizationUpdate = os.clock()

	for _, object in next, defenderObjects do
		for idx, hitbox in next, object.hmaid._tasks do
			if typeof(hitbox) ~= "Instance" then
				continue
			end

			---@note: We call :Debris so we don't have to clean it up ourselves. We just unregister it from the maid.
			if hitbox.Parent then
				continue
			end

			object.hmaid._tasks[idx] = nil
		end
	end
end)

---On quick client effect.
local onQuickClientEffect = LPH_NO_VIRTUALIZE(function(_, _, skillData, _)
	if not skillData or skillData.Skill ~= "TimingPrompt" then
		return
	end

	if not Configuration.expectToggleValue("AutoTimingPrompt") then
		return
	end

	local character = players.LocalPlayer.Character
	if not character then
		return
	end

	local characterHandler = character:FindFirstChild("CharacterHandler")
	if not characterHandler then
		return
	end

	local remotes = characterHandler:FindFirstChild("Remotes")
	if not remotes then
		return
	end

	local m2Remote = remotes:FindFirstChild("M2")
	if not m2Remote then
		return
	end

	m2Remote:FireServer()
end)

---Update assistance.
local updateAssistance = LPH_NO_VIRTUALIZE(function()
	local localPlayer = players.LocalPlayer
	local character = localPlayer.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid")
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not humanoidRootPart then
		return
	end

	if Configuration.expectToggleValue("ForceAutoRotate") then
		humanoid.AutoRotate = true
	end

	if not Configuration.expectToggleValue("AimLock") or not Configuration.expectToggleValue("StickyTargets") then
		stickyTarget = nil
	end

	if not Configuration.expectToggleValue("AimLock") then
		return not Configuration.expectToggleValue("ForceAutoRotate") and autoRotateStore:restore()
	end

	if Configuration.expectToggleValue("StickyTargets") then
		stickyTarget = stickyTarget or Targeting.best()[1]
	end

	local target = stickyTarget or Targeting.best()[1]
	local failure = false

	if not target then
		failure = true
		stickyTarget = nil
	end

	if target and not target.character.Parent then
		failure = true
		stickyTarget = nil
	end

	if target and target.humanoid.Health <= 0 then
		failure = true
		stickyTarget = nil
	end

	if failure then
		return not Configuration.expectToggleValue("ForceAutoRotate") and autoRotateStore:restore()
	end

	if humanoid.PlatformStand then
		return
	end

	if character:GetAttribute("CurrentState") == "Unconscious" then
		return
	end

	if target.character:GetAttribute("CurrentState") == "Unconscious" then
		return
	end

	local targetPosition = target.root.Position

	if not Configuration.expectToggleValue("VerticalInfluence") then
		targetPosition = Vector3.new(targetPosition.X, humanoidRootPart.Position.Y, targetPosition.Z)
	end

	local targetCFrame = CFrame.lookAt(humanoidRootPart.Position, targetPosition)

	if Configuration.expectToggleValue("ForceAutoRotate") then
		humanoid.AutoRotate = false
	else
		autoRotateStore:set(humanoid, "AutoRotate", false)
	end

	---@note: https://www.unknowncheats.me/forum/counterstrike-global-offensive/141636-scaled-smoothing-adaptive-smoothing.html
	if Configuration.expectToggleValue("Smoothing") then
		local alpha = tweenService:GetValue(
			math.clamp(1 - (Configuration.expectOptionValue("SmoothingFactor") or 0.1), 0, 1),
			Enum.EasingStyle[Configuration.expectOptionValue("SmoothingStyle") or "Linear"],
			Enum.EasingDirection[Configuration.expectOptionValue("SmoothingDirection") or "In"]
		)

		humanoidRootPart.CFrame = humanoidRootPart.CFrame:Lerp(targetCFrame, alpha)
	else
		humanoidRootPart.CFrame = targetCFrame
	end
end)

---Update defenders.
local updateDefenders = LPH_NO_VIRTUALIZE(function()
	for _, object in next, defenderAnimationObjects do
		object:update()
	end

	if not Configuration.expectToggleValue("EnableAutoDefense") then
		return
	end

	for _, object in next, defenderPartObjects do
		object:update()
	end
end)

---Toggle visualizations.
Defense.visualizations = LPH_NO_VIRTUALIZE(function()
	for _, object in next, defenderObjects do
		for _, hitbox in next, object.hmaid._tasks do
			if typeof(hitbox) ~= "Instance" then
				continue
			end

			hitbox.Transparency = Configuration.expectToggleValue("EnableVisualizations") and 0.2 or 1.0
		end
	end
end)

---Create a defender part object.
---@param part BasePart
---@param timing PartTiming
---@return PartDefender?
Defense.cdpo = LPH_NO_VIRTUALIZE(function(part, timing)
	local partDefender = PartDefender.new(part, timing)
	if not partDefender then
		return nil
	end

	defenderObjects[part] = partDefender
	defenderPartObjects[part] = partDefender

	return partDefender
end)

---Return the defender animation object for an entity.
---@param entity Instance
---@return AnimatorDefender?
Defense.dao = LPH_NO_VIRTUALIZE(function(entity)
	for _, object in next, defenderAnimationObjects do
		if object.entity ~= entity then
			continue
		end

		return object
	end
end)

---Get playback data of first defender with Animation ID.
---@param aid string
---@return PlaybackData?
Defense.agpd = LPH_NO_VIRTUALIZE(function(aid)
	---@note: Grabbing from 'rpbdata' means that we know that the data has been fully recorded.
	for _, object in next, defenderAnimationObjects do
		local pbdata = object.rpbdata[aid]
		if not pbdata then
			continue
		end

		return pbdata
	end

	---@note: Fallback to deleted playback data if that doesn't exist.
	for _, rpbdata in next, deletedPlaybackData do
		local pbdata = rpbdata[aid]
		if not pbdata then
			continue
		end

		return pbdata
	end
end)

---Initialize defense.
function Defense.init()
	-- Instances.
	local remotes = replicatedStorage:WaitForChild("Remotes")
	local quickClientEffects = remotes:WaitForChild("QuickClientEffects")

	-- Signals.
	local gameDescendantAdded = Signal.new(game.DescendantAdded)
	local gameDescendantRemoved = Signal.new(game.DescendantRemoving)
	local renderStepped = Signal.new(runService.RenderStepped)
	local postSimulation = Signal.new(runService.PostSimulation)
	local playersAdded = Signal.new(players.PlayerAdded)
	local quickClientEffectSignal = Signal.new(quickClientEffects.OnClientEvent)

	defenseMaid:mark(gameDescendantAdded:connect("Defense_OnDescendantAdded", onGameDescendantAdded))
	defenseMaid:mark(gameDescendantRemoved:connect("Defense_OnDescendantRemoved", onGameDescendantRemoved))
	defenseMaid:mark(renderStepped:connect("Defense_UpdateHistory", updateHistory))
	defenseMaid:mark(renderStepped:connect("Defense_UpdateVisualizations", updateVisualizations))
	defenseMaid:mark(renderStepped:connect("Defense_UpdateAssistance", updateAssistance))
	defenseMaid:mark(postSimulation:connect("Defense_UpdateDefenders", updateDefenders))
	defenseMaid:mark(playersAdded:connect("Defense_OnPlayerAdded", onPlayerAdded))
	defenseMaid:mark(quickClientEffectSignal:connect("Defense_OnQuickClientEffect", onQuickClientEffect))

	if players.LocalPlayer then
		onPlayerAdded(players.LocalPlayer)
	end

	for _, descendant in next, game:GetDescendants() do
		onGameDescendantAdded(descendant)
	end

	-- Log.
	Logger.warn("Defense initialized.")
end

---Detach defense.
function Defense.detach()
	for _, object in next, defenderObjects do
		object:detach()
	end

	defenseMaid:clean()

	Logger.warn("Defense detached.")
end

-- Return Defense module.
return Defense

end)
__bundle_register("Features/Combat/PositionHistory", function(require, _LOADED, __bundle_register, __bundle_modules)
-- PositionHistory module.
local PositionHistory = {}

-- Histories table.
local histories = {}

-- Max history seconds.
local MAX_HISTORY_SECS = 3.0

---Add an entry to the history list.
---@param idx any
---@param position CFrame
---@param timestamp number
function PositionHistory.add(idx, position, timestamp)
	local history = histories[idx] or {}

	if not histories[idx] then
		histories[idx] = history
	end

	history[#history + 1] = {
		position = position,
		timestamp = timestamp,
	}

	while true do
		local tail = history[1]
		if not tail then
			break
		end

		if tick() - tail.timestamp <= MAX_HISTORY_SECS then
			break
		end

		table.remove(history, 1)
	end
end

---Get the horizontal angular velocity (yaw rate) for a current index.
---@param index any
---@return number?
function PositionHistory.yrate(index)
	local history = histories[index]
	if not history or #history < 2 then
		return nil
	end

	local latest = history[#history]
	local previous = history[#history - 1]
	local dt = latest.timestamp - previous.timestamp
	if dt <= 1e-4 then
		return nil
	end

	local prevLook = Vector3.new(previous.position.LookVector.X, 0, previous.position.LookVector.Z).Unit
	local latestLook = Vector3.new(latest.position.LookVector.X, 0, latest.position.LookVector.Z).Unit
	local dot = prevLook:Dot(latestLook)
	local crossY = prevLook:Cross(latestLook).Y
	local angle = math.atan2(crossY, dot)
	return angle / dt
end

---Divides the history into a number of equal steps and returns the position at each step.
---@param idx any
---@param steps number
---@param phds number History second limit for past hitbox detection.
---@return CFrame[]?
function PositionHistory.stepped(idx, steps, phds)
	local history = histories[idx]
	if not history or #history == 0 then
		return nil
	end

	if not steps or steps <= 0 then
		return nil
	end

	local vhistory = {}
	local vhtime = history[#history].timestamp

	for _, data in next, history do
		if vhtime - data.timestamp > phds then
			continue
		end

		vhistory[#vhistory + 1] = data.position
	end

	if #vhistory == 0 then
		return {}
	end

	local count = math.min(steps, #vhistory)
	local out = table.create(count)

	for cidx = 1, count do
		out[cidx] = vhistory[math.max(math.floor((cidx * #vhistory) / count), 1)]
	end

	return out
end

---Get closest position (in time) to a timestamp.
---@param idx any
---@param timestamp number
---@return CFrame?
function PositionHistory.closest(idx, timestamp)
	if not histories[idx] then
		return nil
	end

	local closestDelta = nil
	local closestPosition = nil

	for _, data in next, histories[idx] do
		local delta = math.abs(timestamp - data.timestamp)

		if closestDelta and delta >= closestDelta then
			continue
		end

		closestPosition = data.position
		closestDelta = delta
	end

	return closestPosition
end

-- Return PositionHistory module.
return PositionHistory

end)
__bundle_register("Features/Combat/Objects/SoundDefender", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Features.Combat.Objects.Defender
local Defender = require("Features/Combat/Objects/Defender")

---@module Game.Timings.SaveManager
local SaveManager = require("Game/Timings/SaveManager")

---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Features.Combat.Objects.RepeatInfo
local RepeatInfo = require("Features/Combat/Objects/RepeatInfo")

---@module Features.Combat.Objects.HitboxOptions
local HitboxOptions = require("Features/Combat/Objects/HitboxOptions")

---@class SoundDefender: Defender
---@field owner Model? The owner of the part.
---@field sound Sound The sound that we're defending.
---@field part BasePart A part that we can base the position off of.
local SoundDefender = setmetatable({}, { __index = Defender })
SoundDefender.__index = SoundDefender
SoundDefender.__type = "Sound"

-- Services.
local players = game:GetService("Players")

---Check if we're in a valid state to proceed with the action.
---@param self SoundDefender
---@param timing PartTiming
---@param action Action
---@return boolean
SoundDefender.valid = LPH_NO_VIRTUALIZE(function(self, timing, action)
	if not Defender.valid(self, timing, action) then
		return false
	end

	if self.owner and not self:target(self.owner) then
		return self:notify(timing, "Not a viable target.")
	end

	local character = players.LocalPlayer.Character
	if not character then
		return self:notify(timing, "No character found.")
	end

	local options = HitboxOptions.new(self.part, timing)
	options.spredict = false
	options.action = action

	if not self:hc(options, timing.duih and RepeatInfo.new(timing) or nil) then
		return self:notify(timing, "Not in hitbox.")
	end

	return true
end)

---Repeat conditional.
---@param self SoundDefender
---@param _ RepeatInfo
---@return boolean
SoundDefender.rc = LPH_NO_VIRTUALIZE(function(self, _)
	if not self.sound.IsPlaying then
		return false
	end

	return true
end)

---Process sound playing.
---@param self SoundDefender
SoundDefender.process = LPH_NO_VIRTUALIZE(function(self)
	---@type SoundTiming?
	local timing = self:initial(
		self.owner or self.part,
		SaveManager.ss,
		self.owner and self.owner.Name or self.part.Name,
		tostring(self.sound.SoundId)
	)

	if not timing then
		return
	end

	if not Configuration.expectToggleValue("EnableAutoDefense") then
		return
	end

	if players.LocalPlayer.Character and self.owner == players.LocalPlayer.Character then
		return
	end

	---@note: Clean up previous tasks that are still waiting or suspended because they're in a different track.
	self:clean()

	-- Use module if we need to.
	if timing.umoa then
		return self:module(timing)
	end

	-- Add actions.
	return self:actions(timing)
end)

---Create new SoundDefender object.
---@param sound Sound
---@param part BasePart
---@return SoundDefender
function SoundDefender.new(sound, part)
	local self = setmetatable(Defender.new(), SoundDefender)
	local soundPlayed = Signal.new(sound.Played)

	self.sound = sound
	self.part = part
	self.owner = sound:FindFirstAncestorWhichIsA("Model")
	self.maid:mark(soundPlayed:connect(
		"SoundDefender_OnSoundPlayed",
		LPH_NO_VIRTUALIZE(function()
			self:process()
		end)
	))

	if sound.Playing then
		self:process()
	end

	return self
end

-- Return SoundDefender module.
return SoundDefender

end)
__bundle_register("Features/Combat/Objects/HitboxOptions", function(require, _LOADED, __bundle_register, __bundle_modules)
---@class HitboxOptions
---@note: Options for the hitbox check.
---@field part BasePart? If this is specified and it exists, it will be used for the position.
---@field cframe CFrame? Else, the part's CFrame will be used.
---@field timing Timing|AnimationTiming|SoundTiming
---@field action Action?
---@field filter Instance[]
---@field spredict boolean If true, a check will run for predicted positions.
---@field ptime number? The predicted time in seconds for extrapolation.
---@field entity Model? The entity for extrapolation.
---@field phcolor Color3 The color for predicted hitboxes.
---@field pmcolor Color3 The color for predicted missed hitboxes.
---@field hcolor Color3 The color for hitboxes.
---@field mcolor Color3 The color for missed hitboxes.
---@field hmid number? Hitbox visualization ID for normal hitbox check.
local HitboxOptions = {}
HitboxOptions.__index = HitboxOptions

-- Services.
local players = game:GetService("Players")

---Hit color.
---@return Color3
function HitboxOptions:ghcolor(result)
	return result and self.hcolor or self.mcolor
end

---Predicted hit color.
---@return Color3
function HitboxOptions:gphcolor(result)
	return result and self.phcolor or self.pmcolor
end

---Cloned hitbox options.
---@return HitboxOptions
function HitboxOptions:clone()
	local options = setmetatable({}, HitboxOptions)
	options.action = self.action
	options.spredict = self.spredict
	options.entity = self.entity
	options.ptime = self.ptime
	options.entity = self.entity
	options.phcolor = self.phcolor
	options.pmcolor = self.pmcolor
	options.hcolor = self.hcolor
	options.mcolor = self.mcolor
	options.hmid = self.hmid
	options.filter = self.filter
	options.part = self.part
	options.cframe = self.cframe
	options.timing = self.timing
	return options
end

---Get the hitbox size.
---@return Vector3
function HitboxOptions:hitbox()
	local hitbox = self.action and self.action.hitbox or self.timing.hitbox

	if self.timing.duih then
		hitbox = self.timing.hitbox
	end

	hitbox = Vector3.new(PP_SCRAMBLE_NUM(hitbox.X), PP_SCRAMBLE_NUM(hitbox.Y), PP_SCRAMBLE_NUM(hitbox.Z))

	return hitbox
end

---Get extrapolated position.
---@return CFrame
HitboxOptions.extrapolate = LPH_NO_VIRTUALIZE(function(self)
	if not self.part then
		return error("HitboxOptions.extrapolate - unimplemented for CFrame")
	end

	if not self.entity then
		return error("HitboxOptions.extrapolate - no entity specified")
	end

	if not self.ptime then
		return error("HitboxOptions.extrapolate - no predicted time specified")
	end

	-- Return the extrapolated position.
	return self.part.CFrame + (self.part.AssemblyLinearVelocity * self.ptime)
end)

---Get position.
---@return CFrame
HitboxOptions.pos = LPH_NO_VIRTUALIZE(function(self)
	if self.cframe then
		return self.cframe
	end

	if self.part then
		return self.part.CFrame
	end

	return error("HitboxOptions.pos - impossible condition")
end)

---Create new HitboxOptions object.
---@param target Instance|CFrame
---@param timing Timing|AnimationTiming|SoundTiming
---@param filter Instance[]?
---@return HitboxOptions
HitboxOptions.new = LPH_NO_VIRTUALIZE(function(target, timing, filter)
	local self = setmetatable({}, HitboxOptions)
	self.part = typeof(target) == "Instance" and target:IsA("BasePart") and target
	self.cframe = typeof(target) == "CFrame" and target
	self.timing = timing
	self.action = nil
	self.filter = filter or {}
	self.spredict = false
	self.hmid = nil
	self.entity = nil
	self.phcolor = Color3.new(1, 0, 1)
	self.pmcolor = Color3.new(0.349019, 0.345098, 0.345098)
	self.hcolor = Color3.new(0, 1, 0)
	self.mcolor = Color3.new(1, 0, 0)
	self.ptime = nil

	if not self.part and not self.cframe then
		return error("HitboxOptions: No part or CFrame specified.")
	end

	if filter then
		return self
	end

	local character = players.LocalPlayer.Character
	if not character then
		return self
	end

	self.filter = { character }

	return self
end)

-- Return HitboxOptions module.
return HitboxOptions

end)
__bundle_register("Features/Combat/Objects/RepeatInfo", function(require, _LOADED, __bundle_register, __bundle_modules)
---@note: Typed object that represents information. It's not really a true class but just needs to store the correct data.
---@class RepeatInfo
---@field track AnimationTrack?
---@field timing Timing
---@field start number
---@field index number
---@field irdelay number Initial receive delay.
local RepeatInfo = {}
RepeatInfo.__index = RepeatInfo

---Create new RepeatInfo object.
---@param timing Timing
---@param irdelay number
---@return RepeatInfo
function RepeatInfo.new(timing, irdelay)
	local self = setmetatable({}, RepeatInfo)
	self.track = nil
	self.timing = timing
	self.start = os.clock()
	self.index = 0
	self.irdelay = irdelay
	return self
end

-- Return RepeatInfo module.
return RepeatInfo

end)
__bundle_register("Features/Combat/Objects/Defender", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Features.Combat.Objects.Task
local Task = require("Features/Combat/Objects/Task")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module GUI.Library
local Library = require("GUI/Library")

---@module Game.Timings.ModuleManager
local ModuleManager = require("Game/Timings/ModuleManager")

---@module Utility.TaskSpawner
local TaskSpawner = require("Utility/TaskSpawner")

---@module Features.Combat.Targeting
local Targeting = require("Features/Combat/Targeting")

---@module Features.Combat.PositionHistory
local PositionHistory = require("Features/Combat/PositionHistory")

---@module Features.Combat.Objects.HitboxOptions
local HitboxOptions = require("Features/Combat/Objects/HitboxOptions")

---@module Game.InputClient
local InputClient = require("Game/InputClient")

---@module Features.Combat.AttributeListener
local AttributeListener = require("Features/Combat/AttributeListener")

---@module Game.Keybinding
local Keybinding = require("Game/Keybinding")

---@module Utility.OriginalStore
local OriginalStore = require("Utility/OriginalStore")

---@class Defender
---@field tasks Task[]
---@field tmaid Maid Cleaned up every clean cycle.
---@field rhook table<string, function> Hooked functions that we can restore on clean-up.
---@field markers table<string, boolean> Blocking markers for unknown length timings. If the entry exists and is true, then we're blocking.
---@field maid Maid
---@field hmaid Maid
local Defender = {}
Defender.__index = Defender
Defender.__type = "Defender"

-- Services.
local stats = game:GetService("Stats")
local userInputService = game:GetService("UserInputService")
local players = game:GetService("Players")
local textChatService = game:GetService("TextChatService")
local debrisService = game:GetService("Debris")

-- Constants.
local MAX_VISUALIZATION_TIME = 5.0
local MAX_REPEAT_WAIT = 10.0
local PREDICTION_LENIENCY_MULTI = 5.0

---Log a miss to the UI library with distance check.
---@param type string
---@param key string
---@param name string?
---@param distance number
---@param parent string? If provided, will be shown in the log.
---@return boolean
function Defender:miss(type, key, name, distance, parent)
	if not Configuration.expectToggleValue("ShowLoggerWindow") then
		return false
	end

	if
		distance < (Configuration.expectOptionValue("MinimumLoggerDistance") or 0)
		or distance > (Configuration.expectOptionValue("MaximumLoggerDistance") or 0)
	then
		return false
	end

	Library:AddMissEntry(type, key, name, distance, parent)

	return true
end

---Fetch distance.
---@param from Model? | BasePart?
---@return number?
function Defender:distance(from)
	if not from then
		return
	end

	local entRootPart = from

	if from:IsA("Model") then
		entRootPart = from:FindFirstChild("HumanoidRootPart")
	end

	if not entRootPart then
		return
	end

	local localCharacter = players.LocalPlayer.Character
	if not localCharacter then
		return
	end

	local localRootPart = localCharacter:FindFirstChild("HumanoidRootPart")
	if not localRootPart then
		return
	end

	return (entRootPart.Position - localRootPart.Position).Magnitude
end

---Find target - hookable function.
---@param self Defender
---@param entity Model
---@return Target?
Defender.target = LPH_NO_VIRTUALIZE(function(self, entity)
	return Targeting.find(entity)
end)

---Repeat until parry end.
---@param self Defender
---@param entity Model
---@param timing AnimationTiming
---@param info RepeatInfo
Defender.rpue = LPH_NO_VIRTUALIZE(function(self, entity, timing, info)
	local distance = self:distance(entity)
	if not distance then
		return Logger.warn("Stopping RPUE '%s' because the distance is not valid.", PP_SCRAMBLE_STR(timing.name))
	end

	if timing and (distance < PP_SCRAMBLE_NUM(timing.imdd) or distance > PP_SCRAMBLE_NUM(timing.imxd)) then
		return self:notify(timing, "Distance is out of range.")
	end

	if not self:rc(info) then
		return Logger.warn(
			"Stopping RPUE '%s' because the repeat condition is not valid.",
			PP_SCRAMBLE_STR(timing.name)
		)
	end

	local target = self:target(entity)

	local options = HitboxOptions.new(CFrame.new(), timing)
	options.spredict = true
	options.part = target and target.root
	options.entity = entity

	local success = target and self:hc(options, timing.duih and info or nil)

	info.index = info.index + 1

	self:mark(Task.new(string.format("RPUE_%s_%i", PP_SCRAMBLE_STR(timing.name), info.index), function()
		return timing:rpd() - info.irdelay - self.sdelay()
	end, timing.punishable, timing.after, self.rpue, self, self.entity, timing, info))

	if not target then
		return Logger.warn("Skipping RPUE '%s' because the target is not valid.", PP_SCRAMBLE_STR(timing.name))
	end

	if not success then
		return Logger.warn("Skipping RPUE '%s' because we are not in the hitbox.", PP_SCRAMBLE_STR(timing.name))
	end

	if not timing.srpn then
		self:notify(timing, "(%i) Action 'RPUE Parry' is being executed.", info.index)
	end

	InputClient.parry()
end)

---Check if we're in a valid state to proceed with action handling. Extend me.
---@param self Defender
---@param timing Timing
---@param action Action
---@return boolean
Defender.valid = LPH_NO_VIRTUALIZE(function(self, timing, action)
	local integer = Random.new():NextNumber(1.0, 100.0)
	local rate = Configuration.expectOptionValue("FailureRate") or 0.0

	if Configuration.expectToggleValue("AllowFailure") and integer <= rate then
		return self:notify(timing, "(%i <= %i) Intentionally did not run.", integer, rate)
	end

	local selectedFilters = Configuration.expectOptionValue("AutoDefenseFilters") or {}

	local character = players.LocalPlayer.Character
	if not character then
		return self:notify(timing, "No character found.")
	end

	if selectedFilters["Disable When Knocked Recently"] and AttributeListener.krecently() then
		return self:notify(timing, "User was knocked recently.")
	end

	if selectedFilters["Disable When In Dash"] and character:GetAttribute("CurrentState") == "Dashing" then
		return self:notify(timing, "User is dashing.")
	end

	if selectedFilters["Disable When In Flashstep"] and character:GetAttribute("CurrentState") == "Flashstep" then
		return self:notify(timing, "User is flashstepping.")
	end

	if character:GetAttribute("CurrentState") == "Attacking" or character:GetAttribute("CurrentState") == "Skill" then
		return self:notify(timing, "Currently attacking.")
	end

	local chatInputBarConfiguration = textChatService:FindFirstChildOfClass("ChatInputBarConfiguration")

	if
		selectedFilters["Disable When Textbox Focused"]
		and (userInputService:GetFocusedTextBox() or chatInputBarConfiguration.IsFocused)
	then
		return self:notify(timing, "User is typing in a text box.")
	end

	if selectedFilters["Disable When Window Not Active"] and iswindowactive and not iswindowactive() then
		return self:notify(timing, "Window is not active.")
	end

	if
		selectedFilters["Disable When Holding Block"]
		and userInputService:IsKeyDown(Keybinding.info["Block / Parry"] or Enum.KeyCode.F)
	then
		return self:notify(timing, "User is holding block.")
	end

	if timing.tag == "M1" and selectedFilters["Filter Out M1s"] then
		return self:notify(timing, "Attacker is using a 'M1' attack.")
	end

	if timing.tag == "Mantra" and selectedFilters["Filter Out Mantras"] then
		return self:notify(timing, "Attacker is using a 'Mantra' attack.")
	end

	if timing.tag == "Critical" and selectedFilters["Filter Out Criticals"] then
		return self:notify(timing, "Attacker is using a 'Critical' attack.")
	end

	if timing.tag == "Undefined" and selectedFilters["Filter Out Undefined"] then
		return self:notify(timing, "Attacker is using an 'Undefined' attack.")
	end

	return true
end)

---Check if any parts that are in our filter were hit.
---@note: Solara fallback.
local function checkParts(parts, filter)
	for _, part in next, parts do
		for _, fpart in next, filter do
			if part ~= fpart and not part:IsDescendantOf(fpart) then
				continue
			end

			return true
		end
	end

	return false
end

---Visualize a position and size.
---@param self Defender
---@param identifier number? If the identifier is nil, then we will auto-generate one for each visualization.
---@param cframe CFrame
---@param size Vector3
---@param color Color3
Defender.visualize = LPH_NO_VIRTUALIZE(function(self, identifier, cframe, size, color)
	local id = identifier or self.hmaid:uid()
	local vpart = self.hmaid[id] or Instance.new("Part")

	vpart.Parent = workspace
	vpart.Anchored = true
	vpart.CanCollide = false
	vpart.CanQuery = false
	vpart.CanTouch = false
	vpart.Material = Enum.Material.ForceField
	vpart.CastShadow = false
	vpart.Size = size
	vpart.CFrame = cframe
	vpart.Color = color
	vpart.Name = string.format("RW_Visualization_%i", id)
	vpart.Transparency = Configuration.expectToggleValue("EnableVisualizations") and 0.2 or 1.0

	if self.hmaid[id] then
		return
	end

	self.hmaid[id] = vpart

	debrisService:AddItem(vpart, MAX_VISUALIZATION_TIME)
end)

---Run hitbox check. Returns wheter if the hitbox is being touched.
---@todo: An issue is that the player's current look vector will not be the same as when they attack due to a parry timing being seperate from the attack causing this check to fail.
---@param self Defender
---@param cframe CFrame
---@param fd boolean
---@param size Vector3
---@param filter Instance[]
---@return boolean?, CFrame?
Defender.hitbox = LPH_NO_VIRTUALIZE(function(self, cframe, fd, size, filter)
	local shouldManualFilter = getexecutorname
		and (getexecutorname():match("Solara") or getexecutorname():match("Xeno"))

	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = shouldManualFilter and {} or filter
	overlapParams.FilterType = shouldManualFilter and Enum.RaycastFilterType.Exclude or Enum.RaycastFilterType.Include

	local character = players.LocalPlayer.Character
	if not character then
		return nil, nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil, nil
	end

	-- Used CFrame.
	local usedCFrame = cframe

	if fd then
		usedCFrame = usedCFrame * CFrame.new(0, 0, -(size.Z / 2))
	end

	-- Parts in bounds.
	local parts = workspace:GetPartBoundsInBox(usedCFrame, size, overlapParams)

	-- Return result.
	return shouldManualFilter and checkParts(parts, filter) or #parts > 0, usedCFrame
end)

---Check initial state.
---@param self Defender
---@param from Model? | BasePart?
---@param pair TimingContainerPair
---@param name string
---@param key string
---@return Timing?
Defender.initial = LPH_NO_VIRTUALIZE(function(self, from, pair, name, key)
	-- Find timing.
	local timing = pair:index(key)

	-- Fetch distance.
	local distance = self:distance(from)
	if not distance then
		return nil
	end

	-- Check for distance; if we have a timing.
	if timing and (distance < PP_SCRAMBLE_NUM(timing.imdd) or distance > PP_SCRAMBLE_NUM(timing.imxd)) then
		return nil
	end

	-- Check for no timing. If so, let's log a miss.
	---@note: Ignore return value.
	if not timing then
		self:miss(self.__type, key, name, distance, from and tostring(from.Parent) or nil)
		return nil
	end

	-- Return timing.
	return timing
end)

---Logger notify.
---@param self Defender
---@param timing Timing
---@param str string
Defender.notify = LPH_NO_VIRTUALIZE(function(self, timing, str, ...)
	if not Configuration.expectToggleValue("EnableNotifications") then
		return
	end

	Logger.notify("[%s] (%s) %s", PP_SCRAMBLE_STR(timing.name), self.__type, string.format(str, ...))
end)

---@note: Perhaps one day, we can get better approximations for these.
--- These used to rely on GetNetworkPing which we assumed would be sending or atleast receiving delay.
--- That is incorrect, it is RakNet ping thereby being RTT.

---Get receiving delay.
---@return number
function Defender.rdelay()
	return math.max(Defender.rtt() / 2, 0.0)
end

---Get sending delay.
---@return number
function Defender.sdelay()
	return math.max(Defender.rtt() / 2, 0.0)
end

---Get data ping.
---@note: https://devforum.roblox.com/t/in-depth-information-about-robloxs-remoteevents-instance-replication-and-physics-replication-w-sources/1847340
---@note: The forum post above is misleading, not only is it the RTT time, please note that this also takes into account all delays like frame time.
---@note: This is our round-trip time (e.g double the ping) since we have a receiving delay (replication) and a sending delay when we send the input to the server.
---@todo: For every usage, the sending delay needs to be continously updated. The receiving one must be calculated once at initial send for AP ping compensation.
---@return number
function Defender.rtt()
	local network = stats:FindFirstChild("Network")
	if not network then
		return
	end

	local serverStatsItem = network:FindFirstChild("ServerStatsItem")
	if not serverStatsItem then
		return
	end

	local dataPingItem = serverStatsItem:FindFirstChild("Data Ping")
	if not dataPingItem then
		return
	end

	return (dataPingItem:GetValue() / 1000)
end

---Repeat conditional.
---@param self Defender
---@param info RepeatInfo
---@return boolean
Defender.rc = LPH_NO_VIRTUALIZE(function(self, info)
	if os.clock() - info.start >= MAX_REPEAT_WAIT then
		return false
	end

	return true
end)

---Handle delay until in hitbox.
---@param self Defender
---@param options HitboxOptions
---@param info RepeatInfo
---@return boolean
Defender.duih = LPH_NO_VIRTUALIZE(function(self, options, info)
	local clone = options:clone()
	clone.hmid = self.hmaid:uid()

	while task.wait() do
		if not self:rc(info) then
			return false
		end

		if not self:hc(clone, nil) then
			continue
		end

		return true
	end
end)

---Handle hitbox check options.
---@param self Defender
---@param options HitboxOptions
---@param info RepeatInfo? Pass this in if you want to use the delay until in hitbox.
---@return boolean
Defender.hc = LPH_NO_VIRTUALIZE(function(self, options, info)
	local action = options.action
	local timing = options.timing

	-- Run basic validation.
	local character = players.LocalPlayer.Character
	if not character then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	if action and action.ihbc then
		return true
	end

	-- If we have info, then we want to delay until in hitbox.
	if info then
		return self:duih(options, info)
	end

	-- Fetch the data that we need.
	local hitbox = options:hitbox()
	local eposition = options.spredict and options:extrapolate() or nil
	local position = options:pos()

	-- Run hitbox check.
	local result, usedCFrame = self:hitbox(position, timing.fhb, hitbox, options.filter)

	if usedCFrame then
		self:visualize(options.hmid, usedCFrame, hitbox, options:ghcolor(result))
		self:visualize(options.hmid and options.hmid + 1 or nil, root.CFrame, root.Size, options:ghcolor(result))
	end

	if not options.spredict or result then
		return result
	end

	-- Run prediction check.
	local closest = PositionHistory.closest(players.LocalPlayer, tick() - (self.sdelay() * PREDICTION_LENIENCY_MULTI))
	if not closest then
		return false
	end

	local store = OriginalStore.new()

	-- Run check.
	store:run(root, "CFrame", closest, function()
		result, usedCFrame = self:hitbox(eposition, timing.fhb, hitbox, options.filter)
	end)

	-- Visualize predicted hitbox.
	if usedCFrame then
		self:visualize(options.hmid and options.hmid + 1 or nil, usedCFrame, hitbox, options:gphcolor(result))
		self:visualize(options.hmid and options.hmid + 1 or nil, root.CFrame, root.Size, options:gphcolor(result))
	end

	-- Return result.
	return result
end)

---Handle end block.
---@param self Defender
Defender.bend = LPH_NO_VIRTUALIZE(function(self)
	-- Iterate for start block tasks.
	for idx, task in next, self.tasks do
		-- Check if task is a start block.
		if task.identifier ~= "Start Block" then
			continue
		end

		-- End start block tasks.
		task:cancel()

		-- Clear in table.
		self.tasks[idx] = nil
	end

	InputClient.block(false)
end)

---Handle action.
---@param self Defender
---@param timing Timing
---@param action Action
---@param notify boolean
Defender.handle = LPH_NO_VIRTUALIZE(function(self, timing, action, notify)
	if not self:valid(timing, action) then
		return
	end

	if not notify then
		self:notify(timing, "Action type '%s' is being executed.", PP_SCRAMBLE_STR(action._type))
	end

	-- Dash instead of parry.
	local dashReplacement = Random.new():NextNumber(1.0, 100.0)
		<= (Configuration.expectOptionValue("DashInsteadOfParryRate") or 0.0)

	if PP_SCRAMBLE_STR(action._type) ~= "Parry" then
		dashReplacement = false
	end

	if not Configuration.expectToggleValue("AllowFailure") then
		dashReplacement = false
	end

	if timing.umoa or timing.actions:count() ~= 1 then
		dashReplacement = false
	end

	if PP_SCRAMBLE_STR(action._type) == "Start Block" then
		return InputClient.block(true)
	end

	if PP_SCRAMBLE_STR(action._type) == "End Block" then
		return self:bend()
	end

	if PP_SCRAMBLE_STR(action._type) == "Dash" then
		return InputClient.dash()
	end

	-- Apparat (last-resort evasive combo-breaker).
	if PP_SCRAMBLE_STR(action._type) == "Apparat" then
		return InputClient.apparat()
	end

	-- Parry if possible.
	-- We'll assume that we're in the parry state. There's no other type.
	if AttributeListener.cparry() then
		if timing.nfdb or not AttributeListener.cdash() or not dashReplacement then
			return InputClient.parry()
		end

		self:notify(timing, "Action type 'Parry' replaced to 'Dash' type.")

		return InputClient.dash()
	end

	---Block fallback function. Returns whether the fallback was successful.
	---@return boolean
	local function blockFallback()
		if not Configuration.expectToggleValue("DeflectBlockFallback") then
			return false
		end

		Defender:notify(timing, "Action fallback 'Parry' is using block frames.")
		InputClient.deflect()

		return true
	end

	-- Dodge fallback.
	if not Configuration.expectToggleValue("DashOnParryCooldown") then
		return blockFallback()
	end

	if timing.ndfb then
		return self:notify(timing, "Action fallback 'Dodge' is disabled for this timing.")
	end

	if not AttributeListener.cdash() then
		return blockFallback() or self:notify(timing, "Action fallback 'Dodge' blocked because we are unable to dash.")
	end

	self:notify(timing, "Action type 'Parry' overrided to 'Dash' type.")

	return InputClient.dash()
end)

---Check if we have input blocking tasks.
---@param self Defender
---@return boolean
Defender.blocking = LPH_NO_VIRTUALIZE(function(self)
	for _, marker in next, self.markers do
		if not marker then
			continue
		end

		return true
	end

	for _, task in next, self.tasks do
		if not task:blocking() then
			continue
		end

		return true
	end
end)

---Mark task.
---@param task Task
function Defender:mark(task)
	self.tasks[#self.tasks + 1] = task
end

---Clean up hooks.
function Defender:clhook()
	for key, old in next, self.rhook do
		if not self[key] then
			continue
		end

		self[key] = old
	end

	self.rhook = {}
end

---Clean up all tasks.
---@param self Defender
Defender.clean = LPH_NO_VIRTUALIZE(function(self)
	-- Clean-up hooks.
	self:clhook()

	-- Clear temporary maid.
	self.tmaid:clean()

	-- Clear markers.
	self.markers = {}

	-- Clean up hitboxes.
	self.hmaid:clean()

	-- Was there a start block, end block, or parry?
	local blocking = false

	for idx, task in next, self.tasks do
		-- Cancel task.
		task:cancel()

		-- Clear in table.
		self.tasks[idx] = nil

		-- Check.
		blocking = blocking
			or (task.identifier == "Start Block" or task.identifier == "End Block" or task.identifier == "Parry")
	end

	-- Run end block, just in case we get stuck.
	if blocking then
		InputClient.block(false)
	end
end)

---Process module.
---@param self Defender
---@param timing Timing
---@varargs any
Defender.module = LPH_NO_VIRTUALIZE(function(self, timing, ...)
	-- Get loaded function.
	local lf = ModuleManager.modules[PP_SCRAMBLE_STR(timing.smod)]
	if not lf then
		return self:notify(timing, "No module '%s' found.", PP_SCRAMBLE_STR(timing.smod))
	end

	-- Create identifier.
	local identifier = string.format("Defender_RunModule_%s", PP_SCRAMBLE_STR(timing.smod))

	-- Notify.
	if not timing.smn then
		self:notify(timing, "Running module '%s' on timing.", PP_SCRAMBLE_STR(timing.smod))
	end

	-- Run module.
	self.tmaid:mark(TaskSpawner.spawn(identifier, lf, self, timing, ...))
end)

---Add a action to the defender object.
---@param self Defender
---@param timing Timing
---@param action Action
Defender.action = LPH_NO_VIRTUALIZE(function(self, timing, action)
	if timing.umoa then
		action["_type"] = PP_SCRAMBLE_STR(action["_type"])
		action["name"] = PP_SCRAMBLE_STR(action["name"])
		action["_when"] = PP_SCRAMBLE_RE_NUM(action["_when"])
		action["hitbox"] = Vector3.new(
			PP_SCRAMBLE_RE_NUM(action["hitbox"].X),
			PP_SCRAMBLE_RE_NUM(action["hitbox"].Y),
			PP_SCRAMBLE_RE_NUM(action["hitbox"].Z)
		)
	end

	-- Get initial receive delay.
	local rdelay = self.rdelay()

	-- Add action.
	self:mark(Task.new(PP_SCRAMBLE_STR(action._type), function()
		return action:when() - rdelay - self.sdelay()
	end, timing.punishable, timing.after, self.handle, self, timing, action))

	-- Log.
	if not LRM_UserNote or LRM_UserNote == "tester" then
		self:notify(
			timing,
			"Added action '%s' (%.2fs) with ping '%.2f' (changing) subtracted.",
			PP_SCRAMBLE_STR(action.name),
			action:when(),
			self.rtt()
		)
	else
		self:notify(
			timing,
			"Added action '%s' ([redacted]) with ping '%.2f' (changing) subtracted.",
			PP_SCRAMBLE_STR(action.name),
			self.rtt()
		)
	end
end)

---Add actions from timing to defender object.
---@param self Defender
---@param timing Timing
Defender.actions = LPH_NO_VIRTUALIZE(function(self, timing)
	for _, action in next, timing.actions:get() do
		self:action(timing, action)
	end
end)

---Safely replace a function in the defender object.
---@param key string
---@param new function
---@return boolean, function
function Defender:hook(key, new)
	-- Check if we're already hooked.
	if self.rhook[key] then
		Logger.warn("Cannot hook '%s' because it is already hooked.", key)
		return false, nil
	end

	-- Get our assumed old / target function.
	local old = self[key]

	-- Check if function.
	if typeof(old) ~= "function" then
		Logger.warn("Cannot hook '%s' because it is not a function.", key)
		return false, nil
	end

	-- Create hook.
	self[key] = new

	-- Add to hook table with the old function so we can restore it on clean-up.
	self.rhook[key] = old

	-- Log.
	Logger.warn("Hooked '%s' with new function.", key)

	return true, old
end

---Detach defender object.
function Defender:detach()
	-- Clean self.
	self:clean()
	self.maid:clean()

	-- Set object nil.
	self = nil
end

---Create new Defender object.
---@return Defender
function Defender.new()
	local self = setmetatable({}, Defender)
	self.tasks = {}
	self.rhook = {}
	self.tmaid = Maid.new()
	self.maid = Maid.new()
	self.hmaid = Maid.new()
	self.markers = {}
	self.lvisualization = os.clock()
	return self
end

-- Return Defender module.
return Defender

end)
__bundle_register("Utility/OriginalStore", function(require, _LOADED, __bundle_register, __bundle_modules)
---@class OriginalStore
---@param data any
---@param index any
---@param value any
---@field stored boolean
local OriginalStore = {}
OriginalStore.__index = OriginalStore

---Get stored data value.
---@return any
OriginalStore.get = LPH_NO_VIRTUALIZE(function(self)
	if not self.stored then
		return nil
	end

	return self.value
end)

---Set something, run a callback, and then restore.
---@param data table|Instance
---@param index any
---@param value any
---@param callback fun(): any
OriginalStore.run = LPH_NO_VIRTUALIZE(function(self, data, index, value, callback)
	self:set(data, index, value)

	callback()

	self:restore()
end)

---Mark data value.
---@param data table|Instance
---@param index any
OriginalStore.mark = LPH_NO_VIRTUALIZE(function(self, data, index)
	if self.stored and self.data ~= data then
		self:restore()
	end

	if not self.stored then
		self.data = data
		self.index = index
		self.value = data[index]
		self.stored = true
	end
end)

---Set data value.
---@param data table|Instance
---@param index any
---@param value any
OriginalStore.set = LPH_NO_VIRTUALIZE(function(self, data, index, value)
	self:mark(data, index)

	data[index] = value
end)

---Restore data value.
OriginalStore.restore = LPH_NO_VIRTUALIZE(function(self)
	if not self.stored then
		return
	end

	pcall(function()
		self.data[self.index] = self.value
	end)

	self.stored = false
end)

---Detach OriginalStore object.
OriginalStore.detach = LPH_NO_VIRTUALIZE(function(self)
	self:restore()
	self.data = nil
	self.index = nil
	self.value = nil
	self.stored = false
end)

---Create new OriginalStore object.
---@return OriginalStore
OriginalStore.new = LPH_NO_VIRTUALIZE(function()
	local self = setmetatable({}, OriginalStore)
	self.data = nil
	self.index = nil
	self.value = nil
	self.stored = false
	return self
end)

-- Return OriginalStore module.
return OriginalStore

end)
__bundle_register("Features/Combat/AttributeListener", function(require, _LOADED, __bundle_register, __bundle_modules)
-- AttributeListener module.
local AttributeListener = { lastParry = nil, lastDash = nil, lastKnock = nil }

---@modules Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.Signal
local Signal = require("Utility/Signal")

-- Services.
local players = game:GetService("Players")

-- Attribute maid.
local attributeMaid = Maid.new()

---On character added.
---@param character Model
local function onCharacterAdded(character)
	local attributeChangedSignal = Signal.new(character:GetAttributeChangedSignal("CurrentState"))

	attributeMaid["CurrentStateAttributeChanged"] = attributeChangedSignal:connect(
		"AttributeListener_OnAttributeChanged",
		function()
			if character:GetAttribute("CurrentState") == "Parrying" then
				AttributeListener.lastParry = tick()
			end

			if
				character:GetAttribute("CurrentState") == "Flashstep"
				or character:GetAttribute("CurrentState") == "Dashing"
			then
				AttributeListener.lastDash = tick()
			end

			if character:GetAttribute("CurrentState") == "Unconscious" then
				AttributeListener.lastKnock = tick()
			end
		end
	)
end

---On character removing.
---@param character Model
local function onCharacterRemoving(character)
	attributeMaid["CurrentStateAttributeChanged"] = nil
	AttributeListener.lastParry = nil
	AttributeListener.lastDash = nil
	AttributeListener.lastKnock = nil
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

---Can we parry?
---@return boolean
function AttributeListener.cparry()
	local localPlayer = players.LocalPlayer
	local character = localPlayer.Character
	if not character then
		return false
	end

	return not AttributeListener.lastParry
		or tick() - AttributeListener.lastParry >= (character:GetAttribute("ParryCooldown") / 1000)
end

---Can we dash?
---@return boolean
function AttributeListener.cdash()
	local localPlayer = players.LocalPlayer
	local character = localPlayer.Character
	if not character then
		return false
	end

	return not AttributeListener.lastDash or tick() - AttributeListener.lastDash >= (1750 / 1000)
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
	attributeMaid:clean()
end

-- Return AttributeListener module.
return AttributeListener

end)
__bundle_register("Game/InputClient", function(require, _LOADED, __bundle_register, __bundle_modules)
-- InputClient module.
local InputClient = {}

-- Services.
local players = game:GetService("Players")
local userInputService = game:GetService("UserInputService")
local replicatedStorage = game:GetService("ReplicatedStorage")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---Deflect. This is called this way because it can either give parry or block frames depending on whether or not parry is on cooldown.
function InputClient.deflect()
	InputClient.block(true)

	task.wait(Configuration.expectOptionValue("DeflectHoldTime") / 1000)

	InputClient.block(false)
end

---Block.
---@param state boolean
function InputClient.block(state)
	local localPlayer = players.LocalPlayer
	if not localPlayer then
		return
	end

	local character = localPlayer.Character
	if not character then
		return
	end

	local characterHandler = character:FindFirstChild("CharacterHandler")
	if not characterHandler then
		return
	end

	local remotes = characterHandler:FindFirstChild("Remotes")
	local block = remotes and remotes:FindFirstChild("Block")
	if not block then
		return
	end

	block:FireServer(state and "Pressed" or "Released")
end

---Dash.
function InputClient.dash()
	local localPlayer = players.LocalPlayer
	if not localPlayer then
		return
	end

	local character = localPlayer.Character
	if not character then
		return
	end

	local characterHandler = character:FindFirstChild("CharacterHandler")
	if not characterHandler then
		return
	end

	local remotes = characterHandler:FindFirstChild("Remotes")
	local dash = remotes and remotes:FindFirstChild("Dash")
	if not dash then
		return
	end

	---@todo: Implement later.
	--[[
    	local l_l_Parent_0_Attribute_1 = character:GetAttribute("CurrentState")
        if not v346 then
            if l_UserInputService_0:IsKeyDown(Enum.KeyCode.LeftShift) or v345 then
                l_Remotes_0.Flashstep:FireServer("Pressed")
            elseif l_l_Parent_0_Attribute_1 == "Sprinting" and v46 == "Q" then
                l_Remotes_0.Flashstep:FireServer("Pressed")
            end
        elseif l_l_Parent_0_Attribute_1 == "Sprinting" then
            l_Remotes_0.Flashstep:FireServer("Pressed")
        end
        local v348 = "S"
        if v345 then
            v348 = getDirection(l_Parent_0.HumanoidRootPart.CFrame.LookVector)
        end
    ]]
	--
	local v348 = Configuration.expectOptionValue("DefaultDashDirection") or "S"
	local directions = { "W", "A", "S", "D" }

	if v348 == "Random" then
		v348 = directions[math.random(1, #directions)]
	end

	for _, v350 in ipairs(directions) do
		local l_status_4, l_result_4 = pcall(function() --[[ Line: 1629 ]]
			-- upvalues: v350 (copy)
			return Enum.KeyCode[v350]
		end)

		if l_status_4 and l_result_4 and userInputService:IsKeyDown(l_result_4) then
			v348 = v350
		end
	end

	dash:FireServer(v348, nil)
end

---Parry. Fires the dedicated Misc/Parry remote in ReplicatedStorage.
---This is a distinct route from block cycling (deflect) and should be used
---when a parry window is explicitly intended.
function InputClient.parry()
	local remotes = replicatedStorage:FindFirstChild("Remotes")
	local requestModule = remotes and remotes:FindFirstChild("RequestModule")
	if not requestModule then
		return
	end

	requestModule:FireServer("Misc", "Parry")
end

---Apparat. Fires the Misc/Evasive remote — a last-resort combo breaker that
---turns the local player invisible and untargetable.
function InputClient.apparat()
	local remotes = replicatedStorage:FindFirstChild("Remotes")
	local requestModule = remotes and remotes:FindFirstChild("RequestModule")
	if not requestModule then
		return
	end

	requestModule:FireServer("Misc", "Evasive")
end

-- Return InputClient module.
return InputClient

end)
__bundle_register("Features/Combat/Targeting", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Targeting module.
---@note: Glorified extended non-utility Entities file.
local Targeting = {}

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Game.PlayerScanning
local PlayerScanning = require("Game/PlayerScanning")

---@module Features.Combat.Objects.Target
local Target = require("Features/Combat/Objects/Target")

---@module Utility.Table
local Table = require("Utility/Table")

-- Services.
local players = game:GetService("Players")
local userInputService = game:GetService("UserInputService")

---Get a list of all viable targets.
---@return Target[]
Targeting.viable = LPH_NO_VIRTUALIZE(function()
	local ents = workspace:FindFirstChild("Entities")
	if not ents then
		return {}
	end

	local localCharacter = players.LocalPlayer.Character
	if not localCharacter then
		return {}
	end

	local localRootPart = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
	if not localRootPart then
		return {}
	end

	local currentCamera = workspace.CurrentCamera
	if not currentCamera then
		return {}
	end

	local targets = {}

	for _, entity in next, ents:GetChildren() do
		if entity == localCharacter then
			continue
		end

		local playerFromCharacter = players:GetPlayerFromCharacter(entity)
		if not playerFromCharacter and Configuration.expectToggleValue("IgnoreMobs") then
			continue
		end

		if playerFromCharacter and Configuration.expectToggleValue("IgnorePlayers") then
			continue
		end

		local humanoid = entity:FindFirstChildWhichIsA("Humanoid")
		if not humanoid then
			continue
		end

		local rootPart = entity:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			continue
		end

		if humanoid.Health <= 0 then
			continue
		end

		local usernameList = Options["UsernameList"]

		local displayNameFound = playerFromCharacter
			and table.find(usernameList.Values, playerFromCharacter.DisplayName)

		local usernameFound = playerFromCharacter and table.find(usernameList.Values, playerFromCharacter.Name)

		if displayNameFound or usernameFound then
			continue
		end

		local fieldOfViewToEntity =
			currentCamera.CFrame.LookVector:Dot((localRootPart.Position - rootPart.Position).Unit)

		local fieldOfViewLimit = Configuration.expectOptionValue("FOVLimit")

		if fieldOfViewLimit <= 0 or (fieldOfViewToEntity * -1) <= math.cos(math.rad(fieldOfViewLimit)) then
			continue
		end

		local currentDistance = (rootPart.Position - localRootPart.Position).Magnitude
		if currentDistance > Configuration.expectOptionValue("DistanceLimit") then
			continue
		end

		if
			playerFromCharacter
			and PlayerScanning.isAlly(playerFromCharacter)
			and Configuration.expectToggleValue("IgnoreAllies")
		then
			continue
		end

		local mousePosition = userInputService:GetMouseLocation()
		local unitRay = workspace.CurrentCamera:ScreenPointToRay(mousePosition.X, mousePosition.Y)
		local distanceToCrosshair = unitRay:Distance(rootPart.Position)

		targets[#targets + 1] =
			Target.new(entity, humanoid, rootPart, distanceToCrosshair, fieldOfViewToEntity, currentDistance)
	end

	return targets
end)

---Get the best targets through sorting.
---@return Target[]
Targeting.best = LPH_NO_VIRTUALIZE(function()
	local targets = Targeting.viable()
	local sortType = Configuration.expectOptionValue("PlayerSelectionType")
	local sortFunction = nil

	if sortType == "Closest To Crosshair" then
		sortFunction = function(first, second)
			return first.dc < second.dc
		end
	end

	if sortType == "Closest In Distance" then
		sortFunction = function(first, second)
			return first.du < second.du
		end
	end

	if sortType == "Least Health" then
		sortFunction = function(first, second)
			return first.humanoid.Health < second.humanoid.Health
		end
	end

	table.sort(targets, sortFunction)

	return Table.slice(targets, 1, Configuration.expectOptionValue("MaxTargets"))
end)

---Find our model from a list of best targets.
---@param model Model
---@return Target?
Targeting.find = LPH_NO_VIRTUALIZE(function(model)
	for _, target in next, Targeting.best() do
		if target.character ~= model then
			continue
		end

		return target
	end
end)

-- Return Targeting module.
return Targeting

end)
__bundle_register("Utility/Table", function(require, _LOADED, __bundle_register, __bundle_modules)
return LPH_NO_VIRTUALIZE(function()
	-- Table utility functions.
	local Table = {}

	---Take a chunk out of an array into a new array.
	---@param input any[]
	---@param start number
	---@param stop number
	---@return any[]
	function Table.slice(input, start, stop)
		local out = {}

		if start == nil then
			start = 1
		elseif start < 0 then
			start = #input + start + 1
		end
		if stop == nil then
			stop = #input
		elseif stop < 0 then
			stop = #input + stop + 1
		end

		for idx = start, stop do
			table.insert(out, input[idx])
		end

		return out
	end

	-- Return Table module.
	return Table
end)()

end)
__bundle_register("Features/Combat/Objects/Target", function(require, _LOADED, __bundle_register, __bundle_modules)
---@note: Typed object that represents a target. It's not really a true class but just needs to store the correct data.
---@class Target
---@field character Model
---@field humanoid Humanoid
---@field root BasePart
---@field dc number Distance to crosshair.
---@field fov number Field of view to target.
---@field du number Distance to us.
local Target = {}

---Create new Target object.
---@param character Model
---@param humanoid Humanoid
---@param root BasePart
---@param dc number
---@param fov number
---@param du number
---@return Target
function Target.new(character, humanoid, root, dc, fov, du)
	local self = setmetatable({}, Target)
	self.character = character
	self.humanoid = humanoid
	self.root = root
	self.dc = dc
	self.fov = fov
	self.du = du
	return self
end

-- Return Target module.
return Target

end)
__bundle_register("Features/Combat/Objects/Task", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Utility.TaskSpawner
local TaskSpawner = require("Utility/TaskSpawner")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@class Task
---@field thread thread
---@field identifier string
---@field when number A timestamp when the task will be executed.
---@field punishable number A window in seconds where the task can be punished.
---@field after number A window in seconds where the task can be executed.
---@field delay function
local Task = {}
Task.__index = Task

---Check if task should block the input.
---@return boolean
function Task:blocking()
	if not (coroutine.status(self.thread) ~= "dead") then
		return false
	end

	-- We've exceeded the execution time. Block if we're within the after window.
	if os.clock() >= self:when() then
		return os.clock() <= self:when() + self.after
	end

	---@note: Allow us to do inputs up until a certain amount of time before the task happens.
	return os.clock() >= self:when() - self.punishable
end

---Cancel task.
function Task:cancel()
	if coroutine.status(self.thread) ~= "suspended" then
		return
	end

	task.cancel(self.thread)
end

---Get when approximately the task will be executed.
---@return number
function Task:when()
	return self.when + self.delay()
end

---Create new Task object.
---@param identifier string
---@param delay function
---@param punishable number
---@param after number
---@param callback function
---@vararg any
---@return Task
function Task.new(identifier, delay, punishable, after, callback, ...)
	local self = setmetatable({}, Task)
	self.identifier = identifier
	self.delay = delay
	self.punishable = punishable
	self.after = after
	self.thread = TaskSpawner.delay("Action_" .. identifier, delay, callback, ...)

	if not self.punishable or self.punishable <= 0 then
		self.punishable = Configuration.expectOptionValue("DefaultPunishableWindow") or 0.7
	end

	if not self.after or self.after <= 0 then
		self.after = Configuration.expectOptionValue("DefaultAfterWindow") or 0.1
	end

	return self
end

-- Return Task module.
return Task

end)
__bundle_register("Features/Combat/Objects/PartDefender", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Features.Combat.Objects.Defender
local Defender = require("Features/Combat/Objects/Defender")

---@module Game.Timings.SaveManager
local SaveManager = require("Game/Timings/SaveManager")

---@module Features.Combat.Objects.RepeatInfo
local RepeatInfo = require("Features/Combat/Objects/RepeatInfo")

---@module Features.Combat.Objects.HitboxOptions
local HitboxOptions = require("Features/Combat/Objects/HitboxOptions")

---@class PartDefender: Defender
---@field part BasePart
---@field timing PartTiming
---@field touched boolean Determines whether if we touched the timing in the past.
local PartDefender = setmetatable({}, { __index = Defender })
PartDefender.__index = PartDefender
PartDefender.__type = "Part"

-- Services.
local players = game:GetService("Players")

---Get CFrame.
---@param self PartDefender
---@return CFrame
PartDefender.cframe = LPH_NO_VIRTUALIZE(function(self)
	return self.timing.uhc and self.part.CFrame or CFrame.new(self.part.Position)
end)

---Check if we're in a valid state to proceed with the action.
---@param self PartDefender
---@param timing PartTiming
---@param action Action
---@return boolean
PartDefender.valid = LPH_NO_VIRTUALIZE(function(self, timing, action)
	if not Defender.valid(self, timing, action) then
		return false
	end

	local character = players.LocalPlayer.Character
	if not character then
		return self:notify(timing, "No character found.")
	end

	local options = HitboxOptions.new(self:cframe(), timing)
	options.spredict = false
	options.action = action

	if not self.timing.duih and not self:hc(options, timing.duih and RepeatInfo.new(timing) or nil) then
		return self:notify(timing, "Not in hitbox.")
	end

	return true
end)

---Update PartDefender object.
---@param self PartDefender
PartDefender.update = LPH_NO_VIRTUALIZE(function(self)
	-- Skip if we're not handling delay until in hitbox.
	if not self.timing.duih then
		return
	end

	-- Deny updates if we already have actions in the queue.
	if #self.tasks > 0 then
		return
	end

	local localPlayer = players.LocalPlayer
	if not localPlayer then
		return
	end

	local character = localPlayer.Character
	if not character then
		return
	end

	local hb = self.timing.hitbox

	hb = Vector3.new(PP_SCRAMBLE_NUM(hb.X), PP_SCRAMBLE_NUM(hb.Y), PP_SCRAMBLE_NUM(hb.Z))

	-- Get current hitbox state.
	---@note: If we're using PartDefender, why perserve rotation? It's likely wrong or gonna mess us up.
	local touching = self:hitbox(self:cframe(), self.timing.fhb, hb, { character }, PP_SCRAMBLE_STR(self.timing.name))

	-- Deny updates if we're not touching the part.
	if not touching then
		return
	end

	-- Deny updates if the we were touching the part last and we are touching it now.
	if self.touched and touching then
		return
	end

	-- Ok, set the new state.
	self.touched = touching

	-- Clean all previous tasks. Just to be safe. We already check if it's empty... so.
	self:clean()

	-- Add actions.
	return self:actions(self.timing)
end)

---Create new PartDefender object.
---@param part BasePart
---@param timing PartTiming?
---@return PartDefender?
function PartDefender.new(part, timing)
	local self = setmetatable(Defender.new(), PartDefender)

	self.part = part
	self.timing = timing or self:initial(part, SaveManager.ps, nil, part.Name)
	self.touched = false

	-- Handle no timing.
	if not self.timing then
		return nil
	end

	-- Handle module.
	if self.timing.umoa then
		self:module(self.timing)
	end

	-- Handle no hitbox delay with no module.
	if not self.timing.umoa and not self.timing.duih then
		self:actions(self.timing)
	end

	-- Return self.
	return self
end

-- Return PartDefender module.
return PartDefender

end)
__bundle_register("Features/Combat/Objects/AnimatorDefender", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Features.Combat.Objects.Defender
local Defender = require("Features/Combat/Objects/Defender")

---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Game.Timings.SaveManager
local SaveManager = require("Game/Timings/SaveManager")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Game.InputClient
local InputClient = require("Game/InputClient")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Game.Timings.PlaybackData
local PlaybackData = require("Game/Timings/PlaybackData")

---@module GUI.Library
local Library = require("GUI/Library")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Features.Combat.Objects.RepeatInfo
local RepeatInfo = require("Features/Combat/Objects/RepeatInfo")

---@module Features.Combat.Objects.HitboxOptions
local HitboxOptions = require("Features/Combat/Objects/HitboxOptions")

---@module Features.Combat.Objects.Task
local Task = require("Features/Combat/Objects/Task")

---@module Utility.TaskSpawner
local TaskSpawner = require("Utility/TaskSpawner")

---@module Features.Combat.PositionHistory
local PositionHistory = require("Features/Combat/PositionHistory")

---@module Utility.OriginalStore
local OriginalStore = require("Utility/OriginalStore")

---@module Features.Combat.AttributeListener
local AttributeListener = require("Features/Combat/AttributeListener")

---@class AnimatorDefender: Defender
---@field animator Animator
---@field entity Model
---@field kfmaid Maid
---@field heffects Instance[]
---@field keyframes Action[]
---@field offset number?
---@field timing AnimationTiming?
---@field pbdata table<AnimationTrack, PlaybackData> Playback data to be recorded.
---@field rpbdata table<string, PlaybackData> Recorded playback data. Optimization so we don't have to constantly reiterate over recorded data.
---@field manimations table<number, Animation>
---@field track AnimationTrack? Don't be confused. This is the **valid && last** animation track played.
---@field maid Maid This maid is cleaned up after every new animation track. Safe to use for on-animation-track setup.
local AnimatorDefender = setmetatable({}, { __index = Defender })
AnimatorDefender.__index = AnimatorDefender
AnimatorDefender.__type = "Animation"

-- Services.
local players = game:GetService("Players")

-- Constants.
local MAX_REPEAT_TIME = 5.0
local HISTORY_STEPS = 5.0
local PREDICT_FACING_DELTA = 0.3

---Is animation stopped? Made into a function for de-duplication.
---@param self AnimatorDefender
---@param track AnimationTrack
---@param timing AnimationTiming
---@return boolean
AnimatorDefender.stopped = LPH_NO_VIRTUALIZE(function(self, track, timing)
	if
		Configuration.expectToggleValue("AllowFailure")
		and not timing.umoa
		and not timing.rpue
		and Random.new():NextNumber(1.0, 100.0) <= (Configuration.expectOptionValue("IgnoreAnimationEndRate") or 0.0)
		and AttributeListener.cdash()
	then
		return false, self:notify(timing, "Intentionally ignoring animation end to simulate human error.")
	end

	if not timing.iae and not track.IsPlaying then
		return true, self:notify(timing, "Animation stopped playing.")
	end

	if timing.iae and not timing.ieae and not track.IsPlaying and track.TimePosition < track.Length then
		return true, self:notify(timing, "Animation stopped playing early.")
	end
end)

---Repeat conditional. Extra parameter 'track' added on.
---@param self AnimatorDefender
---@param info RepeatInfo
---@return boolean
AnimatorDefender.rc = LPH_NO_VIRTUALIZE(function(self, info)
	---@note: There are cases where we might not have a track. If it's not handled properly, it will throw an error.
	-- Perhaps, the animation can end and we're handling a different repeat conditional.
	if not info.track then
		return Logger.warn(
			"(%s) Did you forget to pass the track? Or perhaps you forgot to place a hook before using this function.",
			PP_SCRAMBLE_STR(info.timing.name)
		)
	end

	if self:stopped(info.track, info.timing) then
		return false
	end

	if info.timing.iae and os.clock() - info.start >= ((info.timing.mat / 1000) or MAX_REPEAT_TIME) then
		return self:notify(info.timing, "Max animation timeout exceeded.")
	end

	return true
end)

---Run predict facing hitbox check.
---@param self AnimatorDefender
---@param options HitboxOptions
---@return boolean
AnimatorDefender.pfh = LPH_NO_VIRTUALIZE(function(self, options)
	local yrate = PositionHistory.yrate(self.entity)
	if not yrate then
		return false
	end

	local root = self.entity:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local localRoot = players.LocalPlayer.Character and players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not localRoot then
		return false
	end

	if math.abs(yrate) < PREDICT_FACING_DELTA then
		return
	end

	local clone = options:clone()
	clone.spredict = false
	clone.hcolor = Color3.new(0, 1, 1)
	clone.mcolor = Color3.new(1, 1, 0)

	local result = false
	local store = OriginalStore.new()

	store:run(root, "CFrame", CFrame.lookAt(root.Position, localRoot.Position), function()
		result = self:hc(clone, nil)
	end)

	return result
end)

---Run past hitbox check.
---@param timing Timing
---@param options HitboxOptions
---@return boolean
AnimatorDefender.phd = LPH_NO_VIRTUALIZE(function(self, timing, options)
	for _, cframe in next, PositionHistory.stepped(self.entity, HISTORY_STEPS, timing.phds) or {} do
		local clone = options:clone()
		clone.spredict = false
		clone.cframe = cframe
		clone.hcolor = Color3.new(0.839215, 0.976470, 0.537254)
		clone.mcolor = Color3.new(0.564705, 0, 1)

		if not self:hc(clone, nil) then
			continue
		end

		return true
	end
end)

---Get extrapolated seconds.
---@param self Defender
---@param timing AnimationTiming
---@return number
AnimatorDefender.fsecs = LPH_NO_VIRTUALIZE(function(self, timing)
	local player = players:GetPlayerFromCharacter(self.entity)
	local sd = (player and player:GetAttribute("AveragePing") or 50.0) / 2000
	return (timing.pfht or 0.15) + (sd + Defender.rdelay())
end)

---Run our facing extrapolation / interpolation.
AnimatorDefender.fpc = LPH_NO_VIRTUALIZE(function(self, timing, options)
	if timing.duih then
		return false
	end

	if timing.pfh and self:pfh(options) then
		return true
	end

	if timing.phd and self:phd(timing, options) then
		return true
	end
end)

---Check if we're in a valid state to proceed with the action.
---@param self AnimatorDefender
---@param timing AnimationTiming
---@param action Action
---@return boolean
AnimatorDefender.valid = LPH_NO_VIRTUALIZE(function(self, timing, action)
	if not Defender.valid(self, timing, action) then
		return false
	end

	if not self.track then
		return self:notify(timing, "No current track.")
	end

	if not self.entity then
		return self:notify(timing, "No entity found.")
	end

	local target = self:target(self.entity)
	if not target then
		return self:notify(timing, "Not a viable target.")
	end

	local root = self.entity:FindFirstChild("HumanoidRootPart")
	if not root then
		return self:notify(timing, "No humanoid root part found.")
	end

	if self:stopped(self.track, timing) then
		return false
	end

	local options = HitboxOptions.new(root, timing)
	options.spredict = not timing.duih and not timing.dp
	options.ptime = self:fsecs(timing)
	options.action = action
	options.entity = self.entity

	local info = RepeatInfo.new(timing)
	info.track = self.track

	local hc = self:hc(options, timing.duih and info or nil)
	if hc then
		return true
	end

	local pc = self:fpc(timing, options)
	if pc then
		return true
	end

	return self:notify(timing, "Not in hitbox.")
end)

---Add a new Keyframe action.
---@param self AnimatorDefender
---@param action Action
---@param tp number
function AnimatorDefender:akeyframe(action, tp)
	-- Set time position.
	action.tp = tp

	---@note: These have to be sent in by a module, so the hitbox and the name also have to get fixed.
	action["_type"] = PP_SCRAMBLE_STR(action["_type"])
	action["name"] = PP_SCRAMBLE_STR(action["name"])
	action["hitbox"] = Vector3.new(
		PP_SCRAMBLE_RE_NUM(action["hitbox"].X),
		PP_SCRAMBLE_RE_NUM(action["hitbox"].Y),
		PP_SCRAMBLE_RE_NUM(action["hitbox"].Z)
	)

	-- Insert in list.
	table.insert(self.keyframes, action)
end

---Get time position of current track.
---@return number?
function AnimatorDefender:tp()
	if not self.track or self.offset == nil then
		return nil
	end

	---@note: Compensate for ping. Convert seconds to time position by adjusting for speed.
	--- Higher speed means it will delay earlier.
	--- Smaller speed means it will delay later.
	return self.track.TimePosition + ((self.offset + self.sdelay()) / self.track.Speed)
end

---Get latest keyframe action that we've exceeded.
---@return Action?
AnimatorDefender.latest = LPH_NO_VIRTUALIZE(function(self)
	local latestKeyframe = nil
	local latestTimePosition = nil

	for _, keyframe in next, self.keyframes do
		if (self:tp() or 0.0) <= keyframe.tp then
			continue
		end

		if latestTimePosition and keyframe.tp <= latestTimePosition then
			continue
		end

		latestTimePosition = keyframe.tp
		latestKeyframe = keyframe
	end

	return latestKeyframe
end)

---Update handling.
---@param self AnimatorDefender
AnimatorDefender.update = LPH_NO_VIRTUALIZE(function(self)
	for track, data in next, self.pbdata do
		-- Don't process tracks.
		if not Configuration.expectToggleValue("ShowAnimationVisualizer") then
			self.pbdata[track] = nil
			continue
		end

		-- Check if the track is playing.
		if not track.IsPlaying then
			-- Remove out of 'pbdata' and put it in to the recorded table.
			self.pbdata[track] = nil
			self.rpbdata[tostring(track.Animation.AnimationId)] = data

			-- Continue to next playback data.
			continue
		end

		-- Start tracking the animation's speed.
		data:astrack(track.Speed)
	end

	-- Run on validated track & timing.
	if not self.track or not self.timing then
		return
	end

	if not self.track.IsPlaying then
		return
	end

	-- Find the latest keyframe that we have exceeded, if there is even any.
	local latest = self:latest()
	if not latest then
		return
	end

	-- Clear the keyframes that we have exceeded.
	local tp = self:tp() or 0.0

	for idx, keyframe in next, self.keyframes do
		if tp <= keyframe.tp then
			continue
		end

		self.keyframes[idx] = nil
	end

	-- Log.
	self:notify(
		self.timing,
		"(%.2f) (really %.2f) Keyframe action '%s' with type '%s' is being executed.",
		tp,
		self.track.TimePosition,
		PP_SCRAMBLE_STR(latest.name),
		PP_SCRAMBLE_STR(latest._type)
	)

	-- Ok, run action of this keyframe.
	self.maid:mark(
		TaskSpawner.spawn(
			string.format("KeyframeAction_%s", PP_SCRAMBLE_STR(latest._type)),
			self.handle,
			self,
			self.timing,
			latest,
			false
		)
	)
end)

---Virtualized processing checks.
---@param track AnimationTrack
---@return boolean
function AnimatorDefender:pvalidate(track)
	if track.Priority == Enum.AnimationPriority.Core then
		return false
	end

	return true
end

---Process animation track.
---@todo: AP telemetry - aswell as tracking effects that are added with timestamps and current ping to that list.
---@param self AnimatorDefender
---@param track AnimationTrack
AnimatorDefender.process = LPH_NO_VIRTUALIZE(function(self, track)
	if players.LocalPlayer.Character and self.entity == players.LocalPlayer.Character then
		return
	end

	if not self:pvalidate(track) then
		return
	end

	-- Clean up Keyframe maid.
	self.kfmaid:clean()

	-- Add to playback data list.
	if Configuration.expectToggleValue("ShowAnimationVisualizer") then
		self.pbdata[track] = PlaybackData.new(self.entity)
	end

	-- Animation ID.
	local aid = tostring(track.Animation.AnimationId)

	-- In logging range?
	local distance = self:distance(self.entity)
	local ilr = distance
		and (
			distance >= (Configuration.expectOptionValue("MinimumLoggerDistance") or 0)
			and distance <= (Configuration.expectOptionValue("MaximumLoggerDistance") or 0)
		)

	-- Keyframe logging.
	local keyframeReached = Signal.new(track.KeyframeReached)

	self.kfmaid:add(keyframeReached:connect("AnimationDefender_OnKeyFrameReached", function(kfname)
		if not ilr then
			return
		end

		Library:AddKeyFrameEntry(distance, aid, kfname, track.TimePosition, false)
	end))

	---@type AnimationTiming?
	local timing = self:initial(self.entity, SaveManager.as, self.entity.Name, aid)
	if not timing then
		return
	end

	if ilr then
		Library:AddExistAnimEntry(self.entity.Name, distance, timing)
	end

	if not Configuration.expectToggleValue("EnableAutoDefense") then
		return
	end

	local humanoidRootPart = self.entity:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	---@note: Clean up previous tasks that are still waiting or suspended because they're in a different track.
	self:clean()

	-- Set current data.
	self.timing = timing
	self.track = track
	self.offset = self.rdelay()

	-- Fake mistime rate.
	---@type Action?
	local _, faction = next(timing.actions._data)

	-- Obviously, we don't want any modules where we don't know how many actions there are.
	-- We don't want any actions that have a count that is not equal to 1.
	-- We need to check if we can atleast dash, because we will be going to are fallback.
	-- We must also check if our action isn't too short or is not a parry type, defeating the purpose.
	if
		Configuration.expectToggleValue("AllowFailure")
		and not timing.umoa
		and not timing.rpue
		and timing.actions:count() == 1
		and Random.new():NextNumber(1.0, 100.0) <= (Configuration.expectOptionValue("FakeMistimeRate") or 0.0)
		and AttributeListener.cdash()
		and faction
		and PP_SCRAMBLE_STR(faction._type) == "Parry"
		and faction:when() > (self.rtt() + 0.6)
	then
		InputClient.deflect()

		self:notify(timing, "Intentionally mistimed to simulate human error.")
	end

	-- Use module over actions.
	if timing.umoa then
		return self:module(timing)
	end

	---@note: Start processing the timing. Add the actions if we're not RPUE.
	if not timing.rpue then
		return self:actions(timing)
	end

	-- Start RPUE.
	local info = RepeatInfo.new(timing, self.rdelay())
	info.track = track

	self:mark(Task.new(string.format("RPUE_%s_%i", timing.name, 0), function()
		return timing:rsd() - info.irdelay - self.sdelay()
	end, timing.punishable, timing.after, self.rpue, self, self.entity, timing, info))

	-- Notify.
	if not LRM_UserNote or LRM_UserNote == "tester" then
		self:notify(
			timing,
			"Added RPUE '%s' (%.2fs, then every %.2fs) with ping '%.2f' (changing) subtracted.",
			PP_SCRAMBLE_STR(timing.name),
			timing:rsd(),
			timing:rpd(),
			self.rtt()
		)
	else
		self:notify(
			timing,
			"Added RPUE '%s' ([redacted], then every [redacted]) with ping '%.2f' (changing) subtracted.",
			PP_SCRAMBLE_STR(timing.name),
			self.rtt()
		)
	end
end)

---Clean up the defender.
function AnimatorDefender:clean()
	-- Empty data.
	self.keyframes = {}
	self.heffects = {}

	-- Empty Keyframe maid.
	self.kfmaid:clean()

	-- Clean through base method.
	Defender.clean(self)
end

---Create new AnimatorDefender object.
---@param animator Animator
---@return AnimatorDefender
function AnimatorDefender.new(animator)
	local entity = animator:FindFirstAncestorWhichIsA("Model")
	if not entity then
		return error(string.format("AnimatorDefender.new(%s) - no entity.", animator:GetFullName()))
	end

	local self = setmetatable(Defender.new(), AnimatorDefender)
	local animationPlayed = Signal.new(animator.AnimationPlayed)

	self.animator = animator
	self.entity = entity
	self.kfmaid = Maid.new()

	self.track = nil
	self.timing = nil
	self.rdelay = nil

	self.heffects = {}
	self.keyframes = {}
	self.pbdata = {}
	self.rpbdata = {}

	self.maid:mark(animationPlayed:connect(
		"AnimatorDefender_OnAnimationPlayed",
		LPH_NO_VIRTUALIZE(function(track)
			self:process(track)
		end)
	))

	return self
end

-- Return AnimatorDefender module.
return AnimatorDefender

end)
__bundle_register("Game/Timings/PlaybackData", function(require, _LOADED, __bundle_register, __bundle_modules)
---@class PlaybackData
---@field base number Timestamp of when the object was created.
---@field ash table<number, number> Animation speed history. The key is the timestamp delta and the value is the speed at that point.
---@field entity Model Entity to playback.
local PlaybackData = {}
PlaybackData.__index = PlaybackData

---Get last exceeded speed difference from a timestamp delta.
---@param from number
---@return number?, number?
function PlaybackData:last(from)
	local latestExceededSpeed = nil
	local latestExceededDelta = nil

	for delta, speed in next, self.ash do
		if from <= delta then
			continue
		end

		if latestExceededDelta and delta <= latestExceededDelta then
			continue
		end

		latestExceededSpeed = speed
		latestExceededDelta = delta
	end

	return latestExceededSpeed, latestExceededDelta
end

---Track animation speed.
---@param speed number
function PlaybackData:astrack(speed)
	local delta = os.clock() - self.base

	if self:last(delta) == speed then
		return
	end

	self.ash[delta] = speed
end

---Create new PlaybackData object.
---@param entity Model
---@return PlaybackData
function PlaybackData.new(entity)
	local self = setmetatable({}, PlaybackData)
	self.base = os.clock()
	self.entity = entity

	---@note: Timestamp delta is how many seconds need to pass before being able to reach this speed.
	self.ash = {}

	return self
end

-- Return PlaybackData module.
return PlaybackData

end)
__bundle_register("Utility/ControlModule", function(require, _LOADED, __bundle_register, __bundle_modules)
return LPH_NO_VIRTUALIZE(function()
	-- This module is used for getting the proper input fly values - 1:1 with Aztup.
	local ControlModule = {
		forwardValue = 0,
		backwardValue = 0,
		leftValue = 0,
		rightValue = 0,
	}

	---@module Utility.Profiler
	local Profiler = require("Utility/Profiler")

	---@module Utility.Logger
	local Logger = require("Utility/Logger")

	---@module Utility.Maid
	local Maid = require("Utility/Maid")

	-- Maids.
	local controlMaid = Maid.new()

	-- Services.
	local ContextActionService = game:GetService("ContextActionService")

	---Bind action safely with maid, error, and profiler handling.
	---@param actionName string
	---@param callback function
	---@param createTouchButton boolean
	local function bindActionWrapper(actionName, callback, createTouchButton, ...)
		---Log bind action errors.
		---@param error string
		local function onBindActionWrapperError(error)
			Logger.trace("onBindActionWrapperError - (%s) - %s", actionName, error)
		end

		local actionWrapperCallback = callback
			and Profiler.wrap(string.format("ControlModule_BindActionWrapper_%s", actionName), function(...)
				local success, result = xpcall(callback, onBindActionWrapperError, ...)

				if not success then
					return nil
				end

				return result
			end)

		---@note: This is a hot-fix and should be handled properly in the future.
		controlMaid:add(function()
			ContextActionService:UnbindAction(actionName)
		end)

		ContextActionService:BindAction(actionName, actionWrapperCallback, createTouchButton, ...)
	end

	---Initialize control module.
	function ControlModule.init()
		bindActionWrapper("ControlModule_ForwardValue", function(_, inputState, _)
			ControlModule.forwardValue = (inputState == Enum.UserInputState.Begin) and -1 or 0
			return Enum.ContextActionResult.Pass
		end, false, Enum.KeyCode.W)

		bindActionWrapper("ControlModule_LeftValue", function(_, inputState, _)
			ControlModule.leftValue = (inputState == Enum.UserInputState.Begin) and -1 or 0
			return Enum.ContextActionResult.Pass
		end, false, Enum.KeyCode.A)

		bindActionWrapper("ControlModule_BackwardValue", function(_, inputState, _)
			ControlModule.backwardValue = (inputState == Enum.UserInputState.Begin) and 1 or 0
			return Enum.ContextActionResult.Pass
		end, false, Enum.KeyCode.S)

		bindActionWrapper("ControlModule_RightValue", function(_, inputState, _)
			ControlModule.rightValue = (inputState == Enum.UserInputState.Begin) and 1 or 0
			return Enum.ContextActionResult.Pass
		end, false, Enum.KeyCode.D)

		Logger.warn("ControlModule initialized.")
	end

	---Detach control module.
	function ControlModule.detach()
		controlMaid:clean()
		Logger.warn("ControlModule detached.")
	end

	---Get move vector.
	---@return Vector3
	function ControlModule.getMoveVector()
		return Vector3.new(
			ControlModule.leftValue + ControlModule.rightValue,
			0,
			ControlModule.forwardValue + ControlModule.backwardValue
		)
	end

	-- Return control module.
	return ControlModule
end)()

end)
__bundle_register("Features", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Features related stuff is handled here.
local Features = {}

---@module Features.Game.Movement
local Movement = require("Features/Game/Movement")

---@module Features.Visuals.Visuals
local Visuals = require("Features/Visuals/Visuals")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Features.Combat.Defense
local Defense = require("Features/Combat/Defense")

---@module Features.Game.AnimationVisualizer
local AnimationVisualizer = require("Features/Game/AnimationVisualizer")

---@module Features.Game.AnimationLogger
local AnimationLogger = require("Features/Game/AnimationLogger")

---@modules Features.Combat.AttributeListener
local AttributeListener = require("Features/Combat/AttributeListener")

---@module Features.Game.Monitoring
local Monitoring = require("Features/Game/Monitoring")

---@module Features.Game.OwnershipWatcher
local OwnershipWatcher = require("Features/Game/OwnershipWatcher")

---@module Features.Exploits.Exploits
local Exploits = require("Features/Exploits/Exploits")

---@module Features.Game.Removal
local Removal = require("Features/Game/Removal")

---@module Features.Automation.Input
local Input = require("Features/Automation/Input")

---Initialize features.
---@note: Careful with features that have entire return LPH_NO_VIRTUALIZE(function() blocks. We assume that we don't care about what's placed in there.
function Features.init()
	Monitoring.init()
	AttributeListener.init()
	Defense.init()
	Visuals.init()
	Movement.init()
	OwnershipWatcher.init()
	Exploits.init()
	Removal.init()
	Input.init()
	AnimationVisualizer.init()
	AnimationLogger.init()

	Logger.warn("Features initialized.")
end

---Detach features.
function Features.detach()
	AnimationVisualizer.detach()
	AnimationLogger.detach()

	Monitoring.detach()
	AttributeListener.detach()
	Defense.detach()
	Movement.detach()
	Visuals.detach()
	OwnershipWatcher.detach()
	Exploits.detach()
	Removal.detach()
	Input.detach()

	Logger.warn("Features detached.")
end

-- Return Features module.
return Features

end)
__bundle_register("Features/Automation/Input", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Input module.
local Input = {}

---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Utility.TaskSpawner
local TaskSpawner = require("Utility/TaskSpawner")

-- Services.
local virtualUser = game:GetService("VirtualUser")
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local virtualInputManager = game:GetService("VirtualInputManager")
local guiService = game:GetService("GuiService")

-- Maids.
local inputMaid = Maid.new()

---Handle raid accept.
local function handleRaidAccept()
	if not Configuration.expectToggleValue("AutoAcceptRaid") then
		return
	end

	local playerGui = players.LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end

	local playerGuiSettings = playerGui:FindFirstChild("Settings")
	if not playerGuiSettings then
		return
	end

	local raidConfirm = playerGuiSettings:FindFirstChild("RaidConfirm")
	if not raidConfirm or not raidConfirm.Visible then
		return
	end

	local yesButton = raidConfirm:FindFirstChild("Yes")
	if not yesButton or not yesButton.Visible then
		return
	end

	if raidConfirm.AbsoluteSize.X == 0 or raidConfirm.AbsoluteSize.Y == 0 then
		return
	end

	local guiInset = guiService:GetGuiInset()
	local pos = yesButton.AbsolutePosition
	local size = yesButton.AbsoluteSize
	local x = pos.X + (size.X / 2) + guiInset.X
	local y = pos.Y + (size.Y / 2) + guiInset.Y

	virtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)

	inputMaid:add(TaskSpawner.delay("Input_RaidAcceptClickRelease", function()
		return 0.1
	end, function()
		virtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
	end))
end

---Input initialization.
function Input.init()
	local localPlayer = players.LocalPlayer
	local idledSignal = Signal.new(localPlayer.Idled)
	local preRenderSignal = Signal.new(runService.PreRender)

	inputMaid:add(preRenderSignal:connect("Input_PreRender", function()
		handleRaidAccept()
	end))

	inputMaid:add(idledSignal:connect("Input_PlayerIdled", function()
		if not Configuration.expectToggleValue("AntiAFK") then
			return
		end

		virtualUser:CaptureController()
		virtualUser:ClickButton2(Vector2.new())
	end))
end

---Input detach.
function Input.detach()
	inputMaid:clean()
end

-- Return Input module.
return Input

end)
__bundle_register("Features/Game/Removal", function(require, _LOADED, __bundle_register, __bundle_modules)
return LPH_NO_VIRTUALIZE(function()
	-- Removal related stuff is handled here.
	local Removal = {}

	---@module Utility.Maid
	local Maid = require("Utility/Maid")

	---@module Utility.Signal
	local Signal = require("Utility/Signal")

	---@module Utility.Configuration
	local Configuration = require("Utility/Configuration")

	---@module Utility.OriginalStoreManager
	local OriginalStoreManager = require("Utility/OriginalStoreManager")

	---@module Utility.Logger
	local Logger = require("Utility/Logger")

	-- Services.
	local runService = game:GetService("RunService")
	local players = game:GetService("Players")
	local lighting = game:GetService("Lighting")

	-- Maids.
	local removalMaid = Maid.new()

	-- Original store managers.
	local noFogMap = removalMaid:mark(OriginalStoreManager.new())
	local noRaidMusicMap = removalMaid:mark(OriginalStoreManager.new())

	-- Signals.
	local renderStepped = Signal.new(runService.RenderStepped)

	-- Last update.
	local lastUpdate = os.clock()

	---Update no fog.
	local function updateNoFog()
		if lighting.FogStart == 9e9 and lighting.FogEnd == 9e9 then
			return
		end

		noFogMap:add(lighting, "FogStart", 9e9)
		noFogMap:add(lighting, "FogEnd", 9e9)

		local atmosphere = lighting:FindFirstChildOfClass("Atmosphere")
		if not atmosphere then
			return
		end

		if atmosphere.Density == 0 then
			return
		end

		noFogMap:add(atmosphere, "Density", 0)
	end

	---Update no raid music.
	local function updateNoRaidMusic()
		local playerRaid = workspace:FindFirstChild("PlayerRaid")
		if not playerRaid then
			return
		end

		for _, child in ipairs(playerRaid:GetChildren()) do
			if not child:IsA("Sound") then
				continue
			end

			noRaidMusicMap:add(child, "Volume", 0)
		end
	end

	---Update removal.
	local function updateRemoval()
		if os.clock() - lastUpdate <= 2.0 then
			return
		end

		lastUpdate = os.clock()

		local localPlayer = players.LocalPlayer
		if not localPlayer then
			return
		end

		if Configuration.expectToggleValue("NoFog") then
			updateNoFog()
		else
			noFogMap:restore()
		end

		if Configuration.expectToggleValue("NoRaidMusic") then
			updateNoRaidMusic()
		else
			noRaidMusicMap:restore()
		end
	end

	---Initalize removal.
	function Removal.init()
		removalMaid:add(renderStepped:connect("Removal_RenderStepped", updateRemoval))

		-- Log.
		Logger.warn("Removal initialized.")
	end

	---Detach removal.
	function Removal.detach()
		-- Clean.
		removalMaid:clean()

		-- Log.
		Logger.warn("Removal detached.")
	end

	-- Return Removal module.
	return Removal
end)()

end)
__bundle_register("Utility/OriginalStoreManager", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Utility.OriginalStore
local OriginalStore = require("Utility/OriginalStore")

---@class OriginalStoreManager
---@param inner OriginalStore[]
local OriginalStoreManager = {}
OriginalStoreManager.__index = OriginalStoreManager

---Forget data value.
---@param data table|Instance
OriginalStoreManager.forget = LPH_NO_VIRTUALIZE(function(self, data)
	self.inner[data] = nil
end)

---Mark data value.
---@param data table|Instance
---@param index any
OriginalStoreManager.mark = LPH_NO_VIRTUALIZE(function(self, data, index)
	local object = self.inner[data] or OriginalStore.new()

	object:mark(data, index)

	self.inner[data] = object
end)

---Add data value.
---@param data table|Instance
---@param index any
---@param value any
OriginalStoreManager.add = LPH_NO_VIRTUALIZE(function(self, data, index, value)
	local object = self.inner[data] or OriginalStore.new()

	object:set(data, index, value)

	self.inner[data] = object
end)

---Get data values.
---@return OriginalStore[]
OriginalStoreManager.data = LPH_NO_VIRTUALIZE(function(self)
	return self.inner
end)

---Get data value.
---@param data table|Instance
---@return OriginalStore
OriginalStoreManager.get = LPH_NO_VIRTUALIZE(function(self, data)
	return self.inner[data]
end)

---Restore data values.
OriginalStoreManager.restore = LPH_NO_VIRTUALIZE(function(self)
	for _, store in next, self.inner do
		store:restore()
	end
end)

---Detach OriginalStoreManager object.
OriginalStoreManager.detach = LPH_NO_VIRTUALIZE(function(self)
	for _, store in next, self.inner do
		store:detach()
	end

	self.inner = {}
end)

---Create new OriginalStoreManager object.
---@return OriginalStoreManager
OriginalStoreManager.new = LPH_NO_VIRTUALIZE(function()
	local self = setmetatable({}, OriginalStoreManager)
	self.inner = {}
	return self
end)

-- Return OriginalStoreManager module.
return OriginalStoreManager

end)
__bundle_register("Features/Exploits/Exploits", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.InstanceWrapper
local InstanceWrapper = require("Utility/InstanceWrapper")

-- Void maid.
local voidMaid = Maid.new()

---Void part.
---@param model Model
---@param part Part
local function voidPart(model, part)
	---@note: Push the part down constantly in an attempt to get it to fall through the void.
	---This also has the positive note of making the part not sleep - retaining it.
	if not part:FindFirstChild("BodyVelocity") then
		local partConstantVelocity = InstanceWrapper.create(voidMaid, part, "BodyVelocity", part)
		partConstantVelocity.MaxForce = Vector3.new(1 / 0, 1 / 0, 1 / 0)
		partConstantVelocity.Velocity = Vector3.new(0, -8500, 0)
		partConstantVelocity.P = 1 / 0
	end

	---@note: Remove part controllers.
	local velocityController = part:FindFirstChild("ControlVel")
		or part:FindFirstChild("SafetyBV")
		or part:FindFirstChild("SwimBV")
		or part:FindFirstChild("Holder")

	if velocityController and velocityController:IsA("BodyMover") then
		velocityController:Destroy()
	end

	-- Set part velocity.
	part.AssemblyLinearVelocity = Vector3.new(0, -5000, 0)

	-- Set model position.
	local modelPos = part.Position
	model:PivotTo(CFrame.new(modelPos.X, workspace.FallenPartsDestroyHeight, modelPos.Z))

	-- Stop part from sleeping.
	sethiddenproperty(part, "NetworkIsSleeping", false)
end

-- Exploits related stuff is handled here.
local Exploits = { ownershipTimestamp = 0, ownershipItem = nil, currentRootPart = nil, flipped = false }

---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Utility.OriginalStore
local OriginalStore = require("Utility/OriginalStore")

---@module Utility.OriginalStoreManager
local OriginalStoreManager = require("Utility/OriginalStoreManager")

---@module Features.Game.OwnershipWatcher
local OwnershipWatcher = require("Features/Game/OwnershipWatcher")

---@module Utility.Logger
local Logger = require("Utility/Logger")

-- Services.
local runService = game:GetService("RunService")
local players = game:GetService("Players")
local physicsService = game:GetService("PhysicsService")

-- Collision group name using our unique table.
local collisionGroupName = tostring(Exploits)

-- Maids.
local exploitsMaid = Maid.new()
local pathfindBreakerMaid = Maid.new()
local invisibilityMaid = Maid.new()

-- Original stores.
local allowSleep = voidMaid:mark(OriginalStore.new())

---@type OriginalStoreManager
local invisibilityMap = invisibilityMaid:mark(OriginalStoreManager.new())

-- Signals.
local heartbeat = Signal.new(runService.Heartbeat)
local preRender = Signal.new(runService.PreRender)

-- Last velocity before breaker modification.
local lastVelocity = nil

-- State.
local invisibilityTrack = nil
local lastInvisibilityAnimator = nil

---Clean up void mobs.
local cleanVoidMobs = LPH_NO_VIRTUALIZE(function()
	voidMaid:clean()
	allowSleep:restore()
end)

---Update void mobs.
local updateVoidMobs = LPH_NO_VIRTUALIZE(function()
	local localPlayer = players.LocalPlayer

	-- Set simulation radius.
	sethiddenproperty(localPlayer, "MaxSimulationRadius", 9e9)
	sethiddenproperty(localPlayer, "SimulationRadius", 9e9)

	-- Set allow sleep.
	allowSleep:set(settings().Physics, "AllowSleep", false)

	---@type BasePart
	for part, data in next, OwnershipWatcher.parts do
		local model = data.model
		if not model then
			continue
		end

		-- Check for ownership. If we don't have it, then we need to reset what we changed during void.
		if not data.owned then
			continue
		end

		---@todo: Filtering out parts (CheckPartConnections, missing checks, etc)
		local localCharacter = localPlayer and localPlayer.Character
		if not localCharacter then
			continue
		end

		if model == localCharacter then
			continue
		end

		if model.Parent ~= workspace.Live then
			continue
		end

		---@note: Set the part to not collide.
		for _, instance in pairs(model:GetChildren()) do
			if instance:IsA("BasePart") then
				instance.CanCollide = false
			end

			local bone = instance:FindFirstChild("Bone")
			if not bone or not bone:IsA("BasePart") then
				continue
			end

			bone.CanCollide = false
		end

		voidPart(model, part)
	end
end)

---Update pathfind breaker heartbeat.
local updatePathfindBreakerHeartbeat = LPH_NO_VIRTUALIZE(function()
	local character = players.LocalPlayer.Character
	if not character then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	lastVelocity = humanoidRootPart.AssemblyLinearVelocity

	humanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, -9e9, 0)

	if not Configuration.expectToggleValue("PathfindBreakerHighlight") then
		return pathfindBreakerMaid:clean()
	end

	local highlight = InstanceWrapper.create(pathfindBreakerMaid, "PathfindBreakerHighlight", "Highlight")
	highlight.FillColor = Configuration.expectOptionValue("PathfindBreakerHighlightColor")
	highlight.OutlineColor = Configuration.expectOptionValue("PathfindBreakerHighlightOutlineColor")

	if humanoidRootPart.Parent then
		highlight.Parent = humanoidRootPart.Parent
	end
end)

---Update invisibility.
local updateInvisibility = LPH_NO_VIRTUALIZE(function()
	local character = players.LocalPlayer.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local torso = character:FindFirstChild("Torso")
	if not torso then
		return
	end

	if invisibilityTrack then
		invisibilityTrack.TimePosition = 2.0
	end

	if
		(invisibilityTrack and not invisibilityTrack.IsPlaying)
		or (lastInvisibilityAnimator and not lastInvisibilityAnimator:IsDescendantOf(game))
	then
		invisibilityTrack = nil
		lastInvisibilityAnimator = nil
	end

	if invisibilityTrack then
		return
	end

	invisibilityMaid:clean()

	lastInvisibilityAnimator = animator

	for _, track in next, animator:GetPlayingAnimationTracks() do
		track:Stop()
	end

	---@type LocalScript
	local animate = character:FindFirstChild("Animate")
	if not animate then
		return
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://14820759081"

	invisibilityTrack = invisibilityMaid:mark(animator:LoadAnimation(animation))
	invisibilityTrack.Priority = Enum.AnimationPriority.Action4
	invisibilityTrack:Play()

	local animationPlayed = Signal.new(animator.AnimationPlayed)

	invisibilityMaid:add(animationPlayed:connect("Exploits_InvisibilityAnimationPlayed", function(track)
		if track == invisibilityTrack then
			return
		end

		track:Stop()
	end))
end)

---Update exploits.
local updateExploits = LPH_NO_VIRTUALIZE(function()
	local localPlayer = players.LocalPlayer
	if not localPlayer then
		return
	end

	if Configuration.expectToggleValue("VoidMobs") then
		updateVoidMobs()
	else
		cleanVoidMobs()
	end

	if Configuration.expectToggleValue("Invisibility") then
		updateInvisibility()
	else
		invisibilityMaid:clean()
		invisibilityTrack = nil
		lastInvisibilityAnimator = nil
	end

	if Configuration.expectToggleValue("PathfindBreaker") then
		updatePathfindBreakerHeartbeat()
	else
		lastVelocity = nil
		pathfindBreakerMaid:clean()
	end
end)

---Update pathfind breaker.
local updatePathfindBreakerRender = LPH_NO_VIRTUALIZE(function()
	if not lastVelocity then
		return
	end

	local character = players.LocalPlayer and players.LocalPlayer.Character
	if not character then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	humanoidRootPart.AssemblyLinearVelocity = lastVelocity
end)

---Initalize exploits.
Exploits.init = LPH_NO_VIRTUALIZE(function()
	exploitsMaid:add(heartbeat:connect("Exploits_Heartbeat", updateExploits))
	exploitsMaid:add(preRender:connect("Exploits_PreRender", updatePathfindBreakerRender))

	---@note: Wrapped in a PCall to prevent errors.
	pcall(function()
		physicsService:RegisterCollisionGroup(collisionGroupName)
		physicsService:CollisionGroupSetCollidable(collisionGroupName, collisionGroupName, false)
		physicsService:CollisionGroupSetCollidable(collisionGroupName, "Default", false)
		physicsService:CollisionGroupSetCollidable(collisionGroupName, "Player", false)
		physicsService:CollisionGroupSetCollidable(collisionGroupName, "WalkThrough", false)
	end)

	-- Log.
	Logger.warn("Exploits initialized.")
end)

---Detach voidMobs.
Exploits.detach = LPH_NO_VIRTUALIZE(function()
	-- Clean.
	exploitsMaid:clean()
	voidMaid:clean()
	invisibilityMaid:clean()
	pathfindBreakerMaid:clean()

	-- Log.
	Logger.warn("Exploits detached.")
end)

-- Return Exploits module.
return Exploits

end)
__bundle_register("Features/Game/OwnershipWatcher", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Ownership data.
local clientPart = Instance.new("Part", workspace)
local clientSuccess, clientPeerId = pcall(function()
	return gethiddenproperty(clientPart, "NetworkOwnerV3")
end)

clientPart:Destroy()

---Check for network ownership.
---@param part BasePart
---@return boolean
local function hasNetworkOwnership(part)
	if getexecutorname():match("AWP") then
		return isnetworkowner(part)
	end

	if getexecutorname():match("Volcano") then
		return isnetworkowner(part)
	end

	if not clientSuccess then
		return isnetworkowner(part)
	end

	local partSuccess, partPeerId = pcall(function()
		return gethiddenproperty(part, "NetworkOwnerV3")
	end)

	if not partSuccess then
		return isnetworkowner(part)
	end

	return partPeerId == clientPeerId
end

return LPH_NO_VIRTUALIZE(function()
	-- Ownership watcher module.
	local OwnershipWatcher = { modelsToScan = {}, parts = {} }

	-- Services
	local runService = game:GetService("RunService")

	---@module Utility.Maid
	local Maid = require("Utility/Maid")

	---@module Utility.Configuration
	local Configuration = require("Utility/Configuration")

	---@module Utility.Signal
	local Signal = require("Utility/Signal")

	---@module Utility.InstanceWrapper
	local InstanceWrapper = require("Utility/InstanceWrapper")

	---@module Utility.Logger
	local Logger = require("Utility/Logger")

	-- Signals.
	local renderStepped = Signal.new(runService.RenderStepped)

	-- Maids.
	local ownershipMaid = Maid.new()

	---Clean up parts. Every model to scan has a maid linked to it.
	local function cleanParts()
		for _, maid in next, OwnershipWatcher.modelsToScan do
			maid:clean()
		end
	end

	---Add entity characters to ownership watcher.
	---@param character Model
	local function onEntitiesAdded(character)
		if not character:IsA("Model") then
			return
		end

		if OwnershipWatcher.modelsToScan[character] then
			return
		end

		OwnershipWatcher.modelsToScan[character] = Maid.new()
	end

	---Remove entity characters from ownership watcher.
	---@param character Model
	local function onEntitiesRemoved(character)
		if not OwnershipWatcher.modelsToScan[character] then
			return
		end

		OwnershipWatcher.modelsToScan[character]:clean()
		OwnershipWatcher.modelsToScan[character] = nil
	end

	---Update ownership.
	local function updateOwnership()
		---@optimization: Stop updating when we don't need it.
		if not Configuration.expectToggleValue("ShowOwnership") and not Configuration.expectToggleValue("VoidMobs") then
			return cleanParts()
		end

		-- Create an update table.
		local updateTable = {}

		-- Add models.
		for model, maid in next, OwnershipWatcher.modelsToScan do
			local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
			if not humanoidRootPart then
				continue
			end

			-- Check if owner.
			local isNetworkOwner = hasNetworkOwnership(humanoidRootPart)

			-- Visualization.
			local netVisual = InstanceWrapper.create(maid, "NetworkVisual", "Part", model)
			netVisual.Size = Vector3.new(10, 10, 10)
			netVisual.Transparency = Configuration.expectToggleValue("ShowOwnership") and 0.8 or 1.0
			netVisual.Color = isNetworkOwner and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
			netVisual.CFrame = humanoidRootPart.CFrame
			netVisual.Anchored = true
			netVisual.CanCollide = false

			-- Part data.
			local data = OwnershipWatcher.parts[humanoidRootPart]
				or {
					owned = isNetworkOwner,
					model = model,
				}

			-- Update part data.
			data.owned = isNetworkOwner
			data.model = model

			-- Set in global part list.
			OwnershipWatcher.parts[humanoidRootPart] = data

			-- Set in map.
			updateTable[humanoidRootPart] = data
		end

		-- Override global part list with the new update table.
		---@note: This will get rid of any parts that were not updated (e.g no longer existing root part or not in model list) upon cycle.
		---@todo: Fix me - this is a bit of a hack.
		OwnershipWatcher.parts = updateTable
	end

	---Get table of watched parts along with a mapping to extra data.
	---@return table<BasePart, table>
	function OwnershipWatcher.get()
		return OwnershipWatcher.parts
	end

	---Initialize OwnershipWatcher module.
	function OwnershipWatcher.init()
		local entities = workspace:WaitForChild("Entities")
		local entitiesChildAdded = Signal.new(entities.ChildAdded)
		local entitiesChildRemoved = Signal.new(entities.ChildRemoved)

		ownershipMaid:add(entitiesChildAdded:connect("OwnershipWatcher_OnEntitiesChildAdded", onEntitiesAdded))
		ownershipMaid:add(entitiesChildRemoved:connect("OwnershipWatcher_OnEntitiesChildRemoved", onEntitiesRemoved))
		ownershipMaid:add(renderStepped:connect("OwnershipWatcher_RenderStepped", updateOwnership))

		for _, entity in next, entities:GetChildren() do
			onEntitiesAdded(entity)
		end

		Logger.warn("OwnershipWatcher initialized.")
	end

	---Detach OwnershipWatcher module.
	function OwnershipWatcher.detach()
		-- Clean up ownership maids.
		ownershipMaid:clean()

		-- Clean up parts.
		cleanParts()

		-- Log.
		Logger.warn("OwnershipWatcher detached.")
	end

	-- Return OwnershipWatcher module.
	return OwnershipWatcher
end)()

end)
__bundle_register("Utility/InstanceWrapper", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Instance wrapper module - used for continously updating functions that require instances.
local InstanceWrapper = {}

-- Services.
local collectionService = game:GetService("CollectionService")
local tweenService = game:GetService("TweenService")

---@module Utility.Signal
local Signal = require("Utility/Signal")

---Add an instance to the cache, clean the instance up through maid, and automatically uncache on deletion.
---@param instanceMaid Maid
---@param identifier string
InstanceWrapper.tween = LPH_NO_VIRTUALIZE(function(instanceMaid, identifier, ...)
	local maidInstance = instanceMaid[identifier]
	if maidInstance then
		return maidInstance
	end

	local instance = tweenService:Create(...)
	local onAncestorChange = Signal.new(instance.AncestryChanged)

	instanceMaid[identifier] = instance
	instanceMaid:add(onAncestorChange:connect("SerenityInstance_OnAncestorChange", function(_)
		if instance:IsDescendantOf(game) then
			return
		end

		instanceMaid:removeTask(identifier)
	end))

	return instance
end)

---Cache an instance, clean the instance up through a maid, and automatically uncache on deletion.
---@param instanceMaid Maid
---@param identifier any
---@param inst Instance
---@return Instance
InstanceWrapper.mark = LPH_NO_VIRTUALIZE(function(instanceMaid, identifier, inst)
	local maidInstance = instanceMaid[identifier]
	if maidInstance then
		return maidInstance
	end

	local onAncestorChange = Signal.new(inst.AncestryChanged)

	if inst:IsA("BodyVelocity") then
		collectionService:AddTag(inst, "AllowedBM")
	end

	instanceMaid[identifier] = inst
	instanceMaid:add(onAncestorChange:connect("SerenityInstance_OnAncestorChange", function(_)
		if inst:IsDescendantOf(game) then
			return
		end

		instanceMaid:removeTask(identifier)
	end))

	return inst
end)

---Create & cache an instance, clean the instance up through a maid, and automatically uncache on deletion.
---@param instanceMaid Maid
---@param identifier any
---@param type string
---@param parent Instance?
---@return Instance
InstanceWrapper.create = LPH_NO_VIRTUALIZE(function(instanceMaid, identifier, type, parent)
	local maidInstance = instanceMaid[identifier]
	if maidInstance then
		return maidInstance
	end

	local newInstance = Instance.new(type, parent)
	local onAncestorChange = Signal.new(newInstance.AncestryChanged)

	if newInstance:IsA("BodyVelocity") then
		collectionService:AddTag(newInstance, "AllowedBM")
	end

	instanceMaid[identifier] = newInstance
	instanceMaid:add(onAncestorChange:connect("SerenityInstance_OnAncestorChange", function(_)
		if newInstance:IsDescendantOf(game) then
			return
		end

		instanceMaid:removeTask(identifier)
	end))

	return newInstance
end)

-- Return InstanceWrapper module
return InstanceWrapper

end)
__bundle_register("Features/Game/Monitoring", function(require, _LOADED, __bundle_register, __bundle_modules)
return LPH_NO_VIRTUALIZE(function()
	---@module Utility.Maid
	local Maid = require("Utility/Maid")

	---@module Utility.Signal
	local Signal = require("Utility/Signal")

	---@module Utility.Configuration
	local Configuration = require("Utility/Configuration")

	---@module Utility.CoreGuiManager
	local CoreGuiManager = require("Utility/CoreGuiManager")

	---@module Utility.Logger
	local Logger = require("Utility/Logger")

	---@module Utility.Entitites
	local Entitites = require("Utility/Entitites")

	---@module Utility.OriginalStore
	local OriginalStore = require("Utility/OriginalStore")

	---@module Utility.TaskSpawner
	local TaskSpawner = require("Utility/TaskSpawner")

	-- Monitoring module.
	local Monitoring = { subject = nil, seen = {} }

	-- Services.
	local runService = game:GetService("RunService")
	local players = game:GetService("Players")

	-- Signals.
	local renderStepped = Signal.new(runService.RenderStepped)

	-- Maids.
	local monitoringMaid = Maid.new()
	local spectateMaid = Maid.new()

	-- Instances.
	local beepSound = CoreGuiManager.imark(Instance.new("Sound"))

	-- Original stores.
	local cameraSubject = spectateMaid:mark(OriginalStore.new())

	-- Update limiting.
	local lastUpdateTime = os.clock()

	---Fetch name.
	local function fetchName(player)
		return string.format("(%s) %s", player:GetAttribute("CharacterName") or "Unknown Character Name", player.Name)
	end

	---Update player proximity.
	local function updatePlayerProximity()
		local proximityRange = Configuration.expectOptionValue("PlayerProximityRange") or 350
		local playersInRange = Entitites.getPlayersInRange(proximityRange)
		if not playersInRange then
			return
		end

		local localPlayer = players.LocalPlayer
		if not localPlayer then
			return
		end

		local backpack = localPlayer:FindFirstChild("Backpack")
		if not backpack then
			return
		end

		-- Handle monitoring.
		for player, _ in next, Monitoring.seen do
			local isInPlayerRange = table.find(playersInRange, player)
			if isInPlayerRange then
				continue
			end

			local removeNotification = Monitoring.seen[player]

			removeNotification()

			Monitoring.seen[player] = nil
		end

		for _, player in next, playersInRange do
			if Monitoring.seen[player] ~= nil then
				continue
			end

			Monitoring.seen[player] =
				Logger.mnnotify("%s entered your proximity radius of %i studs.", fetchName(player), proximityRange)

			if Configuration.expectToggleValue("PlayerProximityBeep") then
				beepSound.SoundId = "rbxassetid://100849623977896"
				beepSound.PlaybackSpeed = 1
				beepSound.Volume = Configuration.expectOptionValue("PlayerProximityBeepVolume") or 0.1
				beepSound:Play()
			end
		end
	end

	---On spectate input began.
	---@param player Player
	---@param input InputObject
	local function onSpectateInputBegan(player, input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		-- Fetch name for player.
		local usedName = fetchName(player)

		-- Get data.
		local localPlayer = players.LocalPlayer
		if not localPlayer then
			return Logger.notify("Failed to spectate '%s' because the local player does not exist.", usedName)
		end

		local character = player.Character
		if not character then
			return Logger.notify("Failed to spectate '%s' because their character does not exist.", usedName)
		end

		local mapPosition = character:GetAttribute("MapPos")
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

		-- Request a stream if we're able to and we know that they're not loaded in.
		if mapPosition and not humanoidRootPart then
			spectateMaid:add(
				TaskSpawner.spawn(
					"Monitoring_RequestStreamMapPos",
					players.LocalPlayer.RequestStreamAroundAsync,
					players.LocalPlayer,
					mapPosition,
					0.1
				)
			)

			return Logger.notify("Requesting stream for unloaded character '%s' - try again later.", usedName)
		end

		-- Fail because they're *truly* not loaded in.
		if not humanoidRootPart then
			return Logger.notify("Failed to spectate '%s' because they are not loaded in.", usedName)
		end

		local shouldUpdateSubject = Monitoring.subject ~= humanoidRootPart and players.LocalPlayer ~= player

		Monitoring.subject = shouldUpdateSubject and humanoidRootPart or nil

		if shouldUpdateSubject then
			Logger.notify("Started spectating player %s.", usedName)
		else
			Logger.notify("Reset spectating camera subject.")
		end
	end

	---Update spectating.
	local function updateSpectating()
		local localPlayer = players.LocalPlayer
		local playerGui = localPlayer and localPlayer.PlayerGui
		local leaderBoard = playerGui and playerGui:FindFirstChild("Leaderboard")
		local list = leaderBoard and leaderBoard:FindFirstChild("List")
		local container = list and list:FindFirstChild("Container")
		if not container then
			return
		end

		local leaderboardMap = {}

		for _, instance in next, container:GetChildren() do
			local player = players:FindFirstChild(instance.Name)
			if not player then
				continue
			end

			leaderboardMap[player] = instance
		end

		-- Update leaderboard based on state.
		for player, frame in next, leaderboardMap do
			local inputBegan = Signal.new(frame.InputBegan)
			local label = string.format("Monitoring_InputBegan%s", player.Name)

			if spectateMaid[frame] then
				continue
			end

			spectateMaid[frame] = inputBegan:connect(label, function(input)
				onSpectateInputBegan(player, input)
			end)
		end
	end

	---Update subject montioring.
	local function updateSubjectMonitoring()
		-- Set camera subject.
		cameraSubject:set(workspace.CurrentCamera, "CameraSubject", Monitoring.subject)

		-- Request stream.
		spectateMaid:add(
			TaskSpawner.spawn(
				"Monitoring_RequestStreamSpectate",
				players.LocalPlayer.RequestStreamAroundAsync,
				players.LocalPlayer,
				Monitoring.subject.Position,
				0.1
			)
		)
	end

	---Update monitoring.
	local function updateMonitoring()
		if Monitoring.subject then
			updateSubjectMonitoring()
		else
			cameraSubject:restore()
		end

		if os.clock() - lastUpdateTime <= 2.0 then
			return
		end

		lastUpdateTime = os.clock()

		if Configuration.expectToggleValue("PlayerSpectating") then
			updateSpectating()
		else
			spectateMaid:clean()
		end

		if Configuration.expectToggleValue("PlayerProximity") then
			updatePlayerProximity()
		end
	end

	---Initialize monitoring.
	function Monitoring.init()
		-- Attach.
		monitoringMaid:add(renderStepped:connect("Monitoring_OnRenderStepped", updateMonitoring))

		-- Log.
		Logger.warn("Monitoring initialized.")
	end

	---Detach spectating.
	function Monitoring.detach()
		-- Clean.
		monitoringMaid:clean()

		-- Log.
		Logger.warn("Monitoring detached.")
	end

	-- Return Monitoring module.
	return Monitoring
end)()

end)
__bundle_register("Utility/Entitites", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Entity utility is handled here.
local Entitites = {}

-- Services.
local players = game:GetService("Players")

---Is a player within 200 studs of the specified position?
---@param position Vector3
---@return Player|nil
Entitites.isNear = LPH_NO_VIRTUALIZE(function(position)
	for _, player in next, players:GetPlayers() do
		if player == players.LocalPlayer then
			continue
		end

		local character = player.Character
		if not character then
			continue
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			continue
		end

		if (position - rootPart.Position).Magnitude > 200 then
			continue
		end

		return player
	end

	return nil
end)

---Find an entity by its name.
---@param name string The name of the entity to find. It is matched.
---@return Model?
Entitites.fe = LPH_NO_VIRTUALIZE(function(name)
	local entities = workspace:FindFirstChild("Entities")
	if not entities then
		return nil
	end

	for _, child in next, entities:GetChildren() do
		if not child.Name:match(name) then
			continue
		end

		return child
	end
end)

---This function is sorted from the nearest to the farthest player.
---Get players within a certain range in studs from the local player.
---@param range number
---@return Player[]
Entitites.getPlayersInRange = LPH_NO_VIRTUALIZE(function(range)
	local localCharacter = players.LocalPlayer.Character
	local localRootPart = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
	if not localRootPart then
		return
	end

	local playersInRange = {}
	local playersDistance = {}

	for _, player in next, players:GetPlayers() do
		if player == players.LocalPlayer then
			continue
		end

		local character = player.Character
		if not character then
			continue
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			continue
		end

		local playerDistance = (rootPart.Position - localRootPart.Position).Magnitude
		if playerDistance > range then
			continue
		end

		table.insert(playersInRange, player)

		playersDistance[player] = playerDistance
	end

	table.sort(playersInRange, function(playerOne, playerTwo)
		return playersDistance[playerOne] < playersDistance[playerTwo]
	end)

	return playersInRange
end)

---This function is sorted from the nearest to the farthest mob.
---Get mobs within a certain range in studs from the local player.
---@param range number
---@return Model[]
Entitites.getMobsInRange = LPH_NO_VIRTUALIZE(function(range)
	local entities = workspace:FindFirstChild("Entities")
	if not entities then
		return
	end

	local localCharacter = players.LocalPlayer.Character
	local localRootPart = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
	if not localRootPart then
		return
	end

	local mobsInRange = {}
	local mobsDistance = {}

	for _, entity in next, entities:GetChildren() do
		if entity == localCharacter then
			continue
		end

		if players:GetPlayerFromCharacter(entity) then
			continue
		end

		local rootPart = entity:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			continue
		end

		local mobDistance = (rootPart.Position - localRootPart.Position).Magnitude
		if mobDistance > range then
			continue
		end

		table.insert(mobsInRange, entity)

		mobsDistance[entity] = mobDistance
	end

	table.sort(mobsInRange, function(mobOne, mobTwo)
		return mobsDistance[mobOne] < mobsDistance[mobTwo]
	end)

	return mobsInRange
end)

---This function is sorted from the nearest to the farthest entity.
---Get entity within a certain range in studs from the local player.
---@param range number
---@return Model[]
Entitites.getEntitiesInRange = LPH_NO_VIRTUALIZE(function(range)
	local entities = workspace:FindFirstChild("Entities")
	if not entities then
		return
	end

	local localCharacter = players.LocalPlayer.Character
	local localRootPart = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
	if not localRootPart then
		return
	end

	local entitiesInRange = {}
	local entitiesDistance = {}

	for _, entity in next, entities:GetChildren() do
		if entity == localCharacter then
			continue
		end

		local rootPart = entity:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			continue
		end

		local entityDistance = (rootPart.Position - localRootPart.Position).Magnitude
		if entityDistance > range then
			continue
		end

		table.insert(entitiesInRange, entity)

		entitiesDistance[entity] = entityDistance
	end

	table.sort(entitiesInRange, function(mobOne, mobTwo)
		return entitiesDistance[mobOne] < entitiesDistance[mobTwo]
	end)

	return entitiesInRange
end)

---Get the nearest entity to the local player.
---@param range number
---@return Model?
Entitites.findNearestEntity = LPH_NO_VIRTUALIZE(function(range)
	return Entitites.getEntitiesInRange(range or math.huge)[1]
end)

---Get the nearest mob to the local player.
---@param range number
---@return Model?
Entitites.findNearestMob = LPH_NO_VIRTUALIZE(function(range)
	return Entitites.getMobsInRange(range or math.huge)[1]
end)

-- Return Entitites module.
return Entitites

end)
__bundle_register("Features/Game/AnimationVisualizer", function(require, _LOADED, __bundle_register, __bundle_modules)
return LPH_NO_VIRTUALIZE(function()
	-- Animation visualizer module.
	---@note: This code is UI code. It is ugly on purpose and lazily made.
	local AnimationVisualizer = {}

	---@module Utility.Signal
	local Signal = require("Utility/Signal")

	---@module Utility.Maid
	local Maid = require("Utility/Maid")

	---@module GUI.Library
	local Library = require("GUI/Library")

	---@module Utility.CoreGuiManager
	local CoreGuiManager = require("Utility/CoreGuiManager")

	-- Visualizer maid.
	local visualizerMaid = Maid.new()

	-- Services.
	local runService = game:GetService("RunService")
	local userInputService = game:GetService("UserInputService")
	local players = game:GetService("Players")

	local screenGui = CoreGuiManager.imark(Instance.new("ScreenGui"))
	screenGui.Name = "ScreenGui"
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false

	local outer = Instance.new("Frame")
	outer.Name = "Outer"
	outer.BackgroundColor3 = Color3.new(1, 1, 1)
	outer.Position = UDim2.new(0.27, 0, 0.216, 0)
	outer.BorderColor3 = Color3.new()
	outer.Size = UDim2.new(0, 260, 0, 301.75)
	outer.ZIndex = 100
	outer.Parent = screenGui

	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.BackgroundColor3 = Library.MainColor
	inner.BorderMode = Enum.BorderMode.Inset
	inner.BorderColor3 = Library.OutlineColor
	inner.Size = UDim2.new(1, 0, 1, 0)
	inner.Parent = outer

	local animationVisualizer = Instance.new("TextLabel")
	animationVisualizer.Name = "AnimationVisualizer"
	animationVisualizer.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
	animationVisualizer.TextColor3 = Library.AccentColor
	animationVisualizer.Text = "Animation Visualizer"
	animationVisualizer.BackgroundColor3 = Color3.new()
	animationVisualizer.BorderSizePixel = 0
	animationVisualizer.BackgroundTransparency = 1
	animationVisualizer.Position = UDim2.new(0, 5, 0, 5)
	animationVisualizer.TextXAlignment = Enum.TextXAlignment.Left
	animationVisualizer.BorderColor3 = Color3.new()
	animationVisualizer.TextSize = 17
	animationVisualizer.Size = UDim2.new(1, 0, 0, 20)
	animationVisualizer.Parent = inner

	local sliderOuter = Instance.new("Frame")
	sliderOuter.Name = "SliderOuter"
	sliderOuter.BackgroundColor3 = Color3.new(1, 1, 1)
	sliderOuter.Position = UDim2.new(0.323, -78, 0.835, 24)
	sliderOuter.BorderColor3 = Color3.new()
	sliderOuter.BorderSizePixel = 0
	sliderOuter.Size = UDim2.new(0, 247, 0, 15)
	sliderOuter.Parent = inner

	local sliderText = Instance.new("TextLabel")
	sliderText.Name = "SliderText"
	sliderText.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
	sliderText.TextColor3 = Library.FontColor
	sliderText.Text = "0.000 / ? (?ms)"
	sliderText.BackgroundTransparency = 1
	sliderText.BackgroundColor3 = Color3.new(1, 1, 1)
	sliderText.BorderSizePixel = 0
	sliderText.BorderColor3 = Color3.new()
	sliderText.TextSize = 12
	sliderText.ZIndex = 12
	sliderText.Size = UDim2.new(1, 0, 1, 0)
	sliderText.Parent = sliderOuter

	local sliderFill = Instance.new("Frame")
	sliderFill.Name = "SliderFill"
	sliderFill.BorderMode = Enum.BorderMode.Inset
	sliderFill.BorderColor3 = Library.AccentColorDark
	sliderFill.BackgroundColor3 = Library.AccentColor
	sliderFill.Size = UDim2.new(0, 1, 1, 0)
	sliderFill.ZIndex = 10
	sliderFill.Parent = sliderOuter

	local hideBorderRight = Instance.new("Frame")
	hideBorderRight.Name = "HideBorderRight"
	hideBorderRight.BackgroundColor3 = Library.AccentColor
	hideBorderRight.Position = UDim2.new(1, 0, 0, 0)
	hideBorderRight.BorderColor3 = Color3.new()
	hideBorderRight.BorderSizePixel = 0
	hideBorderRight.Size = UDim2.new(0, 1, 1, 0)
	hideBorderRight.Parent = sliderFill
	hideBorderRight.Visible = false

	local sliderInner = Instance.new("Frame")
	sliderInner.Name = "SliderInner"
	sliderInner.BorderColor3 = Color3.new()
	sliderInner.BackgroundColor3 = Library.MainColor
	sliderInner.Size = UDim2.new(1, 0, 1, 0)
	sliderInner.Parent = sliderOuter

	local frameBackwards = Instance.new("TextButton")
	frameBackwards.Name = "FrameBackwards"
	frameBackwards.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
	frameBackwards.TextColor3 = Color3.new()
	frameBackwards.Text = ""
	frameBackwards.Position = UDim2.new(0.323, -78, 0.835, -2)
	frameBackwards.BackgroundColor3 = Library.MainColor
	frameBackwards.BorderColor3 = Color3.new()
	frameBackwards.TextSize = 14
	frameBackwards.Size = UDim2.new(0, 70, 0, 20)
	frameBackwards.Parent = inner

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.ScaleType = Enum.ScaleType.Crop
	icon.BorderColor3 = Color3.new()
	icon.BackgroundColor3 = Library.FontColor
	icon.Image = "rbxassetid://10734961526"
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.new(0.5, -8, 0.5, -8)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeXX
	icon.BorderSizePixel = 0
	icon.Size = UDim2.new(0, 16, 0, 16)
	icon.Parent = frameBackwards

	local playStop = Instance.new("TextButton")
	playStop.Name = "PlayStop"
	playStop.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
	playStop.TextColor3 = Color3.new()
	playStop.BorderColor3 = Color3.new()
	playStop.Text = ""
	playStop.Position = UDim2.new(0.323, 0, 0.835, -2)
	playStop.BackgroundColor3 = Library.MainColor
	playStop.TextSize = 14
	playStop.Size = UDim2.new(0, 91, 0, 20)
	playStop.Parent = inner

	local iconTwo = Instance.new("ImageLabel")
	iconTwo.Name = "Icon"
	iconTwo.BorderColor3 = Color3.new()
	iconTwo.BackgroundColor3 = Library.FontColor
	iconTwo.Image = "rbxassetid://10734919336"
	iconTwo.BackgroundTransparency = 1
	iconTwo.Position = UDim2.new(0.5, -8, 0.5, -8)
	iconTwo.SizeConstraint = Enum.SizeConstraint.RelativeXX
	iconTwo.BorderSizePixel = 0
	iconTwo.Size = UDim2.new(0, 16, 0, 16)
	iconTwo.Parent = playStop

	local viewportFrame = Instance.new("ViewportFrame")
	viewportFrame.Name = "ViewportFrame"
	viewportFrame.Visible = false
	viewportFrame.BorderMode = Enum.BorderMode.Inset
	viewportFrame.LightColor = Color3.new(0.549, 0.525, 0.435)
	viewportFrame.Ambient = Color3.new(0.318, 0.318, 0.318)
	viewportFrame.Position = UDim2.new(0, 4, 0, 26)
	viewportFrame.BackgroundColor3 = Library.MainColor
	viewportFrame.BorderColor3 = Color3.new()
	viewportFrame.Size = UDim2.new(1, -8, 0, 195)
	viewportFrame.Parent = inner

	local worldModel = Instance.new("WorldModel", viewportFrame)

	local camera = Instance.new("Camera", viewportFrame)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70

	local speedText = Instance.new("TextLabel")
	speedText.Name = "SpeedText"
	speedText.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
	speedText.TextColor3 = Library.FontColor
	speedText.Text = "Speed (???) - Hit (???)"
	speedText.BackgroundTransparency = 1
	speedText.BackgroundColor3 = Color3.new(1, 1, 1)
	speedText.BorderSizePixel = 0
	speedText.BorderColor3 = Color3.new()
	speedText.TextSize = 12
	speedText.Position = UDim2.new(0.02, 0, 0, 0)
	speedText.TextXAlignment = Enum.TextXAlignment.Left
	speedText.Size = UDim2.new(1, 0, 0, 20)
	speedText.ZIndex = 19
	speedText.Parent = viewportFrame

	local noViewportFrame = Instance.new("Frame")
	noViewportFrame.Name = "NoViewportFrame"
	noViewportFrame.BackgroundColor3 = Library.MainColor
	noViewportFrame.Position = UDim2.new(0, 4, 0, 26)
	noViewportFrame.BorderColor3 = Color3.new()
	noViewportFrame.BorderMode = Enum.BorderMode.Inset
	noViewportFrame.Size = UDim2.new(1, -8, 0, 195)
	noViewportFrame.Parent = inner

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "TextLabel"
	textLabel.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
	textLabel.TextColor3 = Library.FontColor
	textLabel.BorderColor3 = Color3.new()
	textLabel.Text = "Waiting For Animation ID"
	textLabel.BackgroundColor3 = Color3.new(1, 1, 1)
	textLabel.BorderSizePixel = 0
	textLabel.BackgroundTransparency = 1
	textLabel.Position = UDim2.new(0.0968, 0, 0.369, 0)
	textLabel.TextWrapped = true
	textLabel.TextSize = 14
	textLabel.Size = UDim2.new(0, 200, 0, 50)
	textLabel.Parent = noViewportFrame

	local color = Instance.new("Frame")
	color.Name = "Color"
	color.BackgroundColor3 = Library.AccentColor
	color.BorderColor3 = Color3.new()
	color.BorderSizePixel = 0
	color.Size = UDim2.new(1, 0, 0, 2)
	color.Parent = inner

	local frameForwards = Instance.new("TextButton")
	frameForwards.Name = "FrameForwards"
	frameForwards.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json")
	frameForwards.TextColor3 = Color3.new()
	frameForwards.Text = ""
	frameForwards.Position = UDim2.new(0.323, 99, 0.835, -2)
	frameForwards.BackgroundColor3 = Library.MainColor
	frameForwards.BorderColor3 = Color3.new()
	frameForwards.TextSize = 14
	frameForwards.Size = UDim2.new(0, 69, 0, 20)
	frameForwards.Parent = inner

	local iconThree = Instance.new("ImageLabel")
	iconThree.Name = "Icon"
	iconThree.ScaleType = Enum.ScaleType.Crop
	iconThree.BorderColor3 = Color3.new()
	iconThree.BackgroundColor3 = Library.FontColor
	iconThree.Image = "rbxassetid://10734961809"
	iconThree.BackgroundTransparency = 1
	iconThree.Position = UDim2.new(0.5, -8, 0.5, -8)
	iconThree.SizeConstraint = Enum.SizeConstraint.RelativeXX
	iconThree.BorderSizePixel = 0
	iconThree.Size = UDim2.new(0, 16, 0, 16)
	iconThree.Parent = frameForwards

	local animationTextbox = Instance.new("TextBox")
	animationTextbox.Name = "AnimationTextbox"
	animationTextbox.CursorPosition = -1
	animationTextbox.TextColor3 = Library.FontColor
	animationTextbox.Text = "rbxassetid://0"
	animationTextbox.BackgroundColor3 = Library.MainColor
	animationTextbox.Position = UDim2.new(0.323, -78, 0.835, -24)
	animationTextbox.BorderColor3 = Color3.new()
	animationTextbox.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
	animationTextbox.TextSize = 14
	animationTextbox.Size = UDim2.new(0, 246, 0, 15)
	animationTextbox.Parent = inner

	-- Current data for playback loop.
	local currentTrack = nil
	local isPaused = false
	local timeElapsed = 0.0
	local isInitialized = false

	---Map slider value.
	---@param value number
	---@param min number
	---@param max number
	---@param minSize number
	---@param maxSize number
	local function mapSliderValue(value, min, max, minSize, maxSize)
		return (1 - ((value - min) / (max - min))) * minSize + ((value - min) / (max - min)) * maxSize
	end

	---On Animation ID focus lost.
	---@param enter boolean
	---@param _ InputObject
	local function onIdFocusLost(enter, _)
		if not enter then
			return
		end

		-- Empty out previous data.
		currentTrack = nil

		-- Get the local player's character as the entity.
		local character = players.LocalPlayer and players.LocalPlayer.Character
		if not character then
			return AnimationVisualizer.message("No Character Found")
		end

		-- Remove all previously loaded models.
		for _, descendant in next, viewportFrame:GetDescendants() do
			if descendant.ClassName ~= "Model" then
				continue
			end

			descendant:Destroy()
		end

		-- Archivable.
		character.Archivable = true

		-- Load the model & center it.
		local entity = character:Clone()
		if not entity then
			return AnimationVisualizer.message("Failed To Clone Entity")
		end

		entity.Parent = worldModel
		entity:PivotTo(CFrame.new(0, 0, 0))

		-- Fetch the primary part. If it does not exist, then the entity has been unloaded.
		if not entity.PrimaryPart then
			return AnimationVisualizer.message("No Primary Part Found")
		end

		-- Setup camera.
		local _, bbs = entity:GetBoundingBox()
		camera.CFrame =
			CFrame.lookAt(entity.PrimaryPart.Position - Vector3.new(0, 0, bbs.Magnitude), entity.PrimaryPart.Position)

		-- Fetch animator.
		local animator = entity:FindFirstChildWhichIsA("Animator", true)
		if not animator then
			return AnimationVisualizer.message("No Animator Found")
		end

		-- Stop previous animations.
		for _, track in next, animator:GetPlayingAnimationTracks() do
			track:Stop()
		end

		-- Create animation.
		local animation = Instance.new("Animation")
		animation.AnimationId = animationTextbox.Text

		-- Store current track for playback.
		currentTrack = animator:LoadAnimation(animation)

		-- Play animation and keep it at zero speed.
		currentTrack:Play(0.0, 100, 0.0)
		currentTrack.Priority = Enum.AnimationPriority.Action
		currentTrack.Looped = true
		visualizerMaid:mark(currentTrack.DidLoop:Connect(function()
			timeElapsed = 0.0
		end))

		-- Reset time elapsed.
		timeElapsed = 0.0

		-- Show frames.
		viewportFrame.Visible = true
		noViewportFrame.Visible = false
	end

	---Get time elapsed from time position.
	---@param timePosition number
	---@param animationLength number
	---@return number?
	local function getTimeElapsedFromTp(timePosition, animationLength)
		if timePosition <= 0 then
			return 0.0
		end

		-- At constant speed 1.0, elapsed time equals time position.
		return timePosition
	end

	---On playback loop.
	---@param delta number
	local function onPlaybackLoop(delta)
		if not screenGui.Enabled then
			return
		end

		iconTwo.Image = isPaused and "rbxassetid://10734923549" or "rbxassetid://10734919336"

		-- Run slider calculations.
		local mhs = sliderOuter.AbsoluteSize.X
		local hs = currentTrack and mapSliderValue(currentTrack.TimePosition, 0.0, currentTrack.Length, 0, mhs) or 0.0

		-- Update slider text.
		sliderText.Text = currentTrack
				and string.format(
					"%.3f/%.3f (%ims)",
					currentTrack.TimePosition,
					currentTrack.Length,
					math.round((getTimeElapsedFromTp(currentTrack.TimePosition, currentTrack.Length) or 0.0) * 1000)
				)
			or "0.000 / ??? (???ms)"

		-- Update size.
		sliderFill.Visible = not (hs == 0)
		sliderFill.Size = UDim2.new(0, math.max(math.ceil(hs), 1), 1, 0)
		hideBorderRight.Visible = not (hs == mhs or hs == 0)

		-- Update speed amount.
		speedText.Text = currentTrack and string.format("Speed (%.2f) - Hit (???)", currentTrack.Speed)
			or "Speed (???) - Hit (???)"

		if currentTrack then
			local success, kf = pcall(currentTrack.GetTimeOfKeyframe, currentTrack, "HitFrame")

			if not success and not kf then
				success, kf = pcall(currentTrack.GetTimeOfKeyframe, currentTrack, "HitFrameStart")
			end

			if success and kf then
				speedText.Text = string.format("Speed (%.2f) - Hit (%.2f)", currentTrack.Speed, kf)
			end
		end

		if not currentTrack then
			return
		end

		if isPaused then
			return currentTrack:AdjustSpeed(0.0)
		end

		timeElapsed = timeElapsed + delta

		currentTrack:AdjustSpeed(1.0)
	end

	---Toggle play stop function.
	local function togglePlayStop()
		if not currentTrack then
			return
		end

		if not currentTrack.IsPlaying then
			return
		end

		isPaused = not isPaused
	end

	---Go backwards one frame.
	local function onFrameBackwards()
		if not currentTrack then
			return
		end

		currentTrack.TimePosition = math.max(currentTrack.TimePosition - 0.01, 0)
	end

	---Go forwards one frame.
	local function onFrameForwards()
		if not currentTrack then
			return
		end

		currentTrack.TimePosition = math.min(currentTrack.TimePosition + 0.01, currentTrack.Length)
	end

	---On slider input began.
	---@param input InputObject
	---@param gameProcessed boolean
	local function onSliderInputBegan(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		while screenGui.Enabled and userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
			if not currentTrack then
				return
			end

			-- Pause track.
			isPaused = true

			-- Calculate new time position.
			local mouse = players.LocalPlayer:GetMouse()
			local sliderOuterSize = sliderOuter.AbsoluteSize.X
			local mouseX = math.clamp(mouse.X - sliderOuter.AbsolutePosition.X, 0, sliderOuterSize)
			local newTimePosition = mapSliderValue(mouseX, 0, sliderOuterSize, 0, currentTrack.Length)

			-- Update time position.
			currentTrack.TimePosition = newTimePosition

			-- Wait.
			runService.PreRender:Wait()
		end

		timeElapsed = getTimeElapsedFromTp(currentTrack.TimePosition, currentTrack.Length) or 0.0
	end

	---Outer input began.
	---@param input InputObject
	---@param gameProcessed boolean
	local function outerFrameInputBegan(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.KeyCode == Enum.KeyCode.Space then
			return togglePlayStop()
		end

		if input.KeyCode == Enum.KeyCode.Right then
			return onFrameForwards()
		end

		if input.KeyCode == Enum.KeyCode.Left then
			return onFrameBackwards()
		end
	end

	---Load an animation ID into the visualizer and begin playback.
	---@param aid string Full animation asset ID (e.g. "rbxassetid://123456").
	function AnimationVisualizer.loadId(aid)
		AnimationVisualizer.visible(true)
		animationTextbox.Text = aid
		onIdFocusLost(true, nil)
	end

	---Set the visibility of the AnimationVisualizer.
	---@param state boolean
	function AnimationVisualizer.visible(state)
		if state and not isInitialized then
			local ok, err = pcall(AnimationVisualizer.init)

			if not ok then
				screenGui.Enabled = true
				return AnimationVisualizer.message("Visualizer Init Failed: " .. tostring(err))
			end
		end

		screenGui.Enabled = state
	end

	---Show a message.
	---@param message string
	function AnimationVisualizer.message(message)
		viewportFrame.Visible = false
		noViewportFrame.Visible = true
		textLabel.Text = message
	end

	---Initialize AnimationVisualizer module.
	function AnimationVisualizer.init()
		if isInitialized then
			return
		end

		-- Initialize GUI.
		screenGui.Name = "AnimationVisualizer"
		screenGui.Enabled = false
		screenGui.DisplayOrder = 1

		-- Make draggable.
		Library:MakeDraggable(outer)

		-- Setup colors.
		Library:AddToRegistry(color, {
			BackgroundColor3 = "AccentColor",
		}, true)

		Library:AddToRegistry(animationVisualizer, {
			TextColor3 = "AccentColor",
		}, true)

		Library:AddToRegistry(hideBorderRight, {
			BackgroundColor3 = "AccentColor",
		}, true)

		Library:AddToRegistry(sliderFill, {
			BackgroundColor3 = "AccentColor",
		}, true)

		Library:AddToRegistry(inner, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "OutlineColor",
		}, true)

		Library:AddToRegistry(playStop, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "Black",
		}, true)

		Library:AddToRegistry(animationTextbox, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "Black",
			TextColor3 = "FontColor",
		}, true)

		Library:AddToRegistry(icon, {
			ImageColor3 = "FontColor",
		}, true)

		Library:AddToRegistry(iconTwo, {
			ImageColor3 = "FontColor",
		}, true)

		Library:AddToRegistry(iconThree, {
			ImageColor3 = "FontColor",
		}, true)

		Library:AddToRegistry(textLabel, {
			TextColor3 = "FontColor",
		}, true)

		Library:AddToRegistry(speedText, {
			TextColor3 = "FontColor",
		}, true)

		Library:AddToRegistry(noViewportFrame, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "Black",
		}, true)

		Library:AddToRegistry(frameBackwards, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "Black",
		}, true)

		Library:AddToRegistry(frameForwards, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "Black",
		}, true)

		Library:AddToRegistry(viewportFrame, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "Black",
		}, true)

		Library:AddToRegistry(sliderOuter, {
			BorderColor3 = "Black",
		}, true)

		Library:AddToRegistry(sliderInner, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "Black",
		}, true)

		Library:AddToRegistry(sliderFill, {
			BackgroundColor3 = "AccentColor",
			BorderColor3 = "AccentColorDark",
		}, true)

		Library:AddToRegistry(hideBorderRight, {
			BackgroundColor3 = "AccentColor",
		}, true)

		Library:AddToRegistry(sliderText, {
			TextColor3 = "FontColor",
		}, true)

		-- Setup camera.
		viewportFrame.CurrentCamera = camera

		-- Setup intro scene.
		AnimationVisualizer.message("Waiting For Animation ID")

		-- Setup signals.
		local idFocusLost = Signal.new(animationTextbox.FocusLost)
		local preRender = Signal.new(runService.PreRender)
		local playStopClicked = Signal.new(playStop.MouseButton1Click)
		local outerInputBegan = Signal.new(outer.InputBegan)
		local frameBackwardsClick = Signal.new(frameBackwards.MouseButton1Click)
		local frameForwardsClick = Signal.new(frameForwards.MouseButton1Click)
		local sliderInputBegan = Signal.new(sliderOuter.InputBegan)

		visualizerMaid:add(sliderInputBegan:connect("AnimationVisualizer_SliderInputBegan", onSliderInputBegan))
		visualizerMaid:add(frameForwardsClick:connect("AnimationVisualizer_FrameForwardsClick", onFrameForwards))
		visualizerMaid:add(frameBackwardsClick:connect("AnimationVisualizer_FrameBackwardsClick", onFrameBackwards))
		visualizerMaid:add(outerInputBegan:connect("AnimationVisualizer_OuterInputBegan", outerFrameInputBegan))
		visualizerMaid:add(playStopClicked:connect("AnimationVisualizer_PlayStopClicked", togglePlayStop))
		visualizerMaid:add(preRender:connect("AnimationVisualizer_PlaybackLoop", onPlaybackLoop))
		visualizerMaid:add(idFocusLost:connect("AnimationVisualizer_IdFocusLost", onIdFocusLost))

		-- Add outer frame to library.
		Library.AnimationVisualizerFrame = outer
		isInitialized = true
	end

	---Detach AnimationVisualizer module.
	function AnimationVisualizer.detach()
		visualizerMaid:clean()
		isInitialized = false
	end

	-- Return AnimationVisualizer module.
	return AnimationVisualizer
end)()

end)
__bundle_register("Features/Visuals/Visuals", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Features.Visuals.Objects.ModelESP
local ModelESP = require("Features/Visuals/Objects/ModelESP")

---@module Features.Visuals.Objects.PartESP
local PartESP = require("Features/Visuals/Objects/PartESP")

---@module Features.Visuals.Objects.MobESP
local MobESP = require("Features/Visuals/Objects/MobESP")

---@module Features.Visuals.Objects.PlayerESP
local PlayerESP = require("Features/Visuals/Objects/PlayerESP")

---@module Utility.OriginalStoreManager
local OriginalStoreManager = require("Utility/OriginalStoreManager")

---@module Features.Visuals.Group
local Group = require("Features/Visuals/Group")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Utility.OriginalStore
local OriginalStore = require("Utility/OriginalStore")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Utility.Profiler
local Profiler = require("Utility/Profiler")

-- Visuals module.
local Visuals = { currentBuilderData = nil }

-- Services.
local runService = game:GetService("RunService")
local players = game:GetService("Players")
local textChatService = game:GetService("TextChatService")
local lighting = game:GetService("Lighting")

-- Signals.
local renderStepped = Signal.new(runService.RenderStepped)

-- Maids.
local visualsMaid = Maid.new()

-- Last visuals update.
local lastVisualsUpdate = os.clock()

-- Original stores.
local fieldOfView = visualsMaid:mark(OriginalStore.new())

-- Original store managers.
local showRobloxChatMap = visualsMaid:mark(OriginalStoreManager.new())
local ambienceMap = visualsMaid:mark(OriginalStoreManager.new())

-- Groups.
local groups = {}

---Update show roblox chat.
local updateShowRobloxChat = LPH_NO_VIRTUALIZE(function()
	local localPlayer = players.LocalPlayer
	if not localPlayer then
		return
	end

	local playerGui = localPlayer.PlayerGui
	if not playerGui then
		return
	end

	local chatWindowConfiguration = textChatService:FindFirstChild("ChatWindowConfiguration")
	if not chatWindowConfiguration then
		return
	end

	showRobloxChatMap:add(chatWindowConfiguration, "Enabled", true)

	---@note: Probably set a proper restore for this?
	--- But, in Deepwoken, users cannot realisitically access the Roblox chat anyway.
	textChatService.OnIncomingMessage = function(message)
		local source = message.TextSource
		if not source then
			return
		end

		local player = players:GetPlayerByUserId(source.UserId)
		if not player then
			return
		end

		message.PrefixText = string.gsub(message.PrefixText, player.DisplayName, player.Name)
		message.PrefixText = string.format(
			"(%s) %s",
			player:GetAttribute("CharacterName") or "Unknown Character Name",
			message.PrefixText
		)
	end
end)

---Modify ambience color.
---@param value Color3
local modifyAmbienceColor = LPH_NO_VIRTUALIZE(function(value)
	local ambienceColor = Configuration.expectOptionValue("AmbienceColor")
	local shouldUseOriginalAmbienceColor = Configuration.expectToggleValue("OriginalAmbienceColor")

	if not shouldUseOriginalAmbienceColor and ambienceColor then
		return ambienceColor
	end

	local brightness = Configuration.expectOptionValue("OriginalAmbienceColorBrightness") or 0.0
	local red, green, blue = value.R, value.G, value.B

	red = math.min(red + brightness, 255)
	green = math.min(green + brightness, 255)
	blue = math.min(blue + brightness, 255)

	return Color3.fromRGB(red, green, blue)
end)

---Update ambience.
local updateAmbience = LPH_NO_VIRTUALIZE(function()
	local store = ambienceMap:get(lighting)
	local value = store and store:get() or lighting.Ambient
	ambienceMap:add(lighting, "Ambient", modifyAmbienceColor(value))
end)

---Update visuals.
local updateVisuals = LPH_NO_VIRTUALIZE(function()
	for _, group in next, groups do
		group:update()
	end

	if os.clock() - lastVisualsUpdate <= 1.0 then
		return
	end

	lastVisualsUpdate = os.clock()

	if Configuration.expectToggleValue("ModifyFieldOfView") then
		fieldOfView:set(workspace.CurrentCamera, "FieldOfView", Configuration.expectOptionValue("FieldOfView"))
	else
		fieldOfView:restore()
	end

	if Configuration.expectToggleValue("ShowRobloxChat") then
		updateShowRobloxChat()
	else
		showRobloxChatMap:restore()
	end

	if Configuration.expectToggleValue("ModifyAmbience") then
		updateAmbience()
	else
		ambienceMap:restore()
	end
end)

---Emplace object.
---@param instance Instance
---@param object ModelESP|PartESP
local emplaceObject = LPH_NO_VIRTUALIZE(function(instance, object)
	local group = groups[object.identifier] or Group.new(object.identifier)

	group:insert(instance, object)

	groups[object.identifier] = group
end)

---On NPCs DescendantAdded.
---@param descendant Instance
local onNPCsDescendantAdded = LPH_NO_VIRTUALIZE(function(descendant)
	local parent = descendant.Parent
	if not parent then
		return
	end

	if not descendant:IsA("Model") or not parent:IsA("Folder") then
		return
	end

	if parent.Name == "Bounties" then
		return emplaceObject(descendant, ModelESP.new("BountyBoard", descendant, "Bounty Board"))
	end

	if parent.Name == "MissionNPC" then
		return emplaceObject(descendant, ModelESP.new("MissionBoard", descendant, "Mission Board"))
	end

	if parent.Name == "Trader" then
		return emplaceObject(descendant, ModelESP.new("NPC", descendant, "Trader"))
	end

	if parent.Name == "Clothes" then
		return emplaceObject(descendant, ModelESP.new("NPC", descendant, "Clothes"))
	end

	if parent.Name == "Titles" then
		return emplaceObject(descendant, ModelESP.new("NPC", descendant, "Title Selector"))
	end

	if parent.Name == "AdvancedQuests" then
		return emplaceObject(
			descendant,
			ModelESP.new("NPC", descendant, string.format("Advanced Quests (%s)", descendant.Name))
		)
	end

	if parent.Name == "DivisionDuties" then
		return emplaceObject(descendant, ModelESP.new("NPC", descendant, "Division Duties"))
	end

	if parent.Name == "Captains" then
		return emplaceObject(descendant, ModelESP.new("NPC", descendant, "Captain"))
	end

	return emplaceObject(
		descendant,
		ModelESP.new("NPC", descendant, string.format("%s (%s)", parent.Name, descendant.Name))
	)
end)

---On Entities ChildAdded.
---@param child Instance
local onEntitiesChildAdded = LPH_NO_VIRTUALIZE(function(child)
	if players:GetPlayerFromCharacter(child) then
		return
	end

	-- safeguard lol
	if players:FindFirstChild(child.Name) then
		return
	end

	return emplaceObject(child, MobESP.new("Mob", child, child:GetAttribute("EntityType") or child.Name))
end)

---On instance removing.
---@param inst Instance
local onInstanceRemoving = LPH_NO_VIRTUALIZE(function(inst)
	for _, group in next, groups do
		local object = group:remove(inst)
		if not object then
			continue
		end

		object:detach()
	end
end)

---On player added.
---@param player Player
local onPlayerAdded = LPH_NO_VIRTUALIZE(function(player)
	if player == players.LocalPlayer then
		return
	end

	local characterAdded = Signal.new(player.CharacterAdded)
	local characterRemoving = Signal.new(player.CharacterRemoving)
	local playerDestroying = Signal.new(player.Destroying)

	local characterAddedId = nil
	local characterRemovingId = nil
	local playerDestroyingId = nil

	characterAddedId = visualsMaid:add(characterAdded:connect("Visuals_OnCharacterAdded", function(character)
		emplaceObject(player, PlayerESP.new("Player", player, character))
	end))

	characterRemovingId = visualsMaid:add(characterRemoving:connect("Visuals_OnCharacterRemoving", function()
		onInstanceRemoving(player)
	end))

	playerDestroyingId = visualsMaid:add(playerDestroying:connect("Visuals_OnPlayerDestroying", function()
		visualsMaid[characterAddedId] = nil
		visualsMaid[characterRemovingId] = nil
		visualsMaid[playerDestroyingId] = nil
	end))

	local character = player.Character
	if not character then
		return
	end

	emplaceObject(player, PlayerESP.new("Player", player, character))
end)

---On Soul Crystal Spawn Child Added.
---@param child Instance
local onSoulCrystalSpawnChildAdded = LPH_NO_VIRTUALIZE(function(child)
	return emplaceObject(
		child,
		child:IsA("Model") and ModelESP.new("SoulCrystal", child, "Soul Crystal")
			or PartESP.new("SoulCrystal", child, "Soul Crystal")
	)
end)

---On Misc Descendant Added.
---@param child Instance
local onMiscDescendantAdded = LPH_NO_VIRTUALIZE(function(child)
	if child.Name ~= "lootorb" then
		return
	end

	return emplaceObject(child, PartESP.new("LootOrb", child, "Loot Orb"))
end)

---Create listener.
---@param instance Instance
---@param identifier string
---@param addedCallback function
---@param removingCallback function
---@param childFlag boolean
local createListener = LPH_NO_VIRTUALIZE(function(instance, identifier, addedCallback, removingCallback, childFlag)
	local type = childFlag and "Child" or "Descendant"
	local added = Signal.new(childFlag and instance.ChildAdded or instance.DescendantAdded)
	local removed = Signal.new(childFlag and instance.ChildRemoved or instance.DescendantRemoving)

	visualsMaid:add(added:connect(string.format("Visuals_%sOn%sAdded", identifier, type), addedCallback))
	visualsMaid:add(removed:connect(string.format("Visuals_%sOn%sRemoved", identifier, type), removingCallback))

	Profiler.run(string.format("Visuals_%sAddInitial", identifier), function()
		for _, child in next, (childFlag and instance:GetChildren() or instance:GetDescendants()) do
			addedCallback(child)
		end
	end)
end)

---Initialize Visuals.
function Visuals.init()
	local ents = workspace:WaitForChild("Entities")
	local npcs = workspace:WaitForChild("NPCs")
	local misc = workspace:WaitForChild("Misc", 2.0)

	createListener(npcs, "NPCs", onNPCsDescendantAdded, onInstanceRemoving, false)
	createListener(ents, "Entities", onEntitiesChildAdded, onInstanceRemoving, true)
	createListener(players, "Players", onPlayerAdded, onInstanceRemoving, true)

	if misc then
		createListener(misc, "Misc", onMiscDescendantAdded, onInstanceRemoving, true)
	end

	if game.PlaceId == 18214402201 then
		local soulCrystalSpawns = workspace:WaitForChild("SoulCrystalSpawns")
		local soulCrystalSpawned = soulCrystalSpawns:WaitForChild("Spawned")
		createListener(soulCrystalSpawned, "SoulCrystalSpawned", onSoulCrystalSpawnChildAdded, onInstanceRemoving, true)
	end

	visualsMaid:add(renderStepped:connect("Visuals_RenderStepped", updateVisuals))

	Logger.warn("Visuals initialized.")
end

-- Detach Visuals.
function Visuals.detach()
	for _, group in next, groups do
		group:detach()
	end

	visualsMaid:clean()

	Logger.warn("Visuals detached.")
end

-- Return Visuals module.
return Visuals

end)
__bundle_register("Features/Visuals/Group", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Utility.ReferencedMap
local ReferencedMap = require("Utility/ReferencedMap")

---@module Utility.Profiler
local Profiler = require("Utility/Profiler")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@class Group: ReferencedMap
---@field part number
---@field icount number
---@field updated boolean
---@field identifier string
local Group = setmetatable({}, ReferencedMap)
Group.__index = Group

---Update ESP object.
---@param self Group
---@param object ModelESP|PartESP|FilteredESP
Group.object = LPH_NO_VIRTUALIZE(function(self, object)
	self.count = self.count + 1

	if not self.warned and self.count >= 500 then
		-- Notify user.
		Logger.longNotify("(%s) Too many objects will cause your elements to stop updating.", object.identifier)

		-- Set warning.
		self.warned = true
	end

	---@note: If we're updating too many objects, it will cause Roblox to hide UI elements and kick us from the game.
	if self.count >= 500 then
		return
	end

	Profiler.run(string.format("ESP_Update_%s", object.identifier), object.update, object)
end)

---Update group.
---@param self Group
Group.update = LPH_NO_VIRTUALIZE(function(self)
	local map = self:data()

	if not Configuration.idToggleValue(self.identifier, "Enable") then
		return self:hide()
	end

	if Configuration.expectToggleValue("ESPSplitUpdates") then
		local totalElements = #map
		local totalFrames = Configuration.expectOptionValue("ESPSplitFrames")

		local objectsPerPart = math.ceil(totalElements / totalFrames)
		local currentPart = self.part

		local startIdx = (currentPart - 1) * objectsPerPart + 1
		local endIdx = math.min(currentPart * objectsPerPart, totalElements)

		for idx = startIdx, endIdx do
			self:object(map[idx])
		end

		self.part = self.part + 1

		if self.part > totalFrames then
			self.count = 0
			self.part = 1
		end
	else
		for _, object in next, map do
			self:object(object)
		end

		self.part = 1
		self.count = 0
	end

	self.updated = true
end)

---Hide group.
---@param self Group
Group.hide = LPH_NO_VIRTUALIZE(function(self)
	if not self.updated then
		return
	end

	for _, object in next, self:data() do
		object:visible(false)
	end

	self.updated = false
end)

---Detach group.
---@param self Group
Group.detach = LPH_NO_VIRTUALIZE(function(self)
	for _, object in next, self:data() do
		object:detach()
	end
end)

---Create new Group object.
---@param identifier string
---@return Group
function Group.new(identifier)
	local self = setmetatable(ReferencedMap.new(), Group)
	self.part = 1
	self.count = 0
	self.warned = false
	self.updated = true
	self.identifier = identifier
	return self
end

-- Return Group module.
return Group

end)
__bundle_register("Utility/ReferencedMap", function(require, _LOADED, __bundle_register, __bundle_modules)
return LPH_NO_VIRTUALIZE(function()
	---@class ReferencedMap
	---@field _map table
	---@field _references table
	local ReferencedMap = {}
	ReferencedMap.__index = ReferencedMap

	---Insert a value into the map.
	---@param ref any
	---@param element any
	function ReferencedMap:insert(ref, element)
		local key = #self._map + 1
		self._map[key] = element
		self._references[ref] = element
	end

	---Return and remove a element from the map.
	---@param ref any
	---@return any?
	function ReferencedMap:remove(ref)
		local element = self._references[ref]
		if not element then
			return nil
		end

		self._references[ref] = nil

		local position = table.find(self._map, element)
		if not position then
			return nil
		end

		table.remove(self._map, position)

		return element
	end

	---Size of the map.
	---@return number
	function ReferencedMap:size()
		return #self._map
	end

	---Return the map data.
	---@return table
	function ReferencedMap:data()
		return self._map
	end

	---Create new ReferencedMap object.
	---@return ReferencedMap
	function ReferencedMap.new()
		local self = setmetatable({}, ReferencedMap)
		self._map = {}
		self._references = {}
		return self
	end

	-- Return ReferencedMap module.
	return ReferencedMap
end)()

end)
__bundle_register("Features/Visuals/Objects/PlayerESP", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Features.Visuals.Objects.InstanceESP
local InstanceESP = require("Features/Visuals/Objects/InstanceESP")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Game.PlayerScanning
local PlayerScanning = require("Game/PlayerScanning")

---@class PlayerESP: InstanceESP
---@field baseLabel string
---@field player Player
---@field character Model
---@field identifier string
---@field shadow Part
local PlayerESP = setmetatable({}, { __index = InstanceESP })
PlayerESP.__index = PlayerESP
PlayerESP.__type = "PlayerESP"

-- Services.
local players = game:GetService("Players")

-- Formats.
local ESP_HEALTH = "[%i/%i]"
local ESP_VIEW_ANGLE = "[%.2f view angle vs. %.2f]"
local ESP_HEALTH_PERCENTAGE = "[%i%% health]"
local ESP_HEALTH_BARS = "[%.1f bars]"
local ESP_ULTIMATE = "[%i%% bankai/res/volt]"
local ESP_GRADE = "[%s]"
local ESP_ELEMENT = "[%s]"
local ESP_RACE = "[%s]"

---Update PlayerESP.
---@param self PlayerESP
PlayerESP.update = LPH_NO_VIRTUALIZE(function(self)
	local model = self.character
	local player = self.player
	local identifier = self.identifier

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return self:visible(false)
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return self:visible(false)
	end

	local playerNameType = Configuration.idOptionValue(identifier, "PlayerNameType")
	local playerName = "Unknown Player"

	if playerNameType == "Character Name" then
		playerName = player:GetAttribute("CharacterName") or "Unknown Character Name"
	elseif playerNameType == "Roblox Display Name" then
		playerName = player.DisplayName
	elseif playerNameType == "Roblox Username" then
		playerName = player.Name
	end

	if Configuration.expectToggleValue("InfoSpoofing") and Configuration.expectToggleValue("SpoofOtherPlayers") then
		playerName = "Linoria V2 On Top"
	end

	self.label = playerName

	local health = humanoid.Health
	local maxHealth = humanoid.MaxHealth

	local localPlayer = players.LocalPlayer
	local playerGui = localPlayer and localPlayer.PlayerGui
	local leaderBoard = playerGui and playerGui:FindFirstChild("Leaderboard")
	local list = leaderBoard and leaderBoard:FindFirstChild("List")
	local container = list and list:FindFirstChild("Container")
	local playerEntry = container and container:FindFirstChild(player.Name)
	local characterNameEntry = playerEntry and playerEntry:FindFirstChild("CharacterName")

	local tags = { ESP_HEALTH:format(health or -1, maxHealth or -1) }
	local regex = {
		"Grade (%d+)",
		"Semi-Elite Grade",
		"Semi-Grade (%d+)",
		"Elite Grade",
		"Trainee",
		"Human",
		"???",
		"Special Grade",
		"Special Grade (%d+)",
	}

	local grade = nil

	for _, pattern in ipairs(regex) do
		local match = characterNameEntry and characterNameEntry.Text:match(pattern)
		if not match then
			continue
		end

		grade = match
		break
	end

	if grade then
		tags[#tags + 1] = ESP_GRADE:format(grade == "???" and "Hidden Grade" or grade)
	else
		tags[#tags + 1] = ESP_GRADE:format("Unknown Grade")
	end

	if Configuration.idToggleValue(identifier, "ShowElement") then
		tags[#tags + 1] = ESP_ELEMENT:format(model:GetAttribute("Element") or "Unknown Element")
	end

	if Configuration.idToggleValue(identifier, "ShowRace") then
		tags[#tags + 1] = ESP_RACE:format(player:GetAttribute("Race") or "Unknown Race")
	end

	if Configuration.idToggleValue(identifier, "ShowHealthPercentage") then
		local percentage = health / maxHealth * 100
		tags[#tags + 1] = ESP_HEALTH_PERCENTAGE:format(percentage)
	end

	if Configuration.idToggleValue(identifier, "ShowHealthBars") then
		local healthPercentage = health / maxHealth
		local healthInBars = math.clamp(healthPercentage / 0.20, 0, 5)
		tags[#tags + 1] = ESP_HEALTH_BARS:format(healthInBars)
	end

	local usedPosition = humanoidRootPart.Position
	local currentCamera = workspace.CurrentCamera
	local character = players.LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if Configuration.idToggleValue(identifier, "ShowViewAngle") and rootPart then
		tags[#tags + 1] = ESP_VIEW_ANGLE:format(
			currentCamera.CFrame.LookVector:Dot((rootPart.Position - usedPosition).Unit) * -1,
			math.cos(math.rad((Configuration.expectOptionValue("FOVLimit"))))
		)
	end

	if Configuration.idToggleValue(identifier, "ShowUltimate") then
		local ultimate = model:GetAttribute("BankaiMeter") or 0.0
		local maxUltimate = model:GetAttribute("MaxThirdBankaiMeter") or 0.0
		tags[#tags + 1] = ESP_ULTIMATE:format(math.max(ultimate / maxUltimate, 0.0) * 100)
	end

	self.shadow.Position = usedPosition

	local expectedAdornee = model

	if expectedAdornee == nil or not expectedAdornee.Parent or not expectedAdornee.Parent:IsDescendantOf(game) then
		return self:visible(false)
	end

	---@note: BillboardGUIs only update when a property of it changes.
	if self.billboard.Adornee ~= expectedAdornee then
		self.billboard.Adornee = expectedAdornee
	end

	InstanceESP.update(self, usedPosition, tags)

	if not Configuration.idToggleValue(identifier, "MarkAllies") then
		return
	end

	if not PlayerScanning.isAlly(player) then
		return
	end

	self.text.TextColor3 = Configuration.idOptionValue(identifier, "AllyColor")
end)

---Create new PlayerESP object.
---@param identifier string
---@param player Player
---@param character Model
function PlayerESP.new(identifier, player, character)
	local shadow = Instance.new("Part")
	shadow.Transparency = 1.0
	shadow.Anchored = true
	shadow.Parent = workspace
	shadow.CanCollide = false

	local self = setmetatable(InstanceESP.new(shadow, identifier, "Unknown Player"), PlayerESP)
	self.player = player
	self.character = character
	self.identifier = identifier
	self.shadow = self.maid:mark(shadow)

	if character and character:IsA("Model") and not Configuration.expectOptionValue("NoPersisentESP") then
		character.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end

	return self
end

-- Return PlayerESP module.
return PlayerESP

end)
__bundle_register("Features/Visuals/Objects/InstanceESP", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@class InstanceESP
---@field identifier string
---@field maid Maid
---@field label string
---@field text TextLabel
---@field billboard BillboardGui
---@field instance Instance
local InstanceESP = {}
InstanceESP.__index = InstanceESP
InstanceESP.__type = "InstanceESP"

-- Services.
local playersService = game:GetService("Players")

-- Formats.
local ESP_DISTANCE_FORMAT = "%s [%i]"

---Set visibility.
---@param visible boolean
function InstanceESP:visible(visible)
	self.billboard.Enabled = visible
end

---Detach InstanceESP.
function InstanceESP:detach()
	self.maid:clean()
end

---Build text.
---@param self InstanceESP
---@param label string
---@param tags string[]
---@return string
InstanceESP.build = LPH_NO_VIRTUALIZE(function(self, label, tags)
	if #tags <= 0 then
		return label
	end

	local lines = {}
	local start = true

	for _, tag in next, tags do
		local line = lines[#lines] or label

		if not start and #line > Configuration.expectOptionValue("ESPSplitLineLength") then
			lines[#lines + 1] = tag
			continue
		end

		line = line .. " " .. tag

		lines[start and 1 or #lines] = line

		start = false
	end

	return table.concat(lines, "\n")
end)

---Update InstanceESP.
---@param self InstanceESP
---@param position Vector3
---@param tags string[]
InstanceESP.update = LPH_NO_VIRTUALIZE(function(self, position, tags)
	local label = self.label
	local identifier = self.identifier

	if not Configuration.idToggleValue(identifier, "Enable") then
		return self:visible(false)
	end

	local localPlayer = playersService.LocalPlayer
	local localCharacter = localPlayer and localPlayer.Character

	if not localCharacter then
		return self:visible(false)
	end

	local localRoot = localCharacter:FindFirstChild("HumanoidRootPart")
	if not localRoot then
		return self:visible(false)
	end

	local distance = (localRoot.Position - position).Magnitude

	if distance > Configuration.idOptionValue(identifier, "MaxDistance") then
		return self:visible(false)
	end

	if Configuration.idToggleValue(identifier, "ShowDistance") then
		label = ESP_DISTANCE_FORMAT:format(label, distance)
	end

	-- Set visible.
	self:visible(true)

	-- Update text.
	local text = self.text
	text.Text = self:build(label, tags)
	text.TextColor3 = Configuration.idOptionValue(identifier, "Color")
	text.TextSize = Configuration.expectOptionValue("FontSize")
	text.Font = Enum.Font[Configuration.expectOptionValue("Font")] or Enum.Font.Code
end)

---Setup InstanceESP.
function InstanceESP:setup()
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.AlwaysOnTop = true
	billboardGui.Size = UDim2.new(1e5, 0, 1e5, 0)
	billboardGui.Enabled = false
	billboardGui.Adornee = self.instance
	billboardGui.Parent = workspace
	billboardGui.AutoLocalize = false

	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1.0
	textLabel.Size = UDim2.new(1, 0, 1, 0)
	textLabel.TextStrokeTransparency = 0.0
	textLabel.Parent = billboardGui
	textLabel.AutoLocalize = false

	self.billboard = self.maid:mark(billboardGui)
	self.text = self.maid:mark(textLabel)
end

---Create new InstanceESP object.
---@param instance Instance
---@param identifier string
---@param label string
function InstanceESP.new(instance, identifier, label)
	local self = setmetatable({}, InstanceESP)
	self.label = label
	self.instance = instance
	self.identifier = identifier
	self.maid = Maid.new()
	self:setup()
	return self
end

-- Return InstanceESP module.
return InstanceESP

end)
__bundle_register("Features/Visuals/Objects/MobESP", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Features.Visuals.Objects.ModelESP
local ModelESP = require("Features/Visuals/Objects/ModelESP")

---@class MobESP: ModelESP
local MobESP = setmetatable({}, { __index = ModelESP })
MobESP.__index = MobESP
MobESP.__type = "MobESP"

-- Formats.
local ESP_HEALTH = "[%i/%i]"

---Update MobESP.
---@param self MobESP
MobESP.update = LPH_NO_VIRTUALIZE(function(self)
	local humanoid = self.model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return self:visible(false)
	end

	local humanoidRootPart = self.model:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return self:visible(false)
	end

	ModelESP.update(self, { ESP_HEALTH:format(humanoid.Health, humanoid.MaxHealth) })
end)

---Create new MobESP object.
---@param identifier string
---@param model Model
---@param label string
function MobESP.new(identifier, model, label)
	return setmetatable(ModelESP.new(identifier, model, label), MobESP)
end

-- Return MobESP module.
return MobESP

end)
__bundle_register("Features/Visuals/Objects/ModelESP", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Features.Visuals.Objects.InstanceESP
local InstanceESP = require("Features/Visuals/Objects/InstanceESP")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@class ModelESP: InstanceESP
---@field model Model
local ModelESP = setmetatable({}, { __index = InstanceESP })
ModelESP.__index = ModelESP
ModelESP.__type = "ModelESP"

---Update ModelESP.
---@param self ModelESP
---@param tags string[]
ModelESP.update = LPH_NO_VIRTUALIZE(function(self, tags)
	local model = self.model

	if not model.Parent then
		return self:visible(false)
	end

	InstanceESP.update(self, model:GetPivot().Position, tags or {})
end)

---Create new ModelESP object.
---@param identifier string
---@param model Model
---@param label string
function ModelESP.new(identifier, model, label)
	if not model:IsA("Model") then
		return error(string.format("ModelESP expected model on %s creation.", identifier))
	end

	local self = setmetatable(InstanceESP.new(model, identifier, label), ModelESP)
	self.model = model

	if not Configuration.expectOptionValue("NoPersisentESP") then
		self.model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end

	return self
end

-- Return ModelESP module.
return ModelESP

end)
__bundle_register("Features/Visuals/Objects/PartESP", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Features.Visuals.Objects.InstanceESP
local InstanceESP = require("Features/Visuals/Objects/InstanceESP")

---@class PartESP: InstanceESP
---@field part Part
local PartESP = setmetatable({}, { __index = InstanceESP })
PartESP.__index = PartESP
PartESP.__type = "PartESP"

---Update PartESP.
---@param self PartESP
---@param tags string[]
PartESP.update = LPH_NO_VIRTUALIZE(function(self, tags)
	local part = self.part

	if not part.Parent then
		return self:visible(false)
	end

	InstanceESP.update(self, part.Position, tags or {})
end)

---Create new PartESP object.
---@param identifier string
---@param part Part
---@param label string
function PartESP.new(identifier, part, label)
	if not part:IsA("BasePart") then
		return error(string.format("PartESP expected part on %s creation.", identifier))
	end

	local self = setmetatable(InstanceESP.new(part, identifier, label), PartESP)
	self.part = part
	return self
end

-- Return PartESP module.
return PartESP

end)
__bundle_register("Features/Game/Movement", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Utility.OriginalStoreManager
local OriginalStoreManager = require("Utility/OriginalStoreManager")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Features.Exploits.Exploits
local Exploits = require("Features/Exploits/Exploits")

-- Maids.
local movementMaid = Maid.new()

-- Services.
local players = game:GetService("Players")

return LPH_NO_VIRTUALIZE(function()
	-- Movement related stuff is handled here.
	local Movement = {}

	---@module Utility.Signal
	local Signal = require("Utility/Signal")

	---@module Utility.InstanceWrapper
	local InstanceWrapper = require("Utility/InstanceWrapper")

	---@module Utility.OriginalStore
	local OriginalStore = require("Utility/OriginalStore")

	---@module Utility.ControlModule
	local ControlModule = require("Utility/ControlModule")

	---@module Utility.Logger
	local Logger = require("Utility/Logger")

	---@module Utility.Entitites
	local Entitites = require("Utility/Entitites")

	-- Services.
	local runService = game:GetService("RunService")
	local userInputService = game:GetService("UserInputService")

	-- Original stores.
	local agilitySpoofer = movementMaid:mark(OriginalStore.new())

	-- Original store managers.
	local noClipMap = movementMaid:mark(OriginalStoreManager.new())

	-- Signals.
	local preSimulation = Signal.new(runService.PreSimulation)

	-- Debounce.
	local flashStepDebounce = false

	-- State.
	local lastPosition = nil

	---Update noclip.
	---@param character Model
	---@param rootPart BasePart
	local function updateNoClip(character, rootPart)
		for _, instance in pairs(character:GetChildren()) do
			if not instance:IsA("BasePart") then
				continue
			end

			noClipMap:add(instance, "CanCollide", false)
		end
	end

	---Update speed hack.
	---@param rootPart BasePart
	---@param humanoid Humanoid
	local function updateSpeedHack(rootPart, humanoid)
		if Configuration.expectToggleValue("Fly") then
			return
		end

		rootPart.AssemblyLinearVelocity = rootPart.AssemblyLinearVelocity * Vector3.new(0, 1, 0)

		local moveDirection = humanoid.MoveDirection
		if moveDirection.Magnitude <= 0.001 then
			return
		end

		rootPart.AssemblyLinearVelocity = rootPart.AssemblyLinearVelocity
			+ moveDirection.Unit * Configuration.expectOptionValue("SpeedhackSpeed")
	end

	---Update infinite jump.
	---@param rootPart BasePart
	local function updateInfiniteJump(rootPart)
		if Configuration.expectToggleValue("Fly") then
			return
		end

		if not userInputService:IsKeyDown(Enum.KeyCode.Space) then
			return
		end

		rootPart.AssemblyLinearVelocity = rootPart.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
		rootPart.AssemblyLinearVelocity = rootPart.AssemblyLinearVelocity
			+ Vector3.new(0, Configuration.expectOptionValue("InfiniteJumpBoost"), 0)
	end

	---Update fly hack.
	---@param rootPart BasePart
	---@param humanoid Humanoid
	local function updateFlyHack(rootPart, humanoid)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		local flyBodyVelocity = InstanceWrapper.create(movementMaid, "flyBodyVelocity", "BodyVelocity", rootPart)
		flyBodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)

		local flyVelocity = camera.CFrame:VectorToWorldSpace(
			ControlModule.getMoveVector() * Configuration.expectOptionValue("FlySpeed")
		)

		if userInputService:IsKeyDown(Enum.KeyCode.Space) then
			flyVelocity = flyVelocity + Vector3.new(0, Configuration.expectOptionValue("FlyUpSpeed"), 0)
		end

		flyBodyVelocity.Velocity = flyVelocity
	end

	---Update agility spoofer.
	---@param character Model
	local function updateAgilitySpoofer(character)
		local agility = character:FindFirstChild("Agility")
		if not agility then
			return
		end

		---@note: For every 10 investment points, there are two real agility points.
		-- With 40 investment points, we can have 16 real agility points.
		-- However, with 30 investment points, we can only have 14 real agility points.
		-- This means that the starting value must be 8 and we must increase by 2 for every point we have.
		local agilitySpoofValue = 8 + (Options.AgilitySpoof.Value / 10) * 2

		if Toggles.BoostAgilityDirectly.Value then
			agilitySpoofValue = Options.AgilitySpoof.Value
		end

		agilitySpoofer:set(agility, "Value", agilitySpoofValue)
	end

	---Update attach to back.
	---@param rootPart BasePart
	local function updateAttachToBack(rootPart)
		local attachTarget = Entitites.findNearestEntity(200)
		if not attachTarget then
			return
		end

		local attachTargetHrp = attachTarget:FindFirstChild("HumanoidRootPart")
		if not attachTargetHrp then
			return
		end

		local offsetCFrame = CFrame.new(
			0.0,
			Configuration.expectOptionValue("HeightOffset"),
			Configuration.expectOptionValue("BackOffset")
		)

		rootPart.CFrame = rootPart.CFrame:Lerp(attachTargetHrp.CFrame * offsetCFrame, 0.3)
	end

	---Update no slow.
	---@param character Model
	---@param humanoid Humanoid
	local function updateNoSlow(character, humanoid)
		if humanoid.WalkSpeed == 4 or humanoid.WalkSpeed == 0 then
			humanoid.WalkSpeed = character:GetAttribute("BaseWalkspeed")
		end

		if humanoid.JumpHeight == 0 then
			humanoid.JumpHeight = character:GetAttribute("BaseJumpheight")
		end
	end

	---Update flash step.
	---@param character Model
	---@param humanoid Humanoid
	local function updateFlashstepSpeedBoost(character, humanoid)
		local isFlashstep = character:GetAttribute("CurrentState") == "Flashstep"

		if flashStepDebounce and not isFlashstep then
			flashStepDebounce = false
		end

		if flashStepDebounce then
			return
		end

		if not isFlashstep then
			return
		end

		flashStepDebounce = true

		humanoid.WalkSpeed = humanoid.WalkSpeed * (Configuration.expectOptionValue("FlashStepSpeedBoostMulti") or 1.0)
	end

	---Update movement.
	local function updateMovement()
		local localPlayer = players.LocalPlayer
		local character = localPlayer.Character
		if not character then
			return
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			return
		end

		local humanoid = character:FindFirstChild("Humanoid")
		if not humanoid then
			return
		end

		if not Configuration.expectToggleValue("AnchorCharacter") then
			lastPosition = rootPart.CFrame
		end

		if Configuration.expectToggleValue("AnchorCharacter") and lastPosition then
			rootPart.CFrame = lastPosition
		end

		if Configuration.expectToggleValue("FlashstepSpeedBoost") then
			updateFlashstepSpeedBoost(character, humanoid)
		end

		if Configuration.expectToggleValue("NoSlow") then
			updateNoSlow(character, humanoid)
		end

		if Configuration.expectToggleValue("AttachToBack") then
			updateAttachToBack(rootPart)
		end

		if Configuration.expectToggleValue("Fly") then
			updateFlyHack(rootPart, humanoid)
		else
			movementMaid["flyBodyVelocity"] = nil
		end

		if Configuration.expectToggleValue("NoClip") then
			updateNoClip(character, rootPart)
		else
			noClipMap:restore()
		end

		if Configuration.expectToggleValue("Speedhack") then
			updateSpeedHack(rootPart, humanoid)
		end

		if Configuration.expectToggleValue("InfiniteJump") then
			updateInfiniteJump(rootPart)
		end

		if Configuration.expectToggleValue("AgilitySpoof") then
			updateAgilitySpoofer(character)
		else
			agilitySpoofer:restore()
		end
	end

	---Initialize movement.
	function Movement.init()
		-- Attach.
		movementMaid:add(preSimulation:connect("Movement_PreSimulation", updateMovement))

		-- Log.
		Logger.warn("Movement initialized.")
	end

	---Detach movement.
	function Movement.detach()
		-- Clean.
		movementMaid:clean()

		-- Log.
		Logger.warn("Movement detached.")
	end

	-- Return Movement module.
	return Movement
end)()

end)
__bundle_register("Menu", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Menu module.
local Menu = {}

---@module GUI.ThemeManager
local ThemeManager = require("GUI/ThemeManager")

---@module GUI.SaveManager
local SaveManager = require("GUI/SaveManager")

---@module GUI.Library
local Library = require("GUI/Library")

---@module Menu.CombatTab
local CombatTab = require("Menu/CombatTab")

---@module Menu.GameTab
local GameTab = require("Menu/GameTab")

---@module Menu.BuilderTab
local BuilderTab = require("Menu/BuilderTab")

---@module Menu.VisualsTab
local VisualsTab = require("Menu/VisualsTab")

---@module Menu.LycorisTab
local LycorisTab = require("Menu/LycorisTab")

---@module Menu.AutomationTab
local AutomationTab = require("Menu/AutomationTab")

---@module Menu.ExploitTab
local ExploitTab = require("Menu/ExploitTab")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

-- Services.
local runService = game:GetService("RunService")
local stats = game:GetService("Stats")
local players = game:GetService("Players")

-- Signals.
local renderStepped = Signal.new(runService.RenderStepped)

-- Maids.
local menuMaid = Maid.new()

-- Constants.
local MENU_TITLE = "Linoria V2 | Type Soul"

if LRM_UserNote then
	MENU_TITLE = string.format(
		"(Commit %s) Linoria V2 | Type Soul First Release",
		string.sub("8651ab54aacec4210aa23b4858646389a9292352", 1, 6)
	)
end

---Initialize menu.
function Menu.init()
	-- Create window.
	local window = Library:CreateWindow({
		Title = MENU_TITLE,
		Center = true,
		AutoShow = not shared.Lycoris.silent,
		TabPadding = 8,
		MenuFadeTime = 0.0,
	})

	-- Configure ThemeManager.
	ThemeManager:SetLibrary(Library)
	ThemeManager:SetFolder("Lycoris-Rewrite-TypeSoul-Themes")

	-- Configure SaveManager.
	SaveManager:SetLibrary(Library)
	SaveManager:IgnoreThemeSettings()
	SaveManager:SetFolder("Lycoris-Rewrite-TypeSoul-Configs")
	SaveManager:SetIgnoreIndexes({
		"Fly",
		"NoClip",
		"Speedhack",
		"InfiniteJump",
		"AttachToBack",
		"Invisibility",
	})

	-- Initialize all tabs.
	CombatTab.init(window)
	BuilderTab.init(window)
	GameTab.init(window)
	VisualsTab.init(window)
	ExploitTab.init(window)
	AutomationTab.init(window)
	LycorisTab.init(window)

	-- Last update.
	local lastUpdate = os.clock()

	-- Update watermark.
	menuMaid:add(renderStepped:connect(
		"Menu_WatermarkUpdate",
		LPH_NO_VIRTUALIZE(function()
			if os.clock() - lastUpdate <= 0.5 then
				return
			end

			lastUpdate = os.clock()

			-- Get stats.
			local networkStats = stats:FindFirstChild("Network")
			local workspaceStats = stats:FindFirstChild("Workspace")
			local performanceStats = stats:FindFirstChild("PerformanceStats")
			local serverStats = networkStats and networkStats:FindFirstChild("ServerStatsItem") or nil

			-- Get data.
			local pingData = serverStats and serverStats:FindFirstChild("Data Ping") or nil
			local heartbeatData = workspaceStats and workspaceStats:FindFirstChild("Heartbeat") or nil
			local cpuData = performanceStats and performanceStats:FindFirstChild("CPU") or nil
			local gpuData = performanceStats and performanceStats:FindFirstChild("GPU") or nil

			-- Set values.
			local ping = pingData and pingData:GetValue() or 0.0
			local fps = heartbeatData and heartbeatData:GetValue() or 0.0
			local cpu = cpuData and cpuData:GetValue() or 0.0
			local gpu = gpuData and gpuData:GetValue() or 0.0

			-- Character data.
			local mouse = players.LocalPlayer and players.LocalPlayer:GetMouse()
			local position = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position
			local positionFormat = position and string.format("(%.2f, %.2f, %.2f)", position.X, position.Y, position.Z)
				or "N/A"

			-- String.
			local str = string.format("%s | %.2fms | %.1f/s | %.1fms | %.1fms", MENU_TITLE, ping, fps, cpu, gpu)

			if Configuration.expectToggleValue("ShowDebugInformation") then
				str = str .. string.format(" | %s", positionFormat)
				str = str .. string.format(" | %s", mouse and mouse.Target and mouse.Target:GetFullName() or "N/A")
			end

			-- Set watermark.
			Library:SetWatermark(str)
		end)
	))

	-- Configure Library.
	Library.ToggleKeybind = Options.MenuKeybind

	-- Load auto-load config.
	SaveManager:LoadAutoloadConfig()

	-- Log menu initialization.
	Logger.warn("Menu initialized.")
end

---Detach menu.
function Menu.detach()
	menuMaid:clean()

	Library:Unload()

	Logger.warn("Menu detached.")
end

-- Return Menu module.
return Menu

end)
__bundle_register("Menu/ExploitTab", function(require, _LOADED, __bundle_register, __bundle_modules)
-- ExploitTab module.
local ExploitTab = {}

---@module Utility.PersistentData
local PersistentData = require("Utility/PersistentData")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Utility.Logger
local Logger = require("Utility/Logger")

-- Services.
local teleportService = game:GetService("TeleportService")
local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

-- Constants.
local LOBBY_PLACE_ID = 14067600077
local LIBRARY_PLACE_ID = 122291183918016

---Initialize Mob Exploits section.
---@param groupbox table
function ExploitTab.initMobExploitsSection(groupbox)
	local voidMobsToggle = groupbox:AddToggle("VoidMobs", {
		Text = "Void Mobs",
		Tooltip = "Teleport nearby mobs and send them to the void.",
		Default = false,
	})

	voidMobsToggle:AddKeyPicker("VoidMobsKeyBind", { Default = "N/A", SyncToggleState = true, Text = "Void Mobs" })
end

---Initialize Local Character Exploits section.
---@param groupbox table
function ExploitTab.initLocalCharacterExploitsSection(groupbox)
	local pathfindBreakerToggle = groupbox:AddToggle("PathfindBreaker", {
		Text = "Pathfind Breaker",
		Tooltip = "Visibly break the pathfinding for humanoid mobs by attempting to spoof your vertical velocity.",
		Default = false,
	})

	pathfindBreakerToggle:AddKeyPicker(
		"PathfindBreakerKeyBind",
		{ Default = "N/A", SyncToggleState = true, Text = "Pathfind Breaker" }
	)

	local pbDepBox = groupbox:AddDependencyBox()

	local pbHighlightToggle = pbDepBox:AddToggle("PathfindBreakerHighlight", {
		Text = "Show Highlight",
		Tooltip = "Because this feature can be very visible, you can enable a visual highlight to see if it is on.",
		Default = false,
	})

	pbHighlightToggle:AddColorPicker("PathfindBreakerHighlightColor", {
		Default = Color3.fromRGB(200, 0, 255),
		Text = "Highlight Color",
	})

	pbHighlightToggle:AddColorPicker("PathfindBreakerHighlightOutlineColor", {
		Default = Color3.fromRGB(255, 152, 234),
		Text = "Outline Color",
	})

	pbDepBox:SetupDependencies({
		{ pathfindBreakerToggle, true },
	})

	local ivToggle = groupbox:AddToggle("Invisibility", {
		Text = "Invisibility",
		Tooltip = "Play an animation which will desync your character's visible position up from the floor from your actual position.",
		Default = false,
	})

	ivToggle:AddKeyPicker("InvisibilityKeyBind", { Default = "N/A", SyncToggleState = true, Text = "Invisibility" })
end

---Initialize Game Exploits section.
---@param groupbox table
function ExploitTab.initGameExploitsSection(groupbox)
	groupbox:AddButton({
		Text = "Book Fragment Exploit",
		Tooltip = "For every book in the library, forcibly submit in its fragment.",
		DoubleClick = true,
		DoubleClickText = "Use at your own risk?",
		Func = function()
			local libraryPuzzle = workspace:FindFirstChild("LibraryPuzzle")
			if not libraryPuzzle then
				return
			end

			local bookButtons = libraryPuzzle:FindFirstChild("BookButtons")
			if not bookButtons then
				return
			end

			local remotes = replicatedStorage:FindFirstChild("Remotes")
			local questRemotes = remotes and remotes:FindFirstChild("QuestRemotes")
			local bookFragmentRemote = questRemotes and questRemotes:FindFirstChild("BookFragment")
			if not bookFragmentRemote then
				return
			end

			---@note: Books must be done in an order or it will be invalid
			local indices = {}
			local order = {
				"fist",
				"power",
				"king",
				"blade",
				"soul",
			}

			local localPlayer = playersService.LocalPlayer
			local playerGui = localPlayer and localPlayer.PlayerGui
			local bookUi = playerGui and playerGui:FindFirstChild("BookUI")
			local fragments = bookUi and bookUi:FindFirstChild("Fragment")
			if not fragments then
				return
			end

			for _, value in next, order do
				for _, instance in next, fragments:GetChildren() do
					local fragmentText = instance:FindFirstChild("FragmentText")
					if not fragmentText then
						continue
					end

					if not fragmentText.Text:lower():match(value) then
						continue
					end

					indices[#indices + 1] = { idx = tonumber(instance.Name), value = value }
					break
				end
			end

			for _, data in next, indices do
				bookFragmentRemote:FireServer({
					["BookPress"] = true,
					["bookNumber"] = data.idx,
					["FragmentsCorrect"] = true,
				})

				Logger.notify(
					"('%s' - %i) Book Fragment Exploit has forcefully submitted book fragment.",
					data.value,
					data.idx
				)
			end
		end,
	})
end

---Add teleport button with disclaimer.
---@param groupbox table
---@param text string
---@param dest string
local function addTeleportButton(groupbox, text, dest)
	groupbox:AddButton({
		Text = text,
		Tooltip = "This will take you back to the main menu and teleport you from there.",
		DoubleClick = true,
		DoubleClickText = "Use at your own risk?",
		Func = function()
			local slot = Configuration.expectOptionValue("TeleportSlot")
			if not slot or #slot <= 0 then
				return Logger.notify("Please enter a teleport slot to use for teleportation.", 5)
			end

			if not slot:match("^[A-Z]+$") then
				return Logger.notify(
					"Teleport slot must consist of only uppercase alphabetical letters (A-Z) to be used for teleportation.",
					5
				)
			end

			Logger.longNotify(
				"Teleporting to %s using slot '%s' -- please wait for teleport back to main menu.",
				dest,
				slot
			)

			PersistentData.set("tslot", slot)
			PersistentData.set("tdestination", dest)
			teleportService:Teleport(LOBBY_PLACE_ID, playersService.LocalPlayer)
		end,
	})
end

---Initialize Teleports section.
---@param groupbox table
function ExploitTab.initTeleportsSection(groupbox)
	addTeleportButton(groupbox, "Teleport To Hell Ring 1", "Hell Ring 1")
	addTeleportButton(groupbox, "Teleport To Hell Ring 2", "Hell Ring 2")
	addTeleportButton(groupbox, "Teleport To Hell Ring 3", "Hell Ring 3")
	addTeleportButton(groupbox, "Teleport To Soul Society", "Soul Society")
	addTeleportButton(groupbox, "Teleport To Library", "Library")
	addTeleportButton(groupbox, "Teleport To Karakura Town", "Karakura Town")
	addTeleportButton(groupbox, "Teleport To Fake KT", "Fake KT")
	addTeleportButton(groupbox, "Teleport To Rukon District", "Rukon District")
	addTeleportButton(groupbox, "Teleport To Hueco Mundo", "Hueco Mundo")
	addTeleportButton(groupbox, "Teleport To Maze", "Maze")
	addTeleportButton(groupbox, "Teleport To Las Noches", "Las Noches")
	addTeleportButton(groupbox, "Teleport To Wandenreich City", "Wandenreich City")
	addTeleportButton(groupbox, "Teleport To Matchmaking", "Matchmaking")
	addTeleportButton(groupbox, "Teleport To AFK World", "AFK World")

	groupbox:AddInput("TeleportSlot", {
		Text = "Teleport Slot",
		Tooltip = "Enter the slot you want to use for teleportation.",
		Placeholder = "Enter Slot (A-C)",
	})
end
---Initialize tab.
---@param window table
function ExploitTab.init(window)
	-- Create tab.
	local tab = window:AddTab("Exploit")

	-- Initialize sections.
	ExploitTab.initMobExploitsSection(tab:AddDynamicGroupbox("Mob Exploits"))
	ExploitTab.initLocalCharacterExploitsSection(tab:AddDynamicGroupbox("Local Character Exploits"))

	if game.PlaceId == LIBRARY_PLACE_ID then
		ExploitTab.initGameExploitsSection(tab:AddDynamicGroupbox("Game Exploits"))
	end

	ExploitTab.initTeleportsSection(tab:AddDynamicGroupbox("Teleports"))
end

-- Return ExploitTab module.
return ExploitTab

end)
__bundle_register("Menu/AutomationTab", function(require, _LOADED, __bundle_register, __bundle_modules)
-- AutomationTab module.
local AutomationTab = {}

---Initialize 'Input Automation' section.
---@param groupbox table
function AutomationTab.initInputAutomation(groupbox)
	groupbox:AddToggle("AntiAFK", {
		Text = "Anti AFK",
		Tooltip = "Prevent the player from being kicked for being idle by sending periodic inputs for you.",
		Default = false,
	})

	groupbox:AddToggle("AutoAcceptRaid", {
		Text = "Auto Accept Raid",
		Tooltip = "Automatically accept raid prompts.",
		Default = false,
	})
end

---Initialize tab.
---@param window table
function AutomationTab.init(window)
	-- Create tab.
	local tab = window:AddTab("Auto")

	-- Initialize sections.
	AutomationTab.initInputAutomation(tab:AddDynamicGroupbox("Input Automation"))
end

-- Return AutomationTab module.
return AutomationTab

end)
__bundle_register("Menu/LycorisTab", function(require, _LOADED, __bundle_register, __bundle_modules)
-- LycorisTab module.
local LycorisTab = {}

---@module GUI.ThemeManager
local ThemeManager = require("GUI/ThemeManager")

---@module GUI.SaveManager
local SaveManager = require("GUI/SaveManager")

---@module GUI.Library
local Library = require("GUI/Library")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---Initialize Cheat Settings section.
---@param groupbox table
function LycorisTab.initCheatSettingsSection(groupbox)
	groupbox:AddButton("Toggle Silent Mode", function()
		if not isfile or not delfile or not writefile then
			return
		end

		shared.Lycoris.silent = not shared.Lycoris.silent

		if not shared.Lycoris.silent then
			Logger.notify("Silent mode was disabled.")
		end

		if isfile("smarker_ts.txt") then
			delfile("smarker_ts.txt")
		else
			writefile(
				"smarker_ts.txt",
				"Hello, if you're reading this, that means you have Lycoris-Rewrite-TypeSoul silent mode turned on. Deleting this file will turn it off."
			)
		end
	end)

	groupbox:AddButton("Toggle Player Scanning", function()
		if not isfile or not delfile or not writefile then
			return
		end

		shared.Lycoris.dpscanning = not shared.Lycoris.dpscanning

		if not shared.Lycoris.dpscanning then
			Logger.notify("Player scanning was disabled.")
		else
			Logger.notify("Player scanning was enabled.")
		end

		if isfile("dpscanning_ts.txt") then
			delfile("dpscanning_ts.txt")
		else
			writefile(
				"dpscanning_ts.txt",
				"Hello, if you're reading this, that means you have Lycoris-Rewrite-TypeSoul player scanning turned off. Deleting this file will turn it on."
			)
		end
	end)

	groupbox:AddButton("Unload Cheat", function()
		shared.Lycoris.detach()
	end)
end

---Initialize UI Settings section.
---@param groupbox table
function LycorisTab.initUISettingsSection(groupbox)
	local menuBindLabel = groupbox:AddLabel("Menu Bind")

	menuBindLabel:AddKeyPicker("MenuKeybind", { Default = "LeftAlt", NoUI = true, Text = "Menu Keybind" })

	local keybindFrameLabel = groupbox:AddLabel("Keybind List Bind")

	keybindFrameLabel:AddKeyPicker("KeybindList", {
		Default = "N/A",
		Mode = "Off",
		NoUI = true,
		Text = "Keybind List",
		Callback = function(Value)
			Library.KeybindFrame.Visible = Value
		end,
	})

	local watermarkFrameLabel = groupbox:AddLabel("Watermark Bind")

	watermarkFrameLabel:AddKeyPicker("Watermark", {
		Default = "N/A",
		Mode = "Off",
		NoUI = true,
		Text = "Watermark",
		Callback = function(Value)
			Library:SetWatermarkVisibility(Value)
		end,
	})
end

---Initialize tab.
function LycorisTab.init(window)
	-- Create tab.
	local tab = window:AddTab("Settings") -- dont change the name, it's more confusing if its named that way

	-- Initialize sections.
	LycorisTab.initCheatSettingsSection(tab:AddLeftGroupbox("Cheat Settings"))
	LycorisTab.initUISettingsSection(tab:AddRightGroupbox("UI Settings"))

	-- Configure SaveManager & ThemeManager.
	ThemeManager:ApplyToTab(tab)
	SaveManager:BuildConfigSection(tab)
end

-- Return LycorisTab module.
return LycorisTab

end)
__bundle_register("GUI/SaveManager", function(require, _LOADED, __bundle_register, __bundle_modules)
return LPH_NO_VIRTUALIZE(function()
	local httpService = game:GetService("HttpService")

	---Export UDim2 to a serializable table.
	---@param udim2 UDim2
	---@return table
	local function uDIm2Export(udim2)
		return {
			xScale = udim2.X.Scale,
			xOffset = udim2.X.Offset,
			yScale = udim2.Y.Scale,
			yOffset = udim2.Y.Offset,
		}
	end

	---Import UDim2 from a serializable table.
	---@param serialized table
	---@return UDim2
	local function uDim2Import(serialized)
		return UDim2.new(serialized.xScale, serialized.xOffset, serialized.yScale, serialized.yOffset)
	end

	local SaveManager = {}
	do
		SaveManager.Folder = "Lycoris-Rewrite-TypeSoul-Configs"
		SaveManager.Ignore = {}
		SaveManager.Parser = {
			Toggle = {
				Save = function(idx, object)
					return { type = "Toggle", idx = idx, value = object.Value }
				end,
				Load = function(idx, data)
					if Toggles[idx] then
						Toggles[idx]:SetValue(data.value)
					end
				end,
			},
			Slider = {
				Save = function(idx, object)
					return { type = "Slider", idx = idx, value = tostring(object.Value) }
				end,
				Load = function(idx, data)
					if Options[idx] then
						Options[idx]:SetValue(data.value)
					end
				end,
			},
			Dropdown = {
				Save = function(idx, object)
					return {
						type = "Dropdown",
						idx = idx,
						value = object.Value,
						values = object.SaveValues and object.Values or nil,
						mutli = object.Multi,
					}
				end,
				Load = function(idx, data)
					if Options[idx] then
						Options[idx]:SetValue(data.value)

						if not data.values then
							return
						end

						Options[idx]:SetValues(data.values)
					end
				end,
			},
			ColorPicker = {
				Save = function(idx, object)
					return {
						type = "ColorPicker",
						idx = idx,
						hue = object.Hue,
						sat = object.Sat,
						vib = object.Vib,
						transparency = object.Transparency,
						rainbow = object.Rainbow,
					}
				end,
				Load = function(idx, data)
					if Options[idx] then
						Options[idx].Rainbow = data.rainbow
						Options[idx]:SetValue({ data.hue, data.sat, data.vib }, data.transparency)
					end
				end,
			},
			KeyPicker = {
				Save = function(idx, object)
					return { type = "KeyPicker", idx = idx, mode = object.Mode, key = object.Value }
				end,
				Load = function(idx, data)
					if Options[idx] then
						Options[idx]:SetValue({ data.key, data.mode })
					end
				end,
			},

			Input = {
				Save = function(idx, object)
					return { type = "Input", idx = idx, text = object.Value }
				end,
				Load = function(idx, data)
					if Options[idx] and type(data.text) == "string" then
						Options[idx]:SetValue(data.text)
					end
				end,
			},
		}

		function SaveManager:SetIgnoreIndexes(list)
			for _, key in next, list do
				self.Ignore[key] = true
			end
		end

		function SaveManager:SetFolder(folder)
			self.Folder = folder
			self:BuildFolderTree()
		end

		function SaveManager:Save(name)
			if not name then
				return false, "no config file is selected"
			end

			local fullPath = self.Folder .. "/" .. name .. ".json"

			local data = {
				objects = {},
				keybindFramePosition = uDIm2Export(self.Library.KeybindFrame.Position),
				watermarkFramePosition = uDIm2Export(self.Library.Watermark.Position),
				infoLoggerFramePosition = uDIm2Export(self.Library.InfoLoggerFrame.Position),
				infoLoggerBlacklistHistory = self.Library.InfoLoggerData.KeyBlacklistHistory,
				infoLoggerBlacklist = self.Library.InfoLoggerData.KeyBlacklistList,
				infoLoggerCycle = self.Library.InfoLoggerData.InfoLoggerCycle,
				animationVisualizerFramePosition = uDIm2Export(self.Library.AnimationVisualizerFrame.Position),
			}

			for idx, toggle in next, Toggles do
				if self.Ignore[idx] then
					continue
				end

				table.insert(data.objects, self.Parser[toggle.Type].Save(idx, toggle))
			end

			for idx, option in next, Options do
				if not self.Parser[option.Type] then
					continue
				end
				if self.Ignore[idx] then
					continue
				end

				table.insert(data.objects, self.Parser[option.Type].Save(idx, option))
			end

			local success, encoded = pcall(httpService.JSONEncode, httpService, data)
			if not success then
				return false, "failed to encode data"
			end

			writefile(fullPath, encoded)
			return true
		end

		function SaveManager:Load(name)
			if not name then
				return false, "no config file is selected"
			end

			local file = self.Folder .. "/" .. name .. ".json"
			if not isfile(file) then
				return false, "invalid file"
			end

			local success, decoded = pcall(httpService.JSONDecode, httpService, readfile(file))
			if not success then
				return false, "decode error"
			end

			if decoded.keybindFramePosition then
				self.Library.KeybindFrame.Position = uDim2Import(decoded.keybindFramePosition)
			end

			if decoded.watermarkFramePosition then
				self.Library.Watermark.Position = uDim2Import(decoded.watermarkFramePosition)
			end

			if decoded.infoLoggerFramePosition then
				self.Library.InfoLoggerFrame.Position = uDim2Import(decoded.infoLoggerFramePosition)
			end

			if decoded.infoLoggerBlacklistHistory then
				self.Library.InfoLoggerData.KeyBlacklistHistory = decoded.infoLoggerBlacklistHistory
			end

			if decoded.animationVisualizerFramePosition then
				self.Library.AnimationVisualizerFrame.Position = uDim2Import(decoded.animationVisualizerFramePosition)
			end

			for _, option in next, decoded.objects do
				if self.Parser[option.type] then
					task.spawn(function()
						self.Parser[option.type].Load(option.idx, option)
					end) -- task.spawn() so the config loading wont get stuck.
				end
			end

			if decoded.infoLoggerBlacklist then
				self.Library.InfoLoggerData.KeyBlacklistList = decoded.infoLoggerBlacklist
				self.Library:RefreshInfoLogger()
				if Options and Options.BlacklistedKeys then
					Options.BlacklistedKeys:SetValues(self.Library:KeyBlacklists())
				end
			end

			if decoded.infoLoggerCycle then
				self.Library.InfoLoggerData.InfoLoggerCycle = decoded.infoLoggerCycle
				self.Library:RefreshInfoLogger()
				if Options and Options.BlacklistedKeys then
					Options.BlacklistedKeys:SetValues(self.Library:KeyBlacklists())
				end
			end

			return true
		end

		function SaveManager:IgnoreThemeSettings()
			self:SetIgnoreIndexes({
				"BackgroundColor",
				"MainColor",
				"AccentColor",
				"OutlineColor",
				"FontColor", -- themes
				"ThemeManager_ThemeList",
				"ThemeManager_CustomThemeList",
				"ThemeManager_CustomThemeName", -- themes
			})
		end

		function SaveManager:BuildFolderTree()
			local paths = {
				self.Folder,
			}

			for i = 1, #paths do
				local str = paths[i]
				if not isfolder(str) then
					makefolder(str)
				end
			end
		end

		function SaveManager:RefreshConfigList()
			local list = listfiles(self.Folder)

			local out = {}
			for i = 1, #list do
				local file = list[i]
				if file:sub(-5) == ".json" then
					-- i hate this but it has to be done ...

					local pos = file:find(".json", 1, true)
					local start = pos

					local char = file:sub(pos, pos)
					while char ~= "/" and char ~= "\\" and char ~= "" do
						pos = pos - 1
						char = file:sub(pos, pos)
					end

					if char == "/" or char == "\\" then
						table.insert(out, file:sub(pos + 1, start - 1))
					end
				end
			end

			return out
		end

		function SaveManager:SetLibrary(library)
			self.Library = library
		end

		function SaveManager:LoadAutoloadConfig()
			if isfile(self.Folder .. "/autoload.txt") then
				local name = readfile(self.Folder .. "/autoload.txt")

				local success, err = self:Load(name)
				if not success then
					return self.Library:Notify("Failed to load autoload config: " .. err)
				end

				self.Library:Notify(string.format("Auto loaded config %q", name))
			end
		end

		function SaveManager:BuildConfigSection(tab)
			assert(self.Library, "Must set SaveManager.Library")

			local section = tab:AddRightGroupbox("Config Manager")

			section:AddInput("SaveManager_ConfigName", { Text = "Config name" })
			section:AddDropdown(
				"SaveManager_ConfigList",
				{ Text = "Config list", Values = self:RefreshConfigList(), AllowNull = true }
			)

			section:AddDivider()

			section
				:AddButton("Create config", function()
					local name = Options.SaveManager_ConfigName.Value

					if name:gsub(" ", "") == "" then
						return self.Library:Notify("Invalid config name (empty)", 2)
					end

					local success, err = self:Save(name)
					if not success then
						return self.Library:Notify("Failed to save config: " .. err)
					end

					self.Library:Notify(string.format("Created config %q", name))

					Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
					Options.SaveManager_ConfigList:SetValue(nil)
				end)
				:AddButton("Load config", function()
					local name = Options.SaveManager_ConfigList.Value

					local success, err = self:Load(name)
					if not success then
						return self.Library:Notify("Failed to load config: " .. err)
					end

					self.Library:Notify(string.format("Loaded config %q", name))
				end)

			section:AddButton("Overwrite config", function()
				local name = Options.SaveManager_ConfigList.Value

				local success, err = self:Save(name)
				if not success then
					return self.Library:Notify("Failed to overwrite config: " .. err)
				end

				self.Library:Notify(string.format("Overwrote config %q", name))
			end)

			section:AddButton("Refresh list", function()
				Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
				Options.SaveManager_ConfigList:SetValue(nil)
			end)

			section:AddButton("Set as autoload", function()
				local name = Options.SaveManager_ConfigList.Value
				writefile(self.Folder .. "/autoload.txt", name)
				SaveManager.AutoloadLabel:SetText("Current autoload config: " .. name)
				self.Library:Notify(string.format("Set %q to auto load", name))
			end)

			SaveManager.AutoloadLabel = section:AddLabel("Current autoload config: none", true)

			if isfile(self.Folder .. "/autoload.txt") then
				local name = readfile(self.Folder .. "/autoload.txt")
				SaveManager.AutoloadLabel:SetText("Current autoload config: " .. name)
			end

			SaveManager:SetIgnoreIndexes({ "SaveManager_ConfigList", "SaveManager_ConfigName" })
		end

		SaveManager:BuildFolderTree()
	end

	return SaveManager
end)()

end)
__bundle_register("GUI/ThemeManager", function(require, _LOADED, __bundle_register, __bundle_modules)
return LPH_NO_VIRTUALIZE(function()
	local httpService = game:GetService("HttpService")
	local ThemeManager = {}
	do
		ThemeManager.Folder = "Lycoris-Rewrite-TypeSoul-Themes"
		ThemeManager.Library = nil
		ThemeManager.BuiltInThemes = {
			["Default"] = {
				1,
				httpService:JSONDecode(
					'{"FontColor":"ffffff","MainColor":"1c1c1c","AccentColor":"0055ff","BackgroundColor":"141414","OutlineColor":"323232"}'
				),
			},
			["BBot"] = {
				2,
				httpService:JSONDecode(
					'{"FontColor":"ffffff","MainColor":"1e1e1e","AccentColor":"7e48a3","BackgroundColor":"232323","OutlineColor":"141414"}'
				),
			},
			["Fatality"] = {
				3,
				httpService:JSONDecode(
					'{"FontColor":"ffffff","MainColor":"1e1842","AccentColor":"c50754","BackgroundColor":"191335","OutlineColor":"3c355d"}'
				),
			},
			["Jester"] = {
				4,
				httpService:JSONDecode(
					'{"FontColor":"ffffff","MainColor":"242424","AccentColor":"db4467","BackgroundColor":"1c1c1c","OutlineColor":"373737"}'
				),
			},
			["Mint"] = {
				5,
				httpService:JSONDecode(
					'{"FontColor":"ffffff","MainColor":"242424","AccentColor":"3db488","BackgroundColor":"1c1c1c","OutlineColor":"373737"}'
				),
			},
			["Tokyo Night"] = {
				6,
				httpService:JSONDecode(
					'{"FontColor":"ffffff","MainColor":"191925","AccentColor":"6759b3","BackgroundColor":"16161f","OutlineColor":"323232"}'
				),
			},
			["Ubuntu"] = {
				7,
				httpService:JSONDecode(
					'{"FontColor":"ffffff","MainColor":"3e3e3e","AccentColor":"e2581e","BackgroundColor":"323232","OutlineColor":"191919"}'
				),
			},
			["Quartz"] = {
				8,
				httpService:JSONDecode(
					'{"FontColor":"ffffff","MainColor":"232330","AccentColor":"426e87","BackgroundColor":"1d1b26","OutlineColor":"27232f"}'
				),
			},
		}

		function ThemeManager:ApplyTheme(theme)
			local customThemeData = self:GetCustomTheme(theme)
			local data = customThemeData or self.BuiltInThemes[theme]

			if not data then
				return
			end

			for idx, themeData in next, customThemeData or data[2] do
				if type(themeData) == "string" then
					self.Library[idx] = Color3.fromHex(themeData)

					if Options[idx] then
						Options[idx]:SetValueRGB(Color3.fromHex(themeData))
					end
				else
					self.Library[idx] = Color3.fromHSV(themeData.hue, themeData.sat, themeData.vib)

					if Options[idx] then
						Options[idx].Rainbow = themeData.rainbow
						Options[idx]:SetValue({ themeData.hue, themeData.sat, themeData.vib }, themeData.transparency)
					end
				end
			end

			self:ThemeUpdate()
		end

		function ThemeManager:ThemeUpdate()
			-- This allows us to force apply themes without loading the themes tab :)
			local options = { "FontColor", "MainColor", "AccentColor", "BackgroundColor", "OutlineColor" }
			for i, field in next, options do
				if Options and Options[field] then
					self.Library[field] = Options[field].Value
				end
			end

			self.Library.AccentColorDark = self.Library:GetDarkerColor(self.Library.AccentColor)
			self.Library:UpdateColorsUsingRegistry()
		end

		function ThemeManager:LoadDefault()
			local theme = "Default"
			local content = isfile(self.Folder .. "/default.txt") and readfile(self.Folder .. "/default.txt")

			local isDefault = true
			if content then
				if self.BuiltInThemes[content] then
					theme = content
				elseif self:GetCustomTheme(content) then
					theme = content
					isDefault = false
				end
			elseif self.BuiltInThemes[self.DefaultTheme] then
				theme = self.DefaultTheme
			end

			if isDefault then
				Options.ThemeManager_ThemeList:SetValue(theme)
			else
				self:ApplyTheme(theme)
			end
		end

		function ThemeManager:SaveDefault(theme)
			writefile(self.Folder .. "/default.txt", theme)
		end

		function ThemeManager:CreateThemeManager(groupbox)
			groupbox
				:AddLabel("Background color")
				:AddColorPicker("BackgroundColor", { Default = self.Library.BackgroundColor })
			groupbox:AddLabel("Main color"):AddColorPicker("MainColor", { Default = self.Library.MainColor })
			groupbox:AddLabel("Accent color"):AddColorPicker("AccentColor", { Default = self.Library.AccentColor })
			groupbox:AddLabel("Outline color"):AddColorPicker("OutlineColor", { Default = self.Library.OutlineColor })
			groupbox:AddLabel("Font color"):AddColorPicker("FontColor", { Default = self.Library.FontColor })

			local ThemesArray = {}
			for Name, Theme in next, self.BuiltInThemes do
				table.insert(ThemesArray, Name)
			end

			table.sort(ThemesArray, function(a, b)
				return self.BuiltInThemes[a][1] < self.BuiltInThemes[b][1]
			end)

			groupbox:AddDivider()
			groupbox:AddDropdown("ThemeManager_ThemeList", { Text = "Theme list", Values = ThemesArray, Default = 1 })

			groupbox:AddButton("Set as default", function()
				self:SaveDefault(Options.ThemeManager_ThemeList.Value)
				self.Library:Notify(string.format("Set default theme to %q", Options.ThemeManager_ThemeList.Value))
			end)

			Options.ThemeManager_ThemeList:OnChanged(function()
				self:ApplyTheme(Options.ThemeManager_ThemeList.Value)
			end)

			groupbox:AddDivider()
			groupbox:AddInput("ThemeManager_CustomThemeName", { Text = "Custom theme name" })
			groupbox:AddDropdown(
				"ThemeManager_CustomThemeList",
				{ Text = "Custom themes", Values = self:ReloadCustomThemes(), AllowNull = true, Default = 1 }
			)
			groupbox:AddDivider()

			groupbox
				:AddButton("Save theme", function()
					self:SaveCustomTheme(Options.ThemeManager_CustomThemeName.Value)

					Options.ThemeManager_CustomThemeList:SetValues(self:ReloadCustomThemes())
					Options.ThemeManager_CustomThemeList:SetValue(nil)
				end)
				:AddButton("Load theme", function()
					self:ApplyTheme(Options.ThemeManager_CustomThemeList.Value)
				end)

			groupbox:AddButton("Refresh list", function()
				Options.ThemeManager_CustomThemeList:SetValues(self:ReloadCustomThemes())
				Options.ThemeManager_CustomThemeList:SetValue(nil)
			end)

			groupbox:AddButton("Set as default", function()
				if
					Options.ThemeManager_CustomThemeList.Value ~= nil
					and Options.ThemeManager_CustomThemeList.Value ~= ""
				then
					self:SaveDefault(Options.ThemeManager_CustomThemeList.Value)
					self.Library:Notify(
						string.format("Set default theme to %q", Options.ThemeManager_CustomThemeList.Value)
					)
				end
			end)

			ThemeManager:LoadDefault()

			local function UpdateTheme()
				self:ThemeUpdate()
			end

			Options.BackgroundColor:OnChanged(UpdateTheme)
			Options.MainColor:OnChanged(UpdateTheme)
			Options.AccentColor:OnChanged(UpdateTheme)
			Options.OutlineColor:OnChanged(UpdateTheme)
			Options.FontColor:OnChanged(UpdateTheme)
		end

		function ThemeManager:GetCustomTheme(file)
			local path = self.Folder .. "/" .. file
			if not isfile(path) then
				return nil
			end

			local data = readfile(path)
			local success, decoded = pcall(httpService.JSONDecode, httpService, data)

			if not success then
				return nil
			end

			return decoded
		end

		function ThemeManager:SaveCustomTheme(file)
			if file:gsub(" ", "") == "" then
				return self.Library:Notify("Invalid file name for theme (empty)", 3)
			end

			local theme = {}
			local fields = { "FontColor", "MainColor", "AccentColor", "BackgroundColor", "OutlineColor" }

			for _, field in next, fields do
				local option = Options[field]

				theme[field] = {
					type = "ColorPicker",
					hue = option.Hue,
					sat = option.Sat,
					vib = option.Vib,
					transparency = option.Transparency,
					rainbow = option.Rainbow,
				}
			end

			writefile(self.Folder .. "/" .. file .. ".json", httpService:JSONEncode(theme))
		end

		function ThemeManager:ReloadCustomThemes()
			local list = listfiles(self.Folder)

			local out = {}
			for i = 1, #list do
				local file = list[i]
				if file:sub(-5) == ".json" then
					-- i hate this but it has to be done ...

					local pos = file:find(".json", 1, true)
					local char = file:sub(pos, pos)

					while char ~= "/" and char ~= "\\" and char ~= "" do
						pos = pos - 1
						char = file:sub(pos, pos)
					end

					if char == "/" or char == "\\" then
						table.insert(out, file:sub(pos + 1))
					end
				end
			end

			return out
		end

		function ThemeManager:SetLibrary(lib)
			self.Library = lib
		end

		function ThemeManager:BuildFolderTree()
			makefolder(self.Folder)
		end

		function ThemeManager:SetFolder(folder)
			self.Folder = folder
			self:BuildFolderTree()
		end

		function ThemeManager:CreateGroupBox(tab)
			assert(self.Library, "Must set ThemeManager.Library first!")
			return tab:AddLeftGroupbox("Theme Manager")
		end

		function ThemeManager:ApplyToTab(tab)
			assert(self.Library, "Must set ThemeManager.Library first!")
			local groupbox = self:CreateGroupBox(tab)
			self:CreateThemeManager(groupbox)
		end

		function ThemeManager:ApplyToGroupbox(groupbox)
			assert(self.Library, "Must set ThemeManager.Library first!")
			self:CreateThemeManager(groupbox)
		end

		ThemeManager:BuildFolderTree()
	end

	return ThemeManager
end)()

end)
__bundle_register("Menu/VisualsTab", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

-- Visuals tab.
local VisualsTab = {}

---Initialize ESP Customization section.
---@param groupbox table
function VisualsTab.initESPCustomization(groupbox)
	groupbox:AddSlider("FontSize", {
		Text = "ESP Font Size",
		Default = 16,
		Min = 4,
		Max = 24,
		Rounding = 0,
	})

	groupbox:AddSlider("ESPSplitLineLength", {
		Text = "ESP Split Line Length",
		Tooltip = "The total length of a ESP label line before it splits into a new line.",
		Default = 30,
		Min = 10,
		Max = 100,
		Rounding = 0,
	})

	local fonts = {}

	for _, font in next, Enum.Font:GetEnumItems() do
		if font == Enum.Font.Unknown then
			continue
		end

		table.insert(fonts, font.Name)
	end

	groupbox:AddDropdown("Font", { Text = "ESP Fonts", Default = 1, Values = fonts })
end

---Initialize ESP Optimizations section.
---@param groupbox table
function VisualsTab.initESPOptimizations(groupbox)
	groupbox:AddToggle("ESPSplitUpdates", {
		Text = "ESP Split Updates",
		Tooltip = "This is an optimization where the ESP will split updating the object pool into multiple frames.",
		Default = false,
	})

	local esuDepBox = groupbox:AddDependencyBox()

	esuDepBox:AddSlider("ESPSplitFrames", {
		Text = "ESP Split Frames",
		Tooltip = "How many frames we have to split the object pool into.",
		Suffix = "f",
		Default = 64,
		Min = 1,
		Max = 64,
		Rounding = 0,
	})

	esuDepBox:SetupDependencies({
		{ Toggles.ESPSplitUpdates, true },
	})

	groupbox:AddToggle("NoPersisentESP", {
		Text = "No Persistent ESP",
		Tooltip = "Disable ESP models from being persistent and never being streamed out.",
		Default = false,
	})
end

---Initialize Base ESP section.
---@note: Every ESP object has access to these options.
---@param identifier string
---@param groupbox table
---@return string, table, table
function VisualsTab.initBaseESPSection(identifier, groupbox)
	local enableToggle = groupbox
		:AddToggle(Configuration.identify(identifier, "Enable"), {
			Text = "Enable ESP",
			Default = false,
		})
		:AddKeyPicker(Configuration.identify(identifier, "Keybind"), {
			Default = "N/A",
			SyncToggleState = true,
			NoUI = true,
			Text = groupbox.Name,
		})

	enableToggle:AddColorPicker(Configuration.identify(identifier, "Color"), {
		Default = Color3.new(1, 1, 1),
	})

	local enableDepBox = groupbox:AddDependencyBox()

	enableDepBox:AddToggle(Configuration.identify(identifier, "ShowDistance"), {
		Text = "Show Distance",
		Default = false,
	})

	enableDepBox:AddSlider(Configuration.identify(identifier, "MaxDistance"), {
		Text = "Distance Threshold",
		Tooltip = "If the distance is greater than this value, the ESP object will not be shown.",
		Default = 2000,
		Min = 0,
		Max = 100000,
		Suffix = "studs",
		Rounding = 0,
	})

	enableDepBox:SetupDependencies({
		{ enableToggle, true },
	})

	return identifier, enableDepBox
end

---Add Player ESP section.
---@param identifier string
---@param depbox table
function VisualsTab.addPlayerESP(identifier, depbox)
	local markAlliesToggle = depbox:AddToggle(Configuration.identify(identifier, "MarkAllies"), {
		Text = "Mark Allies",
		Default = false,
	})

	markAlliesToggle:AddColorPicker(Configuration.identify(identifier, "AllyColor"), {
		Default = Color3.new(1, 1, 1),
	})

	depbox:AddToggle(Configuration.identify(identifier, "ShowHealthPercentage"), {
		Text = "Show Health Percentage",
		Default = false,
	})

	depbox:AddToggle(Configuration.identify(identifier, "ShowHealthBars"), {
		Text = "Show Health In Bars",
		Default = false,
	})

	depbox:AddToggle(Configuration.identify(identifier, "ShowUltimate"), {
		Text = "Show Ultimate Percentage",
		Default = false,
	})

	depbox:AddToggle(Configuration.identify(identifier, "ShowRace"), {
		Text = "Show Race",
		Default = false,
	})

	depbox:AddToggle(Configuration.identify(identifier, "ShowElement"), {
		Text = "Show Element",
		Default = false,
	})

	depbox:AddDropdown(Configuration.identify(identifier, "PlayerNameType"), {
		Text = "Player Name Type",
		Default = 1,
		Values = { "Character Name", "Roblox Display Name", "Roblox Username" },
	})
end

---Add Filtered ESP section.
---@param identifier string
---@param depbox table
function VisualsTab.addFilterESP(identifier, depbox)
	local filterObjectsToggle = depbox:AddToggle(Configuration.identify(identifier, "FilterObjects"), {
		Text = "Filter Objects",
		Default = true,
	})

	local foDepBox = depbox:AddDependencyBox()

	local filterLabelList = foDepBox:AddDropdown(Configuration.identify(identifier, "FilterLabelList"), {
		Text = "Filter Label List",
		Default = {},
		SaveValues = true,
		Multi = true,
		Values = {},
	})

	local filterLabel = foDepBox:AddInput(Configuration.identify(identifier, "FilterLabel"), {
		Text = "Filter Label",
		Placeholder = "Partial or exact object label.",
	})

	foDepBox:AddDropdown(Configuration.identify(identifier, "FilterLabelListType"), {
		Text = "Filter List Type",
		Default = 1,
		Values = { "Hide Labels Out Of List", "Hide Labels In List" },
	})

	foDepBox:AddButton("Add Name To Filter", function()
		local filterLabelValue = filterLabel.Value

		if #filterLabelValue <= 0 then
			return Logger.notify("Please enter a valid filter name.")
		end

		local filterLabelListValues = filterLabelList.Values

		if not table.find(filterLabelListValues, filterLabelValue) then
			table.insert(filterLabelListValues, filterLabelValue)
		end

		filterLabelList:SetValues(filterLabelListValues)
		filterLabelList:SetValue({})
		filterLabelList:Display()
	end)

	foDepBox:AddButton("Remove Selected Names", function()
		local filterLabelListValues = filterLabelList.Values
		local selectedFilterNames = filterLabelList.Value

		for selectedFilterName, _ in next, selectedFilterNames do
			local selectedIndex = table.find(filterLabelListValues, selectedFilterName)
			if not selectedIndex then
				return Logger.notify("The selected filter name %s does not exist in the list", selectedFilterName)
			end

			table.remove(filterLabelListValues, selectedIndex)
		end

		filterLabelList:SetValues(filterLabelListValues)
		filterLabelList:SetValue({})
		filterLabelList:Display()
	end)

	foDepBox:SetupDependencies({
		{ filterObjectsToggle, true },
	})
end

---Initialize Visual Removals section.
---@param groupbox table
function VisualsTab.initVisualRemovalsSection(groupbox)
	groupbox:AddToggle("NoFog", {
		Text = "No Fog",
		Tooltip = "Atmosphere and Fog effects are hidden.",
		Default = false,
	})
end

---Initialize World Visuals section.
---@param groupbox table
function VisualsTab.initWorldVisualsSection(groupbox)
	groupbox:AddToggle("ModifyFieldOfView", {
		Text = "Modify Field Of View",
		Default = false,
	})

	local fovDepBox = groupbox:AddDependencyBox()

	fovDepBox:AddSlider("FieldOfView", {
		Text = "Field Of View Slider",
		Default = 90,
		Min = 0,
		Max = 120,
		Suffix = "°",
		Rounding = 0,
	})

	fovDepBox:SetupDependencies({
		{ Toggles.ModifyFieldOfView, true },
	})

	local modifyAmbienceToggle = groupbox:AddToggle("ModifyAmbience", {
		Text = "Modify Ambience",
		Tooltip = "Modify the ambience of the game.",
		Default = false,
	})

	modifyAmbienceToggle:AddColorPicker("AmbienceColor", {
		Default = Color3.fromHex("FFFFFF"),
	})

	local oacDepBox = groupbox:AddDependencyBox()

	oacDepBox:AddToggle("OriginalAmbienceColor", {
		Text = "Original Ambience Color",
		Tooltip = "Use the game's original ambience color instead of a custom one.",
		Default = false,
	})

	local umacDepBox = oacDepBox:AddDependencyBox()

	umacDepBox:AddSlider("OriginalAmbienceColorBrightness", {
		Text = "Original Ambience Brightness",
		Default = 0,
		Min = 0,
		Max = 255,
		Suffix = "+",
		Rounding = 0,
	})

	oacDepBox:SetupDependencies({
		{ Toggles.ModifyAmbience, true },
	})

	umacDepBox:SetupDependencies({
		{ Toggles.OriginalAmbienceColor, true },
	})
end

---Initialize tab.
---@param window table
function VisualsTab.init(window)
	-- Create tab.
	local tab = window:AddTab("Visuals")

	-- Initialize sections.
	VisualsTab.initESPCustomization(tab:AddDynamicGroupbox("ESP Customization"))
	VisualsTab.initESPOptimizations(tab:AddDynamicGroupbox("ESP Optimizations"))
	VisualsTab.initWorldVisualsSection(tab:AddDynamicGroupbox("World Visuals"))
	VisualsTab.initVisualRemovalsSection(tab:AddDynamicGroupbox("Visual Removals"))
	VisualsTab.addPlayerESP(VisualsTab.initBaseESPSection("Player", tab:AddDynamicGroupbox("Player ESP")))
	VisualsTab.initBaseESPSection("Mob", tab:AddDynamicGroupbox("Mob ESP"))
	VisualsTab.initBaseESPSection("NPC", tab:AddDynamicGroupbox("NPC ESP"))
	VisualsTab.initBaseESPSection("BountyBoard", tab:AddDynamicGroupbox("Bounty Board ESP"))
	VisualsTab.initBaseESPSection("Crystal", tab:AddDynamicGroupbox("Crystal ESP"))
	VisualsTab.initBaseESPSection("MissionBoard", tab:AddDynamicGroupbox("Mission Board ESP"))
	VisualsTab.initBaseESPSection("LootOrb", tab:AddDynamicGroupbox("Loot Orb ESP"))
end

-- Return VisualsTab module.
return VisualsTab

end)
__bundle_register("Menu/BuilderTab", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Game.Timings.SaveManager
local SaveManager = require("Game/Timings/SaveManager")

---@module Menu.Objects.AnimationBuilderSection
local AnimationBuilderSection = require("Menu/Objects/AnimationBuilderSection")

---@module Menu.Objects.SoundBuilderSection
local SoundBuilderSection = require("Menu/Objects/SoundBuilderSection")

---@module Menu.Objects.PartBuilderSection
local PartBuilderSection = require("Menu/Objects/PartBuilderSection")

---@module Game.Timings.AnimationTiming
local AnimationTiming = require("Game/Timings/AnimationTiming")

---@module Game.Timings.PartTiming
local PartTiming = require("Game/Timings/PartTiming")

---@module Game.Timings.SoundTiming
local SoundTiming = require("Game/Timings/SoundTiming")

---@module Game.Timings.ModuleManager
local ModuleManager = require("Game/Timings/ModuleManager")

---@module Features.Game.AnimationVisualizer
local AnimationVisualizer = require("Features/Game/AnimationVisualizer")

---@module Features.Game.AnimationLogger
local AnimationLogger = require("Features/Game/AnimationLogger")

---@module GUI.Library
local Library = require("GUI/Library")

-- BuilderTab module.
local BuilderTab = {
	abs = nil,
	pbs = nil,
	sbs = nil,
}

---Refresh builder lists.
function BuilderTab.refresh()
	if BuilderTab.abs then
		BuilderTab.abs:reset()
		BuilderTab.abs:refresh()
	end

	if BuilderTab.pbs then
		BuilderTab.pbs:reset()
		BuilderTab.pbs:refresh()
	end

	if BuilderTab.sbs then
		BuilderTab.sbs:reset()
		BuilderTab.sbs:refresh()
	end
end

---Initialize save manager section.
---@param groupbox table
function BuilderTab.initSaveManagerSection(groupbox)
	local pasToggle = groupbox:AddToggle("PeriodicAutoSave", {
		Text = "Auto Save Periodically",
		Default = true,
	})

	local pasDepBox = groupbox:AddDependencyBox()

	pasDepBox:AddSlider("PeriodicAutoSaveInterval", {
		Text = "Auto Save Interval",
		Min = 1,
		Max = 240,
		Rounding = 0,
		Suffix = "s",
		Default = 60,
	})

	pasDepBox:SetupDependencies({
		{ pasToggle, true },
	})

	local configName = groupbox:AddInput("ConfigName", {
		Text = "Config Name",
	})

	local configList = groupbox:AddDropdown("ConfigList", {
		Text = "Config List",
		Values = SaveManager.list(),
		AllowNull = true,
	})

	groupbox
		:AddButton("Create Config", function()
			SaveManager.create(configName.Value)
			SaveManager.refresh(configList)
		end)
		:AddButton({
			Text = "Load Config",
			DoubleClick = true,
			Func = function()
				SaveManager.load(configList.Value)
				BuilderTab.refresh()
			end,
		})

	groupbox:AddButton({
		Text = "Overwrite Config",
		DoubleClick = true,
		Func = function()
			SaveManager.save(configList.Value)
		end,
	})

	groupbox:AddButton({
		Text = "Clear Config",
		DoubleClick = true,
		Func = function()
			SaveManager.clear(configList.Value)
		end,
	})

	groupbox:AddButton("Refresh List", function()
		SaveManager.refresh(configList)

		if Options.MergeConfigList then
			SaveManager.refresh(Options.MergeConfigList)
		end

		BuilderTab.refresh()
	end)

	groupbox:AddButton("Set To Auto Load", function()
		SaveManager.autoload(configList.Value)
	end)
end

---Initialize merge manager section.
---@param groupbox table
function BuilderTab.initMergeManagerSection(groupbox)
	local configList = groupbox:AddDropdown("MergeConfigList", {
		Text = "Config List",
		Values = SaveManager.list(),
		AllowNull = true,
	})

	local mergeConfigType = groupbox:AddDropdown("MergeConfigType", {
		Text = "Merge Type",
		Values = { "Add New Timings", "Overwrite and Add Everything" },
		Default = 1,
	})

	groupbox:AddButton({
		Text = "Merge With Current Config",
		DoubleClick = true,
		Func = function()
			SaveManager.merge(configList.Value, mergeConfigType.Value)
		end,
	})
end

---Initialize logger section.
---@param groupbox table
function BuilderTab.initLoggerSection(groupbox)
	local animVisualizerToggle = groupbox:AddToggle("ShowAnimationVisualizer", {
		Text = "Show Animation Visualizer",
		Default = false,
		Callback = AnimationVisualizer.visible,
	})

	animVisualizerToggle:AddKeyPicker(
		"AnimationVisualizerKeyBind",
		{ Default = "N/A", SyncToggleState = true, Text = "Animation Visualizer" }
	)

	local showLoggerToggle = groupbox:AddToggle("ShowLoggerWindow", {
		Text = "Show Logger Window",
		Default = false,
		Callback = function(value)
			Library.InfoLoggerFrame.Visible = value
		end,
	})

	showLoggerToggle:AddKeyPicker(
		"ShowLoggerWindowKeyBind",
		{ Default = "N/A", SyncToggleState = true, Text = "Logger Window" }
	)

	groupbox:AddSlider("MinimumLoggerDistance", {
		Text = "Minimum Logger Distance",
		Min = 0,
		Max = 100,
		Rounding = 0,
		Suffix = "m",
		Default = 0,
	})

	groupbox:AddSlider("MaximumLoggerDistance", {
		Text = "Maximum Logger Distance",
		Min = 0,
		Max = 1000,
		Rounding = 0,
		Suffix = "m",
		Default = 0,
	})

	local blacklistedKeys = groupbox:AddDropdown("BlacklistedKeys", {
		Text = "Blacklisted Keys",
		Default = {},
		Values = Library:KeyBlacklists(),
		Multi = true,
	})

	groupbox:AddButton("Remove Selected Keys", function()
		for selected, _ in next, blacklistedKeys.Value do
			Library.InfoLoggerData.KeyBlacklistList[selected] = nil
		end

		blacklistedKeys:SetValues(Library:KeyBlacklists())
		blacklistedKeys:SetValue({})
		blacklistedKeys:Display()
	end)
end

---Initialize animation capture section.
---@param groupbox table
function BuilderTab.initCaptureSection(groupbox)
	groupbox:AddToggle("EnableAnimationCapture", {
		Text = "Enable Animation Capture",
		Default = false,
		Tooltip = "When enabled, animations played by nearby entities are captured for timing generation.",
	})

	groupbox:AddSlider("CaptureMinDistance", {
		Text = "Capture Min Distance",
		Min = 0,
		Max = 200,
		Rounding = 0,
		Suffix = "m",
		Default = 0,
	})

	groupbox:AddSlider("CaptureMaxDistance", {
		Text = "Capture Max Distance",
		Min = 0,
		Max = 1000,
		Rounding = 0,
		Suffix = "m",
		Default = 100,
	})

	local capturedList = groupbox:AddDropdown("CapturedAnimationList", {
		Text = "Captured Animations",
		Values = {},
		AllowNull = true,
		Callback = function(value)
			if not value then
				return
			end

			local aid = value:match("%((.+)%)$")
			if not aid then
				return
			end

			AnimationVisualizer.loadId(aid)
		end,
	})

	local timingNameInput = groupbox:AddInput("GeneratedTimingName", {
		Text = "Timing Name (optional)",
		Tooltip = "Leave empty to auto-generate a name from entity + animation ID.",
	})

	local autoSaveConfigInput = groupbox:AddInput("GeneratedTimingAutoSaveConfigName", {
		Text = "Auto Save Config Name",
		Tooltip = "Optional: if set, generated timings are immediately written to this config file.",
		Placeholder = "example: rogue_autogen",
	})

	local function autoSaveGeneratedTimings()
		local configName = autoSaveConfigInput and autoSaveConfigInput.Value
		if not configName or #configName <= 0 then
			return
		end

		local code = SaveManager.write(configName)
		if code == 0 then
			Library:Notify(string.format("Auto-saved timings to '%s'.", configName))
		else
			Library:Notify(string.format("Failed to auto-save timings to '%s'.", configName))
		end
	end

	groupbox:AddButton("Refresh Captured List", function()
		capturedList:SetValues(AnimationLogger.capturedList())
		capturedList:SetValue(nil)
		capturedList:Display()
	end)

	groupbox:AddButton("Generate Timing From Selected", function()
		local selected = capturedList.Value
		if not selected then
			return Library:Notify("Select a captured animation first.")
		end

		-- Extract the animation ID from the display string "EntityName (rbxassetid://123)".
		local aid = selected:match("%((.+)%)$")
		if not aid then
			return Library:Notify("Could not parse animation ID from selection.")
		end

		local name = timingNameInput and timingNameInput.Value or nil
		local success, result = AnimationLogger.generateTiming(aid, name)

		if success then
			Library:Notify(string.format("Created timing '%s'.", result))
			autoSaveGeneratedTimings()
			BuilderTab.refresh()
		else
			Library:Notify(result)
		end
	end)

	groupbox
		:AddButton({
			Text = "Generate All Captured",
			DoubleClick = true,
			Func = function()
				local s, f = AnimationLogger.generateAll()
				Library:Notify(string.format("Generated %d timings (%d skipped/failed).", s, f))

				if s > 0 then
					autoSaveGeneratedTimings()
				end

				BuilderTab.refresh()
			end,
		})
		:AddButton({
			Text = "Clear Captured",
			DoubleClick = true,
			Func = function()
				AnimationLogger.clearCaptured()
				capturedList:SetValues({})
				capturedList:SetValue(nil)
				capturedList:Display()
				Library:Notify("Cleared all captured animations.")
			end,
		})
end

---Initialize Module Manager section.
---@param groupbox table
function BuilderTab.initModuleManagerSection(groupbox)
	local moduleList = groupbox:AddDropdown("ModuleList", {
		Text = "Module List",
		Values = ModuleManager.loaded(),
		AllowNull = true,
		Multi = false,
	})

	groupbox:AddButton("Refresh List", function()
		-- Refresh manager.
		ModuleManager.refresh()

		-- Set loaded modules.
		moduleList:SetValues(ModuleManager.loaded())
		moduleList:SetValue(nil)
		moduleList:Display()
	end)
end

---Initialize tab.
---@param window table
function BuilderTab.init(window)
	-- Create tab.
	local tab = window:AddTab("Builder")

	-- Initialize sections.
	BuilderTab.initSaveManagerSection(tab:AddDynamicGroupbox("Save Manager"))
	BuilderTab.initMergeManagerSection(tab:AddDynamicGroupbox("Merge Manager"))
	BuilderTab.initModuleManagerSection(tab:AddDynamicGroupbox("Module Manager"))
	BuilderTab.initLoggerSection(tab:AddDynamicGroupbox("Logger"))
	BuilderTab.initCaptureSection(tab:AddDynamicGroupbox("Animation Capture"))

	-- Create builder sections.
	BuilderTab.pbs = PartBuilderSection.new("Part", tab:AddDynamicTabbox(), SaveManager.ps, PartTiming.new())
	BuilderTab.abs =
		AnimationBuilderSection.new("Animation", tab:AddDynamicTabbox(), SaveManager.as, AnimationTiming.new())
	BuilderTab.sbs = SoundBuilderSection.new("Sound", tab:AddDynamicTabbox(), SaveManager.ss, SoundTiming.new())

	-- Initialize builder sections.
	BuilderTab.pbs:init()
	BuilderTab.abs:init()
	BuilderTab.sbs:init()
end

-- Return CombatTab module.
return BuilderTab

end)
__bundle_register("Menu/Objects/PartBuilderSection", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Menu.Objects.BuilderSection
local BuilderSection = require("Menu/Objects/BuilderSection")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Game.Timings.PartTiming
local PartTiming = require("Game/Timings/PartTiming")

---@class PartBuilderSection: BuilderSection
---@field partName table
---@field timingDelay table
---@field initialMinimumDistance table
---@field initialMaximumDistance table
---@field timing PartTiming
local PartBuilderSection = setmetatable({}, { __index = BuilderSection })
PartBuilderSection.__index = PartBuilderSection

---Check before writing.
---@return boolean
function PartBuilderSection:check()
	if not BuilderSection.check(self) then
		return false
	end

	if not self.partName.Value or #self.partName.Value <= 0 then
		return Logger.longNotify("Please enter a valid part name.")
	end

	if self.pair:index(self.partName.Value) then
		return Logger.longNotify("The timing ID '%s' is already in the list.", self.partName.Value)
	end

	return true
end

---Load the extra elements. Override me.
---@param timing Timing
function PartBuilderSection:exload(timing)
	self.useHitboxCFrame:SetRawValue(timing.uhc)
	self.partName:SetRawValue(timing.pname)
end

---Reset the elements. Extend me.
function PartBuilderSection:reset()
	BuilderSection.reset(self)
	self.partName:SetRawValue("")
end

---Set creation timing properties. Override me.
---@param timing PartTiming
function PartBuilderSection:cset(timing)
	timing.name = self.timingName.Value
	timing.pname = self.partName.Value
end

---Create new timing. Override me.
---@return PartTiming
function PartBuilderSection:create()
	local timing = PartTiming.new()
	self:cset(timing)
	return timing
end

---Create timing ID element. Override me.
---@param tab table
function PartBuilderSection:tide(tab)
	self.partName = tab:AddInput(nil, {
		Text = "Part Name",
	})
end

---Initialize extra tab.
---@param tab table
function PartBuilderSection:extra(tab)
	self.useHitboxCFrame = tab:AddToggle(nil, {
		Text = "Use Hitbox CFrame",
		Tooltip = "Should the hitbox face where it was originally supposed to?",
		Default = true,
		Callback = self:tnc(function(timing, value)
			timing.uhc = value
		end),
	})
end

---Initialize PartBuilderSection object.
function PartBuilderSection:init()
	self:timing()
	self:builder()
	self:action()
end

---Create new PartBuilderSection object.
---@param name string
---@param tabbox table
---@param pair TimingContainerPair
---@param timing PartTiming
---@return PartBuilderSection
function PartBuilderSection.new(name, tabbox, pair, timing)
	return setmetatable(BuilderSection.new(name, tabbox, pair, timing), PartBuilderSection)
end

-- Return PartBuilderSection module.
return PartBuilderSection

end)
__bundle_register("Menu/Objects/BuilderSection", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Game.Timings.Action
local Action = require("Game/Timings/Action")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Game.Timings.Timing
local Timing = require("Game/Timings/Timing")

---@class BuilderSection
---@note: We assume that all elements will exist in callbacks. This is why they are not explicitly set in the constructor.
---@field tabbox table
---@field pair TimingContainerPair
---@field name string
---@field timingList table
---@field timingName table
---@field timingTag table
---@field hitboxLength table
---@field hitboxWidth table
---@field hitboxHeight table
---@field timingType table
---@field punishableWindow table
---@field afterWindow table
---@field delayUntilInHitbox table
---@field initialMinimumDistance table
---@field initialMaximumDistance table
---@field actionList table
---@field actionName table
---@field actionDelay table
---@field actionType table
local BuilderSection = {}
BuilderSection.__index = BuilderSection

-- Services.
local stats = game:GetService("Stats")

---Create timing ID element. Override me.
---@param tab table
function BuilderSection:tide(tab) end

---Create extra elements. Override me.
---@param tab table
function BuilderSection:extra(tab) end

---Load the extra elements. Override me.
---@param timing Timing
function BuilderSection:exload(timing) end

---Load the extra action elements. Override me.
---@param action Action
function BuilderSection:exaload(action) end

---Action delay. Override me.
---@param base table
function BuilderSection:daction(base)
	-- The user can accidently click this input through the dropdown and override the delay.
	-- It has been moved and set to "Finished" to prevent this.
	self.actionDelay = base:AddInput(nil, {
		Text = "Action Delay",
		Numeric = true,
		Finished = true,
		Callback = self:anc(function(action, value)
			action._when = tonumber(value)
		end),
	})
end

---Reset elements. Extend me.
function BuilderSection:reset()
	-- Reset timing elements.
	self.timingName:SetRawValue("")
	self.timingType:SetRawValue("Config")
	self.timingTag:SetRawValue("Undefined")
	self.initialMaximumDistance:SetRawValue(0)
	self.punishableWindow:SetRawValue(0)
	self.afterWindow:SetRawValue(0)
	self.initialMinimumDistance:SetRawValue(0)
	self.delayUntilInHitbox:SetRawValue(false)
	self.timingHitboxHeight:SetRawValue(0)
	self.timingHitboxLength:SetRawValue(0)
	self.timingHitboxWidth:SetRawValue(0)
	self.useModuleOverActions:SetRawValue(false)
	self.skipModuleNotification:SetRawValue(false)
	self.selectedModule:SetRawValue("")
	self.skipRepeatNotification:SetRawValue(false)
	self.noDashFallback:SetRawValue(false)
	self.hitboxFacingOffset:SetRawValue(true)

	-- Reset action list.
	self:arefresh(nil)

	-- Reset action elements.
	self:raction()
end

---Check before creating new timing. Override me.
---@return boolean
function BuilderSection:check()
	if not self.timingName.Value or #self.timingName.Value <= 0 then
		return Logger.longNotify("Please enter a valid timing name.")
	end

	if self.pair:find(self.timingName.Value) then
		return Logger.longNotify("The timing '%s' already exists in the list.", self.timingName.Value)
	end

	return true
end

---Check before creating new action. Override me.
---@param timing Timing
---@return boolean
function BuilderSection:acheck(timing)
	if not self.actionName.Value or #self.actionName.Value <= 0 then
		return Logger.longNotify("Please enter a valid action name.")
	end

	if timing.actions:find(self.actionName.Value) then
		return Logger.longNotify("The action '%s' already exists in the list.", self.actionName.Value)
	end

	return true
end

---Set creation timing properties. Override me.
---@param timing Timing
function BuilderSection:cset(timing)
	timing.name = self.timingName.Value
end

---Create new timing. Override me.
---@return Timing
function BuilderSection:create()
	local timing = Timing.new()
	self:cset(timing)
	return timing
end

---Initialize action tab. Extend me.
function BuilderSection:action()
	self:baction(self.tabbox:AddTab("Action"))
end

---Reset action elements.
function BuilderSection:raction()
	self.actionName:SetRawValue("")
	self.actionDelay:SetRawValue(0)
	self.actionType:SetRawValue("Parry")
	self.hitboxHeight:SetRawValue(0)
	self.hitboxLength:SetRawValue(0)
	self.hitboxWidth:SetRawValue(0)
end

---Refresh timing list.
function BuilderSection:refresh()
	local values = self.timingType.Value == "Internal" and self.pair.internal:names() or self.pair.config:names()
	self.timingList:SetValues(values)
	self.timingList:SetValue(nil)
	self.timingList:Display()
end

---Refresh action list.
---@param timing Timing?
function BuilderSection:arefresh(timing)
	self.actionList:SetValues(timing and timing.actions:names() or {})
	self.actionList:SetValue(nil)
	self.actionList:Display()
end

---Wrap a callback that needs a timing. This will check for internal timings.
---@param callback function(Timing, ...)
---@return function(...)
function BuilderSection:tnc(callback)
	return function(...)
		-- If no value, return.
		if not self.timingList.Value then
			return Logger.warn("No timing selected.")
		end

		-- Find timing.
		local timing = self.pair:find(self.timingList.Value)
		if not timing then
			return Logger.longNotify("You must select a valid timing to perform this action.")
		end

		-- Check timing type.
		if self.timingType.Value == "Internal" then
			return Logger.longNotify("Internal timing. Changes not replicated. You must clone it to the config first.")
		end

		-- Fire callback.
		callback(timing, ...)
	end
end

---Wrap a callback that needs both an action and a timing.
---@note: This will check for internal timings.
---@param callback function(Timing, Action, ...)
---@return function
function BuilderSection:tanc(callback)
	return function(...)
		-- If no value, return.
		if not self.timingList.Value then
			return Logger.warn("No timing selected.")
		end

		-- Find timing.
		local timing = self.pair:find(self.timingList.Value)
		if not timing then
			return Logger.longNotify("You must select a valid timing to perform this action.")
		end

		-- If no value, return.
		if not self.actionList.Value then
			return Logger.warn("No action selected.")
		end

		-- Find action.
		local action = timing.actions:find(self.actionList.Value)
		if not action then
			return Logger.longNotify("You must select a valid action to perform this action.")
		end

		-- Check timing type.
		if self.timingType.Value == "Internal" then
			return Logger.longNotify("Internal timing. Changes not replicated. You must clone it to the config first.")
		end

		-- Fire callback.
		callback(timing, action, ...)
	end
end

---Wrap a callback that needs a action. This will check for internal timings.
---@param callback function(Action, ...)
---@return function
function BuilderSection:anc(callback)
	return function(...)
		-- If no value, return.
		if not self.timingList.Value then
			return Logger.warn("No timing selected.")
		end

		-- Find timing.
		local timing = self.pair:find(self.timingList.Value)
		if not timing then
			return Logger.longNotify("You must select a valid timing to perform this action.")
		end

		-- If no value, return.
		if not self.actionList.Value then
			return Logger.warn("No action selected.")
		end

		-- Find action.
		local action = timing.actions:find(self.actionList.Value)
		if not action then
			return Logger.longNotify("You must select a valid action to perform this action.")
		end

		-- Check timing type.
		if self.timingType.Value == "Internal" then
			return Logger.longNotify("Internal timing. Changes not replicated. You must clone it to the config first.")
		end

		-- Fire callback.
		callback(action, ...)
	end
end

---Initialize action base.
---@param base table
function BuilderSection:baction(base)
	self.actionList = base:AddDropdown(nil, {
		Text = "Action List",
		Values = {},
		AllowNull = true,
		Callback = self:tnc(function(timing, value)
			-- Reset action elements.
			self:raction()

			-- Check if value exists.
			if not value then
				return Logger.warn("No action value.")
			end

			-- Find action.
			local action = timing.actions:find(value)
			if not action then
				return Logger.longNotify("The selected action '%s' does not exist in the list.", value)
			end

			-- Set action elements.
			self.actionName:SetRawValue(action.name)
			self.actionDelay:SetRawValue(action._when or 0)
			self.actionType:SetRawValue(action._type)
			self.hitboxWidth:SetRawValue(action.hitbox.X)
			self.hitboxHeight:SetRawValue(action.hitbox.Y)
			self.hitboxLength:SetRawValue(action.hitbox.Z)

			-- Load extra action elements.
			self:exaload(action)
		end),
	})

	self.actionType = base:AddDropdown(nil, {
		Text = "Action Type",
		Values = { "Parry", "Dash", "Start Block", "End Block" },
		Default = 1,
		Callback = self:anc(function(action, value)
			action._type = value
		end),
	})

	self:daction(base)

	self.hitboxLength = base:AddSlider(nil, {
		Text = "Hitbox Length",
		Min = 0,
		Max = 300,
		Suffix = "s",
		Default = 0,
		Rounding = 0,
		Callback = self:anc(function(action, value)
			action.hitbox = Vector3.new(action.hitbox.X, action.hitbox.Y, value)
		end),
	})

	self.hitboxWidth = base:AddSlider(nil, {
		Text = "Hitbox Width",
		Min = 0,
		Max = 300,
		Suffix = "s",
		Default = 0,
		Rounding = 0,
		Callback = self:anc(function(action, value)
			action.hitbox = Vector3.new(value, action.hitbox.Y, action.hitbox.Z)
		end),
	})

	self.hitboxHeight = base:AddSlider(nil, {
		Text = "Hitbox Height",
		Min = 0,
		Max = 300,
		Suffix = "s",
		Default = 0,
		Rounding = 0,
		Callback = self:anc(function(action, value)
			action.hitbox = Vector3.new(action.hitbox.X, value, action.hitbox.Z)
		end),
	})

	base:AddDivider()

	self.actionName = base:AddInput(nil, {
		Text = "Action Name",
	})

	base:AddButton(
		"Create New Action",
		self:tnc(function(timing)
			-- Fetch actions.
			local actions = timing.actions

			-- Check.
			if not self:acheck(timing) then
				return
			end

			-- Create new action.
			local action = Action.new()
			action.name = self.actionName.Value
			action._type = "Parry"

			-- Record ping for telemetry.
			local network = stats:FindFirstChild("Network")
			local serverStatsItem = network and network:FindFirstChild("ServerStatsItem")
			local dataPingItem = serverStatsItem and serverStatsItem:FindFirstChild("Data Ping")

			if dataPingItem then
				action.ping = dataPingItem:GetValue()
			end

			-- Push action.
			actions:push(action)

			-- Refresh action list.
			self:arefresh(timing)

			-- Set action list value.
			self.actionList:SetValue(action.name)
			self.actionList:Display()
		end)
	)

	base:AddButton(
		"Duplicate Selected Action",
		self:tanc(function(timing, action)
			-- Fetch actions.
			local actions = timing.actions

			-- Check.
			if not self:acheck(timing) then
				return
			end

			-- Create new action.
			local newAction = action:clone()
			newAction.name = self.actionName.Value

			-- Record ping for telemetry.
			local network = stats:FindFirstChild("Network")
			local serverStatsItem = network and network:FindFirstChild("ServerStatsItem")
			local dataPingItem = serverStatsItem and serverStatsItem:FindFirstChild("Data Ping")

			if dataPingItem then
				newAction.ping = dataPingItem:GetValue()
			end

			-- Push action.
			actions:push(newAction)

			-- Refresh action list.
			self:arefresh(timing)

			-- Set action list value.
			self.actionList:SetValue(newAction.name)
			self.actionList:Display()
		end)
	)

	base:AddButton(
		"Remove Selected Action",
		self:tnc(function(timing)
			-- Get selected value.
			local selected = self.actionList.Value
			if not selected then
				return Logger.longNotify("Please select an action to remove.")
			end

			-- Fetch actions.
			local actions = timing.actions

			-- Find action.
			local action = actions:find(selected)
			if not action then
				return Logger.longNotify("The selected action '%s' does not exist in the list.", selected)
			end

			-- Remove action.
			actions:remove(action)

			-- Refresh action list.
			self:arefresh(timing)
		end)
	)
end

---Initialize timing tab.
function BuilderSection:timing()
	local tab = self.tabbox:AddTab("Timings")

	self.timingType = tab:AddDropdown(nil, {
		Text = "Timing Type",
		Values = { "Config", "Internal" },
		Default = 1,
		Callback = function()
			-- Refresh timing list.
			self:refresh()

			-- Reset elements.
			self:reset()
		end,
	})

	self.timingList = tab:AddDropdown(nil, {
		Text = "Timing List",
		Values = self.timingType.Value == "Internal" and self.pair.internal:names() or self.pair.config:names(),
		AllowNull = true,
		Callback = function(value)
			-- Reset elements.
			self:reset()

			-- Check if value exists.
			if not value then
				return Logger.warn("No timing value.")
			end

			-- Fetch timing.
			local found = self.pair:find(value)
			if not found then
				return Logger.longNotify("The selected timing '%s' does not exist in the list.", value)
			end

			-- Set timing elements.
			self.timingName:SetRawValue(found.name)
			self.timingTag:SetRawValue(found.tag)
			self.initialMaximumDistance:SetRawValue(found.imxd)
			self.initialMinimumDistance:SetRawValue(found.imdd)
			self.delayUntilInHitbox:SetRawValue(found.duih)
			self.timingHitboxLength:SetRawValue(found.hitbox.Z)
			self.timingHitboxWidth:SetRawValue(found.hitbox.X)
			self.timingHitboxHeight:SetRawValue(found.hitbox.Y)
			self.punishableWindow:SetRawValue(found.punishable)
			self.afterWindow:SetRawValue(found.after)
			self.useModuleOverActions:SetRawValue(found.umoa)
			self.skipModuleNotification:SetRawValue(found.smn)
			self.selectedModule:SetRawValue(found.smod)
			self.skipRepeatNotification:SetRawValue(found.srpn)
			self.hitboxFacingOffset:SetRawValue(found.fhb)
			self.noDashFallback:SetRawValue(found.ndfb)

			-- Load extra elements.
			self:exload(found)

			-- Refresh action list.
			self:arefresh(found)
		end,
	})

	tab:AddDivider()

	self.timingName = tab:AddInput(nil, {
		Text = "Timing Name",
		Finished = true,
	})

	self:tide(tab)

	local configDepBox = tab:AddDependencyBox()

	configDepBox:AddButton("Create New Timing", function()
		-- Fetch config.
		local config = self.pair.config

		-- Check if we can successfully create a timing from the given data.
		if not self:check() then
			return
		end

		-- Create new timing.
		local timing = self:create()

		-- Push new timing.
		config:push(timing)

		-- Refresh timing list.
		self:refresh()

		-- Set timing list value.
		self.timingList:SetValue(timing.name)
		self.timingList:Display()
	end)

	configDepBox:AddButton(
		"Duplicate Selected Timing",
		self:tnc(function(found)
			-- Fetch config.
			local config = self.pair.config

			-- Check if we can successfully create a timing from the given data.
			if not self:check() then
				return
			end

			-- Clone new timing.
			local timing = found:clone()

			-- Set creation properties.
			self:cset(timing)

			-- Push new timing.
			config:push(timing)

			-- Refresh timing list.
			self:refresh()

			-- Set timing list value.
			self.timingList:SetValue(timing.name)
			self.timingList:Display()
		end)
	)

	local internalDepBox = tab:AddDependencyBox()

	internalDepBox:AddButton("Clone To Config", function()
		-- Fetch name.
		local name = self.timingList.Value
		if not name then
			return Logger.longNotify("Please select a timing to clone.")
		end

		-- Fetch data.
		local internal = self.pair.internal
		local config = self.pair.config

		-- Fetch the currently selected timing.
		local found = internal:find(name)
		if not found then
			return Logger.longNotify("The selected timing '%s' does not exist in the list.", name)
		end

		-- Check for existing ID.
		if config.timings[found:id()] then
			return Logger.longNotify("The timing ID '%s' already exists in the config.", found:id())
		end

		-- Check for existing timing.
		if config:find(found.name) then
			return Logger.longNotify("The timing name '%s' already exists in the config.", found.name)
		end

		-- Clone timing.
		---@note: No need to refresh after this. It's in the other timing list!
		config:push(internal:clone(found))
	end)

	tab:AddButton("Remove Selected Timing", function()
		-- Fetch name.
		local name = self.timingList.Value
		if not name then
			return Logger.longNotify("Please select a timing to remove.")
		end

		-- Fetch data.
		local internal = self.pair.internal
		local config = self.pair.config
		local found = config:find(name)

		-- Check if internal.
		---@todo: Implement functionality to remove internal timings.
		if internal:find(name) then
			return Logger.longNotify("You cannot remove internal timings, only override them.")
		end

		-- Check if found.
		if not found then
			return Logger.longNotify("The selected timing '%s' does not exist in the list.", name)
		end

		-- Remove timing.
		config:remove(found)

		-- Refresh timing list.
		self:refresh()
	end)

	configDepBox:SetupDependencies({
		{ self.timingType, "Config" },
	})

	internalDepBox:SetupDependencies({
		{ self.timingType, "Internal" },
	})
end

---Initialize builder tab.
function BuilderSection:builder()
	local tab = self.tabbox:AddTab(string.format("%s", self.name))

	self.timingTag = tab:AddDropdown(nil, {
		Text = "Timing Tag",
		Values = { "Undefined", "Critical", "Mantra", "M1" },
		Default = 1,
		Callback = self:tnc(function(timing, value)
			timing.tag = value
		end),
	})

	self.initialMinimumDistance = tab:AddSlider(nil, {
		Text = "Initial Minimum Distance",
		Min = 0,
		Max = 300,
		Suffix = "s",
		Default = 0,
		Rounding = 0,
		Callback = self:tnc(function(timing, value)
			timing.imdd = value
		end),
	})

	self.initialMaximumDistance = tab:AddSlider(nil, {
		Text = "Initial Maximum Distance",
		Min = 0,
		Max = 2500,
		Suffix = "s",
		Default = 1000,
		Rounding = 0,
		Callback = self:tnc(function(timing, value)
			timing.imxd = value
		end),
	})

	self.punishableWindow = tab:AddSlider(nil, {
		Text = "Punishable Window",
		Min = 0,
		Max = 2,
		Default = 0.6,
		Suffix = "s",
		Rounding = 1,
		Callback = self:tnc(function(timing, value)
			timing.punishable = value
		end),
	})

	self.afterWindow = tab:AddSlider(nil, {
		Text = "After Window",
		Min = 0,
		Max = 1,
		Default = 0.1,
		Suffix = "s",
		Rounding = 2,
		Callback = self:tnc(function(timing, value)
			timing.after = value
		end),
	})

	self.delayUntilInHitbox = tab:AddToggle(nil, {
		Text = "Delay Until In Hitbox",
		Default = false,
		Callback = self:tnc(function(timing, value)
			timing.duih = value
		end),
	})

	local duihDepBox = tab:AddDependencyBox()

	self.timingHitboxLength = duihDepBox:AddSlider(nil, {
		Text = "Hitbox Length",
		Min = 0,
		Max = 300,
		Suffix = "s",
		Default = 0,
		Rounding = 0,
		Callback = self:tnc(function(timing, value)
			timing.hitbox = Vector3.new(timing.hitbox.X, timing.hitbox.Y, value)
		end),
	})

	self.timingHitboxWidth = duihDepBox:AddSlider(nil, {
		Text = "Hitbox Width",
		Min = 0,
		Max = 300,
		Suffix = "s",
		Default = 0,
		Rounding = 0,
		Callback = self:tnc(function(timing, value)
			timing.hitbox = Vector3.new(value, timing.hitbox.Y, timing.hitbox.Z)
		end),
	})

	self.timingHitboxHeight = duihDepBox:AddSlider(nil, {
		Text = "Hitbox Height",
		Min = 0,
		Max = 300,
		Suffix = "s",
		Default = 0,
		Rounding = 0,
		Callback = self:tnc(function(timing, value)
			timing.hitbox = Vector3.new(timing.hitbox.X, value, timing.hitbox.Z)
		end),
	})

	duihDepBox:SetupDependencies({
		{ self.delayUntilInHitbox, true },
	})

	self.useModuleOverActions = tab:AddToggle(nil, {
		Text = "Use Module Over Actions",
		Default = false,
		Callback = self:tnc(function(timing, value)
			timing.umoa = value
		end),
	})

	self.skipRepeatNotification = tab:AddToggle(nil, {
		Text = "Skip Repeat Notification",
		Default = false,
		Callback = self:tnc(function(timing, value)
			timing.srpn = value
		end),
	})

	self.hitboxFacingOffset = tab:AddToggle(nil, {
		Text = "Hitbox Facing Offset",
		Tooltip = "Should the hitbox be offset towards the facing direction?",
		Default = true,
		Callback = self:tnc(function(timing, value)
			timing.fhb = value
		end),
	})

	self.noDashFallback = tab:AddToggle(nil, {
		Text = "No Dash Fallback",
		Tooltip = "If enabled, the timing will not fallback to a dash if the parry action is not available.",
		Default = false,
		Callback = self:tnc(function(timing, value)
			timing.ndfb = value
		end),
	})

	local umoaDepBox = tab:AddDependencyBox()

	self.skipModuleNotification = umoaDepBox:AddToggle(nil, {
		Text = "Skip Module Notification",
		Default = false,
		Callback = self:tnc(function(timing, value)
			timing.smn = value
		end),
	})

	self.selectedModule = umoaDepBox:AddInput(nil, {
		Text = "Selected Module",
		Finished = true,
		Callback = self:tnc(function(timing, value)
			timing.smod = value
		end),
	})

	umoaDepBox:SetupDependencies({
		{ self.useModuleOverActions, true },
	})

	self:extra(tab)
end

---Initialize BuilderSection object.
function BuilderSection:init()
	self:timing()
	self:builder()
	self:action()
end

---Create new BuilderSection object.
---@param name string
---@param tabbox table
---@param pair TimingContainerPair
---@param timing Timing
---@return BuilderSection
function BuilderSection.new(name, tabbox, pair, timing)
	local self = setmetatable({}, BuilderSection)
	self.name = name
	self.tabbox = tabbox
	self.pair = pair
	return self
end

-- Return BuilderSection module.
return BuilderSection

end)
__bundle_register("Menu/Objects/SoundBuilderSection", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Menu.Objects.BuilderSection
local BuilderSection = require("Menu/Objects/BuilderSection")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Game.Timings.SoundTiming
local SoundTiming = require("Game/Timings/SoundTiming")

---@class SoundBuilderSection: BuilderSection
---@field soundId table
---@field repeatStartDelay table
---@field repeatUntilParryEnd table
---@field repeatParryDelay table
---@field timing SoundTiming
local SoundBuilderSection = setmetatable({}, { __index = BuilderSection })
SoundBuilderSection.__index = SoundBuilderSection

---Create timing ID element. Override me.
---@param tab table
function SoundBuilderSection:tide(tab)
	self.soundId = tab:AddInput(nil, {
		Text = "Sound ID",
	})
end

---Load the extra elements. Override me.
---@param timing Timing
function SoundBuilderSection:exload(timing)
	self.soundId:SetRawValue(timing._id)
	self.repeatStartDelay:SetRawValue(timing._rsd)
	self.repeatUntilParryEnd:SetRawValue(timing.rpue)
	self.repeatParryDelay:SetRawValue(timing._rpd)
end

---Reset the elements. Extend me.
function SoundBuilderSection:reset()
	BuilderSection.reset(self)
	self.soundId:SetRawValue("")
	self.repeatParryDelay:SetRawValue(0)
	self.repeatStartDelay:SetRawValue(0)
	self.repeatUntilParryEnd:SetRawValue(false)
end

---Check before creating new timing. Override me.
---@return boolean
function SoundBuilderSection:check()
	if not BuilderSection.check(self) then
		return false
	end

	if not self.soundId.Value or #self.soundId.Value <= 0 then
		return Logger.longNotify("Please enter a valid sound ID.")
	end

	if self.pair:index(self.soundId.Value) then
		return Logger.longNotify("The timing ID '%s' is already in the list.", self.soundId.Value)
	end

	return true
end

---Set creation timing properties. Override me.
---@param timing SoundTiming
function SoundBuilderSection:cset(timing)
	timing.name = self.timingName.Value
	timing._id = self.soundId.Value
end

---Create new timing. Override me.
---@return Timing
function SoundBuilderSection:create()
	local timing = SoundTiming.new()
	self:cset(timing)
	return timing
end

---Initialize action tab.
function SoundBuilderSection:action()
	local tab = self.tabbox:AddTab("Action")

	self.repeatUntilParryEnd = tab:AddToggle(nil, {
		Text = "Repeat Parry Until End",
		Default = false,
		Callback = self:tnc(function(timing, value)
			timing.rpue = value
		end),
	})

	local depBoxOn = tab:AddDependencyBox()

	self.repeatStartDelay = depBoxOn:AddInput(nil, {
		Text = "Repeat Start Delay",
		Default = false,
		Callback = self:tnc(function(timing, value)
			timing._rsd = tonumber(value) or 0
		end),
	})

	self.repeatParryDelay = depBoxOn:AddInput(nil, {
		Text = "Repeat Parry Delay",
		Numeric = true,
		Callback = self:tnc(function(timing, value)
			timing._rpd = tonumber(value) or 0
		end),
	})

	local depBoxOff = tab:AddDependencyBox()

	self:baction(depBoxOff)

	depBoxOn:SetupDependencies({
		{ self.repeatUntilParryEnd, true },
	})

	depBoxOff:SetupDependencies({
		{ self.repeatUntilParryEnd, false },
	})
end

---Create new SoundBuilderSection object.
---@param name string
---@param tabbox table
---@param pair TimingContainerPair
---@param timing SoundTiming
---@return SoundBuilderSection
function SoundBuilderSection.new(name, tabbox, pair, timing)
	return setmetatable(BuilderSection.new(name, tabbox, pair, timing), SoundBuilderSection)
end

-- Return SoundBuilderSection module.
return SoundBuilderSection

end)
__bundle_register("Menu/Objects/AnimationBuilderSection", function(require, _LOADED, __bundle_register, __bundle_modules)
---@module Menu.Objects.BuilderSection
local BuilderSection = require("Menu/Objects/BuilderSection")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Game.Timings.AnimationTiming
local AnimationTiming = require("Game/Timings/AnimationTiming")

---@class AnimationBuilderSection: BuilderSection
---@field animationId table
---@field repeatStartDelay table
---@field repeatUntilParryEnd table
---@field repeatParryDelay table
---@field timing AnimationTiming
local AnimationBuilderSection = setmetatable({}, { __index = BuilderSection })
AnimationBuilderSection.__index = AnimationBuilderSection

---Create timing ID element. Override me.
---@param tab table
function AnimationBuilderSection:tide(tab)
	self.animationId = tab:AddInput(nil, {
		Text = "Animation ID",
	})
end

---Load the extra elements. Override me.
---@param timing AnimationTiming
function AnimationBuilderSection:exload(timing)
	self.animationId:SetRawValue(timing._id)
	self.repeatUntilParryEnd:SetRawValue(timing.rpue)
	self.repeatStartDelay:SetRawValue(timing._rsd)
	self.repeatParryDelay:SetRawValue(timing._rpd)
	self.hyperarmor:SetRawValue(timing.ha)
	self.ignoreAnimationEnd:SetRawValue(timing.iae)
	self.ignoreEarlyAnimationEnd:SetRawValue(timing.ieae)
	self.maxAnimationTimeout:SetRawValue(timing.mat)
	self.pastHitboxDetection:SetRawValue(timing.phd)
	self.predictFacingHitboxes:SetRawValue(timing.pfh)
	self.historySeconds:SetRawValue(timing.phds)
	self.extrapolationTime:SetRawValue(timing.pfht)
end

---Reset the elements. Extend me.
function AnimationBuilderSection:reset()
	BuilderSection.reset(self)
	self.animationId:SetRawValue("")
	self.repeatParryDelay:SetRawValue(0)
	self.repeatStartDelay:SetRawValue(0)
	self.repeatUntilParryEnd:SetRawValue(false)
	self.hyperarmor:SetRawValue(false)
	self.hitboxFacingOffset:SetRawValue(true)
	self.ignoreAnimationEnd:SetRawValue(false)
	self.ignoreEarlyAnimationEnd:SetRawValue(false)
	self.maxAnimationTimeout:SetRawValue(2000)
	self.pastHitboxDetection:SetRawValue(false)
	self.historySeconds:SetRawValue(0.5)
	self.predictFacingHitboxes:SetRawValue(false)
	self.extrapolationTime:SetRawValue(0.15)
end

---Check before creating new timing. Override me.
---@return boolean
function AnimationBuilderSection:check()
	if not BuilderSection.check(self) then
		return false
	end

	if not self.animationId.Value or #self.animationId.Value <= 0 then
		return Logger.longNotify("Please enter a valid animation ID.")
	end

	local timing = self.pair:index(self.animationId.Value)
	if timing then
		return Logger.longNotify("The timing ID '%s' (%s) is already in the list.", self.animationId.Value, timing.name)
	end

	return true
end

---Set creation timing properties. Override me.
---@param timing AnimationTiming
function AnimationBuilderSection:cset(timing)
	timing.name = self.timingName.Value
	timing._id = self.animationId.Value
end

---Create new timing. Override me.
---@return Timing
function AnimationBuilderSection:create()
	local timing = AnimationTiming.new()
	self:cset(timing)
	return timing
end

---Initialize extra tab.
---@param tab table
function AnimationBuilderSection:extra(tab)
	self.hyperarmor = tab:AddToggle(nil, {
		Text = "Hyperarmor Flag",
		Tooltip = "Is this timing not able to be interrupted by attacks during the animation?",
		Default = false,
		Callback = self:tnc(function(timing, value)
			timing.ha = value
		end),
	})

	self.ignoreAnimationEnd = tab:AddToggle(nil, {
		Text = "Ignore Animation End",
		Tooltip = "Should the timing ignore the end of the animation?",
		Default = false,
		Callback = self:tnc(function(timing, value)
			timing.iae = value
		end),
	})

	local depBoxEnd = tab:AddDependencyBox()

	self.maxAnimationTimeout = depBoxEnd:AddInput(nil, {
		Text = "Max Animation Timeout",
		Tooltip = "The maximum time (in milliseconds) that the animation is allowed to run with no end check.",
		Default = 2000,
		Numeric = true,
		Callback = self:tnc(function(timing, value)
			timing.mat = tonumber(value)
		end),
	})

	depBoxEnd:SetupDependencies({
		{ self.ignoreAnimationEnd, true },
	})

	self.ignoreEarlyAnimationEnd = tab:AddToggle(nil, {
		Text = "Ignore Early Animation End",
		Tooltip = "Should the timing ignore the early end of the animation?",
		Default = false,
		Callback = self:tnc(function(timing, value)
			timing.ieae = value
		end),
	})

	self.pastHitboxDetection = tab:AddToggle(nil, {
		Text = "Past Hitbox Detection",
		Default = false,
		Tooltip = "Should the hitbox detection track the past hitboxes too?",
		Callback = self:tnc(function(timing, value)
			timing.phd = value
		end),
	})

	local pfdOffDepBox = tab:AddDependencyBox()

	self.historySeconds = pfdOffDepBox:AddSlider(nil, {
		Text = "History Seconds",
		Tooltip = "How far back in seconds should we fetch history?",
		Default = 0.5,
		Min = 0,
		Max = 3.0,
		Rounding = 2,
		Numeric = true,
		Callback = self:tnc(function(timing, value)
			timing.phds = tonumber(value) or 0
		end),
	})

	pfdOffDepBox:SetupDependencies({
		{ self.pastHitboxDetection, true },
	})

	self.predictFacingHitboxes = tab:AddToggle(nil, {
		Text = "Predict Facing Hitboxes",
		Default = false,
		Tooltip = "Should we make a prediction on the facing direction and make a hitbox on that?",
		Callback = self:tnc(function(timing, value)
			timing.pfh = value
		end),
	})

	self.disablePrediction = tab:AddToggle(nil, {
		Text = "Disable Prediction",
		Default = false,
		Tooltip = "Should we disable prediction?",
		Callback = self:tnc(function(timing, value)
			timing.dp = value
		end),
	})

	self.extrapolationTime = tab:AddSlider(nil, {
		Text = "Extrapolation Time",
		Tooltip = "The time (in seconds) to extrapolate by.",
		Default = 0.15,
		Min = 0,
		Max = 2.0,
		Rounding = 3,
		Numeric = true,
		Callback = self:tnc(function(timing, value)
			timing.pfht = tonumber(value)
		end),
	})
end

---Initialize action tab.
function AnimationBuilderSection:action()
	local tab = self.tabbox:AddTab("Action")

	self.repeatUntilParryEnd = tab:AddToggle(nil, {
		Text = "Repeat Parry Until End",
		Default = false,
		Callback = self:tnc(function(timing, value)
			timing.rpue = value
		end),
	})

	local depBoxOn = tab:AddDependencyBox()

	self.repeatStartDelay = depBoxOn:AddInput(nil, {
		Text = "Repeat Start Delay",
		Numeric = true,
		Finished = true,
		Callback = self:tnc(function(timing, value)
			timing._rsd = tonumber(value) or 0
		end),
	})

	self.repeatParryDelay = depBoxOn:AddInput(nil, {
		Text = "Repeat Parry Delay",
		Numeric = true,
		Finished = true,
		Callback = self:tnc(function(timing, value)
			timing._rpd = tonumber(value) or 0
		end),
	})

	local depBoxOff = tab:AddDependencyBox()

	self:baction(depBoxOff)

	depBoxOn:SetupDependencies({
		{ self.repeatUntilParryEnd, true },
	})

	depBoxOff:SetupDependencies({
		{ self.repeatUntilParryEnd, false },
	})
end

---Create new AnimationBuilderSection object.
---@param name string
---@param tabbox table
---@param pair TimingContainerPair
---@param timing AnimationTiming
---@return AnimationBuilderSection
function AnimationBuilderSection.new(name, tabbox, pair, timing)
	return setmetatable(BuilderSection.new(name, tabbox, pair, timing), AnimationBuilderSection)
end

-- Return AnimationBuilderSection module.
return AnimationBuilderSection

end)
__bundle_register("Menu/GameTab", function(require, _LOADED, __bundle_register, __bundle_modules)
-- GameTab module.
local GameTab = {}

-- Services.
local players = game:GetService("Players")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---Initialize local character section.
---@param groupbox table
function GameTab.initLocalCharacterSection(groupbox)
	local speedHackToggle = groupbox:AddToggle("Speedhack", {
		Text = "Speedhack",
		Tooltip = "Modify your character's velocity while moving.",
		Default = false,
	})

	speedHackToggle:AddKeyPicker("SpeedhackKeybind", { Default = "N/A", SyncToggleState = true, Text = "Speedhack" })

	local speedDepBox = groupbox:AddDependencyBox()

	speedDepBox:AddSlider("SpeedhackSpeed", {
		Text = "Speedhack Speed",
		Default = 200,
		Min = 0,
		Max = 300,
		Suffix = "/s",
		Rounding = 0,
	})

	local flyToggle = groupbox:AddToggle("Fly", {
		Text = "Fly",
		Tooltip = "Set your character's velocity while moving to imitate flying.",
		Default = false,
	})

	flyToggle:AddKeyPicker("FlyKeybind", { Default = "N/A", SyncToggleState = true, Text = "Fly" })

	local flyDepBox = groupbox:AddDependencyBox()

	flyDepBox:AddSlider("FlySpeed", {
		Text = "Fly Speed",
		Default = 200,
		Min = 0,
		Max = 450,
		Suffix = "/s",
		Rounding = 0,
	})

	flyDepBox:AddSlider("FlyUpSpeed", {
		Text = "Spacebar Fly Speed",
		Default = 150,
		Min = 0,
		Max = 300,
		Suffix = "/s",
		Rounding = 0,
	})

	local noclipToggle = groupbox:AddToggle("NoClip", {
		Text = "NoClip",
		Tooltip = "Disable collision(s) for your character.",
		Default = false,
	})

	noclipToggle:AddKeyPicker("NoClipKeybind", { Default = "N/A", SyncToggleState = true, Text = "NoClip" })

	local infJumpToggle = groupbox:AddToggle("InfiniteJump", {
		Text = "Infinite Jump",
		Tooltip = "Boost your velocity while the jump key is held.",
		Default = false,
	})

	infJumpToggle:AddKeyPicker(
		"InfiniteJumpKeybind",
		{ Default = "N/A", SyncToggleState = true, Text = "Infinite Jump" }
	)

	local infiniteJumpDepBox = groupbox:AddDependencyBox()

	infiniteJumpDepBox:AddSlider("InfiniteJumpBoost", {
		Text = "Infinite Jump Boost",
		Default = 50,
		Min = 0,
		Max = 500,
		Suffix = "/s",
		Rounding = 0,
	})

	local fssbToggle = groupbox:AddToggle("FlashstepSpeedBoost", {
		Text = "Flashstep Speed Boost",
		Tooltip = "Increase your character's speed while using flashstep.",
		Default = false,
	})

	local fssbDepBox = groupbox:AddDependencyBox()

	fssbDepBox:AddSlider("FlashStepSpeedBoostMulti", {
		Text = "Speed Boost Multiplier",
		Default = 1,
		Min = 0,
		Max = 10,
		Suffix = "x",
		Rounding = 2,
	})

	fssbDepBox:SetupDependencies({
		{ fssbToggle, true },
	})

	fssbToggle:AddKeyPicker("FlashstepSpeedBoostKeybind", {
		Default = "N/A",
		SyncToggleState = true,
		Text = "Flashstep Speed Boost",
	})

	local atbToggle = groupbox:AddToggle("AttachToBack", {
		Text = "Attach To Back",
		Tooltip = "Start following the nearest entity based on a distance and height offset.",
		Default = false,
	})

	atbToggle:AddKeyPicker("AttachToBackKeybind", { Default = "N/A", SyncToggleState = true, Text = "Attach To Back" })

	local atbDepBox = groupbox:AddDependencyBox()

	atbDepBox:AddSlider("BackOffset", {
		Text = "Distance To Entity",
		Default = 5,
		Min = -30,
		Max = 30,
		Suffix = "studs",
		Rounding = 0,
	})

	atbDepBox:AddSlider("HeightOffset", {
		Text = "Height Offset",
		Default = 0,
		Min = -30,
		Max = 30,
		Suffix = "studs",
		Rounding = 0,
	})

	groupbox:AddToggle("AnchorCharacter", {
		Text = "Anchor Character",
		Default = false,
	})

	atbDepBox:SetupDependencies({
		{ Toggles.AttachToBack, true },
	})

	infiniteJumpDepBox:SetupDependencies({
		{ Toggles.InfiniteJump, true },
	})

	speedDepBox:SetupDependencies({
		{ Toggles.Speedhack, true },
	})

	flyDepBox:SetupDependencies({
		{ Toggles.Fly, true },
	})

	groupbox:AddButton({
		Text = "Respawn Character",
		DoubleClick = true,
		Func = function()
			local character = players.LocalPlayer.Character
			if not character then
				return
			end

			local humanoid = character:FindFirstChild("Humanoid")
			if not humanoid then
				return
			end

			humanoid.Health = 0
		end,
	})

	groupbox:AddButton("Redeem Codes", function()
		local codes = {
			"yayfirstweekly",
			"baragganintorisingswallow",
			"tmrfrthistimeonshredsylife",
			"canyouletusbalance",
			"vdekuglobalban",
			"jambajuice1v1",
			"butisitenough",
			"codecodecode",
			"codelolhaha",
			"codeofdoom",
			"600MVisits",
			"300KLikes",
			"serverlistfixed",
			"thosewhoknowemblem",
			"superduperfunsecretcode",
			"wowshutdowncodeyeah",
			"yesterdayshutdown",
			"thanksfor900k",
			"setrona1vertagzeu0",
			"excaliburfool",
			"higuyscode",
			"800kcodeyeah",
			"mythoughtsonthislater",
			"privateservercompensation",
			"codeforshutdownisuppose",
		}

		local localPlayer = players.LocalPlayer
		local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
		local characterHandler = character:WaitForChild("CharacterHandler")
		local remotes = characterHandler:WaitForChild("Remotes")
		local codesRemote = remotes:WaitForChild("Codes")

		for _, code in next, codes do
			local success, result = nil, nil

			repeat
				-- Invoke.
				success, result = codesRemote:InvokeServer(code)

				-- Wait.
				task.wait(0.5)
			until result ~= nil

			Logger.notify(
				"(%s, %s) Code '%s' has been attempted to be redeemed.",
				tostring(success),
				tostring(result),
				code
			)
		end
	end)
end

---Initialize player monitoring section.
---@param groupbox table
function GameTab.initPlayerMonitoringSection(groupbox)
	groupbox:AddToggle("NotifyMod", {
		Text = "Mod Notifications",
		Default = false,
	})

	local nmDepBox = groupbox:AddDependencyBox()

	nmDepBox:AddToggle("NotifyModSound", {
		Text = "Mod Notification Sound",
		Tooltip = "Use a sound along with the mod notification.",
		Default = false,
	})

	local nmbDepBox = nmDepBox:AddDependencyBox()

	nmbDepBox:AddSlider("NotifyModSoundVolume", {
		Text = "Sound Volume",
		Default = 10,
		Min = 0,
		Max = 20,
		Suffix = "v",
		Rounding = 2,
	})

	nmbDepBox:SetupDependencies({
		{ Toggles.NotifyModSound, true },
	})

	nmDepBox:SetupDependencies({
		{ Toggles.NotifyMod, true },
	})

	groupbox:AddToggle("PlayerSpectating", {
		Text = "Player List Spectating",
		Tooltip = "Click on a player on the player list to spectate them.",
		Default = false,
	})

	groupbox:AddToggle("ShowRobloxChat", {
		Text = "Show Roblox Chat",
		Default = false,
	})

	groupbox:AddToggle("ShowOwnership", {
		Text = "Show Network Ownership",
		Default = false,
	})

	groupbox:AddToggle("PlayerProximity", {
		Text = "Player Proximity Notifications",
		Tooltip = "When other players are within specified distance, notify the user.",
		Default = false,
	})

	local ppDepBox = groupbox:AddDependencyBox()

	ppDepBox:AddSlider("PlayerProximityRange", {
		Text = "Player Proximity Distance",
		Default = 1000,
		Min = 50,
		Max = 2500,
		Suffix = "studs",
		Rounding = 0,
	})

	ppDepBox:AddToggle("PlayerProximityBeep", {
		Text = "Play Beep Sound",
		Tooltip = "Use a beep sound along with the proximity notification.",
		Default = false,
	})

	local ppbDepBox = ppDepBox:AddDependencyBox()

	ppbDepBox:AddSlider("PlayerProximityBeepVolume", {
		Text = "Beep Sound Volume",
		Default = 0.1,
		Min = 0,
		Max = 10,
		Suffix = "v",
		Rounding = 2,
	})

	ppbDepBox:SetupDependencies({
		{ Toggles.PlayerProximityBeep, true },
	})

	ppDepBox:SetupDependencies({
		{ Toggles.PlayerProximity, true },
	})
end

---Initialize effect removals section.
---@param groupbox table
function GameTab.initEffectRemovalsSection(groupbox)
	groupbox:AddToggle("NoSlow", {
		Text = "No Slowdown",
		Tooltip = "Prevent the game from freezing your walkspeed or slowing you down.",
		Default = false,
	})
end

---Initialize instance removals.
---@param groupbox table
function GameTab.initInstanceRemovalsSection(groupbox)
	groupbox:AddToggle("NoRaidMusic", {
		Text = "No Raid Music",
		Tooltip = "Mute any 'Raid Music' sounds on the client.",
		Default = false,
	})
end

---Debugging section.
---@param groupbox table
function GameTab.initDebuggingSection(groupbox)
	groupbox:AddToggle("ShowDebugInformation", {
		Text = "Show Debug Information",
		Default = false,
	})
end

---Initialize tab.
function GameTab.init(window)
	-- Create tab.
	local tab = window:AddTab("Game")

	-- Initialize sections.
	GameTab.initDebuggingSection(tab:AddDynamicGroupbox("Debugging"))
	GameTab.initPlayerMonitoringSection(tab:AddDynamicGroupbox("Player Monitoring"))
	GameTab.initLocalCharacterSection(tab:AddDynamicGroupbox("Local Character"))
	GameTab.initInstanceRemovalsSection(tab:AddDynamicGroupbox("Instance Removals"))
	GameTab.initEffectRemovalsSection(tab:AddDynamicGroupbox("Effect Removals"))
end

-- Return GameTab module.
return GameTab

end)
__bundle_register("Menu/CombatTab", function(require, _LOADED, __bundle_register, __bundle_modules)
-- CombatTab module.
local CombatTab = {}

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Features.Combat.Defense
local Defense = require("Features/Combat/Defense")

-- Initialize combat targeting section.
---@param tab table
function CombatTab.initCombatTargetingSection(tab)
	tab:AddDropdown("PlayerSelectionType", {
		Text = "Player Selection Type",
		Values = {
			"Closest In Distance",
			"Closest To Crosshair",
			"Least Health",
		},
		Default = 1,
	})

	tab:AddSlider("FOVLimit", {
		Text = "Player FOV Limit",
		Min = 0,
		Max = 180,
		Default = 180,
		Suffix = "°",
		Rounding = 0,
	})

	tab:AddSlider("DistanceLimit", {
		Text = "Distance Limit",
		Min = 0,
		Max = 10000,
		Default = 3000,
		Suffix = "s",
		Rounding = 0,
	})

	tab:AddSlider("MaxTargets", {
		Text = "Max Targets",
		Min = 1,
		Max = 64,
		Default = 4,
		Rounding = 0,
	})

	tab:AddToggle("IgnorePlayers", {
		Text = "Ignore Players",
		Default = false,
	})

	tab:AddToggle("IgnoreMobs", {
		Text = "Ignore Mobs",
		Default = false,
	})

	tab:AddToggle("IgnoreAllies", {
		Text = "Ignore Allies",
		Default = false,
	})
end

-- Initialize combat whitelist section.
---@param tab table
function CombatTab.initCombatWhitelistSection(tab)
	local usernameList = tab:AddDropdown("UsernameList", {
		Text = "Username List",
		Values = {},
		SaveValues = true,
		Multi = true,
		AllowNull = true,
	})

	local usernameInput = tab:AddInput("UsernameInput", {
		Text = "Username Input",
		Placeholder = "Display name or username.",
	})

	tab:AddButton("Add Username To Whitelist", function()
		local username = usernameInput.Value
		if #username <= 0 then
			return Logger.longNotify("Please enter a valid username.")
		end

		local values = usernameList.Values
		if not table.find(values, username) then
			table.insert(values, username)
		end

		usernameList:SetValues(values)
		usernameList:SetValue({})
		usernameList:Display()
	end)

	tab:AddButton("Remove Selected Usernames", function()
		local values = usernameList.Values
		local value = usernameList.Value

		for selected, _ in next, value do
			local index = table.find(values, selected)
			if not index then
				continue
			end

			table.remove(values, index)
		end

		usernameList:SetValues(values)
		usernameList:SetValue({})
		usernameList:Display()
	end)
end

-- Initialize auto defense section.
---@param groupbox table
function CombatTab.initAutoDefenseSection(groupbox)
	local autoDefenseToggle = groupbox:AddToggle("EnableAutoDefense", {
		Text = "Enable Auto Defense",
		Default = false,
	})

	autoDefenseToggle:AddKeyPicker(
		"EnableAutoDefenseKeybind",
		{ Default = "N/A", SyncToggleState = true, Text = "Auto Defense" }
	)

	local autoDefenseDepBox = groupbox:AddDependencyBox()

	autoDefenseDepBox:AddToggle("EnableNotifications", {
		Text = "Enable Notifications",
		Default = false,
	})

	autoDefenseDepBox:AddToggle("EnableVisualizations", {
		Text = "Enable Visualizations",
		Default = false,
		Callback = Defense.visualizations,
	})

	autoDefenseDepBox:AddToggle("DashOnParryCooldown", {
		Text = "Dash On Parry Cooldown",
		Default = false,
		Tooltip = "If enabled, the auto defense will fallback to a dash if the parry action is not available.",
	})

	autoDefenseDepBox:AddToggle("DeflectBlockFallback", {
		Text = "Deflect Block Fallback",
		Default = false,
		Tooltip = "If enabled, the auto defense will fallback to block frames if parry action and/or fallback is not available.",
	})

	local afToggle = autoDefenseDepBox:AddToggle("AllowFailure", {
		Text = "Allow Failure",
		Default = false,
		Tooltip = "If enabled, the auto defense will sometimes intentionally fail to parry/deflect.",
	})

	local afDepBox = autoDefenseDepBox:AddDependencyBox()

	afDepBox:AddSlider("FailureRate", {
		Text = "Failure Rate",
		Min = 0,
		Max = 100,
		Default = 0,
		Suffix = "%",
		Rounding = 2,
	})

	afDepBox:AddSlider("DashInsteadOfParryRate", {
		Text = "Dash Instead Of Parry Rate",
		Min = 0,
		Max = 100,
		Default = 0,
		Suffix = "%",
		Rounding = 2,
	})

	afDepBox:AddSlider("FakeMistimeRate", {
		Text = "Fake Parry Mistime Rate",
		Min = 0,
		Max = 100,
		Default = 0,
		Suffix = "%",
		Rounding = 2,
	})

	afDepBox:AddSlider("IgnoreAnimationEndRate", {
		Text = "Ignore Animation End Rate",
		Min = 0,
		Max = 100,
		Default = 0,
		Suffix = "%",
		Rounding = 2,
	})

	afDepBox:SetupDependencies({
		{ afToggle, true },
	})

	autoDefenseDepBox:AddDropdown("AutoDefenseFilters", {
		Text = "Auto Defense Filters",
		Values = {
			"Filter Out M1s",
			"Filter Out Mantras",
			"Filter Out Criticals",
			"Filter Out Undefined",
			"Disable When Textbox Focused",
			"Disable When Window Not Active",
			"Disable When Holding Block",
			"Disable When In Dash",
			"Disable When In Flashstep",
			"Disable When Knocked Recently",
		},
		Multi = true,
		AllowNull = true,
		Default = {},
	})

	autoDefenseDepBox:AddDropdown("DefaultDashDirection", {
		Text = "Default Dash Direction",
		Values = { "W", "A", "S", "D", "Random" },
		Tooltip = "The default direction to dash when you are not holding any movement keys.",
		Default = 3,
	})

	autoDefenseDepBox:AddSlider("DeflectHoldTime", {
		Text = "Deflect Hold Time",
		Min = 0,
		Max = 500,
		Default = 0,
		Suffix = "ms",
		Rounding = 1,
	})

	autoDefenseDepBox:SetupDependencies({
		{ autoDefenseToggle, true },
	})
end

---Initialize combat assistance section.
---@param groupbox table
function CombatTab.initCombatAssistance(groupbox)
	groupbox:AddToggle("AutoTimingPrompt", {
		Text = "Auto Timing Prompt",
		Default = false,
		Tooltip = "Automatically perform a timing prompt and M2 for you.",
	})

	local alToggle = groupbox:AddToggle("AimLock", {
		Text = "Aim Lock",
		Default = false,
		Tooltip = "Automatically lock on to the best target.",
	})

	alToggle:AddKeyPicker("AimLockKeybind", { Default = "N/A", SyncToggleState = true, Text = "Aim Lock" })

	local alDepBox = groupbox:AddDependencyBox()

	local lsToggle = alDepBox:AddToggle("Smoothing", {
		Text = "Smoothing",
		Default = false,
		Tooltip = "Should we attempt to smooth the aim lock movement?",
	})

	local lsDepBox = alDepBox:AddDependencyBox()

	lsDepBox:AddSlider("SmoothingFactor", {
		Text = "Smoothing Factor",
		Min = 0.0,
		Max = 1.0,
		Default = 0.1,
		Rounding = 3,
	})

	local styles = {}

	for _, style in next, Enum.EasingStyle:GetEnumItems() do
		table.insert(styles, style.Name)
	end

	lsDepBox:AddDropdown("SmoothingStyle", { Text = "Smoothing Style", Default = 0, Values = styles })

	local direction = {}

	for _, dir in next, Enum.EasingDirection:GetEnumItems() do
		table.insert(direction, dir.Name)
	end

	lsDepBox:AddDropdown("SmoothingDirection", { Text = "Smoothing Direction", Default = 0, Values = direction })

	alDepBox:AddToggle("ForceAutoRotate", {
		Text = "Force Auto Rotate",
		Default = false,
		Tooltip = "Use this if your aim-lock is not rotating your character. This is an un-fixable issue for now.",
	})

	alDepBox:AddToggle("StickyTargets", {
		Text = "Sticky Targets",
		Default = false,
		Tooltip = "Should we attempt to stick to targets as long as the lock is active?",
	})

	alDepBox:AddToggle("VerticalInfluence", {
		Text = "Vertical Influence",
		Default = false,
		Tooltip = "Should we attempt to lock on vertically or just face them on the horizontal plane?",
	})

	alDepBox:SetupDependencies({
		{ alToggle, true },
	})

	lsDepBox:SetupDependencies({
		{ lsToggle, true },
	})
end

---Initialize tab.
---@param window table
function CombatTab.init(window)
	-- Create tab.
	local tab = window:AddTab("Combat")

	-- Initialize sections.
	CombatTab.initAutoDefenseSection(tab:AddDynamicGroupbox("Auto Defense"))
	CombatTab.initCombatAssistance(tab:AddLeftGroupbox("Combat Assistance"))

	-- Create targeting section tab box.
	local tabbox = tab:AddRightTabbox()
	CombatTab.initCombatTargetingSection(tabbox:AddTab("Targeting"))
	CombatTab.initCombatWhitelistSection(tabbox:AddTab("Whitelisting"))
end

-- Return CombatTab module.
return CombatTab

end)
return __bundle_require("__root")