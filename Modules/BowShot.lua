---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(930 + distance * 5.6, 3000)
	action._type = "Start Block"
	action.hitbox = Vector3.new(70, 80, 100)
	action.name = string.format("(%.2f) Dynamic Bow Shot Timing", distance)
	self:action(timing, action)

	local action2 = Action.new()
	action2._when = math.min(1100 + distance * 7, 3000)
	action2._type = "End Block"
	action2.hitbox = Vector3.new(120, 120, 150)
	self:action(timing, action2)
end
