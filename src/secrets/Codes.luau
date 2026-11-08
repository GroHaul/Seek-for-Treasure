--!strict
--[[
	ServerStorage.Secrets.Codes: the code strings (GDD §9.7). Server-only, never
	replicated, so they can't be datamined. Keys are UPPER-CASE letters/digits,
	1-20 characters. expires = unix time (nil = never).

	SEEKATREASURE reward is the GDD default (2 Luck + 2 Cash Potions) until a
	final reward is chosen.
]]

export type Reward = {
	cash: number?,
	potions: { [string]: number }?, -- potion id -> doses (10 min each)
}

export type Code = {
	reward: Reward,
	expires: number?,
}

local Codes: { [string]: Code } = {
	SEEKATREASURE = { reward = { potions = { luck = 2, cash = 2 } } },
}

return table.freeze(Codes)
