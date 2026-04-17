-- AttributeListener module.
local AttributeListener = { lastParry = nil, lastDash = nil, lastKnock = nil }

---@modules Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Features.Combat.TimingHarvester
local TimingHarvester = require("Features/Combat/TimingHarvester")

-- Services.
local players = game:GetService("Players")

-- Top-level maid (CharacterAdded / CharacterRemoving signals).
local attributeMaid = Maid.new()

-- Per-character maid; cleaned on CharacterRemoving. Holds watchers on CharacterState BoolValues.
local stateMaid = Maid.new()

local PARRY_COOLDOWN_S = 2000 / 1000
local DASH_COOLDOWN_S = 1750 / 1000

-- BoolValues under character.CharacterState that we care about. When the .Value flips true,
-- the paired callback fires. Mashle splits state across many BoolValues instead of using
-- Type Soul's single CurrentState string attribute.
local WATCHED = {
	Parry = function()
		AttributeListener.lastParry = nil
		TimingHarvester.onParryResult(false)
	end,
	PerfectParry = function()
		AttributeListener.lastParry = nil
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
	AttributeListener.lastParry = tick()
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
	local signal = Signal.new(bv:GetPropertyChangedSignal("Value"))
	stateMaid:add(signal:connect("AttributeListener_CSValue_" .. bv.Name, function()
		if bv.Value then
			onTrue()
		end
	end))
end

---Attach watchers to every BoolValue we care about under a CharacterState folder, and handle
---late-added ones via ChildAdded.
---@param characterState Instance
local function attachStateWatches(characterState)
	for name, onTrue in pairs(WATCHED) do
		local bv = characterState:FindFirstChild(name)
		if bv and bv:IsA("BoolValue") then
			watchBool(bv, onTrue)
		end
	end

	local childAdded = Signal.new(characterState.ChildAdded)
	stateMaid:add(childAdded:connect("AttributeListener_OnCSChildAdded", function(child)
		local onTrue = WATCHED[child.Name]
		if onTrue and child:IsA("BoolValue") then
			watchBool(child, onTrue)
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

	return not AttributeListener.lastParry or tick() - AttributeListener.lastParry >= PARRY_COOLDOWN_S
end

---Can we dash?
---@return boolean
function AttributeListener.cdash()
	local localPlayer = players.LocalPlayer
	local character = localPlayer.Character
	if not character then
		return false
	end

	return not AttributeListener.lastDash or tick() - AttributeListener.lastDash >= DASH_COOLDOWN_S
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
