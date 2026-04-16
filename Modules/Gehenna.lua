---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 270
	if distance >= 6 then
		action._when = 390
	end
	if distance >= 10 then
		action._when = math.min(410 + distance * 25, 1000)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(45, 45, 45)
	action.name = string.format("(%.2f) Dynamic Gehenna Followup Timing", distance)

	return self:action(timing, action)
end
