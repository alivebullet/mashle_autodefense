---@module Game.Timings.TimingContainer
local TimingContainer = require("Game/Timings/TimingContainer")

---@module Game.Timings.AnimationTiming
local AnimationTiming = require("Game/Timings/AnimationTiming")

---@module Game.Timings.PartTiming
local PartTiming = require("Game/Timings/PartTiming")

---@module Game.Timings.SoundTiming
local SoundTiming = require("Game/Timings/SoundTiming")

---@class TimingSave
---@field _data TimingContainer[]
---@field _meta table
local TimingSave = {}
TimingSave.__index = TimingSave

---Timing save version constant.
---@note: Increment me when the data structure changes and we need to add backwards compatibility.
local TIMING_SAVE_VERSION = 2

---Clone a serializable value.
---@param value any
---@return any
local function cloneValue(value)
	if typeof(value) ~= "table" then
		return value
	end

	local out = {}
	for key, inner in next, value do
		out[key] = cloneValue(inner)
	end

	return out
end

---Merge two metadata tables recursively.
---@param base table?
---@param incoming table?
---@return table
local function mergeMetadata(base, incoming)
	local merged = cloneValue(base or {})
	if typeof(incoming) ~= "table" then
		return merged
	end

	for key, value in next, incoming do
		if typeof(value) == "table" and typeof(merged[key]) == "table" then
			merged[key] = mergeMetadata(merged[key], value)
		else
			merged[key] = cloneValue(value)
		end
	end

	return merged
end

---Compare serializable values.
---@param first any
---@param second any
---@return boolean
local function valuesEqual(first, second)
	if typeof(first) ~= typeof(second) then
		return false
	end

	if typeof(first) ~= "table" then
		return first == second
	end

	local seen = {}
	for key, value in next, first do
		if not valuesEqual(value, second[key]) then
			return false
		end
		seen[key] = true
	end

	for key in next, second do
		if not seen[key] then
			return false
		end
	end

	return true
end

---@alias MergeType
---| '1' # Only add new timings
---| '2' # Overwrite and add everything

---Get timing save.
---@return TimingContainer[]
function TimingSave:get()
	return self._data
end

---Get save metadata.
---@return table
function TimingSave:metadata()
	return self._meta
end

---Clear timing containers.
function TimingSave:clear()
	for _, container in next, self._data do
		container:clear()
	end

	self._meta = {}
end

---Merge with another TimingSave object.
---@param save TimingSave The other save.
---@param type MergeType
function TimingSave:merge(save, type)
	for idx, other in next, save._data do
		local container = self._data[idx]
		if not container then
			continue
		end

		container:merge(other, type)
	end

	self._meta = mergeMetadata(self._meta, save._meta)
end

---Load from partial values.
---@param values table
function TimingSave:load(values)
	local data = self._data
	self._meta = typeof(values.meta) == "table" and cloneValue(values.meta) or {}

	if typeof(values.animation) == "table" then
		data.animation:load(values.animation)
	end

	if typeof(values.part) == "table" then
		data.part:load(values.part)
	end

	if typeof(values.sound) == "table" then
		data.sound:load(values.sound)
	end
end

---Clone timing save.
---@return TimingSave
function TimingSave:clone()
	local save = TimingSave.new()

	for idx, container in next, self._data do
		save._data[idx] = container:clone()
	end

	save._meta = cloneValue(self._meta)

	return save
end

---Equal timing saves.
---@param other TimingSave
---@return boolean
function TimingSave:equals(other)
	if not other or typeof(other) ~= "table" then
		return false
	end

	for idx, container in next, self._data do
		local otherContainer = other._data[idx]
		if not otherContainer then
			return false
		end

		if not container:equals(otherContainer) then
			return false
		end
	end

	return valuesEqual(self._meta, other._meta)
end

---Get timing save count.
---@return number
function TimingSave:count()
	local count = 0

	for _, container in next, self._data do
		count = count + container:count()
	end

	return count
end

---Return a serializable table.
---@return table
function TimingSave:serialize()
	local data = self._data

	return {
		version = TIMING_SAVE_VERSION,
		animation = data.animation:serialize(),
		part = data.part:serialize(),
		sound = data.sound:serialize(),
		meta = cloneValue(self._meta),
	}
end

---Create new TimingSave object.
---@param values table?
---@return TimingSave
function TimingSave.new(values)
	local self = setmetatable({}, TimingSave)

	self._data = {
		animation = TimingContainer.new(AnimationTiming),
		part = TimingContainer.new(PartTiming),
		sound = TimingContainer.new(SoundTiming),
	}
	self._meta = {}

	if values then
		self:load(values)
	end

	return self
end

-- Return TimingSave module.
return TimingSave
