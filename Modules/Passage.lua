---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 750
	if distance >= 15 then
		action._when = math.min(795 + distance * 12.4, 2200)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(28, 20, 30)
	action.name = string.format("(%.2f) Dynamic Flowing Passage Timing", distance)
	return self:action(timing, action)
end
