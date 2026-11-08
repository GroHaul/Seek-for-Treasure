--!strict
--[[
	HudController: always-on HUD (GDD §13.2, §15).
	Top center: SHOPS / PLOT / MEADOW teleport buttons, cash (+ income/sec) and
	diamonds counters, vault pill ("Collect!" pulse).
	Top left: luck / search speed / mutation / rebirth / friend / Server Luck chips
	(at most two rows); potion timers are on the potion hotbar.
	Left (thumb zone): Shop (Robux), Bag, Rebirth. Right: Codes, Settings, Index.
	All numbers come from State (server data) and shared math; nothing is computed
	that the server doesn't also compute.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local SearchMath = require(Shared:WaitForChild("SearchMath"))
local Boosts = require(Shared:WaitForChild("Boosts"))

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Root = require(UI.Root)
local State = require(script.Parent.StateController)

local C = Theme.colors
local SEGMENT = "pets"

local Hud = {
	menu = {} :: { [string]: TextButton },
}

local cashText: TextLabel
local incomeText: TextLabel
local diamondText: TextLabel
local vaultPill: Frame
local vaultText: TextLabel
local vaultScale: UIScale
local chips: { [string]: TextLabel } = {}
local chipFrames: { [string]: Frame } = {}
local lastCash = 0

-- Stat chip: small glossy sky-blue pill, icon on the left, white outlined value.
local function chip(parent: Instance, name: string, order: number, iconName: string): TextLabel
	local frame = Kit.panel({
		Name = name,
		LayoutOrder = order,
		BackgroundColor3 = C.sky,
		Parent = parent,
	}, UDim.new(0.5, 0))
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 2.5
	end
	chipFrames[name] = frame
	local icon = Kit.icon(iconName, 24)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 4, 0.5, 0)
	icon.Parent = frame
	return Kit.label("", {
		Name = "Text",
		Size = UDim2.new(1, -36, 1, -6),
		Position = UDim2.fromOffset(30, 3),
		Parent = frame,
	})
end

--- Teleport the character to a CFrame the server published on workspace.World
--- (attributes replicate even when the target area is streamed out).
local function teleportTo(attribute: string)
	local world = workspace:FindFirstChild("World")
	local target = if world then world:GetAttribute(attribute) else nil
	local player = Players.LocalPlayer :: Player
	local character = player.Character
	if typeof(target) ~= "CFrame" or character == nil or character:FindFirstChild("HumanoidRootPart") == nil then
		return
	end
	Root.close()
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(target.Position, 2)
		end)
		if character.Parent then
			character:PivotTo(target + Vector3.new(0, 3, 0))
		end
	end)
end

local TELEPORTS: { { name: string, color: Color3, target: () -> string } } = {
	{
		name = "SHOPS",
		color = C.leaf,
		target = function()
			return "MarketSpawn"
		end,
	},
	{
		name = "PLOT",
		color = C.sky,
		target = function()
			return string.format("PlotSpawn_%02d", tonumber(State.derived.plotIndex) or 0)
		end,
	},
	{
		name = "MEADOW",
		color = C.sun,
		target = function()
			return "MeadowSpawn"
		end,
	},
}

local function buildTop(canvas: Frame)
	-- teleport buttons: the market, your plot, the search meadow
	local teleports = Kit.new("Frame", {
		Name = "Teleports",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(284, 48),
		Parent = canvas,
	}, { Kit.list(Enum.FillDirection.Horizontal, 4) })
	for i, entry in TELEPORTS do
		local button = Kit.button(entry.name, "secondary", function()
			teleportTo(entry.target())
		end, { Name = entry.name, Size = UDim2.fromOffset(92, 48), LayoutOrder = i })
		button.setColor(entry.color)
		button.instance.Parent = teleports
		Hud.menu[entry.name] = button.instance
	end

	-- floating counters: cash (+ income) and diamonds, big outlined numbers with
	-- no backing, readable on any background
	local currencies = Kit.new("Frame", {
		Name = "Currencies",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(292, 42),
		Parent = canvas,
	})
	local icon = Kit.icon("cash", 36)
	icon.Position = UDim2.fromOffset(0, 2)
	icon.Parent = currencies
	cashText = Kit.label("$0", {
		Name = "Cash",
		Size = UDim2.fromOffset(150, 27),
		Position = UDim2.fromOffset(40, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = currencies,
	}, 3)
	Kit.gradient(C.cashLight, C.cashDeep).Parent = cashText
	incomeText = Kit.label("+$0/s", {
		Name = "Income",
		Size = UDim2.fromOffset(150, 15),
		Position = UDim2.fromOffset(40, 27),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.cashLight,
		Parent = currencies,
	}, 1.5)
	local gem = Kit.icon("diamond", 34)
	gem.Position = UDim2.fromOffset(194, 3)
	gem.Parent = currencies
	diamondText = Kit.label("0", {
		Name = "Diamonds",
		Size = UDim2.fromOffset(62, 30),
		Position = UDim2.fromOffset(230, 5),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = currencies,
	}, 3)
	Kit.gradient(C.white, C.sky).Parent = diamondText
	vaultPill = Kit.panel({
		Name = "VaultPill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 102),
		Size = UDim2.fromOffset(250, 34),
		BackgroundColor3 = C.cash,
		Parent = canvas,
	}, UDim.new(0.5, 0))
	vaultScale = Kit.new("UIScale", { Parent = vaultPill })
	local vaultIcon = Kit.icon("vault", 30)
	vaultIcon.AnchorPoint = Vector2.new(0, 0.5)
	vaultIcon.Position = UDim2.new(0, 8, 0.5, 0)
	vaultIcon.Parent = vaultPill
	vaultText = Kit.label("", { Size = UDim2.new(1, -52, 1, -6), Position = UDim2.fromOffset(42, 3), Parent = vaultPill })

	-- one grid, 3 chips per row, wrapping downward: it stays left of the cash pill
	-- even on an 800-wide phone canvas, and hidden chips take no space
	local chipGrid = Kit.new("Frame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 6),
		Size = UDim2.fromOffset(264, 100),
		Parent = canvas,
	}, {
		Kit.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(84, 30),
			CellPadding = UDim2.fromOffset(6, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
			FillDirection = Enum.FillDirection.Horizontal,
		}),
	})
	chips.luck = chip(chipGrid, "Luck", 1, "luck")
	chips.speed = chip(chipGrid, "Speed", 2, "speed")
	chips.mutation = chip(chipGrid, "Mutation", 3, "mutation")
	chips.rebirths = chip(chipGrid, "Rebirths", 4, "rebirth")
	chips.friends = chip(chipGrid, "Friends", 5, "friends")
	chips.serverLuck = chip(chipGrid, "ServerLuck", 6, "serverLuck")
	-- active potion timers live on the potion hotbar (PotionBarController)
end

local function buildMenu(canvas: Frame)
	local left = Kit.new("Frame", {
		Name = "MenuLeft",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -16),
		Size = UDim2.fromOffset(74, 214),
		Parent = canvas,
	}, { Kit.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom) })
	local right = Kit.new("Frame", {
		Name = "MenuRight",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(74, 222),
		Parent = canvas,
	}, { Kit.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top) })
	-- each tile its own toy color, so the menu reads at a glance
	local entries: { { icon: string, caption: string, parent: Frame, color: Color3 } } = {
		{ icon = "shop", caption = "Shop", parent = left, color = C.coral },
		{ icon = "inventory", caption = "Bag", parent = left, color = C.sun },
		{ icon = "rebirth", caption = "Rebirth", parent = left, color = C.leaf },
		{ icon = "codes", caption = "Codes", parent = right, color = C.grape },
		{ icon = "settings", caption = "Settings", parent = right, color = C.sky },
		{ icon = "index", caption = "Index", parent = right, color = C.sky },
	}
	for i, entry in entries do
		local caption = entry.caption
		local button = Kit.menuButton(entry.icon, caption, function()
			Root.toggle(caption)
		end, entry.color)
		button.LayoutOrder = i
		button.Parent = entry.parent
		Hud.menu[caption] = button
	end
end

local function refreshCash()
	local profile = State.profile
	local cash = tonumber(profile.cash) or 0
	cashText.Text = Format.cash(cash)
	if cash > lastCash + 0.5 then
		local scale = cashText:FindFirstChild("Pop") :: UIScale?
		if scale == nil then
			scale = Kit.new("UIScale", { Name = "Pop", Parent = cashText })
		end
		local pop = scale :: UIScale
		pop.Scale = 1.15
		TweenService:Create(pop, Theme.motion.bouncy, { Scale = 1 }):Play()
	end
	lastCash = cash
end

local function refreshDiamonds()
	diamondText.Text = Format.number(tonumber(State.profile.diamonds) or 0)
end

local function refreshIncome()
	local income = tonumber(State.derived.income) or 0
	incomeText.Text = "+" .. Format.cash(income) .. "/s"
	local friends = tonumber(State.derived.friends) or 0
	chips.friends.Text = string.format("+%d%%", math.min(50, friends * 10))
	chipFrames.Friends.Visible = friends > 0
end

local function refreshVault()
	local vault = tonumber(State.profile.vault) or 0
	vaultText.Text = "Vault " .. Format.cash(vault) .. (if vault >= 1 then " · Collect!" else "")
	vaultPill.Visible = vault >= 1
end

local function refreshStats()
	local profile = State.profile
	if profile.tools == nil then
		return
	end
	local now = os.time()
	local me = Players.LocalPlayer
	chips.luck.Text = string.format("x%.2f", SearchMath.luck(profile, SEGMENT, now, me))
	chips.speed.Text = string.format("%.2fs", SearchMath.interval(profile, SEGMENT, now, me))
	chips.mutation.Text = string.format("x%.2f", SearchMath.mutation(profile, SEGMENT, now))
	local rebirths = tonumber(profile.rebirths) or 0
	chips.rebirths.Text = tostring(rebirths)
	chipFrames.Rebirths.Visible = rebirths > 0
	local serverLuck = Boosts.serverLuckRemaining(now)
	chipFrames.ServerLuck.Visible = serverLuck > 0
	if serverLuck > 0 then
		chips.serverLuck.Text = Format.duration(serverLuck)
	end
end

-- The teleport / currency / vault group is centered, but never further left
-- than the right edge of the chip grid (8 + 264) plus half its width, so the
-- two never overlap on narrow phones.
local CHIPS_RIGHT = 8 + 264 + 8
local GROUP_HALF_WIDTH = 146
local function placeCenterGroup(canvas: Frame)
	local width = canvas.Size.X.Offset
	local centerX = math.max(width / 2, CHIPS_RIGHT + GROUP_HALF_WIDTH)
	for _, name in { "Teleports", "Currencies", "VaultPill" } do
		local item = canvas:FindFirstChild(name)
		if item and item:IsA("GuiObject") then
			item.Position = UDim2.fromOffset(centerX, item.Position.Y.Offset)
		end
	end
end

function Hud.init()
	local canvas = Root.canvas :: Frame
	buildTop(canvas)
	buildMenu(canvas)
	placeCenterGroup(canvas)
	canvas:GetPropertyChangedSignal("Size"):Connect(function()
		placeCenterGroup(canvas)
	end)
end

function Hud.start()
	State.watch({ "cash" }, refreshCash)
	State.watch({ "diamonds" }, refreshDiamonds)
	State.watch({ "derived" }, refreshIncome)
	State.watch({ "vault" }, refreshVault)
	State.watch({ "tools", "potions", "rebirths", "indexRewards" }, refreshStats)
	task.spawn(function()
		local t = 0
		while true do
			task.wait(0.5)
			t += 0.5
			if State.loaded then
				refreshStats()
				-- gentle pulse on the vault pill so new players notice it
				if vaultPill.Visible then
					vaultScale.Scale = 1 + 0.04 * math.sin(t * 3)
				end
			end
		end
	end)
end

return Hud
