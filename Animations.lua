-- Services
local RunService = game:GetService("RunService")

local module = {}

-- Fade between two colours in specific time
function module.fadeColour(gui, property, v0, v1, t, isSequence)
	local increment = 1 / (t * 60)
	if not isSequence then
		local lastValue = gui[property]
		for i = 0, 1, increment do
			if gui[property] == lastValue then
				gui[property] = v0:lerp(v1, i)
				lastValue = gui[property]
				RunService.RenderStepped:wait()
			else
				break
			end
		end
	else
		local lastValue = gui[property]
		for i = 0, 1, increment do
			if gui[property] == lastValue then
				local newSequence = {}
				for n = 1, #v0.Keypoints do
					newSequence[n] = ColorSequenceKeypoint.new(
						v0.Keypoints[n].Time * i + v1.Keypoints[n].Time * (1 - i),
						v0.Keypoints[n].Value:lerp(v1.Keypoints[n].Value, i)
					)
				end
				gui[property] = ColorSequence.new(newSequence)
				lastValue = gui[property]
				RunService.RenderStepped:wait()
			else
				break
			end
		end
	end
	gui[property] = v1
end

-- Fade between two numbers
function module.fadeNumber(gui, property, v0, v1, t)
	local lastValue = gui[property]
	local increment = 1 / (t * 60)
	for i = 0, 1, increment do
		if gui[property] == lastValue then
			gui[property] = v0 + i * (v1 - v0)
			lastValue = gui[property]
			RunService.RenderStepped:wait()
		else
			break
		end
	end
	gui[property] = v1
end

-- Automatically fade between two colours in specific time on hover
function module.createHoverEffect(inputGui, visualGui, property, v0, v1, t, isSequence)	
	local mouseEnter = inputGui.MouseEnter:Connect(function()
		module.fadeColour(visualGui, property, v0, v1, t, isSequence)
	end)
	local mouseLeave = inputGui.MouseLeave:Connect(function()
		module.fadeColour(visualGui, property, v1, v0, t, isSequence)
	end)
	return mouseEnter, mouseLeave
end

return module