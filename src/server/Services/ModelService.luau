--!strict
--[[
	ModelService: treasure models uploaded from ForgeGUI (GDD §13.3).

	Every treasure with a `modelAssetId` is loaded once at startup with
	InsertService:LoadAsset (the place's creator owns the assets). A ForgeGUI
	upload is one textured MeshPart (with a SurfaceAppearance) nested in a few
	Models, so only that MeshPart is kept, as an anchored, non-colliding template
	named "Body". Treasures without a model, or whose load failed, keep the
	placeholder ball. `ready` fires once per loaded model so plots can rebuild.
]]

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Signal = require(Shared.Util.Signal)

local Retry = require(script.Parent.Parent.Util.Retry)

local LOAD_DELAYS = { 1, 2, 4 }

local ModelService = {
	ready = Signal.new() :: Signal.Signal<string>,
}

local templates: { [string]: MeshPart } = {}

--- The loaded template for a treasure (do not parent it; clone it), or nil.
function ModelService.template(treasureId: string): MeshPart?
	return templates[treasureId]
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
	mesh.Name = "Body"
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.Massless = true
	-- RenderFidelity is plugin-only at runtime; ForgeGUI uploads already use Automatic (distance LOD)
	templates[treasureId] = mesh
	ModelService.ready:Fire(treasureId)
end

function ModelService.init() end

function ModelService.start()
	for id, treasure in Catalog.treasureById do
		local assetId = treasure.modelAssetId
		if assetId then
			task.spawn(load, id, assetId)
		end
	end
end

return ModelService
