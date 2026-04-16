---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 350
	if distance >= 19 then
		action._when = math.min(340 + distance * 5.5, 1500)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(20, 20, 68)
	action.name = string.format("(%.2f) Dynamic Quincy Versch Timing", distance)
	return self:action(timing, action)
end
