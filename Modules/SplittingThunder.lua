---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 540
	if distance >= 17 then
		action._when = 560
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(20, 20, 45)
	action.name = string.format("(%.2f) Dynamic Splitting Thunder Timing", distance)
	return self:action(timing, action)
end
