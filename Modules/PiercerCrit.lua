---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(350 + distance * 6, 900)
	action._type = "Parry"
	action.hitbox = Vector3.new(18, 15, 45)
	action.name = string.format("(1) (%.2f) Dynamic Crit Timing", distance)
	self:action(timing, action)

	local action2 = Action.new()
	action2._when = math.min(710 + distance * 6, 900)
	action2._type = "Parry"
	action2.hitbox = Vector3.new(18, 15, 45)
	action2.name = string.format("(2) (%.2f) Dynamic Crit Timing", distance)
	self:action(timing, action2)
end
