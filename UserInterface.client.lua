-- UserInterface
-- Sublivion

-- Services
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

-- Modules
local Animations = require(ReplicatedStorage.Modules.UI.Animations)
local Routes = require(ReplicatedStorage.Data.Routes)
local Thread = require(ReplicatedStorage.Modules.Thread)
local lerp = require(ReplicatedStorage.Functions.Lerp)

-- Constants
local HOVER_TIME = 0.15
local DEFAULT_TRAIN = "Class 377"
local MS_TO_MPH = 2.24
local MAX_CAMERA_ZOOM_DISTANCE = 40
local SPEED_NORMAL_COLOR3 = Color3.fromRGB(230, 230, 230)
local SPEED_OVERSPEED_COLOR3 = Color3.fromRGB(255, 100, 100)
local BRAKE_SELECTOR_COLOR3 = Color3.fromRGB(255, 100, 100)
local NEUTRAL_SELECTOR_COLOR3 = Color3.fromRGB(230, 230, 230)
local TRACTION_SELECTOR_COLOR3 = Color3.fromRGB(40, 255, 111)
local HOVER_COLOUR_EFFECT = Color3.fromRGB(30, 30, 30)
local DRIVING_STATS_UPDATE_INTERVAL = 1/10
local GAUGE_MAX_SPEED = 140 -- mph
local GAUGE_MIN_POSITION = -42
local GAUGE_MAX_POSITION = 262
local GAUGE_SEGMENTS = 7
local SPEED_LIMIT_MIN_ROTATION = -150
local SPEED_LIMIT_MAX_ROTATION = 150
local HORIZONTAL_TWEEN_INCREMENT = UDim2.fromScale(1, 0)
local SPAWN_DELAY = 1
local THROTTLE_MOVE_TIME = 0.5
local SELECTOR_SIZE_CHANGE = 1.075
local SELECTOR_SIZE_CHANGE_TIME = 0.2
local NOTCH_SELECTED_COLOUR_EFFECT = Color3.fromRGB(50, 50, 50)

-- Initialisation
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local spawnTrain = remotes:WaitForChild("SpawnTrain")
local player = Players.LocalPlayer
local gameUI = script.GameUI
local drivingUI = script.DrivingUI
local gaugeRange = GAUGE_MAX_POSITION - GAUGE_MIN_POSITION
local gaugeSegmentsRotations = {}

local function addColor3(c0, c1)
	local r = c0.r + c1.r
	local g = c0.g + c1.g
	local b = c0.b + c1.b
	return Color3.new(r, g, b)
end

local function subColor3(c0, c1)
	local r = math.max(c0.r - c1.r, 0)
	local g = math.max(c0.g - c1.g, 0)
	local b = math.max(c0.b - c1.b, 0)
	return Color3.new(r, g, b)
end

local function hoverEffect(button)
	Animations.createHoverEffect(
		button,
		button,
		"ImageColor3",
		button.ImageColor3,
		subColor3(button.ImageColor3, HOVER_COLOUR_EFFECT),
		HOVER_TIME
	)
end

local function separateDigits(amount)
	local formatted = amount
	local k = 1
	while k ~= 0 do  
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
	end
	return formatted
end

local function getFormattedLocalTime(offsetSeconds)
	local t = os.date("*t")
	local seconds = t.sec
	local minutes = t.min
	local hours = t.hour
	if offsetSeconds then
		seconds += offsetSeconds
		if seconds > 60 then
			minutes += math.floor(seconds / 60)
			seconds %= 60
		end
		if minutes > 60 then
			hours += math.floor(minutes / 60)
			minutes %= 60
		end
		if hours > 24 then
			hours %= 24
		end
	end
	local tableTime = {hours, minutes, seconds}
	for i, v in pairs(tableTime) do
		v = tostring(v)
		if string.len(v) < 2 then
			v = table.concat({"0", v})
		end
		tableTime[i] = v
	end
	table.insert(tableTime, 2, ":")
	table.insert(tableTime, 4, ":")
	return table.concat(tableTime)
end

local function updateDrivingHeartbeat(train)
	local scaledSpeed = train.speed * MS_TO_MPH

	-- Update gauge
	do
		local gaugePosition = math.clamp((scaledSpeed / GAUGE_MAX_SPEED) * gaugeRange + GAUGE_MIN_POSITION, GAUGE_MIN_POSITION, GAUGE_MAX_POSITION)
		drivingUI.Widgets.Speed_Widget.Twist.Rotation = gaugePosition
		for i, v in ipairs(gaugeSegmentsRotations) do
			if gaugePosition > v then
				drivingUI.Widgets.Speed_Widget.Segments[i].Visible = true
			else
				drivingUI.Widgets.Speed_Widget.Segments[i].Visible = false
			end
		end
	end

	-- Update speed text
	do
		local speed = tostring(math.floor(scaledSpeed * 10 + 0.5) * 0.1)
		if not string.find(speed, ".", 2, true) and speed ~= "0" then
			speed = table.concat({speed, ".0"})
		end
		drivingUI.Widgets.Speed_Widget.Speed.Text = speed
		drivingUI.Widgets.Speed_Widget.Speed.TextColor3 = (scaledSpeed - train.speedLimit >= 0.05) and SPEED_OVERSPEED_COLOR3 or SPEED_NORMAL_COLOR3
	end
end

local function updateDrivingStats(train)
	-- Set gradient
	do
		local gradient = tostring(math.abs(math.floor(train.gradient  * 100 * 10 + 0.5) * 0.1))
		if not string.find(gradient, ".", 1, true) then
			gradient = table.concat({gradient, ".0"})
		end
		gradient = table.concat({gradient, "%"})
		drivingUI.Widgets.Speed_Widget.Gradient.Text = gradient
		if train.gradient >= 0 then
			drivingUI.Widgets.Speed_Widget.GradientArrow.Rotation = 180
		else
			drivingUI.Widgets.Speed_Widget.GradientArrow.Rotation = 0
		end
	end

	-- Set time
	drivingUI.Route.Topbar.Time.Text = getFormattedLocalTime()

	-- Set AWS
	drivingUI.Widgets.AWS_Widget.ActiveImage.Visible = train.AWS

	-- Set speed limit
	do
		drivingUI.Widgets.Speed_Widget.SpeedLimit.Rotation = lerp(
			SPEED_LIMIT_MIN_ROTATION,
			SPEED_LIMIT_MAX_ROTATION,
			train.speedLimit / GAUGE_MAX_SPEED
		)
		drivingUI.Widgets.Limit_Widget.Speed.Text = train.speedLimit
	end
end

local function updateTimetable(timetable)

end

local function disconnectAll(toDisconnect)
	for i, v in pairs(toDisconnect) do
		v:Disconnect()
	end
end

-- Initialise GameUI
do
	hoverEffect(gameUI.Topbar.Despawn)
	hoverEffect(gameUI.Topbar.HideGUI)
	hoverEffect(gameUI.Topbar.Points.BuyPoints)

	-- Show/hide gui
	local uiHidden
	local uiMoving
	local function toggleUI()
		if not uiMoving then
			uiMoving = true
			uiHidden = not uiHidden
			local tweenTime = uiHidden and 0.5 or 0.1
			local clonedTopbar = gameUI:FindFirstChild("ClonedTopbar")
			if clonedTopbar then
				clonedTopbar:Destroy()
			end
			if uiHidden then
				clonedTopbar = gameUI.Topbar:Clone()
				for i, v in pairs(clonedTopbar:GetChildren()) do
					if v:IsA("GuiObject") and v.Name ~= "HideGUI" then
						v:Destroy()
					end
				end
				clonedTopbar.Name = "ClonedTopbar"
				clonedTopbar.ZIndex = gameUI.Topbar.ZIndex - 1
				clonedTopbar.Parent = gameUI
			end
			gameUI.Topbar:TweenPosition(
				uiHidden and gameUI.Topbar.Position + HORIZONTAL_TWEEN_INCREMENT or gameUI.Topbar.Position - HORIZONTAL_TWEEN_INCREMENT,
				nil,
				nil,
				tweenTime,
				nil,
				function()
					uiMoving = false
					if uiHidden then
						hoverEffect(clonedTopbar.HideGUI)
						clonedTopbar.HideGUI.MouseButton1Down:Connect(toggleUI)
					end
				end
			)
			drivingUI.Widgets:TweenPosition(
				uiHidden and drivingUI.Widgets.Position + HORIZONTAL_TWEEN_INCREMENT or drivingUI.Widgets.Position - HORIZONTAL_TWEEN_INCREMENT,
				nil,
				nil,
				tweenTime
			)
			drivingUI.Route:TweenPosition(
				uiHidden and drivingUI.Route.Position - HORIZONTAL_TWEEN_INCREMENT or drivingUI.Route.Position + HORIZONTAL_TWEEN_INCREMENT,
				nil,
				nil,
				tweenTime
			)
		end
	end
	gameUI.Topbar.HideGUI.MouseButton1Down:Connect(toggleUI)
end

-- Update DrivingUI
do
	local connections = {}
	player.CharacterAdded:Connect(function(character)
		local client = character:FindFirstChild("TrainClient")
		if character.Parent.Name == "Trains" and client then
			local model = character
			local train = require(client.Dynamics)
			drivingUI = drivingUI:Clone()

			-- Configure camera
			player.CameraMaxZoomDistance = MAX_CAMERA_ZOOM_DISTANCE

			-- Set temporary route
			train:SetInitialRoute(Routes["Three Bridges - Purley (F)"], "Three Bridges TMD")
			print("TO DO: Set specific route if originating from the menu")

			-- Listen to button inputs
			do
				hoverEffect(drivingUI.Widgets.ControlPanel.Doors)
				drivingUI.Widgets.ControlPanel.Doors.MouseButton1Down:Connect(function() 
					train:ToggleDoors()
				end)
			
				hoverEffect(drivingUI.Widgets.ControlPanel.Camera)
				drivingUI.Widgets.ControlPanel.Camera.MouseButton1Down:Connect(function() 
					train:NextCameraMode()
				end)
				
				hoverEffect(drivingUI.Widgets.ControlPanel.Horn_High)
				drivingUI.Widgets.ControlPanel.Horn_High.MouseButton1Down:Connect(function() 
					train:StopHorn(train.hornTypes.Low)
					train:StartHorn(train.hornTypes.High)
				end)
				drivingUI.Widgets.ControlPanel.Horn_High.MouseButton1Up:Connect(function() 
					train:StopHorn(train.HornType.High)
				end)
				
				hoverEffect(drivingUI.Widgets.ControlPanel.Horn_Low)
				drivingUI.Widgets.ControlPanel.Horn_Low.MouseButton1Down:Connect(function() 
					train:StopHorn(train.hornTypes.High)
					train:StartHorn(train.hornTypes.Low)
				end)
				drivingUI.Widgets.ControlPanel.Horn_Low.MouseButton1Up:Connect(function() 
					train:StopHorn(train.HornType.Low)
				end)
			end

			-- Throttle
			do
				local moving
				local throttle = drivingUI.Widgets.ThrottleControl
				local selector = throttle.Selector
				local tractionNotches = math.floor(1 / train.config.tractionIncrement + 0.5)
				local brakeNotches = math.floor(1 / train.config.brakeIncrement + 0.5)
				local notchSpacing = tractionNotches + brakeNotches + 2
				local neutralPosition = brakeNotches + 1
				local originalSelectorSize = selector.Size
				local notchGui

				local function getThrottlePosition()
					if train.throttle < 0 then
						return UDim2.fromScale(0.5, (neutralPosition - brakeNotches * -train.throttle) / notchSpacing)
					elseif train.throttle > 0 then
						return UDim2.fromScale(0.5, (tractionNotches * train.throttle + neutralPosition) / notchSpacing)
					else
						return UDim2.fromScale(0.5, neutralPosition / notchSpacing)
					end
				end

				-- Initialise throttle bar
				do
					local notchTemplate = throttle.Notches.Notch
					notchTemplate.Parent = nil

					-- Create neutral notch
					do
						local notch = notchTemplate:Clone()
						notch.Position = UDim2.fromScale(0.5, neutralPosition / notchSpacing)
						notch.Name = "N"
						notch.Parent = throttle.Notches
						throttle.Centre.Position = notch.Position
					end
					
					-- Create traction notches
					for i = 1, tractionNotches do
						local notch = notchTemplate:Clone()
						local position = neutralPosition + i
						notch.Position = UDim2.fromScale(0.5, position / notchSpacing)
						notch.Name = table.concat({"P", i})
						notch.Parent = throttle.Notches
					end

					-- Create brake notches
					for i = brakeNotches, 1, -1 do
						local notch = notchTemplate:Clone()
						local position = brakeNotches - i + 1
						notch.Position = UDim2.fromScale(0.5, position / notchSpacing)
						notch.Name = table.concat({"B", i})
						notch.Parent = throttle.Notches
					end

					-- Centre selector
					selector.Position = getThrottlePosition()
					 
					-- Set colour
					if train.throttle > 0 then
						selector.ImageColor3 = TRACTION_SELECTOR_COLOR3
					elseif train.throttle < 0 then
						selector.ImageColor3 = BRAKE_SELECTOR_COLOR3
					else
						selector.ImageColor3 = NEUTRAL_SELECTOR_COLOR3
					end
				end

				train.throttleChangedEvent.Event:Connect(function()
					selector:TweenSize(
						UDim2.fromScale(
							originalSelectorSize.X.Scale * SELECTOR_SIZE_CHANGE, 
							originalSelectorSize.Y.Scale * SELECTOR_SIZE_CHANGE
						),
						Enum.EasingDirection.Out,
						Enum.EasingStyle.Sine,
						SELECTOR_SIZE_CHANGE_TIME,
						true
					)
					moving = true
					selector:TweenPosition(
						getThrottlePosition(),
						Enum.EasingDirection.Out,
						Enum.EasingStyle.Sine,
						THROTTLE_MOVE_TIME,
						true,
						function()
							selector:TweenSize(
								originalSelectorSize,
								Enum.EasingDirection.Out,
								Enum.EasingStyle.Sine,
								SELECTOR_SIZE_CHANGE_TIME,
								false,
								function()
									moving = false
								end
							)
						end
					)

					local notch = math.floor(train.throttle * 100 + 0.5) * 0.01
					if notch > 0 then
						notch = table.concat({"P", math.abs(math.floor(notch / train.config.tractionIncrement + 0.5))})
						Animations.fadeColour(selector, "ImageColor3", selector.ImageColor3, TRACTION_SELECTOR_COLOR3, SELECTOR_SIZE_CHANGE_TIME)
					elseif notch < 0 then
						notch = table.concat({"B", math.abs(math.floor(notch / train.config.brakeIncrement + 0.5))})
						Animations.fadeColour(selector, "ImageColor3", selector.ImageColor3, BRAKE_SELECTOR_COLOR3, SELECTOR_SIZE_CHANGE_TIME)
					else
						notch = "N"
						Animations.fadeColour(selector, "ImageColor3", selector.ImageColor3, NEUTRAL_SELECTOR_COLOR3, SELECTOR_SIZE_CHANGE_TIME)
					end
					if notchGui then
						notchGui.ImageColor3 = subColor3(notchGui.ImageColor3, NOTCH_SELECTED_COLOUR_EFFECT)
					end
					notchGui = throttle.Notches:FindFirstChild(notch)
					if notchGui then
						notchGui.ImageColor3 = addColor3(notchGui.ImageColor3, NOTCH_SELECTED_COLOUR_EFFECT)
					end
					selector.ThrottleLabel.Throttle.Text = notch
				end)

				UserInputService.TouchMoved:Connect(function(touch, gameProcessed) 
					if not gameProcessed then
						-- TO DO: Throttle mobile controls
					end
				end)
			end

			-- Update driving UI
			connections.heartbeat = RunService.Heartbeat:Connect(function()
				updateDrivingHeartbeat(train)
			end)
			connections.delayRepeat = Thread.DelayRepeat(DRIVING_STATS_UPDATE_INTERVAL, function() 
				updateDrivingStats(train)
			end)

			-- Initially update timetable
			updateTimetable(train.timetable)

			-- Enable driving UI
			drivingUI.Parent = player.PlayerGui
		end
	end)
	player.CharacterRemoving:Connect(function(character)
		-- Destroy connections
		drivingUI:Destroy()
		drivingUI = script.DrivingUI
		disconnectAll(connections)
	end)
end

-- On datastore update
-- do
-- 	local alerts = gui.Alerts
-- 	local pointsNotifications = {}
-- 	local alertFinished = Instance.new("BindableEvent")
-- 	local pointsAlertPosition = alerts.Points.Position
-- 	remotes.DataStoreUpdate.OnClientEvent:Connect(function(currency, value)
-- 		if currency == "points" then
-- 			stats.Points.Text = value < 100000 and separateDigits(value) or
-- 				separateDigits(table.concat({math.floor(value * 0.001), "K+"}))
-- 			coroutine.wrap(function()
-- 				if points and value > points then
-- 					table.insert(pointsNotifications, value)
-- 					while pointsNotifications[1] ~= value do
-- 						alertFinished.Event:Wait()
-- 					end
-- 					alerts.Points.TextLabel.Text = table.concat({"+", separateDigits(tostring(value - points)), " points"})
-- 					points = value
-- 					alerts.Points:TweenPosition(
-- 						UDim2.new(
-- 							pointsAlertPosition.X.Scale,
-- 							pointsAlertPosition.X.Offset,
-- 							-pointsAlertPosition.Y.Scale,
-- 							pointsAlertPosition.Y.Offset
-- 						),
-- 						Enum.EasingDirection.Out,
-- 						Enum.EasingStyle.Quad,
-- 						TWEEN_TIME,
-- 						true
-- 					)
-- 					wait(TWEEN_TIME + POINTS_ALERT_TIME)
-- 					alerts.Points:TweenPosition(
-- 						pointsAlertPosition,
-- 						Enum.EasingDirection.Out,
-- 						Enum.EasingStyle.Quad,
-- 						TWEEN_TIME,
-- 						true
-- 					)
-- 					wait(TWEEN_TIME)
-- 					table.remove(pointsNotifications, 1)
-- 					alertFinished:Fire()
-- 				else
-- 					points = value
-- 				end
-- 			end)()
-- 		elseif currency == "experience" then
-- 			experience = value
-- 		end
-- 	end)
-- end

-- Configure CoreGui
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
pcall(function() 
	StarterGui:SetCore("ResetButtonCallback", false) 
end)

-- Create gauge segments
do
	local template = drivingUI.Widgets.Speed_Widget.Segments.Template
	for i = 1, GAUGE_SEGMENTS do
		local gaugeSegment = template:Clone()
		gaugeSegment.Parent = drivingUI.Widgets.Speed_Widget.Segments
		gaugeSegment.Name = tostring(i)
		gaugeSegment.Rotation = (i / (GAUGE_SEGMENTS + 1)) * gaugeRange + GAUGE_MIN_POSITION
		table.insert(gaugeSegmentsRotations, gaugeSegment.Rotation)
	end
	template:Destroy()
end

-- Enable GUI
gameUI.Parent = player.PlayerGui

-- Spawn train
Thread.Delay(SPAWN_DELAY, function()
	local teleportData = TeleportService:GetLocalPlayerTeleportData()
	spawnTrain:FireServer(
		teleportData and teleportData.arrivalPoint,
		teleportData and teleportData.trainType or DEFAULT_TRAIN
	)
end)