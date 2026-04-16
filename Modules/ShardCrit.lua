---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 860
	if distance >= 21 then
		action._when = math.min(650 + distance * 10.5, 1600)
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(35, 20, 100)
	action.name = string.format("(%.2f) Dynamic Shard Arrancar Crit Timing", distance)
	return self:action(timing, action)
end
