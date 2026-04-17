---@module Features.Combat.Objects.Defender
local Defender = require("Features/Combat/Objects/Defender")

---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Game.Timings.SaveManager
local SaveManager = require("Game/Timings/SaveManager")

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Game.InputClient
local InputClient = require("Game/InputClient")

---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Game.Timings.PlaybackData
local PlaybackData = require("Game/Timings/PlaybackData")

---@module GUI.Library
local Library = require("GUI/Library")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Features.Combat.Objects.RepeatInfo
local RepeatInfo = require("Features/Combat/Objects/RepeatInfo")

---@module Features.Combat.Objects.HitboxOptions
local HitboxOptions = require("Features/Combat/Objects/HitboxOptions")

---@module Features.Combat.Objects.Task
local Task = require("Features/Combat/Objects/Task")

---@module Utility.TaskSpawner
local TaskSpawner = require("Utility/TaskSpawner")

---@module Features.Combat.PositionHistory
local PositionHistory = require("Features/Combat/PositionHistory")

---@module Utility.OriginalStore
local OriginalStore = require("Utility/OriginalStore")

---@module Features.Combat.AttributeListener
local AttributeListener = require("Features/Combat/AttributeListener")

---@class AnimatorDefender: Defender
---@field animator Animator
---@field entity Model
---@field kfmaid Maid
---@field heffects Instance[]
---@field keyframes Action[]
---@field offset number?
---@field timing AnimationTiming?
---@field pbdata table<AnimationTrack, PlaybackData> Playback data to be recorded.
---@field rpbdata table<string, PlaybackData> Recorded playback data. Optimization so we don't have to constantly reiterate over recorded data.
---@field manimations table<number, Animation>
---@field track AnimationTrack? Don't be confused. This is the **valid && last** animation track played.
---@field maid Maid This maid is cleaned up after every new animation track. Safe to use for on-animation-track setup.
local AnimatorDefender = setmetatable({}, { __index = Defender })
AnimatorDefender.__index = AnimatorDefender
AnimatorDefender.__type = "Animation"

-- Services.
local players = game:GetService("Players")

-- Constants.
local MAX_REPEAT_TIME = 5.0
local HISTORY_STEPS = 5.0
local PREDICT_FACING_DELTA = 0.3

---Is animation stopped? Made into a function for de-duplication.
---@param self AnimatorDefender
---@param track AnimationTrack
---@param timing AnimationTiming
---@return boolean
AnimatorDefender.stopped = LPH_NO_VIRTUALIZE(function(self, track, timing)
	if
		Configuration.expectToggleValue("AllowFailure")
		and not timing.umoa
		and not timing.rpue
		and Random.new():NextNumber(1.0, 100.0) <= (Configuration.expectOptionValue("IgnoreAnimationEndRate") or 0.0)
		and AttributeListener.cdash()
	then
		return false, self:notify(timing, "Intentionally ignoring animation end to simulate human error.")
	end

	if not timing.iae and not track.IsPlaying then
		return true, self:notify(timing, "Animation stopped playing.")
	end

	if timing.iae and not timing.ieae and not track.IsPlaying and track.TimePosition < track.Length then
		return true, self:notify(timing, "Animation stopped playing early.")
	end
end)

---Repeat conditional. Extra parameter 'track' added on.
---@param self AnimatorDefender
---@param info RepeatInfo
---@return boolean
AnimatorDefender.rc = LPH_NO_VIRTUALIZE(function(self, info)
	---@note: There are cases where we might not have a track. If it's not handled properly, it will throw an error.
	-- Perhaps, the animation can end and we're handling a different repeat conditional.
	if not info.track then
		return Logger.warn(
			"(%s) Did you forget to pass the track? Or perhaps you forgot to place a hook before using this function.",
			PP_SCRAMBLE_STR(info.timing.name)
		)
	end

	if self:stopped(info.track, info.timing) then
		return false
	end

	if info.timing.iae and os.clock() - info.start >= ((info.timing.mat / 1000) or MAX_REPEAT_TIME) then
		return self:notify(info.timing, "Max animation timeout exceeded.")
	end

	return true
end)

---Run predict facing hitbox check.
---@param self AnimatorDefender
---@param options HitboxOptions
---@return boolean
AnimatorDefender.pfh = LPH_NO_VIRTUALIZE(function(self, options)
	local yrate = PositionHistory.yrate(self.entity)
	if not yrate then
		return false
	end

	local root = self.entity:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local localRoot = players.LocalPlayer.Character and players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not localRoot then
		return false
	end

	if math.abs(yrate) < PREDICT_FACING_DELTA then
		return
	end

	local clone = options:clone()
	clone.spredict = false
	clone.hcolor = Color3.new(0, 1, 1)
	clone.mcolor = Color3.new(1, 1, 0)

	local result = false
	local store = OriginalStore.new()

	store:run(root, "CFrame", CFrame.lookAt(root.Position, localRoot.Position), function()
		result = self:hc(clone, nil)
	end)

	return result
end)

---Run past hitbox check.
---@param timing Timing
---@param options HitboxOptions
---@return boolean
AnimatorDefender.phd = LPH_NO_VIRTUALIZE(function(self, timing, options)
	for _, cframe in next, PositionHistory.stepped(self.entity, HISTORY_STEPS, timing.phds) or {} do
		local clone = options:clone()
		clone.spredict = false
		clone.cframe = cframe
		clone.hcolor = Color3.new(0.839215, 0.976470, 0.537254)
		clone.mcolor = Color3.new(0.564705, 0, 1)

		if not self:hc(clone, nil) then
			continue
		end

		return true
	end
end)

---Get extrapolated seconds.
---@param self Defender
---@param timing AnimationTiming
---@return number
AnimatorDefender.fsecs = LPH_NO_VIRTUALIZE(function(self, timing)
	-- Mashle doesn't expose a per-player ping attribute. Approximate the attacker's
	-- sending delay with our local RTT/2; it's imperfect but avoids a hardcoded 25ms.
	local sd = Defender.rtt() / 2
	return (timing.pfht or 0.15) + (sd + Defender.rdelay())
end)

---Run our facing extrapolation / interpolation.
AnimatorDefender.fpc = LPH_NO_VIRTUALIZE(function(self, timing, options)
	if timing.duih then
		return false
	end

	if timing.pfh and self:pfh(options) then
		return true
	end

	if timing.phd and self:phd(timing, options) then
		return true
	end
end)

---Check if we're in a valid state to proceed with the action.
---@param self AnimatorDefender
---@param timing AnimationTiming
---@param action Action
---@return boolean
AnimatorDefender.valid = LPH_NO_VIRTUALIZE(function(self, timing, action)
	if not Defender.valid(self, timing, action) then
		return false
	end

	if not self.track then
		return self:notify(timing, "No current track.")
	end

	if not self.entity then
		return self:notify(timing, "No entity found.")
	end

	local target = self:target(self.entity)
	if not target then
		return self:notify(timing, "Not a viable target.")
	end

	local root = self.entity:FindFirstChild("HumanoidRootPart")
	if not root then
		return self:notify(timing, "No humanoid root part found.")
	end

	if self:stopped(self.track, timing) then
		return false
	end

	local options = HitboxOptions.new(root, timing)
	options.spredict = not timing.duih and not timing.dp
	options.ptime = self:fsecs(timing)
	options.action = action
	options.entity = self.entity

	local info = RepeatInfo.new(timing)
	info.track = self.track

	local hc = self:hc(options, timing.duih and info or nil)
	if hc then
		return true
	end

	local pc = self:fpc(timing, options)
	if pc then
		return true
	end

	return self:notify(timing, "Not in hitbox.")
end)

---Add a new Keyframe action.
---@param self AnimatorDefender
---@param action Action
---@param tp number
function AnimatorDefender:akeyframe(action, tp)
	-- Set time position.
	action.tp = tp

	---@note: These have to be sent in by a module, so the hitbox and the name also have to get fixed.
	action["_type"] = PP_SCRAMBLE_STR(action["_type"])
	action["name"] = PP_SCRAMBLE_STR(action["name"])
	action["hitbox"] = Vector3.new(
		PP_SCRAMBLE_RE_NUM(action["hitbox"].X),
		PP_SCRAMBLE_RE_NUM(action["hitbox"].Y),
		PP_SCRAMBLE_RE_NUM(action["hitbox"].Z)
	)

	-- Insert in list.
	table.insert(self.keyframes, action)
end

---Get time position of current track.
---@return number?
function AnimatorDefender:tp()
	if not self.track or self.offset == nil then
		return nil
	end

	---@note: Compensate for ping. Convert seconds to time position by adjusting for speed.
	--- Higher speed means it will delay earlier.
	--- Smaller speed means it will delay later.
	return self.track.TimePosition + ((self.offset + self.sdelay()) / self.track.Speed)
end

---Get latest keyframe action that we've exceeded.
---@return Action?
AnimatorDefender.latest = LPH_NO_VIRTUALIZE(function(self)
	local latestKeyframe = nil
	local latestTimePosition = nil

	for _, keyframe in next, self.keyframes do
		if (self:tp() or 0.0) <= keyframe.tp then
			continue
		end

		if latestTimePosition and keyframe.tp <= latestTimePosition then
			continue
		end

		latestTimePosition = keyframe.tp
		latestKeyframe = keyframe
	end

	return latestKeyframe
end)

---Update handling.
---@param self AnimatorDefender
AnimatorDefender.update = LPH_NO_VIRTUALIZE(function(self)
	for track, data in next, self.pbdata do
		-- Don't process tracks.
		if not Configuration.expectToggleValue("ShowAnimationVisualizer") then
			self.pbdata[track] = nil
			continue
		end

		-- Check if the track is playing.
		if not track.IsPlaying then
			-- Remove out of 'pbdata' and put it in to the recorded table.
			self.pbdata[track] = nil
			self.rpbdata[tostring(track.Animation.AnimationId)] = data

			-- Continue to next playback data.
			continue
		end

		-- Start tracking the animation's speed.
		data:astrack(track.Speed)
	end

	-- Run on validated track & timing.
	if not self.track or not self.timing then
		return
	end

	if not self.track.IsPlaying then
		return
	end

	-- Find the latest keyframe that we have exceeded, if there is even any.
	local latest = self:latest()
	if not latest then
		return
	end

	-- Clear the keyframes that we have exceeded.
	local tp = self:tp() or 0.0

	for idx, keyframe in next, self.keyframes do
		if tp <= keyframe.tp then
			continue
		end

		self.keyframes[idx] = nil
	end

	-- Log.
	self:notify(
		self.timing,
		"(%.2f) (really %.2f) Keyframe action '%s' with type '%s' is being executed.",
		tp,
		self.track.TimePosition,
		PP_SCRAMBLE_STR(latest.name),
		PP_SCRAMBLE_STR(latest._type)
	)

	-- Ok, run action of this keyframe.
	self.maid:mark(
		TaskSpawner.spawn(
			string.format("KeyframeAction_%s", PP_SCRAMBLE_STR(latest._type)),
			self.handle,
			self,
			self.timing,
			latest,
			false
		)
	)
end)

---Virtualized processing checks.
---@param track AnimationTrack
---@return boolean
function AnimatorDefender:pvalidate(track)
	if track.Priority == Enum.AnimationPriority.Core then
		return false
	end

	return true
end

---Process animation track.
---@todo: AP telemetry - aswell as tracking effects that are added with timestamps and current ping to that list.
---@param self AnimatorDefender
---@param track AnimationTrack
AnimatorDefender.process = LPH_NO_VIRTUALIZE(function(self, track)
	if players.LocalPlayer.Character and self.entity == players.LocalPlayer.Character then
		return
	end

	if not self:pvalidate(track) then
		return
	end

	-- Clean up Keyframe maid.
	self.kfmaid:clean()

	-- Add to playback data list.
	if Configuration.expectToggleValue("ShowAnimationVisualizer") then
		self.pbdata[track] = PlaybackData.new(self.entity)
	end

	-- Animation ID.
	local aid = tostring(track.Animation.AnimationId)

	-- In logging range?
	local distance = self:distance(self.entity)
	local ilr = distance
		and (
			distance >= (Configuration.expectOptionValue("MinimumLoggerDistance") or 0)
			and distance <= (Configuration.expectOptionValue("MaximumLoggerDistance") or 0)
		)

	-- Keyframe logging.
	local keyframeReached = Signal.new(track.KeyframeReached)

	self.kfmaid:add(keyframeReached:connect("AnimationDefender_OnKeyFrameReached", function(kfname)
		if not ilr then
			return
		end

		Library:AddKeyFrameEntry(distance, aid, kfname, track.TimePosition, false)
	end))

	---@type AnimationTiming?
	local timing = self:initial(self.entity, SaveManager.as, self.entity.Name, aid)
	if not timing then
		return
	end

	if ilr then
		Library:AddExistAnimEntry(self.entity.Name, distance, timing)
	end

	if not Configuration.expectToggleValue("EnableAutoDefense") then
		return
	end

	local humanoidRootPart = self.entity:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	---@note: Clean up previous tasks that are still waiting or suspended because they're in a different track.
	self:clean()

	-- Set current data.
	self.timing = timing
	self.track = track
	self.offset = self.rdelay()

	-- Fake mistime rate.
	---@type Action?
	local _, faction = next(timing.actions._data)

	-- Obviously, we don't want any modules where we don't know how many actions there are.
	-- We don't want any actions that have a count that is not equal to 1.
	-- We need to check if we can atleast dash, because we will be going to are fallback.
	-- We must also check if our action isn't too short or is not a parry type, defeating the purpose.
	if
		Configuration.expectToggleValue("AllowFailure")
		and not timing.umoa
		and not timing.rpue
		and timing.actions:count() == 1
		and Random.new():NextNumber(1.0, 100.0) <= (Configuration.expectOptionValue("FakeMistimeRate") or 0.0)
		and AttributeListener.cdash()
		and faction
		and PP_SCRAMBLE_STR(faction._type) == "Parry"
		and faction:when() > (self.rtt() + 0.6)
	then
		InputClient.deflect()

		self:notify(timing, "Intentionally mistimed to simulate human error.")
	end

	-- Use module over actions.
	if timing.umoa then
		return self:module(timing)
	end

	---@note: Start processing the timing. Add the actions if we're not RPUE.
	if not timing.rpue then
		return self:actions(timing)
	end

	-- Start RPUE.
	local info = RepeatInfo.new(timing, self.rdelay())
	info.track = track

	self:mark(Task.new(string.format("RPUE_%s_%i", timing.name, 0), function()
		return timing:rsd() - info.irdelay - self.sdelay()
	end, timing.punishable, timing.after, self.rpue, self, self.entity, timing, info))

	-- Notify.
	if not LRM_UserNote or LRM_UserNote == "tester" then
		self:notify(
			timing,
			"Added RPUE '%s' (%.2fs, then every %.2fs) with ping '%.2f' (changing) subtracted.",
			PP_SCRAMBLE_STR(timing.name),
			timing:rsd(),
			timing:rpd(),
			self.rtt()
		)
	else
		self:notify(
			timing,
			"Added RPUE '%s' ([redacted], then every [redacted]) with ping '%.2f' (changing) subtracted.",
			PP_SCRAMBLE_STR(timing.name),
			self.rtt()
		)
	end
end)

---Clean up the defender.
function AnimatorDefender:clean()
	-- Empty data.
	self.keyframes = {}
	self.heffects = {}

	-- Empty Keyframe maid.
	self.kfmaid:clean()

	-- Clean through base method.
	Defender.clean(self)
end

---Create new AnimatorDefender object.
---@param animator Animator
---@return AnimatorDefender
function AnimatorDefender.new(animator)
	local entity = animator:FindFirstAncestorWhichIsA("Model")
	if not entity then
		return error(string.format("AnimatorDefender.new(%s) - no entity.", animator:GetFullName()))
	end

	local self = setmetatable(Defender.new(), AnimatorDefender)
	local animationPlayed = Signal.new(animator.AnimationPlayed)

	self.animator = animator
	self.entity = entity
	self.kfmaid = Maid.new()

	self.track = nil
	self.timing = nil
	self.rdelay = nil

	self.heffects = {}
	self.keyframes = {}
	self.pbdata = {}
	self.rpbdata = {}

	self.maid:mark(animationPlayed:connect(
		"AnimatorDefender_OnAnimationPlayed",
		LPH_NO_VIRTUALIZE(function(track)
			self:process(track)
		end)
	))

	return self
end

-- Return AnimatorDefender module.
return AnimatorDefender
