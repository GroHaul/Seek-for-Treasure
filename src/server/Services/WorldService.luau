--!strict
--[[
	WorldService: builds Workspace.World at server start (placeholder geometry in
	the Sunny Toybox palette until the ForgeGUI models exist).

	Layout (studs): Pawprint Meadow search field is a 60 x 60 square at the
	origin. Four plots face it from the north and four from the south; each
	plot's front edge is 30 studs from the meadow edge (GDD §1.2). The market
	plaza (GDD §15.2) is west of the meadow: a round plaza with the Tools,
	Potions and Upgrades stalls facing its center, each with a ProximityPrompt
	(attribute StallKind) that opens that stall's panel on the client.

	If a hand-made Workspace.World already exists (no SFT_Managed attribute),
	it is used as-is and nothing is built.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = Shared.Config
local PlotConfig = require(Config.Plot) :: Types.PlotConfig
local Upgrades = require(Config.Upgrades) :: Types.UpgradesConfig
local Social = require(Config.Social) :: Types.SocialConfig

local ZONE_HEIGHT = 16
local MEADOW_SIZE = 60
local PLOT_WIDTH = 44
local PLOT_DEPTH = 52
local PLOT_GAP_TO_MEADOW = 30

local PALETTE = {
	sky = Color3.fromHex("#49B6FF"),
	sun = Color3.fromHex("#FFD23F"),
	leaf = Color3.fromHex("#5BD66B"),
	coral = Color3.fromHex("#FF6B6B"),
	grape = Color3.fromHex("#8E5CFF"),
	cream = Color3.fromHex("#FFF4DF"),
	ink = Color3.fromHex("#1D2340"),
	cash = Color3.fromHex("#3DDC84"),
	grass = Color3.fromHex("#7ED957"),
	path = Color3.fromHex("#E8D3A8"),
	stone = Color3.fromHex("#C9CED6"),
}

export type PlotInfo = {
	index: number,
	model: Model,
	cframe: CFrame, -- local -Z faces the meadow
	spawn: BasePart,
	pedestals: { BasePart }, -- by slot number
	arch: BasePart,
	padZone: BasePart,
	padVisual: BasePart,
}

export type MarketInfo = {
	center: Vector3,
	radius: number,
	spawn: BasePart,
	stalls: { [string]: Model }, -- "Tools" | "Potions" | "Upgrades"
}

local MARKET_CENTER = Vector3.new(-88, 0, 0)
local MARKET_RADIUS = 24
local STALL_DISTANCE = 18
local WOOD = Color3.fromHex("#A8713F")
local WOOD_DARK = Color3.fromHex("#7A4E2B")

local STALLS = {
	{ kind = "Tools", title = "TOOLS", color = Color3.fromHex("#49B6FF"), angle = 120, goods = "tools" },
	{ kind = "Potions", title = "POTIONS", color = Color3.fromHex("#8E5CFF"), angle = 180, goods = "potions" },
	{ kind = "Upgrades", title = "UPGRADES", color = Color3.fromHex("#3DDC84"), angle = 240, goods = "gems" },
}

local WorldService = {
	plots = {} :: { PlotInfo },
	market = nil :: MarketInfo?,
	PALETTE = PALETTE,
	MARKET_CENTER = MARKET_CENTER,
	MARKET_RADIUS = MARKET_RADIUS,
}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = parent
	return p
end

local function zonePart(name: string, cframe: CFrame, size: Vector3, parent: Instance): Part
	return part({
		Name = name,
		CFrame = cframe,
		Size = size,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = parent,
	})
end

local function label(parent: BasePart, text: string, size: UDim2, offset: Vector3, maxDistance: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = maxDistance
	gui.AlwaysOnTop = false
	local text_ = Instance.new("TextLabel")
	text_.Name = "Text"
	text_.BackgroundTransparency = 1
	text_.Size = UDim2.fromScale(1, 1)
	text_.Font = Enum.Font.FredokaOne
	text_.TextScaled = true
	text_.TextColor3 = PALETTE.cream
	text_.TextStrokeColor3 = PALETTE.ink
	text_.TextStrokeTransparency = 0
	text_.Text = text
	text_.Parent = gui
	gui.Parent = parent
	return text_
end

local function buildMeadow(world: Folder)
	local area = Instance.new("Model")
	area.Name = "Pets"
	area:SetAttribute("SegmentId", "pets")

	part({
		Name = "Field",
		Size = Vector3.new(MEADOW_SIZE, 1, MEADOW_SIZE),
		CFrame = CFrame.new(0, 0.5, 0),
		Color = PALETTE.grass,
		Material = Enum.Material.Grass,
		Parent = area,
	})

	-- low picket fence around the field, gaps in the middle of each side
	local half = MEADOW_SIZE / 2
	for side = 1, 4 do
		local rot = CFrame.Angles(0, math.rad(90 * side), 0)
		for i = -2, 2 do
			if i ~= 0 then
				local cf = rot * CFrame.new(i * 11, 2, -half)
				part({
					Name = "Fence",
					Size = Vector3.new(9, 2, 0.6),
					CFrame = cf,
					Color = PALETTE.cream,
					Parent = area,
				})
			end
		end
	end

	-- flower bushes (placeholder for the ForgeGUI meadow kit)
	local bushColors = { PALETTE.coral, PALETTE.sun, PALETTE.grape, PALETTE.sky }
	local rng = Random.new(7)
	for i = 1, 14 do
		local x = rng:NextNumber(-half + 4, half - 4)
		local z = rng:NextNumber(-half + 4, half - 4)
		if math.abs(x) > 6 or math.abs(z) > 6 then
			local bush = part({
				Name = "FlowerBush",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * rng:NextNumber(2.5, 4),
				CFrame = CFrame.new(x, 1.8, z),
				Color = bushColors[(i % #bushColors) + 1],
				CanCollide = false,
				Parent = area,
			})
			bush.Material = Enum.Material.SmoothPlastic
		end
	end

	local fountain = part({
		Name = "PetBowlFountain",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.5, 8, 8),
		CFrame = CFrame.new(0, 1.75, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = PALETTE.sky,
		Parent = area,
	})
	label(fountain, "Pawprint Meadow", UDim2.fromScale(14, 3), Vector3.new(0, 7, 0), 160)

	local zone = zonePart("SearchZone", CFrame.new(0, ZONE_HEIGHT / 2, 0), Vector3.new(MEADOW_SIZE, ZONE_HEIGHT, MEADOW_SIZE), area)
	zone:SetAttribute("SegmentId", "pets")
	CollectionService:AddTag(zone, "SFT_SearchZone")

	local segments = Instance.new("Folder")
	segments.Name = "Segments"
	area.Parent = segments
	segments.Parent = world
end

-- "Next code at X likes" board (GDD §9.7). The live like counter is off until
-- HTTP + a proxy are approved, so it shows the fallback text.
local function buildCodeBoard(world: Folder)
	local board = part({
		Name = "CodeBoard",
		Size = Vector3.new(16, 9, 0.8),
		CFrame = CFrame.new(MEADOW_SIZE / 2 + 14, 6.5, 0) * CFrame.Angles(0, math.rad(-90), 0),
		Color = PALETTE.cream,
		Parent = world,
	})
	for _, sx in { -7, 7 } do
		part({ Name = "Post", Size = Vector3.new(1, 6, 1), CFrame = board.CFrame * CFrame.new(sx, -6, 0), Color = PALETTE.ink, Parent = board })
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.45)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = PALETTE.coral
	title.Text = "🎁 CODES"
	title.Parent = gui
	local body = Instance.new("TextLabel")
	body.Name = "Next"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromScale(0.05, 0.45)
	body.Size = UDim2.fromScale(0.9, 0.45)
	body.Font = Enum.Font.FredokaOne
	body.TextScaled = true
	body.TextColor3 = PALETTE.ink
	body.Text = string.gsub(Social.codeBoard.fallbackText, "{n}", string.format("%d", Social.codeBoard.likeMilestones[1]))
	body.Parent = gui
	gui.Parent = board
end

-- Market (GDD §15.2) ---------------------------------------------------------

-- A few simple goods on the shelf and counter, in the stall's colors.
local function stallGoods(kind: string, cf: CFrame, color: Color3, parent: Instance)
	for i = -2, 2 do
		local x = i * 2.1
		if kind == "potions" then
			local bottle = part({
				Name = "Bottle",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.4, 0.9, 0.9),
				CFrame = cf * CFrame.new(x, 6.5, 3.4) * CFrame.Angles(0, 0, math.rad(90)),
				Color = if i % 2 == 0 then color else PALETTE.sky,
				Material = Enum.Material.Glass,
				Transparency = 0.15,
				CanCollide = false,
				Parent = parent,
			})
			bottle.Reflectance = 0.2
		elseif kind == "gems" then
			part({
				Name = "Gem",
				Size = Vector3.new(0.9, 0.9, 0.9),
				CFrame = cf * CFrame.new(x, 6.4, 3.4) * CFrame.Angles(math.rad(45), math.rad(45), 0),
				Color = if i % 2 == 0 then PALETTE.sky else color,
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = parent,
			})
		else
			part({
				Name = "Whistle",
				Size = Vector3.new(1.4, 0.5, 0.5),
				CFrame = cf * CFrame.new(x, 6.1, 3.4) * CFrame.Angles(0, math.rad(20 * i), 0),
				Color = if i % 2 == 0 then PALETTE.sun else color,
				Material = Enum.Material.Metal,
				CanCollide = false,
				Parent = parent,
			})
		end
	end
end

local function buildStall(def: { kind: string, title: string, color: Color3, angle: number, goods: string }, parent: Instance): Model
	local angle = math.rad(def.angle)
	local position = MARKET_CENTER + Vector3.new(math.cos(angle), 0, math.sin(angle)) * STALL_DISTANCE
	-- local -Z (the counter side) faces the plaza center
	local cf = CFrame.lookAt(position, Vector3.new(MARKET_CENTER.X, 0, MARKET_CENTER.Z))
	local model = Instance.new("Model")
	model.Name = def.kind .. "Stall"
	model:SetAttribute("StallKind", def.kind)

	part({
		Name = "Floor",
		Size = Vector3.new(15, 0.6, 11),
		CFrame = cf * CFrame.new(0, 1.1, 0.5),
		Color = WOOD_DARK,
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})
	local counter = part({
		Name = "Counter",
		Size = Vector3.new(12.5, 3.4, 2),
		CFrame = cf * CFrame.new(0, 3.1, -3.6),
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})
	part({ Name = "CounterTop", Size = Vector3.new(13.2, 0.5, 2.8), CFrame = cf * CFrame.new(0, 5.05, -3.6), Color = PALETTE.cream, Parent = model })
	part({
		Name = "BackWall",
		Size = Vector3.new(13.5, 8, 0.8),
		CFrame = cf * CFrame.new(0, 5.4, 4.6),
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})
	part({ Name = "Shelf", Size = Vector3.new(11.5, 0.4, 1.6), CFrame = cf * CFrame.new(0, 5.8, 3.6), Color = PALETTE.cream, Parent = model })
	for _, x in { -6.6, 6.6 } do
		for _, z in { -4.6, 4.6 } do
			part({ Name = "Post", Size = Vector3.new(0.9, 10.5, 0.9), CFrame = cf * CFrame.new(x, 6.5, z), Color = WOOD_DARK, Parent = model })
		end
	end
	-- striped awning, tilted down toward the customer, with a valance at the front
	local awning = cf * CFrame.new(0, 12, -0.3) * CFrame.Angles(math.rad(-14), 0, 0)
	for i = 0, 6 do
		local stripe = if i % 2 == 0 then def.color else PALETTE.cream
		local x = -6.9 + i * 2.3
		part({ Name = "Awning", Size = Vector3.new(2.3, 0.5, 11.5), CFrame = awning * CFrame.new(x, 0, 0), Color = stripe, Parent = model })
		part({ Name = "Valance", Size = Vector3.new(2.3, 1.3, 0.4), CFrame = awning * CFrame.new(x, -0.8, -5.6), Color = stripe, Parent = model })
	end
	stallGoods(def.goods, cf, def.color, model)

	-- big floating title, readable from across the plaza
	local signAnchor = part({
		Name = "Sign",
		Size = Vector3.new(1, 1, 1),
		CFrame = cf * CFrame.new(0, 16.5, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = model,
	})
	local gui = Instance.new("BillboardGui")
	gui.Name = "Title"
	gui.Size = UDim2.fromScale(14, 4)
	gui.MaxDistance = 300
	gui.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 1)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = def.title
	title.TextColor3 = Color3.new(1, 1, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), def.color)
	gradient.Rotation = 90
	gradient.Parent = title
	local stroke = Instance.new("UIStroke")
	stroke.Color = PALETTE.ink
	stroke.Thickness = 3
	stroke.Parent = title
	title.Parent = gui
	gui.Parent = signAnchor

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Open"
	prompt.ActionText = "Open"
	prompt.ObjectText = def.kind .. " Stall"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt:SetAttribute("StallKind", def.kind)
	prompt.Parent = counter

	model.Parent = parent
	return model
end

local function buildMarket(world: Folder)
	local market = Instance.new("Model")
	market.Name = "Market"
	local flat = CFrame.new(MARKET_CENTER.X, 0, MARKET_CENTER.Z) * CFrame.Angles(0, 0, math.rad(90))
	part({
		Name = "Plaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, MARKET_RADIUS * 2, MARKET_RADIUS * 2),
		CFrame = flat * CFrame.new(0.4, 0, 0),
		Color = PALETTE.cream,
		Parent = market,
	})
	part({
		Name = "PlazaRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.84, 20, 20),
		CFrame = flat * CFrame.new(0.42, 0, 0),
		Color = PALETTE.coral,
		Parent = market,
	})
	part({
		Name = "PlazaCenter",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.88, 13, 13),
		CFrame = flat * CFrame.new(0.44, 0, 0),
		Color = PALETTE.sun,
		Parent = market,
	})
	-- coral rays from the center to the edge, between the stalls
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		part({
			Name = "Ray",
			Size = Vector3.new(MARKET_RADIUS * 2 - 2, 0.84, 2.4),
			CFrame = CFrame.new(MARKET_CENTER.X, 0.42, MARKET_CENTER.Z) * CFrame.Angles(0, a, 0),
			Color = PALETTE.coral,
			Parent = market,
		})
	end
	-- where the SHOPS teleport drops you: the plaza's east side, facing the stalls
	local spawnAt = MARKET_CENTER + Vector3.new(10, 3.5, 0)
	local spawnPart: BasePart = zonePart("Spawn", CFrame.lookAt(spawnAt, spawnAt - Vector3.xAxis), Vector3.new(4, 1, 4), market)

	local stalls: { [string]: Model } = {}
	for _, def in STALLS do
		stalls[def.kind] = buildStall(def, market)
	end
	market.Parent = world
	WorldService.market = { center = MARKET_CENTER, radius = MARKET_RADIUS, spawn = spawnPart, stalls = stalls }
	-- teleport targets as attributes: they replicate even when the parts are streamed out
	world:SetAttribute("MarketSpawn", spawnPart.CFrame)
	local toolsCounter = stalls.Tools:FindFirstChild("Counter") :: BasePart
	world:SetAttribute("ToolsStall", toolsCounter.Position)
end

local function plotCFrame(index: number): CFrame
	local perSide = PlotConfig.plotsPerServer / 2
	local north = index <= perSide
	local column = if north then index - 1 else index - perSide - 1
	local x = (column - (perSide - 1) / 2) * (PLOT_WIDTH + 6)
	local z = MEADOW_SIZE / 2 + PLOT_GAP_TO_MEADOW + PLOT_DEPTH / 2
	local center = Vector3.new(x, 0, if north then -z else z)
	return CFrame.lookAt(center, Vector3.new(x, 0, 0))
end

--- Pedestal slot n (1..20) position in plot space: 4 columns x 5 rows, front row first.
local function slotOffset(slot: number): Vector3
	local columns = PlotConfig.gridColumns
	local col = (slot - 1) % columns
	local row = (slot - 1) // columns
	return Vector3.new((col - (columns - 1) / 2) * 9, 0, -10 + row * 8)
end

local function buildPlot(index: number, parent: Folder): PlotInfo
	local cf = plotCFrame(index)
	local model = Instance.new("Model")
	model.Name = string.format("Plot_%02d", index)
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerUserId", 0)

	part({
		Name = "Base",
		Size = Vector3.new(PLOT_WIDTH, 1, PLOT_DEPTH),
		CFrame = cf * CFrame.new(0, 0.5, 0),
		Color = PALETTE.cream,
		Parent = model,
	})
	part({
		Name = "Border",
		Size = Vector3.new(PLOT_WIDTH + 2, 0.8, PLOT_DEPTH + 2),
		CFrame = cf * CFrame.new(0, 0.4, 0),
		Color = PALETTE.ink,
		Parent = model,
	})

	-- owner arch at the front edge
	local front = -PLOT_DEPTH / 2 + 1
	for _, sx in { -8, 8 } do
		part({
			Name = "ArchPillar",
			Size = Vector3.new(2, 12, 2),
			CFrame = cf * CFrame.new(sx, 7, front),
			Color = PALETTE.sun,
			Parent = model,
		})
	end
	local arch = part({
		Name = "Arch",
		Size = Vector3.new(19, 2.5, 2),
		CFrame = cf * CFrame.new(0, 14, front),
		Color = PALETTE.coral,
		Parent = model,
	})
	label(arch, "Free plot", UDim2.fromScale(16, 3), Vector3.new(0, 3.5, 0), 200)

	local spawnPart = zonePart("Spawn", cf * CFrame.new(0, 3.5, front + 5), Vector3.new(4, 1, 4), model)

	-- collect pad (visual) + its detection box
	local padCf = cf * CFrame.new(14, 0, front + 6)
	local padVisual = part({
		Name = "CollectPad",
		Size = Vector3.new(8, 0.6, 8),
		CFrame = padCf * CFrame.new(0, 1.3, 0),
		Color = PALETTE.cash,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	label(padVisual, "Collect $0", UDim2.fromOffset(170, 40), Vector3.new(0, 3, 0), 80)
	local padZone = zonePart("CollectZone", padCf * CFrame.new(0, 5, 0), Vector3.new(8, 10, 8), model)
	padZone:SetAttribute("PlotIndex", index)
	CollectionService:AddTag(padZone, "SFT_CollectPad")

	local pedestalFolder = Instance.new("Folder")
	pedestalFolder.Name = "Pedestals"
	local pedestals: { BasePart } = {}
	for slot = 1, Upgrades.slots.max do
		local ped = part({
			Name = string.format("P%02d", slot),
			Size = Vector3.new(5, 1.6, 5),
			CFrame = cf * CFrame.new(slotOffset(slot) + Vector3.new(0, 1.8, 0)),
			Color = PALETTE.stone,
			Parent = pedestalFolder,
		})
		ped:SetAttribute("Slot", slot)
		pedestals[slot] = ped
	end
	pedestalFolder.Parent = model
	model.PrimaryPart = model:FindFirstChild("Base") :: BasePart
	model.Parent = parent

	return {
		index = index,
		model = model,
		cframe = cf,
		spawn = spawnPart,
		pedestals = pedestals,
		arch = arch,
		padZone = padZone,
		padVisual = padVisual,
	}
end

local function adoptPlot(model: Model, index: number): PlotInfo
	local pedestals: { BasePart } = {}
	for _, ped in (model:WaitForChild("Pedestals") :: Folder):GetChildren() do
		local slot = ped:GetAttribute("Slot")
		if ped:IsA("BasePart") and type(slot) == "number" then
			pedestals[slot] = ped
		end
	end
	local base = model:WaitForChild("Base") :: BasePart
	return {
		index = index,
		model = model,
		cframe = base.CFrame,
		spawn = model:WaitForChild("Spawn") :: BasePart,
		pedestals = pedestals,
		arch = model:WaitForChild("Arch") :: BasePart,
		padZone = model:WaitForChild("CollectZone") :: BasePart,
		padVisual = model:WaitForChild("CollectPad") :: BasePart,
	}
end

function WorldService.init()
	local existing = workspace:FindFirstChild("World")
	if existing and existing:GetAttribute("SFT_Managed") ~= true then
		-- hand-built world: adopt its plots
		local plotsFolder = existing:WaitForChild("Plots")
		for _, model in plotsFolder:GetChildren() do
			local index = model:GetAttribute("PlotIndex")
			if model:IsA("Model") and type(index) == "number" then
				WorldService.plots[index] = adoptPlot(model, index)
			end
		end
		return
	end
	if existing then
		existing:Destroy()
	end

	local world = Instance.new("Folder")
	world.Name = "World"
	world:SetAttribute("SFT_Managed", true)
	buildMeadow(world)
	buildCodeBoard(world)
	buildMarket(world)

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	for index = 1, PlotConfig.plotsPerServer do
		local plot = buildPlot(index, plotsFolder)
		WorldService.plots[index] = plot
		world:SetAttribute(string.format("PlotSpawn_%02d", index), plot.spawn.CFrame)
	end
	plotsFolder.Parent = world
	local meadowSpawn = Vector3.new(0, 4, 20)
	world:SetAttribute("MeadowSpawn", CFrame.lookAt(meadowSpawn, Vector3.new(0, 4, 0)))
	world.Parent = workspace
end

function WorldService.start() end

--- World position of pedestal `slot`'s top surface.
function WorldService.pedestalTop(plot: PlotInfo, slot: number): CFrame
	local ped = plot.pedestals[slot]
	return ped.CFrame * CFrame.new(0, ped.Size.Y / 2, 0)
end

return WorldService
