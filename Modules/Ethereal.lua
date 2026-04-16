---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 440
	if distance >= 13 then
		action._when = math.min(240 + distance * 20, 5000)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(33, 20, 80)
	action.name = string.format("(%.2f) Dynamic Ethereal Timing", distance)
	return self:action(timing, action)
end
