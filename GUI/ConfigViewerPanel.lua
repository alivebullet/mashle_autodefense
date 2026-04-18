return LPH_NO_VIRTUALIZE(function()
	local ConfigViewerPanel = {}

	---@module Utility.Maid
	local Maid = require("Utility/Maid")

	---@module GUI.Library
	local Library = require("GUI/Library")

	---@module Utility.CoreGuiManager
	local CoreGuiManager = require("Utility/CoreGuiManager")

	---@module Utility.Logger
	local Logger = require("Utility/Logger")

	---@module Game.Timings.SaveManager
	local SaveManager = require("Game/Timings/SaveManager")

	---@module Features.Combat.TimingHarvester
	local TimingHarvester = require("Features/Combat/TimingHarvester")

	---@module Features.Game.AnimationLogger
	local AnimationLogger = require("Features/Game/AnimationLogger")

	---@module Features.Game.AnimationVisualizer
	local AnimationVisualizer = require("Features/Game/AnimationVisualizer")

	local FONT = Font.new("rbxasset://fonts/families/RobotoMono.json")
	local TITLE_FONT = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold)
	local PANEL_W = 1140
	local PANEL_H = 808
	local NPC_ENTRY_H = 74
	local ANIM_ENTRY_H = 58
	local ACTION_ENTRY_H = 30
	local BANNED_ENTRY_H = 26
	local ACTION_TYPES = { "Parry", "Dash", "Start Block", "End Block" }
	local TAGS = { "Undefined", "Critical", "Mantra", "M1" }
	local ACTION_COLORS = {
		Parry = Color3.fromRGB(74, 194, 116),
		Dash = Color3.fromRGB(231, 168, 68),
		["Start Block"] = Color3.fromRGB(78, 155, 255),
		["End Block"] = Color3.fromRGB(169, 108, 255),
	}

	local players = game:GetService("Players")
	local runService = game:GetService("RunService")
	local userInputService = game:GetService("UserInputService")

	local panelMaid = Maid.new()
	local npcMaid = Maid.new()
	local animationMaid = Maid.new()
	local actionMaid = Maid.new()
	local bannedMaid = Maid.new()
	local markerMaid = Maid.new()
	local previewMaid = Maid.new()

	local isInitialized = false
	local isPaused = false
	local currentTrack = nil
	local previewTiming = nil

	local state = {
		selectedNpc = nil,
		selectedTiming = nil,
		selectedAction = nil,
		selectedBannedAid = nil,
	}

	local groupedNpcList = {}
	local groupedNpcMap = {}
	local refreshIssue = nil

	local screenGui = CoreGuiManager.imark(Instance.new("ScreenGui"))
	screenGui.Name = "ConfigViewerPanel"
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 3
	screenGui.Enabled = false

	local outer = Instance.new("Frame")
	outer.Name = "ConfigViewerOuter"
	outer.BackgroundColor3 = Color3.new(0, 0, 0)
	outer.BorderSizePixel = 0
	outer.AnchorPoint = Vector2.new(0.5, 0)
	outer.Position = UDim2.new(0.5, 0, 0, 12)
	outer.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	outer.Parent = screenGui

	local outerScale = Instance.new("UIScale")
	outerScale.Parent = outer

	local inner = Instance.new("Frame")
	inner.Name = "ConfigViewerInner"
	inner.BackgroundColor3 = Library.MainColor
	inner.BorderMode = Enum.BorderMode.Inset
	inner.BorderColor3 = Library.OutlineColor
	inner.Size = UDim2.new(1, 0, 1, 0)
	inner.Parent = outer

	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.BackgroundColor3 = Library.AccentColor
	accentBar.BorderSizePixel = 0
	accentBar.Size = UDim2.new(1, 0, 0, 2)
	accentBar.Parent = inner

	local titleLabel = Instance.new("TextLabel")
	titleLabel.FontFace = FONT
	titleLabel.TextColor3 = Library.AccentColor
	titleLabel.Text = "Config Viewer"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.new(0, 12, 0, 8)
	titleLabel.Size = UDim2.new(0, 280, 0, 20)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextSize = 18
	titleLabel.Parent = inner

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.FontFace = FONT
	subtitleLabel.TextColor3 = Library.FontColor
	subtitleLabel.Text = "NPC browser, animation preview, action timeline, and banned IDs in one panel."
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Position = UDim2.new(0, 12, 0, 31)
	subtitleLabel.Size = UDim2.new(0, 620, 0, 16)
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	subtitleLabel.TextSize = 13
	subtitleLabel.Parent = inner

	local closeButton = Instance.new("TextButton")
	closeButton.FontFace = FONT
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.BackgroundColor3 = Color3.fromRGB(186, 54, 54)
	closeButton.BorderSizePixel = 0
	closeButton.Position = UDim2.new(1, -34, 0, 8)
	closeButton.Size = UDim2.new(0, 24, 0, 20)
	closeButton.TextSize = 13
	closeButton.Parent = inner

	local refreshButton = Instance.new("TextButton")
	refreshButton.FontFace = FONT
	refreshButton.Text = "Refresh"
	refreshButton.TextColor3 = Library.FontColor
	refreshButton.BackgroundColor3 = Library.MainColor
	refreshButton.BorderColor3 = Color3.new(0, 0, 0)
	refreshButton.Position = UDim2.new(1, -214, 0, 8)
	refreshButton.Size = UDim2.new(0, 84, 0, 20)
	refreshButton.TextSize = 12
	refreshButton.Parent = inner

	local saveButton = Instance.new("TextButton")
	saveButton.FontFace = FONT
	saveButton.Text = "Save Config"
	saveButton.TextColor3 = Library.FontColor
	saveButton.BackgroundColor3 = Library.MainColor
	saveButton.BorderColor3 = Color3.new(0, 0, 0)
	saveButton.Position = UDim2.new(1, -124, 0, 8)
	saveButton.Size = UDim2.new(0, 84, 0, 20)
	saveButton.TextSize = 12
	saveButton.Parent = inner

	local statusLabel = Instance.new("TextLabel")
	statusLabel.FontFace = FONT
	statusLabel.TextColor3 = Library.FontColor
	statusLabel.Text = "Ready."
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.new(0, 12, 1, -22)
	statusLabel.Size = UDim2.new(1, -24, 0, 14)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextSize = 12
	statusLabel.Parent = inner

	local function registerTheme(instance, properties)
		Library:AddToRegistry(instance, properties, true)
	end

	local function section(parent, title, position, size)
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = Library.MainColor
		frame.BorderMode = Enum.BorderMode.Inset
		frame.BorderColor3 = Library.OutlineColor
		frame.Position = position
		frame.Size = size
		frame.Parent = parent

		local label = Instance.new("TextLabel")
		label.FontFace = FONT
		label.TextColor3 = Library.AccentColor
		label.Text = title
		label.BackgroundTransparency = 1
		label.Position = UDim2.new(0, 8, 0, 6)
		label.Size = UDim2.new(1, -16, 0, 18)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextSize = 15
		label.Parent = frame

		local bar = Instance.new("Frame")
		bar.BackgroundColor3 = Library.AccentColor
		bar.BorderSizePixel = 0
		bar.Position = UDim2.new(0, 6, 0, 29)
		bar.Size = UDim2.new(1, -12, 0, 1)
		bar.Parent = frame

		registerTheme(frame, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "OutlineColor",
		})
		registerTheme(label, {
			TextColor3 = "AccentColor",
		})
		registerTheme(bar, {
			BackgroundColor3 = "AccentColor",
		})

		return frame
	end

	local function createScrollFrame(parent, position, size)
		local scroll = Instance.new("ScrollingFrame")
		scroll.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
		scroll.BorderColor3 = Library.OutlineColor
		scroll.Position = position
		scroll.Size = size
		scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		scroll.ScrollBarThickness = 6
		scroll.ScrollBarImageColor3 = Library.AccentColor
		scroll.Parent = parent

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 4)
		padding.PaddingRight = UDim.new(0, 4)
		padding.PaddingTop = UDim.new(0, 4)
		padding.PaddingBottom = UDim.new(0, 4)
		padding.Parent = scroll

		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 4)
		layout.Parent = scroll

		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
		end)

		registerTheme(scroll, {
			BorderColor3 = "OutlineColor",
			ScrollBarImageColor3 = "AccentColor",
		})

		return scroll, layout
	end

	local function makeButton(parent, text, position, size)
		local button = Instance.new("TextButton")
		button.FontFace = FONT
		button.Text = text
		button.TextColor3 = Library.FontColor
		button.BackgroundColor3 = Library.MainColor
		button.BorderColor3 = Color3.new(0, 0, 0)
		button.Position = position
		button.Size = size
		button.TextSize = 12
		button.Parent = parent

		registerTheme(button, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "Black",
			TextColor3 = "FontColor",
		})

		return button
	end

	local function makeInput(parent, placeholder, position, size)
		local box = Instance.new("TextBox")
		box.FontFace = FONT
		box.TextColor3 = Library.FontColor
		box.PlaceholderColor3 = Color3.fromRGB(132, 132, 132)
		box.PlaceholderText = placeholder
		box.Text = ""
		box.ClearTextOnFocus = false
		box.BackgroundColor3 = Library.MainColor
		box.BorderColor3 = Color3.new(0, 0, 0)
		box.Position = position
		box.Size = size
		box.TextSize = 12
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.Parent = parent

		registerTheme(box, {
			BackgroundColor3 = "MainColor",
			BorderColor3 = "Black",
			TextColor3 = "FontColor",
		})

		return box
	end

	local function makeLabel(parent, text, position, size, textSize, wrap)
		local label = Instance.new("TextLabel")
		label.FontFace = FONT
		label.TextColor3 = Library.FontColor
		label.Text = text
		label.BackgroundTransparency = 1
		label.Position = position
		label.Size = size
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.TextWrapped = wrap == true
		label.TextSize = textSize or 12
		label.Parent = parent

		registerTheme(label, {
			TextColor3 = "FontColor",
		})

		return label
	end

	local leftSection = section(inner, "NPC Browser", UDim2.new(0, 10, 0, 56), UDim2.new(0, 240, 1, -88))
	local middleSection = section(inner, "Saved Animations", UDim2.new(0, 260, 0, 56), UDim2.new(0, 300, 1, -88))
	local rightSection = section(inner, "Preview And Editor", UDim2.new(0, 570, 0, 56), UDim2.new(1, -580, 1, -88))

	local npcCountLabel = makeLabel(leftSection, "NPC Groups: 0", UDim2.new(0, 8, 0, 35), UDim2.new(1, -16, 0, 14), 12, false)
	local npcScroll = createScrollFrame(leftSection, UDim2.new(0, 6, 0, 54), UDim2.new(1, -12, 0.63, -58))
	local bannedTitle = makeLabel(leftSection, "Banned Animation IDs", UDim2.new(0, 8, 0.64, 8), UDim2.new(1, -16, 0, 14), 13, false)
	local bannedCountLabel = makeLabel(leftSection, "Banned: 0", UDim2.new(0, 8, 0.64, 24), UDim2.new(1, -16, 0, 14), 12, false)
	local bannedScroll = createScrollFrame(leftSection, UDim2.new(0, 6, 0.69, 0), UDim2.new(1, -12, 0.31, -8))

	local animationCountLabel = makeLabel(middleSection, "Saved Timings: 0", UDim2.new(0, 8, 0, 35), UDim2.new(1, -16, 0, 14), 12, false)
	local animationHintLabel = makeLabel(middleSection, "Click a saved animation to preview and edit it.", UDim2.new(0, 8, 0, 51), UDim2.new(1, -16, 0, 28), 12, true)
	local animationScroll = createScrollFrame(middleSection, UDim2.new(0, 6, 0, 82), UDim2.new(1, -12, 1, -88))

	local previewViewport = Instance.new("ViewportFrame")
	previewViewport.BackgroundColor3 = Library.MainColor
	previewViewport.BorderMode = Enum.BorderMode.Inset
	previewViewport.BorderColor3 = Color3.new(0, 0, 0)
	previewViewport.Position = UDim2.new(0, 8, 0, 36)
	previewViewport.Size = UDim2.new(1, -16, 0, 298)
	previewViewport.Ambient = Color3.fromRGB(82, 82, 82)
	previewViewport.LightColor = Color3.fromRGB(140, 134, 111)
	previewViewport.Parent = rightSection

	registerTheme(previewViewport, {
		BackgroundColor3 = "MainColor",
		BorderColor3 = "Black",
	})

	local previewWorldModel = Instance.new("WorldModel")
	previewWorldModel.Parent = previewViewport

	local previewCamera = Instance.new("Camera")
	previewCamera.CameraType = Enum.CameraType.Scriptable
	previewCamera.FieldOfView = 70
	previewCamera.Parent = previewViewport
	previewViewport.CurrentCamera = previewCamera

	local previewMessage = makeLabel(
		previewViewport,
		"Select an animation to preview.",
		UDim2.new(0, 24, 0.5, -16),
		UDim2.new(1, -48, 0, 32),
		14,
		true
	)
	previewMessage.TextXAlignment = Enum.TextXAlignment.Center
	previewMessage.TextYAlignment = Enum.TextYAlignment.Center

	local previewTitle = makeLabel(rightSection, "Timing: -", UDim2.new(0, 8, 0, 340), UDim2.new(1, -16, 0, 16), 12, false)
	local previewMeta = makeLabel(rightSection, "Animation ID: -", UDim2.new(0, 8, 0, 356), UDim2.new(1, -16, 0, 16), 12, false)

	local timelineOuter = Instance.new("Frame")
	timelineOuter.BackgroundColor3 = Color3.new(0, 0, 0)
	timelineOuter.BorderSizePixel = 0
	timelineOuter.Position = UDim2.new(0, 8, 0, 378)
	timelineOuter.Size = UDim2.new(1, -16, 0, 16)
	timelineOuter.Parent = rightSection

	registerTheme(timelineOuter, {
		BorderColor3 = "Black",
	})

	local timelineInner = Instance.new("Frame")
	timelineInner.BackgroundColor3 = Library.MainColor
	timelineInner.BorderMode = Enum.BorderMode.Inset
	timelineInner.BorderColor3 = Color3.new(0, 0, 0)
	timelineInner.Size = UDim2.new(1, 0, 1, 0)
	timelineInner.Parent = timelineOuter

	registerTheme(timelineInner, {
		BackgroundColor3 = "MainColor",
		BorderColor3 = "Black",
	})

	local timelineFill = Instance.new("Frame")
	timelineFill.BackgroundColor3 = Library.AccentColor
	timelineFill.BorderColor3 = Library.AccentColorDark
	timelineFill.BorderMode = Enum.BorderMode.Inset
	timelineFill.Size = UDim2.new(0, 1, 1, 0)
	timelineFill.Visible = false
	timelineFill.Parent = timelineOuter

	registerTheme(timelineFill, {
		BackgroundColor3 = "AccentColor",
		BorderColor3 = "AccentColorDark",
	})

	local timelineMarkers = Instance.new("Frame")
	timelineMarkers.BackgroundTransparency = 1
	timelineMarkers.BorderSizePixel = 0
	timelineMarkers.Size = UDim2.new(1, 0, 1, 0)
	timelineMarkers.ZIndex = 10
	timelineMarkers.Parent = timelineOuter

	local timelineText = makeLabel(rightSection, "0.000 / 0.000 (0ms)", UDim2.new(0, 8, 0, 398), UDim2.new(0.62, 0, 0, 16), 12, false)
	local trackInfoText = makeLabel(rightSection, "No action markers loaded.", UDim2.new(0.62, 0, 0, 398), UDim2.new(0.38, -8, 0, 16), 12, false)
	trackInfoText.TextXAlignment = Enum.TextXAlignment.Right

	local backButton = makeButton(rightSection, "<", UDim2.new(0, 8, 0, 420), UDim2.new(0, 54, 0, 22))
	local playButton = makeButton(rightSection, "Pause", UDim2.new(0, 68, 0, 420), UDim2.new(0, 78, 0, 22))
	local forwardButton = makeButton(rightSection, ">", UDim2.new(0, 152, 0, 420), UDim2.new(0, 54, 0, 22))
	local externalButton = makeButton(rightSection, "Open Visualizer", UDim2.new(0, 214, 0, 420), UDim2.new(0, 114, 0, 22))
	local banButton = makeButton(rightSection, "Ban ID", UDim2.new(0, 334, 0, 420), UDim2.new(0, 74, 0, 22))
	local unbanButton = makeButton(rightSection, "Unban ID", UDim2.new(0, 414, 0, 420), UDim2.new(0, 82, 0, 22))

	local actionListLabel = makeLabel(rightSection, "Actions", UDim2.new(0, 8, 0, 452), UDim2.new(0.3, 0, 0, 16), 13, false)
	local actionHelpLabel = makeLabel(rightSection, "Click an action row or a timeline marker to edit it.", UDim2.new(0.3, 0, 0, 452), UDim2.new(0.7, -8, 0, 16), 12, false)
	actionHelpLabel.TextXAlignment = Enum.TextXAlignment.Right
	local actionScroll = createScrollFrame(rightSection, UDim2.new(0, 8, 0, 472), UDim2.new(1, -16, 0, 102))

	local timingNameLabel = makeLabel(rightSection, "Timing Name", UDim2.new(0, 8, 0, 582), UDim2.new(0, 140, 0, 14), 12, false)
	local timingNameBox = makeInput(rightSection, "Rename saved animation", UDim2.new(0, 8, 0, 598), UDim2.new(0, 240, 0, 22))
	local renameButton = makeButton(rightSection, "Rename", UDim2.new(0, 254, 0, 598), UDim2.new(0, 72, 0, 22))

	local delayLabel = makeLabel(rightSection, "Selected Action Delay (ms)", UDim2.new(0, 334, 0, 582), UDim2.new(0, 164, 0, 14), 12, false)
	local delayBox = makeInput(rightSection, "e.g. 160", UDim2.new(0, 334, 0, 598), UDim2.new(0, 88, 0, 22))
	local applyDelayButton = makeButton(rightSection, "Apply", UDim2.new(0, 428, 0, 598), UDim2.new(0, 68, 0, 22))

	local tagButton = makeButton(rightSection, "Tag: Undefined", UDim2.new(0, 8, 0, 628), UDim2.new(0, 126, 0, 22))
	local noDashButton = makeButton(rightSection, "No Dash Fallback: Off", UDim2.new(0, 140, 0, 628), UDim2.new(0, 186, 0, 22))
	local deleteTimingButton = makeButton(rightSection, "Delete Timing", UDim2.new(0, 334, 0, 628), UDim2.new(0, 98, 0, 22))
	local deleteActionButton = makeButton(rightSection, "Delete Action", UDim2.new(0, 438, 0, 628), UDim2.new(0, 98, 0, 22))

	local typeLabel = makeLabel(rightSection, "Set Action Type", UDim2.new(0, 8, 0, 658), UDim2.new(0, 120, 0, 14), 12, false)
	local typeButtons = {}
	for index, actionType in ipairs(ACTION_TYPES) do
		typeButtons[actionType] = makeButton(
			rightSection,
			actionType,
			UDim2.new(0, 8 + ((index - 1) * 126), 0, 676),
			UDim2.new(0, 118, 0, 22)
		)
	end

	registerTheme(inner, {
		BackgroundColor3 = "MainColor",
		BorderColor3 = "OutlineColor",
	})
	registerTheme(accentBar, {
		BackgroundColor3 = "AccentColor",
	})
	registerTheme(titleLabel, {
		TextColor3 = "AccentColor",
	})
	registerTheme(subtitleLabel, {
		TextColor3 = "FontColor",
	})
	registerTheme(statusLabel, {
		TextColor3 = "FontColor",
	})

	local function configAnimationContainer()
		return SaveManager.as and SaveManager.as.config or nil
	end

	local function setStatus(text)
		statusLabel.Text = text
	end

	local function noteRefreshIssue(message)
		if refreshIssue then
			return
		end

		refreshIssue = tostring(message)
		Logger.warn("[ConfigViewer] %s", refreshIssue)
	end

	local function normalizedGroupName(value)
		return string.lower(tostring(value or "")):gsub("[%W_]+", "")
	end

	local function localCharacterModel()
		local localCharacter = players.LocalPlayer and players.LocalPlayer.Character
		if typeof(localCharacter) == "Instance" and localCharacter:IsA("Model") then
			return localCharacter
		end

		return nil
	end

	local function updateOuterScale()
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(PANEL_W, PANEL_H)
		local widthScale = math.max(viewport.X - 24, 1) / PANEL_W
		local heightScale = math.max(viewport.Y - 24, 1) / PANEL_H
		outerScale.Scale = math.max(math.min(widthScale, heightScale, 1), 0.1)
	end

	local function lowerKey(value)
		return string.lower(tostring(value or ""))
	end

	local function displayGroupName(groupName)
		local trimmed = type(groupName) == "string" and string.match(groupName, "^%s*(.-)%s*$") or ""
		return trimmed ~= "" and trimmed or "Unknown Group"
	end

	local function sortStrings(values)
		table.sort(values, function(left, right)
			return lowerKey(left) < lowerKey(right)
		end)
	end

	local function currentDelayMs(action)
		if not action then
			return 0
		end

		return math.round((action:when() or 0) * 1000)
	end

	local function sortedActions(timing)
		local actions = {}
		if not timing then
			return actions
		end

		for _, action in next, timing.actions:get() do
			table.insert(actions, action)
		end

		table.sort(actions, function(left, right)
			local leftDelay = currentDelayMs(left)
			local rightDelay = currentDelayMs(right)

			if leftDelay == rightDelay then
				return lowerKey(left.name) < lowerKey(right.name)
			end

			return leftDelay < rightDelay
		end)

		return actions
	end

	local function selectedTimingValid()
		local container = configAnimationContainer()
		if not container or not state.selectedTiming then
			return false
		end

		return container.timings[state.selectedTiming:id()] == state.selectedTiming
	end

	local function selectedActionValid()
		if not state.selectedTiming or not state.selectedAction then
			return false
		end

		return state.selectedTiming.actions:find(state.selectedAction.name) == state.selectedAction
	end

	local function derivedGroupName(timing)
		local harvested = tostring(timing.name or ""):match("^(.-)_%d+_Harvested$")
		local fallback = harvested or timing.name or "Unknown"
		if type(fallback) ~= "string" or #fallback <= 0 then
			return "Unknown"
		end

		return fallback
	end

	local function appendGroupName(names, seen, groupName)
		if type(groupName) ~= "string" then
			return
		end

		local trimmed = string.match(groupName, "^%s*(.-)%s*$")
		local key = normalizedGroupName(trimmed)
		if key == "" or seen[key] then
			return
		end

		seen[key] = true
		table.insert(names, trimmed)
	end

	local function timingAid(timing)
		local aid = timing and timing._id
		if type(aid) ~= "string" or aid == "" then
			return nil
		end

		return aid
	end

	local function groupNamesForTiming(timing)
		local names = {}
		local seen = {}
		local primaryName = derivedGroupName(timing)
		appendGroupName(names, seen, primaryName)

		local aid = timingAid(timing)
		local captured = type(aid) == "string" and AnimationLogger.getCaptured(aid) or nil
		local observed = type(aid) == "string" and TimingHarvester.getObserved()[aid] or nil
		local previewSource = aid and AnimationLogger.getPreviewSource(aid) or nil

		local function appendAlias(name)
			if type(name) ~= "string" or name == "Player" then
				return
			end

			if normalizedGroupName(name) == normalizedGroupName(primaryName) then
				return
			end

			appendGroupName(names, seen, name)
		end

		appendAlias(captured and captured.entityName or nil)
		appendAlias(observed and observed.meta and observed.meta.entityName or nil)
		if typeof(previewSource) == "Instance" and previewSource:IsA("Model") and previewSource.Parent then
			local localCharacter = localCharacterModel()
			if previewSource ~= localCharacter then
				appendAlias(previewSource.Name)
			end
		end

		return names
	end

	local function findLiveModel(groupName)
		local live = workspace:FindFirstChild("Live")
		if not live or type(groupName) ~= "string" or #groupName <= 0 then
			return nil
		end

		local exact = live:FindFirstChild(groupName)
		if typeof(exact) == "Instance" and exact:IsA("Model") then
			return exact
		end

		local normalizedWanted = normalizedGroupName(groupName)
		if normalizedWanted == "" then
			return nil
		end

		local partial = nil
		for _, child in ipairs(live:GetChildren()) do
			if child:IsA("Model") then
				local normalizedChild = normalizedGroupName(child.Name)
				if normalizedChild == normalizedWanted then
					return child
				end

				if not partial and (string.find(normalizedChild, normalizedWanted, 1, true) or string.find(normalizedWanted, normalizedChild, 1, true)) then
					partial = child
				end
			end
		end

		return partial
	end

	local function appendPreviewCandidate(candidates, seen, candidate)
		if typeof(candidate) ~= "Instance" or not candidate:IsA("Model") or not candidate.Parent then
			return
		end

		if seen[candidate] then
			return
		end

		seen[candidate] = true
		table.insert(candidates, candidate)
	end

	local function previewCandidatesForTiming(timing, groupName)
		local candidates = {}
		local seen = {}

		appendPreviewCandidate(candidates, seen, findLiveModel(groupName))
		appendPreviewCandidate(candidates, seen, findLiveModel(derivedGroupName(timing)))

		local aid = timingAid(timing)
		local previewSource = aid and AnimationLogger.getPreviewSource(aid) or nil
		appendPreviewCandidate(candidates, seen, previewSource)
		appendPreviewCandidate(candidates, seen, localCharacterModel())

		return candidates
	end

	local function ensureAnimator(model)
		local animator = model and model:FindFirstChildWhichIsA("Animator", true) or nil
		if animator then
			return animator
		end

		local controller = model and model:FindFirstChildWhichIsA("AnimationController", true) or nil
		local humanoid = model and model:FindFirstChildWhichIsA("Humanoid", true) or nil
		local host = humanoid or controller
		if not host and model then
			host = Instance.new("AnimationController")
			host.Name = "PreviewAnimationController"
			host.Parent = model
		end

		if not host then
			return nil
		end

		animator = Instance.new("Animator")
		animator.Name = "PreviewAnimator"
		animator.Parent = host
		return animator
	end

	local function cloneModel(sourceModel)
		if typeof(sourceModel) ~= "Instance" or not sourceModel:IsA("Model") then
			return nil
		end

		pcall(function()
			sourceModel.Archivable = true
		end)

		local ok, clone = pcall(function()
			return sourceModel:Clone()
		end)

		if not ok then
			return nil
		end

		return clone
	end

	local function pivotPart(model)
		return model and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)) or nil
	end

	local function fillViewport(viewport, worldModel, camera, sourceModel)
		for _, child in ipairs(worldModel:GetChildren()) do
			child:Destroy()
		end

		local clone = cloneModel(sourceModel)
		if not clone then
			return nil
		end

		clone.Parent = worldModel
		clone:PivotTo(CFrame.new(0, 0, 0))

		local root = pivotPart(clone)
		if not root then
			clone:Destroy()
			return nil
		end

		if not clone.PrimaryPart then
			clone.PrimaryPart = root
		end

		local _, bounds = clone:GetBoundingBox()
		local focus = root.Position + Vector3.new(0, bounds.Y * 0.25, 0)
		camera.CFrame = CFrame.lookAt(
			focus + Vector3.new(0, bounds.Y * 0.15, math.max(bounds.Magnitude * 1.25, 4)),
			focus
		)
		viewport.CurrentCamera = camera

		return clone
	end

	local function selectedAid()
		return timingAid(state.selectedTiming)
	end

	local function setPreviewMessage(message)
		previewMessage.Text = message
		previewMessage.Visible = true
	end

	local function clearPreview()
		previewMaid:clean()
		currentTrack = nil
		previewTiming = nil
		isPaused = false
		for _, child in ipairs(previewWorldModel:GetChildren()) do
			child:Destroy()
		end
		setPreviewMessage("Select an animation to preview.")
		timelineFill.Visible = false
		timelineFill.Size = UDim2.new(0, 1, 1, 0)
		timelineText.Text = "0.000 / 0.000 (0ms)"
		trackInfoText.Text = "No action markers loaded."
	end

	local function actionMarkerColor(action)
		return ACTION_COLORS[action._type] or Library.AccentColor
	end

	local function updateEditorTexts()
		local timing = state.selectedTiming
		local action = state.selectedAction

		previewTitle.Text = string.format("Timing: %s", timing and timing.name or "-")
		previewMeta.Text = string.format("Animation ID: %s", timingAid(timing) or "-")

		if timing then
			timingNameBox.Text = timing.name
			tagButton.Text = string.format("Tag: %s", timing.tag or "Undefined")
			noDashButton.Text = string.format("No Dash Fallback: %s", timing.ndfb and "On" or "Off")
		else
			timingNameBox.Text = ""
			tagButton.Text = "Tag: Undefined"
			noDashButton.Text = "No Dash Fallback: Off"
		end

		if action then
			delayBox.Text = tostring(currentDelayMs(action))
			trackInfoText.Text = string.format("Selected: %s (%s @ %dms)", action.name, action._type, currentDelayMs(action))
		else
			delayBox.Text = ""
			trackInfoText.Text = timing and "Select an action to edit its marker." or "No action markers loaded."
		end

		for actionType, button in next, typeButtons do
			if action and action._type == actionType then
				button.BackgroundColor3 = actionMarkerColor(action)
				button.TextColor3 = Color3.new(1, 1, 1)
			else
				button.BackgroundColor3 = Library.MainColor
				button.TextColor3 = Library.FontColor
			end
		end
	end

	local function refreshMarkers()
		markerMaid:clean()

		if not currentTrack or not state.selectedTiming then
			return
		end

		local trackLength = currentTrack.Length
		if type(trackLength) ~= "number" or trackLength <= 0 then
			return
		end

		for _, action in ipairs(sortedActions(state.selectedTiming)) do
			local normalized = math.clamp((action:when() or 0) / trackLength, 0, 1)
			local marker = Instance.new("TextButton")
			marker.AutoButtonColor = false
			marker.Text = ""
			marker.BorderSizePixel = 0
			marker.BackgroundColor3 = actionMarkerColor(action)
			marker.AnchorPoint = Vector2.new(0.5, 0)
			marker.Position = UDim2.new(normalized, 0, 0, 0)
			marker.Size = UDim2.new(0, action == state.selectedAction and 6 or 3, 1, 0)
			marker.ZIndex = 12
			marker.Parent = timelineMarkers

			markerMaid:add(marker)
			markerMaid:add(marker.MouseButton1Click:Connect(function()
				state.selectedAction = action
				updateEditorTexts()
				refreshMarkers()
				ConfigViewerPanel.refresh(false)
			end))
		end
	end

	local function syncPreview()
		if not state.selectedTiming then
			clearPreview()
			return
		end

		if previewTiming == state.selectedTiming and currentTrack then
			previewMessage.Visible = false
			refreshMarkers()
			return
		end

		previewMaid:clean()
		currentTrack = nil
		previewTiming = state.selectedTiming
		isPaused = false
		playButton.Text = "Pause"

		local aid = timingAid(state.selectedTiming)
		if not aid then
			setPreviewMessage("Selected timing has no animation ID.")
			refreshMarkers()
			return
		end

		local candidates = previewCandidatesForTiming(state.selectedTiming, state.selectedNpc)
		if #candidates == 0 then
			setPreviewMessage("No preview source is available for this animation yet.")
			refreshMarkers()
			return
		end

		local loadedClone = nil
		local loadedAnimation = nil
		local lastFailure = "Failed to load the selected animation on the preview model."
		for _, sourceModel in ipairs(candidates) do
			local clone = fillViewport(previewViewport, previewWorldModel, previewCamera, sourceModel)
			if clone then
				local animator = ensureAnimator(clone)
				if animator then
					local animation = Instance.new("Animation")
					animation.AnimationId = aid

					local ok, track = pcall(function()
						return animator:LoadAnimation(animation)
					end)
					if ok and track then
						loadedClone = clone
						loadedAnimation = animation
						currentTrack = track
						break
					end

					animation:Destroy()
					lastFailure = "Failed to load the selected animation on the preview model."
				else
					lastFailure = "Preview model has no Animator."
				end

				clone:Destroy()
			else
				lastFailure = "Failed to clone preview model."
			end
		end

		if not currentTrack or not loadedClone or not loadedAnimation then
			setPreviewMessage(lastFailure)
			refreshMarkers()
			return
		end

		previewMaid:add(loadedClone)
		previewMaid:add(loadedAnimation)
		currentTrack.Priority = Enum.AnimationPriority.Action
		currentTrack.Looped = true
		currentTrack:Play(0.0, 100, 1.0)
		previewMaid:add(currentTrack)
		previewMessage.Visible = false
		refreshMarkers()
	end

	local function collectGroups()
		groupedNpcList = {}
		groupedNpcMap = {}

		local container = configAnimationContainer()
		if not container then
			return
		end

		for _, timing in ipairs(container:list()) do
			for _, groupName in ipairs(groupNamesForTiming(timing)) do
				local group = groupedNpcMap[groupName]
				if not group then
					group = {
						name = groupName,
						timings = {},
					}
					groupedNpcMap[groupName] = group
					table.insert(groupedNpcList, group)
				end

				table.insert(group.timings, timing)
			end
		end

		table.sort(groupedNpcList, function(left, right)
			return lowerKey(left.name) < lowerKey(right.name)
		end)

		for _, group in ipairs(groupedNpcList) do
			table.sort(group.timings, function(left, right)
				local leftAid = timingAid(left) or ""
				local rightAid = timingAid(right) or ""

				if leftAid == rightAid then
					return lowerKey(left.name) < lowerKey(right.name)
				end

				return lowerKey(leftAid) < lowerKey(rightAid)
			end)
		end
	end

	local function groupContainsTiming(group, timing)
		if not group or not timing then
			return false
		end

		for _, candidate in ipairs(group.timings) do
			if candidate == timing then
				return true
			end
		end

		return false
	end

	local function ensureSelections()
		if not groupedNpcMap[state.selectedNpc] then
			state.selectedNpc = groupedNpcList[1] and groupedNpcList[1].name or nil
		end

		local currentGroup = state.selectedNpc and groupedNpcMap[state.selectedNpc] or nil
		if not currentGroup then
			state.selectedTiming = nil
			state.selectedAction = nil
			return
		end

		if not selectedTimingValid() or not groupContainsTiming(currentGroup, state.selectedTiming) then
			state.selectedTiming = currentGroup.timings[1]
		end

		if not selectedActionValid() then
			local actions = sortedActions(state.selectedTiming)
			state.selectedAction = actions[1]
		end
	end

	local function clearList(maid, scroll)
		maid:clean()
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiObject") and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end
	end

	local function thumbnailForGroup(parent, group)
		local viewport = Instance.new("ViewportFrame")
		viewport.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
		viewport.BorderColor3 = Color3.new(0, 0, 0)
		viewport.Position = UDim2.new(0, 8, 0, 8)
		viewport.Size = UDim2.new(0, 54, 0, 54)
		viewport.Ambient = Color3.fromRGB(82, 82, 82)
		viewport.LightColor = Color3.fromRGB(140, 134, 111)
		viewport.Parent = parent

		registerTheme(viewport, {
			BorderColor3 = "Black",
		})

		local worldModel = Instance.new("WorldModel")
		worldModel.Parent = viewport

		local camera = Instance.new("Camera")
		camera.CameraType = Enum.CameraType.Scriptable
		camera.Parent = viewport
		viewport.CurrentCamera = camera

		local function addPlaceholder()
			local placeholder = Instance.new("TextLabel")
			placeholder.FontFace = TITLE_FONT
			placeholder.Text = string.sub(displayGroupName(group.name), 1, 1)
			placeholder.TextColor3 = Library.AccentColor
			placeholder.BackgroundTransparency = 1
			placeholder.Size = UDim2.new(1, 0, 1, 0)
			placeholder.TextSize = 26
			placeholder.Parent = viewport

			registerTheme(placeholder, {
				TextColor3 = "AccentColor",
			})
		end

		local ok, rendered = pcall(function()
			local previewSource = nil
			for _, timing in ipairs(group.timings) do
				previewSource = previewSourceForTiming(timing, group.name)
				if previewSource then
					break
				end
			end

			return fillViewport(viewport, worldModel, camera, previewSource)
		end)

		if not ok or not rendered then
			for _, child in ipairs(worldModel:GetChildren()) do
				child:Destroy()
			end
			addPlaceholder()
		end

		return viewport
	end

	local function refreshNpcEntries()
		clearList(npcMaid, npcScroll)
		npcCountLabel.Text = string.format("NPC Groups: %d", #groupedNpcList)

		for index, group in ipairs(groupedNpcList) do
			local ok, err = pcall(function()
				local groupDisplayName = displayGroupName(group.name)
				local entry = Instance.new("TextButton")
				entry.AutoButtonColor = false
				entry.Text = ""
				entry.LayoutOrder = index
				entry.BackgroundColor3 = group.name == state.selectedNpc and Library.AccentColor or Color3.fromRGB(26, 26, 26)
				entry.BackgroundTransparency = group.name == state.selectedNpc and 0.55 or 0
				entry.BorderSizePixel = 0
				entry.Size = UDim2.new(1, -2, 0, NPC_ENTRY_H)
				entry.Parent = npcScroll

				npcMaid:add(entry)
				thumbnailForGroup(entry, group)

				local nameLabel = Instance.new("TextLabel")
				nameLabel.FontFace = FONT
				nameLabel.TextColor3 = Library.FontColor
				nameLabel.Text = groupDisplayName
				nameLabel.BackgroundTransparency = 1
				nameLabel.Position = UDim2.new(0, 70, 0, 9)
				nameLabel.Size = UDim2.new(1, -78, 0, 18)
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.TextSize = 14
				nameLabel.Parent = entry

				registerTheme(nameLabel, {
					TextColor3 = "FontColor",
				})

				local countLabel = Instance.new("TextLabel")
				countLabel.FontFace = FONT
				countLabel.TextColor3 = Color3.fromRGB(168, 168, 168)
				countLabel.Text = string.format("%d saved timing%s", #group.timings, #group.timings == 1 and "" or "s")
				countLabel.BackgroundTransparency = 1
				countLabel.Position = UDim2.new(0, 70, 0, 31)
				countLabel.Size = UDim2.new(1, -78, 0, 15)
				countLabel.TextXAlignment = Enum.TextXAlignment.Left
				countLabel.TextSize = 11
				countLabel.Parent = entry

				local aidLabel = Instance.new("TextLabel")
				aidLabel.FontFace = FONT
				aidLabel.TextColor3 = Color3.fromRGB(132, 132, 132)
				aidLabel.Text = string.format("First ID: %s", timingAid(group.timings[1]) or "-")
				aidLabel.BackgroundTransparency = 1
				aidLabel.Position = UDim2.new(0, 70, 0, 47)
				aidLabel.Size = UDim2.new(1, -78, 0, 14)
				aidLabel.TextXAlignment = Enum.TextXAlignment.Left
				aidLabel.TextSize = 10
				aidLabel.Parent = entry

				npcMaid:add(entry.MouseButton1Click:Connect(function()
					state.selectedNpc = group.name
					state.selectedTiming = nil
					state.selectedAction = nil
					ConfigViewerPanel.refresh(false)
				end))
			end)

			if not ok then
				noteRefreshIssue(string.format("NPC row '%s' failed to render: %s", displayGroupName(group and group.name), tostring(err)))
			end
		end
	end

	local function animationSummary(timing)
		local actions = sortedActions(timing)
		if #actions == 0 then
			return "No actions saved"
		end

		local first = actions[1]
		return string.format("%s @ %dms | %d action%s", first._type, currentDelayMs(first), #actions, #actions == 1 and "" or "s")
	end

	local function refreshAnimationEntries()
		clearList(animationMaid, animationScroll)
		local group = state.selectedNpc and groupedNpcMap[state.selectedNpc] or nil
		local timings = group and group.timings or {}
		animationCountLabel.Text = string.format("Saved Timings: %d", #timings)

		if not group then
			if not SaveManager.llcn or #SaveManager.llcn <= 0 then
				animationHintLabel.Text = "No config loaded. Use the Config Viewer tab to load a saved timing file."
			else
				animationHintLabel.Text = string.format("Loaded config '%s' has no saved animation timings.", SaveManager.llcn)
			end
			return
		end

		animationHintLabel.Text = string.format("Browsing '%s'. Rename the saved animation name or change its action timing on the right.", group.name)

		for index, timing in ipairs(timings) do
			local ok, err = pcall(function()
				local selected = timing == state.selectedTiming
				local entry = Instance.new("TextButton")
				entry.AutoButtonColor = false
				entry.Text = ""
				entry.LayoutOrder = index
				entry.BackgroundColor3 = selected and Library.AccentColor or Color3.fromRGB(26, 26, 26)
				entry.BackgroundTransparency = selected and 0.55 or 0
				entry.BorderSizePixel = 0
				entry.Size = UDim2.new(1, -2, 0, ANIM_ENTRY_H)
				entry.Parent = animationScroll

				animationMaid:add(entry)

				local nameLabel = makeLabel(entry, timing.name, UDim2.new(0, 8, 0, 8), UDim2.new(1, -16, 0, 18), 13, false)
				nameLabel.TextColor3 = Library.FontColor
				local aidLabel = makeLabel(
					entry,
					string.format("ID: %s", timingAid(timing) or "-"),
					UDim2.new(0, 8, 0, 28),
					UDim2.new(1, -16, 0, 14),
					11,
					false
				)
				aidLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
				local metaLabel = makeLabel(
					entry,
					animationSummary(timing),
					UDim2.new(0, 8, 0, 42),
					UDim2.new(1, -16, 0, 14),
					10,
					false
				)
				metaLabel.TextColor3 = Color3.fromRGB(132, 132, 132)

				animationMaid:add(entry.MouseButton1Click:Connect(function()
					state.selectedTiming = timing
					state.selectedAction = nil
					ConfigViewerPanel.refresh(false)
				end))
			end)

			if not ok then
				noteRefreshIssue(string.format("Animation row '%s' failed to render: %s", tostring(timing and timing.name or "?"), tostring(err)))
			end
		end
	end

	local function refreshActionEntries()
		clearList(actionMaid, actionScroll)
		local actions = sortedActions(state.selectedTiming)

		for index, action in ipairs(actions) do
			local selected = action == state.selectedAction
			local entry = Instance.new("TextButton")
			entry.AutoButtonColor = false
			entry.Text = ""
			entry.LayoutOrder = index
			entry.BackgroundColor3 = selected and actionMarkerColor(action) or Color3.fromRGB(26, 26, 26)
			entry.BackgroundTransparency = selected and 0.3 or 0
			entry.BorderSizePixel = 0
			entry.Size = UDim2.new(1, -2, 0, ACTION_ENTRY_H)
			entry.Parent = actionScroll

			actionMaid:add(entry)

			local actionLabel = makeLabel(
				entry,
				string.format("%s  |  %s  |  %dms", action.name, action._type, currentDelayMs(action)),
				UDim2.new(0, 8, 0, 7),
				UDim2.new(1, -16, 0, 14),
				12,
				false
			)

			actionMaid:add(entry.MouseButton1Click:Connect(function()
				state.selectedAction = action
				updateEditorTexts()
				refreshMarkers()
				refreshActionEntries()
			end))
		end
	end

	local function refreshBannedEntries()
		clearList(bannedMaid, bannedScroll)
		local banned = {}
		for aid, info in next, TimingHarvester.getBanned() do
			table.insert(banned, { aid = aid, info = info })
		end

		table.sort(banned, function(left, right)
			return lowerKey(left.aid) < lowerKey(right.aid)
		end)

		bannedCountLabel.Text = string.format("Banned: %d", #banned)

		if #banned > 0 then
			local stillSelected = false
			for _, entry in ipairs(banned) do
				if entry.aid == state.selectedBannedAid then
					stillSelected = true
					break
				end
			end
			if not stillSelected then
				state.selectedBannedAid = banned[1].aid
			end
		else
			state.selectedBannedAid = nil
		end

		for index, entryData in ipairs(banned) do
			local selected = entryData.aid == state.selectedBannedAid
			local entry = Instance.new("TextButton")
			entry.AutoButtonColor = false
			entry.Text = ""
			entry.LayoutOrder = index
			entry.BackgroundColor3 = selected and Library.AccentColor or Color3.fromRGB(26, 26, 26)
			entry.BackgroundTransparency = selected and 0.55 or 0
			entry.BorderSizePixel = 0
			entry.Size = UDim2.new(1, -2, 0, BANNED_ENTRY_H)
			entry.Parent = bannedScroll

			bannedMaid:add(entry)

			local label = makeLabel(
				entry,
				string.format("%s  |  %s", entryData.aid, entryData.info.meta and entryData.info.meta.entityName or "?"),
				UDim2.new(0, 8, 0, 6),
				UDim2.new(1, -16, 0, 14),
				11,
				false
			)

			bannedMaid:add(entry.MouseButton1Click:Connect(function()
				state.selectedBannedAid = entryData.aid
				refreshBannedEntries()
				local container = configAnimationContainer()
				if not container then
					return
				end

				for _, timing in ipairs(container:list()) do
					if timingAid(timing) == entryData.aid then
						state.selectedNpc = groupNamesForTiming(timing)[1] or derivedGroupName(timing)
						state.selectedTiming = timing
						state.selectedAction = nil
						ConfigViewerPanel.refresh(false)
						break
					end
				end
			end))
		end
	end

	local function saveCurrentConfig()
		if not SaveManager.llcn or #SaveManager.llcn <= 0 then
			return Logger.notify("No loaded config file to write. Load or create one first.")
		end

		SaveManager.write(SaveManager.llcn)
		setStatus(string.format("Saved '%s'.", SaveManager.llcn))
	end

	local function applyActionDelay(action, delayMs)
		action._when = delayMs
		for _, profile in ipairs(action.pingProfiles or {}) do
			profile.when = delayMs
		end
	end

	function ConfigViewerPanel.refresh(reloadPreview)
		refreshIssue = nil

		local ok, err = pcall(function()
			collectGroups()
			ensureSelections()
			refreshNpcEntries()
			refreshAnimationEntries()
			refreshActionEntries()
			refreshBannedEntries()
			updateEditorTexts()

			if reloadPreview ~= false then
				syncPreview()
			else
				if previewTiming ~= state.selectedTiming then
					syncPreview()
				else
					refreshMarkers()
				end
			end

			if refreshIssue then
				setStatus(refreshIssue)
			elseif #groupedNpcList == 0 then
				if not SaveManager.llcn or #SaveManager.llcn <= 0 then
					setStatus("No config loaded. Use the Config Viewer tab to load one.")
				else
					setStatus(string.format("Loaded config '%s' has no saved animation timings.", SaveManager.llcn))
				end
			else
				local bannedIds = 0
				for _ in next, TimingHarvester.getBanned() do
					bannedIds = bannedIds + 1
				end

				setStatus(string.format("Browsing %d NPC groups and %d banned animation IDs.", #groupedNpcList, bannedIds))
			end
		end)

		if not ok then
			local message = string.format("Config Viewer refresh failed: %s", tostring(err))
			setStatus(message)
			Logger.warn("[ConfigViewer] %s", message)
			return false
		end

		return true
	end

	local function sliderWidth()
		return timelineOuter.AbsoluteSize.X
	end

	local function sliderFillSize(timePosition, length)
		local width = sliderWidth()
		if width <= 0 or length <= 0 then
			return 0
		end

		return math.clamp(math.floor((timePosition / length) * width + 0.5), 0, width)
	end

	local function updateTimelineVisuals()
		if not currentTrack then
			timelineFill.Visible = false
			timelineText.Text = "0.000 / 0.000 (0ms)"
			return
		end

		local length = currentTrack.Length or 0
		local timePosition = currentTrack.TimePosition or 0
		local fill = sliderFillSize(timePosition, length)
		timelineFill.Visible = fill > 0
		timelineFill.Size = UDim2.new(0, math.max(fill, 1), 1, 0)
		timelineText.Text = string.format("%.3f / %.3f (%dms)", timePosition, length, math.round(timePosition * 1000))
	end

	local function playPausePreview()
		if not currentTrack then
			return
		end

		isPaused = not isPaused
		playButton.Text = isPaused and "Play" or "Pause"
		setStatus(isPaused and "Preview paused." or "Preview resumed.")
	end

	local function stepPreview(delta)
		if not currentTrack then
			return
		end

		currentTrack.TimePosition = math.clamp(currentTrack.TimePosition + delta, 0, currentTrack.Length)
		isPaused = true
		playButton.Text = "Play"
		updateTimelineVisuals()
	end

	local function scrubTimeline()
		if not currentTrack then
			return
		end

		while screenGui.Enabled and userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
			if not currentTrack then
				return
			end

			local mouse = players.LocalPlayer:GetMouse()
			local width = sliderWidth()
			if width <= 0 then
				return
			end

			isPaused = true
			playButton.Text = "Play"
			local mouseX = math.clamp(mouse.X - timelineOuter.AbsolutePosition.X, 0, width)
			currentTrack.TimePosition = (mouseX / width) * currentTrack.Length
			updateTimelineVisuals()
			runService.PreRender:Wait()
		end
	end

	function ConfigViewerPanel.visible(state)
		if state and not isInitialized then
			ConfigViewerPanel.init()
		end

		screenGui.Enabled = state
		if state then
			updateOuterScale()
			ConfigViewerPanel.refresh(true)
		end
	end

	function ConfigViewerPanel.toggle()
		ConfigViewerPanel.visible(not screenGui.Enabled)
	end

	function ConfigViewerPanel.init()
		if isInitialized then
			return
		end

		updateOuterScale()
		Library:MakeDraggable(outer)

		panelMaid:add(closeButton.MouseButton1Click:Connect(function()
			ConfigViewerPanel.visible(false)
		end))

		panelMaid:add(refreshButton.MouseButton1Click:Connect(function()
			ConfigViewerPanel.refresh(true)
		end))

		panelMaid:add(saveButton.MouseButton1Click:Connect(function()
			saveCurrentConfig()
		end))

		panelMaid:add(playButton.MouseButton1Click:Connect(playPausePreview))
		panelMaid:add(backButton.MouseButton1Click:Connect(function()
			stepPreview(-0.01)
		end))
		panelMaid:add(forwardButton.MouseButton1Click:Connect(function()
			stepPreview(0.01)
		end))
		panelMaid:add(externalButton.MouseButton1Click:Connect(function()
			local aid = selectedAid()
			if not aid then
				return Logger.notify("Select a saved animation first.")
			end

			AnimationVisualizer.loadId(aid)
		end))

		panelMaid:add(banButton.MouseButton1Click:Connect(function()
			local aid = selectedAid()
			if not aid then
				return Logger.notify("Select a saved animation first.")
			end

			local ok, result = TimingHarvester.ban(aid)
			if not ok then
				return Logger.notify(result)
			end

			AnimationLogger.removeCaptured(aid)
			state.selectedBannedAid = aid
			ConfigViewerPanel.refresh(false)
		end))

		panelMaid:add(unbanButton.MouseButton1Click:Connect(function()
			local aid = state.selectedBannedAid or selectedAid()
			if not aid then
				return Logger.notify("Select a banned animation ID first.")
			end

			local ok, result = TimingHarvester.unban(aid)
			if not ok then
				return Logger.notify(result)
			end

			ConfigViewerPanel.refresh(false)
		end))

		panelMaid:add(renameButton.MouseButton1Click:Connect(function()
			local timing = state.selectedTiming
			local container = configAnimationContainer()
			local newName = timingNameBox.Text
			if not timing or not container then
				return Logger.notify("Select a saved animation first.")
			end

			if not newName or #newName <= 0 then
				return Logger.notify("Timing name cannot be empty.")
			end

			local existing = container:find(newName)
			if existing and existing ~= timing then
				return Logger.notify("Timing name '%s' already exists.", newName)
			end

			timing.name = newName
			ConfigViewerPanel.refresh(false)
			setStatus(string.format("Renamed timing to '%s'.", newName))
		end))

		panelMaid:add(applyDelayButton.MouseButton1Click:Connect(function()
			local action = state.selectedAction
			if not action then
				return Logger.notify("Select an action first.")
			end

			local delayMs = tonumber(delayBox.Text)
			if not delayMs then
				return Logger.notify("Enter a numeric delay in milliseconds.")
			end

			applyActionDelay(action, math.max(0, math.round(delayMs)))
			ConfigViewerPanel.refresh(false)
			setStatus(string.format("Updated '%s' to %dms.", action.name, math.round(delayMs)))
		end))

		panelMaid:add(tagButton.MouseButton1Click:Connect(function()
			local timing = state.selectedTiming
			if not timing then
				return Logger.notify("Select a saved animation first.")
			end

			local currentIndex = table.find(TAGS, timing.tag or "Undefined") or 1
			local nextIndex = currentIndex + 1
			if nextIndex > #TAGS then
				nextIndex = 1
			end

			timing.tag = TAGS[nextIndex]
			ConfigViewerPanel.refresh(false)
		end))

		panelMaid:add(noDashButton.MouseButton1Click:Connect(function()
			local timing = state.selectedTiming
			if not timing then
				return Logger.notify("Select a saved animation first.")
			end

			timing.ndfb = not timing.ndfb
			ConfigViewerPanel.refresh(false)
		end))

		panelMaid:add(deleteTimingButton.MouseButton1Click:Connect(function()
			local timing = state.selectedTiming
			local container = configAnimationContainer()
			if not timing or not container then
				return Logger.notify("Select a saved animation first.")
			end

			container:remove(timing)
			state.selectedTiming = nil
			state.selectedAction = nil
			ConfigViewerPanel.refresh(true)
			setStatus("Deleted the selected saved timing.")
		end))

		panelMaid:add(deleteActionButton.MouseButton1Click:Connect(function()
			local timing = state.selectedTiming
			local action = state.selectedAction
			if not timing or not action then
				return Logger.notify("Select an action first.")
			end

			timing.actions:remove(action)
			state.selectedAction = nil
			ConfigViewerPanel.refresh(false)
			setStatus("Deleted the selected action.")
		end))

		for actionType, button in next, typeButtons do
			panelMaid:add(button.MouseButton1Click:Connect(function()
				local action = state.selectedAction
				if not action then
					return Logger.notify("Select an action first.")
				end

				action._type = actionType
				ConfigViewerPanel.refresh(false)
				setStatus(string.format("Set '%s' to %s.", action.name, actionType))
			end))
		end

		panelMaid:add(timelineOuter.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end

			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end

			scrubTimeline()
		end))

		panelMaid:add(outer.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end

			if input.KeyCode == Enum.KeyCode.Space then
				playPausePreview()
			elseif input.KeyCode == Enum.KeyCode.Left then
				stepPreview(-0.01)
			elseif input.KeyCode == Enum.KeyCode.Right then
				stepPreview(0.01)
			end
		end))

		panelMaid:add(runService.PreRender:Connect(function()
			updateOuterScale()

			if not screenGui.Enabled then
				return
			end

			updateTimelineVisuals()

			if not currentTrack then
				playButton.Text = "Pause"
				return
			end

			if isPaused then
				currentTrack:AdjustSpeed(0.0)
				playButton.Text = "Play"
				return
			end

			currentTrack:AdjustSpeed(1.0)
			playButton.Text = "Pause"
		end))

		clearPreview()
		isInitialized = true
	end

	function ConfigViewerPanel.detach()
		previewMaid:clean()
		markerMaid:clean()
		actionMaid:clean()
		animationMaid:clean()
		npcMaid:clean()
		bannedMaid:clean()
		panelMaid:clean()
		isInitialized = false
		screenGui.Enabled = false
	end

	return ConfigViewerPanel
end)()