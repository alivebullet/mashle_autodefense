---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(430 + distance * 13, 2500)
	action._type = "Parry"
	action.hitbox = Vector3.new(40, 30, 120)
	action.name = string.format("(%.2f) Dynamic Duke Stomp Timing", distance)

	return self:action(timing, action)
end
