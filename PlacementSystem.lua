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

-- Configuration
local GRID_SIZE = 10
local MAX_DISTANCE = 1000
local GRID_TEXTURE_ID = "rbxassetid://71966238444315"

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
	self.CanPlace = true
	
	return self
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

-- Functions that performs a raycast from the mouse position to find a valid surface
function PlacementSystem:GetMouseTarget()
	local mousePos = UIS:GetMouseLocation()
	local viewportRay = workspace.CurrentCamera:ViewportPointToRay(mousePos.X, mousePos.Y)
	
	local filterList = { self.PreviewModel, plr.Character }
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { filterList }
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true
	
	local result = workspace:Raycast(viewportRay.Origin, viewportRay.Direction * MAX_DISTANCE, raycastParams)
	
	if result then
		return result.Position, result.Instance, result.Normal
	else
		local t = -viewportRay.Origin.Y / viewportRay.Direction.Y
		
		if t > 0 then
			local hitPoint = viewportRay.Origin + viewportRay.Direction * t
			return hitPoint, nil, Vector3.new(0, 1, 0)
		end
	end
	
	return viewportRay.Origin + (viewportRay.Direction * MAX_DISTANCE), nil, Vector3.new(0, 1, 0)
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

-- Function to handle the input for rotation, activation and object placement
function PlacementSystem:HandleInput(input, gp)
	if gp then return end
	
	if input.KeyCode == Enum.KeyCode.E then
		self:Activate("Model1")
		return
	end
	
	if self.IsActive then
		if input.KeyCode == Enum.KeyCode.R then
			self.CurrentRotation = (self.CurrentRotation + 90) % 360
		end
		
		if input.KeyCode == Enum.KeyCode.Q then
			self.CurrentRotation = (self.CurrentRotation - 90) % 360
		end
		
		if input.KeyCode == Enum.KeyCode.X then
			self:Deactivate()
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if self.CanPlace then
				self:PlaceObject()
			else
				print("Cannot place!")
			end
		end
	end
end

-- Update called every frame.
-- It calculates the target position, rotation, and checks for collisions.
function PlacementSystem:Update()
	if not self.IsActive or not self.PreviewModel then return end
	
	local targetPos, targetPart, targetNormal = self:GetMouseTarget()
	local snappedPos = self:CalculateGrid(targetPos)
	
	-- Normal.Y > 0.9 to ensure the surface is flat enough to place on
	local isGround = targetPart ~= nil and targetNormal.Y > 0.9
	
	local modelSize = self.PreviewModel:GetExtentsSize()
	
	-- Construct the CFrame for the preview model
	local finalCFrame = CFrame.new(snappedPos + Vector3.new(0, modelSize.Y / 2, 0))
		* CFrame.Angles(0, math.rad(self.CurrentRotation), 0)
	
	-- Lerp the preview model to the target position with a smooth transition
	self.PreviewModel:PivotTo(self.PreviewModel:GetPivot():Lerp(finalCFrame, 0.2))
	
	self:CheckCollisions(isGround)
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
end

-- Function that cleans the preview up and resets state
function PlacementSystem:Deactivate()
	self.IsActive = false
	
	if self.PreviewModel then
		self.PreviewModel:Destroy()
		self.PreviewModel = nil
	end
	
	self:ToggleVisualGrid(false)
end

-- Initializes the system
local system = PlacementSystem.new()

UIS.InputBegan:Connect(function(input, gp)
	system:HandleInput(input, gp)
end)

plr.CharacterAdded:Connect(function()
	system:Deactivate()
end)

RunService.RenderStepped:Connect(function()
	system:Update()
end)