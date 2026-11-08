--!strict
--[[
	Boosts: gamepass, VIP, server-wide and upgrade modifiers (GDD §10, §15).

	Gamepass ownership is mirrored by the server into Player attributes
	"Pass_<key>" = true, and the Server Luck Boost into the workspace attribute
	SFT_ServerLuckUntil (unix time). Attributes set by the server replicate to
	clients but a client's own changes never reach the server, so the server can
	trust what it reads here, and the HUD shows the same numbers it computes.
]]

local Types = require(script.Parent.Types)
local UpgradeMath = require(script.Parent.UpgradeMath)
local Config = script.Parent.Config
local Monetization = require(Config.Monetization) :: Types.MonetizationConfig
local Economy = require(Config.Economy) :: Types.EconomyConfig

local BASE_WALK_SPEED = 16

local Boosts = {
	SERVER_LUCK_ATTRIBUTE = "SFT_ServerLuckUntil",
}

function Boosts.hasPass(player: Player?, key: string): boolean
	return player ~= nil and player:GetAttribute("Pass_" .. key) == true
end

--- Seconds left on the Server Luck Boost (0 when inactive).
function Boosts.serverLuckRemaining(now: number): number
	local untilTime = workspace:GetAttribute(Boosts.SERVER_LUCK_ATTRIBUTE)
	return if type(untilTime) == "number" then math.max(0, untilTime - now) else 0
end

--- Luck multiplier from 2x Luck and the Server Luck Boost (before the luck cap).
function Boosts.luckMult(player: Player?, now: number): number
	local mult = 1
	if Boosts.hasPass(player, "luck2x") then
		mult *= Monetization.luck2xMult
	end
	if Boosts.serverLuckRemaining(now) > 0 then
		mult *= Monetization.serverLuckMult
	end
	return mult
end

--- Search interval multiplier from Fast Search.
function Boosts.intervalMult(player: Player?): number
	return if Boosts.hasPass(player, "fastSearch") then Monetization.fastSearchMult else 1
end

--- Permanent plot income multiplier: Cash Boost upgrade x 2x Cash x VIP.
--- Applies to live and offline income, never to potion prices.
function Boosts.cashMult(player: Player?, profile: any): number
	local mult = 1 + UpgradeMath.value(profile, "cash")
	if Boosts.hasPass(player, "cash2x") then
		mult *= Monetization.cash2xMult
	end
	if Boosts.hasPass(player, "vip") then
		mult *= Monetization.vip.cashMult
	end
	return mult
end

--- Offline earnings cap (seconds) and rate, with upgrades and VIP.
function Boosts.offline(player: Player?, profile: any): (number, number)
	local cap = Economy.offlineCapSeconds + UpgradeMath.value(profile, "offlineCap")
	local rate = Economy.offlineRate + UpgradeMath.value(profile, "offlineRate")
	if Boosts.hasPass(player, "vip") then
		cap += Monetization.vip.offlineCapBonusSeconds
		rate = math.max(rate, Monetization.vip.offlineRate)
	end
	return cap, math.min(rate, 1)
end

function Boosts.walkSpeed(profile: any): number
	return BASE_WALK_SPEED + UpgradeMath.value(profile, "walkSpeed")
end

return table.freeze(Boosts)
