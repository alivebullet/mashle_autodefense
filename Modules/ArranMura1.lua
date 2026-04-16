---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 550
	if distance >= 15 then
		action._when = math.min(550 + distance * 6.2, 1000)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(22, 15, 36)
	action.name = string.format("(%.2f) Dynamic Arrancar Murasama Crit Timing", distance)
	return self:action(timing, action)
end
