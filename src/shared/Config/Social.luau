--!strict
--[[
	Config/Social: GDD §9.7. Code STRINGS are secret and live server-only in
	ServerStorage.Secrets.Codes; only the public rules and board text are here.
	likeCounter stays disabled until you approve "Allow HTTP Requests" and a proxy;
	the board then falls back to fallbackText ("{n}" = next milestone).
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Social: Types.SocialConfig = {
	friendBoost = { perFriend = 0.1, cap = 0.5 },
	codes = { maxLength = 20, maxFailures = 10, failureWindowSeconds = 600, cooldownSeconds = 600 },
	codeBoard = {
		likeMilestones = { 1000, 2500, 5000, 10000, 25000, 50000, 100000 },
		fallbackText = "Next code at {n} likes!",
	},
	likeCounter = { enabled = false, pollSeconds = 300, proxyBaseUrl = "" },
}

return DeepFreeze(Social)
