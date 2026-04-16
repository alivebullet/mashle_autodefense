---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(810 + distance * 11, 1700)
	action._type = "Dash"
	action.hitbox = Vector3.new(24, 20, 60)
	action.name = string.format("(%.2f) Dynamic Magma Plume Timing", distance)

	return self:action(timing, action)
end
