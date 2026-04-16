---@type Action
local Action = getfenv().Action

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local action = Action.new()
	action._type = "Parry"
	action.hitbox = Vector3.new(15, 15, 120)
	action.name = "Keyframe Action"
	return self:akeyframe(action, 1.41)
end
