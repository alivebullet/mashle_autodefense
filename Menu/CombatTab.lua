-- CombatTab module.
local CombatTab = {}

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Features.Combat.Defense
local Defense = require("Features/Combat/Defense")

-- Initialize combat targeting section.
---@param tab table
function CombatTab.initCombatTargetingSection(tab)
	tab:AddDropdown("PlayerSelectionType", {
		Text = "Player Selection Type",
		Values = {
			"Closest In Distance",
			"Closest To Crosshair",
			"Least Health",
		},
		Default = 1,
	})

	tab:AddSlider("FOVLimit", {
		Text = "Player FOV Limit",
		Min = 0,
		Max = 180,
		Default = 180,
		Suffix = "°",
		Rounding = 0,
	})

	tab:AddSlider("DistanceLimit", {
		Text = "Distance Limit",
		Min = 0,
		Max = 10000,
		Default = 3000,
		Suffix = "s",
		Rounding = 0,
	})

	tab:AddSlider("MaxTargets", {
		Text = "Max Targets",
		Min = 1,
		Max = 64,
		Default = 4,
		Rounding = 0,
	})

	tab:AddToggle("IgnorePlayers", {
		Text = "Ignore Players",
		Default = false,
	})

	tab:AddToggle("IgnoreMobs", {
		Text = "Ignore Mobs",
		Default = false,
	})

	tab:AddToggle("IgnoreAllies", {
		Text = "Ignore Allies",
		Default = false,
	})
end

-- Initialize combat whitelist section.
---@param tab table
function CombatTab.initCombatWhitelistSection(tab)
	local usernameList = tab:AddDropdown("UsernameList", {
		Text = "Username List",
		Values = {},
		SaveValues = true,
		Multi = true,
		AllowNull = true,
	})

	local usernameInput = tab:AddInput("UsernameInput", {
		Text = "Username Input",
		Placeholder = "Display name or username.",
	})

	tab:AddButton("Add Username To Whitelist", function()
		local username = usernameInput.Value
		if #username <= 0 then
			return Logger.longNotify("Please enter a valid username.")
		end

		local values = usernameList.Values
		if not table.find(values, username) then
			table.insert(values, username)
		end

		usernameList:SetValues(values)
		usernameList:SetValue({})
		usernameList:Display()
	end)

	tab:AddButton("Remove Selected Usernames", function()
		local values = usernameList.Values
		local value = usernameList.Value

		for selected, _ in next, value do
			local index = table.find(values, selected)
			if not index then
				continue
			end

			table.remove(values, index)
		end

		usernameList:SetValues(values)
		usernameList:SetValue({})
		usernameList:Display()
	end)
end

-- Initialize auto defense section.
---@param groupbox table
function CombatTab.initAutoDefenseSection(groupbox)
	local autoDefenseToggle = groupbox:AddToggle("EnableAutoDefense", {
		Text = "Enable Auto Defense",
		Default = false,
	})

	autoDefenseToggle:AddKeyPicker(
		"EnableAutoDefenseKeybind",
		{ Default = "N/A", SyncToggleState = true, Text = "Auto Defense" }
	)

	local autoDefenseDepBox = groupbox:AddDependencyBox()

	autoDefenseDepBox:AddToggle("EnableNotifications", {
		Text = "Enable Notifications",
		Default = false,
	})

	autoDefenseDepBox:AddToggle("EnableVisualizations", {
		Text = "Enable Visualizations",
		Default = false,
		Callback = Defense.visualizations,
	})

	autoDefenseDepBox:AddToggle("DashOnParryCooldown", {
		Text = "Dash On Parry Cooldown",
		Default = false,
		Tooltip = "If enabled, the auto defense will fallback to a dash if the parry action is not available.",
	})

	autoDefenseDepBox:AddToggle("DeflectBlockFallback", {
		Text = "Deflect Block Fallback",
		Default = false,
		Tooltip = "If enabled, the auto defense will fallback to block frames if parry action and/or fallback is not available.",
	})

	local afToggle = autoDefenseDepBox:AddToggle("AllowFailure", {
		Text = "Allow Failure",
		Default = false,
		Tooltip = "If enabled, the auto defense will sometimes intentionally fail to parry/deflect.",
	})

	local afDepBox = autoDefenseDepBox:AddDependencyBox()

	afDepBox:AddSlider("FailureRate", {
		Text = "Failure Rate",
		Min = 0,
		Max = 100,
		Default = 0,
		Suffix = "%",
		Rounding = 2,
	})

	afDepBox:AddSlider("DashInsteadOfParryRate", {
		Text = "Dash Instead Of Parry Rate",
		Min = 0,
		Max = 100,
		Default = 0,
		Suffix = "%",
		Rounding = 2,
	})

	afDepBox:AddSlider("FakeMistimeRate", {
		Text = "Fake Parry Mistime Rate",
		Min = 0,
		Max = 100,
		Default = 0,
		Suffix = "%",
		Rounding = 2,
	})

	afDepBox:AddSlider("IgnoreAnimationEndRate", {
		Text = "Ignore Animation End Rate",
		Min = 0,
		Max = 100,
		Default = 0,
		Suffix = "%",
		Rounding = 2,
	})

	afDepBox:SetupDependencies({
		{ afToggle, true },
	})

	autoDefenseDepBox:AddDropdown("AutoDefenseFilters", {
		Text = "Auto Defense Filters",
		Values = {
			"Filter Out M1s",
			"Filter Out Mantras",
			"Filter Out Criticals",
			"Filter Out Undefined",
			"Disable When Textbox Focused",
			"Disable When Window Not Active",
			"Disable When Holding Block",
			"Disable When In Dash",
			"Disable When Knocked Recently",
		},
		Multi = true,
		AllowNull = true,
		Default = {},
	})

	autoDefenseDepBox:AddDropdown("DefaultDashDirection", {
		Text = "Default Dash Direction",
		Values = { "W", "A", "S", "D", "Random" },
		Tooltip = "The default direction to dash when you are not holding any movement keys.",
		Default = 3,
	})

	autoDefenseDepBox:AddSlider("DeflectHoldTime", {
		Text = "Deflect Hold Time",
		Min = 0,
		Max = 500,
		Default = 0,
		Suffix = "ms",
		Rounding = 1,
	})

	autoDefenseDepBox:SetupDependencies({
		{ autoDefenseToggle, true },
	})
end

---Initialize combat assistance section.
---@param groupbox table
function CombatTab.initCombatAssistance(groupbox)
	local alToggle = groupbox:AddToggle("AimLock", {
		Text = "Aim Lock",
		Default = false,
		Tooltip = "Automatically lock on to the best target.",
	})

	alToggle:AddKeyPicker("AimLockKeybind", { Default = "N/A", SyncToggleState = true, Text = "Aim Lock" })

	local alDepBox = groupbox:AddDependencyBox()

	local lsToggle = alDepBox:AddToggle("Smoothing", {
		Text = "Smoothing",
		Default = false,
		Tooltip = "Should we attempt to smooth the aim lock movement?",
	})

	local lsDepBox = alDepBox:AddDependencyBox()

	lsDepBox:AddSlider("SmoothingFactor", {
		Text = "Smoothing Factor",
		Min = 0.0,
		Max = 1.0,
		Default = 0.1,
		Rounding = 3,
	})

	local styles = {}

	for _, style in next, Enum.EasingStyle:GetEnumItems() do
		table.insert(styles, style.Name)
	end

	lsDepBox:AddDropdown("SmoothingStyle", { Text = "Smoothing Style", Default = 0, Values = styles })

	local direction = {}

	for _, dir in next, Enum.EasingDirection:GetEnumItems() do
		table.insert(direction, dir.Name)
	end

	lsDepBox:AddDropdown("SmoothingDirection", { Text = "Smoothing Direction", Default = 0, Values = direction })

	alDepBox:AddToggle("ForceAutoRotate", {
		Text = "Force Auto Rotate",
		Default = false,
		Tooltip = "Use this if your aim-lock is not rotating your character. This is an un-fixable issue for now.",
	})

	alDepBox:AddToggle("StickyTargets", {
		Text = "Sticky Targets",
		Default = false,
		Tooltip = "Should we attempt to stick to targets as long as the lock is active?",
	})

	alDepBox:AddToggle("VerticalInfluence", {
		Text = "Vertical Influence",
		Default = false,
		Tooltip = "Should we attempt to lock on vertically or just face them on the horizontal plane?",
	})

	alDepBox:SetupDependencies({
		{ alToggle, true },
	})

	lsDepBox:SetupDependencies({
		{ lsToggle, true },
	})
end

---Initialize tab.
---@param window table
function CombatTab.init(window)
	-- Create tab.
	local tab = window:AddTab("Combat")

	-- Initialize sections.
	CombatTab.initAutoDefenseSection(tab:AddDynamicGroupbox("Auto Defense"))
	CombatTab.initCombatAssistance(tab:AddLeftGroupbox("Combat Assistance"))

	-- Create targeting section tab box.
	local tabbox = tab:AddRightTabbox()
	CombatTab.initCombatTargetingSection(tabbox:AddTab("Targeting"))
	CombatTab.initCombatWhitelistSection(tabbox:AddTab("Whitelisting"))
end

-- Return CombatTab module.
return CombatTab
