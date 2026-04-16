---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = math.min(440 + distance * 6.5, 1500)
	action._type = "Parry"
	action.hitbox = Vector3.new(80, 40, 119)
	action.name = string.format("(%.2f) Dynamic Galvano Timing", distance)

	return self:action(timing, action)
end
