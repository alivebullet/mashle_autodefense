---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local distance = self:distance(self.entity)
	local action = Action.new()
	action._type = "Parry"
	action.hitbox = Vector3.new(15, 15, 120)
	action.name = string.format("(%.2f - %.2f) Dynamic Keyframe Action", distance, self.track.Speed)

	local tp = 1.0

	if distance >= 20 then
		tp = 1.1
	end

	if distance >= 25 then
		tp = 1.12
	end

	if distance >= 30 then
		tp = 1.15
	end

	if distance >= 35 then
		tp = 1.18
	end

	if distance >= 40 then
		tp = 1.2
	end

	return self:akeyframe(action, tp)
end
