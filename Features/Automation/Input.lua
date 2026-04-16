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
