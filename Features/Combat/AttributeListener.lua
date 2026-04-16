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
