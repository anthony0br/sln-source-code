-- Modules
local ResizeAlign = require(game.ServerStorage.ResizeAlign)

-- Functions

-- Make a clone and return matching parts
local function makeClone(template)
	-- Clone descendants
	local model = Instance.new("Model")
	model.Name = template.Name
	local copies = {}
	for i, v in pairs(template:GetChildren()) do
		if v:IsA("BasePart") then
			copies[v] = v:Clone()
			copies[v].Parent = model
		else
			local clone = v:Clone()
			if #v:GetChildren() > 0 then
				clone:ClearAllChildren()
				local container, cCopies = makeClone(v)
				for i, v in pairs(cCopies) do
					copies[i] = v
					v.Parent = clone
				end
				container:Destroy()
			end
			clone.Parent = model
		end
	end
	return model, copies
end

-- Moves a model to a CFrame
local function moveModel(model, cframe)
	local center = model:GetBoundingBox()
	for _, part in pairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local offset = center:ToObjectSpace(part.CFrame)
			local newCFrame = cframe:ToWorldSpace(offset)
			part.CFrame = newCFrame
		end
	end
end

local track = workspace.DoubleTrack
local startBlock = game:GetService("Selection"):Get()[1]
local blockSegmentCFrames = {}
local pointsTable = {(startBlock.CFrame * CFrame.new(0, 0, 0.5 * startBlock.Size.Z)).Position}

print("Initialising")

-- Trace path and calculates points
do
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {workspace.BoxTrack}
    raycastParams.FilterType = Enum.RaycastFilterType.Whitelist
    local block = startBlock
    while block do
        block.Parent = workspace
        table.insert(pointsTable, (block.CFrame * CFrame.new(0, 0, -0.5 * block.Size.Z)).Position)
        local raycastResult = workspace:Raycast(
            block.Position,
            block.CFrame * Vector3.new(0, 0, -block.Size.Z) - block.Position,
            raycastParams
        )
        block.Parent = workspace.BoxTrack
        table.insert(blockSegmentCFrames, block.CFrame)
        if raycastResult then
            block = raycastResult.Instance
        else
            block = nil
        end
        print(#pointsTable)
        wait()
    end
end

print("Building track")

-- Reconstruct track
do
    local path = Instance.new("Folder")
    path.Name = "ReplacedTrack"
    path.Parent = workspace
    local lastSegment
    local maxIterations = #pointsTable - 1
    local copiesTable = {}

    for i = 1, maxIterations do
        -- Create segment
        local segment, copies
        local template = lastSegment or track
        segment, copies = makeClone(template)
        table.insert(copiesTable, copies)
        segment.Parent = path
        
        -- Calculate length
        local P0, P1 = pointsTable[i], pointsTable[i + 1]
        local length = (P0 - P1).Magnitude
        
        -- Move the model to the correct CFrame
        moveModel(segment, blockSegmentCFrames[i])
        
        -- Set length of segments
        for i, v in pairs(copies) do
            v.Size = Vector3.new(v.Size.X, v.Size.Y, length)
        end
        
        -- Align all parts in the last segment
        if i == maxIterations then
            local orientation = segment:GetBoundingBox()
            orientation = orientation - orientation.Position
            local point = Instance.new("Part")
            point.Parent = workspace
            point.CFrame = orientation + P1
            for i, v in pairs(segment:GetDescendants()) do
                if v:IsA("BasePart") then
                    ResizeAlign.DoExtend(
                        {Object = v, Normal = Enum.NormalId.Front}, 
                        {Object = point, Normal = Enum.NormalId.Front}
                    )
                end
            end
        end

        lastSegment = segment
    end

    -- Fill gaps
    for i, v in ipairs(copiesTable) do
        if i > 1 then
            for i, v in pairs(v) do
                ResizeAlign.DoExtend(
                    {Object = i, Normal = Enum.NormalId.Front}, 
                    {Object = v, Normal = Enum.NormalId.Back}
                )
            end
        end
    end
end

print("Done")