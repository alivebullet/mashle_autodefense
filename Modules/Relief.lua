---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(625 + distance * 11, 1300)
	action._type = "Start Block"
	action.hitbox = Vector3.new(30, 15, 60)
	action.name = string.format("(%.2f) Dynamic Crescent Relief Timing", distance)
	self:action(timing, action)

	local action2 = Action.new()
	action2._when = 1600
	action2._type = "End Block"
	action2.hitbox = Vector3.new(200, 200, 200)
	action2.name = string.format("(2) (%.2f) Dynamic Crit Timing", distance)
	self:action(timing, action2)
end
