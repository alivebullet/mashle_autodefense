---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	repeat
		task.wait()
	until self.track.TimePosition >= 0.75
	local action = Action.new()
	action._when = 0
	if distance >= 20 then
		action._when = math.min(1 + distance * 3, 1500)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(25, 20, 80)
	action.name = string.format("(%.2f) Dynamic Fire GS Neutral Crit Timing", distance)
	return self:action(timing, action)
end
