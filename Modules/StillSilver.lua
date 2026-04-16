---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 850
	if distance >= 25 then
		action._when = math.min(850 + distance * 3.5, 1500)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(20, 20, 100)
	action.name = string.format("(%.2f) Dynamic Still Silver Timing", distance)
	return self:action(timing, action)
end
