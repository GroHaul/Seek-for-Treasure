--!strict
--[[
	HudController: always-on HUD (GDD §13.2).
	Top center: cash pill, income/sec, vault pill ("Collect!" pulse).
	Top left: luck / search speed / mutation / friend chips, potion timers.
	Left (thumb zone): Shop, Bag, Rebirth. Right: Codes, Settings.
	All numbers come from State (server data) and shared math; nothing is computed
	that the server doesn't also compute.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local SearchMath = require(Shared:WaitForChild("SearchMath"))
local Catalog = require(Shared:WaitForChild("Catalog"))

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
local vaultPill: Frame
local vaultText: TextLabel
local vaultScale: UIScale
local chips: { [string]: TextLabel } = {}
local chipFrames: { [string]: Frame } = {}
local potionChips: { [string]: TextLabel } = {}
local lastCash = 0

local function chip(parent: Instance, name: string, order: number): TextLabel
	local frame = Kit.panel({
		Name = name,
		LayoutOrder = order,
		Parent = parent,
	}, UDim.new(0.5, 0))
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 2
	end
	chipFrames[name] = frame
	return Kit.text("", {
		Name = "Text",
		Size = UDim2.new(1, -12, 1, -6),
		Position = UDim2.fromOffset(6, 3),
		FontFace = Theme.fonts.number,
		Parent = frame,
	})
end

local function buildTop(canvas: Frame)
	local cashPill = Kit.panel({
		Name = "CashPill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(250, 50),
		Parent = canvas,
	}, UDim.new(0.5, 0))
	Kit.shadow(cashPill, UDim.new(0.5, 0))
	local icon = Kit.icon("cash", 34)
	icon.Position = UDim2.fromOffset(12, 8)
	icon.Parent = cashPill
	cashText = Kit.text("$0", {
		Name = "Cash",
		Size = UDim2.new(1, -64, 1, -10),
		Position = UDim2.fromOffset(52, 5),
		FontFace = Theme.fonts.number,
		TextColor3 = C.ink,
		Parent = cashPill,
	})
	incomeText = Kit.text("+$0/s", {
		Name = "Income",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.fromOffset(220, 20),
		FontFace = Theme.fonts.number,
		TextColor3 = C.cash,
		TextStrokeColor3 = C.ink,
		TextStrokeTransparency = 0,
		Parent = canvas,
	})
	vaultPill = Kit.panel({
		Name = "VaultPill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		Size = UDim2.fromOffset(250, 32),
		BackgroundColor3 = C.cash,
		Parent = canvas,
	}, UDim.new(0.5, 0))
	vaultScale = Kit.new("UIScale", { Parent = vaultPill })
	vaultText = Kit.text("", { Size = UDim2.new(1, -16, 1, -6), Position = UDim2.fromOffset(8, 3), Parent = vaultPill })

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
	chips.luck = chip(chipGrid, "Luck", 1)
	chips.speed = chip(chipGrid, "Speed", 2)
	chips.mutation = chip(chipGrid, "Mutation", 3)
	chips.rebirths = chip(chipGrid, "Rebirths", 4)
	chips.friends = chip(chipGrid, "Friends", 5)
	for i, potion in Catalog.potionById do
		local label = chip(chipGrid, "Potion_" .. i, 10 + potion.durationSeconds)
		potionChips[potion.id] = label
	end
end

local function buildMenu(canvas: Frame)
	local left = Kit.new("Frame", {
		Name = "MenuLeft",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -14),
		Size = UDim2.fromOffset(70, 214),
		Parent = canvas,
	}, { Kit.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom) })
	local right = Kit.new("Frame", {
		Name = "MenuRight",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(70, 236),
		Parent = canvas,
	}, { Kit.list(Enum.FillDirection.Vertical, 12) })
	local entries: { { icon: string, caption: string, parent: Frame } } = {
		{ icon = "shop", caption = "Shop", parent = left },
		{ icon = "inventory", caption = "Bag", parent = left },
		{ icon = "rebirth", caption = "Rebirth", parent = left },
		{ icon = "codes", caption = "Codes", parent = right },
		{ icon = "settings", caption = "Settings", parent = right },
	}
	for i, entry in entries do
		local caption = entry.caption
		local button = Kit.menuButton(entry.icon, caption, function()
			Root.toggle(caption)
		end)
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

local function refreshIncome()
	local income = tonumber(State.derived.income) or 0
	incomeText.Text = "+" .. Format.cash(income) .. "/s"
	local friends = tonumber(State.derived.friends) or 0
	chips.friends.Text = string.format("👥 +%d%%", math.min(50, friends * 10))
	chipFrames.Friends.Visible = friends > 0
end

local function refreshVault()
	local vault = tonumber(State.profile.vault) or 0
	vaultText.Text = "🏦 Vault " .. Format.cash(vault) .. (if vault >= 1 then " · Collect!" else "")
	vaultPill.Visible = vault >= 1
end

local function refreshStats()
	local profile = State.profile
	if profile.tools == nil then
		return
	end
	local now = os.time()
	chips.luck.Text = string.format("🍀 x%.2f", SearchMath.luck(profile, SEGMENT, now))
	chips.speed.Text = string.format("⏱️ %.2fs", SearchMath.interval(profile, SEGMENT, now))
	chips.mutation.Text = string.format("✨ x%.2f", SearchMath.mutation(profile, SEGMENT, now))
	local rebirths = tonumber(profile.rebirths) or 0
	chips.rebirths.Text = "🌟 " .. rebirths
	chipFrames.Rebirths.Visible = rebirths > 0
	for id, label in potionChips do
		local expiry = if profile.potions then tonumber(profile.potions[id]) or 0 else 0
		local remaining = expiry - now
		local frame = label.Parent :: Frame
		frame.Visible = remaining > 0
		if remaining > 0 then
			local glyph = if id == "luck" then "🍀" elseif id == "speed" then "⚡" elseif id == "mutation" then "🧪" else "💰"
			label.Text = glyph .. " " .. Format.duration(remaining)
		end
	end
end

-- The cash / income / vault group is centered, but never further left than
-- the right edge of the chip grid (8 + 264) plus half its width, so the two
-- never overlap on narrow phones.
local CHIPS_RIGHT = 8 + 264 + 8
local function placeCenterGroup(canvas: Frame)
	local width = canvas.Size.X.Offset
	local centerX = math.max(width / 2, CHIPS_RIGHT + 125)
	for _, name in { "CashPill", "Income", "VaultPill" } do
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
