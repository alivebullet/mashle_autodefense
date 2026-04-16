-- AutomationTab module.
local AutomationTab = {}

---Initialize 'Input Automation' section.
---@param groupbox table
function AutomationTab.initInputAutomation(groupbox)
	groupbox:AddToggle("AntiAFK", {
		Text = "Anti AFK",
		Tooltip = "Prevent the player from being kicked for being idle by sending periodic inputs for you.",
		Default = false,
	})

	groupbox:AddToggle("AutoAcceptRaid", {
		Text = "Auto Accept Raid",
		Tooltip = "Automatically accept raid prompts.",
		Default = false,
	})
end

---Initialize tab.
---@param window table
function AutomationTab.init(window)
	-- Create tab.
	local tab = window:AddTab("Auto")

	-- Initialize sections.
	AutomationTab.initInputAutomation(tab:AddDynamicGroupbox("Input Automation"))
end

-- Return AutomationTab module.
return AutomationTab
