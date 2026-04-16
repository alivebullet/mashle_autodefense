---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(520 + distance * 15.1, 1300)
	action._type = "Parry"
	action.hitbox = Vector3.new(40, 25, 32)
	action.name = string.format("(%.2f) Dynamic Power Timing", distance)

	return self:action(timing, action)
end
