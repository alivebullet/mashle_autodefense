---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 350
	if distance >= 13 then
		action._when = 330
	end
	if distance >= 18 then
		action._when = 410
	end
	if distance >= 19 then
		action._when = 520
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(15, 15, 25)
	action.name = string.format("(%.2f) Dynamic Scythe Timing", distance)
	return self:action(timing, action)
end
