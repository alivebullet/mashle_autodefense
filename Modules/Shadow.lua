-- Timestamp.
local lastShadowCloneTimestamp = nil

---@class Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	if self:distance(self.entity) > 80 then
		return
	end

	if lastShadowCloneTimestamp and os.clock() - lastShadowCloneTimestamp <= 1.0 then
		return
	end

	self:hook("target", function()
		return true
	end)

	lastShadowCloneTimestamp = os.clock()

	timing.fhb = false

	local action = Action.new()
	action._when = 300
	action._type = "Parry"
	action.ihbc = false
	action.hitbox = Vector3.new(50, 50, 50)
	action.name = "Shadow Timing"
	self:action(timing, action)
end
