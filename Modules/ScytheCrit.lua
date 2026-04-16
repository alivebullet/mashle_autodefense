---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 530
	if distance >= 13 then
		action._when = math.min(450 + distance * 15.2, 1000)
	end
	if distance >= 31 then
		action._when = math.min(950 + distance * 4, 1300)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(27, 15, 40)
	action.name = string.format("(%.2f) Dynamic Scythe Crit Timing", distance)
	return self:action(timing, action)
end
