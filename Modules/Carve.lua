---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = 360
	if distance >= 16 then
		action._when = math.min(150 + distance * 18, 1000)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(22, 15, 35)
	action.name = string.format("(%.2f) Dynamic Carving Timing", distance)

	return self:action(timing, action)
end
