-- Timestamp.
local lastPowerTimestamp = nil

---@class Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	if self:distance(self.entity) > 12 then
		return
	end

	if lastPowerTimestamp and os.clock() - lastPowerTimestamp <= 1.0 then
		return
	end

	self:hook("target", function()
		return true
	end)

	lastPowerTimestamp = os.clock()

	timing.fhb = true

	local action = Action.new()
	action._when = 920
	action._type = "Dash"
	action.ihbc = false
	action.hitbox = Vector3.new(12, 12, 12)
	action.name = "True Power Timing"
	self:action(timing, action)
end
