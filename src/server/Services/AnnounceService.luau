--!strict
--[[
	AnnounceService: the Mythic+ server banner (GDD §9.2). When anyone finds a
	Mythic or rarer treasure, every client in the server gets Announce_Banner
	{ displayName, treasureId, rarity, mutation }. Only ids and the Roblox
	DisplayName are sent (no free text). Sky beam and the cross-server
	announcement are backlog.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Reveal = require(Shared.Config.Reveal) :: Types.RevealConfig

local RemoteService = require(script.Parent.RemoteService)
local SearchService = require(script.Parent.SearchService)

local AnnounceService = {}

function AnnounceService.init() end

function AnnounceService.start()
	SearchService.found:Connect(function(player, info)
		if info.rarity < Reveal.banner.minRarity then
			return
		end
		RemoteService.fireAll(Net.Announce_Banner, {
			displayName = player.DisplayName,
			userId = player.UserId,
			treasureId = info.treasure.id,
			rarity = info.rarity,
			mutation = info.mutation,
		})
	end)
end

return AnnounceService
