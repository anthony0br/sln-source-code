local train = {}

-- UI
train.name = script.Name
train.icon = ""
train.thumbnail = ""
train.description = [[Family Name: Electrostar
Max. Operating Speed: 100mph (160km/h)
Power Supply: 25kV AC OHLE + 750V DC Third Rail
Length: 4-12 cars
Built: 239
In service: 2003 - present
]]

-- Configuration
train.configurations = {4, 8, 12}
train.operatorLiveries = {
    ["Sussex Rail"] = {"Green and White"}
}

-- Availability
train.price = 0
train.groupId = false
train.groupRank = false

return train