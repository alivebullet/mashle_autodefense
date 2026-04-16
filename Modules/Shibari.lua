---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(250 + distance * 10, 700)
	action._type = "Dash"
	action.hitbox = Vector3.new(18, 15, 50)
	action.name = string.format("(%.2f) Dynamic Shibari Timing", distance)

	return self:action(timing, action)
end
