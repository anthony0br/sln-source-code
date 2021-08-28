-- Detects trains over sensors

-- Constants
local RAY_LENGTH = 2

-- Services
local Players = game:GetService("Players")

-- Initialisation
local trains = workspace:WaitForChild("Trains")

-- Functions

local function findTrainFromDescendant(d)
	if Players:FindFirstChild(d.Name) and d:FindFirstChild("Settings") then
		return d
	elseif d.Parent and d.Parent ~= workspace then
		return findTrainFromDescendant(d.Parent)
	end
end

local function getTrainsOverSensor(sensorPosition)
	local trainsOverSensor = {}
	for i, v in pairs(trains:GetChildren()) do
		local centre, size = v:GetBoundingBox()
		local localSensorPosition = centre:PointToObjectSpace(sensorPosition)
		if math.abs(localSensorPosition.X) <= size.X * 0.5 and math.abs(localSensorPosition.Z) <= size.Z * 0.5 then
			table.insert(trainsOverSensor, v)
		end
	end
	return trainsOverSensor
end

-- Class Sensor
local Sensor = {}
Sensor.__index = Sensor

function Sensor.new(position, direction)
	local self = setmetatable({}, Sensor)
	self.position = position
	self.direction = direction
	self.hitEvent = Instance.new("BindableEvent")
	self.leftEvent = Instance.new("BindableEvent")
	self.hit = self.hitEvent.Event
	self.left = self.leftEvent.Event
	self._raycastParams = RaycastParams.new()
	self._raycastParams.FilterType = Enum.RaycastFilterType.Whitelist
	self._raycastParams.IgnoreWater = true
	
	return self
end

function Sensor:Update()
	local part
	local trainsOverSensor = getTrainsOverSensor(self.position)
	if #trainsOverSensor > 0 then
		-- Raycast to check which train, if any, of the trains are passing the sensor
		self._raycastParams.FilterDescendantsInstances = trainsOverSensor
		local result = workspace:Raycast(self.position, self.direction * RAY_LENGTH, self._raycastParams)
		if result then
			part = result.Instance
		end
	end
	if part then
		local newTrain = findTrainFromDescendant(part)
		if newTrain and self.train ~= newTrain then
			self.train = newTrain
			self.hitEvent:Fire()
		end
		self.train = newTrain
	elseif self.train then
		self.leftEvent:Fire()
		self.train = nil
	end
end

function Sensor.fromPart(part)
	local position = part.Position
	local direction = part.CFrame.upVector
	return Sensor.new(position, direction)
end

return Sensor