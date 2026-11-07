--!strict
--[[
	IndexController: the Collection Index panel (GDD §9.3). One page per segment
	(MVP: Pets). Found treasures show their color, times found and the mutations
	seen; unfound ones are silhouettes with their "1 in N" odds. A progress bar
	marks the 50% / 75% / 100% milestones and their permanent luck bonus.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Format = require(Shared:WaitForChild("Format"))
local IndexConfig = require(Shared:WaitForChild("Config"):WaitForChild("Index")) :: any

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Root = require(UI.Root)
local Remotes = require(script.Parent.Parent.Remotes)
local State = require(script.Parent.StateController)
local Toast = require(script.Parent.ToastController)

local C = Theme.colors
local SEGMENT = "pets"

local IndexPanel = {}

local grid: ScrollingFrame
local summary: TextLabel
local fill: Frame
local track: Frame

local function mutationsSeen(mask: number): string
	local names = {}
	for _, family in { "finish", "aura" } do
		for _, m in Catalog.mutationById do
			if m.family == family and bit32.band(mask, m.bit) ~= 0 then
				table.insert(names, m.name)
			end
		end
	end
	return table.concat(names, " · ")
end

local function render()
	if not Root.isOpen("Index") or not State.loaded then
		return
	end
	local profile = State.profile
	local segment = Catalog.segmentById[SEGMENT]
	local treasures = table.clone(segment.treasures)
	table.sort(treasures, function(a, b)
		if a.rarity ~= b.rarity then
			return a.rarity < b.rarity
		end
		return a.name < b.name
	end)
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local found = 0
	for i, treasure in treasures do
		local entry = profile.index and profile.index[treasure.id]
		local isFound = entry ~= nil and (tonumber(entry.n) or 0) > 0
		if isFound then
			found += 1
		end
		local rarity = Catalog.rarities[treasure.rarity]
		local color = Color3.fromHex(rarity.color)
		local card = Kit.new("Frame", {
			Name = treasure.id,
			BackgroundColor3 = if isFound then C.white else Color3.fromHex("#E6E1D6"),
			LayoutOrder = i,
			Parent = grid,
		}, { Kit.corner(UDim.new(0, 14)) })
		Kit.rarityStroke(card, if isFound then color else C.muted, treasure.rarity)
		Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 8),
			Size = UDim2.fromOffset(44, 44),
			BackgroundColor3 = if isFound then color else C.ink,
			Parent = card,
		}, { Kit.corner(UDim.new(0.5, 0)), Kit.stroke(C.ink, 2) })
		Kit.text(if isFound then treasure.name else "???", { Size = UDim2.new(1, -8, 0, 18), Position = UDim2.fromOffset(4, 56), Parent = card })
		Kit.text(rarity.name, { Size = UDim2.new(1, -8, 0, 14), Position = UDim2.fromOffset(4, 74), TextColor3 = Kit.readable(color), Parent = card })
		Kit.text(if isFound then "Found ×" .. Format.number(entry.n) else Format.oneIn(math.max(rarity.oneIn, 1)), {
			Size = UDim2.new(1, -8, 0, 14),
			Position = UDim2.fromOffset(4, 90),
			FontFace = Theme.fonts.number,
			TextColor3 = if isFound then C.ink else C.muted,
			Parent = card,
		})
		if isFound and (tonumber(entry.m) or 0) > 0 then
			Kit.text(mutationsSeen(entry.m), {
				Size = UDim2.new(1, -8, 0, 12),
				Position = UDim2.fromOffset(4, 106),
				FontFace = Theme.fonts.body,
				TextColor3 = C.grape,
				Parent = card,
			})
		end
	end
	local total = #treasures
	local claimed = profile.indexRewards and tonumber(profile.indexRewards[SEGMENT]) or 0
	local bonus = 0
	for i = 1, claimed do
		bonus += IndexConfig.milestones[i].luckBonus
	end
	summary.Text = string.format("Pawprint Meadow: %d / %d found · Index luck bonus +%d%%", found, total, math.floor(bonus * 100 + 0.5))
	fill.Size = UDim2.fromScale(found / math.max(total, 1), 1)
	for i in IndexConfig.milestones do
		local tick = track:FindFirstChild("Milestone" .. i) :: Frame?
		if tick then
			tick.BackgroundColor3 = if i <= claimed then C.cash else C.white
		end
	end
end

function IndexPanel.init()
	local modal = Root.modal("Index", "Collection Index", Vector2.new(700, 440))
	local content = modal.content
	summary = Kit.text("", { Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, Parent = content })
	track = Kit.new("Frame", {
		Name = "Track",
		BackgroundColor3 = C.white,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, -10, 0, 16),
		Parent = content,
	}, { Kit.corner(UDim.new(0.5, 0)), Kit.stroke(C.ink, 2) }) :: Frame
	fill = Kit.new("Frame", { BackgroundColor3 = C.leaf, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track }, { Kit.corner(UDim.new(0.5, 0)) }) :: Frame
	for i, milestone in IndexConfig.milestones do
		Kit.new("Frame", {
			Name = "Milestone" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(milestone.fraction, 0.5),
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = C.white,
			ZIndex = 3,
			Parent = track,
		}, { Kit.corner(UDim.new(0.5, 0)), Kit.stroke(C.ink, 2) })
		Kit.text(string.format("+%d%%", math.floor(milestone.luckBonus * 100 + 0.5)), {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(milestone.fraction, 0, 1, 2),
			Size = UDim2.fromOffset(40, 14),
			FontFace = Theme.fonts.number,
			TextColor3 = C.cash,
			Parent = track,
		})
	end
	grid = Kit.new("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 1, -66),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.ink,
		Parent = content,
	}, {
		Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(106, 124), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		Kit.padding(6),
	}) :: ScrollingFrame
	modal.onOpen = render
end

function IndexPanel.start()
	State.watch({ "index", "indexRewards" }, render)
	Remotes.on(Net.Notify, function(payload: any)
		if type(payload) == "table" and payload.kind == "index_milestone" then
			Toast.show(
				string.format(
					"📖 Index %d/%d! Luck +%d%% forever",
					tonumber(payload.found) or 0,
					tonumber(payload.total) or 0,
					math.floor((tonumber(payload.luckBonus) or 0) * 100 + 0.5)
				),
				C.leaf,
				4
			)
		end
	end)
end

return IndexPanel
