---@module Game.Timings.SaveManager
local SaveManager = require("Game/Timings/SaveManager")

---@module Menu.Objects.AnimationBuilderSection
local AnimationBuilderSection = require("Menu/Objects/AnimationBuilderSection")

---@module Menu.Objects.SoundBuilderSection
local SoundBuilderSection = require("Menu/Objects/SoundBuilderSection")

---@module Menu.Objects.PartBuilderSection
local PartBuilderSection = require("Menu/Objects/PartBuilderSection")

---@module Game.Timings.AnimationTiming
local AnimationTiming = require("Game/Timings/AnimationTiming")

---@module Game.Timings.PartTiming
local PartTiming = require("Game/Timings/PartTiming")

---@module Game.Timings.SoundTiming
local SoundTiming = require("Game/Timings/SoundTiming")

---@module Game.Timings.ModuleManager
local ModuleManager = require("Game/Timings/ModuleManager")

---@module Features.Game.AnimationVisualizer
local AnimationVisualizer = require("Features/Game/AnimationVisualizer")

---@module Features.Game.AnimationLogger
local AnimationLogger = require("Features/Game/AnimationLogger")

---@module Features.Combat.TimingHarvester
local TimingHarvester = require("Features/Combat/TimingHarvester")

---@module GUI.Library
local Library = require("GUI/Library")

-- BuilderTab module.
local BuilderTab = {
	abs = nil,
	pbs = nil,
	sbs = nil,
}

---Refresh builder lists.
function BuilderTab.refresh()
	if BuilderTab.abs then
		BuilderTab.abs:reset()
		BuilderTab.abs:refresh()
	end

	if BuilderTab.pbs then
		BuilderTab.pbs:reset()
		BuilderTab.pbs:refresh()
	end

	if BuilderTab.sbs then
		BuilderTab.sbs:reset()
		BuilderTab.sbs:refresh()
	end
end

---Initialize save manager section.
---@param groupbox table
function BuilderTab.initSaveManagerSection(groupbox)
	local pasToggle = groupbox:AddToggle("PeriodicAutoSave", {
		Text = "Auto Save Periodically",
		Default = true,
	})

	local pasDepBox = groupbox:AddDependencyBox()

	pasDepBox:AddSlider("PeriodicAutoSaveInterval", {
		Text = "Auto Save Interval",
		Min = 1,
		Max = 240,
		Rounding = 0,
		Suffix = "s",
		Default = 60,
	})

	pasDepBox:SetupDependencies({
		{ pasToggle, true },
	})

	local configName = groupbox:AddInput("ConfigName", {
		Text = "Config Name",
	})

	local configList = groupbox:AddDropdown("ConfigList", {
		Text = "Config List",
		Values = SaveManager.list(),
		AllowNull = true,
	})

	groupbox
		:AddButton("Create Config", function()
			SaveManager.create(configName.Value)
			SaveManager.refresh(configList)
		end)
		:AddButton({
			Text = "Load Config",
			DoubleClick = true,
			Func = function()
				SaveManager.load(configList.Value)
				BuilderTab.refresh()
			end,
		})

	groupbox:AddButton({
		Text = "Overwrite Config",
		DoubleClick = true,
		Func = function()
			SaveManager.save(configList.Value)
		end,
	})

	groupbox:AddButton({
		Text = "Clear Config",
		DoubleClick = true,
		Func = function()
			SaveManager.clear(configList.Value)
		end,
	})

	groupbox:AddButton("Refresh List", function()
		SaveManager.refresh(configList)

		if Options.MergeConfigList then
			SaveManager.refresh(Options.MergeConfigList)
		end

		BuilderTab.refresh()
	end)

	groupbox:AddButton("Set To Auto Load", function()
		SaveManager.autoload(configList.Value)
	end)
end

---Initialize merge manager section.
---@param groupbox table
function BuilderTab.initMergeManagerSection(groupbox)
	local configList = groupbox:AddDropdown("MergeConfigList", {
		Text = "Config List",
		Values = SaveManager.list(),
		AllowNull = true,
	})

	local mergeConfigType = groupbox:AddDropdown("MergeConfigType", {
		Text = "Merge Type",
		Values = { "Add New Timings", "Overwrite and Add Everything" },
		Default = 1,
	})

	groupbox:AddButton({
		Text = "Merge With Current Config",
		DoubleClick = true,
		Func = function()
			SaveManager.merge(configList.Value, mergeConfigType.Value)
		end,
	})
end

---Initialize logger section.
---@param groupbox table
function BuilderTab.initLoggerSection(groupbox)
	local animVisualizerToggle = groupbox:AddToggle("ShowAnimationVisualizer", {
		Text = "Show Animation Visualizer",
		Default = false,
		Callback = AnimationVisualizer.visible,
	})

	animVisualizerToggle:AddKeyPicker(
		"AnimationVisualizerKeyBind",
		{ Default = "N/A", SyncToggleState = true, Text = "Animation Visualizer" }
	)

	local showLoggerToggle = groupbox:AddToggle("ShowLoggerWindow", {
		Text = "Show Logger Window",
		Default = false,
		Callback = function(value)
			Library.InfoLoggerFrame.Visible = value
		end,
	})

	showLoggerToggle:AddKeyPicker(
		"ShowLoggerWindowKeyBind",
		{ Default = "N/A", SyncToggleState = true, Text = "Logger Window" }
	)

	groupbox:AddSlider("MinimumLoggerDistance", {
		Text = "Minimum Logger Distance",
		Min = 0,
		Max = 100,
		Rounding = 0,
		Suffix = "m",
		Default = 0,
	})

	groupbox:AddSlider("MaximumLoggerDistance", {
		Text = "Maximum Logger Distance",
		Min = 0,
		Max = 1000,
		Rounding = 0,
		Suffix = "m",
		Default = 0,
	})

	local blacklistedKeys = groupbox:AddDropdown("BlacklistedKeys", {
		Text = "Blacklisted Keys",
		Default = {},
		Values = Library:KeyBlacklists(),
		Multi = true,
	})

	groupbox:AddButton("Remove Selected Keys", function()
		for selected, _ in next, blacklistedKeys.Value do
			Library.InfoLoggerData.KeyBlacklistList[selected] = nil
		end

		blacklistedKeys:SetValues(Library:KeyBlacklists())
		blacklistedKeys:SetValue({})
		blacklistedKeys:Display()
	end)
end

---Initialize animation capture section.
---@param groupbox table
function BuilderTab.initCaptureSection(groupbox)
	groupbox:AddToggle("EnableAnimationCapture", {
		Text = "Enable Animation Capture",
		Default = false,
		Tooltip = "When enabled, animations played by nearby entities are captured for timing generation.",
	})

	groupbox:AddSlider("CaptureMinDistance", {
		Text = "Capture Min Distance",
		Min = 0,
		Max = 200,
		Rounding = 0,
		Suffix = "m",
		Default = 0,
	})

	groupbox:AddSlider("CaptureMaxDistance", {
		Text = "Capture Max Distance",
		Min = 0,
		Max = 1000,
		Rounding = 0,
		Suffix = "m",
		Default = 100,
	})

	local capturedList = groupbox:AddDropdown("CapturedAnimationList", {
		Text = "Captured Animations",
		Values = {},
		AllowNull = true,
		Callback = function(value)
			if not value then
				return
			end

			local aid = value:match("%((.+)%)$")
			if not aid then
				return
			end

			AnimationVisualizer.loadId(aid)
		end,
	})

	local timingNameInput = groupbox:AddInput("GeneratedTimingName", {
		Text = "Timing Name (optional)",
		Tooltip = "Leave empty to auto-generate a name from entity + animation ID.",
	})

	local autoSaveConfigInput = groupbox:AddInput("GeneratedTimingAutoSaveConfigName", {
		Text = "Auto Save Config Name",
		Tooltip = "Optional: if set, generated timings are immediately written to this config file.",
		Placeholder = "example: rogue_autogen",
	})

	local function autoSaveGeneratedTimings()
		local configName = autoSaveConfigInput and autoSaveConfigInput.Value
		if not configName or #configName <= 0 then
			return
		end

		local code = SaveManager.write(configName)
		if code == 0 then
			Library:Notify(string.format("Auto-saved timings to '%s'.", configName))
		else
			Library:Notify(string.format("Failed to auto-save timings to '%s'.", configName))
		end
	end

	groupbox:AddButton("Refresh Captured List", function()
		capturedList:SetValues(AnimationLogger.capturedList())
		capturedList:SetValue(nil)
		capturedList:Display()
	end)

	groupbox:AddButton("Generate Timing From Selected", function()
		local selected = capturedList.Value
		if not selected then
			return Library:Notify("Select a captured animation first.")
		end

		-- Extract the animation ID from the display string "EntityName (rbxassetid://123)".
		local aid = selected:match("%((.+)%)$")
		if not aid then
			return Library:Notify("Could not parse animation ID from selection.")
		end

		local name = timingNameInput and timingNameInput.Value or nil
		local success, result = AnimationLogger.generateTiming(aid, name)

		if success then
			Library:Notify(string.format("Created timing '%s'.", result))
			autoSaveGeneratedTimings()
			BuilderTab.refresh()
		else
			Library:Notify(result)
		end
	end)

	groupbox
		:AddButton({
			Text = "Generate All Captured",
			DoubleClick = true,
			Func = function()
				local s, f = AnimationLogger.generateAll()
				Library:Notify(string.format("Generated %d timings (%d skipped/failed).", s, f))

				if s > 0 then
					autoSaveGeneratedTimings()
				end

				BuilderTab.refresh()
			end,
		})
		:AddButton({
			Text = "Clear Captured",
			DoubleClick = true,
			Func = function()
				AnimationLogger.clearCaptured()
				capturedList:SetValues({})
				capturedList:SetValue(nil)
				capturedList:Display()
				Library:Notify("Cleared all captured animations.")
			end,
		})
end

---Initialize timing harvester section.
---@param groupbox table
function BuilderTab.initHarvesterSection(groupbox)
	groupbox:AddToggle("EnableTimingHarvester", {
		Text = "Enable Timing Harvester",
		Default = false,
		Tooltip = "Records every parry press + outcome + damage hit. Solves Perfect Parry / Parry windows per animation.",
	})

	local statusLabel = groupbox:AddLabel("Samples: 0 aids / 0 total")

	local harvestedList = groupbox:AddDropdown("HarvestedAnimationList", {
		Text = "Harvested Animations",
		Values = {},
		AllowNull = true,
	})

	local harvestedNameInput = groupbox:AddInput("HarvestedTimingName", {
		Text = "Timing Name (optional)",
		Tooltip = "Leave empty to auto-generate '<EntityName>_<id>_Harvested'.",
	})

	local harvestedAutoSaveInput = groupbox:AddInput("HarvestedAutoSaveConfigName", {
		Text = "Auto Save Config Name",
		Tooltip = "Optional: if set, promoted timings are immediately written to this config file.",
		Placeholder = "example: mashle_autogen",
	})

	local function autoSaveHarvested()
		local configName = harvestedAutoSaveInput and harvestedAutoSaveInput.Value
		if not configName or #configName <= 0 then
			return
		end

		local code = SaveManager.write(configName)
		if code == 0 then
			Library:Notify(string.format("Auto-saved harvested timings to '%s'.", configName))
		else
			Library:Notify(string.format("Failed to auto-save harvested timings to '%s'.", configName))
		end
	end

	local function refreshStatus()
		local aidCount, total = TimingHarvester.counts()
		statusLabel:SetText(string.format("Samples: %d aids / %d total", aidCount, total))
	end

	groupbox:AddButton("Refresh Harvested List", function()
		harvestedList:SetValues(TimingHarvester.list())
		harvestedList:SetValue(nil)
		harvestedList:Display()
		refreshStatus()
	end)

	groupbox:AddButton("Dump Samples To Logger", function()
		TimingHarvester.dump()
		refreshStatus()
	end)

	groupbox:AddButton("Promote Selected To Config", function()
		local selected = harvestedList.Value
		if not selected then
			return Library:Notify("Select a harvested animation first.")
		end

		local aid = TimingHarvester.aidFromLabel(selected)
		if not aid then
			return Library:Notify("Could not parse animation ID from selection.")
		end

		local name = harvestedNameInput and harvestedNameInput.Value or nil
		local ok, result = TimingHarvester.promoteToConfig(aid, name)

		if ok then
			Library:Notify(string.format("Created timing '%s'.", result))
			autoSaveHarvested()
			BuilderTab.refresh()
		else
			Library:Notify(result)
		end
	end)

	groupbox
		:AddButton({
			Text = "Promote All Harvested",
			DoubleClick = true,
			Func = function()
				local s, f = TimingHarvester.promoteAll()
				Library:Notify(string.format("Promoted %d timings (%d skipped/failed).", s, f))

				if s > 0 then
					autoSaveHarvested()
				end

				BuilderTab.refresh()
			end,
		})
		:AddButton({
			Text = "Clear Harvested Samples",
			DoubleClick = true,
			Func = function()
				TimingHarvester.clear()
				harvestedList:SetValues({})
				harvestedList:SetValue(nil)
				harvestedList:Display()
				refreshStatus()
				Library:Notify("Cleared all harvested samples.")
			end,
		})
end

---Initialize Module Manager section.
---@param groupbox table
function BuilderTab.initModuleManagerSection(groupbox)
	local moduleList = groupbox:AddDropdown("ModuleList", {
		Text = "Module List",
		Values = ModuleManager.loaded(),
		AllowNull = true,
		Multi = false,
	})

	groupbox:AddButton("Refresh List", function()
		-- Refresh manager.
		ModuleManager.refresh()

		-- Set loaded modules.
		moduleList:SetValues(ModuleManager.loaded())
		moduleList:SetValue(nil)
		moduleList:Display()
	end)
end

---Initialize tab.
---@param window table
function BuilderTab.init(window)
	-- Create tab.
	local tab = window:AddTab("Builder")

	-- Initialize sections.
	BuilderTab.initSaveManagerSection(tab:AddDynamicGroupbox("Save Manager"))
	BuilderTab.initMergeManagerSection(tab:AddDynamicGroupbox("Merge Manager"))
	BuilderTab.initModuleManagerSection(tab:AddDynamicGroupbox("Module Manager"))
	BuilderTab.initLoggerSection(tab:AddDynamicGroupbox("Logger"))
	BuilderTab.initCaptureSection(tab:AddDynamicGroupbox("Animation Capture"))
	BuilderTab.initHarvesterSection(tab:AddDynamicGroupbox("Timing Harvester"))

	-- Create builder sections.
	BuilderTab.pbs = PartBuilderSection.new("Part", tab:AddDynamicTabbox(), SaveManager.ps, PartTiming.new())
	BuilderTab.abs =
		AnimationBuilderSection.new("Animation", tab:AddDynamicTabbox(), SaveManager.as, AnimationTiming.new())
	BuilderTab.sbs = SoundBuilderSection.new("Sound", tab:AddDynamicTabbox(), SaveManager.ss, SoundTiming.new())

	-- Initialize builder sections.
	BuilderTab.pbs:init()
	BuilderTab.abs:init()
	BuilderTab.sbs:init()
end

-- Return CombatTab module.
return BuilderTab
