---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = math.min(100 + distance * 7, 600)
	action._type = "Parry"
	action.hitbox = Vector3.new(20, 15, 60)
	action.name = string.format("(%.2f) Dynamic Spirit Shot Timing", distance)

	return self:action(timing, action)
end
