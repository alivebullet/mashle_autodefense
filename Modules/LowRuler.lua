---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(750 + distance * 1.9, 1200)
	action._type = "Dash"
	action.hitbox = Vector3.new(150, 100, 150)
	action.name = string.format("(%.2f) Dynamic Low Ruler Timing", distance)

	return self:action(timing, action)
end
