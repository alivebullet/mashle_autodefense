---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(2550 + distance * 4, 3300)
	action._type = "Dash"
	action.hitbox = Vector3.new(75, 75, 85)
	action.name = string.format("(%.2f) Dynamic Lebron Dunk Timing", distance)

	return self:action(timing, action)
end
