---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 700
	if distance >= 13 then
		action._when = math.min(690 + distance * 8.5, 1400)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(27, 15, 27)
	action.name = string.format("(%.2f) Dynamic Reishi String Timing", distance)
	return self:action(timing, action)
end
