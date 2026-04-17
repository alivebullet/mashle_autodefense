return LPH_NO_VIRTUALIZE(function()
	-- Universal Animation Logger module.
	-- Monitors all nearby Animators and logs animation plays/keyframes to the Info Logger.
	-- Also captures animation data for auto-generating timings.
	local AnimationLogger = {}

	---@module Utility.Maid
	local Maid = require("Utility/Maid")

	---@module GUI.Library
	local Library = require("GUI/Library")

	---@module Utility.Configuration
	local Configuration = require("Utility/Configuration")

	---@module Game.Timings.AnimationTiming
	local AnimationTiming = require("Game/Timings/AnimationTiming")

	---@module Game.Timings.Action
	local Action = require("Game/Timings/Action")

	---@module Game.Timings.SaveManager
	local SaveManager = require("Game/Timings/SaveManager")

	---@module Utility.Logger
	local Logger = require("Utility/Logger")

	---@module Game.DynamicTiming
	local DynamicTiming = require("Game/DynamicTiming")

	---@module Features.Combat.TimingHarvester
	local TimingHarvester = require("Features/Combat/TimingHarvester")

	-- Services.
	local players = game:GetService("Players")

	-- Logger maid.
	local loggerMaid = Maid.new()

	-- Tracked animators mapped to their cleanup maids.
	local trackedAnimators = {}
	local isInitialized = false

	-- Captured animation data for auto-generating timings.
	-- Key: animation ID, Value: { id, entityName, length, speed, keyframes = { { name, timePosition } }, capturedAt }
	local capturedAnimations = {}

	-- Most recent source entity seen for each animation id, used by the visualizer.
	local previewSources = {}

	-- Animations currently playing on nearby entities (for damage-hit capture).
	-- Key: animation ID, Value: { track = AnimationTrack, entity = Model }
	-- Note: only the most recent track per aid is stored.
	local activePlayingTracks = {}

	---Return whether a model has a usable part for distance or viewport preview.
	---@param model Model?
	---@return boolean
	local function hasRenderablePart(model)
		return model ~= nil and (model.PrimaryPart ~= nil or model:FindFirstChildWhichIsA("BasePart", true) ~= nil)
	end

	---Get distance from local player to an entity.
	---@param entity Model
	---@return number
	local function getDistanceTo(entity)
		local localChar = players.LocalPlayer and players.LocalPlayer.Character
		if not localChar or not localChar.PrimaryPart then
			return math.huge
		end

		local targetPart = entity:IsA("Model") and entity.PrimaryPart
			or entity:FindFirstChildWhichIsA("BasePart", true)
		if not targetPart then
			return math.huge
		end

		return (localChar.PrimaryPart.Position - targetPart.Position).Magnitude
	end

	---Check if a distance is within the configured logger range.
	---@param distance number
	---@return boolean
	local function isInRange(distance)
		local minDist = Configuration.expectOptionValue("MinimumLoggerDistance") or 0
		local maxDist = Configuration.expectOptionValue("MaximumLoggerDistance") or 0

		-- A max of 0 means no distance filtering.
		if maxDist <= 0 then
			return true
		end

		return distance >= minDist and distance <= maxDist
	end

	---Check if a distance is within the capture-specific range.
	---@param distance number
	---@return boolean
	local function isInCaptureRange(distance)
		local minDist = Configuration.expectOptionValue("CaptureMinDistance") or 0
		local maxDist = Configuration.expectOptionValue("CaptureMaxDistance") or 0

		-- A max of 0 means no distance filtering.
		if maxDist <= 0 then
			return true
		end

		return distance >= minDist and distance <= maxDist
	end

	---Get the parent entity (Model) of an Animator.
	---@param animator Animator
	---@return Model?
	local function getEntityFromAnimator(animator)
		local current = animator.Parent
		local fallback = nil
		while current do
			if current:IsA("Model") then
				if hasRenderablePart(current) then
					fallback = current
				end

				if current:FindFirstChildWhichIsA("Humanoid") and hasRenderablePart(current) then
					return current
				end

				if current:FindFirstChildWhichIsA("AnimationController") and hasRenderablePart(current) then
					return current
				end
			end
			current = current.Parent
		end
		return fallback
	end

	---Track an animator and log its animations.
	---@param animator Animator
	---@param entity Model
	local function trackAnimator(animator, entity)
		if trackedAnimators[animator] then
			return
		end

		-- Skip the local player's own animator.
		local localChar = players.LocalPlayer and players.LocalPlayer.Character
		if localChar and entity == localChar then
			return
		end

		local animMaid = Maid.new()
		trackedAnimators[animator] = animMaid

		-- Listen for new animations being played.
		animMaid:add(animator.AnimationPlayed:Connect(function(track)
			local distance = getDistanceTo(entity)
			local inLogRange = isInRange(distance)
			local inCaptureRange = isInCaptureRange(distance)

			local aid = track.Animation and track.Animation.AnimationId or "Unknown"

			if TimingHarvester.isBanned(aid) then
				return
			end

			previewSources[aid] = entity

			-- Feed the timing harvester unconditionally (self-gated by EnableTimingHarvester + its own distance filter).
			TimingHarvester.onAnimationStart(aid, entity, track)

			if not inLogRange and not inCaptureRange then
				return
			end

			-- Log the animation play event.
			if inLogRange then
				Library:AddTelemetryEntry(
					"(%.1fm) '%s' played '%s' (Speed: %.2f, Length: %.3f)",
					distance,
					entity.Name,
					aid,
					track.Speed,
					track.Length
				)
			end

			-- Capture animation data if enabled.
			if Configuration.expectToggleValue("EnableAnimationCapture") and inCaptureRange then
				if not capturedAnimations[aid] then
					capturedAnimations[aid] = {
						id = aid,
						entityName = entity.Name,
						length = track.Length,
						speed = track.Speed,
						keyframes = {},
						capturedAt = os.clock(),
					}
				end

				-- Register as an active playing track so damage-hit capture can snapshot it.
				activePlayingTracks[aid] = { track = track, entity = entity }

				-- Deregister when the track stops.
				animMaid:add(track.Stopped:Connect(function()
					if activePlayingTracks[aid] and activePlayingTracks[aid].track == track then
						activePlayingTracks[aid] = nil
					end
				end))
			end

			-- Listen for keyframes on this track.
			animMaid:add(track.KeyframeReached:Connect(function(kfName)
				if inLogRange then
					Library:AddKeyFrameEntry(getDistanceTo(entity), aid, kfName, track.TimePosition, false)
				end

				-- Capture keyframe data if enabled.
				if Configuration.expectToggleValue("EnableAnimationCapture") and inCaptureRange and capturedAnimations[aid] then
					local kfs = capturedAnimations[aid].keyframes
					local exists = false

					for _, kf in next, kfs do
						if kf.name == kfName then
							exists = true
							break
						end
					end

					if not exists then
						table.insert(kfs, {
							name = kfName,
							timePosition = track.TimePosition,
						})
					end
				end
			end))
		end))

		-- Clean up when the animator is removed from the game.
		animMaid:add(animator.Destroying:Connect(function()
			if trackedAnimators[animator] then
				trackedAnimators[animator]:clean()
				trackedAnimators[animator] = nil
			end
		end))
	end

	---Scan an entity for an Animator and start tracking it.
	---@param entity Model
	local function scanEntity(entity)
		if not entity then
			return
		end

		local animator = entity:FindFirstChildWhichIsA("Animator", true)
		if animator then
			trackAnimator(animator, entity)
		end
	end

	---Handle a player joining or their character spawning.
	---@param player Player
	local function onPlayer(player)
		if player == players.LocalPlayer then
			return
		end

		if player.Character then
			scanEntity(player.Character)
		end

		loggerMaid:add(player.CharacterAdded:Connect(function(char)
			-- Wait briefly for Animator to be added.
			task.defer(function()
				scanEntity(char)
			end)
		end))
	end

	---Handle a new Animator appearing anywhere in workspace (catches NPCs).
	---@param descendant Instance
	local function onDescendantAdded(descendant)
		if not descendant:IsA("Animator") then
			return
		end

		local entity = getEntityFromAnimator(descendant)
		if entity then
			trackAnimator(descendant, entity)
		end
	end

	---Get list of captured animation IDs.
	---@return string[]
	function AnimationLogger.capturedList()
		local list = {}

		for aid, data in next, capturedAnimations do
			table.insert(list, string.format("%s (%s)", data.entityName, aid))
		end

		table.sort(list)

		return list
	end

	---Get captured animation data by animation ID.
	---@param aid string
	---@return table?
	function AnimationLogger.getCaptured(aid)
		return capturedAnimations[aid]
	end

	---Get all captured animations.
	---@return table
	function AnimationLogger.getAllCaptured()
		return capturedAnimations
	end

	---Get the latest known source entity for an animation id.
	---@param aid string
	---@return Model?
	function AnimationLogger.getPreviewSource(aid)
		local source = previewSources[aid]
		if typeof(source) ~= "Instance" or not source:IsA("Model") then
			return nil
		end

		if not source.Parent then
			previewSources[aid] = nil
			return nil
		end

		return source
	end

	---Clear all captured animations.
	function AnimationLogger.clearCaptured()
		capturedAnimations = {}
	end

	---Remove a captured animation by animation id.
	---@param aid string
	function AnimationLogger.removeCaptured(aid)
		capturedAnimations[aid] = nil
	end

	---Generate an AnimationTiming from a captured animation and push it into the config.
	---@param aid string The animation ID to generate from.
	---@param timingName string? Optional custom name (defaults to entityName_shortened_id).
	---@return boolean, string
	function AnimationLogger.generateTiming(aid, timingName)
		local data = capturedAnimations[aid]
		if not data then
			return false, "No captured data for animation ID: " .. tostring(aid)
		end

		-- Check SaveManager is ready.
		if not SaveManager.as then
			return false, "SaveManager not initialized."
		end

		-- Check if timing already exists.
		local existing = SaveManager.as:index(aid)
		if existing then
			return false, string.format("Timing already exists for '%s' (%s).", aid, existing.name)
		end

		-- Generate a name if not provided.
		local name = timingName
		if not name or #name <= 0 then
			-- Use entityName + short ID.
			local shortId = aid:match("(%d+)$") or tostring(os.clock())
			name = string.format("%s_%s", data.entityName, shortId)
		end

		-- Check name uniqueness.
		local existingName = SaveManager.as:find(name)
		if existingName then
			return false, string.format("Timing name '%s' already exists.", name)
		end

		-- Create the timing.
		local timing = AnimationTiming.new()
		timing._id = aid
		timing.name = name
		timing.tag = "Undefined"
		timing.imdd = 0
		timing.imxd = 100
		timing.hitbox = Vector3.new(20, 20, 30)
		timing.fhb = true
		timing.pfh = true
		timing.pfht = 0.15

		-- ── Determine the best raw _when value ──────────────────────────────
		-- Priority: damage-hit capture > named keyframe > all keyframes > length fallback.

		if data.damageHitTime then
			-- Damage-hit capture: adjust for projectile travel time via DynamicTiming.
			local rawMs = data.damageHitTime.timePos * 1000
			local dist = data.damageHitTime.distance
			local adjMs = DynamicTiming.adjust(rawMs, dist, aid, nil)

			local action = Action.new()
			action.name = "Action_DamageHit_1"
			action._type = "Parry"
			action._when = PP_SCRAMBLE_RE_NUM(math.round(adjMs))
			action.hitbox = Vector3.new(20, 20, 30)
			action.ihbc = false

			timing.actions:push(action)

			Logger.notify(
				"[DynamicTiming] '%s': raw=%.0fms dist=%.1fst adj=%.0fms",
				name, rawMs, dist, adjMs
			)
		else
			-- Fallback: keyframe-based generation (original behaviour).
			local hitKeyframes = {}
			for _, kf in next, data.keyframes do
				local kfLower = string.lower(kf.name)
				if kfLower:find("hit") or kfLower:find("damage") or kfLower:find("attack") or kfLower:find("impact") then
					table.insert(hitKeyframes, kf)
				end
			end

			local actionKeyframes = #hitKeyframes > 0 and hitKeyframes or data.keyframes

			if #actionKeyframes > 0 then
				table.sort(actionKeyframes, function(a, b)
					return a.timePosition < b.timePosition
				end)

				for i, kf in next, actionKeyframes do
					local action = Action.new()
					action.name = string.format("Action_%s_%d", kf.name, i)
					action._type = "Parry"
					action._when = PP_SCRAMBLE_RE_NUM(math.round(kf.timePosition * 1000))
					action.hitbox = Vector3.new(20, 20, 30)
					action.ihbc = false

					timing.actions:push(action)
				end
			else
				-- No keyframes at all — use 60% of animation length.
				local action = Action.new()
				action.name = "Action_Default_1"
				action._type = "Parry"
				action._when = PP_SCRAMBLE_RE_NUM(math.round(data.length * 0.6 * 1000))
				action.hitbox = Vector3.new(20, 20, 30)
				action.ihbc = false

				timing.actions:push(action)
			end
		end

		-- Push into SaveManager config.
		local success, err = pcall(SaveManager.as.config.push, SaveManager.as.config, timing)
		if not success then
			return false, "Failed to push timing: " .. tostring(err)
		end

		Logger.notify("Generated timing '%s' for animation '%s' with %d action(s).", name, aid, timing.actions:count())

		return true, name
	end

	---Generate timings for ALL captured animations.
	---@return number, number
	function AnimationLogger.generateAll()
		local successCount = 0
		local failCount = 0

		for aid, _ in next, capturedAnimations do
			local success, _ = AnimationLogger.generateTiming(aid)

			if success then
				successCount = successCount + 1
			else
				failCount = failCount + 1
			end
		end

		Logger.notify("Generated %d timings (%d skipped/failed).", successCount, failCount)

		return successCount, failCount
	end

	---Hook the local player's Humanoid HealthChanged to capture damage-hit timestamps.
	---Called once per character spawn so it always targets the current Humanoid.
	---@param character Model
	local function hookLocalDamage(character)
		local humanoid = character:FindFirstChildWhichIsA("Humanoid")
		if not humanoid then
			return
		end

		local lastHealth = humanoid.Health

		loggerMaid:add(humanoid.HealthChanged:Connect(function(newHealth)
			-- Only care about damage (health decrease).
			if newHealth >= lastHealth then
				lastHealth = newHealth
				return
			end

			lastHealth = newHealth

			-- Snapshot every currently-active animation's time position and distance.
			-- This becomes the authoritative 'when' for auto-generated timings.
			if not Configuration.expectToggleValue("EnableAnimationCapture") then
				return
			end

			for aid, entry in next, activePlayingTracks do
				if not capturedAnimations[aid] then
					continue
				end

				local timePos = entry.track.TimePosition
				local dist = getDistanceTo(entry.entity)

				-- Only update if this snapshot is more recent (later in the animation).
				local existing = capturedAnimations[aid].damageHitTime
				if not existing or timePos > existing.timePos then
					capturedAnimations[aid].damageHitTime = {
						timePos = timePos,
						distance = dist,
					}

					Library:AddTelemetryEntry(
						"[DamageCap] '%s' hit at tp=%.3fs dist=%.1fst",
						capturedAnimations[aid].entityName,
						timePos,
						dist
					)
				end
			end
		end))
	end

	---Initialize AnimationLogger module.
	function AnimationLogger.init()
		if isInitialized then
			return
		end

		-- Hook local player damage on current and future characters.
		local localPlayer = players.LocalPlayer
		if localPlayer then
			if localPlayer.Character then
				hookLocalDamage(localPlayer.Character)
			end

			loggerMaid:add(localPlayer.CharacterAdded:Connect(function(char)
				task.defer(function()
					hookLocalDamage(char)
				end)
			end))
		end

		-- Track existing players.
		for _, player in next, players:GetPlayers() do
			onPlayer(player)
		end

		-- Track new players.
		loggerMaid:add(players.PlayerAdded:Connect(function(player)
			onPlayer(player)
		end))

		-- Track Animators appearing in workspace (NPCs, etc).
		loggerMaid:add(workspace.DescendantAdded:Connect(onDescendantAdded))

		-- Scan existing workspace descendants for Animators.
		for _, descendant in next, workspace:GetDescendants() do
			onDescendantAdded(descendant)
		end

		isInitialized = true
	end

	---Detach AnimationLogger module.
	function AnimationLogger.detach()
		for _, maid in next, trackedAnimators do
			maid:clean()
		end

		trackedAnimators = {}
		previewSources = {}
		loggerMaid:clean()
		isInitialized = false
	end

	-- Return AnimationLogger module.
	return AnimationLogger
end)()
