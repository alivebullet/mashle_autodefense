---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = math.min(420 + distance * 4, 750)
	if distance >= 26 then
		action._when = math.min(285 + distance * 18, 1700)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(55, 20, 70)
	action.name = string.format("(%.2f) Dynamic Nerve Pull Timing", distance)
	return self:action(timing, action)
end
