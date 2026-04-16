-- Player scanning is handled here.
local PlayerScanning = {
	scanQueue = {},
	scanDataCache = {},
	friendCache = {},
	waitingForLoad = {},
	readyList = {},
	scanning = false,
}

---@module Utility.CoreGuiManager
local CoreGuiManager = require("Utility/CoreGuiManager")

---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

-- Services.
local players = game:GetService("Players")
local httpService = game:GetService("HttpService")
local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")

-- Instances.
local moderatorSound = CoreGuiManager.imark(Instance.new("Sound"))

-- Maid.
local playerScanningMaid = Maid.new()

-- Timestamp.
local lastRateLimit = nil

---Fetch name.
local function fetchName(player)
	local spoofName = Configuration.expectToggleValue("InfoSpoofing")
		and Configuration.expectToggleValue("SpoofOtherPlayers")

	return spoofName and "[REDACTED]"
		or string.format("(%s) %s", player:GetAttribute("CharacterName") or "Unknown Character Name", player.Name)
end

---Run player scans.
local runPlayerScans = LPH_NO_VIRTUALIZE(function()
	local localPlayer = players.LocalPlayer
	if not localPlayer then
		return
	end

	for player, _ in next, PlayerScanning.scanQueue do
		if shared.Lycoris.dpscanning then
			continue
		end

		if not PlayerScanning.scanDataCache[player] then
			local handledSuccess, handledResult = nil, nil

			local unhandledSuccess, unhandledResult = pcall(function()
				handledSuccess, handledResult = PlayerScanning.getStaffRank(player)
			end)

			if not unhandledSuccess then
				Logger.warn(
					"Scan player %s ran into error '%s' while getting staff rank.",
					player.Name,
					unhandledResult
				)

				Logger.longNotify("Failed to scan player %s for moderator status.", fetchName(player), unhandledResult)

				PlayerScanning.scanQueue[player] = nil

				continue
			end

			if not handledSuccess then
				continue
			end

			if Configuration.expectToggleValue("NotifyMod") and handledResult then
				Logger.longNotify("%s is a staff member with the rank '%s' in group.", fetchName(player), handledResult)

				if Configuration.expectToggleValue("NotifyModSound") then
					moderatorSound.SoundId = "rbxassetid://6045346303"
					moderatorSound.PlaybackSpeed = 1
					moderatorSound.Volume = Configuration.expectToggleValue("NotifyModSoundVolume") or 10
					moderatorSound:Play()
				end
			end

			PlayerScanning.scanDataCache[player] = { staffRank = handledResult }
		end

		PlayerScanning.scanQueue[player] = nil

		PlayerScanning.friendCache[player] = localPlayer:GetFriendStatus(player) == Enum.FriendStatus.Friend

		Logger.warn("Player scanning finished scanning %s in queue.", fetchName(player))
	end
end)

---Are there moderators in the server?
---@return table
function PlayerScanning.hasModerators()
	for _, scanData in next, PlayerScanning.scanDataCache do
		if not scanData.staffRank then
			continue
		end

		return true
	end

	return false
end

---Is a player an ally?
---@param player Player
---@return boolean
function PlayerScanning.isAlly(player)
	return PlayerScanning.friendCache[player]
end

---Fetch roblox data.
---@param url string
---@return boolean, string?
local function fetchRobloxData(url)
	if lastRateLimit and os.clock() - lastRateLimit <= 30 then
		return false, "On rate-limit cooldown."
	end

	local response = request({
		Url = url,
		Method = "GET",
		Headers = {
			["Content-Type"] = "application/json",
		},
	})

	if response.StatusCode == 429 then
		Logger.longNotify("Player scanning is being rate-limited and results will be delayed.")
		Logger.longNotify("Please stay in the server with caution.")

		lastRateLimit = os.clock()

		return false, "Rate-limited."
	end

	if not response then
		return error("Failed to fetch Roblox data.")
	end

	if not response.Success then
		return error(
			string.format("Failed to successfully fetch Roblox data with status code %i.", response.StatusCode)
		)
	end

	if not response.Body then
		return error("Failed to find Roblox data.")
	end

	return true, httpService:JSONDecode(response.Body)
end

---Get staff rank - nil if they're not a staff.
---@param player Player
---@return boolean, string?
function PlayerScanning.getStaffRank(player)
	local responseSuccess, responseData =
		fetchRobloxData(("https://groups.roblox.com/v2/users/%i/groups/roles?includeLocked=true"):format(player.UserId))

	if not responseSuccess then
		return false, responseData
	end

	local character = player.Character

	if character and character:GetAttribute("ContentCreator") then
		return true, "Content Creator"
	end

	for _, groupData in next, responseData.data do
		if groupData.group.id ~= 32740991 and groupData.group.id ~= 13077028 then
			continue
		end

		if groupData.role.rank <= 0 then
			continue
		end

		return true, groupData.role.name
	end

	return true, nil
end

---Update player scanning.
---@note: Request will yield - so we need a debounce to prevent multiple scan loops.
---@note: We must defer the error back to the caller and reset the scanning debounce so errors will not break the scanning loop.
function PlayerScanning.update()
	if PlayerScanning.scanning then
		return
	end

	PlayerScanning.scanning = true

	local success, result = pcall(runPlayerScans)

	PlayerScanning.scanning = false

	if success then
		return
	end

	return error(result)
end

---On friend status changed.
---@param player Player
---@param status Enum.FriendStatus
function PlayerScanning.friend(player, status)
	PlayerScanning.friendCache[player] = status == Enum.FriendStatus.Friend
end

---On player added.
---@param player Player
function PlayerScanning.onPlayerAdded(player)
	if player == players.LocalPlayer then
		return
	end

	PlayerScanning.scanQueue[player] = true
end

---On player removing.
---@param player Player
function PlayerScanning.onPlayerRemoving(player)
	PlayerScanning.scanQueue[player] = nil
	PlayerScanning.scanDataCache[player] = nil
	PlayerScanning.friendCache[player] = nil
	PlayerScanning.waitingForLoad[player] = nil
end

---Initialize PlayerScanning.
function PlayerScanning.init()
	-- Signals.
	local playerAddedSignal = Signal.new(players.PlayerAdded)
	local playerRemovingSignal = Signal.new(players.PlayerRemoving)
	local renderSteppedSignal = Signal.new(runService.RenderStepped)
	local friendStatusChanged = Signal.new(players.LocalPlayer.FriendStatusChanged)

	-- Connect events.
	playerScanningMaid:add(friendStatusChanged:connect("PlayerScanning_OnFriendStatusChanged", PlayerScanning.friend))
	playerScanningMaid:add(renderSteppedSignal:connect("PlayerScanning_Update", PlayerScanning.update))
	playerScanningMaid:add(playerAddedSignal:connect("PlayerScanning_OnPlayerAdded", PlayerScanning.onPlayerAdded))
	playerScanningMaid:add(
		playerRemovingSignal:connect("PlayerScanning_OnPlayerRemoving", PlayerScanning.onPlayerRemoving)
	)

	-- Run event(s) for existing players.
	for _, player in next, players:GetPlayers() do
		PlayerScanning.onPlayerAdded(player)
	end
end

---Detach PlayerScanning.
function PlayerScanning.detach()
	playerScanningMaid:clean()
end

-- Return PlayerScanning module.
return PlayerScanning
