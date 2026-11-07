--!strict
--[[
	ZoneService: server-side position checks at 5 Hz (GDD §1.1, §6).

	Zones are invisible box parts tagged in CollectionService:
	  SFT_SearchZone  attribute SegmentId (string)  -> where auto-search runs
	  SFT_CollectPad  attribute PlotIndex (number)  -> where vault becomes cash
	A player is "in" a zone when their living character's HumanoidRootPart is
	inside the box. The client never reports positions or zones.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared").Util.Signal)

local TICK_SECONDS = 0.2
local SEARCH_TAG = "SFT_SearchZone"
local PAD_TAG = "SFT_CollectPad"

type PlayerZones = { segmentId: string?, padPlot: number? }

local ZoneService = {
	SEARCH_TAG = SEARCH_TAG,
	PAD_TAG = PAD_TAG,
	searchZoneChanged = Signal.new() :: Signal.Signal<Player, string?>,
	padChanged = Signal.new() :: Signal.Signal<Player, number?>,
}

local current: { [Player]: PlayerZones } = {}

local function inside(part: BasePart, position: Vector3): boolean
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size * 0.5
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function tick()
	local zones = CollectionService:GetTagged(SEARCH_TAG)
	local pads = CollectionService:GetTagged(PAD_TAG)
	for _, player in Players:GetPlayers() do
		local state = current[player]
		if state == nil then
			state = { segmentId = nil, padPlot = nil }
			current[player] = state
		end
		local segmentId: string? = nil
		local padPlot: number? = nil
		local root = rootOf(player)
		if root then
			local pos = root.Position
			for _, zone in zones do
				if zone:IsA("BasePart") and inside(zone, pos) then
					local id = zone:GetAttribute("SegmentId")
					if type(id) == "string" then
						segmentId = id
						break
					end
				end
			end
			for _, pad in pads do
				if pad:IsA("BasePart") and inside(pad, pos) then
					local index = pad:GetAttribute("PlotIndex")
					if type(index) == "number" then
						padPlot = index
						break
					end
				end
			end
		end
		if segmentId ~= state.segmentId then
			state.segmentId = segmentId
			ZoneService.searchZoneChanged:Fire(player, segmentId)
		end
		if padPlot ~= state.padPlot then
			state.padPlot = padPlot
			ZoneService.padChanged:Fire(player, padPlot)
		end
	end
end

--- Segment id of the search zone the player stands in, or nil.
function ZoneService.getSearchSegment(player: Player): string?
	local state = current[player]
	return if state then state.segmentId else nil
end

--- Plot index of the collect pad the player stands on, or nil.
function ZoneService.getPadPlot(player: Player): number?
	local state = current[player]
	return if state then state.padPlot else nil
end

--- Exposed for tests: run one check immediately.
ZoneService.tickNow = tick

function ZoneService.init() end

function ZoneService.start()
	Players.PlayerRemoving:Connect(function(player)
		current[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			local ok, err = pcall(tick :: any)
			if not ok then
				warn("[ZoneService] tick error: " .. tostring(err))
			end
		end
	end)
end

return ZoneService
