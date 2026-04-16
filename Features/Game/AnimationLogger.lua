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

	---Get the parent entity (Model) of an Animator.
	---@param animator Animator
	---@return Model?
	local function getEntityFromAnimator(animator)
		local current = animator.Parent
		while current do
			if current:IsA("Model") and current:FindFirstChildWhichIsA("Humanoid") then
				return current
			end
			current = current.Parent
		end
		return nil
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
			if not isInRange(distance) then
				return
			end

			local aid = track.Animation and track.Animation.AnimationId or "Unknown"

			-- Log the animation play event.
			Library:AddTelemetryEntry(
				"(%.1fm) '%s' played '%s' (Speed: %.2f, Length: %.3f)",
				distance,
				entity.Name,
				aid,
				track.Speed,
				track.Length
			)

			-- Capture animation data if enabled.
			if Configuration.expectToggleValue("EnableAnimationCapture") then
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
			end

			-- Listen for keyframes on this track.
			animMaid:add(track.KeyframeReached:Connect(function(kfName)
				Library:AddKeyFrameEntry(getDistanceTo(entity), aid, kfName, track.TimePosition, false)

				-- Capture keyframe data if enabled.
				if Configuration.expectToggleValue("EnableAnimationCapture") and capturedAnimations[aid] then
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

	---Clear all captured animations.
	function AnimationLogger.clearCaptured()
		capturedAnimations = {}
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

		-- Create actions from keyframes.
		local hitKeyframes = {}
		for _, kf in next, data.keyframes do
			local kfLower = string.lower(kf.name)
			if kfLower:find("hit") or kfLower:find("damage") or kfLower:find("attack") or kfLower:find("impact") then
				table.insert(hitKeyframes, kf)
			end
		end

		-- If no hit keyframes found, use all keyframes as potential action points.
		local actionKeyframes = #hitKeyframes > 0 and hitKeyframes or data.keyframes

		if #actionKeyframes > 0 then
			-- Sort by time position.
			table.sort(actionKeyframes, function(a, b)
				return a.timePosition < b.timePosition
			end)

			for i, kf in next, actionKeyframes do
				local action = Action.new()
				action.name = string.format("Action_%s_%d", kf.name, i)
				action._type = "Parry"
				action._when = math.round(kf.timePosition * 1000) -- Convert seconds to milliseconds.
				action.hitbox = Vector3.new(20, 20, 30)
				action.ihbc = false

				timing.actions:push(action)
			end
		else
			-- No keyframes captured - create a single parry action at a reasonable time.
			-- Use 60% of the animation length as the default action time.
			local action = Action.new()
			action.name = "Action_Default_1"
			action._type = "Parry"
			action._when = math.round(data.length * 0.6 * 1000)
			action.hitbox = Vector3.new(20, 20, 30)
			action.ihbc = false

			timing.actions:push(action)
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

	---Initialize AnimationLogger module.
	function AnimationLogger.init()
		if isInitialized then
			return
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
		loggerMaid:clean()
		isInitialized = false
	end

	-- Return AnimationLogger module.
	return AnimationLogger
end)()
