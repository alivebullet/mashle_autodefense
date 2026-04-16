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
