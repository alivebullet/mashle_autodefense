-- InputClient module.
local InputClient = {}

-- Services.
local players = game:GetService("Players")
local userInputService = game:GetService("UserInputService")

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

-- Return InputClient module.
return InputClient
