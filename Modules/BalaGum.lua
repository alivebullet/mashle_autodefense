---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(480 + distance * 5.5, 1100)
	action._type = "Parry"
	action.hitbox = Vector3.new(60, 20, 60)
	action.name = string.format("(%.2f) Dynamic Bala Gum Timing", distance)

	return self:action(timing, action)
end
