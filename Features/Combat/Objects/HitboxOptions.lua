---@class HitboxOptions
---@note: Options for the hitbox check.
---@field part BasePart? If this is specified and it exists, it will be used for the position.
---@field cframe CFrame? Else, the part's CFrame will be used.
---@field timing Timing|AnimationTiming|SoundTiming
---@field action Action?
---@field filter Instance[]
---@field spredict boolean If true, a check will run for predicted positions.
---@field ptime number? The predicted time in seconds for extrapolation.
---@field entity Model? The entity for extrapolation.
---@field phcolor Color3 The color for predicted hitboxes.
---@field pmcolor Color3 The color for predicted missed hitboxes.
---@field hcolor Color3 The color for hitboxes.
---@field mcolor Color3 The color for missed hitboxes.
---@field hmid number? Hitbox visualization ID for normal hitbox check.
local HitboxOptions = {}
HitboxOptions.__index = HitboxOptions

-- Services.
local players = game:GetService("Players")

---Return the best action time-position available for adaptive hitbox lookup.
---@param action Action?
---@return number?
local function actionWhen(action)
	if not action then
		return nil
	end

	if type(action.tp) == "number" then
		return action.tp
	end

	if type(action.when) == "function" then
		local ok, value = pcall(action.when, action)
		if ok and type(value) == "number" then
			return value
		end
	end

	return nil
end

---Return the timing animation id if available.
---@param timing Timing|AnimationTiming|SoundTiming
---@return string?
local function timingId(timing)
	if not timing or type(timing.id) ~= "function" then
		return nil
	end

	local ok, aid = pcall(timing.id, timing)
	if ok and type(aid) == "string" and aid ~= "" then
		return aid
	end

	return nil
end

---Hit color.
---@return Color3
function HitboxOptions:ghcolor(result)
	return result and self.hcolor or self.mcolor
end

---Predicted hit color.
---@return Color3
function HitboxOptions:gphcolor(result)
	return result and self.phcolor or self.pmcolor
end

---Cloned hitbox options.
---@return HitboxOptions
function HitboxOptions:clone()
	local options = setmetatable({}, HitboxOptions)
	options.action = self.action
	options.spredict = self.spredict
	options.entity = self.entity
	options.ptime = self.ptime
	options.entity = self.entity
	options.phcolor = self.phcolor
	options.pmcolor = self.pmcolor
	options.hcolor = self.hcolor
	options.mcolor = self.mcolor
	options.hmid = self.hmid
	options.filter = self.filter
	options.part = self.part
	options.cframe = self.cframe
	options.timing = self.timing
	options._adaptiveHitbox = nil
	return options
end

---Return the effective live hitbox state for this check.
---@return table
function HitboxOptions:adaptiveHitbox()
	if type(self._adaptiveHitbox) == "table" then
		return self._adaptiveHitbox
	end

	local hitbox = self.action and self.action.hitbox or self.timing.hitbox
	local hitboxOffset = self.action and self.action.hitboxOffset or self.timing.hitboxOffset
	local facing = self.timing.fhb == true

	if self.timing.duih then
		hitbox = self.timing.hitbox
		hitboxOffset = self.timing.hitboxOffset
	end

	if typeof(hitbox) ~= "Vector3" then
		hitbox = Vector3.zero
	end

	if typeof(hitboxOffset) ~= "Vector3" then
		hitboxOffset = Vector3.zero
	end

	local aid = timingId(self.timing)
	if aid then
		local okHarvester, TimingHarvester = pcall(require, "Features/Combat/TimingHarvester")
		if okHarvester and type(TimingHarvester) == "table" and type(TimingHarvester.liveHitbox) == "function" then
			local dynamic = TimingHarvester.liveHitbox(aid, actionWhen(self.action), hitbox, hitboxOffset, facing)
			if type(dynamic) == "table" then
				if typeof(dynamic.hitbox) == "Vector3" then
					hitbox = dynamic.hitbox
				end

				if typeof(dynamic.offset) == "Vector3" then
					hitboxOffset = dynamic.offset
				end

				if type(dynamic.facing) == "boolean" then
					facing = dynamic.facing
				end
			end
		end
	end

	self._adaptiveHitbox = {
		hitbox = hitbox,
		offset = hitboxOffset,
		facing = facing,
	}

	return self._adaptiveHitbox
end

---Get the hitbox size.
---@return Vector3
function HitboxOptions:hitbox()
	local hitbox = self:adaptiveHitbox().hitbox

	hitbox = Vector3.new(PP_SCRAMBLE_NUM(hitbox.X), PP_SCRAMBLE_NUM(hitbox.Y), PP_SCRAMBLE_NUM(hitbox.Z))

	return hitbox
end

---Get the hitbox center offset.
---@return Vector3
function HitboxOptions:hitboxOffset()
	local hitboxOffset = self:adaptiveHitbox().offset

	return Vector3.new(
		PP_SCRAMBLE_NUM(hitboxOffset.X),
		PP_SCRAMBLE_NUM(hitboxOffset.Y),
		PP_SCRAMBLE_NUM(hitboxOffset.Z)
	)
end

---Should this hitbox still use the original forward-facing rectangle offset?
---@return boolean
function HitboxOptions:facingHitbox()
	return self:adaptiveHitbox().facing == true
end

---Get extrapolated position.
---@return CFrame
HitboxOptions.extrapolate = LPH_NO_VIRTUALIZE(function(self)
	if not self.part then
		return error("HitboxOptions.extrapolate - unimplemented for CFrame")
	end

	if not self.entity then
		return error("HitboxOptions.extrapolate - no entity specified")
	end

	if not self.ptime then
		return error("HitboxOptions.extrapolate - no predicted time specified")
	end

	-- Return the extrapolated position.
	local predicted = self.part.CFrame + (self.part.AssemblyLinearVelocity * self.ptime)
	local hitboxOffset = self:hitboxOffset()
	if hitboxOffset.Magnitude > 0 then
		predicted = predicted * CFrame.new(hitboxOffset)
	end

	return predicted
end)

---Get position.
---@return CFrame
HitboxOptions.pos = LPH_NO_VIRTUALIZE(function(self)
	local position = nil
	if self.cframe then
		position = self.cframe
	elseif self.part then
		position = self.part.CFrame
	end

	if not position then
		return error("HitboxOptions.pos - impossible condition")
	end

	local hitboxOffset = self:hitboxOffset()
	if hitboxOffset.Magnitude > 0 then
		position = position * CFrame.new(hitboxOffset)
	end

	return position
end)

---Create new HitboxOptions object.
---@param target Instance|CFrame
---@param timing Timing|AnimationTiming|SoundTiming
---@param filter Instance[]?
---@return HitboxOptions
HitboxOptions.new = LPH_NO_VIRTUALIZE(function(target, timing, filter)
	local self = setmetatable({}, HitboxOptions)
	self.part = typeof(target) == "Instance" and target:IsA("BasePart") and target
	self.cframe = typeof(target) == "CFrame" and target
	self.timing = timing
	self.action = nil
	self.filter = filter or {}
	self.spredict = false
	self.hmid = nil
	self.entity = nil
	self.phcolor = Color3.new(1, 0, 1)
	self.pmcolor = Color3.new(0.349019, 0.345098, 0.345098)
	self.hcolor = Color3.new(0, 1, 0)
	self.mcolor = Color3.new(1, 0, 0)
	self.ptime = nil

	if not self.part and not self.cframe then
		return error("HitboxOptions: No part or CFrame specified.")
	end

	if filter then
		return self
	end

	local character = players.LocalPlayer.Character
	if not character then
		return self
	end

	self.filter = { character }

	return self
end)

-- Return HitboxOptions module.
return HitboxOptions
