--!strict
--[[
	SearchController: the search progress bar (bottom center), the pity meter
	("Legendary+ in 312"), and a find toast for every reveal. The server decides
	when a search completes; the bar only animates between Search_State and
	Search_Reveal events. Finds go to RevealController (toast or cinematic).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Format"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Pity = require(Shared:WaitForChild("Config"):WaitForChild("Pity")) :: any

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Root = require(UI.Root)
local Remotes = require(script.Parent.Parent.Remotes)
local State = require(script.Parent.StateController)

local C = Theme.colors

local Search = {
	active = false,
	-- (payload) for every find; the reveal cinematic (step 7) hooks in here
	revealed = Signal.new() :: Signal.Signal<any>,
	stateChanged = Signal.new() :: Signal.Signal<boolean>,
}

local bar: Frame
local fill: Frame
local title: TextLabel
local pityText: TextLabel
local interval = 3
local startedAt = 0

local PITY_NAMES = { epic = "Epic+", legendary = "Legendary+", mythic = "Mythic+" }

local function refreshPity()
	local pity = State.profile.pity
	if type(pity) ~= "table" then
		return
	end
	local bestId, bestLeft = "epic", math.huge
	for _, floor in Pity do
		local left = floor.guaranteeAt - (tonumber(pity[floor.id]) or 0)
		if left < bestLeft then
			bestId, bestLeft = floor.id, left
		end
	end
	pityText.Text = string.format("%s guaranteed in %d", PITY_NAMES[bestId] or bestId, bestLeft)
end

local function mutationNames(mutation: { string }): string
	local names = {}
	for _, id in mutation do
		local m = Catalog.mutationById[id]
		if m then
			table.insert(names, string.upper(m.name))
		end
	end
	return table.concat(names, " ")
end

function Search.findText(payload: any): (string, Color3)
	local treasure = Catalog.treasureById[payload.treasureId]
	local rarity = Catalog.rarities[payload.rarity]
	if treasure == nil or rarity == nil then
		return "New find!", C.ink
	end
	local mut = mutationNames(payload.mutation or {})
	local readable = Kit.readable(Color3.fromHex(rarity.color)):ToHex()
	local text = string.format(
		'+ %s%s <font color="#%s">[%s]</font>%s',
		if mut ~= "" then mut .. " " else "",
		treasure.name,
		readable,
		rarity.name,
		if rarity.oneIn > 0 then " " .. Format.oneIn(rarity.oneIn) else ""
	)
	if payload.soldFor then
		text ..= " · bag full, sold " .. Format.cash(payload.soldFor)
	end
	return text, Kit.readable(Color3.fromHex(rarity.color))
end

function Search.init()
	bar = Kit.panel({
		Name = "SearchBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(330, 64),
		BackgroundColor3 = C.sky,
		Parent = Root.canvas,
	}, UDim.new(0, 16))
	title = Kit.label("Walk into Pawprint Meadow to search", {
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.fromOffset(10, 3),
		TextColor3 = C.sun,
		Parent = bar,
	})
	-- dark track with a glossy green fill, like a game progress bar
	local track = Kit.new("Frame", {
		Name = "Track",
		BackgroundColor3 = C.ink,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 27),
		Size = UDim2.new(1, -24, 0, 16),
		Parent = bar,
	}, { Kit.corner(UDim.new(0.5, 0)), Kit.stroke(C.ink, 2) })
	fill = Kit.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = C.white,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	}, { Kit.corner(UDim.new(0.5, 0)), Kit.gradient(C.cashLight, C.cashDeep) })
	Kit.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = C.white,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(6, 3),
		Size = UDim2.new(1, -12, 0, 4),
		Parent = fill,
	}, { Kit.corner(UDim.new(0.5, 0)) })
	pityText = Kit.label("", {
		Size = UDim2.new(1, -20, 0, 15),
		Position = UDim2.fromOffset(10, 45),
		TextColor3 = Color3.fromHex("#D9C2FF"),
		Parent = bar,
	}, 1.5)
end

function Search.start()
	Remotes.on(Net.Search_State, function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		Search.active = payload.active == true
		interval = tonumber(payload.interval) or interval
		startedAt = tonumber(payload.startedAt) or workspace:GetServerTimeNow()
		title.Text = if Search.active then "🎵 Searching..." else "Walk into Pawprint Meadow to search"
		Search.stateChanged:Fire(Search.active)
	end)
	Remotes.on(Net.Search_Reveal, function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		startedAt = workspace:GetServerTimeNow()
		-- RevealController decides: toast for Common/Uncommon, cinematic for Rare+
		Search.revealed:Fire(payload)
	end)
	State.watch({ "pity" }, refreshPity)
	RunService.RenderStepped:Connect(function()
		if Search.active and interval > 0 then
			local progress = math.clamp((workspace:GetServerTimeNow() - startedAt) / interval, 0, 1)
			fill.Size = UDim2.fromScale(progress, 1)
		else
			fill.Size = UDim2.fromScale(0, 1)
		end
	end)
end

return Search
