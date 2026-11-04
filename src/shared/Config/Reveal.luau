--!strict
--[[
	Config/Reveal: GDD §9.1. Cinematic per reveal tier (Rarity.revealTier).
	skippableAfter = seconds before the skip button appears; nil = not skippable.
	The composition stays inside the center safeCenterWidth of the screen (9:16 crop).
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Reveal: Types.RevealConfig = {
	tiers = {
		{ tier = 0, seconds = 1.2, shakePx = 0, skippableAfter = nil, toast = true, sound = "pop" },
		{ tier = 1, seconds = 0.8, shakePx = 0, skippableAfter = 0, toast = false, sound = "ding" },
		{ tier = 2, seconds = 1.4, shakePx = 2, skippableAfter = 0, toast = false, sound = "whoosh_sparkle" },
		{ tier = 3, seconds = 2.2, shakePx = 4, skippableAfter = 1, toast = false, sound = "drumroll_cymbal" },
		{ tier = 4, seconds = 3.0, shakePx = 6, skippableAfter = nil, toast = false, sound = "choir_hit" },
		{ tier = 5, seconds = 4.0, shakePx = 8, skippableAfter = nil, toast = false, sound = "heavenly_choir" },
		{ tier = 6, seconds = 5.0, shakePx = 10, skippableAfter = nil, toast = false, sound = "orchestral_swell" },
		{ tier = 7, seconds = 6.0, shakePx = 12, skippableAfter = nil, toast = false, sound = "bass_drop" },
		{ tier = 8, seconds = 7.5, shakePx = 14, skippableAfter = nil, toast = false, sound = "secret_stinger" },
	},
	mutationStampSeconds = 0.5,
	safeCenterWidth = 0.5,
	banner = { minRarity = 6, seconds = 5, queueMax = 3 },
}

return DeepFreeze(Reveal)
