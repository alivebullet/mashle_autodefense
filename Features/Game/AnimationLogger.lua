return LPH_NO_VIRTUALIZE(function()
	-- Universal Animation Logger module.
	-- Monitors all nearby Animators and logs animation plays/keyframes to the Info Logger.
	local AnimationLogger = {}

	---@module Utility.Maid
	local Maid = require("Utility/Maid")

	---@module GUI.Library
	local Library = require("GUI/Library")

	---@module Utility.Configuration
	local Configuration = require("Utility/Configuration")

	-- Services.
	local players = game:GetService("Players")

	-- Logger maid.
	local loggerMaid = Maid.new()

	-- Tracked animators mapped to their cleanup maids.
	local trackedAnimators = {}
	local isInitialized = false

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

			-- Listen for keyframes on this track.
			animMaid:add(track.KeyframeReached:Connect(function(kfName)
				Library:AddKeyFrameEntry(getDistanceTo(entity), aid, kfName, track.TimePosition, false)
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
