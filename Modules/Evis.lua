---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 620
	if distance >= 15 then
		action._when = math.min(640 + distance * 4, 1200)
	end
	action._type = "Start Block"
	action.hitbox = Vector3.new(60, 30, 37)
	action.name = string.format("(%.2f) Dynamic Evisorate Timing", distance)
	self:action(timing, action)

	local action2 = Action.new()
	action2._when = 1325
	action2._type = "End Block"
	action2.hitbox = Vector3.new(100, 100, 100)
	action2.name = string.format("(2) (%.2f) Dynamic Evisorate Timing", distance)
	self:action(timing, action2)
end
