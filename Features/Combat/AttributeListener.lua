-- AttributeListener module.
local AttributeListener = {
	lastParry = nil,
	lastParryAttempt = nil,
	lastParrySuccess = nil,
	lastDash = nil,
	lastKnock = nil,
	stateValues = {},
}

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
		AttributeListener.lastParrySuccess = tick()
		TimingHarvester.onParryResult(false)
	end,
	PerfectParry = function()
		AttributeListener.lastParry = nil
		AttributeListener.lastParrySuccess = tick()
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
	AttributeListener.lastParryAttempt = now

	-- Do not extend the synthetic cooldown when we are already locked out. That makes
	-- repeated checks drift farther away from the real game cooldown.
	if not AttributeListener.lastParry or now - AttributeListener.lastParry >= PARRY_COOLDOWN_S then
		AttributeListener.lastParry = now
	end
end

---Clear the local parry cooldown when the game confirms a successful parry.
function AttributeListener.clearParryCooldown()
	AttributeListener.lastParry = nil
	AttributeListener.lastParrySuccess = tick()
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

	return math.max(0, math.round((PARRY_COOLDOWN_S - (tick() - AttributeListener.lastParry)) * 1000))
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

---Current local parry availability snapshot.
---@return table
function AttributeListener.parryStatus()
	local now = tick()
	local remainingMs = AttributeListener.parryRemainingMs()
	local activeStates = AttributeListener.activeStates()
	local reason = remainingMs > 0 and "synthetic-cooldown" or "ready"

	return {
		canParry = remainingMs <= 0,
		reason = reason,
		remainingMs = remainingMs,
		sinceAttemptMs = AttributeListener.lastParryAttempt and math.round((now - AttributeListener.lastParryAttempt) * 1000)
			or nil,
		sinceSuccessMs = AttributeListener.lastParrySuccess and math.round((now - AttributeListener.lastParrySuccess) * 1000)
			or nil,
		activeStates = activeStates,
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
