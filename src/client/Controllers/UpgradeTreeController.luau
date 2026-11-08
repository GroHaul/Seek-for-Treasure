--!strict
--[[
	UpgradeTreeController: the Upgrades stall's hex tree (GDD §15.4).

	Left: hexagon tiles on an axial grid (pointy-top) around the root. Tile
	colors: gold root, grey "???" (locked or coming soon), white (not bought),
	sky (partly bought), leaf (maxed); the selected tile has a sun glow.
	Right: the selected node's details, its levels with prices, and a buy
	button. Diamond nodes send Upgrade_Buy; the Plot Slots node is cash and
	sends Shop_BuySlot. The server re-checks everything.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Format"))
local UpgradeMath = require(Shared:WaitForChild("UpgradeMath"))
local Boosts = require(Shared:WaitForChild("Boosts"))
local UpgradeTree = require(Shared:WaitForChild("Config"):WaitForChild("UpgradeTree")) :: any

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Root = require(UI.Root)
local Assets = require(UI.Assets)
local Remotes = require(script.Parent.Parent.Remotes)
local State = require(script.Parent.StateController)

local C = Theme.colors
local TILE = 86 -- square image size; the hexagon fills ~86% of the width
local STEP_X = 78
local STEP_Y = 66
local DETAIL_WIDTH = 228
local ROMAN = { "I", "II", "III", "IV", "V", "VI" }
local LOCKED = Color3.fromHex("#5A6078")
local PANEL_DARK = Color3.fromHex("#2B3150")

local UpgradeTreeUI = {}

type Tile = { button: ImageButton, glow: ImageLabel }

local treeArea: Frame
local detail: Frame
local diamondsText: TextLabel
local tiles: { [string]: Tile } = {}
local selected = "root"

-- detail panel parts
local dIcon: Frame
local dName: TextLabel
local dTag: TextLabel
local dDesc: TextLabel
local dLevels: Frame
local dStatus: TextLabel
local dButton: any

local function hasSlotPass(): boolean
	return Boosts.hasPass(Players.LocalPlayer, "plotSlots")
end

local function nodeState(profile: any, node: any): string
	if node.id == "root" then
		return "root"
	end
	if not UpgradeMath.isRevealed(profile, node) then
		return "hidden"
	end
	local level = UpgradeMath.level(profile, node.id)
	if level >= UpgradeMath.maxLevel(node, hasSlotPass()) then
		return "maxed"
	end
	return if level > 0 then "partial" else "open"
end

local STATE_COLOR: { [string]: Color3 } = {
	root = C.sun,
	hidden = LOCKED,
	open = C.white,
	partial = C.sky,
	maxed = C.leaf,
}

local function priceText(node: any, cost: number): string
	return if node.currency == "cash" then Format.cash(cost) else "💎 " .. Format.number(cost)
end

local function clearChildren(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function renderDetail(profile: any)
	local node = UpgradeMath.nodeById[selected]
	if node == nil then
		return
	end
	local state = nodeState(profile, node)
	local hidden = state == "hidden"
	clearChildren(dIcon)
	local icon = Kit.icon(if hidden then "lock" else node.icon, 60)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Parent = dIcon
	dName.Text = if hidden then "???" else node.name
	dTag.Text = if node.comingSoon
		then "COMING SOON"
		elseif node.currency == "cash" then "CASH UPGRADE"
		elseif node.currency == "diamonds" then "DIAMOND UPGRADE"
		else "START"
	dDesc.Text = if hidden then "Unlock the upgrade next to it first." else UpgradeMath.describe(node)

	clearChildren(dLevels)
	local level = UpgradeMath.level(profile, node.id)
	local maxLevel = UpgradeMath.maxLevel(node, hasSlotPass())
	if not hidden and node.currency == "diamonds" then
		for i = 1, maxLevel do
			local owned = i <= level
			local row = Kit.new("Frame", {
				Name = "Level" .. i,
				BackgroundColor3 = if owned then C.leaf elseif i == level + 1 then C.sky else PANEL_DARK,
				BackgroundTransparency = if owned or i == level + 1 then 0.15 else 0.4,
				Size = UDim2.new(1, 0, 0, 24),
				LayoutOrder = i,
				Parent = dLevels,
			}, { Kit.corner(UDim.new(0, 8)) })
			Kit.label(string.format("%s  Level %s", if owned then "✓" else "•", ROMAN[i] or tostring(i)), {
				Size = UDim2.new(0.55, -6, 1, -4),
				Position = UDim2.fromOffset(6, 2),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = row,
			}, 1.5)
			Kit.label(priceText(node, node.costs[i]), {
				Size = UDim2.new(0.45, -6, 1, -4),
				Position = UDim2.new(0.55, 0, 0, 2),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = C.skyLight,
				Parent = row,
			}, 1.5)
		end
	elseif not hidden and node.currency == "cash" then
		Kit.label(string.format("Slots %d / %d", level + 6, maxLevel + 6), {
			Size = UDim2.new(1, 0, 0, 26),
			Parent = dLevels,
		})
	end

	local cost = if hidden then nil else UpgradeMath.nextCost(profile, node, hasSlotPass())
	local have = if node.currency == "cash" then tonumber(profile.cash) or 0 else tonumber(profile.diamonds) or 0
	if node.comingSoon then
		dStatus.Text = "More upgrades in a future update!"
		dButton.setText("Locked")
		dButton.setColor(C.coral)
		dButton.setEnabled(false)
	elseif hidden then
		local requires = node.requires and UpgradeMath.nodeById[node.requires]
		dStatus.Text = if requires then "Unlock " .. requires.name .. " first!" else ""
		dButton.setText("Locked")
		dButton.setColor(C.coral)
		dButton.setEnabled(false)
	elseif node.currency == "none" then
		dStatus.Text = "Find treasures to earn 💎 diamonds."
		dButton.setText("Explore!")
		dButton.setColor(C.sun)
		dButton.setEnabled(false)
	elseif cost == nil then
		dStatus.Text = ""
		dButton.setText("MAXED")
		dButton.setColor(C.leaf)
		dButton.setEnabled(false)
	else
		dStatus.Text = if have >= cost
			then ""
			elseif node.currency == "cash" then "Need " .. Format.cash(cost - have) .. " more"
			else "Need 💎 " .. Format.number(cost - have) .. " more"
		dButton.setText("Buy " .. priceText(node, cost))
		dButton.setColor(C.cash)
		dButton.setEnabled(have >= cost)
	end
end

local function render()
	if not Root.isOpen("Upgrades") or not State.loaded then
		return
	end
	local profile = State.profile
	diamondsText.Text = Format.number(tonumber(profile.diamonds) or 0)
	for id, tile in tiles do
		local node = UpgradeMath.nodeById[id]
		local state = nodeState(profile, node)
		tile.button.ImageColor3 = STATE_COLOR[state]
		tile.glow.Visible = id == selected
		local hidden = state == "hidden"
		local content = tile.button:FindFirstChild("Content") :: Frame
		content.Visible = not hidden
		local unknown = tile.button:FindFirstChild("Unknown") :: TextLabel
		unknown.Visible = hidden
		local footer = content:FindFirstChild("Footer") :: TextLabel
		local level = UpgradeMath.level(profile, id)
		local maxLevel = UpgradeMath.maxLevel(node, hasSlotPass())
		local cost = UpgradeMath.nextCost(profile, node, hasSlotPass())
		footer.Text = if node.currency == "none" then "" elseif cost == nil then "MAX" else priceText(node, cost)
		local progress = content:FindFirstChild("Progress") :: TextLabel
		progress.Text = if node.currency == "none" then "" else string.format("%d/%d", level, maxLevel)
	end
	renderDetail(profile)
end

local function buildTile(node: any, center: Vector2)
	local button = Kit.new("ImageButton", {
		Name = node.id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(TILE, TILE),
		BackgroundTransparency = 1,
		Image = Assets.hexFill.image or "",
		ImageColor3 = C.white,
		AutoButtonColor = false,
		ZIndex = 2,
		Parent = treeArea,
	}) :: ImageButton
	local glow = Kit.new("ImageLabel", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(TILE + 16, TILE + 16),
		BackgroundTransparency = 1,
		Image = Assets.hexFill.image or "",
		ImageColor3 = C.sun,
		ImageTransparency = 0.15,
		Visible = false,
		ZIndex = 1,
		Parent = treeArea,
	}) :: ImageLabel
	Kit.new("ImageLabel", {
		Name = "Outline",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = Assets.hexOutline.image or "",
		ImageColor3 = C.ink,
		Parent = button,
	})
	local content = Kit.new("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = button }) :: Frame
	local icon = Kit.icon(node.icon, 32)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0.5, -10)
	icon.Parent = content
	Kit.label(node.name, {
		Name = "NodeName",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 8),
		Size = UDim2.fromOffset(TILE - 18, 13),
		Parent = content,
	}, 1.5)
	Kit.label("", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 21),
		Size = UDim2.fromOffset(TILE - 28, 13),
		TextColor3 = C.skyLight,
		Parent = content,
	}, 1.5)
	Kit.label("", {
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(34, 13),
		TextColor3 = C.sun,
		Parent = content,
	}, 1.5)
	Kit.label("???", {
		Name = "Unknown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(TILE - 24, 30),
		TextColor3 = C.muted,
		Visible = false,
		Parent = button,
	}, 2.5)
	button.Activated:Connect(function()
		selected = node.id
		render()
	end)
	tiles[node.id] = { button = button, glow = glow }
end

local function buildDetail(parent: Frame)
	detail = Kit.panel({
		Name = "Detail",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, DETAIL_WIDTH, 1, 0),
		BackgroundColor3 = PANEL_DARK,
		Parent = parent,
	}, UDim.new(0, 16))
	dIcon =
		Kit.new("Frame", { Name = "Icon", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 64), Parent = detail }) :: Frame
	dName = Kit.label("", { Name = "Name", Position = UDim2.fromOffset(8, 72), Size = UDim2.new(1, -16, 0, 28), TextColor3 = C.sun, Parent = detail }, 2.5)
	dTag = Kit.label("", { Name = "Tag", Position = UDim2.fromOffset(8, 100), Size = UDim2.new(1, -16, 0, 16), TextColor3 = C.cashLight, Parent = detail }, 1.5)
	dDesc = Kit.text("", {
		Name = "Desc",
		Position = UDim2.fromOffset(10, 118),
		Size = UDim2.new(1, -20, 0, 34),
		FontFace = Theme.fonts.body,
		TextColor3 = C.white,
		TextWrapped = true,
		Parent = detail,
	})
	dLevels = Kit.new("Frame", {
		Name = "Levels",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 156),
		Size = UDim2.new(1, -20, 0, 112),
		Parent = detail,
	}, { Kit.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top) }) :: Frame
	dStatus = Kit.label("", {
		Name = "Status",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -62),
		Size = UDim2.new(1, -16, 0, 16),
		TextColor3 = C.coral,
		Parent = detail,
	}, 1.5)
	dButton = Kit.button("", "primary", function()
		local node = UpgradeMath.nodeById[selected]
		if node == nil then
			return
		end
		if node.currency == "cash" then
			Remotes.fire(Net.Shop_BuySlot)
		elseif node.currency == "diamonds" then
			Remotes.fire(Net.Upgrade_Buy, node.id)
		end
	end, {
		Name = "Buy",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -20, 0, 50),
	})
	dButton.instance.Parent = detail
end

function UpgradeTreeUI.init()
	local modal = Root.modal("Upgrades", "Upgrades Stall", Vector2.new(720, 440))
	local content = modal.content
	treeArea = Kit.new("Frame", {
		Name = "Tree",
		BackgroundTransparency = 1,
		ClipsDescendants = false,
		Size = UDim2.new(1, -(DETAIL_WIDTH + 8), 1, 0),
		Parent = content,
	}) :: Frame
	buildDetail(content)

	-- your diamonds, top-left of the tree
	local gem = Kit.icon("diamond", 30)
	gem.Position = UDim2.fromOffset(0, 0)
	gem.Parent = treeArea
	diamondsText = Kit.label("0", {
		Name = "Diamonds",
		Position = UDim2.fromOffset(34, 2),
		Size = UDim2.fromOffset(110, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = treeArea,
	}, 2.5)
	Kit.gradient(C.white, C.sky).Parent = diamondsText

	-- center the grid in the tree area
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, node in UpgradeTree.nodes do
		local x = STEP_X * (node.q + node.r / 2)
		local y = STEP_Y * node.r
		minX, maxX = math.min(minX, x), math.max(maxX, x)
		minY, maxY = math.min(minY, y), math.max(maxY, y)
	end
	local function place()
		local size = treeArea.AbsoluteSize / (Root.scale > 0 and Root.scale or 1)
		local width = if size.X > 0 then size.X else 452
		local height = if size.Y > 0 then size.Y else 364
		local offset = Vector2.new(width / 2 - (minX + maxX) / 2, height / 2 - (minY + maxY) / 2 + 6)
		for _, node in UpgradeTree.nodes do
			local center = offset + Vector2.new(STEP_X * (node.q + node.r / 2), STEP_Y * node.r)
			local tile = tiles[node.id]
			if tile then
				tile.button.Position = UDim2.fromOffset(center.X, center.Y)
				tile.glow.Position = UDim2.fromOffset(center.X, center.Y)
			else
				buildTile(node, center)
			end
		end
	end
	place()
	treeArea:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	modal.onOpen = render
end

function UpgradeTreeUI.start()
	State.watch({ "diamonds", "upgrades", "plot", "cash" }, render)
end

return UpgradeTreeUI
