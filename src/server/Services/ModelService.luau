--!strict
--[[
	ModelService: treasure models (GDD §13.3).

	1. Blender models (tools/blender/build_treasures.py -> assets/models/pets_treasures.glb),
	   imported once in Studio into ServerStorage.TreasureModels and saved with the
	   place. Each is a MeshPart named like the treasure's `model` field
	   ("DustBunny"); any nesting under that folder is fine. These come first, so the
	   whole collection shares one style.
	2. Otherwise the ForgeGUI upload in `modelAssetId`, loaded with
	   InsertService:LoadAsset (the place's creator owns the assets).
	3. Otherwise the placeholder ball.

	Only the single textured MeshPart is kept, as an anchored, non-colliding
	template named "Body". `ready` fires once per template so plots can rebuild.
]]

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Signal = require(Shared.Util.Signal)

local Retry = require(script.Parent.Parent.Util.Retry)

local LOAD_DELAYS = { 1, 2, 4 }
local TEMPLATE_FOLDER = "TreasureModels"

local ModelService = {
	ready = Signal.new() :: Signal.Signal<string>,
}

local templates: { [string]: MeshPart } = {}

--- The loaded template for a treasure (do not parent it; clone it), or nil.
function ModelService.template(treasureId: string): MeshPart?
	return templates[treasureId]
end

local function adopt(treasureId: string, mesh: MeshPart)
	mesh.Name = "Body"
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.Massless = true
	-- RenderFidelity is plugin-only at runtime; imported meshes default to Automatic (distance LOD)
	templates[treasureId] = mesh
	ModelService.ready:Fire(treasureId)
end

--- The imported Blender MeshPart for a model name, if the place has one.
local function importedMesh(modelName: string): MeshPart?
	local folder = ServerStorage:FindFirstChild(TEMPLATE_FOLDER)
	local found = if folder then folder:FindFirstChild(modelName, true) else nil
	if found == nil then
		return nil
	end
	if found:IsA("MeshPart") then
		return found
	end
	return found:FindFirstChildWhichIsA("MeshPart", true)
end

local function load(treasureId: string, assetId: number)
	local ok, result = Retry.run("model " .. treasureId, function()
		return InsertService:LoadAsset(assetId)
	end, LOAD_DELAYS)
	if not ok then
		warn(`[ModelService] {treasureId} ({assetId}) could not be loaded; keeping the placeholder`)
		return
	end
	local container = result :: Instance
	local mesh = container:FindFirstChildWhichIsA("MeshPart", true)
	if mesh == nil then
		warn(`[ModelService] {treasureId} ({assetId}) has no MeshPart; keeping the placeholder`)
		container:Destroy()
		return
	end
	mesh.Parent = nil
	container:Destroy()
	adopt(treasureId, mesh)
end

function ModelService.init() end

function ModelService.start()
	for id, treasure in Catalog.treasureById do
		local imported = importedMesh(treasure.model)
		if imported then
			adopt(id, imported:Clone())
		elseif treasure.modelAssetId then
			task.spawn(load, id, treasure.modelAssetId)
		end
	end
end

return ModelService
