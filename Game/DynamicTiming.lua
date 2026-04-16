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
