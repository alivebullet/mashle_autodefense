---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(520 + distance * 8, 1600)
	action._type = "Parry"
	action.hitbox = Vector3.new(35, 15, 100)
	action.name = string.format("(%.2f) Dynamic Reishi Wave Timing", distance)

	return self:action(timing, action)
end
