---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 290
	if distance >= 7 then
		action._when = math.min(310 + distance * 5.2, 700)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(90, 30, 90)
	action.name = string.format("(%.2f) Dynamic Prismatic Timing", distance)
	return self:action(timing, action)
end
