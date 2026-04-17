return LPH_NO_VIRTUALIZE(function()
	-- TimingHarvester module.
	-- Accumulates labelled parry samples from live play: every time a nearby animation
	-- starts, every time we press parry, every time Parry/PerfectParry flips true, every
	-- time we take damage. A solver turns those samples into an AnimationTiming and can
	-- promote it to the active config.
	local TimingHarvester = {}

	---@module Utility.Maid
	local Maid = require("Utility/Maid")

	---@module Utility.Logger
	local Logger = require("Utility/Logger")

	---@module Utility.Configuration
	local Configuration = require("Utility/Configuration")

	-- Services.
	local players = game:GetService("Players")
	local stats = game:GetService("Stats")

	-- State.
	local harvesterMaid = Maid.new()
	local damageMaid = Maid.new()
	local isInit = false

	-- Ring buffer of recent nearby animation plays.
	-- Each entry: { aid, entity, entityName, t0, speed, length, distance }
	local recentAnims = {}

	-- In-flight press. Set on onParryPress, consumed by outcome flip or timeout.
	local pendingPress = nil

	-- Sample DB: [aid] = { meta = { aid, entityName, firstSeenAt }, pressSamples = {...}, hitSamples = {...} }
	local samples = {}

	-- Tuning constants.
	local MAX_RECENT_ANIMS = 24
	local ANIM_LOOKBACK_S = 2.0
	local MAX_PRESS_OFFSET_S = 1.5
	local OUTCOME_WAIT_S = 0.5
	local ATTRIB_MAX_DISTANCE = 60

	---Get full RTT in seconds from Stats.Network.ServerStatsItem."Data Ping" (ms).
	---@return number
	local function rttSeconds()
		local network = stats:FindFirstChild("Network")
		if not network then
			return 0
		end

		local serverStatsItem = network:FindFirstChild("ServerStatsItem")
		if not serverStatsItem then
			return 0
		end

		local dataPing = serverStatsItem:FindFirstChild("Data Ping")
		if not dataPing then
			return 0
		end

		local ok, v = pcall(function()
			return dataPing:GetValue()
		end)
		return (ok and type(v) == "number") and (v * 0.001) or 0
	end

	---Distance from local player to an entity (nil if unknown).
	---@param entity Model?
	---@return number?
	local function distanceTo(entity)
		local localChar = players.LocalPlayer and players.LocalPlayer.Character
		if not localChar or not localChar.PrimaryPart or not entity then
			return nil
		end

		local target = entity:IsA("Model") and entity.PrimaryPart
			or entity:FindFirstChildWhichIsA("BasePart", true)
		if not target then
			return nil
		end

		return (localChar.PrimaryPart.Position - target.Position).Magnitude
	end

	---Is the harvester enabled via config toggle?
	---@return boolean
	local function enabled()
		return Configuration.expectToggleValue("EnableTimingHarvester") == true
	end

	---Find the animation most likely responsible for an outcome observed at time t.
	---@param t number
	---@return table?
	local function pickCandidate(t)
		local cutoff = t - ANIM_LOOKBACK_S
		local best, bestOffset = nil, math.huge

		for i = #recentAnims, 1, -1 do
			local a = recentAnims[i]
			if a.t0 < cutoff then
				break
			end

			local off = t - a.t0
			if off >= 0 and off <= MAX_PRESS_OFFSET_S then
				-- Prefer most recent in-distance animation.
				local dist = distanceTo(a.entity) or a.distance or math.huge
				if dist <= ATTRIB_MAX_DISTANCE and off < bestOffset then
					bestOffset = off
					best = a
					best._attribDist = dist
				end
			end
		end

		return best
	end

	---Get or create a sample bucket for an animation id.
	---@param aid string
	---@param entityName string
	---@param priority string?
	---@return table
	local function bucket(aid, entityName, priority)
		local b = samples[aid]
		if not b then
			b = {
				meta = { aid = aid, entityName = entityName, firstSeenAt = tick(), priority = priority or "?" },
				pressSamples = {},
				hitSamples = {},
			}
			samples[aid] = b
		end
		return b
	end

	---Convert observed client-side press offset into server-side animation time position.
	---@param clientOffset number
	---@param speed number
	---@param ping number
	---@return number
	local function toServerAnimTime(clientOffset, speed, ping)
		-- Server-side wall-clock offset = client offset + full RTT (anim start lag + press travel).
		-- Convert to animation-local time by multiplying by playback speed.
		return (clientOffset + ping) * (speed or 1.0)
	end

	---Record an animation start seen from a nearby entity.
	---@param aid string
	---@param entity Model?
	---@param track AnimationTrack?
	function TimingHarvester.onAnimationStart(aid, entity, track)
		if not enabled() then
			return
		end

		if not aid or aid == "" or aid == "Unknown" then
			return
		end

		-- Skip non-combat animations (Idle, Movement, Core).
		if track and track.Priority then
			local pri = track.Priority
			if pri == Enum.AnimationPriority.Core
				or pri == Enum.AnimationPriority.Idle
				or pri == Enum.AnimationPriority.Movement then
				return
			end
		end

		table.insert(recentAnims, {
			aid = aid,
			entity = entity,
			entityName = entity and entity.Name or "?",
			t0 = tick(),
			speed = (track and track.Speed) or 1.0,
			length = (track and track.Length) or 0,
			distance = distanceTo(entity),
			priority = (track and track.Priority) and track.Priority.Name or "?",
		})

		if #recentAnims > MAX_RECENT_ANIMS then
			table.remove(recentAnims, 1)
		end
	end

	---Record a parry press. Opens a pending-outcome window.
	function TimingHarvester.onParryPress()
		if not enabled() then
			return
		end

		local t = tick()
		local myPress = { t = t, resolved = false }
		pendingPress = myPress

		task.delay(OUTCOME_WAIT_S, function()
			if myPress.resolved or pendingPress ~= myPress then
				return
			end

			-- No flip arrived: record as a failed press sample.
			local candidate = pickCandidate(t)
			if not candidate then
				return
			end

			local ping = rttSeconds()
			local clientOffset = t - candidate.t0
			local serverWhen = toServerAnimTime(clientOffset, candidate.speed, ping)

			local b = bucket(candidate.aid, candidate.entityName, candidate.priority)
			table.insert(b.pressSamples, {
				when = serverWhen,
				clientOffset = clientOffset,
				perfect = false,
				parried = false,
				distance = candidate._attribDist,
				ping = ping,
				t = t,
			})

			myPress.resolved = true
		end)
	end

	---Record a Parry or PerfectParry BoolValue flipping true.
	---@param perfect boolean
	function TimingHarvester.onParryResult(perfect)
		if not enabled() then
			return
		end

		local now = tick()
		local ping = rttSeconds()

		-- Outcome arrives ~ping/2 after the server processed. Attribute to the press time
		-- if we have a pending press; otherwise to now minus ping/2.
		local effectiveT = (pendingPress and not pendingPress.resolved) and pendingPress.t
			or (now - ping * 0.5)

		local candidate = pickCandidate(effectiveT)
		if not candidate then
			return
		end

		local clientOffset = effectiveT - candidate.t0
		local serverWhen = toServerAnimTime(clientOffset, candidate.speed, ping)

		local b = bucket(candidate.aid, candidate.entityName, candidate.priority)
		table.insert(b.pressSamples, {
			when = serverWhen,
			clientOffset = clientOffset,
			perfect = perfect,
			parried = true,
			distance = candidate._attribDist,
			ping = ping,
			t = now,
		})

		if pendingPress then
			pendingPress.resolved = true
		end
	end

	---Record local player taking damage. Attributes to the most recent nearby animation.
	local function onDamageObserved()
		if not enabled() then
			return
		end

		local now = tick()
		local ping = rttSeconds()

		-- Damage arrives ~ping/2 after server-side hit processing.
		local effectiveT = now - ping * 0.5
		local candidate = pickCandidate(effectiveT)
		if not candidate then
			return
		end

		local clientOffset = effectiveT - candidate.t0
		local serverWhen = toServerAnimTime(clientOffset, candidate.speed, ping)

		local b = bucket(candidate.aid, candidate.entityName, candidate.priority)
		table.insert(b.hitSamples, {
			when = serverWhen,
			clientOffset = clientOffset,
			distance = candidate._attribDist,
			ping = ping,
			t = now,
		})
	end

	---Attach a HealthChanged listener to the local humanoid.
	---@param character Model
	local function hookDamage(character)
		damageMaid:clean()

		local humanoid = character:FindFirstChildWhichIsA("Humanoid")
		if not humanoid then
			return
		end

		local lastHealth = humanoid.Health
		damageMaid:add(humanoid.HealthChanged:Connect(function(h)
			if h < lastHealth then
				lastHealth = h
				onDamageObserved()
			else
				lastHealth = h
			end
		end))
	end

	---Median of a numeric list (sorted).
	---@param t number[]
	---@return number?
	local function median(t)
		if #t == 0 then
			return nil
		end
		local s = table.clone(t)
		table.sort(s)
		return s[math.ceil(#s / 2)]
	end

	---Percentile of a numeric list.
	---@param t number[]
	---@param p number 0..1
	---@return number?
	local function percentile(t, p)
		if #t == 0 then
			return nil
		end
		local s = table.clone(t)
		table.sort(s)
		local idx = math.max(1, math.min(#s, math.ceil(#s * p)))
		return s[idx]
	end

	---Solve a timing estimate from accumulated samples.
	---@param aid string
	---@return table?
	function TimingHarvester.solve(aid)
		local b = samples[aid]
		if not b then
			return nil
		end

		local perfectWhens, parryWhens, failWhens, hitWhens, distances, pings = {}, {}, {}, {}, {}, {}

		for _, s in ipairs(b.pressSamples) do
			if s.parried then
				table.insert(parryWhens, s.when)
				if s.perfect then
					table.insert(perfectWhens, s.when)
				end
			else
				table.insert(failWhens, s.when)
			end

			if s.distance then
				table.insert(distances, s.distance)
			end

			if s.ping then
				table.insert(pings, s.ping)
			end
		end

		for _, s in ipairs(b.hitSamples) do
			table.insert(hitWhens, s.when)
			if s.distance then
				table.insert(distances, s.distance)
			end

			if s.ping then
				table.insert(pings, s.ping)
			end
		end

		-- Prefer Perfect Parry median (tightest window) when we have any; else median
		-- across all successful parry presses; else median across damage hits.
		local bestWhen = median(perfectWhens) or median(parryWhens) or median(hitWhens)
		if not bestWhen then
			return {
				aid = aid,
				entityName = b.meta.entityName,
				sampleCount = #b.pressSamples + #b.hitSamples,
				perfectCount = #perfectWhens,
				parryCount = #parryWhens,
				failCount = #failWhens,
				hitCount = #hitWhens,
				bestWhen = nil,
			}
		end

		local minDist = #distances > 0 and math.min(table.unpack(distances)) or 0
		local maxDist = #distances > 0 and math.max(table.unpack(distances)) or 100

		return {
			aid = aid,
			entityName = b.meta.entityName,
			sampleCount = #b.pressSamples + #b.hitSamples,
			perfectCount = #perfectWhens,
			parryCount = #parryWhens,
			failCount = #failWhens,
			hitCount = #hitWhens,
			bestWhen = bestWhen,
			perfectRange = {
				lo = percentile(perfectWhens, 0.1),
				hi = percentile(perfectWhens, 0.9),
			},
			parryRange = {
				lo = percentile(parryWhens, 0.1),
				hi = percentile(parryWhens, 0.9),
			},
			hitRange = {
				lo = percentile(hitWhens, 0.1),
				hi = percentile(hitWhens, 0.9),
			},
			medianPingMs = (median(pings) or 0) * 1000,
			minDistance = minDist,
			maxDistance = maxDist,
			-- Confidence scales with successful parry count.
			confidence = math.min(1.0, (#perfectWhens + #parryWhens) / 8),
		}
	end

	---Return the raw samples table for external UI.
	---@return table
	function TimingHarvester.getSamples()
		return samples
	end

	---List harvested animations (one label per aid) for a dropdown.
	---@return string[]
	function TimingHarvester.list()
		local out = {}
		for aid, b in next, samples do
			local solved = TimingHarvester.solve(aid)
			local label
			if solved and solved.bestWhen then
				label = string.format(
					"[%s] %s (%s) n=%d/P%d/p%d/f%d when=%dms",
					b.meta.priority or "?",
					b.meta.entityName,
					aid,
					solved.sampleCount,
					solved.perfectCount,
					solved.parryCount,
					solved.failCount,
					math.round((solved.bestWhen or 0) * 1000)
				)
			else
				label = string.format("[%s] %s (%s) n=%d no-solve", b.meta.priority or "?", b.meta.entityName, aid, (solved and solved.sampleCount) or 0)
			end
			table.insert(out, label)
		end
		table.sort(out)
		return out
	end

	---Extract aid from a list label.
	---@param label string
	---@return string?
	function TimingHarvester.aidFromLabel(label)
		return label and label:match("%((rbxassetid://%d+)%)")
	end

	---Dump a readable summary of all accumulated samples to the Logger window.
	function TimingHarvester.dump()
		local n = 0
		for aid, b in next, samples do
			n = n + 1
			local solved = TimingHarvester.solve(aid)
			if solved and solved.bestWhen then
				Logger.warn(
					"[Harvester] %s %s: n=%d perfect=%d parry=%d fail=%d hit=%d when=%.0fms dist=[%.1f,%.1f] conf=%.2f",
					b.meta.entityName,
					aid,
					solved.sampleCount,
					solved.perfectCount,
					solved.parryCount,
					solved.failCount,
					solved.hitCount,
					(solved.bestWhen or 0) * 1000,
					solved.minDistance,
					solved.maxDistance,
					solved.confidence
				)
			else
				Logger.warn("[Harvester] %s %s: n=%d (not solvable yet)", b.meta.entityName, aid, (solved and solved.sampleCount) or 0)
			end
		end
		if n == 0 then
			Logger.warn("[Harvester] no samples collected yet.")
		end
	end

	---Promote a solved timing to the active config.
	---@param aid string
	---@param timingName string?
	---@return boolean, string
	function TimingHarvester.promoteToConfig(aid, timingName)
		local SaveManager = require("Game/Timings/SaveManager")
		local AnimationTiming = require("Game/Timings/AnimationTiming")
		local Action = require("Game/Timings/Action")

		local function getParryAction(timing)
			for _, action in next, timing.actions:get() do
				if action._type == "Parry" then
					return action
				end
			end
		end

		local solved = TimingHarvester.solve(aid)
		if not solved then
			return false, "No samples for aid: " .. tostring(aid)
		end

		if not solved.bestWhen then
			return false, string.format("Not enough successful samples for %s (n=%d).", aid, solved.sampleCount)
		end

		if not SaveManager.as then
			return false, "SaveManager not ready."
		end

		local whenMs = math.round(solved.bestWhen * 1000)
		local profilePingMs = math.max(0, math.round(solved.medianPingMs or (rttSeconds() * 1000)))
		local existingConfig = SaveManager.as.config and SaveManager.as.config.timings[aid]

		if existingConfig then
			local action = getParryAction(existingConfig)
			if not action then
				action = Action.new()
				action.name = string.format("Action_Harvested_n%d", solved.sampleCount)
				action._type = "Parry"
				action.hitbox = Vector3.new(20, 20, 30)
				action.ihbc = false
				existingConfig.actions:push(action)
			end

			action._when = PP_SCRAMBLE_RE_NUM(whenMs)
			action:addPingProfile(profilePingMs, whenMs, solved.sampleCount)

			existingConfig.imdd = math.max(0, math.min(existingConfig.imdd or solved.minDistance, solved.minDistance))
			existingConfig.imxd = math.max(existingConfig.imxd or solved.maxDistance, solved.maxDistance)

			Logger.notify(
				"[Harvester] Updated '%s' with %.0fms @ %dms RTT (%d profiles).",
				existingConfig.name,
				solved.bestWhen * 1000,
				profilePingMs,
				#(action.pingProfiles or {})
			)

			return true, existingConfig.name
		end

		local name = timingName
		if not name or #name <= 0 then
			local shortId = aid:match("(%d+)$") or tostring(math.floor(tick()))
			name = string.format("%s_%s_Harvested", solved.entityName, shortId)
		end

		local existingName = SaveManager.as:find(name)
		if existingName then
			return false, string.format("Timing name '%s' already exists.", name)
		end

		local timing = AnimationTiming.new()
		timing._id = aid
		timing.name = name
		timing.tag = "Undefined"
		timing.imdd = math.max(0, math.floor(solved.minDistance - 2))
		timing.imxd = math.ceil(solved.maxDistance + 5)
		timing.hitbox = Vector3.new(20, 20, 30)
		timing.fhb = true
		timing.pfh = true
		timing.pfht = 0.15

		local action = Action.new()
		action.name = string.format("Action_Harvested_n%d", solved.sampleCount)
		action._type = "Parry"
		action._when = PP_SCRAMBLE_RE_NUM(whenMs)
		action.hitbox = Vector3.new(20, 20, 30)
		action.ihbc = false
		action:addPingProfile(profilePingMs, whenMs, solved.sampleCount)
		timing.actions:push(action)

		local ok, err = pcall(SaveManager.as.config.push, SaveManager.as.config, timing)
		if not ok then
			return false, "Failed to push timing: " .. tostring(err)
		end

		Logger.notify(
			"[Harvester] Promoted '%s' when=%.0fms @ %dms RTT (n=%d perfect=%d parry=%d conf=%.2f).",
			name,
			solved.bestWhen * 1000,
			profilePingMs,
			solved.sampleCount,
			solved.perfectCount,
			solved.parryCount,
			solved.confidence
		)

		return true, name
	end

	---Promote every solvable sample bucket to config.
	---@return number, number
	function TimingHarvester.promoteAll()
		local successCount, failCount = 0, 0
		for aid, _ in next, samples do
			local ok, _ = TimingHarvester.promoteToConfig(aid)
			if ok then
				successCount = successCount + 1
			else
				failCount = failCount + 1
			end
		end
		Logger.notify("[Harvester] Promoted %d timings (%d skipped/failed).", successCount, failCount)
		return successCount, failCount
	end

	---Clear all state.
	function TimingHarvester.clear()
		samples = {}
		recentAnims = {}
		pendingPress = nil
		Logger.notify("[Harvester] Cleared all samples.")
	end

	---Return live totals for UI display.
	---@return number, number
	function TimingHarvester.counts()
		local totalSamples, aidCount = 0, 0
		for _, b in next, samples do
			aidCount = aidCount + 1
			totalSamples = totalSamples + #b.pressSamples + #b.hitSamples
		end
		return aidCount, totalSamples
	end

	---Initialize.
	function TimingHarvester.init()
		if isInit then
			return
		end
		isInit = true

		local localPlayer = players.LocalPlayer
		if not localPlayer then
			return
		end

		if localPlayer.Character then
			hookDamage(localPlayer.Character)
		end

		harvesterMaid:add(localPlayer.CharacterAdded:Connect(function(char)
			task.defer(function()
				hookDamage(char)
			end)
		end))
	end

	---Detach.
	function TimingHarvester.detach()
		harvesterMaid:clean()
		damageMaid:clean()
		samples = {}
		recentAnims = {}
		pendingPress = nil
		isInit = false
	end

	return TimingHarvester
end)()
