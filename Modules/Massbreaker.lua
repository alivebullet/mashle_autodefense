---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(880 + distance * 6.8, 2000)
	action._type = "Parry"
	action.hitbox = Vector3.new(35, 20, 80)
	action.name = string.format("(%.2f) Dynamic Massbreaker Timing", distance)

	return self:action(timing, action)
end
