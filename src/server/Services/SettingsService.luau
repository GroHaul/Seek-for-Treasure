--!strict
--[[
	SettingsService: per-player settings (Reduce screen shake, music, sfx) and the
	tutorial-done flag. Both are plain booleans in the profile.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local RemoteService = require(script.Parent.RemoteService)
local StateService = require(script.Parent.StateService)
local Guard = require(script.Parent.Parent.Util.Guard)

local SETTING_KEYS = { reduceShake = true, music = true, sfx = true }

local SettingsService = {}

function SettingsService.init() end

function SettingsService.start()
	RemoteService.on(Net.Settings_Set, 2, 4, function(player, profile, keyArg, valueArg)
		local key = Guard.oneOf(keyArg, SETTING_KEYS, 16)
		local value = Guard.bool(valueArg)
		if key == nil or value == nil then
			return
		end
		(profile.settings :: any)[key] = value
		StateService.markDirty(player, "settings")
	end)
	RemoteService.on(Net.Tutorial_Done, 0.2, 1, function(player, profile)
		if not profile.flags.tutorialDone then
			profile.flags.tutorialDone = true
			StateService.markDirty(player, "flags")
		end
	end)
end

return SettingsService
