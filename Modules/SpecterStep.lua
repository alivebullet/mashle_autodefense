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
	action._when = 225
	action._type = "Start Block"
	action.ihbc = false
	action.hitbox = Vector3.new(20, 20, 20)
	action.name = "Start Timing"
	self:action(timing, action)

	local action2 = Action.new()
	action2._when = 400
	action2._type = "End Block"
	action2.hitbox = Vector3.new(40, 40, 40)
	action2.name = "End Timing"
	self:action(timing, action2)
end
