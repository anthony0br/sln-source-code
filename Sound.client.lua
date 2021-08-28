-- Services
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Modules
local Thread = require(ReplicatedStorage.Modules.Thread)

-- Constants
local SCALE = 0.7175
local DOPPLER_SCALE = 1
local ROLLOFF_SCALE = 1
local UPDATE_INTERVAL = 1/20
local RAY_LENGTH = 100

-- Ambient changing settings
local CarpettedHallway = 5
local Cave = 15
local Auditorium = 100

-- Initialisation
SoundService.DistanceFactor = SCALE
SoundService.DopplerScale = DOPPLER_SCALE
SoundService.RolloffScale = ROLLOFF_SCALE
local raycastParams = RaycastParams.new()
raycastParams.IgnoreWater = true

-- Update sound environment
Thread.DelayRepeat(UPDATE_INTERVAL, function()
	local result = workspace:Raycast(workspace.CurrentCamera.CFrame.Position, Vector3.new(0, RAY_LENGTH, 0), raycastParams)
	local distance = result and math.abs(result.Position.Y - workspace.CurrentCamera.CFrame.Position.Y) or 0
	if Players.LocalPlayer.Character then
		if distance == 0 then
			SoundService.AmbientReverb = Enum.ReverbType.GenericReverb
		elseif distance <= CarpettedHallway then
			SoundService.AmbientReverb = Enum.ReverbType.CarpettedHallway
		elseif distance <= Cave then
			SoundService.AmbientReverb = Enum.ReverbType.Cave
		elseif distance <= Auditorium then
			SoundService.AmbientReverb = Enum.ReverbType.Auditorium
		end
	else
		SoundService.AmbientReverb = Enum.ReverbType.NoReverb
	end
end)