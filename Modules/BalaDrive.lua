---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(600 + distance * 5.5, 1400)
	action._type = "Start Block"
	action.hitbox = Vector3.new(60, 20, 60)
	action.name = string.format("(%.2f) Dynamic Bala Drive Timing", distance)
	self:action(timing, action)

	local action2 = Action.new()
	action2._when = 1000
	action2._type = "End Block"
	action2.hitbox = Vector3.new(200, 200, 200)
	action2.name = string.format("(2) (%.2f) Dynamic Timing", distance)
	self:action(timing, action2)
end
