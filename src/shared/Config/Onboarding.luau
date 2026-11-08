--!strict
--[[
	Config/Onboarding: GDD §1.2, §9.5 (moved into the MVP at Checkpoint 1).
	A brand-new profile (0 rebirths) gets forced minimum rarities on these search
	numbers; the tutorial is 5 arrow steps, skippable, under 60 s.
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Onboarding: Types.OnboardingConfig = {
	forcedMinRarity = {
		[3] = 2, -- search #3 -> Uncommon or better
		[8] = 3, -- search #8 -> Rare or better
	},
	tutorialSteps = {
		{ id = "walk", text = "Follow the pawprints to Pawprint Meadow!" },
		{ id = "watch", text = "Stand still - your whistle searches for you." },
		{ id = "collect", text = "Your pets earn cash. Step on your Collect pad!" },
		{ id = "buy", text = "Visit the Tools stall and buy the Wooden Whistle." },
		{ id = "back", text = "Head back to the meadow and keep searching!" },
	},
}

return DeepFreeze(Onboarding)
