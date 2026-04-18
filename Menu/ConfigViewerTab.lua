-- ConfigViewerTab module.
local ConfigViewerTab = {}

---@module GUI.ConfigViewerPanel
local ConfigViewerPanel = require("GUI/ConfigViewerPanel")

---@module Game.Timings.SaveManager
local SaveManager = require("Game/Timings/SaveManager")

---@module Features.Combat.TimingHarvester
local TimingHarvester = require("Features/Combat/TimingHarvester")

---@module Utility.Logger
local Logger = require("Utility/Logger")

local summaryLabel = nil
local configNameInput = nil
local configListDropdown = nil

local function bannedCount()
	local count = 0
	for _ in next, TimingHarvester.getBanned() do
		count = count + 1
	end
	return count
end

local function configAnimationContainer()
	return SaveManager.as and SaveManager.as.config or nil
end

local function configTimingCount()
	local config = configAnimationContainer()
	return config and config:count() or 0
end

local function refreshConfigList()
	if configListDropdown then
		SaveManager.refresh(configListDropdown)
	end
end

local function refreshViewerState(reloadPreview)
	refreshConfigList()
	ConfigViewerTab.refreshSummary()
	ConfigViewerPanel.refresh(reloadPreview ~= false)
	return true
end

function ConfigViewerTab.refreshSummary()
	if not summaryLabel then
		return
	end

	local loadedConfigName = SaveManager.llcn or "none"
	local timingCount = configTimingCount()
	local detail = "Open the square viewer to browse NPC thumbnails, play saved animations, scrub the timeline, and edit per-action timings."

	if not SaveManager.llcn or #SaveManager.llcn <= 0 then
		detail = "No config is currently loaded. Use the controls above to load your saved timing file into the viewer."
	elseif timingCount == 0 then
		detail = string.format("Loaded config '%s' has no saved animation timings.", SaveManager.llcn)
	end

	summaryLabel:SetText(string.format(
		"Loaded Config: %s\nSaved Animation Timings: %d\nBanned Animation IDs: %d\n\n%s",
		loadedConfigName,
		timingCount,
		bannedCount(),
		detail
	))
end

---@param groupbox table
function ConfigViewerTab.initViewerSection(groupbox)
	configNameInput = groupbox:AddInput("ConfigViewerConfigName", {
		Text = "Config Name",
	})

	configListDropdown = groupbox:AddDropdown("ConfigViewerConfigList", {
		Text = "Config List",
		Values = SaveManager.list(),
		AllowNull = true,
	})

	groupbox
		:AddButton("Create Config", function()
			SaveManager.create(configNameInput.Value)
			refreshViewerState(false)
		end)
		:AddButton({
			Text = "Load Config",
			DoubleClick = true,
			Func = function()
				SaveManager.load(configListDropdown.Value)
				refreshViewerState(true)
			end,
		})

	groupbox:AddButton("Refresh Config List", function()
		refreshViewerState(false)
		Logger.notify("Config viewer list refreshed.")
	end)

	groupbox:AddButton("Open Config Viewer", function()
		ConfigViewerPanel.visible(true)
		refreshViewerState(true)
	end)

	groupbox:AddButton("Save Current Timing Config", function()
		if not SaveManager.llcn or #SaveManager.llcn <= 0 then
			return Logger.notify("No loaded config file to write. Load or create one first.")
		end

		SaveManager.write(SaveManager.llcn)
		refreshViewerState(false)
	end)

	groupbox:AddButton("Set To Auto Load", function()
		SaveManager.autoload(configListDropdown and configListDropdown.Value or nil)
		ConfigViewerTab.refreshSummary()
	end)

	groupbox:AddButton("Close Config Viewer", function()
		ConfigViewerPanel.visible(false)
	end)

	summaryLabel = groupbox:AddLabel("Loading config viewer summary...", true)
	ConfigViewerTab.refreshSummary()
end

---@param groupbox table
function ConfigViewerTab.initHelpSection(groupbox)
	groupbox:AddLabel(
		"The square viewer groups saved timings by NPC-like entity, shows a model thumbnail when a preview source exists, lists the saved animations for that group, and plays the selected animation with action markers over the timeline.",
		true
	)
	groupbox:AddLabel(
		"You can rename the saved animation, change the selected action type to Parry or Dash, edit its delay in milliseconds, toggle No Dash Fallback, delete timings or actions, and ban or unban animation IDs from the same panel.",
		true
	)
end

---@param window table
function ConfigViewerTab.init(window)
	local tab = window:AddTab("Config Viewer")

	ConfigViewerTab.initViewerSection(tab:AddLeftGroupbox("Viewer"))
	ConfigViewerTab.initHelpSection(tab:AddRightGroupbox("Usage"))
end

return ConfigViewerTab
