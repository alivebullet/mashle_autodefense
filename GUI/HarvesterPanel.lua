return LPH_NO_VIRTUALIZE(function()
	-- Standalone Timing Harvester UI panel.
	-- Opens as a separate draggable window, showing all harvested combat animations,
	-- solve results, and action buttons (promote, visualize, debug log, etc.).
	local HarvesterPanel = {}

	---@module Features.Combat.TimingHarvester
	local TimingHarvester = require("Features/Combat/TimingHarvester")

	---@module Features.Game.AnimationVisualizer
	local AnimationVisualizer = require("Features/Game/AnimationVisualizer")

	---@module Features.Game.AnimationLogger
	local AnimationLogger = require("Features/Game/AnimationLogger")

	---@module Features.Combat.Objects.Defender
	local Defender = require("Features/Combat/Objects/Defender")

	---@module Utility.CoreGuiManager
	local CoreGuiManager = require("Utility/CoreGuiManager")

	---@module GUI.Library
	local Library = require("GUI/Library")

	---@module Utility.Logger
	local Logger = require("Utility/Logger")

	-- Constants.
	local FONT = Font.new("rbxasset://fonts/families/RobotoMono.json")
	local ENTRY_HEIGHT = 40
	local PANEL_W = 400
	local PANEL_H = 520

	-- State.
	local isInitialized = false
	local selectedAid = nil
	local entryFrames = {}
	local viewMode = "observed"

	-- ScreenGui.
	local screenGui = CoreGuiManager.imark(Instance.new("ScreenGui"))
	screenGui.Name = "HarvesterPanel"
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 2
	screenGui.Enabled = false

	-- Outer border.
	local outer = Instance.new("Frame")
	outer.Name = "HarvesterOuter"
	outer.BackgroundColor3 = Color3.new(1, 1, 1)
	outer.Position = UDim2.new(0.28, 0, 0.1, 0)
	outer.BorderColor3 = Color3.new()
	outer.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	outer.ZIndex = 100
	outer.Parent = screenGui

	-- Inner.
	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.BackgroundColor3 = Library.MainColor
	inner.BorderMode = Enum.BorderMode.Inset
	inner.BorderColor3 = Library.OutlineColor
	inner.Size = UDim2.new(1, 0, 1, 0)
	inner.Parent = outer

	-- Title.
	local titleLabel = Instance.new("TextLabel")
	titleLabel.FontFace = FONT
	titleLabel.TextColor3 = Library.AccentColor
	titleLabel.Text = "Timing Harvester"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.new(0, 8, 0, 5)
	titleLabel.Size = UDim2.new(1, -40, 0, 20)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextSize = 17
	titleLabel.Parent = inner

	-- Close button.
	local closeBtn = Instance.new("TextButton")
	closeBtn.FontFace = FONT
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
	closeBtn.BorderSizePixel = 0
	closeBtn.Position = UDim2.new(1, -26, 0, 5)
	closeBtn.Size = UDim2.new(0, 20, 0, 18)
	closeBtn.TextSize = 13
	closeBtn.Parent = inner

	-- Status.
	local statusLabel = Instance.new("TextLabel")
	statusLabel.FontFace = FONT
	statusLabel.TextColor3 = Library.FontColor
	statusLabel.Text = "0 animations / 0 samples"
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.new(0, 8, 0, 27)
	statusLabel.Size = UDim2.new(1, -16, 0, 14)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextSize = 12
	statusLabel.Parent = inner

	-- Separator.
	local sep = Instance.new("Frame")
	sep.BackgroundColor3 = Library.AccentColor
	sep.BorderSizePixel = 0
	sep.Position = UDim2.new(0, 4, 0, 44)
	sep.Size = UDim2.new(1, -8, 0, 1)
	sep.Parent = inner

	-- Scroll frame.
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
	scrollFrame.BorderColor3 = Library.OutlineColor
	scrollFrame.Position = UDim2.new(0, 4, 0, 48)
	scrollFrame.Size = UDim2.new(1, -8, 1, -156)
	scrollFrame.ScrollBarThickness = 5
	scrollFrame.ScrollBarImageColor3 = Library.AccentColor
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.Parent = inner

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.Name
	listLayout.Padding = UDim.new(0, 2)
	listLayout.Parent = scrollFrame

	-- Auto-size canvas from layout.
	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 4)
	end)

	-- Padding.
	local scrollPadding = Instance.new("UIPadding")
	scrollPadding.PaddingTop = UDim.new(0, 2)
	scrollPadding.PaddingLeft = UDim.new(0, 2)
	scrollPadding.PaddingRight = UDim.new(0, 2)
	scrollPadding.Parent = scrollFrame

	-- Button container.
	local btnArea = Instance.new("Frame")
	btnArea.BackgroundTransparency = 1
	btnArea.Position = UDim2.new(0, 4, 1, -104)
	btnArea.Size = UDim2.new(1, -8, 0, 100)
	btnArea.Parent = inner

	---Create a styled button.
	---@param text string
	---@param pos UDim2
	---@param size UDim2
	---@return TextButton
	local function makeBtn(text, pos, size)
		local btn = Instance.new("TextButton")
		btn.FontFace = FONT
		btn.Text = text
		btn.TextColor3 = Library.FontColor
		btn.BackgroundColor3 = Library.MainColor
		btn.BorderColor3 = Color3.new()
		btn.Position = pos
		btn.Size = size
		btn.TextSize = 12
		btn.AutoButtonColor = true
		btn.Parent = btnArea
		return btn
	end

	-- Row 1.
	local btnRefresh = makeBtn("Refresh", UDim2.new(0, 0, 0, 0), UDim2.new(0.25, -2, 0, 28))
	local btnPromSel = makeBtn("Promote Sel", UDim2.new(0.25, 1, 0, 0), UDim2.new(0.25, -2, 0, 28))
	local btnPromAll = makeBtn("Promote All", UDim2.new(0.5, 1, 0, 0), UDim2.new(0.25, -2, 0, 28))
	local btnVisualize = makeBtn("Visualize", UDim2.new(0.75, 1, 0, 0), UDim2.new(0.25, -1, 0, 28))

	-- Row 2.
	local btnBanSel = makeBtn("Ban Sel", UDim2.new(0, 0, 0, 34), UDim2.new(0.25, -2, 0, 28))
	local btnUnbanSel = makeBtn("Unban Sel", UDim2.new(0.25, 1, 0, 34), UDim2.new(0.25, -2, 0, 28))
	local btnToggleView = makeBtn("View Banned", UDim2.new(0.5, 1, 0, 34), UDim2.new(0.25, -2, 0, 28))
	local btnDumpBanned = makeBtn("Dump Banned", UDim2.new(0.75, 1, 0, 34), UDim2.new(0.25, -1, 0, 28))

	-- Row 3.
	local btnClear = makeBtn("Clear Samples", UDim2.new(0, 0, 0, 68), UDim2.new(0.25, -2, 0, 28))
	local btnCopyDbg = makeBtn("Copy Debug", UDim2.new(0.25, 1, 0, 68), UDim2.new(0.25, -2, 0, 28))
	local btnDump = makeBtn("Dump Log", UDim2.new(0.5, 1, 0, 68), UDim2.new(0.25, -2, 0, 28))
	local btnClrDbg = makeBtn("Clr Debug", UDim2.new(0.75, 1, 0, 68), UDim2.new(0.25, -1, 0, 28))

	local function updateModeButtons()
		if viewMode == "banned" then
			btnToggleView.Text = "View Seen"
			btnClear.Text = "Clr Banned"
		else
			btnToggleView.Text = "View Banned"
			btnClear.Text = "Clear Samples"
		end
	end

	---Clear all entry frames from the scroll list.
	local function clearEntries()
		for _, e in next, entryFrames do
			e:Destroy()
		end
		entryFrames = {}
	end

	---Auto-save promoted timings to the config name set in the Linoria input.
	local function autoSave()
		local input = Options and Options["HarvestedAutoSaveConfigName"]
		local configName = input and input.Value
		if not configName or #configName <= 0 then
			return
		end

		local SaveManager = require("Game/Timings/SaveManager")
		local code = SaveManager.write(configName)
		if code == 0 then
			Logger.notify("Auto-saved to '%s'.", configName)
		end
	end

	---Create an entry frame for an observed or banned animation.
	---@param index number
	---@param aid string
	---@param data table
	---@param solved table?
	---@param banned boolean?
	local function createEntry(index, aid, data, solved, banned)
		local frame = Instance.new("TextButton")
		frame.Name = string.format("%04d", index)
		frame.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
		frame.BorderSizePixel = 0
		frame.Size = UDim2.new(1, -4, 0, ENTRY_HEIGHT)
		frame.AutoButtonColor = false
		frame.Text = ""
		frame.Parent = scrollFrame

		-- Line 1: [Priority] EntityName  rbxassetid://...
		local priStr = banned and "BANNED" or (data.meta.priority or "?")
		local shortAid = aid:match("(%d+)$") or aid
		local l1 = Instance.new("TextLabel")
		l1.FontFace = FONT
		l1.TextColor3 = Library.FontColor
		l1.Text = string.format("[%s] %s  rbxassetid://%s", priStr, data.meta.entityName or "?", shortAid)
		l1.BackgroundTransparency = 1
		l1.Position = UDim2.new(0, 4, 0, 2)
		l1.Size = UDim2.new(1, -8, 0, 16)
		l1.TextXAlignment = Enum.TextXAlignment.Left
		l1.TextSize = 11
		l1.TextTruncate = Enum.TextTruncate.AtEnd
		l1.Parent = frame

		-- Line 2: sample stats + solve result.
		local statsText
		if banned then
			statsText = string.format(
				"seen=%d | samples=%d | blocked from logger + harvester",
				data.seenCount or 0,
				data.sampleCount or 0
			)
		elseif solved and solved.bestWhen then
			statsText = string.format(
				"seen=%d | n=%d  P=%d p=%d f=%d h=%d | when=%dms | conf=%.0f%%",
				data.seenCount or 0,
				solved.sampleCount,
				solved.perfectCount,
				solved.parryCount,
				solved.failCount,
				solved.hitCount,
				math.round(solved.bestWhen * 1000),
				(solved.confidence or 0) * 100
			)
		else
			statsText = string.format(
				"seen=%d | n=%d | no-solve",
				data.seenCount or 0,
				solved and solved.sampleCount or 0
			)
		end

		local l2 = Instance.new("TextLabel")
		l2.FontFace = FONT
		l2.TextColor3 = Color3.fromRGB(160, 160, 160)
		l2.Text = statsText
		l2.BackgroundTransparency = 1
		l2.Position = UDim2.new(0, 4, 0, 20)
		l2.Size = UDim2.new(1, -8, 0, 16)
		l2.TextXAlignment = Enum.TextXAlignment.Left
		l2.TextSize = 11
		l2.Parent = frame

		-- Left-click to select.
		frame.MouseButton1Click:Connect(function()
			selectedAid = aid
			for _, e in next, entryFrames do
				e.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
				e.BackgroundTransparency = 0
			end
			frame.BackgroundColor3 = Library.AccentColor
			frame.BackgroundTransparency = 0.65
		end)

		-- Right-click to open in visualizer.
		frame.MouseButton2Click:Connect(function()
			AnimationVisualizer.loadId(aid)
		end)

		table.insert(entryFrames, frame)
	end

	---Refresh the panel with current harvester data.
	function HarvesterPanel.refresh()
		clearEntries()
		selectedAid = nil
		updateModeButtons()

		if viewMode == "banned" then
			local banned = TimingHarvester.getBanned()
			local sorted = {}
			local bannedCount = 0

			for aid, data in next, banned do
				bannedCount = bannedCount + 1
				table.insert(sorted, { aid = aid, data = data })
			end

			statusLabel.Text = string.format("%d banned animation%s", bannedCount, bannedCount == 1 and "" or "s")

			table.sort(sorted, function(a, b)
				return (a.data.meta.bannedAt or 0) > (b.data.meta.bannedAt or 0)
			end)

			for i, entry in ipairs(sorted) do
				createEntry(i, entry.aid, entry.data, nil, true)
			end
			return
		end

		local observed = TimingHarvester.getObserved()
		local aidCount, totalSamples = TimingHarvester.counts()
		local observedCount, bannedCount = 0, 0
		local sorted = {}

		for aid, data in next, observed do
			observedCount = observedCount + 1
			table.insert(sorted, { aid = aid, data = data })
		end

		for _ in next, TimingHarvester.getBanned() do
			bannedCount = bannedCount + 1
		end

		statusLabel.Text = string.format(
			"%d seen / %d sampled / %d banned",
			observedCount,
			aidCount,
			bannedCount
		)

		table.sort(sorted, function(a, b)
			return (a.data.meta.lastSeenAt or 0) > (b.data.meta.lastSeenAt or 0)
		end)

		for i, entry in ipairs(sorted) do
			local solved = TimingHarvester.solve(entry.aid)
			createEntry(i, entry.aid, entry.data, solved, false)
		end
	end

	---Show or hide the panel.
	---@param state boolean
	function HarvesterPanel.visible(state)
		if state and not isInitialized then
			HarvesterPanel.init()
		end
		screenGui.Enabled = state
		if state then
			HarvesterPanel.refresh()
		end
	end

	---Toggle panel visibility.
	function HarvesterPanel.toggle()
		HarvesterPanel.visible(not screenGui.Enabled)
	end

	---Initialize panel (lazy, called on first show).
	function HarvesterPanel.init()
		if isInitialized then
			return
		end
		isInitialized = true

		Library:MakeDraggable(outer)

		Library:AddToRegistry(inner, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "OutlineColor",
		}, true)

		Library:AddToRegistry(titleLabel, {
			TextColor3 = "AccentColor",
		}, true)

		Library:AddToRegistry(statusLabel, {
			TextColor3 = "FontColor",
		}, true)

		Library:AddToRegistry(sep, {
			BackgroundColor3 = "AccentColor",
		}, true)

		Library:AddToRegistry(scrollFrame, {
			BorderColor3 = "OutlineColor",
			ScrollBarImageColor3 = "AccentColor",
		}, true)

		for _, btn in next, {
			btnRefresh, btnPromSel, btnPromAll, btnVisualize,
			btnBanSel, btnUnbanSel, btnToggleView, btnDumpBanned,
			btnClear, btnCopyDbg, btnDump, btnClrDbg,
		} do
			Library:AddToRegistry(btn, {
				BackgroundColor3 = "MainColor",
				TextColor3 = "FontColor",
			}, true)
		end

		-- Close.
		closeBtn.MouseButton1Click:Connect(function()
			HarvesterPanel.visible(false)
		end)

		-- Refresh.
		btnRefresh.MouseButton1Click:Connect(function()
			HarvesterPanel.refresh()
		end)

		-- Promote selected.
		btnPromSel.MouseButton1Click:Connect(function()
			if viewMode ~= "observed" then
				return Logger.notify("Switch back to the seen list to promote animations.")
			end

			if not selectedAid then
				return Logger.notify("Select an animation first.")
			end
			local ok, result = TimingHarvester.promoteToConfig(selectedAid)
			if ok then
				Logger.notify("Promoted '%s'.", result)
				autoSave()
				HarvesterPanel.refresh()
			else
				Logger.notify(result)
			end
		end)

		-- Promote all.
		btnPromAll.MouseButton1Click:Connect(function()
			if viewMode ~= "observed" then
				return Logger.notify("Switch back to the seen list to promote animations.")
			end

			local s, f = TimingHarvester.promoteAll()
			Logger.notify("Promoted %d (%d skipped).", s, f)
			if s > 0 then
				autoSave()
			end
			HarvesterPanel.refresh()
		end)

		-- Visualize selected.
		btnVisualize.MouseButton1Click:Connect(function()
			if selectedAid then
				AnimationVisualizer.loadId(selectedAid)
			else
				Logger.notify("Select an animation first.")
			end
		end)

		-- Ban selected seen animation.
		btnBanSel.MouseButton1Click:Connect(function()
			if viewMode ~= "observed" then
				return Logger.notify("Switch to the seen list to ban an animation.")
			end

			if not selectedAid then
				return Logger.notify("Select an animation first.")
			end

			local ok, result = TimingHarvester.ban(selectedAid)
			if ok then
				AnimationLogger.removeCaptured(selectedAid)
				HarvesterPanel.refresh()
			else
				Logger.notify(result)
			end
		end)

		-- Unban selected animation.
		btnUnbanSel.MouseButton1Click:Connect(function()
			if viewMode ~= "banned" then
				return Logger.notify("Switch to the banned list to unban an animation.")
			end

			if not selectedAid then
				return Logger.notify("Select a banned animation first.")
			end

			local ok, result = TimingHarvester.unban(selectedAid)
			if ok then
				HarvesterPanel.refresh()
			else
				Logger.notify(result)
			end
		end)

		-- Toggle between seen and banned animation views.
		btnToggleView.MouseButton1Click:Connect(function()
			viewMode = viewMode == "observed" and "banned" or "observed"
			HarvesterPanel.refresh()
		end)

		-- Dump banned list.
		btnDumpBanned.MouseButton1Click:Connect(function()
			TimingHarvester.dumpBanned()
		end)

		-- Clear all samples.
		btnClear.MouseButton1Click:Connect(function()
			if viewMode == "banned" then
				TimingHarvester.clearBanned()
			else
				TimingHarvester.clear()
			end

			selectedAid = nil
			HarvesterPanel.refresh()
		end)

		-- Copy defense debug log to clipboard.
		btnCopyDbg.MouseButton1Click:Connect(function()
			local log = Defender.getDebugLog()
			if #log == 0 then
				return Logger.notify("Debug log empty.")
			end
			if setclipboard then
				setclipboard(log)
				Logger.notify("Copied %d debug lines.", #Defender._debugLog)
			else
				Logger.notify("setclipboard not available.")
			end
		end)

		-- Dump harvester summary to logger.
		btnDump.MouseButton1Click:Connect(function()
			TimingHarvester.dump()
		end)

		-- Clear defense debug log.
		btnClrDbg.MouseButton1Click:Connect(function()
			Defender.clearDebugLog()
			Logger.notify("Debug log cleared.")
		end)
	end

	---Detach panel.
	function HarvesterPanel.detach()
		screenGui.Enabled = false
		clearEntries()
		isInitialized = false
	end

	return HarvesterPanel
end)()
