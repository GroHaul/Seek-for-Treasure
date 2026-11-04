--!strict
--[[
	Shared type definitions (both server and client require this).
	Step 1 holds the Config shapes; later steps add profile and remote payload types.
]]

-- Config/Rarities -------------------------------------------------------------
export type Rarity = {
	id: string,
	name: string,
	order: number, -- 1 (Common) .. 10 (Secret)
	oneIn: number, -- base odds "1 in N" at Luck 1; 0 for Common (takes the remainder)
	baseCps: number, -- cash/sec at segment multiplier 1, no mutation
	color: string, -- hex, converted with Color3.fromHex on use
	colorEnd: string?, -- second gradient stop (Cosmic)
	rainbowEdge: boolean?, -- animated rainbow edge (Secret)
	revealTier: number, -- 0..8, see Config/Reveal
}

-- Config/Mutations ------------------------------------------------------------
export type MutationFamilyId = "finish" | "aura"

export type ParticleSpec = {
	preset: string,
	rate: number,
	lifetime: number?,
}

export type MutationVisual = {
	material: string?, -- Enum.Material name
	color: string?,
	reflectance: number?,
	transparency: number?,
	hueCycleSeconds: number?,
	highlightColor: string?,
	highlightHueCycle: boolean?,
	lightRange: number?, -- PointLight in the rarity color
	particles: ParticleSpec?,
	beams: { preset: string, count: number }?,
	trail: string?,
}

export type Mutation = {
	id: string,
	name: string,
	family: MutationFamilyId,
	mult: number,
	weight: number,
	bit: number, -- Index bitmask bit (power of two)
	visual: MutationVisual,
}

export type MutationFamily = {
	id: MutationFamilyId,
	name: string,
	baseChance: number,
	chanceCap: number,
	entries: { Mutation },
}

export type MutationsConfig = {
	totalCap: number,
	families: { MutationFamily },
}

-- Config/Pity -----------------------------------------------------------------
export type PityFloor = {
	id: string,
	minRarity: number, -- guaranteed rarity order or better
	guaranteeAt: number, -- this many consecutive searches without it forces it
}

-- Config/Tools ----------------------------------------------------------------
export type ToolTier = {
	tier: number,
	interval: number, -- seconds per search
	luck: number,
	mutation: number, -- multiplier on both mutation chances
	basePrice: number, -- times the segment's toolPriceMult
}

export type ToolsConfig = {
	minSearchInterval: number,
	tiers: { ToolTier },
}

-- Config/Segments -------------------------------------------------------------
export type Treasure = {
	id: string,
	name: string,
	rarity: number,
	weight: number,
	model: string, -- asset name under ReplicatedStorage.Assets.Treasures.<segment>
	description: string, -- one-line ForgeGUI model description (GDD §4.2)
}

export type ToolName = {
	tier: number,
	id: string,
	name: string,
}

export type Segment = {
	id: string,
	name: string,
	area: string,
	theme: string,
	order: number,
	unlockCost: number,
	incomeMult: number,
	toolPriceMult: number,
	toolLine: string,
	tools: { ToolName },
	treasures: { Treasure },
}

-- Config/Potions --------------------------------------------------------------
export type PotionEffect = "luck" | "speed" | "mutation" | "cash"

export type Potion = {
	id: PotionEffect,
	name: string,
	multiplier: number,
	durationSeconds: number,
	priceSeconds: number, -- price = max(minPrice, priceSeconds * base plot income)
	minPrice: number,
}

export type PotionsConfig = {
	maxRemainingSeconds: number,
	list: { Potion },
}

-- Config/Upgrades -------------------------------------------------------------
export type UpgradesConfig = {
	slots: {
		start: number,
		max: number,
		passExtra: number,
		basePrice: number, -- price of the next slot = basePrice * growth ^ slotsBought
		growth: number,
	},
}

-- Config/Rebirth --------------------------------------------------------------
export type RebirthConfig = {
	baseCost: number,
	mvpBaseCost: number, -- used while only one segment exists
	growth: number,
	cashBonusPerRebirth: number,
	luckBonusPerRebirth: number,
	keepAllTreasures: boolean,
}

-- Config/Economy --------------------------------------------------------------
export type EconomyConfig = {
	luckCap: number,
	startingCash: number,
	sellSeconds: number,
	offlineRate: number,
	offlineCapSeconds: number,
	inventoryCap: number,
	autoSellBelowRarity: number,
	vaultTickSeconds: number,
	migrationCompensationSeconds: number,
}

-- Config/Plot -----------------------------------------------------------------
export type PlotConfig = {
	plotsPerServer: number,
	gridColumns: number,
	gridRows: number,
	pedestalByRarity: { string },
}

-- Config/Index ----------------------------------------------------------------
export type IndexMilestone = {
	fraction: number,
	luckBonus: number,
}

export type IndexConfig = {
	milestones: { IndexMilestone },
}

-- Config/Onboarding -----------------------------------------------------------
export type OnboardingConfig = {
	forcedMinRarity: { [number]: number }, -- search number -> minimum rarity order
	tutorialSteps: { { id: string, text: string } },
}

-- Config/Reveal ---------------------------------------------------------------
export type RevealTier = {
	tier: number,
	seconds: number,
	shakePx: number,
	skippableAfter: number?, -- nil = not skippable
	toast: boolean,
	sound: string,
}

export type RevealConfig = {
	tiers: { RevealTier },
	mutationStampSeconds: number,
	safeCenterWidth: number,
	banner: { minRarity: number, seconds: number, queueMax: number },
}

-- Config/Social ---------------------------------------------------------------
export type SocialConfig = {
	friendBoost: { perFriend: number, cap: number },
	codes: { maxLength: number, maxFailures: number, failureWindowSeconds: number, cooldownSeconds: number },
	codeBoard: { likeMilestones: { number }, fallbackText: string },
	likeCounter: { enabled: boolean, pollSeconds: number, proxyBaseUrl: string },
}

return nil
