---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(1250 + distance * 5, 2500)
	action._type = "Parry"
	action.hitbox = Vector3.new(150, 120, 150)
	action.name = string.format("(%.2f) Dynamic Bomb Kick Timing", distance)

	return self:action(timing, action)
end
