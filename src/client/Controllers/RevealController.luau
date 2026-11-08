--!strict
--[[
	RevealController: the reveal cinematic (GDD §9.1), built to be clipped.

	R0 Common/Uncommon: toast only. R1 Rare: card flip. R2 Epic: 3-card spin.
	R3 Legendary: silhouette roulette + gold rays. R4 Mythic: dim + rumble.
	R5 Divine: slow-mo, halo rings, white-out. R6 Celestial: hyperspace stars.
	R7 Cosmic: black-hole implosion -> explosion. R8 Secret: fake-out (a Cosmic
	plate cracks, glitches, a beat of silence, then a rainbow shatter).
	Every reveal ends on a big rarity title + "1 in N" + mutation stamp.

	The core composition stays inside the center 50% of the screen width (so a
	9:16 crop of a landscape recording keeps it). Timings, shake and skip rules
	come from Config.Reveal. Screen shake is skipped with "Reduce screen shake".
	The server keeps searching meanwhile: finds that arrive during a cinematic
	queue up (max 3); queued commons are merged into a "+N more finds" toast.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Format = require(Shared:WaitForChild("Format"))
local RevealConfig = require(Shared:WaitForChild("Config"):WaitForChild("Reveal")) :: any

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Root = require(UI.Root)
local Search = require(script.Parent.SearchController)
local Toast = require(script.Parent.ToastController)
local Settings = require(script.Parent.SettingsController)

local C = Theme.colors
local MAX_QUEUE = 3

local Reveal = {
	playing = false,
}

local overlay: Frame
local queue: { any } = {}
local merged = 0
local skipRequested = false

local function rarityColor(order: number): Color3
	return Color3.fromHex(Catalog.rarities[order].color)
end

-- Waits t seconds, returning early (true) if the player skipped.
local function pause(t: number): boolean
	local deadline = os.clock() + t
	while os.clock() < deadline do
		if skipRequested then
			return true
		end
		RunService.RenderStepped:Wait()
	end
	return skipRequested
end

local function tween(inst: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- Screen shake: UI stage jitter + camera offset. Skipped with Reduce screen shake.
local function shake(stage: Frame, px: number, seconds: number)
	if px <= 0 or Settings.reduceShake() then
		return
	end
	task.spawn(function()
		local character = (Players.LocalPlayer :: Player).Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local base = stage.Position
		local deadline = os.clock() + seconds
		while os.clock() < deadline and stage.Parent do
			local fade = (deadline - os.clock()) / seconds
			local dx, dy = (math.random() * 2 - 1) * px * fade, (math.random() * 2 - 1) * px * fade
			stage.Position = base + UDim2.fromOffset(dx, dy)
			if humanoid then
				humanoid.CameraOffset = Vector3.new(dx, dy, 0) * 0.03
			end
			RunService.RenderStepped:Wait()
		end
		stage.Position = base
		if humanoid then
			humanoid.CameraOffset = Vector3.zero
		end
	end)
end

local function circle(parent: Instance, size: number, color: Color3, transparency: number?, z: number?): Frame
	return Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		ZIndex = z or 92,
		Parent = parent,
	}, { Kit.corner(UDim.new(0.5, 0)) })
end

local function rainbow(): ColorSequence
	local keys = {}
	for i = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.8, 1)))
	end
	return ColorSequence.new(keys)
end

type Ctx = {
	payload: any,
	order: number,
	tier: any,
	stage: Frame,
	orb: Frame,
	rays: Frame,
	plate: Frame,
	title: TextLabel,
	name: TextLabel,
	odds: TextLabel,
	flash: Frame,
	running: boolean,
}

local function buildStage(payload: any, order: number, tierConfig: any): Ctx
	local canvas = Root.canvas :: Frame
	local width = math.max(300, canvas.Size.X.Offset * 0.5)
	local stage = Kit.new("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, width, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 91,
		Parent = overlay,
	}) :: Frame
	local rays = Kit.new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(360, 360),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 91,
		Parent = stage,
	}) :: Frame
	for i = 0, 11 do
		Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 14, 1, 0),
			Rotation = i * 15,
			BackgroundColor3 = rarityColor(order),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 91,
			Parent = rays,
		}, {
			Kit.new("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
	end
	local orb = circle(stage, 120, C.ink, 0, 93)
	Kit.stroke(C.white, 4).Parent = orb
	local plate = Kit.panel({
		Name = "Plate",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(math.min(320, width - 20), 104),
		ZIndex = 94,
		Visible = false,
		Parent = stage,
	}, UDim.new(0, 18))
	local title = Kit.text("", {
		Size = UDim2.new(1, -16, 0, 44),
		Position = UDim2.fromOffset(8, 4),
		TextStrokeColor3 = C.ink,
		TextStrokeTransparency = 0,
		ZIndex = 95,
		Parent = plate,
	})
	local name = Kit.text("", { Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 48), ZIndex = 95, Parent = plate })
	local odds = Kit.text("", {
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(8, 78),
		FontFace = Theme.fonts.number,
		TextColor3 = C.grape,
		ZIndex = 95,
		Parent = plate,
	})
	local flash = Kit.new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.white,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 98,
		Parent = overlay,
	}) :: Frame
	local ctx: Ctx = {
		payload = payload,
		order = order,
		tier = tierConfig,
		stage = stage,
		orb = orb,
		rays = rays,
		plate = plate,
		title = title,
		name = name,
		odds = odds,
		flash = flash,
		running = true,
	}
	-- rays spin while the stage exists
	task.spawn(function()
		while ctx.running do
			rays.Rotation = (rays.Rotation + 0.6) % 360
			RunService.RenderStepped:Wait()
		end
	end)
	return ctx
end

local function flashOnce(ctx: Ctx, color: Color3, peak: number, seconds: number)
	ctx.flash.BackgroundColor3 = color
	ctx.flash.BackgroundTransparency = peak
	tween(ctx.flash, seconds, { BackgroundTransparency = 1 })
end

-- R2: three cards orbit the orb, then collapse into it.
local function spinCards(ctx: Ctx, seconds: number)
	local cards = {}
	for i = 1, 3 do
		local card = Kit.panel({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(60, 84),
			BackgroundColor3 = C.white,
			ZIndex = 94,
			Parent = ctx.stage,
		}, UDim.new(0, 10))
		Kit.rarityStroke(card, rarityColor(ctx.order), ctx.order)
		cards[i] = card
	end
	local start = os.clock()
	while os.clock() - start < seconds and not skipRequested do
		local t = (os.clock() - start) / seconds
		local radius = 110 * (1 - t)
		for i, card in cards do
			local angle = t * math.pi * 6 + i * (math.pi * 2 / 3)
			card.Position = UDim2.new(0.5, math.cos(angle) * radius, 0.42, math.sin(angle) * radius * 0.5)
			card.Rotation = math.deg(angle) % 360
		end
		RunService.RenderStepped:Wait()
	end
	for _, card in cards do
		card:Destroy()
	end
end

-- R3: the silhouette's name cycles through the segment's pool, slowing down.
local function roulette(ctx: Ctx, seconds: number)
	local segment = Catalog.segmentById[Catalog.treasureSegment[ctx.payload.treasureId]]
	local label = Kit.text("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(300, 40),
		TextColor3 = C.white,
		TextStrokeColor3 = C.ink,
		TextStrokeTransparency = 0,
		ZIndex = 95,
		Parent = ctx.stage,
	})
	local start = os.clock()
	local gap = 0.05
	while os.clock() - start < seconds and not skipRequested do
		local pick = segment.treasures[math.random(1, #segment.treasures)]
		label.Text = "??? " .. pick.name .. " ???"
		pause(gap)
		gap *= 1.18
	end
	label:Destroy()
end

-- R5 halo rings / R7 implosion share these expanding (or collapsing) rings.
local function rings(ctx: Ctx, count: number, color: Color3, inward: boolean, seconds: number)
	for i = 1, count do
		task.delay((i - 1) * seconds / count, function()
			if not ctx.running then
				return
			end
			local ring = circle(ctx.stage, if inward then 420 else 60, color, 1, 92)
			local stroke = Kit.stroke(color, 4)
			stroke.Parent = ring
			tween(ring, seconds * 0.8, { Size = UDim2.fromOffset(if inward then 10 else 420, if inward then 10 else 420) })
			tween(stroke, seconds * 0.8, { Transparency = 1 })
			task.delay(seconds * 0.8, function()
				ring:Destroy()
			end)
		end)
	end
end

-- R6: stars rush outward from the center (hyperspace). R7 uses inward = true.
local function stars(count: number, color: Color3, inward: boolean, seconds: number)
	for i = 1, count do
		local angle = math.random() * math.pi * 2
		local far = UDim2.new(0.5, math.cos(angle) * 600, 0.42, math.sin(angle) * 360)
		local near = UDim2.fromScale(0.5, 0.42)
		local dot = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = if inward then far else near,
			Size = UDim2.fromOffset(6, 6),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 92,
			Parent = overlay,
		}, { Kit.corner(UDim.new(0.5, 0)) })
		local delay = (i / count) * seconds * 0.6
		task.delay(delay, function()
			if dot.Parent then
				tween(
					dot,
					seconds * 0.4,
					{ Position = if inward then near else far, Size = UDim2.fromOffset(if inward then 2 else 14, 4) },
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				)
			end
		end)
		task.delay(delay + seconds * 0.4, function()
			dot:Destroy()
		end)
	end
end

-- R8: glitch bars over the cracked fake plate.
local function glitch(ctx: Ctx, seconds: number)
	local start = os.clock()
	while os.clock() - start < seconds and not skipRequested do
		local bar = Kit.new("Frame", {
			Position = UDim2.new(0, math.random(-40, 40), math.random(), 0),
			Size = UDim2.new(1, 0, 0, math.random(4, 18)),
			BackgroundColor3 = Color3.fromHSV(math.random(), 0.9, 1),
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ZIndex = 97,
			Parent = overlay,
		})
		ctx.plate.Rotation = math.random(-6, 6)
		task.delay(0.08, function()
			bar:Destroy()
		end)
		RunService.RenderStepped:Wait()
	end
	ctx.plate.Rotation = 0
end

local function showPlate(ctx: Ctx, order: number, treasureName: string, oneIn: number)
	local rarity = Catalog.rarities[order]
	ctx.title.Text = string.upper(rarity.name) .. "!"
	ctx.title.TextColor3 = rarityColor(order)
	local gradient = ctx.title:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient:Destroy()
	end
	if rarity.colorEnd then
		ctx.title.TextColor3 = C.white
		Kit.new("UIGradient", { Color = ColorSequence.new(rarityColor(order), Color3.fromHex(rarity.colorEnd)), Parent = ctx.title })
	elseif rarity.rainbowEdge then
		ctx.title.TextColor3 = C.white
		local g = Kit.new("UIGradient", { Color = rainbow(), Parent = ctx.title }) :: UIGradient
		task.spawn(function()
			while ctx.running do
				g.Offset = Vector2.new(math.sin(os.clock() * 2) * 0.5, 0)
				RunService.RenderStepped:Wait()
			end
		end)
	end
	ctx.name.Text = treasureName
	ctx.odds.Text = if oneIn > 0 then Format.oneIn(oneIn) else ""
	Kit.rarityStroke(ctx.plate, Kit.readable(rarityColor(order)), order)
	ctx.plate.Visible = true
	local scale = ctx.plate:FindFirstChildOfClass("UIScale") or Kit.new("UIScale", { Parent = ctx.plate })
	scale.Scale = 0.4
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

local function play(payload: any)
	local order = math.clamp(tonumber(payload.rarity) or 1, 1, #Catalog.rarities)
	local rarity = Catalog.rarities[order]
	local tierConfig = RevealConfig.tiers[rarity.revealTier + 1]
	local treasure = Catalog.treasureById[payload.treasureId]
	local treasureName = if treasure then treasure.name else "???"
	local total = tierConfig.seconds
	local suspense = total * 0.55
	skipRequested = false

	overlay.Visible = true
	overlay.BackgroundTransparency = 1
	local ctx = buildStage(payload, order, tierConfig)

	local skipButton: Kit.Button? = nil
	if tierConfig.skippableAfter ~= nil then
		local button = Kit.button("Skip ▶", "neutral", function()
			skipRequested = true
		end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 8), Size = UDim2.fromOffset(120, 48), ZIndex = 99, Visible = false })
		button.instance.Parent = ctx.stage
		skipButton = button
		task.delay(tierConfig.skippableAfter, function()
			if button.instance.Parent then
				button.instance.Visible = true
			end
		end)
	end

	local tier = rarity.revealTier
	-- a light dim for Rare..Legendary keeps the HUD from cluttering the clip;
	-- Mythic+ dim further inside their own sequences
	if tier >= 1 and tier <= 3 then
		tween(overlay, 0.2, { BackgroundTransparency = ({ 0.7, 0.6, 0.55 })[tier] })
	end
	if tier == 1 then
		-- card flip: the plate turns over with a blue flash
		showPlate(ctx, order, treasureName, rarity.oneIn)
		ctx.plate.Size = UDim2.fromOffset(0, 104)
		tween(ctx.plate, suspense, { Size = UDim2.fromOffset(math.min(320, ctx.stage.Size.X.Offset - 20), 104) }, Enum.EasingStyle.Back)
		flashOnce(ctx, rarityColor(order), 0.6, 0.4)
		pause(suspense)
	elseif tier == 2 then
		shake(ctx.stage, tierConfig.shakePx, 0.15)
		spinCards(ctx, suspense)
	elseif tier == 3 then
		ctx.rays.Visible = true
		shake(ctx.stage, tierConfig.shakePx, suspense)
		roulette(ctx, suspense)
	elseif tier == 4 then
		tween(overlay, 0.4, { BackgroundTransparency = 0.35 })
		shake(ctx.stage, tierConfig.shakePx, suspense)
		pause(suspense)
	elseif tier == 5 then
		tween(overlay, 0.4, { BackgroundTransparency = 0.4 })
		local scale = Kit.new("UIScale", { Scale = 0.5, Parent = ctx.orb }) :: UIScale
		tween(scale, suspense, { Scale = 1.3 }, Enum.EasingStyle.Sine)
		rings(ctx, 3, Color3.fromHex("#FFF3B0"), false, suspense)
		shake(ctx.stage, tierConfig.shakePx, suspense)
		pause(suspense * 0.85)
		flashOnce(ctx, C.white, 0, 0.9)
		pause(suspense * 0.15)
	elseif tier == 6 then
		tween(overlay, 0.3, { BackgroundTransparency = 0.25 })
		stars(60, Color3.fromHex("#6EF2FF"), false, suspense)
		shake(ctx.stage, tierConfig.shakePx, suspense)
		pause(suspense)
		flashOnce(ctx, Color3.fromHex("#6EF2FF"), 0.2, 0.8)
	elseif tier == 7 then
		tween(overlay, 0.3, { BackgroundTransparency = 0.15 })
		local hole = circle(ctx.stage, 10, Color3.new(0, 0, 0), 0, 92)
		tween(hole, suspense, { Size = UDim2.fromOffset(260, 260) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		stars(50, Color3.fromHex("#B98BFF"), true, suspense)
		rings(ctx, 3, Color3.fromHex("#7B2FFF"), true, suspense)
		shake(ctx.stage, tierConfig.shakePx, suspense)
		pause(suspense)
		hole:Destroy()
		flashOnce(ctx, Color3.fromHex("#FF4FD8"), 0, 0.8)
	elseif tier == 8 then
		-- the fake-out: looks like a Cosmic find...
		tween(overlay, 0.3, { BackgroundTransparency = 0.15 })
		stars(30, Color3.fromHex("#B98BFF"), true, suspense * 0.3)
		pause(suspense * 0.3)
		local cosmic = Catalog.rarities[9]
		showPlate(ctx, 9, "???", cosmic.oneIn)
		shake(ctx.stage, 6, suspense * 0.2)
		pause(suspense * 0.25)
		-- ...the plate cracks and glitches...
		shake(ctx.stage, tierConfig.shakePx, suspense * 0.2)
		glitch(ctx, suspense * 0.25)
		-- ...a beat of silence...
		ctx.stage.Visible = false
		overlay.BackgroundTransparency = 0
		pause(0.6)
		ctx.stage.Visible = true
		-- ...and a rainbow shatter
		ctx.flash.BackgroundTransparency = 0
		Kit.new("UIGradient", { Color = rainbow(), Parent = ctx.flash })
		tween(ctx.flash, 1, { BackgroundTransparency = 1 })
		overlay.BackgroundTransparency = 0.2
	end

	-- the reveal: orb takes the rarity (and mutation) color, rays burst, plate lands
	local orbColor = rarityColor(order)
	for _, id in payload.mutation or {} do
		local m = Catalog.mutationById[id]
		if m and m.visual.color then
			orbColor = Color3.fromHex(m.visual.color)
		end
	end
	ctx.orb.BackgroundColor3 = orbColor
	if #(payload.mutation or {}) == 0 and (rarity.colorEnd or rarity.rainbowEdge) then
		ctx.orb.BackgroundColor3 = C.white
		Kit.new("UIGradient", {
			Color = if rarity.rainbowEdge then rainbow() else ColorSequence.new(rarityColor(order), Color3.fromHex(rarity.colorEnd or rarity.color)),
			Rotation = 45,
			Parent = ctx.orb,
		})
	elseif rarity.rainbowEdge then
		Kit.new("UIGradient", { Color = rainbow(), Rotation = 45, Parent = ctx.orb })
		ctx.orb.BackgroundColor3 = Color3.new(1, 1, 1):Lerp(orbColor, 0.5)
	end
	if tier >= 2 then
		ctx.rays.Visible = true
		local scale = Kit.new("UIScale", { Scale = 0.3, Parent = ctx.rays }) :: UIScale
		tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	showPlate(ctx, order, treasureName, rarity.oneIn)

	local remaining = math.max(0.4, total - suspense)
	local mutationNames = {}
	for _, id in payload.mutation or {} do
		local m = Catalog.mutationById[id]
		if m then
			table.insert(mutationNames, string.upper(m.name))
		end
	end
	if #mutationNames > 0 then
		pause(math.min(0.4, remaining * 0.5))
		local stamp = Kit.text("+" .. table.concat(mutationNames, " +") .. "!", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.72, 0.3),
			Size = UDim2.fromOffset(220, 46),
			Rotation = -12,
			TextColor3 = C.sun,
			TextStrokeColor3 = C.ink,
			TextStrokeTransparency = 0,
			ZIndex = 96,
			Parent = ctx.stage,
		})
		local s = Kit.new("UIScale", { Scale = 2.2, Parent = stamp }) :: UIScale
		tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		pause(RevealConfig.mutationStampSeconds)
	end
	pause(remaining)
	if skipButton then
		skipButton.instance.Visible = false
	end

	-- fade out
	ctx.running = false
	tween(overlay, 0.25, { BackgroundTransparency = 1 })
	ctx.stage:Destroy()
	ctx.flash:Destroy()
	task.wait(0.25)
	for _, child in overlay:GetChildren() do
		child:Destroy()
	end
	overlay.Visible = false
end

local function pump()
	if Reveal.playing then
		return
	end
	Reveal.playing = true
	while #queue > 0 do
		local payload = table.remove(queue, 1)
		local ok, err = pcall(play :: any, payload)
		if not ok then
			warn("[Reveal] " .. tostring(err))
			overlay.Visible = false
		end
	end
	Reveal.playing = false
	if merged > 0 then
		Toast.show(string.format("+%d more find%s", merged, if merged == 1 then "" else "s"), C.cash)
		merged = 0
	end
end

--- Entry point for every find (also used by tests).
function Reveal.handle(payload: any)
	local order = math.clamp(tonumber(payload.rarity) or 1, 1, #Catalog.rarities)
	local tier = Catalog.rarities[order].revealTier
	if tier == 0 then
		if Reveal.playing then
			merged += 1
		else
			local text, color = Search.findText(payload)
			Toast.show(text, color, 2)
		end
		return
	end
	if #queue >= MAX_QUEUE then
		-- keep the rarest queued reveals; the lowest becomes part of the merged toast
		table.sort(queue, function(a, b)
			return (tonumber(a.rarity) or 0) > (tonumber(b.rarity) or 0)
		end)
		if (tonumber(queue[#queue].rarity) or 0) < order then
			table.remove(queue)
			merged += 1
		else
			merged += 1
			return
		end
	end
	table.insert(queue, payload)
	task.spawn(pump)
end

function Reveal.init()
	overlay = Kit.new("Frame", {
		Name = "Reveal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 90,
		Parent = Root.canvas,
	}) :: Frame
end

function Reveal.start()
	Search.revealed:Connect(Reveal.handle)
end

return Reveal
