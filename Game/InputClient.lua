-- InputClient module.
local InputClient = {}

-- Services.
local players = game:GetService("Players")
local userInputService = game:GetService("UserInputService")
local virtualInputManager = game:GetService("VirtualInputManager")
local replicatedStorage = game:GetService("ReplicatedStorage")

local DASH_INPUT_HOLD_S = 0.12

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Features.Combat.TimingHarvester
local TimingHarvester = require("Features/Combat/TimingHarvester")

---@module Features.Combat.AttributeListener
local AttributeListener = require("Features/Combat/AttributeListener")

---@module Features.Combat.ParryCooldownProbe
local ParryCooldownProbe = require("Features/Combat/ParryCooldownProbe")

---Deflect. This is called this way because it can either give parry or block frames depending on whether or not parry is on cooldown.
function InputClient.deflect()
	InputClient.block(true)

	task.wait(Configuration.expectOptionValue("DeflectHoldTime") / 1000)

	InputClient.block(false)
end

---Block (Mashle). Fires UpdateCharacterState with a boolean Blocking state.
---@param state boolean
function InputClient.block(state)
	local remotes = replicatedStorage:FindFirstChild("Remotes")
	local updateCharacterState = remotes and remotes:FindFirstChild("UpdateCharacterState")
	if not updateCharacterState then
		return
	end

	updateCharacterState:FireServer("Blocking", state)
end

---@param keyCode Enum.KeyCode?
---@param isDown boolean
---@return boolean
local function sendMovementKeyEvent(keyCode, isDown)
	if not keyCode then
		return false
	end

	local ok = pcall(function()
		virtualInputManager:SendKeyEvent(isDown, keyCode, false, game)
	end)

	return ok
end

---@param key string?
---@return Vector3
local function dashMoveVector(key)
	local localVectorMap = {
		W = Vector3.new(0, 0, -1),
		A = Vector3.new(-1, 0, 0),
		S = Vector3.new(0, 0, 1),
		D = Vector3.new(1, 0, 0),
	}

	local localVector = localVectorMap[key] or localVectorMap.S
	local camera = workspace.CurrentCamera
	if not camera then
		return localVector
	end

	local worldVector = camera.CFrame:VectorToWorldSpace(localVector)
	return Vector3.new(worldVector.X, 0, worldVector.Z)
end

---Dash (Mashle). Fires RequestModule with direction string and cooldown payload.
---Note: Mashle appears to infer actual movement from held keys server-side, so a bare
---remote fire may not produce movement. If dash fallback silently no-ops, either turn
---off DashOnParryCooldown or add movement-key simulation around this call.
function InputClient.dash()
	local remotes = replicatedStorage:FindFirstChild("Remotes")
	local requestModule = remotes and remotes:FindFirstChild("RequestModule")
	if not requestModule then
		return
	end

	local directionMap = {
		W = "GroundForward",
		A = "GroundLeft",
		S = "GroundBack",
		D = "GroundRight",
	}

	local key = Configuration.expectOptionValue("DefaultDashDirection") or "S"
	local keys = { "W", "A", "S", "D" }
	local keyCode = nil

	if key == "Random" then
		key = keys[math.random(1, #keys)]
	end

	for _, k in ipairs(keys) do
		local ok, kc = pcall(function()
			return Enum.KeyCode[k]
		end)

		if ok and kc and userInputService:IsKeyDown(kc) then
			key = k
			keyCode = kc
		end
	end

	if not keyCode then
		local ok, kc = pcall(function()
			return Enum.KeyCode[key]
		end)

		if ok then
			keyCode = kc
		end
	end

	local direction = directionMap[key] or "GroundBack"
	local simulatedKey = false
	local localPlayer = players.LocalPlayer
	local character = localPlayer and localPlayer.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	local moveVector = dashMoveVector(key)

	if keyCode and not userInputService:IsKeyDown(keyCode) then
		simulatedKey = sendMovementKeyEvent(keyCode, true)
	end

	if humanoid and moveVector.Magnitude > 0 then
		humanoid:Move(moveVector, false)
	end

	ParryCooldownProbe.onDashAttempt("script")
	requestModule:FireServer("Misc", "Dash", direction, { DashCooldown = 1.75 })

	if simulatedKey then
		task.delay(DASH_INPUT_HOLD_S, function()
			sendMovementKeyEvent(keyCode, false)
		end)
	end

	if humanoid then
		task.delay(DASH_INPUT_HOLD_S, function()
			humanoid:Move(Vector3.zero, false)
		end)
	end
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

	AttributeListener.markParryAttempt()
	TimingHarvester.onParryPress()
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
