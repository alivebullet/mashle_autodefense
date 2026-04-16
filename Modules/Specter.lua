-- Timestamp.
local lastSpecterTimestamp = nil

---@class Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	if self:distance(self.entity) > 12 then
		return
	end

	if lastSpecterTimestamp and os.clock() - lastSpecterTimestamp <= 1.0 then
		return
	end

	self:hook("target", function()
		return true
	end)

	lastSpecterTimestamp = os.clock()

	timing.fhb = false

	local action = Action.new()
	action._when = 0
	action._type = "Parry"
	action.ihbc = false
	action.hitbox = Vector3.new(15, 15, 15)
	action.name = "Shadow Timing"
	self:action(timing, action)
end
