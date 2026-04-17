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

	if key == "Random" then
		key = keys[math.random(1, #keys)]
	end

	for _, k in ipairs(keys) do
		local ok, kc = pcall(function()
			return Enum.KeyCode[k]
		end)

		if ok and kc and userInputService:IsKeyDown(kc) then
			key = k
		end
	end

	local direction = directionMap[key] or "GroundBack"

	requestModule:FireServer("Misc", "Dash", direction, { DashCooldown = 1.75 })
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
