---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = 440
	if distance >= 11 then
		action._when = math.min(290 + distance * 22.5, 2000)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(25, 15, 30)
	action.name = string.format("(%.2f) Dynamic Water X Timing", distance)

	return self:action(timing, action)
end
