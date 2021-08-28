local Players = game:GetService("Players")
local ScriptService = game:GetService("ServerScriptService")
local ChatService = require(ScriptService:WaitForChild("ChatServiceRunner").ChatService)

local ranks = {
	["255"] = {TagText = "Developer", TagColor = Color3.fromRGB(240, 190, 10), ChatColor = Color3.fromRGB(255, 230, 220)},
    ["253"] = {TagText = "Developer", TagColor = Color3.fromRGB(240, 190, 10), ChatColor = Color3.fromRGB(255, 230, 220)},
	["251"] = {TagText = "Moderator", TagColor = Color3.fromRGB(250, 58, 44), ChatColor = Color3.fromRGB(255, 230, 220)},
	["252"] = {TagText = "Contributor", TagColor = Color3.fromRGB(200, 150, 30), ChatColor = Color3.fromRGB(255, 255, 255)},
    ["230"] = {TagText = "Tester", TagColor = Color3.fromRGB(0, 204, 153), ChatColor = Color3.fromRGB(255, 255, 255)},
}
local groupId = 4713730

-- Add system message
local chatChannel = ChatService:GetChannel("All")
chatChannel.WelcomeMessage = "Welcome to South London Network. Press / to chat."

-- Messages and tags for new joiners
ChatService.SpeakerAdded:Connect(function(SpeakerName)
    if game.Players:FindFirstChild(SpeakerName) then
		local plr = game.Players:FindFirstChild(SpeakerName)
        local Speaker = ChatService:GetSpeaker(SpeakerName) 
		local role = ""
        if plr:IsInGroup(groupId) then
            local rank = plr:GetRankInGroup(groupId)
           	local tag = ranks[tostring(rank)]
			if tag then
                Speaker:SetExtraData("Tags", {{TagText = tag.TagText, TagColor = tag.TagColor}})
                Speaker:SetExtraData("NameColor", tag.TagColor)
				Speaker:SetExtraData("ChatColor", tag.ChatColor)
				role = table.concat({tag.TagText, " "})
            end   
        end
		chatChannel:SendSystemMessage(table.concat({role, SpeakerName, " has joined the server."}))
    end
end)

Players.PlayerRemoving:Connect(function(player)
	chatChannel:SendSystemMessage(table.concat({player.Name, " has left the server."}))
end)