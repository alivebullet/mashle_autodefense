---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Features.Visuals.Objects.ModelESP
local ModelESP = require("Features/Visuals/Objects/ModelESP")

---@module Features.Visuals.Objects.PartESP
local PartESP = require("Features/Visuals/Objects/PartESP")

---@module Features.Visuals.Objects.MobESP
local MobESP = require("Features/Visuals/Objects/MobESP")

---@module Features.Visuals.Objects.PlayerESP
local PlayerESP = require("Features/Visuals/Objects/PlayerESP")

---@module Utility.OriginalStoreManager
local OriginalStoreManager = require("Utility/OriginalStoreManager")

---@module Features.Visuals.Group
local Group = require("Features/Visuals/Group")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Utility.OriginalStore
local OriginalStore = require("Utility/OriginalStore")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Utility.Profiler
local Profiler = require("Utility/Profiler")

-- Visuals module.
local Visuals = { currentBuilderData = nil }

-- Services.
local runService = game:GetService("RunService")
local players = game:GetService("Players")
local textChatService = game:GetService("TextChatService")
local lighting = game:GetService("Lighting")

-- Signals.
local renderStepped = Signal.new(runService.RenderStepped)

-- Maids.
local visualsMaid = Maid.new()

-- Last visuals update.
local lastVisualsUpdate = os.clock()

-- Original stores.
local fieldOfView = visualsMaid:mark(OriginalStore.new())

-- Original store managers.
local showRobloxChatMap = visualsMaid:mark(OriginalStoreManager.new())
local ambienceMap = visualsMaid:mark(OriginalStoreManager.new())

-- Groups.
local groups = {}

---Update show roblox chat.
local updateShowRobloxChat = LPH_NO_VIRTUALIZE(function()
	local localPlayer = players.LocalPlayer
	if not localPlayer then
		return
	end

	local playerGui = localPlayer.PlayerGui
	if not playerGui then
		return
	end

	local chatWindowConfiguration = textChatService:FindFirstChild("ChatWindowConfiguration")
	if not chatWindowConfiguration then
		return
	end

	showRobloxChatMap:add(chatWindowConfiguration, "Enabled", true)

	---@note: Probably set a proper restore for this?
	--- But, in Deepwoken, users cannot realisitically access the Roblox chat anyway.
	textChatService.OnIncomingMessage = function(message)
		local source = message.TextSource
		if not source then
			return
		end

		local player = players:GetPlayerByUserId(source.UserId)
		if not player then
			return
		end

		message.PrefixText = string.gsub(message.PrefixText, player.DisplayName, player.Name)
		message.PrefixText = string.format(
			"(%s) %s",
			player:GetAttribute("CharacterName") or "Unknown Character Name",
			message.PrefixText
		)
	end
end)

---Modify ambience color.
---@param value Color3
local modifyAmbienceColor = LPH_NO_VIRTUALIZE(function(value)
	local ambienceColor = Configuration.expectOptionValue("AmbienceColor")
	local shouldUseOriginalAmbienceColor = Configuration.expectToggleValue("OriginalAmbienceColor")

	if not shouldUseOriginalAmbienceColor and ambienceColor then
		return ambienceColor
	end

	local brightness = Configuration.expectOptionValue("OriginalAmbienceColorBrightness") or 0.0
	local red, green, blue = value.R, value.G, value.B

	red = math.min(red + brightness, 255)
	green = math.min(green + brightness, 255)
	blue = math.min(blue + brightness, 255)

	return Color3.fromRGB(red, green, blue)
end)

---Update ambience.
local updateAmbience = LPH_NO_VIRTUALIZE(function()
	local store = ambienceMap:get(lighting)
	local value = store and store:get() or lighting.Ambient
	ambienceMap:add(lighting, "Ambient", modifyAmbienceColor(value))
end)

---Update visuals.
local updateVisuals = LPH_NO_VIRTUALIZE(function()
	for _, group in next, groups do
		group:update()
	end

	if os.clock() - lastVisualsUpdate <= 1.0 then
		return
	end

	lastVisualsUpdate = os.clock()

	if Configuration.expectToggleValue("ModifyFieldOfView") then
		fieldOfView:set(workspace.CurrentCamera, "FieldOfView", Configuration.expectOptionValue("FieldOfView"))
	else
		fieldOfView:restore()
	end

	if Configuration.expectToggleValue("ShowRobloxChat") then
		updateShowRobloxChat()
	else
		showRobloxChatMap:restore()
	end

	if Configuration.expectToggleValue("ModifyAmbience") then
		updateAmbience()
	else
		ambienceMap:restore()
	end
end)

---Emplace object.
---@param instance Instance
---@param object ModelESP|PartESP
local emplaceObject = LPH_NO_VIRTUALIZE(function(instance, object)
	local group = groups[object.identifier] or Group.new(object.identifier)

	group:insert(instance, object)

	groups[object.identifier] = group
end)

---On NPCs DescendantAdded.
---@param descendant Instance
local onNPCsDescendantAdded = LPH_NO_VIRTUALIZE(function(descendant)
	local parent = descendant.Parent
	if not parent then
		return
	end

	if not descendant:IsA("Model") or not parent:IsA("Folder") then
		return
	end

	if parent.Name == "Bounties" then
		return emplaceObject(descendant, ModelESP.new("BountyBoard", descendant, "Bounty Board"))
	end

	if parent.Name == "MissionNPC" then
		return emplaceObject(descendant, ModelESP.new("MissionBoard", descendant, "Mission Board"))
	end

	if parent.Name == "Trader" then
		return emplaceObject(descendant, ModelESP.new("NPC", descendant, "Trader"))
	end

	if parent.Name == "Clothes" then
		return emplaceObject(descendant, ModelESP.new("NPC", descendant, "Clothes"))
	end

	if parent.Name == "Titles" then
		return emplaceObject(descendant, ModelESP.new("NPC", descendant, "Title Selector"))
	end

	if parent.Name == "AdvancedQuests" then
		return emplaceObject(
			descendant,
			ModelESP.new("NPC", descendant, string.format("Advanced Quests (%s)", descendant.Name))
		)
	end

	if parent.Name == "DivisionDuties" then
		return emplaceObject(descendant, ModelESP.new("NPC", descendant, "Division Duties"))
	end

	if parent.Name == "Captains" then
		return emplaceObject(descendant, ModelESP.new("NPC", descendant, "Captain"))
	end

	return emplaceObject(
		descendant,
		ModelESP.new("NPC", descendant, string.format("%s (%s)", parent.Name, descendant.Name))
	)
end)

---On Entities ChildAdded.
---@param child Instance
local onEntitiesChildAdded = LPH_NO_VIRTUALIZE(function(child)
	if players:GetPlayerFromCharacter(child) then
		return
	end

	-- safeguard lol
	if players:FindFirstChild(child.Name) then
		return
	end

	return emplaceObject(child, MobESP.new("Mob", child, child:GetAttribute("EntityType") or child.Name))
end)

---On instance removing.
---@param inst Instance
local onInstanceRemoving = LPH_NO_VIRTUALIZE(function(inst)
	for _, group in next, groups do
		local object = group:remove(inst)
		if not object then
			continue
		end

		object:detach()
	end
end)

---On player added.
---@param player Player
local onPlayerAdded = LPH_NO_VIRTUALIZE(function(player)
	if player == players.LocalPlayer then
		return
	end

	local characterAdded = Signal.new(player.CharacterAdded)
	local characterRemoving = Signal.new(player.CharacterRemoving)
	local playerDestroying = Signal.new(player.Destroying)

	local characterAddedId = nil
	local characterRemovingId = nil
	local playerDestroyingId = nil

	characterAddedId = visualsMaid:add(characterAdded:connect("Visuals_OnCharacterAdded", function(character)
		emplaceObject(player, PlayerESP.new("Player", player, character))
	end))

	characterRemovingId = visualsMaid:add(characterRemoving:connect("Visuals_OnCharacterRemoving", function()
		onInstanceRemoving(player)
	end))

	playerDestroyingId = visualsMaid:add(playerDestroying:connect("Visuals_OnPlayerDestroying", function()
		visualsMaid[characterAddedId] = nil
		visualsMaid[characterRemovingId] = nil
		visualsMaid[playerDestroyingId] = nil
	end))

	local character = player.Character
	if not character then
		return
	end

	emplaceObject(player, PlayerESP.new("Player", player, character))
end)

---On Soul Crystal Spawn Child Added.
---@param child Instance
local onSoulCrystalSpawnChildAdded = LPH_NO_VIRTUALIZE(function(child)
	return emplaceObject(
		child,
		child:IsA("Model") and ModelESP.new("SoulCrystal", child, "Soul Crystal")
			or PartESP.new("SoulCrystal", child, "Soul Crystal")
	)
end)

---On Misc Descendant Added.
---@param child Instance
local onMiscDescendantAdded = LPH_NO_VIRTUALIZE(function(child)
	if child.Name ~= "lootorb" then
		return
	end

	return emplaceObject(child, PartESP.new("LootOrb", child, "Loot Orb"))
end)

---Create listener.
---@param instance Instance
---@param identifier string
---@param addedCallback function
---@param removingCallback function
---@param childFlag boolean
local createListener = LPH_NO_VIRTUALIZE(function(instance, identifier, addedCallback, removingCallback, childFlag)
	local type = childFlag and "Child" or "Descendant"
	local added = Signal.new(childFlag and instance.ChildAdded or instance.DescendantAdded)
	local removed = Signal.new(childFlag and instance.ChildRemoved or instance.DescendantRemoving)

	visualsMaid:add(added:connect(string.format("Visuals_%sOn%sAdded", identifier, type), addedCallback))
	visualsMaid:add(removed:connect(string.format("Visuals_%sOn%sRemoved", identifier, type), removingCallback))

	Profiler.run(string.format("Visuals_%sAddInitial", identifier), function()
		for _, child in next, (childFlag and instance:GetChildren() or instance:GetDescendants()) do
			addedCallback(child)
		end
	end)
end)

---Initialize Visuals.
function Visuals.init()
	local ents = workspace:WaitForChild("Entities")
	local npcs = workspace:WaitForChild("NPCs")
	local misc = workspace:WaitForChild("Misc", 2.0)

	createListener(npcs, "NPCs", onNPCsDescendantAdded, onInstanceRemoving, false)
	createListener(ents, "Entities", onEntitiesChildAdded, onInstanceRemoving, true)
	createListener(players, "Players", onPlayerAdded, onInstanceRemoving, true)

	if misc then
		createListener(misc, "Misc", onMiscDescendantAdded, onInstanceRemoving, true)
	end

	if game.PlaceId == 18214402201 then
		local soulCrystalSpawns = workspace:WaitForChild("SoulCrystalSpawns")
		local soulCrystalSpawned = soulCrystalSpawns:WaitForChild("Spawned")
		createListener(soulCrystalSpawned, "SoulCrystalSpawned", onSoulCrystalSpawnChildAdded, onInstanceRemoving, true)
	end

	visualsMaid:add(renderStepped:connect("Visuals_RenderStepped", updateVisuals))

	Logger.warn("Visuals initialized.")
end

-- Detach Visuals.
function Visuals.detach()
	for _, group in next, groups do
		group:detach()
	end

	visualsMaid:clean()

	Logger.warn("Visuals detached.")
end

-- Return Visuals module.
return Visuals
