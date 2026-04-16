---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 350
	if distance >= 15 then
		action._when = 330
	end
	if distance >= 20 then
		action._when = 500
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(17, 15, 28)
	action.name = string.format("(%.2f) Dynamic Longsword Crit Timing", distance)
	return self:action(timing, action)
end
