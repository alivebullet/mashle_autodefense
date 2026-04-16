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
