---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 350
	if distance >= 12 then
		action._when = 420
	end
	if distance >= 14 then
		action._when = 460
	end
	if distance >= 15 then
		action._when = 530
	end
	if distance >= 19 then
		action._when = 650
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(15, 15, 23)
	action.name = string.format("(%.2f) Dynamic Twinblade Crit Timing", distance)
	return self:action(timing, action)
end
