---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 370
	if distance >= 8 then
		action._when = math.min(400 + distance * 13.1, 1500)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(14, 15, 20)
	action.name = string.format("(%.2f) Dynamic Confliction Timing", distance)
	return self:action(timing, action)
end
