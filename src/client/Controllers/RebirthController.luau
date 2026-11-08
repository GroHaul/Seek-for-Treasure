--!strict
--[[
	RebirthController: the Rebirth confirm screen (GDD §7). Lists exactly what
	resets and what is kept, the permanent reward, and progress toward the cost.
	The button needs two taps; the server checks the cost again.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Format"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local EconomyMath = require(Shared:WaitForChild("EconomyMath"))

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Root = require(UI.Root)
local Remotes = require(script.Parent.Parent.Remotes)
local State = require(script.Parent.StateController)

local C = Theme.colors

local Rebirth = {}

local costText: TextLabel
local rewardText: TextLabel
local fill: Frame
local button: Kit.Button
local armed = false

local function refresh()
	if not State.loaded then
		return
	end
	local profile = State.profile
	local rebirths = tonumber(profile.rebirths) or 0
	local cost = EconomyMath.rebirthCost(rebirths, #Catalog.segments)
	local cash = tonumber(profile.cash) or 0
	costText.Text = string.format("Rebirth %d costs %s  (you have %s)", rebirths + 1, Format.cash(cost), Format.cash(cash))
	rewardText.Text = string.format(
		"Forever: cash x%.1f → x%.1f  ·  luck +%d%% → +%d%%",
		EconomyMath.rebirthCashMult(rebirths),
		EconomyMath.rebirthCashMult(rebirths + 1),
		rebirths * 10,
		(rebirths + 1) * 10
	)
	fill.Size = UDim2.fromScale(math.clamp(cash / cost, 0, 1), 1)
	local affordable = cash >= cost
	button.setEnabled(affordable)
	if not affordable then
		armed = false
	end
	button.setText(if armed then "Tap again to rebirth!" elseif affordable then "Rebirth" else "Need " .. Format.cash(cost - cash) .. " more")
end

function Rebirth.init()
	local modal = Root.modal("Rebirth", "Rebirth", Vector2.new(560, 400))
	local content = modal.content
	Kit.list(Enum.FillDirection.Vertical, 8).Parent = content
	costText = Kit.text("", { Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, Parent = content })
	local track = Kit.new("Frame", {
		BackgroundColor3 = C.white,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -20, 0, 18),
		LayoutOrder = 2,
		Parent = content,
	}, { Kit.corner(UDim.new(0.5, 0)), Kit.stroke(C.ink, 2) })
	fill = Kit.new("Frame", { BackgroundColor3 = C.grape, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track }, { Kit.corner(UDim.new(0.5, 0)) })
	rewardText = Kit.text("", { Size = UDim2.new(1, 0, 0, 24), TextColor3 = C.grape, LayoutOrder = 3, Parent = content })
	Kit.text("✅ You keep: every treasure, your Index, pity counters, potions, codes", {
		Size = UDim2.new(1, 0, 0, 22),
		FontFace = Theme.fonts.body,
		TextColor3 = C.ink,
		LayoutOrder = 4,
		Parent = content,
	})
	Kit.text("🔄 Resets: cash, vault, whistles (back to Tin), plot slots (back to 6)", {
		Size = UDim2.new(1, 0, 0, 22),
		FontFace = Theme.fonts.body,
		TextColor3 = C.coral,
		LayoutOrder = 5,
		Parent = content,
	})
	button = Kit.button("Rebirth", "danger", function()
		if not armed then
			armed = true
			refresh()
			task.delay(4, function()
				armed = false
				refresh()
			end)
			return
		end
		armed = false
		Remotes.fire(Net.Rebirth_Request)
		Root.close()
	end, { Size = UDim2.fromOffset(280, 58), LayoutOrder = 6 })
	button.instance.Parent = content
	modal.onOpen = refresh
	modal.onClose = function()
		armed = false
	end
end

function Rebirth.start()
	State.watch({ "cash", "rebirths" }, refresh)
end

return Rebirth
