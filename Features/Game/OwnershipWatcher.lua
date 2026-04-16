-- Ownership data.
local clientPart = Instance.new("Part", workspace)
local clientSuccess, clientPeerId = pcall(function()
	return gethiddenproperty(clientPart, "NetworkOwnerV3")
end)

clientPart:Destroy()

---Check for network ownership.
---@param part BasePart
---@return boolean
local function hasNetworkOwnership(part)
	if getexecutorname():match("AWP") then
		return isnetworkowner(part)
	end

	if getexecutorname():match("Volcano") then
		return isnetworkowner(part)
	end

	if not clientSuccess then
		return isnetworkowner(part)
	end

	local partSuccess, partPeerId = pcall(function()
		return gethiddenproperty(part, "NetworkOwnerV3")
	end)

	if not partSuccess then
		return isnetworkowner(part)
	end

	return partPeerId == clientPeerId
end

return LPH_NO_VIRTUALIZE(function()
	-- Ownership watcher module.
	local OwnershipWatcher = { modelsToScan = {}, parts = {} }

	-- Services
	local runService = game:GetService("RunService")

	---@module Utility.Maid
	local Maid = require("Utility/Maid")

	---@module Utility.Configuration
	local Configuration = require("Utility/Configuration")

	---@module Utility.Signal
	local Signal = require("Utility/Signal")

	---@module Utility.InstanceWrapper
	local InstanceWrapper = require("Utility/InstanceWrapper")

	---@module Utility.Logger
	local Logger = require("Utility/Logger")

	-- Signals.
	local renderStepped = Signal.new(runService.RenderStepped)

	-- Maids.
	local ownershipMaid = Maid.new()

	---Clean up parts. Every model to scan has a maid linked to it.
	local function cleanParts()
		for _, maid in next, OwnershipWatcher.modelsToScan do
			maid:clean()
		end
	end

	---Add entity characters to ownership watcher.
	---@param character Model
	local function onEntitiesAdded(character)
		if not character:IsA("Model") then
			return
		end

		if OwnershipWatcher.modelsToScan[character] then
			return
		end

		OwnershipWatcher.modelsToScan[character] = Maid.new()
	end

	---Remove entity characters from ownership watcher.
	---@param character Model
	local function onEntitiesRemoved(character)
		if not OwnershipWatcher.modelsToScan[character] then
			return
		end

		OwnershipWatcher.modelsToScan[character]:clean()
		OwnershipWatcher.modelsToScan[character] = nil
	end

	---Update ownership.
	local function updateOwnership()
		---@optimization: Stop updating when we don't need it.
		if not Configuration.expectToggleValue("ShowOwnership") and not Configuration.expectToggleValue("VoidMobs") then
			return cleanParts()
		end

		-- Create an update table.
		local updateTable = {}

		-- Add models.
		for model, maid in next, OwnershipWatcher.modelsToScan do
			local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
			if not humanoidRootPart then
				continue
			end

			-- Check if owner.
			local isNetworkOwner = hasNetworkOwnership(humanoidRootPart)

			-- Visualization.
			local netVisual = InstanceWrapper.create(maid, "NetworkVisual", "Part", model)
			netVisual.Size = Vector3.new(10, 10, 10)
			netVisual.Transparency = Configuration.expectToggleValue("ShowOwnership") and 0.8 or 1.0
			netVisual.Color = isNetworkOwner and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
			netVisual.CFrame = humanoidRootPart.CFrame
			netVisual.Anchored = true
			netVisual.CanCollide = false

			-- Part data.
			local data = OwnershipWatcher.parts[humanoidRootPart]
				or {
					owned = isNetworkOwner,
					model = model,
				}

			-- Update part data.
			data.owned = isNetworkOwner
			data.model = model

			-- Set in global part list.
			OwnershipWatcher.parts[humanoidRootPart] = data

			-- Set in map.
			updateTable[humanoidRootPart] = data
		end

		-- Override global part list with the new update table.
		---@note: This will get rid of any parts that were not updated (e.g no longer existing root part or not in model list) upon cycle.
		---@todo: Fix me - this is a bit of a hack.
		OwnershipWatcher.parts = updateTable
	end

	---Get table of watched parts along with a mapping to extra data.
	---@return table<BasePart, table>
	function OwnershipWatcher.get()
		return OwnershipWatcher.parts
	end

	---Initialize OwnershipWatcher module.
	function OwnershipWatcher.init()
		local entities = workspace:WaitForChild("Entities")
		local entitiesChildAdded = Signal.new(entities.ChildAdded)
		local entitiesChildRemoved = Signal.new(entities.ChildRemoved)

		ownershipMaid:add(entitiesChildAdded:connect("OwnershipWatcher_OnEntitiesChildAdded", onEntitiesAdded))
		ownershipMaid:add(entitiesChildRemoved:connect("OwnershipWatcher_OnEntitiesChildRemoved", onEntitiesRemoved))
		ownershipMaid:add(renderStepped:connect("OwnershipWatcher_RenderStepped", updateOwnership))

		for _, entity in next, entities:GetChildren() do
			onEntitiesAdded(entity)
		end

		Logger.warn("OwnershipWatcher initialized.")
	end

	---Detach OwnershipWatcher module.
	function OwnershipWatcher.detach()
		-- Clean up ownership maids.
		ownershipMaid:clean()

		-- Clean up parts.
		cleanParts()

		-- Log.
		Logger.warn("OwnershipWatcher detached.")
	end

	-- Return OwnershipWatcher module.
	return OwnershipWatcher
end)()
