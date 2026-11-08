--!strict
--[[
	Assets: UI icon image ids (GDD §13.2).

	Icons are Microsoft Fluent Emoji 3D (MIT License, Copyright (c) Microsoft
	Corporation): https://github.com/microsoft/fluentui-emoji. The source PNGs
	and the license live in assets/icons/fluent-emoji/ (see its README for the
	file -> asset id map). They were uploaded to Roblox on 2026-11-08 through
	Studio. If an image ever fails to load, every element still has the emoji
	glyph below as a fallback (used when `image` is nil).

	The ForgeGUI Bag test icon (rbxassetid://116299538304293) is replaced by the
	Fluent backpack so all icons share one style.
]]

export type Icon = { image: string?, glyph: string }

local Assets: { [string]: Icon } = {
	shop = { glyph = "🛒", image = "rbxassetid://93741744799151" },
	inventory = { glyph = "🎒", image = "rbxassetid://124707017308512" },
	rebirth = { glyph = "🌟", image = "rbxassetid://125457799178791" },
	codes = { glyph = "🎁", image = "rbxassetid://109519026022389" },
	settings = { glyph = "⚙️", image = "rbxassetid://92857477225368" },
	index = { glyph = "📖", image = "rbxassetid://116244545982533" },
	cash = { glyph = "💵", image = "rbxassetid://124615432824907" },
	vault = { glyph = "🏦", image = "rbxassetid://100371264091175" },
	luck = { glyph = "🍀", image = "rbxassetid://76646880457752" },
	speed = { glyph = "⏱️", image = "rbxassetid://85872337584049" },
	mutation = { glyph = "✨", image = "rbxassetid://83317238554915" },
	friends = { glyph = "👥", image = "rbxassetid://130161396633617" },
	potion_luck = { glyph = "🍀", image = "rbxassetid://76646880457752" },
	potion_speed = { glyph = "⚡", image = "rbxassetid://82464453411290" },
	potion_mutation = { glyph = "🧪", image = "rbxassetid://119978601723067" },
	potion_cash = { glyph = "💰", image = "rbxassetid://103982091792482" },
	tool = { glyph = "🎵", image = "rbxassetid://95145629235572" },
	slot = { glyph = "🧱", image = "rbxassetid://121177499435167" },
	lock = { glyph = "🔒", image = "rbxassetid://95315631693920" },
	close = { glyph = "✕" },
}

return table.freeze(Assets)
