local config = {}

-- Physics (SI units)
local POWER = 1200000
local MAX_TRACTIVE_FORCE = 120000
config.getTractiveForce = function(v, t)
	return math.min(POWER / v, MAX_TRACTIVE_FORCE) * t
end
config.getResistance = function(v)
	return
		2.4408342217133668e+002
		+ -6.6956077015743858e+001 * v
		+  9.6682473704699188e+000 * v * v
end
config.getBrakeForce = function(v, t) 
	return v > 4 and 190000 * t or 280000 * t
end
config.mass = 173000
config.scale = 400/287 -- 1 meter : studs
config.tractionIncreaseRate = 1
config.tractionDecreaseRate = 1
config.brakeIncreaseRate = 1
config.brakeDecreaseRate = 1

-- Controls
config.tractionIncrement = 0.25
config.brakeIncrement = 1/3
config.throttleChangeInterval = 0.5

-- Configuration
config.trainType = "Class 377"
local AXLE_NAME = "AXLE"
local LEFT_DOOR_NAME = "LEFT_DOOR" -- Door to the left in the doorway
local RIGHT_DOOR_NAME = "RIGHT_DOOR"
local DOOR_INDICATOR_NAME_LEFT = "DOOR_INDICATOR_LEFT"
local DOOR_INDICATOR_NAME_RIGHT = "DOOR_INDICATOR_RIGHT"
config.doorIndicatorClosedTransparency = 1
config.doorIndicatorOpenTransparency = 0
config.height = 3.3
config.carriages = script.Parent.Carriages:GetChildren()
config.doorOpenSequence = {
	{
		Vector3.new(-0.1, 0, 0.1),
		TweenInfo.new(
			0.7,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.Out
		)
	},
	{
		Vector3.new(-1, 0, 0),
		TweenInfo.new(
			2,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out
		)
	}
}
config.doorCloseSequence = {
	{
		Vector3.new(),
		TweenInfo.new(2.5)
	},
	{
		Vector3.new(1, 0, 0),
		TweenInfo.new(
			2,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.Out
		)
	},
	{
		Vector3.new(0.1, 0, -0.1),
		TweenInfo.new(
			0.7,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out
		)
	},
	{
		Vector3.new(),
		TweenInfo.new(1)
	}
}
config.doorMultiplier00 = Vector3.new(-1, 1, -1)
config.doorMultiplier01 = Vector3.new(1, 1, -1)
config.doorMultiplier10 = Vector3.new(1, 1, 1)
config.doorMultiplier11 = Vector3.new(-1, 1, 1)
config.minimumPlatformHeight = -1
-- % of carriage from centre that must be on a platform for doors to open
config.miniumumDoorOpenPlatformedArea = 0.6

-- Axles
config.wheelCircumference = 3.456

-- Cameras (must be attachments)
config.cabCameras = {
	script.Parent.Carriages["1"].PrimaryPart.CAB_CAMERA,
}
config.passengerCameras = {
	script.Parent.Carriages["1"].PrimaryPart.INT_CAMERA,
	script.Parent.Carriages["1"].PrimaryPart.DOOR_CAMERA
}
config.cabCameraOscillationMaxSpeed = 50

-- Sound
config.globalSounds = {
	Static = {
		SoundId = "rbxassetid://4759693128",
		Volume = 0.5,
		EmitterSize = 10,
		Looped = true,
		Playing = true
	},
	Whine = {
		SoundId = "rbxassetid://4760140808",
		Volume = 0,
		EmitterSize = 10,
		Looped = true,
		Playing = true
	},
	Motor = {
		SoundId = "",
		Volume = 0,
		EmitterSize = 10,
		Looped = true,
		Playing = true
	},
	Running = {
		SoundId = "rbxassetid://4948820361",
		Volume = 0,
		EmitterSize = 10,
		Looped = true,
		Playing = true
	},
	DoorOpen = {
		SoundId = "rbxassetid://4748641272",
		Volume = 1,
		EmitterSize = 10,
		Looped = false,
		Playing = false
	},
	DoorClose = {
		SoundId = "rbxassetid://4748640910",
		Volume = 1,
		EmitterSize = 10,
		Looped = false,
		Playing = false
	}
}
-- Property = throttle property * speed property
-- Note: actual values are interpolated using linear regression
config.soundDynamics = {
	["0"] = {
		Motor = {
			PlaybackSpeed = 0.7,
			Volume = 0
		},
		Whine = {
			Volume = 0
		},
		Running = {
			Volume = 0,
			PlaybackSpeed = 0.5,
		}
	},
	["0.3"] = {
		Motor = {
			PlaybackSpeed = 0.7,
			Volume = 0
		},
		Whine = {
			Volume = 0.8
		},
		Running = {
			Volume = 0,
			PlaybackSpeed = 0.5,
		}
	},
	["5"] = {
		Motor = {
			PlaybackSpeed = 0.8,
			Volume = 1
		},
		Whine = {
			Volume = 0.9
		},
		Running = {
			Volume = 0.15,
			PlaybackSpeed = 0.4,
		}
	},
	["15"] = {
		Motor = {
			PlaybackSpeed = 1,
			Volume = 1
		},
		Whine = {
			Volume = 0.1
		},
		Running = {
			Volume = 0.4,
			PlaybackSpeed = 0.5,
		}
	},
	["25"] = {
		Motor = {
			PlaybackSpeed = 1.2,
			Volume = 1
		},
		Whine = {
			Volume = 0.05
		},
		Running = {
			Volume = 0.6,
			PlaybackSpeed = 0.7
		}
	},
	["35"] = {
		Motor = {
			PlaybackSpeed = 1.2,
			Volume = 1
		},
		Whine = {
			Volume = 0.05
		},
		Running = {
			Volume = 1.7,
			PlaybackSpeed = 0.9
		}
	},
	["50"] = {
		Motor = {
			PlaybackSpeed = 1.2,
			Volume = 1
		},
		Whine = {
			Volume = 0.05
		},
		Running = {
			Volume = 2,
			PlaybackSpeed = 1.1
		}
	}
}
config.awsSounds = {
	Clear = {
		SoundId = "rbxassetid://4742268067",
		Volume = 1,
		EmitterSize = 1,
		Looped = false
	},
	Warn = {
		SoundId = "rbxassetid://4742253590",
		Volume = 1,
		EmitterSize = 1,
		Looped = true
	}
}

-- Get axles and doors
do
	local leftDoors = {} -- Not on the left side, but on the door on the left of each doorway
	local rightDoors = {}
	local rightSideDoorIndicators = {}
	local leftSideDoorIndicators = {}
	local axles = {}
	for i, v in pairs(config.carriages) do
		local carriageName = v.Name
		leftDoors[carriageName] = {}
		rightDoors[carriageName] = {}
		for i, v in pairs(v:GetDescendants()) do
			if v:IsA("BasePart") then
				if v.Name == AXLE_NAME then
					table.insert(axles, v)
				elseif v.Name == LEFT_DOOR_NAME then
					table.insert(leftDoors[carriageName], v)
				elseif v.Name == RIGHT_DOOR_NAME then
					table.insert(rightDoors[carriageName], v)
				elseif v.Name == DOOR_INDICATOR_NAME_RIGHT then
					rightSideDoorIndicators[carriageName] = v
				elseif v.Name == DOOR_INDICATOR_NAME_LEFT then
					leftSideDoorIndicators[carriageName] = v
	 			end
			end
		end
	end
	config.axles = axles
	config.leftDoors = leftDoors
	config.rightDoors = rightDoors
	config.leftSideDoorIndicators = leftSideDoorIndicators
	config.rightSideDoorIndicators = rightSideDoorIndicators
end

return config