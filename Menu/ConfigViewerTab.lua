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

local function bannedCount()
	local count = 0
	for _ in next, TimingHarvester.getBanned() do
		count = count + 1
	end
	return count
end

local function configTimingCount()
	local config = SaveManager.as and SaveManager.as.config
	return config and config:count() or 0
end

function ConfigViewerTab.refreshSummary()
	if not summaryLabel then
		return
	end

	summaryLabel:SetText(string.format(
		"Loaded Config: %s\nSaved Animation Timings: %d\nBanned Animation IDs: %d\n\nOpen the square viewer to browse NPC thumbnails, play saved animations, scrub the timeline, and edit per-action timings.",
		SaveManager.llcn or "unsaved session",
		configTimingCount(),
		bannedCount()
	))
end

---@param groupbox table
function ConfigViewerTab.initViewerSection(groupbox)
	summaryLabel = groupbox:AddLabel("Loading config viewer summary...", true)
	ConfigViewerTab.refreshSummary()

	groupbox:AddButton("Open Config Viewer", function()
		ConfigViewerPanel.toggle()
		ConfigViewerTab.refreshSummary()
	end)

	groupbox:AddButton("Refresh Viewer Summary", function()
		ConfigViewerPanel.refresh(true)
		ConfigViewerTab.refreshSummary()
		Logger.notify("Config viewer refreshed.")
	end)

	groupbox:AddButton("Save Current Timing Config", function()
		if not SaveManager.llcn or #SaveManager.llcn <= 0 then
			return Logger.notify("No loaded config file to write. Load or create one first.")
		end

		SaveManager.write(SaveManager.llcn)
		ConfigViewerTab.refreshSummary()
	end)

	groupbox:AddButton("Close Config Viewer", function()
		ConfigViewerPanel.visible(false)
	end)
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
