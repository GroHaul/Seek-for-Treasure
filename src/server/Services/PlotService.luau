--!strict
--[[
	PlotService: plots, placement, income, collecting, offline earnings (GDD §6).

	- Claim: on profile load, the lowest free plot; released on leave.
	- Spawn: every character spawns at its owner's plot.
	- Place/Remove/Place Best: validated remotes; new finds auto-fill the lowest
	  empty unlocked slot.
	- Income: vault += plotIncome * dt every second (server-computed);
	  plotIncome = sum(placed income) * rebirthMult * cashPotion * friendMult.
	- Collect: standing on your own Collect pad moves vault -> cash (no remote).
	- Offline: on load, permanent base income * min(elapsed, 2 h) * 50% -> cash.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Catalog = require(Shared.Catalog)
local EconomyMath = require(Shared.EconomyMath)
local Format = require(Shared.Format)
local Signal = require(Shared.Util.Signal)
local Config = Shared.Config
local Economy = require(Config.Economy) :: Types.EconomyConfig
local PlotConfig = require(Config.Plot) :: Types.PlotConfig
local Upgrades = require(Config.Upgrades) :: Types.UpgradesConfig

local DataService = require(script.Parent.DataService)
local RemoteService = require(script.Parent.RemoteService)
local StateService = require(script.Parent.StateService)
local WorldService = require(script.Parent.WorldService)
local ZoneService = require(script.Parent.ZoneService)
local InventoryService = require(script.Parent.InventoryService)
local SocialService = require(script.Parent.SocialService)
local Guard = require(script.Parent.Parent.Util.Guard)

local PEDESTAL_COLORS = {
	stone = Color3.fromHex("#C9CED6"),
	bronze = Color3.fromHex("#C98B52"),
	gold = Color3.fromHex("#FFC93C"),
	crystal = Color3.fromHex("#9FF3FF"),
	cosmic = Color3.fromHex("#7B2FFF"),
}
local PARTICLE_COLORS: { [string]: Color3 } = {
	sparkle_gold = Color3.fromHex("#FFC93C"),
	glint_white = Color3.fromHex("#FFFFFF"),
	smoke_dark = Color3.fromHex("#2A2140"),
	halo_ring = Color3.fromHex("#FFF4DF"),
	flame_orange = Color3.fromHex("#FF8A2B"),
	spark_blue = Color3.fromHex("#49B6FF"),
	star_orbit = Color3.fromHex("#FFF3B0"),
}

local PlotService = {
	collected = Signal.new() :: Signal.Signal<Player, number>,
	placed = Signal.new() :: Signal.Signal<Player, number, string>,
	offlineGranted = Signal.new() :: Signal.Signal<Player, number, number>, -- amount, seconds
}

local plotOwner: { [number]: Player? } = {}
local plotOf: { [Player]: number } = {}

--- Plot index owned by player, or nil.
function PlotService.plotIndex(player: Player): number?
	return plotOf[player]
end

--- Income of placed treasures with permanent multipliers only (rebirth).
function PlotService.basePlotIncome(profile: Types.Profile): number
	local sum = 0
	for _, uid in profile.plot.layout do
		local entry = profile.inventory[uid]
		if entry then
			sum += EconomyMath.treasureIncome(entry)
		end
	end
	return sum * EconomyMath.rebirthCashMult(profile.rebirths)
end

--- Full live income/sec including potions and friend boost.
function PlotService.plotIncome(player: Player, profile: Types.Profile): number
	local boost = EconomyMath.potionMult(profile.potions, "cash", os.time()) * SocialService.friendMult(player)
	return PlotService.basePlotIncome(profile) * boost
end

-- Visuals ---------------------------------------------------------------------

local function rarityColor(order: number): Color3
	return Color3.fromHex(Catalog.rarities[order].color)
end

local function makeLabel(parent: Instance, name: string, size: UDim2, offset: Vector3, maxDistance: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.RichText = true
	text.TextColor3 = Color3.fromHex("#FFF4DF")
	text.TextStrokeColor3 = Color3.fromHex("#1D2340")
	text.TextStrokeTransparency = 0
	text.Parent = gui
	gui.Parent = parent
	return text
end

local function applyMutationVisuals(body: BasePart, mutation: { string })
	for _, id in mutation do
		local m = Catalog.mutationById[id]
		if m == nil then
			continue
		end
		local v = m.visual
		if v.material then
			body.Material = (Enum.Material :: any)[v.material]
		end
		if v.color then
			body.Color = Color3.fromHex(v.color)
		end
		if v.reflectance then
			body.Reflectance = v.reflectance
		end
		if v.transparency then
			body.Transparency = v.transparency
		end
		if v.lightRange then
			local light = Instance.new("PointLight")
			light.Range = v.lightRange
			light.Color = body.Color
			light.Parent = body
		end
		if v.particles then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = v.particles.preset
			emitter.Rate = v.particles.rate
			emitter.Lifetime = NumberRange.new(v.particles.lifetime or 1.2)
			emitter.Speed = NumberRange.new(1, 2)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Size = NumberSequence.new(0.35, 0)
			emitter.LightEmission = 0.6
			emitter.Color = ColorSequence.new(PARTICLE_COLORS[v.particles.preset] or Color3.new(1, 1, 1))
			emitter.Parent = body
		end
		body:SetAttribute("Hue" .. m.family, v.hueCycleSeconds or (if v.highlightHueCycle then 6 else nil))
	end
end

local function mutationText(mutation: { string }): string
	local names = {}
	for _, id in mutation do
		local m = Catalog.mutationById[id]
		if m then
			table.insert(names, m.name)
		end
	end
	return table.concat(names, " ")
end

local function buildTreasure(entry: Types.InventoryEntry, top: CFrame, incomePerSec: number): Model
	local treasure = Catalog.treasureById[entry.id]
	local model = Instance.new("Model")
	model.Name = "Treasure"
	local size = 2.2 + math.min(entry.rarity, 10) * 0.18
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.one * size
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.Material = Enum.Material.SmoothPlastic
	body.Color = rarityColor(entry.rarity)
	body.CFrame = top * CFrame.new(0, size / 2 + 0.2, 0)
	applyMutationVisuals(body, entry.mutation)
	body.Parent = model
	local mut = mutationText(entry.mutation)
	local text = makeLabel(body, "Info", UDim2.fromScale(7, 2.6), Vector3.new(0, size / 2 + 1.6, 0), 60)
	text.Text = string.format(
		'%s\n<font color="%s">%s</font>%s\n<font color="#3DDC84">%s/s</font>',
		treasure.name,
		Catalog.rarities[entry.rarity].color,
		Catalog.rarities[entry.rarity].name,
		if mut ~= "" then " · " .. mut else "",
		Format.cash(incomePerSec)
	)
	model:SetAttribute("TreasureId", entry.id)
	model:SetAttribute("Rarity", entry.rarity)
	model.PrimaryPart = body
	return model
end

local function refreshVisuals(index: number)
	local plot = WorldService.plots[index]
	if plot == nil then
		return
	end
	local owner = plotOwner[index]
	local profile = if owner then DataService.getProfile(owner) else nil
	local slots = if profile then profile.plot.slots else 0
	local rebirthMult = if profile then EconomyMath.rebirthCashMult(profile.rebirths) else 1
	for slot, ped in plot.pedestals do
		local old = ped:FindFirstChild("Treasure")
		if old then
			old:Destroy()
		end
		local lock = ped:FindFirstChild("Lock")
		if lock then
			lock:Destroy()
		end
		ped.Color = PEDESTAL_COLORS.stone
		ped.Transparency = if slot <= slots or profile == nil then 0 else 0.55
		if profile == nil then
			continue
		end
		if slot > slots then
			if slot == slots + 1 and slots < Upgrades.slots.max then
				local text = makeLabel(ped, "Lock", UDim2.fromScale(6, 1.6), Vector3.new(0, 2.5, 0), 50)
				text.Text = "🔒 " .. Format.cash(EconomyMath.slotPrice(slots))
			end
			continue
		end
		local uid = profile.plot.layout[tostring(slot)]
		local entry = if uid then profile.inventory[uid] else nil
		if entry then
			local band = PlotConfig.pedestalByRarity[entry.rarity]
			ped.Color = (PEDESTAL_COLORS :: any)[band] or PEDESTAL_COLORS.stone
			local model = buildTreasure(entry, WorldService.pedestalTop(plot, slot), EconomyMath.treasureIncome(entry) * rebirthMult)
			model.Parent = ped
		end
	end
	local archText = plot.arch:FindFirstChild("Label")
	local archLabel = if archText then archText:FindFirstChild("Text") else nil
	if archLabel and archLabel:IsA("TextLabel") then
		archLabel.Text = if owner then owner.DisplayName .. "'s Plot" else "Free plot"
	end
end
PlotService.refreshVisuals = refreshVisuals

local function updatePadLabel(index: number, vault: number)
	local plot = WorldService.plots[index]
	local gui = plot and plot.padVisual:FindFirstChild("Label")
	local text = gui and gui:FindFirstChild("Text")
	if text and text:IsA("TextLabel") then
		text.Text = "Collect " .. Format.cash(vault)
	end
end

local function pushDerived(player: Player, profile: Types.Profile)
	StateService.setDerived(player, "income", PlotService.plotIncome(player, profile))
	StateService.setDerived(player, "baseIncome", PlotService.basePlotIncome(profile))
	StateService.setDerived(player, "friends", SocialService.friendsInServer(player))
	StateService.setDerived(player, "plotIndex", plotOf[player] or 0)
end

local function layoutChanged(player: Player, profile: Types.Profile)
	StateService.markDirty(player, "plot")
	pushDerived(player, profile)
	local index = plotOf[player]
	if index then
		refreshVisuals(index)
	end
end
PlotService.layoutChanged = layoutChanged

-- Placement -------------------------------------------------------------------

local function lowestEmptySlot(profile: Types.Profile): number?
	for slot = 1, profile.plot.slots do
		if profile.plot.layout[tostring(slot)] == nil then
			return slot
		end
	end
	return nil
end

function PlotService.place(player: Player, profile: Types.Profile, slot: number, uid: string): boolean
	if slot < 1 or slot > profile.plot.slots or profile.inventory[uid] == nil then
		return false
	end
	if InventoryService.placedSlot(profile, uid) ~= nil then
		return false
	end
	profile.plot.layout[tostring(slot)] = uid -- an occupant goes back to the inventory
	layoutChanged(player, profile)
	PlotService.placed:Fire(player, slot, uid)
	return true
end

function PlotService.remove(player: Player, profile: Types.Profile, slot: number): boolean
	local key = tostring(slot)
	if profile.plot.layout[key] == nil then
		return false
	end
	profile.plot.layout[key] = nil
	layoutChanged(player, profile)
	return true
end

--- Fill slots 1..n with the n highest-income treasures (ties: older first).
function PlotService.placeBest(player: Player, profile: Types.Profile)
	local ranked: { { uid: string, income: number, t: number } } = {}
	for uid, entry in profile.inventory do
		table.insert(ranked, { uid = uid, income = EconomyMath.treasureIncome(entry), t = entry.t })
	end
	table.sort(ranked, function(a, b)
		if a.income ~= b.income then
			return a.income > b.income
		end
		if a.t ~= b.t then
			return a.t < b.t
		end
		-- same second: lower uid number first, so the order is deterministic
		return (tonumber(string.sub(a.uid, 2)) or 0) < (tonumber(string.sub(b.uid, 2)) or 0)
	end)
	table.clear(profile.plot.layout)
	for slot = 1, math.min(profile.plot.slots, #ranked) do
		profile.plot.layout[tostring(slot)] = ranked[slot].uid
	end
	layoutChanged(player, profile)
end

--- Drop layout entries above the slot count (used by rebirth).
function PlotService.trimLayout(player: Player, profile: Types.Profile)
	for key in profile.plot.layout do
		local n = tonumber(key)
		if n == nil or n > profile.plot.slots then
			profile.plot.layout[key] = nil
		end
	end
	layoutChanged(player, profile)
end

--- Put the best unplaced treasures into empty unlocked slots (after buying a slot).
function PlotService.fillEmptySlots(player: Player, profile: Types.Profile)
	local placed: { [string]: boolean } = {}
	for _, uid in profile.plot.layout do
		placed[uid] = true
	end
	local unplaced: { { uid: string, income: number } } = {}
	for uid, entry in profile.inventory do
		if not placed[uid] then
			table.insert(unplaced, { uid = uid, income = EconomyMath.treasureIncome(entry) })
		end
	end
	table.sort(unplaced, function(a, b)
		return a.income > b.income
	end)
	local nextBest = 1
	for slot = 1, profile.plot.slots do
		local key = tostring(slot)
		if profile.plot.layout[key] == nil and unplaced[nextBest] then
			profile.plot.layout[key] = unplaced[nextBest].uid
			nextBest += 1
		end
	end
	layoutChanged(player, profile)
end

-- Lifecycle -------------------------------------------------------------------

local function spawnAtPlot(player: Player, character: Model)
	local index = plotOf[player]
	local plot = if index then WorldService.plots[index] else nil
	if plot == nil then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root and character.Parent then
		character:PivotTo(plot.spawn.CFrame * CFrame.new(0, 3, 0))
	end
end

local function claim(player: Player, profile: Types.Profile, lastOnline: number, isNew: boolean)
	for index = 1, PlotConfig.plotsPerServer do
		if plotOwner[index] == nil and WorldService.plots[index] then
			plotOwner[index] = player
			plotOf[player] = index
			WorldService.plots[index].model:SetAttribute("OwnerUserId", player.UserId)
			break
		end
	end
	if plotOf[player] == nil then
		warn(`[PlotService] no free plot for {player.UserId}`)
	end

	-- offline earnings: permanent multipliers only, elapsed clamped to [0, cap]
	if not isNew and lastOnline > 0 then
		local elapsed = os.time() - lastOnline
		local amount = EconomyMath.offlineEarnings(PlotService.basePlotIncome(profile), elapsed)
		if amount > 0 then
			profile.cash += amount
			profile.lifetimeEarned += amount
			StateService.markDirty(player, "cash", "lifetimeEarned")
			local seconds = math.clamp(elapsed, 0, Economy.offlineCapSeconds)
			RemoteService.fire(Net.Notify, player, { kind = "welcome_back", amount = amount, seconds = seconds })
			PlotService.offlineGranted:Fire(player, amount, seconds)
		end
	end

	pushDerived(player, profile)
	local index = plotOf[player]
	if index then
		refreshVisuals(index)
		updatePadLabel(index, profile.vault)
	end
	if player.Character then
		task.spawn(spawnAtPlot, player, player.Character)
	end
end

local function unclaim(player: Player)
	local index = plotOf[player]
	plotOf[player] = nil
	if index then
		plotOwner[index] = nil
		WorldService.plots[index].model:SetAttribute("OwnerUserId", 0)
		refreshVisuals(index)
		updatePadLabel(index, 0)
	end
end

local function collect(player: Player, profile: Types.Profile)
	local amount = math.floor(profile.vault)
	if amount < 1 then
		return
	end
	profile.vault -= amount
	profile.cash += amount
	profile.lifetimeEarned += amount
	StateService.markDirty(player, "cash", "vault", "lifetimeEarned")
	PlotService.collected:Fire(player, amount)
end

local function accrualLoop()
	local last = os.clock()
	while true do
		task.wait(Economy.vaultTickSeconds)
		local now = os.clock()
		local dt = math.min(now - last, 5)
		last = now
		for player, index in plotOf do
			local profile = DataService.getProfile(player)
			if profile == nil or DataService.isReadOnly(player) then
				continue
			end
			local income = PlotService.plotIncome(player, profile)
			if income > 0 then
				profile.vault += income * dt
				StateService.markDirty(player, "vault")
			end
			if ZoneService.getPadPlot(player) == index then
				collect(player, profile)
			end
			pushDerived(player, profile)
			updatePadLabel(index, profile.vault)
		end
	end
end

function PlotService.init() end

function PlotService.start()
	DataService.loaded:Connect(function(player, profile, info)
		claim(player, profile, info.lastOnline, info.isNew)
	end)
	DataService.releasing:Connect(function(player)
		unclaim(player)
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			spawnAtPlot(player, character)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character)
			spawnAtPlot(player, character)
		end)
	end

	InventoryService.added:Connect(function(player, uid)
		local profile = DataService.getProfile(player)
		if profile == nil then
			return
		end
		local slot = lowestEmptySlot(profile)
		if slot then
			PlotService.place(player, profile, slot, uid)
		end
	end)
	InventoryService.removed:Connect(function(player)
		local profile = DataService.getProfile(player)
		if profile then
			pushDerived(player, profile)
		end
	end)
	ZoneService.padChanged:Connect(function(player, padPlot)
		local profile = DataService.getProfile(player)
		if profile and padPlot ~= nil and padPlot == plotOf[player] and not DataService.isReadOnly(player) then
			collect(player, profile)
		end
	end)
	SocialService.friendsChanged:Connect(function(player)
		local profile = DataService.getProfile(player)
		if profile then
			pushDerived(player, profile)
		end
	end)

	local maxSlots = Upgrades.slots.max + Upgrades.slots.passExtra
	RemoteService.on(Net.Plot_Place, 5, 10, function(player, profile, slotArg, uidArg)
		local slot = Guard.int(slotArg, 1, maxSlots)
		local uid = Guard.str(uidArg, 12)
		if slot and uid then
			PlotService.place(player, profile, slot, uid)
		end
	end)
	RemoteService.on(Net.Plot_Remove, 5, 10, function(player, profile, slotArg)
		local slot = Guard.int(slotArg, 1, maxSlots)
		if slot then
			PlotService.remove(player, profile, slot)
		end
	end)
	RemoteService.on(Net.Plot_PlaceBest, 1, 2, function(player, profile)
		PlotService.placeBest(player, profile)
	end)
	RemoteService.on(Net.Inv_Sell, 5, 10, function(player, profile, uidArg)
		local uid = Guard.str(uidArg, 12)
		if uid then
			InventoryService.sell(player, profile, uid)
		end
	end)

	task.spawn(accrualLoop)
end

return PlotService
