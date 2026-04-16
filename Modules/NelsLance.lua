---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._when = 650
	if distance >= 18 then
		action._when = 680
	end
	if distance >= 20 then
		action._when = 700
	end
	if distance >= 22 then
		action._when = 720
	end
	if distance >= 24 then
		action._when = 880
	end
	if distance >= 26 then
		action._when = 950
	end
	if distance >= 28 then
		action._when = 990
	end
	if distance >= 30 then
		action._when = 1040
	end
	if distance >= 32 then
		action._when = 1080
	end
	action._type = "Parry"
	action.hitbox = Vector3.new(20, 15, 33)
	action.name = string.format("(%.2f) Dynamic Nels Lance Crit Timing", distance)
	return self:action(timing, action)
end
