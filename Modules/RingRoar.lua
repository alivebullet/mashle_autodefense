---@module Features.Combat.Objects.RepeatInfo
local RepeatInfo = getfenv().RepeatInfo

---Module function.
---@param self AnimatorDefender
---@param timing AnimationTiming
return function(self, timing)
	timing.rpue = true
	timing._rpd = 150
	timing._rsd = 1200
	timing.hitbox = Vector3.new(300, 300, 300)

	if self.track.Speed >= 0.94 and self.track.Speed <= 0.96 then
		timing._rsd = 1150
	end

	if self.track.Speed >= 1.45 and self.track.Speed <= 1.55 then
		timing._rsd = 1200
	end

	local info = RepeatInfo.new(timing)
	info.track = self.track
	info.irdelay = self.rdelay()
	self:rpue(self.entity, timing, info)
end
