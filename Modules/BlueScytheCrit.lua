---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 700
	action._type = "Parry"
	action.hitbox = Vector3.new(15, 15, 25)
	action.name = string.format("(%.2f) Dynamic Blue Scythe Timing", distance)
	return self:action(timing, action)
end
