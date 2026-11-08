--!strict
--[[
	PotionStallController: the Potions stall's panel (GDD §15.3).

	The stall restocks every 5 minutes. The stock comes from StockMath (the same
	in every server for the same window), so the client can show it without
	asking; the server re-checks stock, your per-restock limit and the price on
	every Shop_BuyPotion. Bought potions go into your bag (hotbar).
	A toast announces each restock.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Format"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))
local StockMath = require(Shared:WaitForChild("StockMath"))
local Potions = require(Shared:WaitForChild("Config"):WaitForChild("Potions")) :: any

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Root = require(UI.Root)
local Rows = require(UI.Rows)
local Remotes = require(script.Parent.Parent.Remotes)
local State = require(script.Parent.StateController)
local Toast = require(script.Parent.ToastController)

local C = Theme.colors

local PotionStall = {}

local list: ScrollingFrame
local header: TextLabel
local shownCycle = -1

local function serverNow(): number
	return math.floor(workspace:GetServerTimeNow())
end

local function render()
	if not Root.isOpen("Potions") or not State.loaded then
		return
	end
	Rows.clear(list)
	local profile = State.profile
	local now = serverNow()
	local cycle = StockMath.cycle(now)
	shownCycle = cycle
	local stock = StockMath.stock(cycle)
	local record = profile.potionStock
	local bought = if type(record) == "table" and record.cycle == cycle and type(record.bought) == "table" then record.bought else {}
	local baseIncome = tonumber(State.derived.baseIncome) or 0
	for order, potion in Potions.list do
		local inStock = stock[potion.id] or 0
		local left = math.max(0, inStock - (tonumber(bought[potion.id]) or 0))
		local held = if type(profile.potionBag) == "table" then tonumber(profile.potionBag[potion.id]) or 0 else 0
		local frame = Rows.row(list, order, "potion_" .. potion.id, potion.name, potion.description .. " · in bag: " .. held, 250)
		if inStock == 0 then
			Rows.button(frame, "Not in stock", "neutral", false, function() end)
		elseif left == 0 then
			Rows.button(frame, "Sold out", "danger", false, function() end)
		else
			local price = EconomyMath.potionPrice(potion, baseIncome)
			Rows.button(frame, "Buy " .. Format.cash(price), "primary", (tonumber(profile.cash) or 0) >= price, function()
				Remotes.fire(Net.Shop_BuyPotion, potion.id)
			end)
		end
		if inStock > 0 then
			Kit.label(string.format("%d / %d left", left, inStock), {
				Name = "Stock",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -178, 0.5, 0),
				Size = UDim2.fromOffset(78, 22),
				TextColor3 = if left > 0 then C.sun else C.muted,
				Parent = frame,
			})
		end
	end
end

local function tick()
	local now = serverNow()
	header.Text = "Restocks in " .. Format.duration(StockMath.secondsToRestock(now)) .. "  ·  random potions, limited stock"
	if StockMath.cycle(now) ~= shownCycle then
		local first = shownCycle == -1
		shownCycle = StockMath.cycle(now)
		render()
		local flags = State.profile.flags
		if not first and State.loaded and type(flags) == "table" and flags.tutorialDone then
			Toast.show("🧪 The Potions stall restocked!", C.grape, 3)
		end
	end
end

function PotionStall.init()
	local modal = Root.modal("Potions", "Potions Stall", Vector2.new(660, 430))
	header = Kit.label("", {
		Name = "Restock",
		Size = UDim2.new(1, -12, 0, 26),
		Position = UDim2.fromOffset(6, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.sun,
		Parent = modal.content,
	})
	list = Rows.list(modal.content, 32)
	modal.onOpen = render
end

function PotionStall.start()
	State.watch({ "cash", "potionBag", "potionStock", "derived" }, render)
	task.spawn(function()
		while true do
			tick()
			task.wait(1)
		end
	end)
end

return PotionStall
