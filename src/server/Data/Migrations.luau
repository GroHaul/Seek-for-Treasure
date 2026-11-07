--!strict
--[[
	Migrations (GDD §11.4). All functions are pure: they take a profile table and
	return it, never yield, never touch Instances. They run inside the load
	UpdateAsync transform.

	1. migrate: run steps[from] for every schema below CURRENT_SCHEMA.
	2. reconcile: deep-fill fields missing vs the template; move unknown top-level
	   keys into _legacy (kept for one version).
	3. sanitize: unknown treasure ids -> cash (60 s of their income at segment x1);
	   drop broken plot references; clamp slots and tool tiers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Catalog = require(Shared.Catalog)
local RollMath = require(Shared.RollMath)
local Config = Shared.Config
local Economy = require(Config.Economy) :: Types.EconomyConfig
local Upgrades = require(Config.Upgrades) :: Types.UpgradesConfig
local Tools = require(Config.Tools) :: Types.ToolsConfig

local ProfileTemplate = require(script.Parent.ProfileTemplate)

local Migrations = {}

-- steps[n] upgrades a schema-n profile to schema n+1. None yet (v1 is current).
local steps: { [number]: (any) -> any } = {}

local KEEP_UNKNOWN = { _lock = true, _legacy = true }

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value :: any do
		out[k] = deepCopy(v)
	end
	return out :: any
end
Migrations.deepCopy = deepCopy

function Migrations.migrate(profile: any): any
	local schema = if type(profile.schema) == "number" then profile.schema else 1
	while schema < ProfileTemplate.CURRENT_SCHEMA do
		local step = steps[schema]
		assert(step, `missing migration from schema {schema}`)
		profile = step(profile)
		schema += 1
		profile.schema = schema
	end
	profile.schema = schema
	return profile
end

-- Fill keys missing in `target` from `template`, recursing into dictionaries.
-- Collections keyed by uid/treasure id are left alone (template has them empty).
local function fill(target: { [any]: any }, template: { [any]: any })
	for key, default in template do
		local current = target[key]
		if current == nil then
			target[key] = deepCopy(default)
		elseif type(default) == "table" and type(current) == "table" and next(default) ~= nil then
			fill(current, default)
		elseif type(default) ~= type(current) and type(default) ~= "table" then
			-- wrong primitive type (corrupt field): reset to default
			target[key] = default
		end
	end
end

function Migrations.reconcile(profile: any): any
	local template = ProfileTemplate.new() :: any
	fill(profile, template)
	for key in profile do
		if template[key] == nil and not KEEP_UNKNOWN[key] and key ~= "stats" then
			profile._legacy = profile._legacy or {}
			profile._legacy[key] = profile[key]
			profile[key] = nil
		end
	end
	return profile
end

local function finiteOr(n: any, fallback: number): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	return n
end

--- Returns the sanitized profile and the cash granted for removed treasures.
function Migrations.sanitize(profile: Types.Profile): (Types.Profile, number)
	local compensation = 0
	profile.cash = math.max(0, finiteOr(profile.cash, 0))
	profile.vault = math.max(0, finiteOr(profile.vault, 0))
	profile.rebirths = math.max(0, math.floor(finiteOr(profile.rebirths, 0)))

	for uid, entry in profile.inventory do
		local treasure = if type(entry) == "table" then Catalog.treasureById[entry.id] else nil
		if treasure == nil then
			if type(entry) == "table" and type(entry.rarity) == "number" then
				local rarity = Catalog.rarities[math.clamp(math.floor(entry.rarity), 1, #Catalog.rarities)]
				local mutation = if type(entry.mutation) == "table" then entry.mutation else {}
				compensation += rarity.baseCps * RollMath.mutationMultiplier(mutation) * Economy.migrationCompensationSeconds
			end
			profile.inventory[uid] = nil
		else
			-- trust Config over the stored copy for derived fields
			entry.rarity = treasure.rarity
			entry.segment = Catalog.treasureSegment[entry.id]
			entry.level = math.clamp(math.floor(finiteOr(entry.level, 1)), 1, 10)
			if type(entry.mutation) ~= "table" then
				entry.mutation = {}
			end
		end
	end

	local maxSlots = Upgrades.slots.max + Upgrades.slots.passExtra
	profile.plot.slots = math.clamp(math.floor(finiteOr(profile.plot.slots, Upgrades.slots.start)), Upgrades.slots.start, maxSlots)
	local placed: { [string]: boolean } = {}
	for slot, uid in profile.plot.layout do
		local n = tonumber(slot)
		if n == nil or n < 1 or n > profile.plot.slots or n % 1 ~= 0 or profile.inventory[uid] == nil or placed[uid] then
			profile.plot.layout[slot] = nil
		else
			placed[uid] = true
		end
	end

	for segmentId, tool in profile.tools do
		if Catalog.segmentById[segmentId] == nil then
			profile.tools[segmentId] = nil
		else
			tool.owned = math.clamp(math.floor(finiteOr(tool.owned, 1)), 1, #Tools.tiers)
			tool.equipped = math.clamp(math.floor(finiteOr(tool.equipped, tool.owned)), 1, tool.owned)
		end
	end

	profile.cash += math.floor(compensation)
	return profile, compensation
end

--- Full load pipeline on a copy of the stored value.
function Migrations.prepare(stored: any): (Types.Profile, number)
	local profile = Migrations.migrate(deepCopy(stored))
	profile = Migrations.reconcile(profile)
	return Migrations.sanitize(profile)
end

--- True if every number in the table is finite (JSON-safe) and keys are JSON-safe.
function Migrations.isSerializable(value: any, depth: number?): boolean
	local d = depth or 0
	if d > 12 then
		return false
	end
	local t = type(value)
	if t == "number" then
		return value == value and value ~= math.huge and value ~= -math.huge
	elseif t == "string" or t == "boolean" then
		return true
	elseif t == "table" then
		for k, v in value do
			if type(k) ~= "string" and type(k) ~= "number" then
				return false
			end
			if not Migrations.isSerializable(v, d + 1) then
				return false
			end
		end
		return true
	end
	return false
end

return table.freeze(Migrations)
