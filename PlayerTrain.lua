--[[
	PlayerTrain - returns the train object for the current train

	API
	
	.new()
	
	.self.config = settings required from settings module (table)
	.speedLimit = speed limit displayed on the UI (integer)
	._throttleLocked = whether throttle is locked or not (bool)
	.speed = speed in the Z axis (number)
	.throttle = -1 to 1 (decimal)
	.direction = -1 or 1
	.AWS = whether AWS warning should be lit (bool)
	.timetable
	
	:SetActualThrottle(t)
	:UpdatePhysics()
	:IncrementThrottle()
	:DecrementThrottle()
	:UpdateCamera(dt)
	:ChangeCameraMode(view)
	:NextCameraMode()
	:EmergencyStop(event)
	:NewSensor(part, func)
	:UpdateSensorsWithinRadius(radius)
	:StartHorn(hornType)
	:StopHorn(hornType)
	:WarnAWS()
	:AcknowledgeAWS()
	:ClearAWS()
	:ToggleDoors()
	:SetLights(day, forward)
	:SetInitialRoute(route, startPoint)
	:IgnoreTrackNames(list)
	:FollowTrackNames(list)
	:IncrementNextStop()
	:GetTrackIgnoreList()
--]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Modules
local Camera = require(ReplicatedStorage.Modules.Camera)
local Sensor = require(ReplicatedStorage.Modules.Sensor)
local Thread = require(ReplicatedStorage.Modules.Thread)
local Switch = require(ReplicatedStorage.Modules.Switch)
local deepCopy = require(ReplicatedStorage.Functions.DeepCopy)

-- Constants:

-- General
local TRAIN_LOAD_TIMEOUT = 600

-- Controls
local MINIMUM_DESIRED_THROTTLE = 0.01
local DEFAULT_THROTTLE = -1
local DEFAULT_SPEED = 0
local DEFAULT_DIRECTION = 1
local EMERGENCY_THROTTLE = -1.6

-- Physics
local ACTIVE_TRACK = workspace.Track
local INACTIVE_TRACK = workspace:FindFirstChild("InactiveTrack") or Instance.new("Folder")
local BODYGYRO_INTERPOLATION = 0.15
local AWS_WARN_TIME = 6
local RAY_LENGTH = 20
local MAX_DERAIL_COUNT = 200
local DOORS_MIN_OPEN = 20
local DEFAULT_SPEED_LIMIT = 5
local GUIDE_PART_NAME = "Rails"
local GRAVITATIONAL_CONSTANT = 9.8
local REVERSE_CFRAME = CFrame.Angles(0, math.pi, 0)

-- Camera
local FIRST_PERSON_ZOOM_SPEED = 5
local MIN_FOV = 15
local MAX_FOV = 70
local FP_CAMERA_ROTATION = Vector2.new()
local FP_CAMERA_ROTATION_SPEED = 0.2
local FP_CAMERA_STIFFNESS = 2.5
local FP_CAMERA_HEADSWAY_SIZE = Vector3.new(0, 0, 1)
local FP_CAMERA_MAX_HEADSWAY = Vector3.new(0.2, 0.2, 0.2)
local FP_CAMERA_OSCILLATION_SIZE = 0.17
local FP_CAMERA_MIN_OSCILLATION_SIZE = 0.05
local FP_CAMERA_OSCILLATION_RATE = 10
local DEFAULT_CAMERA_MODE = 1
local DEFAULT_CAMERA_CYCLE = 1
local CAMERA_MODES = {
	Cab = 1,
	Exterior = 2,
	Passenger = 3,
	Fixed = 4
}
local HORN_TYPES = {
	High = 1,
	Low = 2
}
local MAX_CAMERA_MODE = 3

-- Functions

local function nameSort(a, b)
	return tonumber(a.Name) < tonumber(b.Name)
end

-- Initialisation
local trainClient = script.Parent.Parent
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local spawnTrain = remotes:WaitForChild("SpawnTrain")
INACTIVE_TRACK.Name = "InactiveTrack"
INACTIVE_TRACK.Parent = workspace
local mouse = Players.LocalPlayer:GetMouse()

local Train = {}
Train.__index = Train

function Train.new(character)
	local self = setmetatable({}, Train)
	
	-- Wait for train to load and fetch settings
	do
		if not character:FindFirstChild("Carriages") then
			warn("Improper train config")
			spawnTrain:FireServer()
		end
		
		local count = 0
		
		for i, v in pairs(character.Carriages:GetChildren()) do
			repeat 
				RunService.Heartbeat:Wait()
				count = count + 1
				if count == TRAIN_LOAD_TIMEOUT then
					warn("Could not load carriage " + v.Name)
					spawnTrain:FireServer()
				end
			until #v:GetChildren() > 0 and v.PrimaryPart
		end
		
		local config = character:WaitForChild("Settings")
		assert(config, "No settings module")
		self.config = require(config)
	end
	
	-- Sort carriages in the correct order
	table.sort(self.config.carriages, nameSort)
	
	-- Set up train object
	self.throttle = DEFAULT_THROTTLE
	self.speedLimit = DEFAULT_SPEED_LIMIT
	self.speed = DEFAULT_SPEED
	self.direction = DEFAULT_DIRECTION
	self._sensors = {}
	self._createdSensorParts = {}
	self._lastPhysicsExecuteTime = os.clock()
	self.stoppedEvent = Instance.new("BindableEvent")
	self.stoppedEvent.Name = "Stopped"
	self.stoppedEvent.Parent = character
	self.throttleChangedEvent = Instance.new("BindableEvent")
	self.throttleChangedEvent.Name = "ThrottleChanged"
	self.throttleChangedEvent.Parent = character
	self._derailCount = 0
	self._actualThrottle = self.throttle
	self.hornTypes = HORN_TYPES
	self.gradient = 0

	-- Create raycast parameters object
	self._raycastParams = RaycastParams.new()
	self._raycastParams.FilterType = Enum.RaycastFilterType.Whitelist
	self._raycastParams.IgnoreWater = true
	self._raycastParams.FilterDescendantsInstances = {ACTIVE_TRACK}

	-- Set up track
	self._trackIgnoreList = {}
	self:SetInitialRoute()
	ACTIVE_TRACK.ChildAdded:Connect(function(child)
		if not table.find(self._trackIgnoreList, child.Name) then
			self:_AddToActiveTrack(child.Name)
		end
	end)
	ACTIVE_TRACK.ChildRemoved:Connect(function(child)
		self:_RemoveFromActiveTrack(child.Name)
	end)
	
	-- Set up camera
	self.cameraMode = DEFAULT_CAMERA_MODE
	self.cameraCycle = DEFAULT_CAMERA_CYCLE
	self._camera = Camera.new()
	self._camera.camera = workspace.CurrentCamera
	self._camera.maxHeadSway = FP_CAMERA_MAX_HEADSWAY
	self._camera.position = Vector3.new()
	self._camera.stiffness = FP_CAMERA_STIFFNESS
	self._camera.rotation = FP_CAMERA_ROTATION
	self._camera.rotationSpeed = math.rad(FP_CAMERA_ROTATION_SPEED)
	self._camera.headSwaySize = FP_CAMERA_HEADSWAY_SIZE
	self.cameraModes = CAMERA_MODES
	mouse.WheelForward:Connect(function()
		self._camera.targetZoomFOV = math.clamp(self._camera.targetZoomFOV - FIRST_PERSON_ZOOM_SPEED, MIN_FOV, MAX_FOV)
	end)
	mouse.WheelBackward:Connect(function()
		self._camera.targetZoomFOV = math.clamp(self._camera.targetZoomFOV + FIRST_PERSON_ZOOM_SPEED, MIN_FOV, MAX_FOV)
	end)
	
	-- Set up AWS
	do
		self.warnAWS = Instance.new("Sound")
		self.clearAWS = Instance.new("Sound")
		self.warnAWS.Looped = self.config.awsSounds.Warn.Looped
		self.warnAWS.SoundId = self.config.awsSounds.Warn.SoundId
		self.warnAWS.Volume = self.config.awsSounds.Warn.Volume
		self.warnAWS.Name = "Warn"
		self.warnAWS.Parent = character
		self.clearAWS.Looped = self.config.awsSounds.Clear.Looped
		self.clearAWS.SoundId = self.config.awsSounds.Clear.SoundId
		self.clearAWS.Volume = self.config.awsSounds.Clear.Volume
		self.clearAWS.Name = "Clear"
		self.clearAWS.Parent = character
	end
	
	-- Get motors
	self.motors = {}
	for i, v in pairs(self.config.carriages) do
		for i, v in pairs(v.PrimaryPart:GetChildren()) do
			if v.Name == "Motor" and v:IsA("HingeConstraint") then
				table.insert(self.motors, v)
			end
		end
	end
	
	return self
end

function Train:_RemoveFromActiveTrack(name)
	for i, v in pairs(ACTIVE_TRACK:GetChildren()) do
		if v.Name == name then
			v.Parent = INACTIVE_TRACK
		end
	end
end

function Train:_AddToActiveTrack(name)
	for i, v in pairs(INACTIVE_TRACK:GetChildren()) do
		if v.Name == name then
			v.Parent = ACTIVE_TRACK
		end
	end
end

function Train:UpdatePhysics()
	-- Calculate change in time
	local t = os.clock()
	local dt = t - self._lastPhysicsExecuteTime
	self._lastPhysicsExecuteTime = t
	
	-- Don't update if train is fully despawning
	if self._derailed or not trainClient or not trainClient.Parent then
		return false
	end
	
	-- Remember derail count to check if any part of the train is derailed
	local lastDerailCount = self._derailCount
	local partDerailed

	-- Get current scaled velocity
	local scaledVelocity = self.speed * self.config.scale * self.direction
	
	-- Update BodyMovers
	for i, car in pairs(self.config.carriages) do
		local carPart = car.PrimaryPart
		local bogie0Cf = carPart.bogie0.WorldCFrame
		local bogie1Cf = carPart.bogie1.WorldCFrame

		-- Raycast track
		local result0 = workspace:Raycast(carPart.bogie0.WorldPosition, bogie0Cf.UpVector * -RAY_LENGTH, self._raycastParams)
		local result1 = workspace:Raycast(carPart.bogie1.WorldPosition, bogie1Cf.UpVector * -RAY_LENGTH, self._raycastParams)
		local part0, pos0, part1, pos1

		-- Check if derailed
		if not result0 or not result1 then
			partDerailed = true
		end
		if not partDerailed then
			part0, pos0 = result0.Instance, result0.Position
			part1, pos1 = result1.Instance, result1.Position
			if part0.Name ~= GUIDE_PART_NAME and part1.Name ~= GUIDE_PART_NAME then
				partDerailed = true
			end
		end

		-- Update BodyMovers if not derailed
		if not partDerailed then
			-- Find if either track part is reversed
			local reversePos0 = bogie0Cf.lookVector:Dot(part0.CFrame.lookVector) < 0
			local reversePos1 = bogie1Cf.lookVector:Dot(part1.CFrame.lookVector) < 0
			
			-- Centre intersects with track
			do
				local trackCFrame = part0.CFrame
				local pos = trackCFrame:PointToObjectSpace(pos0)
				pos = Vector3.new(0, 0, pos.Z)
				pos0 = trackCFrame:PointToWorldSpace(pos)
			end
			do
				local trackCFrame = part1.CFrame
				local pos = trackCFrame:PointToObjectSpace(pos1)
				pos = Vector3.new(0, 0, pos.Z)
				pos1 = trackCFrame:PointToWorldSpace(pos)
			end
			
			-- Get CFrames of intersects
			local orientation0 = part0.CFrame - part0.CFrame.Position
			local orientation1 = part1.CFrame - part1.CFrame.Position
			local cf0 = CFrame.new(pos0) * (reversePos0 and orientation0 * REVERSE_CFRAME or orientation0)
			local cf1 = CFrame.new(pos1) * (reversePos1 and orientation1 * REVERSE_CFRAME or orientation1)
			local targetCf = cf0:Lerp(cf1, 0.5) * CFrame.new(0, self.config.height, -scaledVelocity)
			
			-- Set BodyVelocity
			carPart.BodyVelocity.Velocity = targetCf.Position - carPart.Position
			
			-- Set BodyGyro
			carPart.BodyGyro.CFrame = carPart.BodyGyro.CFrame:Lerp(targetCf, BODYGYRO_INTERPOLATION * dt * self.speed)
		end
	end

	-- Update physics values if not derailed (to prevent decoupling)
	if not partDerailed then
		-- Set actual throttle
		local throttle = self._actualThrottle
		if throttle < self.throttle then
			local newThrottle = throttle + 
				(throttle >= 0 and self.config.tractionIncreaseRate or self.config.brakeDecreaseRate) * dt
			if newThrottle > self.throttle then
				throttle = self.throttle
			else
				throttle = newThrottle
			end
		elseif throttle > self.throttle then
			local newThrottle = throttle -
				(throttle > 0 and self.config.tractionDecreaseRate or self.config.brakeIncreaseRate) * dt
			if newThrottle < self.throttle then
				throttle = self.throttle
			else
				throttle = newThrottle
			end
		end
		self:SetActualThrottle(throttle)
		
		-- Calculate resultant force
		local resultantForce = -self.config.getResistance(self.speed)
		if throttle > 0 then
			resultantForce += self.config.getTractiveForce(self.speed, throttle)
		else
			resultantForce += self.config.getBrakeForce(self.speed, throttle)
		end
		
		-- Gravity due to gradients
		do
			local length = #self.config.carriages
			local cf0 = self.config.carriages[1].PrimaryPart.CFrame * CFrame.new(0, 0, -self.config.carriages[1].PrimaryPart.Size.Z / 2)
			local cf1 = self.config.carriages[length].PrimaryPart.CFrame * CFrame.new(0, 0, self.config.carriages[length].PrimaryPart.Size.Z / 2)
			self.gradient = (cf0.Y - cf1.Y) / Vector3.new(cf0.X - cf1.X, 0, cf0.Z - cf1.Z).Magnitude
			local magnitude = self.config.mass * GRAVITATIONAL_CONSTANT
			local F_parallel = math.sin(math.atan(self.gradient)) * magnitude
			resultantForce -= F_parallel
		end

		-- Update speed and velocity, if not derailed (to prevent decoupling)
		local nextSpeed = math.max(self.speed + resultantForce / self.config.mass * dt, 0)
		if self.speed ~= 0 and nextSpeed == 0 then
			self.stoppedEvent:Fire()
		end
		self.speed = nextSpeed
		
		-- Update motors
		local wheelSpeed = -scaledVelocity / self.config.wheelCircumference * 2 * math.pi
		for i, v in pairs(self.motors) do
			v.AngularVelocity = wheelSpeed
		end
	else
		self._derailCount += 1
		if self._derailCount > MAX_DERAIL_COUNT then
			self._derailed = true
			warn("Derailed")
			spawnTrain:FireServer()
			return false
		end
	end
	
	-- Reset derail count if derail count is not changed
	if self._derailCount == lastDerailCount then
		self._derailCount = 0
	end
end

function Train:SetActualThrottle(t)
	if self._actualThrottle == 0 then
		if t > 0 then
			print("TO DO: Update throttle direction to 1 on sever")
		elseif t < 0 then
			print("TO DO: Update throttle direction to -1 on server")
		end
	elseif self._actualThrottle > 0 then
		if t == 0 then
			print("TO DO: Update throttle direction to 0 on server")
		elseif t < 0 then
			print("TO DO: Update throttle direction to -1 on server")
		end
	else
		if t == 0 then
			print("TO DO: Update throttle direction to 0 on server")
		elseif t > 0 then
			print("TO DO: Update throttle direction to 1 on server")
		end
	end
	self._actualThrottle = t
end

function Train:GetActualThrottle()
	return self._actualThrottle
end

function Train:IgnoreTrackNames(list)
	for i, v in pairs(list) do
		if not table.find(self._trackIgnoreList, v) then
			table.insert(self._trackIgnoreList, v)
			self:_RemoveFromActiveTrack(v)
		end
	end
end

function Train:FollowTrackNames(list)
	for i, v in pairs(list) do
		local index = table.find(self._trackIgnoreList, v)
		if index then
			table.remove(self._trackIgnoreList, index)
			self:_AddToActiveTrack(v)
		end
	end
end

function Train:SetInitialRoute(route, startPoint)
	-- Reset ignore list
	self:FollowTrackNames(self._trackIgnoreList)

	if typeof(route) == "table" and typeof(route.startPoints) == "table" and route.startPoints[startPoint] then
		self.timetable = deepCopy(route.timetable)
		startPoint = route.startPoints[startPoint]
		local startTime = startPoint.startTime

		-- Set timetable and track depending on the direction
		local directionSwitch = Switch()
			:case(1, function() 
				for i, v in pairs(self.timetable) do
					v.departTime = v.departTime - startTime
				end
			end)

			:case(-1, function()
				for i, v in pairs(self.timetable) do
					v.departTime = startTime - v.departTime
				end
			end)

		directionSwitch(startPoint.direction)

		-- Remove stops before start
		for i, v in pairs(self.timetable) do
			if v.departTime < 0 then
				self.timetable[i] = nil
			end
		end

		print("[PlayerTrain]: Set route. To do: send points table to server.")
	else
		print("[PlayerTrain]: Reset route")
	end
end

function Train:IncrementNextStop()
	-- Get the current route and shift the table to the left
end

function Train:GetTrackIgnoreList()
	return self._trackIgnoreList
end

function Train:IncrementThrottle(i)
	if not self._throttleLocked then
		i = i == -1 and i or 1
		local tractionIncrement = self.config.tractionIncrement * i
		local brakeIncrement = self.config.brakeIncrement * i
		local newThrottle = self.throttle
		-- Increment throttle
		if newThrottle > 0 then
			newThrottle += tractionIncrement
			if newThrottle < 0 then
				newThrottle = 0
			end
		elseif newThrottle < 0 then
			newThrottle += brakeIncrement
			if newThrottle > 0 then
				newThrottle = 0
			end
		elseif tractionIncrement > 0 and brakeIncrement > 0 then
			newThrottle += tractionIncrement
		elseif tractionIncrement < 0 and brakeIncrement < 0 then
			newThrottle += brakeIncrement
		end
		-- Clamp throttle
		if math.abs(newThrottle) < MINIMUM_DESIRED_THROTTLE then
			newThrottle = 0
		elseif math.abs(newThrottle) > 1 then
			if math.abs(self.throttle) > 1 then
				newThrottle = self.throttle
			else
				newThrottle = newThrottle > 1 and 1 or -1
			end
		end
		if newThrottle ~= self.throttle then
			self.throttle = newThrottle
			self.throttleChangedEvent:Fire()
		end
	end
end

function Train:DecrementThrottle()
	return Train:IncrementThrottle(-1)
end

function Train:UpdateCamera(dt)
	local cameraSwitch = Switch()
		:case(CAMERA_MODES.Cab, function() 
			if self.cameraCycle > # self.config.cabCameras then
				self.cameraCycle = 1
			end
			self._camera.relativeTo = self.config.cabCameras[self.cameraCycle]
			local speedProgress = self.speed / self.config.cabCameraOscillationMaxSpeed
			self._camera.headOscillationRate = FP_CAMERA_OSCILLATION_RATE
			self._camera.headOscillationSize = speedProgress * FP_CAMERA_OSCILLATION_SIZE
			if self._camera.headOscillationSize < FP_CAMERA_MIN_OSCILLATION_SIZE then
				self._camera.headOscillationSize = 0
				self._camera.headOscillationRate = 0
			end
			self._camera:Update(dt)
		end)

		:case(CAMERA_MODES.Exterior, function()
			self._camera.targetZoomFOV = 70
			self._camera.zoom.p = 70
			workspace.CurrentCamera.FieldOfView = 70
			if self.cameraCycle > #self.config.carriages then
				self.cameraCycle = 1
			end
			if workspace.CurrentCamera.CameraType ~= Enum.CameraType.Custom then
				workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
			end
			workspace.CurrentCamera.CameraSubject = self.config.carriages[self.cameraCycle].PrimaryPart
		end)

		:case(CAMERA_MODES.Passenger, function() 
			if self.cameraCycle > #self.config.passengerCameras then
				self.cameraCycle = 1
			end
			self._camera.relativeTo = self.config.passengerCameras[self.cameraCycle] 
			self._camera:Update(dt)
		end)
		
	cameraSwitch(self.cameraMode)
end

function Train:ChangeCameraMode(mode)
	if self.cameraMode ~= mode then
		self.cameraCycle = 1
		self.cameraMode = mode
	else
		self.cameraCycle += 1
	end
end

function Train:NextCameraMode()
	local nextCameraMode = self.cameraMode + 1
	if nextCameraMode > MAX_CAMERA_MODE then
		nextCameraMode = 1
	end
	return self:ChangeCameraMode(nextCameraMode)
end

function Train:EmergencyStop(event)
	Thread.Spawn(function()
		self._throttleLocked = true
		self.throttle = EMERGENCY_THROTTLE
		if event then
			event:Wait()
		end
		if self.speed ~= 0 then
			self.stoppedEvent.Event:Wait()
		end
		self._throttleLocked = false
		self.throttle = DEFAULT_THROTTLE
	end)
end

function Train:WarnAWS()
	self.warnAWS:Play()
	self.AWS = true
	Thread.Delay(AWS_WARN_TIME, function() 
		if self.warnAWS.Playing then
			self:EmergencyStop()
		end
	end)
end

function Train:AcknowledgeAWS()
	self.warnAWS:Stop()
end

function Train:ClearAWS()
	self.clearAWS:Play()
	self.AWS = false
end

function Train:NewSensor(part, func)
	if not self._createdSensorParts[part] then
		local sensor = Sensor.fromPart(part)
		sensor.hit:Connect(function(...)
			func(sensor, ...)
		end)
		self._createdSensorParts[part] = true
		table.insert(self._sensors, sensor)
		return sensor
	end
	return false
end

function Train:UpdateSensorsWithinRadius(radius)
	for i, v in pairs(self._sensors) do
		local centre = self.config.carriages[1].PrimaryPart.Position:Lerp(
			self.config.carriages[#self.config.carriages].PrimaryPart.Position, 
			0.5
		)
		if (v.position - centre).Magnitude < radius then
			v:Update()
		end
	end
end

function Train:ToggleDoors()
	if self.speed == 0 and self.throttle <= 0 and not self._doorsMoving then
		self._throttleLocked = true
		self.throttle = -1
		self._doorsMoving = true
		remotes.MoveDoors:InvokeServer(not self._doorsOpen)
		if not self._doorsOpen then
			wait(DOORS_MIN_OPEN)
		end
		self._doorsOpen = not self._doorsOpen
		self._doorsMoving = false
		if not self._doorsOpen then
			self._throttleLocked = false
		end
	end
end

function Train:StartHorn(hornType)

end

function Train:StopHorn(hornType)

end

return Train.new(Players.LocalPlayer.Character)