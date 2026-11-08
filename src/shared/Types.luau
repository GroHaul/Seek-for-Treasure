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
export type PotionEffect = "luck" | "speed" | "mutation" | "cash" | "diamond"

export type Potion = {
	id: PotionEffect,
	name: string,
	multiplier: number,
	durationSeconds: number,
	priceSeconds: number, -- price = max(minPrice, priceSeconds * base plot income)
	minPrice: number,
	description: string,
}

-- One line of the Potions stall's stock table: each restock, the potion appears
-- with probability `chance`, with a stock of min..max (inclusive).
export type PotionStockEntry = {
	id: PotionEffect,
	chance: number,
	min: number,
	max: number,
}

export type PotionsConfig = {
	maxRemainingSeconds: number,
	bagMax: number, -- most potions of one kind a player can hold
	restockSeconds: number,
	list: { Potion },
	stock: { PotionStockEntry },
}

-- Config/Diamonds -------------------------------------------------------------
export type DiamondsConfig = {
	baseChance: number, -- chance per find before boosts
	chanceCap: number,
	byRarity: { number }, -- diamonds dropped by rarity order 1..10
}

-- Config/UpgradeTree ----------------------------------------------------------
export type UpgradeEffect =
	"none"
	| "luck"
	| "interval"
	| "cash"
	| "diamondChance"
	| "diamondAmount"
	| "mutation"
	| "walkSpeed"
	| "offlineCap"
	| "offlineRate"
	| "slots"

export type UpgradeNode = {
	id: string,
	name: string,
	description: string, -- "{v}" is replaced by the per-level value
	icon: string, -- UI/Assets key
	q: number, -- axial hex coordinates; the root is (0, 0)
	r: number,
	effect: UpgradeEffect,
	perLevel: number,
	costs: { number }, -- diamond price of level 1..n; #costs is the max level
	currency: "diamonds" | "cash" | "none",
	requires: string?, -- node that needs level >= 1 before this one shows
	comingSoon: boolean?,
}

export type UpgradeTreeConfig = {
	nodes: { UpgradeNode },
}

-- Config/Monetization ---------------------------------------------------------
export type PassInfo = {
	key: string,
	name: string,
	description: string,
	icon: string,
	id: number, -- Roblox gamepass id; 0 = not created yet ("Coming soon")
	price: number, -- Robux, shown until the live price loads
	luck: boolean?, -- changes the odds of free rolls (paid-random policy gate)
}

export type ProductGrant = {
	potions: { [string]: number }?, -- potion id -> count added to the bag
	diamonds: number?,
	cashSeconds: number?, -- seconds of the buyer's base plot income
	serverLuckSeconds: number?,
}

export type ProductInfo = {
	key: string,
	name: string,
	description: string,
	icon: string,
	id: number, -- Roblox developer product id; 0 = not created yet
	price: number,
	tab: "Potions" | "Diamonds" | "Boosts",
	grant: ProductGrant,
	luck: boolean?,
	featured: boolean?,
}

export type MonetizationConfig = {
	passes: { PassInfo },
	products: { ProductInfo },
	vip: { cashMult: number, offlineCapBonusSeconds: number, offlineRate: number },
	cash2xMult: number,
	luck2xMult: number,
	fastSearchMult: number,
	serverLuckMult: number,
	purchaseHistory: number, -- receipt ids kept in the profile
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
	potions: { luck: number, speed: number, mutation: number, cash: number, diamond: number }, -- unix expiry, 0 = none
	potionBag: { [string]: number }, -- potion id -> count held (drink from the hotbar)
	potionStock: { cycle: number, bought: { [string]: number } }, -- this restock's purchases
	diamonds: number,
	upgrades: { [string]: number }, -- upgrade-tree node id -> level
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
	diamonds: number?, -- diamonds this find dropped (nil = none)
}

return nil
