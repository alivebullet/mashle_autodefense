-- Features related stuff is handled here.
local Features = {}

---@module Features.Game.Movement
local Movement = require("Features/Game/Movement")

---@module Features.Visuals.Visuals
local Visuals = require("Features/Visuals/Visuals")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Features.Combat.Defense
local Defense = require("Features/Combat/Defense")

---@module Features.Game.AnimationVisualizer
local AnimationVisualizer = require("Features/Game/AnimationVisualizer")

---@module Features.Game.AnimationLogger
local AnimationLogger = require("Features/Game/AnimationLogger")

---@modules Features.Combat.AttributeListener
local AttributeListener = require("Features/Combat/AttributeListener")

---@module Features.Game.Monitoring
local Monitoring = require("Features/Game/Monitoring")

---@module Features.Game.OwnershipWatcher
local OwnershipWatcher = require("Features/Game/OwnershipWatcher")

---@module Features.Exploits.Exploits
local Exploits = require("Features/Exploits/Exploits")

---@module Features.Game.Removal
local Removal = require("Features/Game/Removal")

---@module Features.Automation.Input
local Input = require("Features/Automation/Input")

---Initialize features.
---@note: Careful with features that have entire return LPH_NO_VIRTUALIZE(function() blocks. We assume that we don't care about what's placed in there.
function Features.init()
	Monitoring.init()
	AttributeListener.init()
	Defense.init()
	Visuals.init()
	Movement.init()
	OwnershipWatcher.init()
	Exploits.init()
	Removal.init()
	Input.init()
	AnimationVisualizer.init()
	AnimationLogger.init()

	Logger.warn("Features initialized.")
end

---Detach features.
function Features.detach()
	AnimationVisualizer.detach()
	AnimationLogger.detach()

	Monitoring.detach()
	AttributeListener.detach()
	Defense.detach()
	Movement.detach()
	Visuals.detach()
	OwnershipWatcher.detach()
	Exploits.detach()
	Removal.detach()
	Input.detach()

	Logger.warn("Features detached.")
end

-- Return Features module.
return Features
