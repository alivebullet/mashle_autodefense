---@class Action
---@field _type string
---@field _when number When the action will occur in miliseconds. Never access directly.
---@field hitbox Vector3 The hitbox of the action.
---@field ihbc boolean Ignore hitbox check.
---@field name string The name of the action.
---@field pingProfiles table[]? Ping-aware harvested timing profiles: { ping = number, when = number, samples = number }
---@field tp number Time position. Never accessible unless inside of a module or inside of real code. This is never serialized.
local Action = {}
Action.__index = Action

-- Services.
local stats = game:GetService("Stats")

-- Constants.
local PROFILE_MERGE_THRESHOLD_MS = 30

---Get the current full RTT in milliseconds.
---@return number?
local function currentPingMs()
	local network = stats:FindFirstChild("Network")
	if not network then
		return nil
	end

	local serverStatsItem = network:FindFirstChild("ServerStatsItem")
	if not serverStatsItem then
		return nil
	end

	local dataPing = serverStatsItem:FindFirstChild("Data Ping")
	if not dataPing then
		return nil
	end

	local ok, value = pcall(function()
		return dataPing:GetValue()
	end)
	if not ok or type(value) ~= "number" then
		return nil
	end

	return value
end

---Return the closest stored ping profile for the current RTT.
---@return table?
function Action:closestPingProfile()
	if type(self.pingProfiles) ~= "table" or #self.pingProfiles == 0 then
		return nil
	end

	local pingMs = currentPingMs()
	if not pingMs then
		return nil
	end

	local best, bestDelta = nil, math.huge
	for _, profile in ipairs(self.pingProfiles) do
		local delta = math.abs((profile.ping or 0) - pingMs)
		if delta < bestDelta then
			bestDelta = delta
			best = profile
		end
	end

	return best
end

---Add or merge a ping profile into the action.
---@param pingMs number
---@param whenMs number
---@param samples number?
---@return table
function Action:addPingProfile(pingMs, whenMs, samples)
	self.pingProfiles = self.pingProfiles or {}

	local count = math.max(1, math.floor(samples or 1))
	local bestIndex, bestDelta = nil, math.huge

	for index, profile in ipairs(self.pingProfiles) do
		local delta = math.abs((profile.ping or 0) - pingMs)
		if delta < bestDelta then
			bestDelta = delta
			bestIndex = index
		end
	end

	if bestIndex and bestDelta <= PROFILE_MERGE_THRESHOLD_MS then
		local profile = self.pingProfiles[bestIndex]
		local existingSamples = math.max(1, math.floor(profile.samples or 1))
		local totalSamples = existingSamples + count

		profile.ping = ((profile.ping or pingMs) * existingSamples + pingMs * count) / totalSamples
		profile.when = ((profile.when or whenMs) * existingSamples + whenMs * count) / totalSamples
		profile.samples = totalSamples
	else
		table.insert(self.pingProfiles, {
			ping = pingMs,
			when = whenMs,
			samples = count,
		})
	end

	table.sort(self.pingProfiles, function(a, b)
		return (a.ping or 0) < (b.ping or 0)
	end)

	return self:closestPingProfile() or self.pingProfiles[#self.pingProfiles]
end

---Getter for when in seconds.
---@return number
function Action:when()
	local profile = self:closestPingProfile()
	if profile and type(profile.when) == "number" then
		return profile.when / 1000
	end

	return PP_SCRAMBLE_NUM(self._when) / 1000
end

---Load from partial values.
---@param values table
function Action:load(values)
	if typeof(values._type) == "string" then
		self._type = values._type
	end

	if typeof(values.when) == "number" then
		self._when = values.when
	end

	if typeof(values.name) == "string" then
		self.name = values.name
	end

	if typeof(values.hitbox) == "table" then
		self.hitbox = Vector3.new(values.hitbox.X, values.hitbox.Y, values.hitbox.Z)
	end

	if typeof(values.ihbc) == "boolean" then
		self.ihbc = values.ihbc
	end

	if typeof(values.pingProfiles) == "table" then
		self.pingProfiles = {}

		for _, profile in ipairs(values.pingProfiles) do
			if typeof(profile) ~= "table" then
				continue
			end

			if typeof(profile.ping) ~= "number" or typeof(profile.when) ~= "number" then
				continue
			end

			table.insert(self.pingProfiles, {
				ping = profile.ping,
				when = profile.when,
				samples = typeof(profile.samples) == "number" and profile.samples or 1,
			})
		end

		table.sort(self.pingProfiles, function(a, b)
			return (a.ping or 0) < (b.ping or 0)
		end)
	end
end

---Equals check.
---@param other Action
---@return boolean
function Action:equals(other)
	if self._type ~= other._type then
		return false
	end

	if self._when ~= other._when then
		return false
	end

	if self.name ~= other.name then
		return false
	end

	if self.hitbox ~= other.hitbox then
		return false
	end

	if self.ihbc ~= other.ihbc then
		return false
	end

	local selfCount = type(self.pingProfiles) == "table" and #self.pingProfiles or 0
	local otherCount = type(other.pingProfiles) == "table" and #other.pingProfiles or 0
	if selfCount ~= otherCount then
		return false
	end

	for index = 1, selfCount do
		local lhs = self.pingProfiles[index]
		local rhs = other.pingProfiles[index]
		if not lhs or not rhs then
			return false
		end

		if lhs.ping ~= rhs.ping or lhs.when ~= rhs.when or lhs.samples ~= rhs.samples then
			return false
		end
	end

	return true
end

---Clone action.
---@return Action
function Action:clone()
	local clone = Action.new()

	clone._type = self._type
	clone._when = self._when
	clone.name = self.name
	clone.hitbox = self.hitbox
	clone.ihbc = self.ihbc
	clone.pingProfiles = {}

	for _, profile in ipairs(self.pingProfiles or {}) do
		table.insert(clone.pingProfiles, {
			ping = profile.ping,
			when = profile.when,
			samples = profile.samples,
		})
	end

	return clone
end

---Return a serializable table.
---@return table
function Action:serialize()
	return {
		_type = self._type,
		when = self._when,
		name = self.name,
		hitbox = {
			X = self.hitbox.X,
			Y = self.hitbox.Y,
			Z = self.hitbox.Z,
		},
		ihbc = self.ihbc,
			pingProfiles = self.pingProfiles,
	}
end

---Create new Action object.
---@param values table?
---@return Action
function Action.new(values)
	local self = setmetatable({}, Action)

	self._type = "N/A"
	self._when = 0
	self.name = ""
	self.hitbox = Vector3.zero
	self.ihbc = false
	self.pingProfiles = {}
	self.tp = 0

	if values then
		self:load(values)
	end

	return self
end

-- Return Action module.
return Action
