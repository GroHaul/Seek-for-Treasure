--!strict
--[[
	ChatTagController: the "[VIP]" chat tag (GDD §10.1). A message from a player
	whose server-set attribute Pass_vip is true gets a sun-yellow [VIP] prefix.
	Uses TextChatService (the default chat).
]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local ChatTag = {}

function ChatTag.init() end

function ChatTag.start()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local source = message.TextSource
		local player = if source then Players:GetPlayerByUserId(source.UserId) else nil
		if player and player:GetAttribute("Pass_vip") == true then
			local properties = Instance.new("TextChatMessageProperties")
			properties.PrefixText = '<font color="#FFD23F">[VIP]</font> ' .. message.PrefixText
			return properties
		end
		return nil
	end
end

return ChatTag
