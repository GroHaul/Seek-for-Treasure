--!strict
--[[
	BannerController: the Mythic+ server banner (GDD §9.2). Shown to everyone in
	the server: "⭐ Name found Crystal Dragonling [Mythic] (1 in 1,500)!",
	rarity-colored, 5 s each, at most 3 queued. Sits at the top, centered on the
	cash group's column so it never covers the chip grid or the menus.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Format = require(Shared:WaitForChild("Format"))
local RevealConfig = require(Shared:WaitForChild("Config"):WaitForChild("Reveal")) :: any

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Root = require(UI.Root)
local Remotes = require(script.Parent.Parent.Remotes)
local Reveal = require(script.Parent.RevealController)

local C = Theme.colors
local CHIPS_RIGHT = 280 -- keep in step with HudController's chip grid
local RIGHT_MENU = 90

local Banner = {}

local banner: Frame
local text: TextLabel
local queue: { any } = {}
local showing = false

local function place()
	local width = (Root.canvas :: Frame).Size.X.Offset
	local centerX = math.max(width / 2, CHIPS_RIGHT + 125)
	local room = 2 * math.min(centerX - CHIPS_RIGHT, width - RIGHT_MENU - centerX)
	banner.Position = UDim2.fromOffset(centerX, 4)
	banner.Size = UDim2.fromOffset(math.min(560, room), 54)
end

--- Banner text for a payload (exposed for tests).
function Banner.textFor(payload: any): string?
	local treasure = Catalog.treasureById[payload.treasureId]
	local rarity = Catalog.rarities[tonumber(payload.rarity) or 0]
	if treasure == nil or rarity == nil or type(payload.displayName) ~= "string" then
		return nil
	end
	local mutation = ""
	for _, id in payload.mutation or {} do
		local m = Catalog.mutationById[id]
		if m then
			mutation ..= string.upper(m.name) .. " "
		end
	end
	return string.format(
		'⭐ %s found %s%s <font color="#%s">[%s]</font> (%s)!',
		payload.displayName,
		mutation,
		treasure.name,
		Kit.readable(Color3.fromHex(rarity.color)):ToHex(),
		rarity.name,
		Format.oneIn(rarity.oneIn)
	)
end

local function pump()
	if showing then
		return
	end
	showing = true
	while #queue > 0 do
		local payload = table.remove(queue, 1)
		-- never spoil the finder's own cinematic (e.g. the Secret fake-out)
		if payload.userId == (Players.LocalPlayer :: Player).UserId then
			task.wait(0.2)
			while Reveal.playing do
				task.wait(0.2)
			end
		end
		local message = Banner.textFor(payload)
		if message then
			local rarity = Catalog.rarities[payload.rarity]
			text.Text = message
			Kit.rarityStroke(banner, Color3.fromHex(rarity.color), rarity.order)
			place()
			banner.Visible = true
			local scale = banner:FindFirstChildOfClass("UIScale") :: UIScale
			scale.Scale = 0.5
			TweenService:Create(scale, Theme.motion.bouncy, { Scale = 1 }):Play()
			task.wait(RevealConfig.banner.seconds)
			banner.Visible = false
			task.wait(0.2)
		end
	end
	showing = false
end

function Banner.init()
	banner = Kit.panel({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.cream,
		Visible = false,
		ZIndex = 85,
		Parent = Root.canvas,
	}, UDim.new(0.5, 0))
	Kit.new("UIScale", { Parent = banner })
	text = Kit.text("", { Size = UDim2.new(1, -28, 1, -12), Position = UDim2.fromOffset(14, 6), ZIndex = 86, Parent = banner })
	place();
	(Root.canvas :: Frame):GetPropertyChangedSignal("Size"):Connect(place)
end

function Banner.show(payload: any)
	if #queue >= RevealConfig.banner.queueMax then
		return
	end
	table.insert(queue, payload)
	task.spawn(pump)
end

function Banner.start()
	Remotes.on(Net.Announce_Banner, function(payload: any)
		if type(payload) == "table" then
			Banner.show(payload)
		end
	end)
end

return Banner
