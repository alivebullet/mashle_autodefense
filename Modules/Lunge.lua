---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(170 + distance * 16.5, 650)
	if distance >= 29 then
		action._when = math.min(500 + distance * 3.6, 1000)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(23, 15, 45)
	action.name = string.format("(%.2f) Dynamic Accelerate Timing", distance)

	return self:action(timing, action)
end
