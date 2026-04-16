---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local action = Action.new()
	action._type = "Parry"
	action.hitbox = Vector3.new(15, 15, 12)
	action.name = "Keyframe Action"
	return self:akeyframe(action, 0.40)
end
