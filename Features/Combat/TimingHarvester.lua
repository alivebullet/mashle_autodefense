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

	---@module Utility.NetworkLatency
	local NetworkLatency = require("Utility/NetworkLatency")

	-- Services.
	local players = game:GetService("Players")

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

	-- Observed combat animations, even if they never produced usable samples.
	-- Key: animation ID, Value: { meta = { aid, entityName, priority, firstSeenAt, lastSeenAt }, seenCount = number }
	local observedAnims = {}

	-- User-banned animation IDs that should be ignored by logger + harvester.
	-- Key: animation ID, Value: { meta = {...}, sampleCount = number, seenCount = number }
	local bannedAnims = {}

	-- Persisted damage-based hitbox learning loaded from the active config metadata.
	-- Key: animation ID, Value: { entityName = string, samples = { { t, when, x, y, z } } }
	local persistedHitboxLearning = {}

	-- Per-animation cache for solved live hitbox state.
	local hitboxStateVersions = {}
	local hitboxStateCache = {}

	-- Tuning constants.
	local MAX_RECENT_ANIMS = 24
	local ANIM_LOOKBACK_S = 2.0
	local MAX_PRESS_OFFSET_S = 1.5
	local OUTCOME_WAIT_S = 0.5
	local ATTRIB_MAX_DISTANCE = 60
	local EARLY_SUCCESS_WINDOW_POSITION = 0.35
	local HIT_FALLBACK_LEAD_S = 0.05
	-- Hitbox learning.
	local HITBOX_AXIS_PERCENTILE = 0.95
	local HITBOX_PAD_WIDTH = 2
	local HITBOX_PAD_HEIGHT = 2
	local HITBOX_PAD_DEPTH = 4
	local DEFAULT_HITBOX = Vector3.new(20, 20, 30)
	local HITBOX_MIN_EXTENT = Vector3.new(8, 8, 12)
	local HITBOX_MAX_EXTENT = Vector3.new(40, 30, 50)
	local MIN_HITBOX_SAMPLES = 3
	local MIN_HITBOX_ADAPT_SAMPLES = 6
	local MAX_PERSISTED_HITBOX_SAMPLES = 96
	local MIN_HITBOX_SHRINK_SAMPLES = 12
	local MIN_HITBOX_SHRINK_RECENT_SAMPLES = 6
	local HITBOX_RECENT_CONFIRMATION_SAMPLES = 8
	local HITBOX_MOTION_NEIGHBORS = 5
	local HITBOX_MOTION_WEIGHT_FLOOR = 0.02
	local HITBOX_SHRINK_TOLERANCE = Vector3.new(0.5, 0.5, 1)

	---Return the normalized model for an entity-like instance.
	---@param entity Instance?
	---@return Model?
	local function entityModel(entity)
		if typeof(entity) ~= "Instance" then
			return nil
		end

		if entity:IsA("Model") then
			return entity
		end

		return entity:FindFirstAncestorOfClass("Model")
	end

	---Invalidate cached hitbox state for an animation id.
	---@param aid string?
	local function invalidateHitboxState(aid)
		if type(aid) ~= "string" or aid == "" then
			return
		end

		hitboxStateVersions[aid] = (hitboxStateVersions[aid] or 0) + 1
		hitboxStateCache[aid] = nil
	end

	---Clear all cached hitbox state.
	local function clearHitboxStateCache()
		hitboxStateVersions = {}
		hitboxStateCache = {}
	end

	---Get the display label for an entity inside the harvester.
	---@param entity Model?
	---@return string
	local function entityLabel(entity)
		entity = entityModel(entity)
		if typeof(entity) ~= "Instance" then
			return "?"
		end

		if players:GetPlayerFromCharacter(entity) then
			return "Player"
		end

		return entity.Name or "?"
	end

	---Return a stable scale signature for the entity's humanoid.
	---@param entity Model?
	---@return string
	local function entityScaleSignature(entity)
		local humanoid = entity and entity:FindFirstChildWhichIsA("Humanoid")
		if not humanoid then
			return "default"
		end

		local function scaleValue(name)
			local value = humanoid:FindFirstChild(name)
			if value and value:IsA("NumberValue") then
				return value.Value
			end

			return 1
		end

		return string.format(
			"%s:%.3f:%.3f:%.3f:%.3f:%.3f",
			humanoid.RigType.Name,
			scaleValue("BodyHeightScale"),
			scaleValue("BodyWidthScale"),
			scaleValue("BodyDepthScale"),
			scaleValue("HeadScale"),
			type(humanoid.HipHeight) == "number" and humanoid.HipHeight or 0
		)
	end

	---Return a stable actor profile key for hitbox learning.
	---@param entity Instance?
	---@return string?
	local function actorProfileKey(entity)
		local model = entityModel(entity)
		if not model then
			return nil
		end

		local player = players:GetPlayerFromCharacter(model)
		local scale = entityScaleSignature(model)
		if player then
			return string.format("player:%d:%s", player.UserId, scale)
		end

		return string.format("npc:%s:%s", model.Name or "?", scale)
	end

	---Return the cache key used for actor-specific hitbox learning.
	---@param aid string
	---@param actorKey string?
	---@return string
	local function hitboxLearningKey(aid, actorKey)
		return string.format("%s|%s", aid, actorKey or "*")
	end

	---Create a serializable banned entry.
	---@param aid string
	---@param info table?
	---@return table
	local function persistentBannedEntry(aid, info)
		local meta = type(info) == "table" and type(info.meta) == "table" and info.meta or {}
		return {
			meta = {
				aid = aid,
				entityName = type(meta.entityName) == "string" and meta.entityName or "?",
				priority = type(meta.priority) == "string" and meta.priority or "?",
				bannedAt = type(meta.bannedAt) == "number" and meta.bannedAt or 0,
			},
			sampleCount = type(info) == "table" and type(info.sampleCount) == "number" and info.sampleCount or 0,
			seenCount = type(info) == "table" and type(info.seenCount) == "number" and info.seenCount or 0,
		}
	end

	---Create a serializable hitbox sample entry.
	---@param info table?
	---@return table?
	local function persistentHitboxSample(info)
		if type(info) ~= "table" then
			return nil
		end

		local x = type(info.x) == "number" and info.x or nil
		local y = type(info.y) == "number" and info.y or nil
		local z = type(info.z) == "number" and info.z or nil
		if x == nil or y == nil or z == nil then
			return nil
		end

		return {
			t = type(info.t) == "number" and info.t or 0,
			when = type(info.when) == "number" and info.when or 0,
			x = x,
			y = y,
			z = z,
			actorKey = type(info.actorKey) == "string" and info.actorKey or nil,
		}
	end

	---Create a serializable hitbox learning entry.
	---@param aid string
	---@param info table?
	---@return table
	local function persistentHitboxLearningEntry(aid, info)
		local samplesOut = {}
		local sourceSamples = type(info) == "table" and type(info.samples) == "table" and info.samples or {}

		for _, sample in ipairs(sourceSamples) do
			local normalized = persistentHitboxSample(sample)
			if normalized then
				table.insert(samplesOut, normalized)
			end
		end

		table.sort(samplesOut, function(lhs, rhs)
			return (lhs.t or 0) < (rhs.t or 0)
		end)

		while #samplesOut > MAX_PERSISTED_HITBOX_SAMPLES do
			table.remove(samplesOut, 1)
		end

		return {
			aid = aid,
			entityName = type(info) == "table" and type(info.entityName) == "string" and info.entityName or "?",
			actorKey = type(info) == "table" and type(info.actorKey) == "string" and info.actorKey or nil,
			samples = samplesOut,
		}
	end

	---Get the current harvester minimum distance.
	---@return number
	local function harvesterMinDistance()
		return Configuration.expectOptionValue("TimingHarvesterMinDistance") or 0
	end

	---Get the current harvester maximum distance.
	---@return number
	local function harvesterMaxDistance()
		local value = Configuration.expectOptionValue("TimingHarvesterMaxDistance")
		if type(value) ~= "number" or value <= 0 then
			return ATTRIB_MAX_DISTANCE
		end

		return value
	end

	---Local-space offset from the attacker's CFrame to the local player's root position.
	---Negative Z is in front of the attacker; X is right; Y is up.
	---@param attacker Model?
	---@return Vector3?
	local function localOffsetFromAttacker(attacker)
		if typeof(attacker) ~= "Instance" then
			return nil
		end

		local localChar = players.LocalPlayer and players.LocalPlayer.Character
		if not localChar or not localChar.PrimaryPart then
			return nil
		end

		local attackerPart = attacker:IsA("Model") and attacker.PrimaryPart
			or attacker:FindFirstChildWhichIsA("BasePart", true)
		if not attackerPart then
			return nil
		end

		return attackerPart.CFrame:PointToObjectSpace(localChar.PrimaryPart.Position)
	end

	---Distance from local player to an entity (nil if unknown).
	---@param entity Model?
	---@return number?
	local function distanceTo(entity)
		if typeof(entity) ~= "Instance" then
			return nil
		end

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

	---Check whether the harvester should consider an entity at its current distance.
	---@param entity Model?
	---@return boolean, number?, Instance?
	local function shouldTrackEntity(entity)
		entity = entityModel(entity)
		if typeof(entity) ~= "Instance" then
			return false, nil, nil
		end

		local distance = distanceTo(entity)
		if not distance then
			return false, nil, entity
		end

		if Configuration.expectToggleValue("TimingHarvesterIgnorePlayers") ~= false then
			local player = players:GetPlayerFromCharacter(entity)
			if player then
				return false, distance, entity
			end
		end

		if distance < harvesterMinDistance() or distance > harvesterMaxDistance() then
			return false, distance, entity
		end

		return true, distance, entity
	end

	---Count samples for a given animation id.
	---@param aid string
	---@return number
	local function sampleCountFor(aid)
		local b = samples[aid]
		if not b then
			return 0
		end

		return #b.pressSamples + #b.hitSamples
	end

	---Track that an animation id was observed in combat.
	---@param aid string
	---@param entityName string
	---@param priority string?
	local function markObserved(aid, entityName, priority)
		local info = observedAnims[aid]
		if not info then
			info = {
				meta = {
					aid = aid,
					entityName = entityName,
					priority = priority or "?",
					firstSeenAt = tick(),
					lastSeenAt = tick(),
				},
				seenCount = 0,
			}
			observedAnims[aid] = info
		end

		info.meta.entityName = entityName or info.meta.entityName or "?"
		info.meta.priority = priority or info.meta.priority or "?"
		info.meta.lastSeenAt = tick()
		info.seenCount = (info.seenCount or 0) + 1
	end

	---Remove all recent buffered animation starts for an animation id.
	---@param aid string
	local function pruneRecent(aid)
		local filtered = {}
		for _, entry in ipairs(recentAnims) do
			if entry.aid ~= aid then
				table.insert(filtered, entry)
			end
		end
		recentAnims = filtered
	end

	---Get full RTT in seconds from Stats.Network.ServerStatsItem."Data Ping" (ms).
	---@return number
	local function rttSeconds()
		return NetworkLatency.rttSeconds()
	end

	---Is the harvester enabled via config toggle?
	---@return boolean
	local function enabled()
		return Configuration.expectToggleValue("EnableTimingHarvester") == true
	end

	---Should combat samples be collected for live hitbox learning?
	---@return boolean
	local function sampleCollectionEnabled()
		return enabled() or Configuration.expectToggleValue("EnableAutoDefense") == true
	end

	---Find the animation most likely responsible for an outcome observed at time t.
	---@param t number
	---@return table?
	local function pickCandidate(t)
		local cutoff = t - ANIM_LOOKBACK_S
		local maxDist = harvesterMaxDistance()
		local best, bestOffset = nil, math.huge

		for i = #recentAnims, 1, -1 do
			local a = recentAnims[i]
			if a.t0 < cutoff then
				break
			end

			if bannedAnims[a.aid] then
				continue
			end

			local off = t - a.t0
			if off >= 0 and off <= MAX_PRESS_OFFSET_S then
				-- Prefer most recent in-distance animation.
				local dist = distanceTo(a.entity) or a.distance or math.huge
				if dist <= maxDist and off < bestOffset then
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
		if not sampleCollectionEnabled() then
			return
		end

		if not aid or aid == "" or aid == "Unknown" then
			return
		end

		if bannedAnims[aid] then
			return
		end

		local trackEntity, currentDistance, resolvedEntity = shouldTrackEntity(entity)
		if not trackEntity then
			return
		end

		-- Skip non-combat animations. Movement priority is usually locomotion noise,
		-- but some Mashle NPC attacks also use Movement while remaining non-looped.
		if track and track.Priority then
			local pri = track.Priority
			if pri == Enum.AnimationPriority.Core
				or pri == Enum.AnimationPriority.Idle
				or (pri == Enum.AnimationPriority.Movement and track.Looped ~= false) then
				return
			end
		end

		local label = entityLabel(resolvedEntity)
		markObserved(aid, label, (track and track.Priority) and track.Priority.Name or "?")

		table.insert(recentAnims, {
			aid = aid,
			entity = resolvedEntity,
			entityName = label,
			t0 = tick(),
			speed = (track and track.Speed) or 1.0,
			length = (track and track.Length) or 0,
			distance = currentDistance,
			priority = (track and track.Priority) and track.Priority.Name or "?",
		})

		if #recentAnims > MAX_RECENT_ANIMS then
			table.remove(recentAnims, 1)
		end
	end

	---Return whether an animation id is banned.
	---@param aid string
	---@return boolean
	function TimingHarvester.isBanned(aid)
		return bannedAnims[aid] ~= nil
	end

	---Get observed combat animations.
	---@return table
	function TimingHarvester.getObserved()
		return observedAnims
	end

	---Get banned animations.
	---@return table
	function TimingHarvester.getBanned()
		return bannedAnims
	end

	---Ban an animation id and remove any current harvested data for it.
	---@param aid string
	---@return boolean, string
	function TimingHarvester.ban(aid)
		if not aid or aid == "" then
			return false, "Invalid animation id."
		end

		if bannedAnims[aid] then
			return false, string.format("Animation already banned: %s", aid)
		end

		local observed = observedAnims[aid]
		local sample = samples[aid]
		local entityName = (sample and sample.meta.entityName)
			or (observed and observed.meta.entityName)
			or "?"
		local priority = (sample and sample.meta.priority)
			or (observed and observed.meta.priority)
			or "?"

		bannedAnims[aid] = {
			meta = {
				aid = aid,
				entityName = entityName,
				priority = priority,
				bannedAt = tick(),
			},
			sampleCount = sampleCountFor(aid),
			seenCount = observed and observed.seenCount or 0,
		}

		samples[aid] = nil
		observedAnims[aid] = nil
		persistedHitboxLearning[aid] = nil
		pruneRecent(aid)

		Logger.notify("[Harvester] Banned '%s' (%s).", entityName, aid)
		return true, aid
	end

	---Unban an animation id. It will be observed again next time it plays.
	---@param aid string
	---@return boolean, string
	function TimingHarvester.unban(aid)
		local banned = bannedAnims[aid]
		if not banned then
			return false, string.format("Animation is not banned: %s", tostring(aid))
		end

		bannedAnims[aid] = nil
		Logger.notify("[Harvester] Unbanned '%s' (%s).", banned.meta.entityName or "?", aid)
		return true, aid
	end

	---Clear all banned animation ids.
	function TimingHarvester.clearBanned()
		bannedAnims = {}
		Logger.notify("[Harvester] Cleared banned animation list.")
	end

	---Dump banned animations to the logger.
	function TimingHarvester.dumpBanned()
		local count = 0
		for aid, info in next, bannedAnims do
			count = count + 1
			Logger.warn(
				"[Harvester][Banned] %s %s: seen=%d samples=%d priority=%s",
				info.meta.entityName or "?",
				aid,
				info.seenCount or 0,
				info.sampleCount or 0,
				info.meta.priority or "?"
			)
		end

		if count == 0 then
			Logger.warn("[Harvester][Banned] no banned animations.")
		end
	end

	---Serialize persistent harvester state for config saves.
	---@return table
	function TimingHarvester.serializePersistentState()
		local out = {}
		local hitboxOut = {}
		local seen = {}

		for aid, info in next, bannedAnims do
			out[aid] = persistentBannedEntry(aid, info)
		end

		for aid in next, persistedHitboxLearning do
			seen[aid] = true
		end

		for aid in next, samples do
			seen[aid] = true
		end

		for aid in next, seen do
			local mergedSamples = nil
			local bucket = samples[aid]
			local persisted = persistedHitboxLearning[aid]
			local entityName = (bucket and bucket.meta and bucket.meta.entityName)
				or (persisted and persisted.entityName)
				or "?"

			local function sampleKey(sample)
				return string.format(
					"%s:%d:%d:%d:%d:%d",
					type(sample.actorKey) == "string" and sample.actorKey or "*",
					math.round((sample.t or 0) * 1000),
					math.round((sample.when or 0) * 1000),
					math.round((sample.x or 0) * 100),
					math.round((sample.y or 0) * 100),
					math.round((sample.z or 0) * 100)
				)
			end

			local function mergeSamples()
				local merged, dedupe = {}, {}

				local function pushSample(sample)
					local normalized = persistentHitboxSample(sample)
					if not normalized then
						return
					end

					local key = sampleKey(normalized)
					if dedupe[key] then
						return
					end

					dedupe[key] = true
					table.insert(merged, normalized)
				end

				if type(persisted) == "table" and type(persisted.samples) == "table" then
					for _, sample in ipairs(persisted.samples) do
						pushSample(sample)
					end
				end

				if type(bucket) == "table" and type(bucket.pressSamples) == "table" then
					for _, sample in ipairs(bucket.pressSamples) do
						if sample.parried then
							pushSample(runtimeHitboxSample(sample))
						end
					end
				end

				if type(bucket) == "table" and type(bucket.hitSamples) == "table" then
					for _, sample in ipairs(bucket.hitSamples) do
						pushSample(runtimeHitboxSample(sample))
					end
				end

				table.sort(merged, function(lhs, rhs)
					return (lhs.t or 0) < (rhs.t or 0)
				end)

				while #merged > MAX_PERSISTED_HITBOX_SAMPLES do
					table.remove(merged, 1)
				end

				return merged
			end

			mergedSamples = mergeSamples()
			if #mergedSamples > 0 then
				hitboxOut[aid] = persistentHitboxLearningEntry(aid, {
					entityName = entityName,
					samples = mergedSamples,
				})
			end
		end

		return {
			bannedAnims = out,
			hitboxLearning = hitboxOut,
		}
	end

	---Load persistent harvester state from config saves.
	---@param state table?
	function TimingHarvester.loadPersistentState(state)
		local loaded = {}
		local loadedHitbox = {}
		if type(state) == "table" and type(state.bannedAnims) == "table" then
			for aid, info in next, state.bannedAnims do
				if type(aid) == "string" and aid ~= "" then
					loaded[aid] = persistentBannedEntry(aid, info)
				end
			end
		end

		if type(state) == "table" and type(state.hitboxLearning) == "table" then
			for aid, info in next, state.hitboxLearning do
				if type(aid) == "string" and aid ~= "" then
					local entry = persistentHitboxLearningEntry(aid, info)
					if #entry.samples > 0 then
						loadedHitbox[aid] = entry
					end
				end
			end
		end

		bannedAnims = loaded
		persistedHitboxLearning = loadedHitbox
		clearHitboxStateCache()

		for aid in next, loaded do
			observedAnims[aid] = nil
		end

		local filtered = {}
		for _, entry in ipairs(recentAnims) do
			if not loaded[entry.aid] then
				table.insert(filtered, entry)
			end
		end
		recentAnims = filtered
	end

	---Record a parry press. Opens a pending-outcome window.
	function TimingHarvester.onParryPress()
		if not sampleCollectionEnabled() then
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
		if not sampleCollectionEnabled() then
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
			actorKey = actorProfileKey(candidate.entity),
			hitOffset = localOffsetFromAttacker(candidate.entity),
		})

			if typeof(b.pressSamples[#b.pressSamples].hitOffset) == "Vector3" then
				invalidateHitboxState(candidate.aid)
			end

		if pendingPress then
			pendingPress.resolved = true
		end
	end

	---Record local player taking damage. Attributes to the most recent nearby animation.
	local function onDamageObserved()
		if not sampleCollectionEnabled() then
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
			actorKey = actorProfileKey(candidate.entity),
			hitOffset = localOffsetFromAttacker(candidate.entity),
		})

		if typeof(b.hitSamples[#b.hitSamples].hitOffset) == "Vector3" then
			invalidateHitboxState(candidate.aid)
		end
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

	---Generate a de-duplication key for a hitbox sample.
	---@param sample table
	---@return string
	local function hitboxSampleKey(sample)
		return string.format(
			"%s:%d:%d:%d:%d:%d",
			type(sample.actorKey) == "string" and sample.actorKey or "*",
			math.round((sample.t or 0) * 1000),
			math.round((sample.when or 0) * 1000),
			math.round((sample.x or 0) * 100),
			math.round((sample.y or 0) * 100),
			math.round((sample.z or 0) * 100)
		)
	end

	---Normalize a runtime damage sample into a serializable hitbox sample.
	---@param sample table?
	---@return table?
	local function runtimeHitboxSample(sample)
		if type(sample) ~= "table" then
			return nil
		end

		local offset = sample.hitOffset
		if typeof(offset) ~= "Vector3" then
			return nil
		end

		return persistentHitboxSample({
			t = sample.t,
			when = sample.when,
			x = offset.X,
			y = offset.Y,
			z = offset.Z,
			actorKey = type(sample.actorKey) == "string" and sample.actorKey or nil,
		})
	end

	---Merge persisted damage samples with live damage samples for an animation.
	---@param aid string
	---@param bucket table?
	---@param actorKey string?
	---@return table[]
	local function mergedHitboxSamples(aid, bucket, actorKey)
		local merged, seen = {}, {}
		local persisted = persistedHitboxLearning[aid]
		local matchedProfile = false

		local function sampleMatches(normalized)
			if type(actorKey) ~= "string" or actorKey == "" then
				return true
			end

			if normalized.actorKey == actorKey then
				matchedProfile = true
				return true
			end

			return normalized.actorKey == nil
		end

		local function pushSample(sample)
			local normalized = persistentHitboxSample(sample)
			if not normalized or not sampleMatches(normalized) then
				return
			end

			local key = hitboxSampleKey(normalized)
			if seen[key] then
				return
			end

			seen[key] = true
			table.insert(merged, normalized)
		end

		if type(persisted) == "table" and type(persisted.samples) == "table" then
			for _, sample in ipairs(persisted.samples) do
				pushSample(sample)
			end
		end

		if type(bucket) == "table" and type(bucket.pressSamples) == "table" then
			for _, sample in ipairs(bucket.pressSamples) do
				if sample.parried then
					pushSample(runtimeHitboxSample(sample))
				end
			end
		end

		if type(bucket) == "table" and type(bucket.hitSamples) == "table" then
			for _, sample in ipairs(bucket.hitSamples) do
				pushSample(runtimeHitboxSample(sample))
			end
		end

		table.sort(merged, function(lhs, rhs)
			return (lhs.t or 0) < (rhs.t or 0)
		end)

		if type(actorKey) == "string" and actorKey ~= "" then
			local filtered = {}
			for _, sample in ipairs(merged) do
				if matchedProfile then
					if sample.actorKey == actorKey then
						filtered[#filtered + 1] = sample
					end
				elseif sample.actorKey == nil then
					filtered[#filtered + 1] = sample
				end
			end

			merged = filtered
		end

		while #merged > MAX_PERSISTED_HITBOX_SAMPLES do
			table.remove(merged, 1)
		end

		return merged
	end

	---Return a sample as a Vector3.
	---@param sample table
	---@return Vector3
	local function hitboxSampleVector(sample)
		return Vector3.new(sample.x or 0, sample.y or 0, sample.z or 0)
	end

	---Return the component-wise max of two vectors.
	---@param lhs Vector3
	---@param rhs Vector3
	---@return Vector3
	local function vectorMax(lhs, rhs)
		return Vector3.new(
			math.max(lhs.X, rhs.X),
			math.max(lhs.Y, rhs.Y),
			math.max(lhs.Z, rhs.Z)
		)
	end

	---Clamp hitbox size to configured bounds.
	---@param size Vector3
	---@return Vector3
	local function clampHitboxSize(size)
		return Vector3.new(
			math.max(HITBOX_MIN_EXTENT.X, math.min(HITBOX_MAX_EXTENT.X, size.X)),
			math.max(HITBOX_MIN_EXTENT.Y, math.min(HITBOX_MAX_EXTENT.Y, size.Y)),
			math.max(HITBOX_MIN_EXTENT.Z, math.min(HITBOX_MAX_EXTENT.Z, size.Z))
		)
	end

	---Choose a promoted axis length conservatively.
	---@param currentValue number
	---@param proposedValue number
	---@param recentValue number
	---@param tolerance number
	---@param shrinkReady boolean
	---@return number
	local function chooseAxis(currentValue, proposedValue, recentValue, tolerance, shrinkReady)
		if recentValue > currentValue + tolerance then
			return math.max(proposedValue, recentValue)
		end

		if proposedValue < currentValue - tolerance then
			return shrinkReady and proposedValue or currentValue
		end

		return proposedValue
	end

	---Choose the live or promoted hitbox from the learned state.
	---@param current Vector3?
	---@param solved table?
	---@param fallback Vector3?
	---@return Vector3
	local function chooseAdaptedHitbox(current, solved, fallback)
		local fallbackBox = typeof(fallback) == "Vector3" and fallback or DEFAULT_HITBOX
		local currentBox = typeof(current) == "Vector3" and current or fallbackBox
		if type(solved) ~= "table" or typeof(solved.hitbox) ~= "Vector3" then
			return currentBox
		end

		if (solved.hitboxSamples or 0) < MIN_HITBOX_ADAPT_SAMPLES then
			return currentBox
		end

		local proposed = solved.hitbox
		local recentBox = typeof(solved.hitboxRecentRequired) == "Vector3" and solved.hitboxRecentRequired or proposed
		local shrinkReady = (solved.hitboxSamples or 0) >= MIN_HITBOX_SHRINK_SAMPLES
			and (solved.hitboxRecentSampleCount or 0) >= MIN_HITBOX_SHRINK_RECENT_SAMPLES

		return Vector3.new(
			chooseAxis(currentBox.X, proposed.X, recentBox.X, HITBOX_SHRINK_TOLERANCE.X, shrinkReady),
			chooseAxis(currentBox.Y, proposed.Y, recentBox.Y, HITBOX_SHRINK_TOLERANCE.Y, shrinkReady),
			chooseAxis(currentBox.Z, proposed.Z, recentBox.Z, HITBOX_SHRINK_TOLERANCE.Z, shrinkReady)
		)
	end

	---Return a motion-aware hitbox center for a given animation time.
	---@param samplesIn table[]
	---@param when number
	---@return Vector3?
	local function motionCenterFromSamples(samplesIn, when)
		if #samplesIn == 0 or type(when) ~= "number" then
			return nil
		end

		local ranked = {}
		for _, sample in ipairs(samplesIn) do
			table.insert(ranked, {
				sample = sample,
				delta = math.abs((sample.when or 0) - when),
			})
		end

		table.sort(ranked, function(lhs, rhs)
			if lhs.delta == rhs.delta then
				return (lhs.sample.t or 0) < (rhs.sample.t or 0)
			end

			return lhs.delta < rhs.delta
		end)

		local totalWeight, weighted = 0, Vector3.zero
		for index = 1, math.min(#ranked, HITBOX_MOTION_NEIGHBORS) do
			local entry = ranked[index]
			local weight = 1 / math.max(HITBOX_MOTION_WEIGHT_FLOOR, entry.delta)
			weighted = weighted + (hitboxSampleVector(entry.sample) * weight)
			totalWeight = totalWeight + weight
		end

		if totalWeight <= 0 then
			return hitboxSampleVector(ranked[1].sample)
		end

		return weighted / totalWeight
	end

	---Return the most recent hitbox samples up to the requested count.
	---@param samplesIn table[]
	---@param count number
	---@return table[]
	local function recentHitboxSamples(samplesIn, count)
		local out = {}
		local startIndex = math.max(1, #samplesIn - count + 1)

		for index = startIndex, #samplesIn do
			out[#out + 1] = samplesIn[index]
		end

		return out
	end

	---Return the exact hitbox size required to contain the supplied damage samples.
	---@param samplesIn table[]
	---@param fallbackCenter Vector3?
	---@return Vector3?
	local function requiredHitboxSize(samplesIn, fallbackCenter)
		if #samplesIn == 0 then
			return nil
		end

		local halfX, halfY, halfZ = 0, 0, 0
		for _, sample in ipairs(samplesIn) do
			local center = motionCenterFromSamples(samplesIn, sample.when or 0) or fallbackCenter or Vector3.zero
			local point = hitboxSampleVector(sample)
			local residual = point - center

			halfX = math.max(halfX, math.abs(residual.X))
			halfY = math.max(halfY, math.abs(residual.Y))
			halfZ = math.max(halfZ, math.abs(residual.Z))
		end

		return clampHitboxSize(Vector3.new(
			halfX * 2 + HITBOX_PAD_WIDTH,
			halfY * 2 + HITBOX_PAD_HEIGHT,
			halfZ * 2 + HITBOX_PAD_DEPTH
		))
	end

	---Solve a signed hitbox size and center offset from attacker-local damage samples.
	---@param samplesIn table[]
	---@return Vector3?, Vector3?, number, Vector3?, number
	local function solveHitboxShape(samplesIn)
		local sampleCount = #samplesIn
		if sampleCount < MIN_HITBOX_SAMPLES then
			return nil, nil, sampleCount, nil, 0
		end

		local whens, xs, ys, zs = {}, {}, {}, {}
		for _, sample in ipairs(samplesIn) do
			whens[#whens + 1] = sample.when or 0
		end

		local baseWhen = median(whens) or 0
		local baseCenter = motionCenterFromSamples(samplesIn, baseWhen) or Vector3.zero
		local recentSamples = recentHitboxSamples(samplesIn, HITBOX_RECENT_CONFIRMATION_SAMPLES)
		local recentRequired = requiredHitboxSize(recentSamples, baseCenter)

		for _, sample in ipairs(samplesIn) do
			local center = motionCenterFromSamples(samplesIn, sample.when or baseWhen) or baseCenter
			local residual = hitboxSampleVector(sample) - center

			table.insert(xs, math.abs(residual.X))
			table.insert(ys, math.abs(residual.Y))
			table.insert(zs, math.abs(residual.Z))
		end

		---@param axisSamples number[]
		---@param padFull number
		---@param minExtent number
		---@param maxExtent number
		---@return number, number
		local function axisShape(axisSamples, padFull, minExtent, maxExtent)
			local lo = percentile(axisSamples, 1 - HITBOX_AXIS_PERCENTILE) or 0
			local hi = percentile(axisSamples, HITBOX_AXIS_PERCENTILE) or 0
			if hi < lo then
				lo, hi = hi, lo
			end

			local full = (hi - lo) + padFull
			if full < minExtent then full = minExtent end
			if full > maxExtent then full = maxExtent end

			return full, 0
		end

		local sizeX = axisShape(xs, HITBOX_PAD_WIDTH, HITBOX_MIN_EXTENT.X, HITBOX_MAX_EXTENT.X)
		local sizeY = axisShape(ys, HITBOX_PAD_HEIGHT, HITBOX_MIN_EXTENT.Y, HITBOX_MAX_EXTENT.Y)
		local sizeZ = axisShape(zs, HITBOX_PAD_DEPTH, HITBOX_MIN_EXTENT.Z, HITBOX_MAX_EXTENT.Z)
		local candidateSize = clampHitboxSize(Vector3.new(sizeX, sizeY, sizeZ))
		local safeSize = recentRequired and vectorMax(candidateSize, recentRequired) or candidateSize

		return safeSize, baseCenter, sampleCount, recentRequired, #recentSamples
	end

	---Solve the current learned hitbox state for an animation id.
	---@param aid string
	---@return table
	local function solveLiveHitboxState(aid, actorKey)
		local cacheKey = hitboxLearningKey(aid, actorKey)
		local version = hitboxStateVersions[aid] or 0
		local cached = hitboxStateCache[cacheKey]
		if cached and cached.version == version then
			return cached.state
		end

		local learnedSamples = mergedHitboxSamples(aid, samples[aid], actorKey)
		local hitbox, hitboxOffset, hitboxSamples, hitboxRecentRequired, hitboxRecentSampleCount = solveHitboxShape(learnedSamples)
		local state = {
			samples = learnedSamples,
			actorKey = actorKey,
			hitbox = hitbox,
			hitboxOffset = hitboxOffset,
			hitboxSamples = hitboxSamples,
			hitboxRecentRequired = hitboxRecentRequired,
			hitboxRecentSampleCount = hitboxRecentSampleCount,
		}

		hitboxStateCache[cacheKey] = {
			version = version,
			state = state,
		}

		return state
	end

	---Return whether the learned hitbox is ready to override the base rectangle.
	---@param solved table?
	---@return boolean
	local function adaptiveHitboxReady(solved)
		return type(solved) == "table"
			and typeof(solved.hitbox) == "Vector3"
			and (solved.hitboxSamples or 0) >= MIN_HITBOX_ADAPT_SAMPLES
	end

	---Return the live hitbox shape, center, and facing mode for an animation.
	---@param aid string
	---@param when number?
	---@param fallbackHitbox Vector3?
	---@param fallbackOffset Vector3?
	---@param fallbackFacing boolean?
	---@param entity Instance?
	---@return table
	function TimingHarvester.liveHitbox(aid, when, fallbackHitbox, fallbackOffset, fallbackFacing, entity)
		local hitbox = typeof(fallbackHitbox) == "Vector3" and fallbackHitbox or DEFAULT_HITBOX
		local hitboxOffset = typeof(fallbackOffset) == "Vector3" and fallbackOffset or Vector3.zero
		local facing = fallbackFacing == true
		local actorKey = actorProfileKey(entity)

		if type(aid) ~= "string" or aid == "" then
			return {
				hitbox = hitbox,
				offset = hitboxOffset,
				facing = facing,
				adaptive = false,
				samples = 0,
			}
		end

		local solved = solveLiveHitboxState(aid, actorKey)
		if not adaptiveHitboxReady(solved) then
			return {
				hitbox = hitbox,
				offset = hitboxOffset,
				facing = facing,
				adaptive = false,
				samples = solved.hitboxSamples or 0,
			}
		end

		local dynamicOffset = type(when) == "number"
			and (motionCenterFromSamples(solved.samples, when) or solved.hitboxOffset)
			or solved.hitboxOffset

		return {
			hitbox = chooseAdaptedHitbox(hitbox, solved, hitbox),
			offset = typeof(dynamicOffset) == "Vector3" and dynamicOffset or hitboxOffset,
			facing = false,
			adaptive = true,
			samples = solved.hitboxSamples or 0,
		}
	end

	---Return a motion-aware hitbox center for the given animation time.
	---@param aid string
	---@param when number
	---@param fallback Vector3?
	---@return Vector3?
	function TimingHarvester.hitboxOffsetAt(aid, when, fallback)
		if type(aid) ~= "string" or aid == "" or type(when) ~= "number" then
			return fallback
		end

		local liveHitbox = TimingHarvester.liveHitbox(aid, when, nil, fallback, false, nil)
		if type(liveHitbox) ~= "table" then
			return fallback
		end

		return typeof(liveHitbox.offset) == "Vector3" and liveHitbox.offset or fallback
	end

	---Pick a slightly early timing inside a solved success window.
	---@param lo number?
	---@param hi number?
	---@return number?
	local function earlyWindowTiming(lo, hi)
		if lo == nil or hi == nil then
			return nil
		end

		return lo + ((hi - lo) * EARLY_SUCCESS_WINDOW_POSITION)
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

		local perfectLo = percentile(perfectWhens, 0.1)
		local perfectHi = percentile(perfectWhens, 0.9)
		local parryLo = percentile(parryWhens, 0.1)
		local parryHi = percentile(parryWhens, 0.9)
		local hitLo = percentile(hitWhens, 0.1)
		local hitHi = percentile(hitWhens, 0.9)
		local liveHitbox = solveLiveHitboxState(aid)
		local hitbox = liveHitbox.hitbox
		local hitboxOffset = liveHitbox.hitboxOffset
		local hitboxSamples = liveHitbox.hitboxSamples
		local hitboxRecentRequired = liveHitbox.hitboxRecentRequired
		local hitboxRecentSampleCount = liveHitbox.hitboxRecentSampleCount

		-- Mashle parry becomes active slightly before impact, so midpoint timings trend late.
		-- Bias harvested timings toward the early side of successful parry samples.
		local bestWhen = earlyWindowTiming(perfectLo, perfectHi) or earlyWindowTiming(parryLo, parryHi)
		if not bestWhen and #hitWhens > 0 then
			bestWhen = math.max(0, (median(hitWhens) or 0) - HIT_FALLBACK_LEAD_S)
		end
		if not bestWhen then
			return {
				aid = aid,
				entityName = b.meta.entityName,
				sampleCount = #b.pressSamples + #b.hitSamples,
				perfectCount = #perfectWhens,
				parryCount = #parryWhens,
				failCount = #failWhens,
				hitCount = #hitWhens,
				hitbox = hitbox,
				hitboxOffset = hitboxOffset,
				hitboxSamples = hitboxSamples,
				hitboxRecentRequired = hitboxRecentRequired,
				hitboxRecentSampleCount = hitboxRecentSampleCount,
				bestWhen = nil,
			}
		end

		local minDist, maxDist = 0, 100
		if #distances > 0 then
			minDist, maxDist = distances[1], distances[1]
			for i = 2, #distances do
				local d = distances[i]
				if d < minDist then minDist = d end
				if d > maxDist then maxDist = d end
			end
		end

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
				lo = perfectLo,
				hi = perfectHi,
			},
			parryRange = {
				lo = parryLo,
				hi = parryHi,
			},
			hitRange = {
				lo = hitLo,
				hi = hitHi,
			},
			medianPingMs = (median(pings) or 0) * 1000,
			minDistance = minDist,
			maxDistance = maxDist,
			hitbox = hitbox,
			hitboxOffset = hitboxOffset,
			hitboxSamples = hitboxSamples,
			hitboxRecentRequired = hitboxRecentRequired,
			hitboxRecentSampleCount = hitboxRecentSampleCount,
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
			local labelName = b.meta.entityName == "Player"
				and string.format("Player - (%s)", aid)
				or string.format("%s (%s)", b.meta.entityName, aid)
			local label
			if solved and solved.bestWhen then
				label = string.format(
					"[%s] %s n=%d/P%d/p%d/f%d when=%dms",
					b.meta.priority or "?",
					labelName,
					solved.sampleCount,
					solved.perfectCount,
					solved.parryCount,
					solved.failCount,
					math.round((solved.bestWhen or 0) * 1000)
				)
			else
				label = string.format(
					"[%s] %s n=%d no-solve",
					b.meta.priority or "?",
					labelName,
					(solved and solved.sampleCount) or 0
				)
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

		local defaultHitbox = DEFAULT_HITBOX
		local learnedHitbox = solved.hitbox
		local learnedHitboxOffset = solved.hitboxOffset
		local adaptiveShapeReady = adaptiveHitboxReady(solved)

		local function applyLearnedShape(target)
			if not adaptiveShapeReady or typeof(learnedHitboxOffset) ~= "Vector3" then
				return false
			end

			target.hitbox = chooseAdaptedHitbox(target.hitbox, solved, defaultHitbox)
			target.hitboxOffset = learnedHitboxOffset

			if target.fhb ~= nil then
				target.fhb = false
			end

			return true
		end

		if existingConfig then
			local action = getParryAction(existingConfig)
			if not action then
				action = Action.new()
				action.name = string.format("Action_Harvested_n%d", solved.sampleCount)
				action._type = "Parry"
				action.hitbox = typeof(existingConfig.hitbox) == "Vector3" and existingConfig.hitbox or defaultHitbox
				action.hitboxOffset = typeof(existingConfig.hitboxOffset) == "Vector3" and existingConfig.hitboxOffset or Vector3.zero
				action.ihbc = false
				existingConfig.actions:push(action)
			end

			applyLearnedShape(action)

			action._when = PP_SCRAMBLE_RE_NUM(whenMs)
			action:addPingProfile(profilePingMs, whenMs, solved.sampleCount)

			applyLearnedShape(existingConfig)
			existingConfig.imdd = math.max(0, math.min(existingConfig.imdd or solved.minDistance, solved.minDistance))
			existingConfig.imxd = math.max(existingConfig.imxd or solved.maxDistance, solved.maxDistance)

			local hb = existingConfig.hitbox
			local hbo = existingConfig.hitboxOffset
			Logger.notify(
				"[Harvester] Updated '%s' with %.0fms @ %dms RTT (%d profiles) hitbox=(%.1f, %.1f, %.1f) offset=(%.1f, %.1f, %.1f) from %d contact pts.",
				existingConfig.name,
				solved.bestWhen * 1000,
				profilePingMs,
				#(action.pingProfiles or {}),
				(typeof(hb) == "Vector3" and hb.X) or 0,
				(typeof(hb) == "Vector3" and hb.Y) or 0,
				(typeof(hb) == "Vector3" and hb.Z) or 0,
				(typeof(hbo) == "Vector3" and hbo.X) or 0,
				(typeof(hbo) == "Vector3" and hbo.Y) or 0,
				(typeof(hbo) == "Vector3" and hbo.Z) or 0,
				solved.hitboxSamples or 0
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
		timing.hitbox = chooseAdaptedHitbox(defaultHitbox, solved, defaultHitbox)
		timing.hitboxOffset = adaptiveShapeReady and typeof(learnedHitboxOffset) == "Vector3" and learnedHitboxOffset or Vector3.zero
		timing.fhb = not adaptiveShapeReady
		timing.pfh = true
		timing.pfht = 0.15

		local action = Action.new()
		action.name = string.format("Action_Harvested_n%d", solved.sampleCount)
		action._type = "Parry"
		action._when = PP_SCRAMBLE_RE_NUM(whenMs)
		action.hitbox = chooseAdaptedHitbox(defaultHitbox, solved, defaultHitbox)
		action.hitboxOffset = adaptiveShapeReady and typeof(learnedHitboxOffset) == "Vector3" and learnedHitboxOffset or Vector3.zero
		action.ihbc = false
		action:addPingProfile(profilePingMs, whenMs, solved.sampleCount)
		timing.actions:push(action)

		local ok, err = pcall(SaveManager.as.config.push, SaveManager.as.config, timing)
		if not ok then
			return false, "Failed to push timing: " .. tostring(err)
		end

		local promotedHb = timing.hitbox
		local promotedOffset = timing.hitboxOffset
		Logger.notify(
			"[Harvester] Promoted '%s' when=%.0fms @ %dms RTT (n=%d perfect=%d parry=%d conf=%.2f) hitbox=(%.1f, %.1f, %.1f) offset=(%.1f, %.1f, %.1f) from %d contact pts.",
			name,
			solved.bestWhen * 1000,
			profilePingMs,
			solved.sampleCount,
			solved.perfectCount,
			solved.parryCount,
			solved.confidence,
			(typeof(promotedHb) == "Vector3" and promotedHb.X) or 0,
			(typeof(promotedHb) == "Vector3" and promotedHb.Y) or 0,
			(typeof(promotedHb) == "Vector3" and promotedHb.Z) or 0,
			(typeof(promotedOffset) == "Vector3" and promotedOffset.X) or 0,
			(typeof(promotedOffset) == "Vector3" and promotedOffset.Y) or 0,
			(typeof(promotedOffset) == "Vector3" and promotedOffset.Z) or 0,
			solved.hitboxSamples or 0
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
		clearHitboxStateCache()
		recentAnims = {}
		pendingPress = nil
		Logger.notify("[Harvester] Cleared all harvested samples.")
	end

	---Clear all harvester state, including seen and banned animation ids.
	function TimingHarvester.clearAll()
		samples = {}
		observedAnims = {}
		bannedAnims = {}
		persistedHitboxLearning = {}
		clearHitboxStateCache()
		recentAnims = {}
		pendingPress = nil
		Logger.notify("[Harvester] Reset all harvester data.")
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
		observedAnims = {}
		bannedAnims = {}
		persistedHitboxLearning = {}
		clearHitboxStateCache()
		recentAnims = {}
		pendingPress = nil
		isInit = false
	end

	return TimingHarvester
end)()
