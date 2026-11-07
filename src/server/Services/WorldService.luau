--!strict
--[[
	WorldService: builds Workspace.World at server start (placeholder geometry in
	the Sunny Toybox palette until the ForgeGUI models exist).

	Layout (studs): Pawprint Meadow search field is a 60 x 60 square at the
	origin. Four plots face it from the north and four from the south; each
	plot's front edge is 30 studs from the meadow edge (GDD §1.2).

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

local WorldService = {
	plots = {} :: { PlotInfo },
	PALETTE = PALETTE,
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
	label(padVisual, "Collect $0", UDim2.fromScale(10, 2.5), Vector3.new(0, 4, 0), 80)
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

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	for index = 1, PlotConfig.plotsPerServer do
		WorldService.plots[index] = buildPlot(index, plotsFolder)
	end
	plotsFolder.Parent = world
	world.Parent = workspace
end

function WorldService.start() end

--- World position of pedestal `slot`'s top surface.
function WorldService.pedestalTop(plot: PlotInfo, slot: number): CFrame
	local ped = plot.pedestals[slot]
	return ped.CFrame * CFrame.new(0, ped.Size.Y / 2, 0)
end

return WorldService
