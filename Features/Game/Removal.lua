return LPH_NO_VIRTUALIZE(function()
	-- Removal related stuff is handled here.
	local Removal = {}

	---@module Utility.Maid
	local Maid = require("Utility/Maid")

	---@module Utility.Signal
	local Signal = require("Utility/Signal")

	---@module Utility.Configuration
	local Configuration = require("Utility/Configuration")

	---@module Utility.OriginalStoreManager
	local OriginalStoreManager = require("Utility/OriginalStoreManager")

	---@module Utility.Logger
	local Logger = require("Utility/Logger")

	-- Services.
	local runService = game:GetService("RunService")
	local players = game:GetService("Players")
	local lighting = game:GetService("Lighting")

	-- Maids.
	local removalMaid = Maid.new()

	-- Original store managers.
	local noFogMap = removalMaid:mark(OriginalStoreManager.new())
	local noRaidMusicMap = removalMaid:mark(OriginalStoreManager.new())

	-- Signals.
	local renderStepped = Signal.new(runService.RenderStepped)

	-- Last update.
	local lastUpdate = os.clock()

	---Update no fog.
	local function updateNoFog()
		if lighting.FogStart == 9e9 and lighting.FogEnd == 9e9 then
			return
		end

		noFogMap:add(lighting, "FogStart", 9e9)
		noFogMap:add(lighting, "FogEnd", 9e9)

		local atmosphere = lighting:FindFirstChildOfClass("Atmosphere")
		if not atmosphere then
			return
		end

		if atmosphere.Density == 0 then
			return
		end

		noFogMap:add(atmosphere, "Density", 0)
	end

	---Update no raid music.
	local function updateNoRaidMusic()
		local playerRaid = workspace:FindFirstChild("PlayerRaid")
		if not playerRaid then
			return
		end

		for _, child in ipairs(playerRaid:GetChildren()) do
			if not child:IsA("Sound") then
				continue
			end

			noRaidMusicMap:add(child, "Volume", 0)
		end
	end

	---Update removal.
	local function updateRemoval()
		if os.clock() - lastUpdate <= 2.0 then
			return
		end

		lastUpdate = os.clock()

		local localPlayer = players.LocalPlayer
		if not localPlayer then
			return
		end

		if Configuration.expectToggleValue("NoFog") then
			updateNoFog()
		else
			noFogMap:restore()
		end

		if Configuration.expectToggleValue("NoRaidMusic") then
			updateNoRaidMusic()
		else
			noRaidMusicMap:restore()
		end
	end

	---Initalize removal.
	function Removal.init()
		removalMaid:add(renderStepped:connect("Removal_RenderStepped", updateRemoval))

		-- Log.
		Logger.warn("Removal initialized.")
	end

	---Detach removal.
	function Removal.detach()
		-- Clean.
		removalMaid:clean()

		-- Log.
		Logger.warn("Removal detached.")
	end

	-- Return Removal module.
	return Removal
end)()
