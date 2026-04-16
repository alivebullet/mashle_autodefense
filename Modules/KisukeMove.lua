-- Timestamp.
local lastShadowTimestamp = nil

---@class Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	if self:distance(self.entity) > 12 then
		return
	end

	if lastShadowTimestamp and os.clock() - lastShadowTimestamp <= 1.0 then
		return
	end

	self:hook("target", function()
		return true
	end)

	lastShadowTimestamp = os.clock()

	timing.fhb = false

	local action = Action.new()
	action._when = 290
	action._type = "Parry"
	action.ihbc = false
	action.hitbox = Vector3.new(25, 25, 25)
	action.name = "Shadow Timing"
	self:action(timing, action)
end
