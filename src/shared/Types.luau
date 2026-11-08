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
	modelAssetId: number?, -- Roblox Model asset uploaded from ForgeGUI; nil = placeholder ball
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

-- Profile (GDD §11.1) ---------------------------------------------------------
export type InventoryEntry = {
	id: string, -- treasure id, e.g. "pets_ember_fox"
	segment: string,
	rarity: number, -- 1..10
	mutation: { string }, -- 0..2 ids (one Finish + one Aura max)
	level: number, -- 1..10 (enhancement; MVP always 1)
	t: number, -- unix time found
}

export type Profile = {
	schema: number,
	cash: number,
	vault: number,
	lifetimeEarned: number,
	rebirths: number,
	inventory: { [string]: InventoryEntry }, -- key = uid "t<n>"
	nextUid: number,
	plot: { slots: number, layout: { [string]: string } }, -- "1".."24" -> uid
	tools: { [string]: { owned: number, equipped: number } },
	segments: { [string]: boolean },
	potions: { luck: number, speed: number, mutation: number, cash: number }, -- unix expiry, 0 = none
	pity: { epic: number, legendary: number, mythic: number },
	index: { [string]: { n: number, m: number } }, -- treasureId -> count found, mutation bitmask
	indexRewards: { [string]: number }, -- segment -> highest milestone claimed (0..3)
	codes: { [string]: number }, -- code -> unix time redeemed
	streak: { day: number, lastDay: number },
	stats: {
		searches: number,
		playtime: number,
		rarest: { id: string, rarity: number, mutation: { string } }?,
	},
	purchases: { [string]: number },
	settings: { reduceShake: boolean, music: boolean, sfx: boolean },
	flags: { tutorialDone: boolean },
	lastOnline: number,
	_lock: { jobId: string, t: number }?,
	_legacy: { [string]: any }?,
}

-- Remote payloads (S -> C) ----------------------------------------------------
export type SearchStatePayload = {
	active: boolean,
	segmentId: string?,
	interval: number,
	startedAt: number, -- workspace:GetServerTimeNow() when the current search began
}

export type RevealPayload = {
	uid: string?, -- nil when the find was auto-sold (inventory full)
	treasureId: string,
	rarity: number,
	mutation: { string },
	soldFor: number?,
	pity: { id: string, remaining: number }?, -- nearest pity floor after this find
}

return nil
