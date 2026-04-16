---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(720 + distance * 3, 800)
	if distance >= 20 then
		action._when = math.min(750 + distance * 6, 1400)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(30, 15, 60)
	action.name = string.format("(%.2f) Dynamic Phase Timing", distance)

	return self:action(timing, action)
end
