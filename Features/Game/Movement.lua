---@module Utility.Configuration
local Configuration = require("Utility/Configuration")

---@module Utility.OriginalStoreManager
local OriginalStoreManager = require("Utility/OriginalStoreManager")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Features.Exploits.Exploits
local Exploits = require("Features/Exploits/Exploits")

-- Maids.
local movementMaid = Maid.new()

-- Services.
local players = game:GetService("Players")

return LPH_NO_VIRTUALIZE(function()
	-- Movement related stuff is handled here.
	local Movement = {}

	---@module Utility.Signal
	local Signal = require("Utility/Signal")

	---@module Utility.InstanceWrapper
	local InstanceWrapper = require("Utility/InstanceWrapper")

	---@module Utility.OriginalStore
	local OriginalStore = require("Utility/OriginalStore")

	---@module Utility.ControlModule
	local ControlModule = require("Utility/ControlModule")

	---@module Utility.Logger
	local Logger = require("Utility/Logger")

	---@module Utility.Entitites
	local Entitites = require("Utility/Entitites")

	-- Services.
	local runService = game:GetService("RunService")
	local userInputService = game:GetService("UserInputService")

	-- Original stores.
	local agilitySpoofer = movementMaid:mark(OriginalStore.new())

	-- Original store managers.
	local noClipMap = movementMaid:mark(OriginalStoreManager.new())

	-- Signals.
	local preSimulation = Signal.new(runService.PreSimulation)

	-- Debounce.
	local flashStepDebounce = false

	-- State.
	local lastPosition = nil

	---Update noclip.
	---@param character Model
	---@param rootPart BasePart
	local function updateNoClip(character, rootPart)
		for _, instance in pairs(character:GetChildren()) do
			if not instance:IsA("BasePart") then
				continue
			end

			noClipMap:add(instance, "CanCollide", false)
		end
	end

	---Update speed hack.
	---@param rootPart BasePart
	---@param humanoid Humanoid
	local function updateSpeedHack(rootPart, humanoid)
		if Configuration.expectToggleValue("Fly") then
			return
		end

		rootPart.AssemblyLinearVelocity = rootPart.AssemblyLinearVelocity * Vector3.new(0, 1, 0)

		local moveDirection = humanoid.MoveDirection
		if moveDirection.Magnitude <= 0.001 then
			return
		end

		rootPart.AssemblyLinearVelocity = rootPart.AssemblyLinearVelocity
			+ moveDirection.Unit * Configuration.expectOptionValue("SpeedhackSpeed")
	end

	---Update infinite jump.
	---@param rootPart BasePart
	local function updateInfiniteJump(rootPart)
		if Configuration.expectToggleValue("Fly") then
			return
		end

		if not userInputService:IsKeyDown(Enum.KeyCode.Space) then
			return
		end

		rootPart.AssemblyLinearVelocity = rootPart.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
		rootPart.AssemblyLinearVelocity = rootPart.AssemblyLinearVelocity
			+ Vector3.new(0, Configuration.expectOptionValue("InfiniteJumpBoost"), 0)
	end

	---Update fly hack.
	---@param rootPart BasePart
	---@param humanoid Humanoid
	local function updateFlyHack(rootPart, humanoid)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		local flyBodyVelocity = InstanceWrapper.create(movementMaid, "flyBodyVelocity", "BodyVelocity", rootPart)
		flyBodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)

		local flyVelocity = camera.CFrame:VectorToWorldSpace(
			ControlModule.getMoveVector() * Configuration.expectOptionValue("FlySpeed")
		)

		if userInputService:IsKeyDown(Enum.KeyCode.Space) then
			flyVelocity = flyVelocity + Vector3.new(0, Configuration.expectOptionValue("FlyUpSpeed"), 0)
		end

		flyBodyVelocity.Velocity = flyVelocity
	end

	---Update agility spoofer.
	---@param character Model
	local function updateAgilitySpoofer(character)
		local agility = character:FindFirstChild("Agility")
		if not agility then
			return
		end

		---@note: For every 10 investment points, there are two real agility points.
		-- With 40 investment points, we can have 16 real agility points.
		-- However, with 30 investment points, we can only have 14 real agility points.
		-- This means that the starting value must be 8 and we must increase by 2 for every point we have.
		local agilitySpoofValue = 8 + (Options.AgilitySpoof.Value / 10) * 2

		if Toggles.BoostAgilityDirectly.Value then
			agilitySpoofValue = Options.AgilitySpoof.Value
		end

		agilitySpoofer:set(agility, "Value", agilitySpoofValue)
	end

	---Update attach to back.
	---@param rootPart BasePart
	local function updateAttachToBack(rootPart)
		local attachTarget = Entitites.findNearestEntity(200)
		if not attachTarget then
			return
		end

		local attachTargetHrp = attachTarget:FindFirstChild("HumanoidRootPart")
		if not attachTargetHrp then
			return
		end

		local offsetCFrame = CFrame.new(
			0.0,
			Configuration.expectOptionValue("HeightOffset"),
			Configuration.expectOptionValue("BackOffset")
		)

		rootPart.CFrame = rootPart.CFrame:Lerp(attachTargetHrp.CFrame * offsetCFrame, 0.3)
	end

	---Update no slow.
	---@param character Model
	---@param humanoid Humanoid
	local function updateNoSlow(character, humanoid)
		if humanoid.WalkSpeed == 4 or humanoid.WalkSpeed == 0 then
			humanoid.WalkSpeed = character:GetAttribute("BaseWalkspeed")
		end

		if humanoid.JumpHeight == 0 then
			humanoid.JumpHeight = character:GetAttribute("BaseJumpheight")
		end
	end

	---Update flash step.
	---@param character Model
	---@param humanoid Humanoid
	local function updateFlashstepSpeedBoost(character, humanoid)
		local isFlashstep = character:GetAttribute("CurrentState") == "Flashstep"

		if flashStepDebounce and not isFlashstep then
			flashStepDebounce = false
		end

		if flashStepDebounce then
			return
		end

		if not isFlashstep then
			return
		end

		flashStepDebounce = true

		humanoid.WalkSpeed = humanoid.WalkSpeed * (Configuration.expectOptionValue("FlashStepSpeedBoostMulti") or 1.0)
	end

	---Update movement.
	local function updateMovement()
		local localPlayer = players.LocalPlayer
		local character = localPlayer.Character
		if not character then
			return
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			return
		end

		local humanoid = character:FindFirstChild("Humanoid")
		if not humanoid then
			return
		end

		if not Configuration.expectToggleValue("AnchorCharacter") then
			lastPosition = rootPart.CFrame
		end

		if Configuration.expectToggleValue("AnchorCharacter") and lastPosition then
			rootPart.CFrame = lastPosition
		end

		if Configuration.expectToggleValue("FlashstepSpeedBoost") then
			updateFlashstepSpeedBoost(character, humanoid)
		end

		if Configuration.expectToggleValue("NoSlow") then
			updateNoSlow(character, humanoid)
		end

		if Configuration.expectToggleValue("AttachToBack") then
			updateAttachToBack(rootPart)
		end

		if Configuration.expectToggleValue("Fly") then
			updateFlyHack(rootPart, humanoid)
		else
			movementMaid["flyBodyVelocity"] = nil
		end

		if Configuration.expectToggleValue("NoClip") then
			updateNoClip(character, rootPart)
		else
			noClipMap:restore()
		end

		if Configuration.expectToggleValue("Speedhack") then
			updateSpeedHack(rootPart, humanoid)
		end

		if Configuration.expectToggleValue("InfiniteJump") then
			updateInfiniteJump(rootPart)
		end

		if Configuration.expectToggleValue("AgilitySpoof") then
			updateAgilitySpoofer(character)
		else
			agilitySpoofer:restore()
		end
	end

	---Initialize movement.
	function Movement.init()
		-- Attach.
		movementMaid:add(preSimulation:connect("Movement_PreSimulation", updateMovement))

		-- Log.
		Logger.warn("Movement initialized.")
	end

	---Detach movement.
	function Movement.detach()
		-- Clean.
		movementMaid:clean()

		-- Log.
		Logger.warn("Movement detached.")
	end

	-- Return Movement module.
	return Movement
end)()
