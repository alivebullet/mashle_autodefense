---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(1300 + distance * 7.6, 2000)
	action._type = "Dash"
	action.hitbox = Vector3.new(140, 50, 140)
	action.name = string.format("(%.2f) Dynamic Reishi Bomb Timing", distance)

	return self:action(timing, action)
end
