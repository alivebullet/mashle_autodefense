---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)

	local action = Action.new()
	action._when = 680
	if distance >= 9 then
		action._when = math.min(750 + distance * 19, 1000)
	end
	if distance >= 21 then
		action._when = math.min(990 + distance * 2, 1800)
	end
	action._type = "Start Block"
	action.hitbox = Vector3.new(81, 70, 81)
	action.name = string.format("(%.2f) Dynamic Fear Timing", distance)
	self:action(timing, action)

	local action2 = Action.new()
	action2._when = 2000
	action2._type = "End Block"
	action2.hitbox = Vector3.new(120, 120, 120)
	self:action(timing, action2)
end
