---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 430
	if distance >= 12 then
		action._when = 570
	end
	if distance >= 14 then
		action._when = 630
	end
	if distance >= 16 then
		action._when = 650
	end
	if distance >= 18 then
		action._when = 690
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(15, 15, 22)
	action.name = string.format("(%.2f) Dynamic Hakuda Crit Timing", distance)
	return self:action(timing, action)
end
