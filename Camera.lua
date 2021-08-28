--[[
	First person camera module
	
	API
	
	camera = Camera.new() - constructs a new camera class
	camera.camera = workspace.Camera -- the camera
	camera.position = V3 relative position of the camera
	camera.stiffness = the sway of the camera
	camera.relativeTo = part that the camera is relative to
	camera.zoom.f = zoom stiffness
	camera.zoom.p = zoom FOV
	camera.targetZoomFOV = target zoom FOV
	camera.rotation = rotation
	camera.rotationSpeed = rotation speed
	camera.headSwaySize = head sway distance per 1 stud/s^2 acceleration
	camera:update() 
--]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Modules
local Spring = require(ReplicatedStorage.Modules.Spring)

-- Module
local Camera = {}
Camera.__index = Camera

function Camera.new()
	local self = setmetatable({}, Camera)
	self.headSway = Spring.new(0, Vector3.new())
	self.rotateInput = Spring.new(0, Vector2.new())
	self.zoom = Spring.new(1.5, 70)
	self.targetZoomFOV = 70

	return self
end

function Camera:Update(dt)
	local relativeTo = self.relativeTo
	if not relativeTo then
		return false
	end
	
	-- Configure camera
	if self.camera.CameraType ~= Enum.CameraType.Scriptable then
		self.camera.CameraType = Enum.CameraType.Scriptable
	end
	
	-- Configure springs
	self.headSway.f = self.stiffness
	self.rotateInput.f = self.stiffness
	
	-- Head sway
	local acceleration = Vector3.new()
	local relativeVelocity = relativeTo.WorldCFrame:vectorToObjectSpace(relativeTo.Parent.Velocity)
	if self.relativeVelocity then
		acceleration = relativeVelocity - self.relativeVelocity
	end
	local tickValue = os.clock() * self.headOscillationRate
	local headSway = self.headSway:Update(dt, -acceleration * self.headSwaySize + Vector3.new(math.sin(tickValue), math.cos(tickValue), 0) * dt * self.headOscillationSize) 
	headSway = Vector3.new(
		math.clamp(headSway.X, -self.maxHeadSway.X, self.maxHeadSway.X),
		math.clamp(headSway.Y, -self.maxHeadSway.Y, self.maxHeadSway.Y),
		math.clamp(headSway.Z, -self.maxHeadSway.Z, self.maxHeadSway.Z)
	)
	
	-- Update zoom FOV
	self.camera.FieldOfView = self.zoom:Update(dt, self.targetZoomFOV)
	
	-- Get rotate input
	local mouseDelta = Vector2.new()
	local pressed = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	if pressed then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		mouseDelta = UserInputService:GetMouseDelta()
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	local rotateInput = self.rotateInput:Update(dt, mouseDelta)
	self.rotation = self.rotation + rotateInput * self.rotationSpeed
	
	-- Set camera CFrame
	local rotationCFrame = CFrame.Angles(0, -self.rotation.X, 0) * CFrame.Angles(-self.rotation.Y, 0, 0)
	self.camera.CFrame = relativeTo.WorldCFrame * CFrame.new(self.position + headSway) * rotationCFrame
	
	-- Set velocity
	self.relativeVelocity = relativeVelocity
end

return Camera