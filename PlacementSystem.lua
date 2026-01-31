--[[
	Placement system
	
	Author: WillyFromBelair (cri.corda)
	
	Description:
	A placement system with grid snapping and collision detection.
	Features include also object rotation, surface validation (so the object cannot be placed in air),
	dynamic visual feedback (color change of the object based on if it is placeable or not), grid visual layout
]]

-- Services
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CAS = game:GetService("ContextActionService")

-- Configuration
local GRID_SIZE = 10
local MAX_DISTANCE = 1000
local GRID_TEXTURE_ID = "rbxassetid://71966238444315"
local SPRING_STIFFNESS = 15
local SPRING_DAMPING = 0.6

-- Variables
local plr = Players.LocalPlayer
local assets = ReplicatedStorage:WaitForChild("Assets")

local PlacementSystem = {}
PlacementSystem.__index = PlacementSystem

-- Initializes the placement system
function PlacementSystem.new()
	local self = setmetatable({}, PlacementSystem)
	
	self.IsActive = false
	self.PreviewModel = nil
	self.VisualGrid = nil
	self.CurrentModelName = ""
	self.CurrentRotation = 0
	self.VisualRotation = 0
	self.CanPlace = true
	
	self.TargetCFrame = CFrame.new()
	self.CurrentCFrame = CFrame.new()
	self.Velocity = Vector3.new()
	
	self.ShakeOffset = Vector3.new()
	
	return self
end

--[[
	Function that calculates and applies spring-dampened motion to the preview model
	This is used to handle position smoothing, rotation interpolation and invalid-state shaking
]]
function PlacementSystem:ApplySpring(dt)
	-- Position smoothing via spring
	local displacement = (self.TargetCFrame.Position - self.CurrentCFrame.Position)
	local force = displacement * SPRING_STIFFNESS
	self.Velocity = (self.Velocity * SPRING_DAMPING) + (force * dt)
	
	-- Smooth rotation interpolation
	local rotationSpeed = 15
	self.VisualRotation = math.lerp(self.VisualRotation, self.CurrentRotation, math.clamp(dt * rotationSpeed, 0, 1))
	
	local shake = Vector3.new()
	
	-- Shake effect when attempting to place in an invalid location
	if not self.CanPlace and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		shake = Vector3.new(math.random(-2, 2) / 10, 0, math.random(-2, 2) / 10)
	end
	
	local newPos = self.CurrentCFrame.Position + self.Velocity + shake
	
	local rotationCFrame = CFrame.Angles(0, math.rad(self.VisualRotation), 0)
	self.CurrentCFrame = CFrame.new(newPos) * rotationCFrame
end

-- Function that calculates the final CFrame based on grid snapping and surface normals
function PlacementSystem:CalculatePlacementCFrame(pos, normal)
	local snappedX = math.round(pos.X / GRID_SIZE) * GRID_SIZE
	local snappedZ = math.round(pos.Z / GRID_SIZE) * GRID_SIZE
	
	local modelSize = self.PreviewModel:GetExtentsSize()
	
	local heightOffset = normal * (modelSize.Y / 2)
	
	return CFrame.new(Vector3.new(snappedX, pos.Y, snappedZ) + heightOffset)
end

-- Function to create or remove the visual grid overlay
function PlacementSystem:ToggleVisualGrid(state)
	if state then
		local gridPart = Instance.new("Part")
		gridPart.Name = "VisualGridOverlay"
		gridPart.Size = Vector3.new(MAX_DISTANCE * 2, 0.1, MAX_DISTANCE * 2)
		gridPart.Anchored = true
		gridPart.CanCollide = false
		gridPart.CanTouch = false
		gridPart.CastShadow = false
		gridPart.Transparency = 1
		
		gridPart.Position = Vector3.new(plr.Character.PrimaryPart.Position.X, 0.05, plr.Character.PrimaryPart.Position.Z)
		
		local texture = Instance.new("Texture")
		texture.Texture = GRID_TEXTURE_ID
		texture.Face = Enum.NormalId.Top
		texture.StudsPerTileU = GRID_SIZE
		texture.StudsPerTileV = GRID_SIZE
		texture.Transparency = 0.6
		texture.Parent = gridPart

		gridPart.Parent = workspace
		self.VisualGrid = gridPart
	else
		if self.VisualGrid then
			self.VisualGrid:Destroy()
			self.VisualGrid = nil
		end
	end
end

-- This function calculates the position on the grid (snap to grid)
function PlacementSystem:CalculateGrid(pos)
	local x = math.round(pos.X / GRID_SIZE) * GRID_SIZE
	local z = math.round(pos.Z / GRID_SIZE) * GRID_SIZE
	
	return Vector3.new(x, pos.Y, z)
end

-- Function that determines the input source (Mouse or Touch) and returns the 2D screen position.
function PlacementSystem:GetInputLocation()
	if UIS.TouchEnabled and not UIS.MouseEnabled then
		if UIS:GetLastInputType() == Enum.UserInputType.Touch then
			return UIS:GetMouseLocation()
		end
		
		local viewportSize = workspace.CurrentCamera.ViewportSize
		return Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
	end
	return UIS:GetMouseLocation()
end

-- Functions that performs a raycast from the mouse position to find a valid surface
function PlacementSystem:GetMouseTarget()
	local inputPos = self:GetInputLocation()
	local viewportRay = workspace.CurrentCamera:ViewportPointToRay(inputPos.X, inputPos.Y)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {self.PreviewModel, plr.Character}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(viewportRay.Origin, viewportRay.Direction * MAX_DISTANCE, raycastParams)

	if result then
		return result.Position, result.Instance, result.Normal
	end
	return nil
end

-- Function that checks for collisions
function PlacementSystem:CheckCollisions(isGround)
	if not self.PreviewModel then return end
	
	local params = OverlapParams.new()
	params.FilterDescendantsInstances = {
		self.PreviewModel,
		plr.Character
	}
	params.FilterType = Enum.RaycastFilterType.Exclude
	
	local touchingParts = workspace:GetPartsInPart(self.PreviewModel.PrimaryPart or self.PreviewModel:FindFirstChildWhichIsA("BasePart"), params)
	
	-- Placement is valid only if no collisions occur and the object is on the ground
	self.CanPlace = (#touchingParts == 0 and isGround)
	
	local targetColor = Color3.fromRGB(255)
	
	if self.CanPlace then
		targetColor = Color3.fromRGB(0, 255)
	elseif not isGround and #touchingParts == 0 then
		targetColor = Color3.fromRGB(255, 255)
	end
	
	for _, part in ipairs(self.PreviewModel:GetDescendants()) do
		if part:IsA("BasePart") then
			TweenService:Create(
				part,
				TweenInfo.new(0.2),
				{ Color = targetColor}
			):Play()
		end
	end
end

-- Function to place the object by cloning the template and restoring its properties
-- Places the object on the desired position and orientation, both chosen in "preview model" mode
function PlacementSystem:PlaceObject()
	if not self.PreviewModel or not self.CanPlace then return end
	
	local template = assets:FindFirstChild(self.CurrentModelName)
	if not template then return end
	
	local finalModel = template:Clone()
	
	for _, part in ipairs(finalModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 0
			part.CanCollide = true
			part.Anchored = true
		end
	end
	
	finalModel:PivotTo(self.PreviewModel:GetPivot())
	finalModel.Parent = workspace
end

-- Action handlers for ContextActionService

-- Function to handle the input for rotation, activation and object placement
function PlacementSystem:HandleRotation(actionName, inputState, inputObject)
	if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	
	if actionName == "RotateAction" then
		self.CurrentRotation += 90
	elseif actionName == "RotateActionCounter" then
		self.CurrentRotation -= 90
	end
	return Enum.ContextActionResult.Pass
end

function PlacementSystem:HandleCancel(actionName, inputState, inputObject)
	if inputState == Enum.UserInputState.Begin then
		self:Deactivate()
	end
	return Enum.ContextActionResult.Pass
end

function PlacementSystem:HandlePlace(actionName, inputState, inputObject)
	if inputState == Enum.UserInputState.Begin then
		if self.CanPlace then
			self:PlaceObject()
		else
			self.Velocity = self.Velocity + Vector3.new(0, 5, 0)
		end
	end
	return Enum.ContextActionResult.Pass
end

function PlacementSystem:HandleInput(input, gp)
	if gp then return end
	
	if input.KeyCode == Enum.KeyCode.E and not self.IsActive then
		self:Activate("Model1")
	end
end

-- Update called via RenderStepped.
-- It calculates the target position, rotation, and checks for collisions.
function PlacementSystem:Update(dt)
	if not self.IsActive or not self.PreviewModel then return end

	local pos, hitInstance, normal = self:GetMouseTarget()
	
	local charPos = plr.Character and plr.Character.PrimaryPart and plr.Character.PrimaryPart.Position
	local distance = charPos and pos and (charPos - pos).Magnitude or 0
	
	-- Ensure normal is valid and surface is facing upwards
	local isTopFace = normal and normal.Y > 0.9
	
	if not pos or not normal or distance > MAX_DISTANCE or not isTopFace then
		self.TargetCFrame = plr.Character.PrimaryPart.CFrame * CFrame.new(0, 0, -10)
		self:ApplySpring(dt)
		self.PreviewModel:PivotTo(self.CurrentCFrame)
		
		self.CanPlace = false
		self:CheckCollisions(false)
		return
	end
	
	self.TargetCFrame = self:CalculatePlacementCFrame(pos, normal)
	self:ApplySpring(dt)

	self.PreviewModel:PivotTo(self.CurrentCFrame)
	self:CheckCollisions(hitInstance ~= nil)
end

-- Function to activate the system for a specific model
function PlacementSystem:Activate(modelName)
	if self.IsActive then return end
	
	if self.PreviewModel then
		self.PreviewModel:Destroy()
	end
	
	local template = assets:FindFirstChild(modelName)
	
	if not template then
		warn(`Model not found in Assets: {modelName}`)
		return
	end
	
	self.CurrentModelName = modelName
	self.PreviewModel = template:Clone()
	
	-- Prepares preview visual state
	for _, part in ipairs(self.PreviewModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 0.5
			part.CanCollide = false
			part.Anchored = true
			part.CastShadow = false
		end
	end
	
	self.PreviewModel.Parent = workspace
	self.IsActive = true
	self.CurrentRotation = 0
	
	self:ToggleVisualGrid(true)
	
	-- Bind cross-platform actions
	CAS:BindAction("RotateAction", function(...) return self:HandleRotation(...) end, true, Enum.KeyCode.R, Enum.KeyCode.ButtonX)
	CAS:BindAction("RotateActionCounter", function(...) return self:HandleRotation(...) end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
	CAS:BindAction("CancelAction", function(...) return self:HandleCancel(...) end, true, Enum.KeyCode.X, Enum.KeyCode.ButtonB)
	CAS:BindAction("PlaceAction", function(...) return self:HandlePlace(...) end, true, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch, Enum.KeyCode.ButtonR2)

	if UIS.TouchEnabled then
		CAS:SetTitle("RotateAction", "Rotate ->")
		CAS:SetTitle("RotateActionCounter", "<- Rotate")
		CAS:SetTitle("CancelAction", "Exit")
		CAS:SetTitle("PlaceAction", "Place")
	end
end

-- Function that cleans the preview up and resets state
function PlacementSystem:Deactivate()
	self.IsActive = false
	
	if self.PreviewModel then
		self.PreviewModel:Destroy()
		self.PreviewModel = nil
	end
	
	self:ToggleVisualGrid(false)
	
	CAS:UnbindAction("RotateAction")
	CAS:UnbindAction("RotateActionCounter")
	CAS:UnbindAction("CancelAction")
	CAS:UnbindAction("PlaceAction")
end

-- Initializes the system
local system = PlacementSystem.new()

UIS.InputBegan:Connect(function(input, gp)
	system:HandleInput(input, gp)
end)

plr.CharacterAdded:Connect(function()
	system:Deactivate()
end)

RunService.RenderStepped:Connect(function(dt)
	system:Update(dt)
end)
