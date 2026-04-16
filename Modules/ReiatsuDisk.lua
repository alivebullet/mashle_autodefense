---@type Action
local Action = getfenv().Action

---@type Signal
local Signal = getfenv().Signal

---@type PartTiming
local PartTiming = getfenv().PartTiming

---@module Features.Combat.Defense
local Defense = getfenv().Defense

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	local effects = workspace:FindFirstChild("Effects")
	local peffects = effects and effects:FindFirstChild(self.entity.Name)
	if not peffects then
		return
	end

	local distance = self:distance(self.entity)

	if distance <= 15 then
		local action = Action.new()
		action._when = 400
		action._type = "Start Block"
		action.ihbc = true
		action.name = "Reiatsu Disk Start Block"
		self:action(timing, action)

		local action2 = Action.new()
		action2._when = 1300
		action2._type = "End Block"
		action2.ihbc = true
		action2.name = "Reiatsu Disk End Block"
		return self:action(timing, action2)
	end

	local childAdded = Signal.new(peffects.ChildAdded)
	local childConnection = nil

	local function listener(child)
		if child.Name ~= "ReiatsuDisc" then
			return
		end

		if childConnection then
			childConnection:Disconnect()
		end

		local action = Action.new()
		action._when = 0
		action._type = "Parry"
		action.name = "Reiatsu Disk Part"

		local pt = PartTiming.new()
		pt.uhc = true
		pt.fhb = false
		pt.duih = true
		pt.name = "ReiatsuDiskProjectile"
		pt.hitbox = Vector3.new(7, 7, 30)
		pt.actions:push(action)

		Defense.cdpo(child, pt)
	end

	childConnection = childAdded:connect("ReiatsuDisk_ProjectileListener", listener)

	for _, child in next, peffects:GetChildren() do
		listener(child)
	end
end
