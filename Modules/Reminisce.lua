---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	task.wait(0.1)
	local action = Action.new()
	action._when = (490 * 0.75) / self.track.Speed
	action._type = "Parry"
	action.hitbox = Vector3.new(16, 15, 16)
	action.name = string.format("(%.2f) Dynamic Reminisce Timing", self.track.Speed)
	return self:action(timing, action)
end
