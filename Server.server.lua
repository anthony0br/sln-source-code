-- Handles almost everything server related in SLN
-- Sublivion

-- Services
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Constants
local BODY_SCALE = {
	depth = 0.32,
	height = 0.32,
	width = 0.2,
	head = 0.32,
}
local MAXIMUM_HEIGHT = 10
local AFK_CHECK_INTERVAL = 300
local AFK_CHECK_DISTANCE = 100
local SIGNAL_CHANGE_DELAY = 3
local SANITY_CHECK_INTERVAL = 1
local SOUND_UPDATES_PER_STEP = 4
local DOOR_OPEN_SOUND_NAME = "DoorOpen"
local DOOR_CLOSE_SOUND_NAME = "DoorClose"

-- Create trains folder
local trains = Instance.new("Folder")
trains.Name = "Trains"
trains.Parent = workspace

-- Create remotes
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
local dataStoreUpdate = Instance.new("RemoteEvent")
dataStoreUpdate.Name = "DataStoreUpdate"
dataStoreUpdate.Parent = remotes
local moveDoors = Instance.new("RemoteFunction")
moveDoors.Parent = remotes
moveDoors.Name = "MoveDoors"

-- Modules
local trainConfigs = require(ServerStorage.Modules.Trains)
local Sensor = require(ReplicatedStorage.Modules.Sensor)
local Thread = require(ReplicatedStorage.Modules.Thread)
local lerp = require(ReplicatedStorage.Functions.Lerp)

-- -- Initialise datastores
-- DataStore2.Combine("DATA", "points")
-- DataStore2.Combine("DATA", "experience")

-- Functions

-- 1: Proceed (green)
-- 2: Preliminary caution (double yellow)
-- 3: Caution (yellow)
-- 4: Stop (red)
local function setSignalAspect(signal, aspectId)
	local matchFound
	local closest
	local difference
	for i, v in pairs(signal.Aspects:GetDescendants()) do
		if v:IsA("SurfaceGui") or v:IsA("BillboardGui") then
			if v.Name == tostring(aspectId) then
				v.Enabled = true
				matchFound = true
			else
				local foundAspectId = tonumber(v.Name)
				local localDifference = foundAspectId - tonumber(aspectId)
				if not difference or localDifference < difference or
				(localDifference == difference and foundAspectId < tonumber(closest)) then
					closest = v.Name
					difference = localDifference
				end
				v.Enabled = false
			end
		end
	end
	if not matchFound and closest then
		setSignalAspect(signal, closest)
	end
end

local function getSignalAspect(signal)
	for i, v in pairs(signal.Aspects:GetDescendants()) do
		if v:IsA("SurfaceGui") and v.Enabled then
			return tonumber(v.Name)
		end
	end
	return
end

-- Linear regression algorithm for sound
local function getSoundProperties(values, factorValue)
	local finalValues = {}

	-- Find the points of the line
	local minIndex
	local maxIndex
	for i, v in pairs(values) do
		i = tonumber(i)
		if i <= factorValue and (minIndex and i > minIndex or not minIndex) then
			minIndex = i
		end
		if i >= factorValue and (maxIndex and i < maxIndex or not maxIndex) then
			maxIndex = i
		end
	end

	-- Record the interpolated values in the table finalValues
	if minIndex and maxIndex then
		local minValues = values[tostring(minIndex)]
		if minIndex ~= maxIndex then
			local maxValues = values[tostring(maxIndex)]
			local a = (factorValue - minIndex) / (maxIndex - minIndex)
			for sound, values in pairs(minValues) do
				finalValues[sound] = {}
				for p, v in pairs(values) do
					finalValues[sound][p] = lerp(minValues[sound][p], maxValues[sound][p], a)
				end
			end
		else
			for sound, values in pairs(minValues) do
				finalValues[sound] = {}
				for p, v in pairs(values) do
					finalValues[sound][p] = minValues[sound][p]
				end
			end
		end
	end

	return finalValues
end

-- Update sounds
do
	local last = os.clock()
	local trainIndex = 1
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		local dt = t - last
		last = t
		local initialTrainIndex = trainIndex
		local trains = trains:GetChildren()
		for i = 1, SOUND_UPDATES_PER_STEP  do
			local train = trains[trainIndex]
			if train then
				local config = trainConfigs[train.Name]

				-- Set sounds
				local speed = math.abs(train.PrimaryPart.CFrame:PointToObjectSpace(
					train.PrimaryPart.Velocity + train.PrimaryPart.Position
				).Z / config.scale)
				local soundProperties = getSoundProperties(config.soundDynamics, speed)
				for sound, v in pairs(soundProperties) do
					for i, car in pairs(config.carriages) do
						for p, v in pairs(v) do
							if sound then
								local sound = car.PrimaryPart:FindFirstChild(sound)
								if sound and sound:IsA("Sound") then
									sound[p] = v
								end
							end
						end
					end
				end
			end
		end

		trainIndex = trainIndex + 1
		if trainIndex > #trains then
			trainIndex = 1
		end
	end)
end

-- Sanity checks
do
	Thread.DelayRepeat(SANITY_CHECK_INTERVAL, function()
		for i, train in pairs(trains:GetChildren()) do
			-- Get train settings
			local config = trainConfigs[train.Name]

			for i, v in pairs(config.carriages) do
				-- Despawn rogue or cursed trains
				if v:IsA("BasePart") then
					local part = workspace:FindPartOnRayWithWhitelist(
						Ray.new(
							v.Position,
							v.CFrame.UpVector * -MAXIMUM_HEIGHT
						),
						{workspace.Track}
					)
					if not part then
						train:Destroy()
					end
				end
			end
		end
	end)
end

-- AFK check
do
	local trainPositions = {}
	Thread.DelayRepeat(AFK_CHECK_INTERVAL, function()
		for i, train in pairs(trains:GetChildren()) do
			if train and trainPositions[train.Name] and (trainPositions[train.Name] - train.PrimaryPart.Position).Magnitude < AFK_CHECK_DISTANCE then
				train:Destroy()
				Players:FindFirstChild(train.Name).Character = nil
			end
		end
		trainPositions = {}
		for i, train in pairs(trains:GetChildren()) do
			trainPositions[train.Name] = train.PrimaryPart.Position
		end
	end)
end

-- Door animations
do
	local function startWeldAnimation(weld, sequence)
		for i, v in ipairs(sequence) do
			local tween = TweenService:Create(weld, v[2], {C0 = weld.C0 * CFrame.new(v[1])})
			tween:Play()
			tween.Completed:Wait()
		end
	end

	local function checkPlatform(train, car, height, direction, doorProportion)
		if car and car.PrimaryPart then
			local y = -0.5 * car.PrimaryPart.Size.Y + height
			local z = 0.5 * car.PrimaryPart.Size.Z * doorProportion
			local x = direction * car.PrimaryPart.Size.X * 0.5
			local ray0 = Ray.new(
				car.PrimaryPart.CFrame * Vector3.new(x, y, -z),
				car.PrimaryPart.CFrame.RightVector * direction
			)
			local ray1 = Ray.new(
				car.PrimaryPart.CFrame * Vector3.new(x, y, z),
				car.PrimaryPart.CFrame.RightVector * direction
			)
			local part0 = workspace:FindPartOnRayWithIgnoreList(ray0, {train, workspace.Track})
			local part1 = workspace:FindPartOnRayWithIgnoreList(ray1, {train, workspace.Track})
			return part0 and part1 and true
		end
		return false
	end

	moveDoors.OnServerInvoke = function(player, open)
		-- Get sequences for each door
		local train = trains:FindFirstChild(player.Name)
		local config = trainConfigs[train.Name]
		local sequence = open and config.doorOpenSequence or config.doorCloseSequence
		local sequence00 = {}
		local sequence01 = {}
		local sequence10 = {}
		local sequence11 = {}
		local animationTime = 0
		for i, v in ipairs(sequence) do
			animationTime = animationTime + v[2].Time
			table.insert(sequence00, {v[1] * config.doorMultiplier00, v[2]})
			table.insert(sequence01, {v[1] * config.doorMultiplier01, v[2]})
			table.insert(sequence10, {v[1] * config.doorMultiplier10, v[2]})
			table.insert(sequence11, {v[1] * config.doorMultiplier11, v[2]})
		end
		local doorIndicatorTransparency = open and config.doorIndicatorOpenTransparency or config.doorIndicatorClosedTransparency
		local sound = open and DOOR_OPEN_SOUND_NAME or DOOR_CLOSE_SOUND_NAME

		-- Select doors to open
		local leftSideCarriagesToToggle = {}
		local rightSideCarriagesToToggle = {}
		for i, v in pairs(config.carriages) do
			if v.PrimaryPart then
				-- Check if platform exists
				local doorProportion = config.miniumumDoorOpenPlatformedArea
				local height = config.minimumPlatformHeight
				local leftSide = checkPlatform(train, v, height, -1, doorProportion)
				local rightSide = checkPlatform(train, v, height, 1, doorProportion)

				-- Play sound and change indicattors
				if leftSide or rightSide then
					local soundObject = v.PrimaryPart:FindFirstChild(sound)
					if soundObject then
						soundObject:Play()
					end
					if open then
						if leftSide then
							config.leftSideDoorIndicators[v.Name].Transparency = doorIndicatorTransparency
						else
							config.rightSideDoorIndicators[v.Name].Transparency = doorIndicatorTransparency
						end
					end
				end

				-- Add to table to toggle doors
				leftSideCarriagesToToggle[v.Name] = leftSide
				rightSideCarriagesToToggle[v.Name] = rightSide
			end
		end

		-- Play animations
		for i, car in pairs(config.carriages) do
			if config.leftDoors[car.Name] then
				for i, v in pairs(config.leftDoors[car.Name]) do
					if v.Weld.C0.X < 0 and leftSideCarriagesToToggle[car.Name] then
						coroutine.wrap(function()
							startWeldAnimation(v.Weld, sequence00)
							config.leftSideDoorIndicators[car.Name].Transparency = doorIndicatorTransparency
						end)()
					elseif v.Weld.C0.X > 0 and rightSideCarriagesToToggle[car.Name] then
						coroutine.wrap(function()
							startWeldAnimation(v.Weld, sequence10)
							config.rightSideDoorIndicators[car.Name].Transparency = doorIndicatorTransparency
						end)()
					end
				end
			end
			if config.rightDoors[car.Name] then
				for i, v in pairs(config.rightDoors[car.Name]) do
					if v.Weld.C0.X < 0 and leftSideCarriagesToToggle[car.Name] then
						coroutine.wrap(function()
							startWeldAnimation(v.Weld, sequence01)
							config.leftSideDoorIndicators[car.Name].Transparency = doorIndicatorTransparency
						end)()
					elseif v.Weld.C0.X > 0 and rightSideCarriagesToToggle[car.Name] then
						coroutine.wrap(function()
							startWeldAnimation(v.Weld, sequence11)
							config.rightSideDoorIndicators[car.Name].Transparency = doorIndicatorTransparency
						end)()
					end
				end
			end
		end

		wait(animationTime)
		return true
	end
end

-- Handle new players
Players.PlayerAdded:Connect(function(player)
	-- -- Create datastores
	-- local pointsStore = DataStore2("points", player)
	-- local experienceStore = DataStore2("experience", player)
	-- local function callRemote(remote, value)
	-- 	dataStoreUpdate:FireClient(player, remote, value) 
	-- end
	-- callRemote("points", pointsStore:Get(STARTING_POINTS))
	-- callRemote("experience", experienceStore:Get(STARTING_EXPERIENCE))
	-- pointsStore:OnUpdate(function(value)
	-- 	callRemote("points", value)
	-- end)
	-- experienceStore:OnUpdate(function(value)
	-- 	callRemote("experience", value)
	-- end)
	-- pointsStore:Increment(10000)

	-- Setup characters
	player.CharacterAdded:Connect(function()
		local character = player.Character

		if not character:IsDescendantOf(trains) and character:WaitForChild("Humanoid") then
			-- Handle kill bricks
			for i, v in pairs(character:GetChildren()) do
				if v:IsA("BasePart") then
					v.Touched:Connect(function(part)
						v.Massless = true
						if part:IsDescendantOf(workspace.Track) or part.Name == "KILL" then
							player.Character = nil
							character:Destroy()
						end
					end)
				end
			end

			-- Scale character
			local depthScale = character.Humanoid:WaitForChild("BodyDepthScale", 1)
			local heightScale = character.Humanoid:WaitForChild("BodyHeightScale", 1)
			local widthScale = character.Humanoid:WaitForChild("BodyWidthScale", 1)
			local headScale = character.Humanoid:WaitForChild("HeadScale", 1)

			if depthScale and heightScale and widthScale and headScale then
				depthScale.Value = BODY_SCALE.depth
				heightScale.Value = BODY_SCALE.height
				widthScale.Value = BODY_SCALE.width
				headScale.Value = BODY_SCALE.head
			else
				warn("Missing body scale")
				player.Character = nil
				character:Destroy()
			end
		end
	end)
end)