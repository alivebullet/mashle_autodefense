---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = 1500
	action._type = "Parry"
	action.hitbox = Vector3.new(15, 15, 80)
	action.name = string.format("(%.2f) Dynamic X-Axis Gun Timing", distance)

	return self:action(timing, action)
end
