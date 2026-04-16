---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 490
	if distance >= 13 then
		action._when = math.min(630 + distance * 3.2, 1000)
	end
	if distance >= 19 then
		action._when = math.min(700 + distance * 2, 1400)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(23, 15, 28)
	action.name = string.format("(%.2f) Dynamic Yamato Critical Timing", distance)
	return self:action(timing, action)
end
