---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(970 + distance * 3, 1400)
	action._type = "Parry"
	action.hitbox = Vector3.new(25, 25, 75)
	action.name = string.format("(%.2f) Dynamic Murasama Quincy Crit Timing", distance)

	return self:action(timing, action)
end
