-- Train Initialisation, Physics, and Controls.

-- Services
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

-- Modules
local Thread = require(ReplicatedStorage.Modules.Thread)
local Switch = require(ReplicatedStorage.Modules.Switch)

-- Constants
local CONTROLS = {
	CabView = {Enum.KeyCode.One, Enum.KeyCode.DPadDown},
	ExteriorView = {Enum.KeyCode.Two, Enum.KeyCode.DPadUp},
	PassengerView = {Enum.KeyCode.Three, Enum.KeyCode.DPadLeft},
	FixedView = {Enum.KeyCode.Four, Enum.KeyCode.DPadDown},
	IncrementThrottle = {Enum.KeyCode.W, Enum.KeyCode.ButtonR2, Enum.KeyCode.D},
	DecrementThrottle = {Enum.KeyCode.S, Enum.KeyCode.ButtonL2, Enum.KeyCode.A},
	ToggleDoors = {Enum.KeyCode.T, Enum.KeyCode.ButtonX},
	AcknowledgeAWS = {Enum.KeyCode.Q, Enum.KeyCode.ButtonY},
	NextCameraMode = {Enum.KeyCode.V},
	HighHorn = {Enum.KeyCode.B, Enum.KeyCode.Thumbstick1},
	LowHorn = {Enum.KeyCode.Space, Enum.KeyCode.Thumbstick2}
}
local TELEPORTERS = workspace.Teleporters
local PHYSICS_UPDATE_INTERVAL = 1/30
local SENSOR_UPDATE_INTERVAL = 1/3
local SENSOR_UPDATE_RADIUS = 200

-- Initialisation
local trainClient = Players.LocalPlayer.Character:FindFirstChild("TrainClient")
assert(trainClient, "[Dynamics]: TrainClient missing")
trainClient.Freecam.Disabled = true
trainClient.Freecam.Disabled = false
local teleporting
local train = require(trainClient.PlayerTrain)

-- Functions

-- 1: Proceed (green)
-- 2: Preliminary caution (double yellow)
-- 3: Caution (yellow)
-- 4: Stop (red)
local function getSignalAspect(signal)
	for i, v in pairs(signal.Aspects:GetDescendants()) do
		if v:IsA("SurfaceGui") and v.Enabled then
			return tonumber(v.Name)
		end
	end
	return false
end

-- Load Teleport Data
do
	local teleportData = TeleportService:GetLocalPlayerTeleportData()
	if teleportData then
		train.speed = teleportData.speed
		train.speedLimit = teleportData.speedLimit
		train.throttle = teleportData.throttle
		train.direction = teleportData.direction
		train.timetable = teleportData.timetable
		train:SetActualThrottle(teleportData.actualThrottleToSet)
		train:IgnoreTrackNames(teleportData.trackIgnoreList)
	end
end

-- Update physics
Thread.DelayRepeat(PHYSICS_UPDATE_INTERVAL, function()
	if not teleporting then
		train:UpdatePhysics()
	end
end)

-- Update camera
RunService.RenderStepped:Connect(function(dt)
	train:UpdateCamera(dt)
end)

-- Update sensors
Thread.DelayRepeat(SENSOR_UPDATE_INTERVAL, function()
	train:UpdateSensorsWithinRadius(SENSOR_UPDATE_RADIUS)
end)

-- AWS sensors
do	
	local function newAWS(signal)
		local sensor = train:NewSensor(signal.AWS, function()
			print("TO DO: Check if signal is on the route")
			if getSignalAspect(signal) == 1 then
				train:ClearAWS()
			else
				train:WarnAWS()
			end
		end)
		return sensor
	end
	for i, v in pairs(workspace.Signals:GetChildren()) do
		for i, signal in pairs(v:GetChildren()) do
			if signal:FindFirstChild("AWS") then
				newAWS(signal)
			else -- Set up new sensors that are streamed in
				local connection
				connection = signal.ChildAdded:Connect(function(child)
					if child.Name == "AWS" then
						newAWS(signal)
						connection:Disconnect()
					end
				end)
			end
		end
	end
end

-- Speed limit sensors
do
	local function newSpeedLimit(sign)
		train:NewSensor(sign.SENSOR, function(self)
			if tonumber(sign.Sign.Gui.Speed.Text) > train.speedLimit then
				self.left:Wait()
			end
			train.speedLimit = tonumber(sign.Sign.Gui.Speed.Text)
		end)
	end
	for i, v in pairs(workspace.PermissibleSpeedIndicators:GetChildren()) do
		if v:FindFirstChild("SENSOR") then
			newSpeedLimit(v)
		else -- Set up new sensors that are streamed in
			local connection
			connection = v.ChildAdded:Connect(function(child)
				if child.Name == "SENSOR" then
					newSpeedLimit(v)
					connection:Disconnect()
				end
			end)
		end
	end
end

-- Teleportation
do
	local function newTeleporter(teleporter)
		if teleporter and teleporter:IsA("BasePart") then
			local name = teleporter.Name
			local placeValue = teleporter:FindFirstChild("PlaceID")
			if placeValue then
				train:NewSensor(teleporter, function()
					local teleportData = {}
					teleporting = true
					teleportData.speed = train.speed
					teleportData.speedLimit = train.speedLimit
					teleportData.throttle = train.throttle
					teleportData.actualThrottleToSet = train:GetActualThrottle()
					teleportData.direction = train.direction
					teleportData.timetable = train.timetable
					teleportData.trackIgnoreList = train:GetTrackIgnoreList()
					teleportData.arrivalPoint = name
					teleportData.trainType = train.config.trainType
					TeleportService:Teleport(placeValue.Value, nil, teleportData)
				end)
			end
		end
	end
	-- Set up teleporters that have already streamed in
	for i, v in pairs(TELEPORTERS:GetChildren()) do
		newTeleporter(v)
	end
	-- Set up new teleporters when they are streamed in
	TELEPORTERS.ChildAdded:Connect(function(v)
		newTeleporter(v)
	end)
end

-- Control bindings
do
	local function handleAction(name, state, input)
		if state == Enum.UserInputState.Begin then
			local throttleMovement = 1
			local switch
			switch = Switch()
				-- Handle throttle controls
				:case("IncrementThrottle", function() 
					train:IncrementThrottle(throttleMovement)
					Thread.Delay(train.config.throttleChangeInterval, function() 
						if input and input.UserInputState ~= Enum.UserInputState.End then
							switch("IncrementThrottle")
						end
					end)
				end)
				:case("DecrementThrottle", function()
					throttleMovement = -1
					switch("IncrementThrottle")
				end)

				-- Camera views
				:case("NextCameraMode", function()
					train:NextCameraMode()
				end)
				:case("CabView", function()
					train:ChangeCameraMode(train.cameraModes.Cab)
				end)
				:case("ExteriorView", function()
					train:ChangeCameraMode(train.cameraModes.Exterior)
				end)
				:case("PassengerView", function()
					train:ChangeCameraMode(train.cameraModes.Passenger)
				end)
				:case("FixedView", function()
					train:ChangeCameraMode(train.cameraModes.Fixed)
				end)

				-- Misc controls
				:case("AcknowledgeAWS", function()
					train:AcknowledgeAWS()
				end)
				:case("ToggleDoors", function()
					train:ToggleDoors()
				end)
				:case("HighHorn", function()
					train:StopHorn(train.hornTypes.Low)
					train:StartHorn(train.hornTypes.High)
				end)
				:case("LowHorn", function()
					train:StopHorn(train.hornTypes.High)
					train:StartHorn(train.hornTypes.Low)
				end)

			switch(name)
		elseif state == Enum.UserInputState.End then
			local switch = Switch()
				-- End horns
				:case("HighHorn", function()
					train:StopHorn(train.HornType.High)
				end)
				:case("LowHorn", function()
					train:StopHorn(train.HornType.Low)
				end)

			switch(name)
		end
	end
	
	for i, v in pairs(CONTROLS) do
		ContextActionService:UnbindAction(i)
		ContextActionService:BindAction(i, handleAction, false, table.unpack(v))
	end
end

return train