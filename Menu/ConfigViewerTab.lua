-- ConfigViewerTab module.
local ConfigViewerTab = {}

---@module Game.Timings.SaveManager
local SaveManager = require("Game/Timings/SaveManager")

---@module Features.Combat.TimingHarvester
local TimingHarvester = require("Features/Combat/TimingHarvester")

---@module Features.Game.AnimationVisualizer
local AnimationVisualizer = require("Features/Game/AnimationVisualizer")

---@module Features.Game.AnimationLogger
local AnimationLogger = require("Features/Game/AnimationLogger")

---@module Utility.Logger
local Logger = require("Utility/Logger")

local ui = {}
local state = {
	selectedNpc = nil,
	selectedTimingName = nil,
	selectedActionName = nil,
	selectedBannedAid = nil,
}

---@return TimingContainer?
local function configAnimationContainer()
	return SaveManager.as and SaveManager.as.config or nil
end

---@param list string[]
---@param value string?
---@return boolean
local function hasValue(list, value)
	if not value then
		return false
	end

	for _, item in ipairs(list) do
		if item == value then
			return true
		end
	end

	return false
end

---@param value string
---@return string
local function lowerKey(value)
	return string.lower(tostring(value or ""))
end

---@param values string[]
local function sortStrings(values)
	table.sort(values, function(left, right)
		return lowerKey(left) < lowerKey(right)
	end)
end

---@param dropdown table
---@param values string[]
---@param value string?
local function setDropdown(dropdown, values, value)
	dropdown:SetValues(values)
	dropdown:SetRawValue(value)
	dropdown:Display()
end

---@param timing AnimationTiming?
---@return string
local function timingEntityName(timing)
	if not timing then
		return "Unknown"
	end

	local name = tostring(timing.name or "")
	local harvested = name:match("^(.-)_%d+_Harvested$")
	if harvested and #harvested > 0 then
		return harvested
	end

	return name ~= "" and name or "Unknown"
end

---@param timing AnimationTiming?
---@return string
local function timingAnimationId(timing)
	local aid = timing and timing._id
	if type(aid) ~= "string" or aid == "" then
		return "-"
	end

	return aid
end

---@param timing AnimationTiming?
---@return string[]
local function timingActionNames(timing)
	if not timing then
		return {}
	end

	local names = timing.actions:names()
	sortStrings(names)
	return names
end

---@return table<string, { timings: AnimationTiming[] }>, string[], number
local function groupedConfigTimings()
	local grouped = {}
	local names = {}
	local total = 0
	local container = configAnimationContainer()

	if not container then
		return grouped, names, total
	end

	for _, timing in ipairs(container:list()) do
		total = total + 1

		local entityName = timingEntityName(timing)
		local bucket = grouped[entityName]
		if not bucket then
			bucket = { timings = {} }
			grouped[entityName] = bucket
			table.insert(names, entityName)
		end

		table.insert(bucket.timings, timing)
	end

	sortStrings(names)

	for _, entityName in ipairs(names) do
		table.sort(grouped[entityName].timings, function(left, right)
			local leftId = timingAnimationId(left)
			local rightId = timingAnimationId(right)

			if leftId == rightId then
				return lowerKey(left.name) < lowerKey(right.name)
			end

			return lowerKey(leftId) < lowerKey(rightId)
		end)
	end

	return grouped, names, total
end

---@param aid string?
---@return AnimationTiming[]
local function timingsForAnimationId(aid)
	local matches = {}
	if not aid then
		return matches
	end

	local container = configAnimationContainer()
	if not container then
		return matches
	end

	for _, timing in ipairs(container:list()) do
		if timing._id == aid then
			table.insert(matches, timing)
		end
	end

	table.sort(matches, function(left, right)
		return lowerKey(left.name) < lowerKey(right.name)
	end)

	return matches
end

---@return AnimationTiming?
local function selectedTiming()
	local container = configAnimationContainer()
	return container and state.selectedTimingName and container:find(state.selectedTimingName) or nil
end

---@return Action?
local function selectedAction()
	local timing = selectedTiming()
	return timing and state.selectedActionName and timing.actions:find(state.selectedActionName) or nil
end

---@return number
local function bannedCount()
	local count = 0
	for _ in next, TimingHarvester.getBanned() do
		count = count + 1
	end
	return count
end

---@param timing AnimationTiming?
---@return string
local function timingSummaryText(timing)
	if not timing then
		return "Select a saved animation timing to view its details."
	end

	local actionCount = timing.actions:count()
	local actionLines = {}
	for _, actionName in ipairs(timingActionNames(timing)) do
		local action = timing.actions:find(actionName)
		if action then
			table.insert(
				actionLines,
				string.format("- %s: %s @ %dms", action.name, action._type or "Parry", tonumber(action._when) or 0)
			)
		end
	end

	if #actionLines == 0 then
		actionLines[1] = "- No actions saved"
	end

	return table.concat({
		string.format("Timing: %s", timing.name),
		string.format("Animation ID: %s", timingAnimationId(timing)),
		string.format("Entity Group: %s", timingEntityName(timing)),
		string.format("Tag: %s", timing.tag or "Undefined"),
		string.format("Distance: %.0f - %.0f", tonumber(timing.imdd) or 0, tonumber(timing.imxd) or 0),
		string.format("Punishable / After: %.2fs / %.2fs", tonumber(timing.punishable) or 0, tonumber(timing.after) or 0),
		string.format("Delay Until In Hitbox: %s", timing.duih and "On" or "Off"),
		string.format("No Dash Fallback: %s", timing.ndfb and "On" or "Off"),
		string.format("Use Module Over Actions: %s", timing.umoa and "On" or "Off"),
		string.format("Animation ID Banned: %s", TimingHarvester.isBanned(timing._id) and "Yes" or "No"),
		string.format("Actions (%d):", actionCount),
		table.concat(actionLines, "\n"),
	}, "\n")
end

---@param timing AnimationTiming?
---@return string
local function npcSummaryText(timingList)
	if not timingList or #timingList == 0 then
		return "No saved timings for the selected NPC group."
	end

	local lines = { string.format("Saved Animations: %d", #timingList) }
	for index, timing in ipairs(timingList) do
		if index > 10 then
			table.insert(lines, string.format("... and %d more", #timingList - 10))
			break
		end

		table.insert(lines, string.format("- %s [%s]", timing.name, timingAnimationId(timing)))
	end

	return table.concat(lines, "\n")
end

---@param action Action?
---@return string
local function actionSummaryText(action)
	if not action then
		return "Select an action to view or edit its timing details."
	end

	local pingProfiles = {}
	for _, profile in ipairs(action.pingProfiles or {}) do
		table.insert(
			pingProfiles,
			string.format(
				"- RTT %dms -> %dms (samples=%d)",
				math.round(profile.ping or 0),
				math.round(profile.when or 0),
				math.floor(profile.samples or 1)
			)
		)
	end

	if #pingProfiles == 0 then
		pingProfiles[1] = "- No ping profiles saved"
	end

	return table.concat({
		string.format("Action: %s", action.name),
		string.format("Type: %s", action._type or "Parry"),
		string.format("Delay: %dms", tonumber(action._when) or 0),
		string.format(
			"Hitbox: %.0f x %.0f x %.0f",
			action.hitbox.X,
			action.hitbox.Y,
			action.hitbox.Z
		),
		"Ping Profiles:",
		table.concat(pingProfiles, "\n"),
	}, "\n")
end

---@param aid string?
---@return string
local function bannedSummaryText(aid)
	if not aid then
		return "No banned animation ID selected."
	end

	local banned = TimingHarvester.getBanned()[aid]
	if not banned then
		return "The selected animation ID is not currently banned."
	end

	local matching = timingsForAnimationId(aid)
	local matchingLines = {}
	for index, timing in ipairs(matching) do
		if index > 8 then
			table.insert(matchingLines, string.format("... and %d more", #matching - 8))
			break
		end

		table.insert(matchingLines, string.format("- %s", timing.name))
	end

	if #matchingLines == 0 then
		matchingLines[1] = "- No saved config timings use this ID"
	end

	return table.concat({
		string.format("Animation ID: %s", aid),
		string.format("Entity Name: %s", banned.meta and banned.meta.entityName or "?"),
		string.format("Priority: %s", banned.meta and banned.meta.priority or "?"),
		string.format("Seen / Samples: %d / %d", tonumber(banned.seenCount) or 0, tonumber(banned.sampleCount) or 0),
		"Matching Saved Timings:",
		table.concat(matchingLines, "\n"),
	}, "\n")
end

local function saveCurrentConfig()
	if not SaveManager.llcn or #SaveManager.llcn <= 0 then
		return Logger.notify("No loaded config file to write. Use the Builder save manager first.")
	end

	SaveManager.write(SaveManager.llcn)
end

local refreshAll

local function refreshBannedState()
	local ids = {}
	for aid in next, TimingHarvester.getBanned() do
		table.insert(ids, aid)
	end
	sortStrings(ids)

	if not hasValue(ids, state.selectedBannedAid) then
		state.selectedBannedAid = ids[1]
	end

	setDropdown(ui.bannedList, ids, state.selectedBannedAid)
	ui.bannedCountLabel:SetText(string.format("Banned Animation IDs: %d", #ids))
	ui.bannedInfoLabel:SetText(bannedSummaryText(state.selectedBannedAid))
end

refreshAll = function()
	local grouped, npcNames, totalTimings = groupedConfigTimings()
	local bannedIds = bannedCount()

	if not hasValue(npcNames, state.selectedNpc) then
		state.selectedNpc = npcNames[1]
	end

	setDropdown(ui.npcList, npcNames, state.selectedNpc)

	local npcTimings = state.selectedNpc and grouped[state.selectedNpc] and grouped[state.selectedNpc].timings or {}
	local timingNames = {}
	for _, timing in ipairs(npcTimings) do
		table.insert(timingNames, timing.name)
	end

	if not hasValue(timingNames, state.selectedTimingName) then
		state.selectedTimingName = timingNames[1]
	end

	setDropdown(ui.timingList, timingNames, state.selectedTimingName)

	local timing = selectedTiming()
	local actionNames = timingActionNames(timing)
	if not hasValue(actionNames, state.selectedActionName) then
		state.selectedActionName = actionNames[1]
	end

	setDropdown(ui.actionList, actionNames, state.selectedActionName)

	local action = selectedAction()

	ui.activeConfigLabel:SetText(string.format("Loaded Config: %s", SaveManager.llcn or "unsaved session"))
	ui.countsLabel:SetText(string.format("NPC Groups: %d\nSaved Timings: %d\nBanned IDs: %d", #npcNames, totalTimings, bannedIds))
	ui.npcSummaryLabel:SetText(npcSummaryText(npcTimings))
	ui.timingInfoLabel:SetText(timingSummaryText(timing))
	ui.actionInfoLabel:SetText(actionSummaryText(action))

	if timing then
		ui.timingName:SetRawValue(timing.name)
		ui.timingTag:SetRawValue(timing.tag or "Undefined")
		ui.timingTag:Display()
		ui.minDistance:SetRawValue(tonumber(timing.imdd) or 0)
		ui.maxDistance:SetRawValue(tonumber(timing.imxd) or 0)
		ui.noDashFallback:SetRawValue(timing.ndfb == true)
	else
		ui.timingName:SetRawValue("")
		ui.timingTag:SetRawValue("Undefined")
		ui.timingTag:Display()
		ui.minDistance:SetRawValue(0)
		ui.maxDistance:SetRawValue(0)
		ui.noDashFallback:SetRawValue(false)
	end

	if action then
		ui.actionType:SetRawValue(action._type or "Parry")
		ui.actionType:Display()
		ui.actionDelay:SetRawValue(tonumber(action._when) or 0)
		ui.hitboxWidth:SetRawValue(action.hitbox.X)
		ui.hitboxHeight:SetRawValue(action.hitbox.Y)
		ui.hitboxLength:SetRawValue(action.hitbox.Z)
	else
		ui.actionType:SetRawValue("Parry")
		ui.actionType:Display()
		ui.actionDelay:SetRawValue(0)
		ui.hitboxWidth:SetRawValue(0)
		ui.hitboxHeight:SetRawValue(0)
		ui.hitboxLength:SetRawValue(0)
	end

	refreshBannedState()
	ui.tabStatus:SetText("Viewer refreshed. Select an NPC group to browse saved timings.")
	end

---@param timing AnimationTiming?
---@return string?
local function timingIdOrNotify(timing)
	local aid = timing and timing._id
	if type(aid) ~= "string" or aid == "" then
		Logger.notify("The selected timing does not have an animation ID.")
		return nil
	end

	return aid
end

---Initialize tab.
---@param window table
function ConfigViewerTab.init(window)
	local tab = window:AddTab("Config Viewer")
	local browserBox = tab:AddLeftTabbox()
	local detailsBox = tab:AddRightTabbox()

	local configTab = browserBox:AddTab("Config")
	local bannedTab = browserBox:AddTab("Banned")
	local timingTab = detailsBox:AddTab("Timing")
	local actionTab = detailsBox:AddTab("Action")

	ui.tabStatus = configTab:AddLabel("Viewer ready.", true)
	ui.activeConfigLabel = configTab:AddLabel("Loaded Config: unsaved session", true)
	ui.countsLabel = configTab:AddLabel("NPC Groups: 0\nSaved Timings: 0\nBanned IDs: 0", true)
	configTab:AddBlank(4)

	ui.npcList = configTab:AddDropdown(nil, {
		Text = "NPC List",
		Values = {},
		AllowNull = true,
		Callback = function(value)
			state.selectedNpc = value
			state.selectedTimingName = nil
			state.selectedActionName = nil
			refreshAll()
		end,
	})

	ui.timingList = configTab:AddDropdown(nil, {
		Text = "Saved Animations",
		Values = {},
		AllowNull = true,
		Callback = function(value)
			state.selectedTimingName = value
			state.selectedActionName = nil
			refreshAll()
		end,
	})

	ui.npcSummaryLabel = configTab:AddLabel("No saved timings loaded.", true)

	configTab:AddButton("Refresh Viewer", function()
		refreshAll()
	end)

	configTab:AddButton("Visualize Selected", function()
		local timing = selectedTiming()
		local aid = timingIdOrNotify(timing)
		if aid then
			AnimationVisualizer.loadId(aid)
		end
	end)

	configTab:AddButton("Ban Selected ID", function()
		local timing = selectedTiming()
		local aid = timingIdOrNotify(timing)
		if not aid then
			return
		end

		local ok, result = TimingHarvester.ban(aid)
		if not ok then
			return Logger.notify(result)
		end

		AnimationLogger.removeCaptured(aid)
		refreshAll()
	end)

	configTab:AddButton({
		Text = "Delete Selected Timing",
		DoubleClick = true,
		Func = function()
			local timing = selectedTiming()
			local container = configAnimationContainer()
			if not timing or not container then
				return Logger.notify("Select a saved timing first.")
			end

			container:remove(timing)
			state.selectedTimingName = nil
			state.selectedActionName = nil
			refreshAll()
		end,
	})

	configTab:AddButton("Save Current Config", function()
		saveCurrentConfig()
	end)

	ui.bannedCountLabel = bannedTab:AddLabel("Banned Animation IDs: 0", true)
	ui.bannedList = bannedTab:AddDropdown(nil, {
		Text = "Banned Animation IDs",
		Values = {},
		AllowNull = true,
		Callback = function(value)
			state.selectedBannedAid = value
			refreshBannedState()
		end,
	})

	ui.bannedInfoLabel = bannedTab:AddLabel("No banned animation IDs.", true)

	bannedTab:AddButton("Refresh Banned", function()
		refreshBannedState()
	end)

	bannedTab:AddButton("Visualize Banned ID", function()
		if not state.selectedBannedAid then
			return Logger.notify("Select a banned animation ID first.")
		end

		AnimationVisualizer.loadId(state.selectedBannedAid)
	end)

	bannedTab:AddButton("Unban Selected ID", function()
		if not state.selectedBannedAid then
			return Logger.notify("Select a banned animation ID first.")
		end

		local ok, result = TimingHarvester.unban(state.selectedBannedAid)
		if not ok then
			return Logger.notify(result)
		end

		refreshAll()
	end)

	bannedTab:AddButton({
		Text = "Delete Matching Saved Timings",
		DoubleClick = true,
		Func = function()
			if not state.selectedBannedAid then
				return Logger.notify("Select a banned animation ID first.")
			end

			local container = configAnimationContainer()
			if not container then
				return Logger.notify("No loaded config timings to remove.")
			end

			local matches = timingsForAnimationId(state.selectedBannedAid)
			if #matches == 0 then
				return Logger.notify("No saved config timings use this animation ID.")
			end

			for _, timing in ipairs(matches) do
				container:remove(timing)
			end

			state.selectedTimingName = nil
			state.selectedActionName = nil
			refreshAll()
		end,
	})

	ui.timingInfoLabel = timingTab:AddLabel("Select a saved animation timing to view its details.", true)
	ui.timingName = timingTab:AddInput(nil, {
		Text = "Timing Name",
		Finished = true,
		Callback = function(value)
			local timing = selectedTiming()
			local container = configAnimationContainer()
			if not timing or not container then
				return Logger.notify("Select a saved timing first.")
			end

			if not value or #value <= 0 then
				return Logger.notify("Timing name cannot be empty.")
			end

			local existing = container:find(value)
			if existing and existing ~= timing then
				return Logger.notify("Timing name '%s' already exists.", value)
			end

			timing.name = value
			state.selectedNpc = timingEntityName(timing)
			state.selectedTimingName = value
			refreshAll()
		end,
	})

	ui.timingTag = timingTab:AddDropdown(nil, {
		Text = "Timing Tag",
		Values = { "Undefined", "Critical", "Mantra", "M1" },
		Default = 1,
		Callback = function(value)
			local timing = selectedTiming()
			if not timing then
				return Logger.notify("Select a saved timing first.")
			end

			timing.tag = value
			refreshAll()
		end,
	})

	ui.minDistance = timingTab:AddSlider(nil, {
		Text = "Initial Minimum Distance",
		Min = 0,
		Max = 300,
		Default = 0,
		Rounding = 0,
		Callback = function(value)
			local timing = selectedTiming()
			if not timing then
				return Logger.notify("Select a saved timing first.")
			end

			timing.imdd = value
			refreshAll()
		end,
	})

	ui.maxDistance = timingTab:AddSlider(nil, {
		Text = "Initial Maximum Distance",
		Min = 0,
		Max = 2500,
		Default = 0,
		Rounding = 0,
		Callback = function(value)
			local timing = selectedTiming()
			if not timing then
				return Logger.notify("Select a saved timing first.")
			end

			timing.imxd = value
			refreshAll()
		end,
	})

	ui.noDashFallback = timingTab:AddToggle(nil, {
		Text = "No Dash Fallback",
		Default = false,
		Callback = function(value)
			local timing = selectedTiming()
			if not timing then
				return Logger.notify("Select a saved timing first.")
			end

			timing.ndfb = value
			refreshAll()
		end,
	})

	ui.actionInfoLabel = actionTab:AddLabel("Select an action to view or edit its timing details.", true)
	ui.actionList = actionTab:AddDropdown(nil, {
		Text = "Action List",
		Values = {},
		AllowNull = true,
		Callback = function(value)
			state.selectedActionName = value
			refreshAll()
		end,
	})

	ui.actionType = actionTab:AddDropdown(nil, {
		Text = "Action Type",
		Values = { "Parry", "Dash", "Start Block", "End Block" },
		Default = 1,
		Callback = function(value)
			local action = selectedAction()
			if not action then
				return Logger.notify("Select an action first.")
			end

			action._type = value
			refreshAll()
		end,
	})

	ui.actionDelay = actionTab:AddInput(nil, {
		Text = "Action Delay",
		Numeric = true,
		Finished = true,
		Callback = function(value)
			local action = selectedAction()
			if not action then
				return Logger.notify("Select an action first.")
			end

			action._when = tonumber(value) or 0
			refreshAll()
		end,
	})

	ui.hitboxWidth = actionTab:AddSlider(nil, {
		Text = "Hitbox Width",
		Min = 0,
		Max = 300,
		Default = 0,
		Rounding = 0,
		Callback = function(value)
			local action = selectedAction()
			if not action then
				return Logger.notify("Select an action first.")
			end

			action.hitbox = Vector3.new(value, action.hitbox.Y, action.hitbox.Z)
			refreshAll()
		end,
	})

	ui.hitboxHeight = actionTab:AddSlider(nil, {
		Text = "Hitbox Height",
		Min = 0,
		Max = 300,
		Default = 0,
		Rounding = 0,
		Callback = function(value)
			local action = selectedAction()
			if not action then
				return Logger.notify("Select an action first.")
			end

			action.hitbox = Vector3.new(action.hitbox.X, value, action.hitbox.Z)
			refreshAll()
		end,
	})

	ui.hitboxLength = actionTab:AddSlider(nil, {
		Text = "Hitbox Length",
		Min = 0,
		Max = 300,
		Default = 0,
		Rounding = 0,
		Callback = function(value)
			local action = selectedAction()
			if not action then
				return Logger.notify("Select an action first.")
			end

			action.hitbox = Vector3.new(action.hitbox.X, action.hitbox.Y, value)
			refreshAll()
		end,
	})

	actionTab:AddButton({
		Text = "Remove Selected Action",
		DoubleClick = true,
		Func = function()
			local timing = selectedTiming()
			local action = selectedAction()
			if not timing or not action then
				return Logger.notify("Select an action first.")
			end

			timing.actions:remove(action)
			state.selectedActionName = nil
			refreshAll()
		end,
	})

	refreshAll()
end

-- Return ConfigViewerTab module.
return ConfigViewerTab