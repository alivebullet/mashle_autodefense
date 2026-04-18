local NetworkLatency = {}

-- Services.
local stats = game:GetService("Stats")

-- Constants.
local MAX_SAMPLES = 12
local REFRESH_INTERVAL_S = 0.05
local EMA_ALPHA = 0.35

-- State.
local samples = {}
local emaMs = nil
local lastRefreshAt = 0

---Read the raw Roblox data ping value in milliseconds.
---@return number?
local function rawPingMs()
	local network = stats:FindFirstChild("Network")
	if not network then
		return nil
	end

	local serverStatsItem = network:FindFirstChild("ServerStatsItem")
	if not serverStatsItem then
		return nil
	end

	local dataPingItem = serverStatsItem:FindFirstChild("Data Ping")
	if not dataPingItem then
		return nil
	end

	local ok, value = pcall(function()
		return dataPingItem:GetValue()
	end)
	if not ok or type(value) ~= "number" then
		return nil
	end

	return value
end

---Median of a numeric list.
---@param values number[]
---@return number?
local function median(values)
	if #values == 0 then
		return nil
	end

	local sorted = table.clone(values)
	table.sort(sorted)
	return sorted[math.ceil(#sorted / 2)]
end

---Refresh the rolling ping state at most once per interval.
local function refresh()
	local now = os.clock()
	if (now - lastRefreshAt) < REFRESH_INTERVAL_S then
		return
	end

	lastRefreshAt = now

	local raw = rawPingMs()
	if type(raw) ~= "number" then
		return
	end

	samples[#samples + 1] = raw
	while #samples > MAX_SAMPLES do
		table.remove(samples, 1)
	end

	emaMs = emaMs and (emaMs + ((raw - emaMs) * EMA_ALPHA)) or raw
end

---Return the smoothed full RTT in milliseconds.
---@return number
function NetworkLatency.rttMilliseconds()
	refresh()

	local raw = rawPingMs()
	local medianMs = median(samples)
	if type(medianMs) ~= "number" and type(raw) == "number" then
		return raw
	end

	if type(medianMs) ~= "number" then
		return 0
	end

	if type(emaMs) ~= "number" then
		return medianMs
	end

	return math.max(0, (medianMs * 0.7) + (emaMs * 0.3))
end

---Return the smoothed full RTT in seconds.
---@return number
function NetworkLatency.rttSeconds()
	return NetworkLatency.rttMilliseconds() * 0.001
end

return NetworkLatency