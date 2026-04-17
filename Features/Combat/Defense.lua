---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.OriginalStore
local OriginalStore = require("Utility/OriginalStore")

---@module Features.Combat.Objects.AnimatorDefender
local AnimatorDefender = require("Features/Combat/Objects/AnimatorDefender")

---@module Features.Combat.Objects.PartDefender
local PartDefender = require("Features/Combat/Objects/PartDefender")

---@module Features.Combat.Targeting
local Targeting = require("Features/Combat/Targeting")

---@module Features.Combat.Objects.SoundDefender
local SoundDefender = require("Features/Combat/Objects/SoundDefender")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Features.Combat.PositionHistory
local PositionHistory = require("Features/Combat/PositionHistory")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module GUI.Library
local Library = require("GUI/Library")

---@module Utility.TaskSpawner
local TaskSpawner = require("Utility/TaskSpawner")

---@module Features.Combat.AttributeListener
local AttributeListener = require("Features/Combat/AttributeListener")

-- Handle all defense related functions.
local Defense = {}

-- Services.
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

-- Auto rotate store.
local autoRotateStore = OriginalStore.new()

-- Maids.
local defenseMaid = Maid.new()

-- Defender objects.
local defenderObjects = {}
local defenderPartObjects = {}
local defenderAnimationObjects = {}

-- Stored deleted playback data.
local deletedPlaybackData = {}

-- Visualization updating.
local lastVisualizationUpdate = os.clock()

-- Last history updating.
local lastHistoryUpdate = os.clock()

-- Aim lock state.
local stickyTarget = nil

---Add animator defender.
---@param animator Animator
local addAnimatorDefender = LPH_NO_VIRTUALIZE(function(animator)
	local animationDefender = AnimatorDefender.new(animator)
	defenderObjects[animator] = animationDefender
	defenderAnimationObjects[animator] = animationDefender
end)

---Add sound defender.
---@param sound Sound
local addSoundDefender = LPH_NO_VIRTUALIZE(function(sound)
	---@note: If there's nothing to base the sound position off of, then I'm just gonna skip it bruh.
	local part = sound:FindFirstAncestorWhichIsA("BasePart")
	if not part then
		return
	end

	-- Add sound defender.
	defenderObjects[sound] = SoundDefender.new(sound, part)
end)

---Add parry log.
local addParryLog = LPH_NO_VIRTUALIZE(function(descendant)
	local localPlayer = players.LocalPlayer
	local character = localPlayer and localPlayer.Character
	if not character then
		return
	end

	local effectFolder = descendant:FindFirstAncestorWhichIsA("Folder")
	if not effectFolder then
		return
	end

	if effectFolder.Name ~= character.Name then
		return
	end

	AttributeListener.clearParryCooldown()
	Library:AddTelemetryEntry("(%s) Instance '%s' created in effect folder.", effectFolder.Name, descendant.Name)
end)

--- Add damage logger.
---@param player Player
local addDamageLogger = LPH_NO_VIRTUALIZE(function(player)
	local character = player.Character or player.CharacterAdded:Wait()

	---@type Humanoid
	local humanoid = character:WaitForChild("Humanoid")
	if not humanoid then
		return
	end

	local healthChanged = Signal.new(humanoid.HealthChanged)
	local currentHealth = humanoid.Health

	defenseMaid:add(healthChanged:connect("Defense_HumanoidHealthChange", function(health)
		if currentHealth <= health then
			return
		end

		local change = currentHealth - health

		Library:AddTelemetryEntry(
			string.format("(%.2f/%.2f) (%.2f) Humanoid health change detected.", health, humanoid.MaxHealth, change)
		)

		currentHealth = health
	end))
end)

---On player added.
local onPlayerAdded = LPH_NO_VIRTUALIZE(function(player)
	if player ~= players.LocalPlayer then
		return
	end

	defenseMaid:add(TaskSpawner.spawn("Defense_AddDamageLogger", addDamageLogger, player))
end)

---On game descendant added.
---@param descendant Instance
local onGameDescendantAdded = LPH_NO_VIRTUALIZE(function(descendant)
	if descendant:IsA("Animator") then
		return addAnimatorDefender(descendant)
	end

	if descendant:IsA("Sound") then
		return addSoundDefender(descendant)
	end

	if descendant:IsA("BasePart") then
		return descendant.Name == "ParryEffect" and addParryLog(descendant) or Defense.cdpo(descendant)
	end
end)

---On game descendant removed.
---@param descendant Instance
local onGameDescendantRemoved = LPH_NO_VIRTUALIZE(function(descendant)
	local object = defenderObjects[descendant]
	if not object then
		return
	end

	if object.rpbdata then
		deletedPlaybackData[descendant] = object.rpbdata
	end

	if defenderPartObjects[descendant] then
		defenderPartObjects[descendant] = nil
	end

	if defenderAnimationObjects[descendant] then
		defenderAnimationObjects[descendant] = nil
	end

	object:detach()
	object[descendant] = nil
end)

---Update history.
local updateHistory = LPH_NO_VIRTUALIZE(function()
	if os.clock() - lastHistoryUpdate <= 0.05 then
		return
	end

	lastHistoryUpdate = os.clock()

	local character = players.LocalPlayer.Character
	if not character then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	PositionHistory.add(players.LocalPlayer, humanoidRootPart.CFrame, tick())

	for _, player in next, players:GetPlayers() do
		if player == players.LocalPlayer then
			continue
		end

		local pcharacter = player.Character
		if not pcharacter then
			continue
		end

		local proot = pcharacter:FindFirstChild("HumanoidRootPart")
		if not proot then
			continue
		end

		PositionHistory.add(pcharacter, proot.CFrame, tick())
	end
end)

---Update visualization.
local updateVisualizations = LPH_NO_VIRTUALIZE(function()
	if os.clock() - lastVisualizationUpdate <= 5.0 then
		return
	end

	lastVisualizationUpdate = os.clock()

	for _, object in next, defenderObjects do
		for idx, hitbox in next, object.hmaid._tasks do
			if typeof(hitbox) ~= "Instance" then
				continue
			end

			---@note: We call :Debris so we don't have to clean it up ourselves. We just unregister it from the maid.
			if hitbox.Parent then
				continue
			end

			object.hmaid._tasks[idx] = nil
		end
	end
end)

---Update assistance.
local updateAssistance = LPH_NO_VIRTUALIZE(function()
	local localPlayer = players.LocalPlayer
	local character = localPlayer.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid")
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not humanoidRootPart then
		return
	end

	if Configuration.expectToggleValue("ForceAutoRotate") then
		humanoid.AutoRotate = true
	end

	if not Configuration.expectToggleValue("AimLock") or not Configuration.expectToggleValue("StickyTargets") then
		stickyTarget = nil
	end

	if not Configuration.expectToggleValue("AimLock") then
		return not Configuration.expectToggleValue("ForceAutoRotate") and autoRotateStore:restore()
	end

	if Configuration.expectToggleValue("StickyTargets") then
		stickyTarget = stickyTarget or Targeting.best()[1]
	end

	local target = stickyTarget or Targeting.best()[1]
	local failure = false

	if not target then
		failure = true
		stickyTarget = nil
	end

	if target and not target.character.Parent then
		failure = true
		stickyTarget = nil
	end

	if target and target.humanoid.Health <= 0 then
		failure = true
		stickyTarget = nil
	end

	if failure then
		return not Configuration.expectToggleValue("ForceAutoRotate") and autoRotateStore:restore()
	end

	if humanoid.PlatformStand then
		return
	end

	if AttributeListener.cs("Ragdoll") or AttributeListener.cs("Stun") then
		return
	end

	if AttributeListener.csOn(target.character, "Ragdoll") or AttributeListener.csOn(target.character, "Stun") then
		return
	end

	local targetPosition = target.root.Position

	if not Configuration.expectToggleValue("VerticalInfluence") then
		targetPosition = Vector3.new(targetPosition.X, humanoidRootPart.Position.Y, targetPosition.Z)
	end

	local targetCFrame = CFrame.lookAt(humanoidRootPart.Position, targetPosition)

	if Configuration.expectToggleValue("ForceAutoRotate") then
		humanoid.AutoRotate = false
	else
		autoRotateStore:set(humanoid, "AutoRotate", false)
	end

	---@note: https://www.unknowncheats.me/forum/counterstrike-global-offensive/141636-scaled-smoothing-adaptive-smoothing.html
	if Configuration.expectToggleValue("Smoothing") then
		local alpha = tweenService:GetValue(
			math.clamp(1 - (Configuration.expectOptionValue("SmoothingFactor") or 0.1), 0, 1),
			Enum.EasingStyle[Configuration.expectOptionValue("SmoothingStyle") or "Linear"],
			Enum.EasingDirection[Configuration.expectOptionValue("SmoothingDirection") or "In"]
		)

		humanoidRootPart.CFrame = humanoidRootPart.CFrame:Lerp(targetCFrame, alpha)
	else
		humanoidRootPart.CFrame = targetCFrame
	end
end)

---Update defenders.
local updateDefenders = LPH_NO_VIRTUALIZE(function()
	for _, object in next, defenderAnimationObjects do
		object:update()
	end

	if not Configuration.expectToggleValue("EnableAutoDefense") then
		return
	end

	for _, object in next, defenderPartObjects do
		object:update()
	end
end)

---Toggle visualizations.
Defense.visualizations = LPH_NO_VIRTUALIZE(function()
	for _, object in next, defenderObjects do
		for _, hitbox in next, object.hmaid._tasks do
			if typeof(hitbox) ~= "Instance" then
				continue
			end

			hitbox.Transparency = Configuration.expectToggleValue("EnableVisualizations") and 0.2 or 1.0
		end
	end
end)

---Create a defender part object.
---@param part BasePart
---@param timing PartTiming
---@return PartDefender?
Defense.cdpo = LPH_NO_VIRTUALIZE(function(part, timing)
	local partDefender = PartDefender.new(part, timing)
	if not partDefender then
		return nil
	end

	defenderObjects[part] = partDefender
	defenderPartObjects[part] = partDefender

	return partDefender
end)

---Return the defender animation object for an entity.
---@param entity Instance
---@return AnimatorDefender?
Defense.dao = LPH_NO_VIRTUALIZE(function(entity)
	for _, object in next, defenderAnimationObjects do
		if object.entity ~= entity then
			continue
		end

		return object
	end
end)

---Get playback data of first defender with Animation ID.
---@param aid string
---@return PlaybackData?
Defense.agpd = LPH_NO_VIRTUALIZE(function(aid)
	---@note: Grabbing from 'rpbdata' means that we know that the data has been fully recorded.
	for _, object in next, defenderAnimationObjects do
		local pbdata = object.rpbdata[aid]
		if not pbdata then
			continue
		end

		return pbdata
	end

	---@note: Fallback to deleted playback data if that doesn't exist.
	for _, rpbdata in next, deletedPlaybackData do
		local pbdata = rpbdata[aid]
		if not pbdata then
			continue
		end

		return pbdata
	end
end)

---Initialize defense.
function Defense.init()
	-- Signals.
	local gameDescendantAdded = Signal.new(game.DescendantAdded)
	local gameDescendantRemoved = Signal.new(game.DescendantRemoving)
	local renderStepped = Signal.new(runService.RenderStepped)
	local postSimulation = Signal.new(runService.PostSimulation)
	local playersAdded = Signal.new(players.PlayerAdded)

	defenseMaid:mark(gameDescendantAdded:connect("Defense_OnDescendantAdded", onGameDescendantAdded))
	defenseMaid:mark(gameDescendantRemoved:connect("Defense_OnDescendantRemoved", onGameDescendantRemoved))
	defenseMaid:mark(renderStepped:connect("Defense_UpdateHistory", updateHistory))
	defenseMaid:mark(renderStepped:connect("Defense_UpdateVisualizations", updateVisualizations))
	defenseMaid:mark(renderStepped:connect("Defense_UpdateAssistance", updateAssistance))
	defenseMaid:mark(postSimulation:connect("Defense_UpdateDefenders", updateDefenders))
	defenseMaid:mark(playersAdded:connect("Defense_OnPlayerAdded", onPlayerAdded))

	if players.LocalPlayer then
		onPlayerAdded(players.LocalPlayer)
	end

	for _, descendant in next, game:GetDescendants() do
		onGameDescendantAdded(descendant)
	end

	-- Log.
	Logger.warn("Defense initialized.")
end

---Detach defense.
function Defense.detach()
	for _, object in next, defenderObjects do
		object:detach()
	end

	defenseMaid:clean()

	Logger.warn("Defense detached.")
end

-- Return Defense module.
return Defense
