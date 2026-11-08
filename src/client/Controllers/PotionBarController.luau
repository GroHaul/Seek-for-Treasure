--!strict
--[[
	PotionBarController: the potion hotbar (GDD §15.3). Bottom center, above the
	search card: one slot per potion you hold or have active, showing its icon,
	how many are in your bag ("x3") and the time left while active. Tap a slot to
	drink one (Potion_Use); the server refuses a drink past 60 min remaining.
	Hidden when there's nothing to show and while the tutorial banner is up.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Format"))
local Potions = require(Shared:WaitForChild("Config"):WaitForChild("Potions")) :: any

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Root = require(UI.Root)
local Remotes = require(script.Parent.Parent.Remotes)
local State = require(script.Parent.StateController)

local C = Theme.colors
local SLOT = 52

local PotionBar = {}

type Slot = { frame: TextButton, count: TextLabel, timer: TextLabel }

local bar: Frame
local slots: { [string]: Slot } = {}

local function refresh()
	if not State.loaded then
		bar.Visible = false
		return
	end
	local profile = State.profile
	local bag = if type(profile.potionBag) == "table" then profile.potionBag else {}
	local timers = if type(profile.potions) == "table" then profile.potions else {}
	local now = os.time()
	local any = false
	for _, potion in Potions.list do
		local slot = slots[potion.id]
		local held = tonumber(bag[potion.id]) or 0
		local remaining = math.max(0, (tonumber(timers[potion.id]) or 0) - now)
		local show = held > 0 or remaining > 0
		slot.frame.Visible = show
		any = any or show
		slot.count.Text = if held > 0 then "x" .. held else ""
		slot.timer.Text = if remaining > 0 then Format.duration(remaining) else ""
	end
	local tutorial = (Root.canvas :: Frame):FindFirstChild("TutorialBanner")
	local tutorialUp = tutorial ~= nil and tutorial:IsA("GuiObject") and tutorial.Visible
	bar.Visible = any and not tutorialUp
end

function PotionBar.init()
	bar = Kit.new("Frame", {
		Name = "PotionBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -82),
		Size = UDim2.fromOffset(SLOT, SLOT),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		Parent = Root.canvas,
	}, { Kit.list(Enum.FillDirection.Horizontal, 6) }) :: Frame
	for order, potion in Potions.list do
		local id = potion.id
		local button = Kit.button("", "neutral", function()
			local bag = State.profile.potionBag
			if type(bag) == "table" and (tonumber(bag[id]) or 0) > 0 then
				Remotes.fire(Net.Potion_Use, id)
			end
		end, { Name = id, Size = UDim2.fromOffset(SLOT, SLOT), LayoutOrder = order, Visible = false })
		button.setColor(C.grape)
		local frame = button.instance
		local icon = Kit.icon("potion_" .. id, 36)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.45)
		icon.Parent = frame
		local count = Kit.label("", {
			Name = "Count",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 2, 0, -4),
			Size = UDim2.fromOffset(34, 18),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = C.sun,
			Parent = frame,
		})
		local timer = Kit.label("", {
			Name = "Timer",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 4),
			Size = UDim2.fromOffset(SLOT, 16),
			TextColor3 = C.cashLight,
			Parent = frame,
		}, 1.5)
		frame.Parent = bar
		slots[id] = { frame = frame, count = count, timer = timer }
	end
end

function PotionBar.start()
	State.watch({ "potionBag", "potions" }, refresh)
	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)
end

return PotionBar
