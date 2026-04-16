---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 400
	if distance >= 21 then
		action._when = 660
	end
	if distance >= 42 then
		action._when = 900
	end
	if distance >= 64 then
		action._when = 1180
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(30, 20, 100)
	action.name = string.format("(%.2f) Dynamic Justice Timing", distance)
	return self:action(timing, action)
end
