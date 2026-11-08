--!strict
--[[
	Assets: UI image ids for the ForgeGUI kit (GDD §13.2). Empty until the
	ForgeGUI -> Roblox publishing connection can upload images (it currently
	reports asset_permission_missing). Every UI element falls back to the emoji
	glyph below, so the game is fully usable with no images.
]]

export type Icon = { image: string?, glyph: string }

local Assets: { [string]: Icon } = {
	shop = { glyph = "🛒" },
	inventory = { glyph = "🎒" },
	rebirth = { glyph = "🌟" },
	codes = { glyph = "🎁" },
	settings = { glyph = "⚙️" },
	index = { glyph = "📖" },
	cash = { glyph = "💵" },
	vault = { glyph = "🏦" },
	luck = { glyph = "🍀" },
	speed = { glyph = "⏱️" },
	mutation = { glyph = "✨" },
	friends = { glyph = "👥" },
	potion_luck = { glyph = "🍀" },
	potion_speed = { glyph = "⚡" },
	potion_mutation = { glyph = "🧪" },
	potion_cash = { glyph = "💰" },
	tool = { glyph = "🎵" },
	slot = { glyph = "🧱" },
	lock = { glyph = "🔒" },
	close = { glyph = "✕" },
}

return table.freeze(Assets)
