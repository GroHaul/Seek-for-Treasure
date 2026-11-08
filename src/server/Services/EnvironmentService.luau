--!strict
--[[
	EnvironmentService: terrain and lighting in the Sunny Toybox look (GDD §13.1).

	Built at server start in code, so it lives in the repo like the rest of the
	world (Rojo can't sync terrain). Nothing here touches gameplay parts.

	Terrain (skipped if the place already has hand-made terrain):
	  - grass ground over the whole area, its surface 0.25 studs above the
	    template Baseplate so the Baseplate never shows through
	  - sandy paths: each plot's front -> a cross path -> the meadow's fence gaps,
	    plus a small plaza around the code board; sand under every plot so the
	    terrain's grass blades don't grow through plot floors and pedestals
	  - a pond east of the meadow (sand rim, water)
	  - a ring of rolling grass hills with a few rocks framing the play area

	Lighting: warm afternoon sun, light atmosphere, low bloom. Existing effects
	in Lighting are tuned (not deleted); missing ones are created.
	Lighting.Technology can't be set from a script; set it to Future in Studio.
]]

local Lighting = game:GetService("Lighting")

local WorldService = require(script.Parent.WorldService)

local GROUND_TOP = 0.25 -- Baseplate top is 0
local GROUND_DEPTH = 12
local GROUND_HALF = 420
local PATH_WIDTH = 8

local MEADOW_HALF = 30
local PLOT_FRONT = 60 -- |z| of the plots' front edges
local CROSS_PATH_Z = 45
local PLOT_COLUMNS = { -75, -25, 25, 75 }
local POND_CENTER = Vector3.new(80, 0, 0)
local POND_RADIUS = 16

local COLORS = {
	grass = Color3.fromHex("#6CCB4F"),
	leafyGrass = Color3.fromHex("#5BB845"),
	sand = Color3.fromHex("#E8D3A8"),
	rock = Color3.fromHex("#B9BDC7"),
	water = Color3.fromHex("#49B6FF"),
}

local EnvironmentService = {}

local function terrainIsEmpty(terrain: Terrain): boolean
	local ok, cells = pcall(function()
		return terrain:CountCells()
	end)
	if not ok then
		warn(`[EnvironmentService] couldn't count terrain cells ({cells}); building terrain anyway`)
		return true
	end
	return cells == 0
end

--- Fills a flat block whose top sits on the ground surface.
local function flat(terrain: Terrain, center: Vector3, sizeX: number, sizeZ: number, depth: number, material: Enum.Material)
	local cframe = CFrame.new(center.X, GROUND_TOP - depth / 2, center.Z)
	terrain:FillBlock(cframe, Vector3.new(sizeX, depth, sizeZ), material)
end

local function buildPaths(terrain: Terrain)
	local sand = Enum.Material.Sand
	for _, side in { -1, 1 } do
		-- from each plot's front edge to the cross path
		for _, x in PLOT_COLUMNS do
			local z = side * (CROSS_PATH_Z + PLOT_FRONT) / 2
			flat(terrain, Vector3.new(x, 0, z), PATH_WIDTH, PLOT_FRONT - CROSS_PATH_Z + PATH_WIDTH / 2, 4, sand)
		end
		-- the cross path in front of the four plots
		flat(terrain, Vector3.new(0, 0, side * CROSS_PATH_Z), 150 + PATH_WIDTH, PATH_WIDTH, 4, sand)
		-- from the cross path to the meadow's fence gap
		flat(terrain, Vector3.new(0, 0, side * (CROSS_PATH_Z + MEADOW_HALF) / 2), PATH_WIDTH, CROSS_PATH_Z - MEADOW_HALF, 4, sand)
	end
	-- a small sandy plaza around the code board outside the east fence gap
	flat(terrain, Vector3.new(MEADOW_HALF + 12, 0, 0), 24, 24, 4, sand)
end

-- Terrain grass blades (Decoration) grow straight through parts, so the ground
-- under every plot is sand: plots stay visible and get a sandy rim.
local PLOT_RIM = 4

local function clearUnderPlots(terrain: Terrain)
	-- the meadow's fence, bushes and fountain need the same treatment; LeafyGrass
	-- stays green but grows no blades
	local meadow = (MEADOW_HALF + 3) * 2
	flat(terrain, Vector3.zero, meadow, meadow, 4, Enum.Material.LeafyGrass)
	for _, plot in WorldService.plots do
		local base = plot.model:FindFirstChild("Base")
		if base and base:IsA("BasePart") then
			local size = base.Size
			terrain:FillBlock(
				CFrame.new(base.Position.X, GROUND_TOP - 2, base.Position.Z) * base.CFrame.Rotation,
				Vector3.new(size.X + PLOT_RIM * 2, 4, size.Z + PLOT_RIM * 2),
				Enum.Material.Sand
			)
		end
	end
end

local function buildPond(terrain: Terrain)
	-- FillCylinder's axis is the CFrame's Y axis
	local function cylinder(radius: number, top: number, bottom: number, material: Enum.Material)
		local height = top - bottom
		terrain:FillCylinder(CFrame.new(POND_CENTER.X, bottom + height / 2, POND_CENTER.Z), height, radius, material)
	end
	cylinder(POND_RADIUS + 4, GROUND_TOP, -8, Enum.Material.Sand) -- beach rim
	cylinder(POND_RADIUS, GROUND_TOP, -5, Enum.Material.Air) -- dig
	cylinder(POND_RADIUS, -0.75, -5, Enum.Material.Water)
end

local function buildHills(terrain: Terrain)
	local rng = Random.new(20261108)
	local count = 34
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local radiusX = 215 + rng:NextNumber(-15, 25)
		local radiusZ = 235 + rng:NextNumber(-15, 25)
		local size = rng:NextNumber(34, 60)
		local center = Vector3.new(math.cos(angle) * radiusX, -size * rng:NextNumber(0.35, 0.55), math.sin(angle) * radiusZ)
		terrain:FillBall(center, size, if i % 3 == 0 then Enum.Material.LeafyGrass else Enum.Material.Grass)
		if i % 5 == 0 then
			-- a rocky outcrop on some hills
			local rock = center + Vector3.new(rng:NextNumber(-8, 8), size * 0.55, rng:NextNumber(-8, 8))
			terrain:FillBall(rock, rng:NextNumber(7, 11), Enum.Material.Rock)
		end
	end
	-- a second, taller row behind for depth
	for i = 1, 18 do
		local angle = (i / 18) * math.pi * 2 + 0.17
		local size = rng:NextNumber(60, 90)
		local center = Vector3.new(math.cos(angle) * 300, -size * 0.4, math.sin(angle) * 320)
		terrain:FillBall(center, size, Enum.Material.Grass)
	end
end

local function buildTerrain()
	local terrain = workspace.Terrain
	if not terrainIsEmpty(terrain) then
		return -- hand-made terrain wins
	end
	terrain:SetMaterialColor(Enum.Material.Grass, COLORS.grass)
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, COLORS.leafyGrass)
	terrain:SetMaterialColor(Enum.Material.Sand, COLORS.sand)
	terrain:SetMaterialColor(Enum.Material.Rock, COLORS.rock)
	terrain.WaterColor = COLORS.water
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.4
	terrain.WaterWaveSize = 0.08
	terrain.WaterWaveSpeed = 6

	flat(terrain, Vector3.zero, GROUND_HALF * 2, GROUND_HALF * 2, GROUND_DEPTH, Enum.Material.Grass)
	clearUnderPlots(terrain)
	buildPaths(terrain)
	buildPond(terrain)
	buildHills(terrain)
end

--- The existing instance of `className` under Lighting, or a new one.
local function effect<T>(className: string): T
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing then
		return existing :: any
	end
	local created = Instance.new(className :: any)
	created.Name = "SFT_" .. className
	created.Parent = Lighting
	return created :: any
end

local function buildLighting()
	Lighting.ClockTime = 14.2
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(96, 92, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 146, 160)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 236, 205)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25

	local atmosphere = effect("Atmosphere") :: Atmosphere
	atmosphere.Density = 0.27
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(199, 226, 255)
	atmosphere.Decay = Color3.fromRGB(255, 228, 196)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 1.1

	local bloom = effect("BloomEffect") :: BloomEffect
	bloom.Intensity = 0.35
	bloom.Size = 20
	bloom.Threshold = 1.6

	local sunRays = effect("SunRaysEffect") :: SunRaysEffect
	sunRays.Intensity = 0.06
	sunRays.Spread = 0.6

	local grade = effect("ColorCorrectionEffect") :: ColorCorrectionEffect
	grade.Saturation = 0.12
	grade.Contrast = 0.06
	grade.Brightness = 0.02
	grade.TintColor = Color3.fromRGB(255, 251, 242)

	-- the template's depth of field blurs the plots behind the meadow; keep it subtle
	local focus = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if focus then
		focus.FarIntensity = 0.05
		focus.FocusDistance = 60
		focus.InFocusRadius = 120
		focus.NearIntensity = 0
	end
end

function EnvironmentService.init()
	buildLighting()
	buildTerrain()
end

function EnvironmentService.start() end

return EnvironmentService
