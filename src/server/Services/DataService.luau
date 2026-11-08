--!strict
--[[
	DataService: player profile lifecycle (GDD §11.3).

	join -> SessionStore:load (locked) -> in-memory profile (the only source of truth)
	     -> autosave every 90 s, staggered by join time (refreshes lock + lastOnline)
	leave -> releasing signal -> final save + lock release in one UpdateAsync
	BindToClose -> release every player in parallel, wait up to 25 s

	A profile that failed to load is never saved; the player is kicked and the
	stored data is untouched. A "newer schema" profile is read-only.

	Store: DataStore "SFT_Profiles_v1". In Studio without API access (or with
	ServerStorage attribute SFT_UseMockStore = true) an in-memory MockStore is
	used instead, and that's printed loudly. Live servers always use the real store.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)

local Data = script.Parent.Parent.Data
local SessionStore = require(Data.SessionStore)
local MockStore = require(Data.MockStore)

local STORE_NAME = "SFT_Profiles_v1"
local AUTOSAVE_SECONDS = 90
local SHUTDOWN_WAIT_SECONDS = 25

export type LoadInfo = {
	isNew: boolean,
	lastOnline: number,
	compensation: number,
	readOnly: boolean,
}

type Session = {
	player: Player,
	key: string,
	profile: Types.Profile,
	readOnly: boolean,
	lastSave: number,
	playtimeMark: number,
	saving: boolean,
	released: boolean,
	releaseStarted: boolean,
}

local DataService = {
	loaded = Signal.new() :: Signal.Signal<Player, Types.Profile, LoadInfo>,
	-- fired (handlers run synchronously until they yield) just before the final save
	releasing = Signal.new() :: Signal.Signal<Player, Types.Profile>,
	storeKind = "none",
}

local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}
local sessionStore: SessionStore.SessionStore
local mockStore: MockStore.MockStore? = nil
local jobId = if RunService:IsStudio() then "studio-" .. HttpService:GenerateGUID(false) else game.JobId

local function keyFor(userId: number): string
	return "u_" .. tostring(userId)
end

local function chooseStore(): SessionStore.Store
	if not RunService:IsStudio() then
		DataService.storeKind = "datastore"
		return DataStoreService:GetDataStore(STORE_NAME) :: any
	end
	if ServerStorage:GetAttribute("SFT_UseMockStore") == true then
		DataService.storeKind = "mock"
		warn("[DataService] Studio: SFT_UseMockStore is set; using the in-memory MockStore (nothing persists).")
		mockStore = MockStore.new()
		return mockStore :: any
	end
	local ok, store = pcall(function()
		local ds = DataStoreService:GetDataStore(STORE_NAME)
		ds:GetAsync("__probe")
		return ds
	end)
	if ok then
		DataService.storeKind = "datastore"
		return store :: any
	end
	DataService.storeKind = "mock"
	warn(`[DataService] Studio has no DataStore access ({store}); using the in-memory MockStore. Nothing persists between playtests.`)
	mockStore = MockStore.new()
	return mockStore :: any
end

--- The loaded, writable-or-read-only profile, or nil while loading / after leaving.
function DataService.getProfile(player: Player): Types.Profile?
	local session = sessions[player]
	return if session then session.profile else nil
end

function DataService.isReadOnly(player: Player): boolean
	local session = sessions[player]
	return session == nil or session.readOnly
end

function DataService.waitForProfile(player: Player, timeoutSeconds: number?): Types.Profile?
	local deadline = os.clock() + (timeoutSeconds or 60)
	while player.Parent and os.clock() < deadline do
		local session = sessions[player]
		if session then
			return session.profile
		end
		task.wait(0.1)
	end
	return nil
end

local function save(session: Session, release: boolean): string
	while session.saving do
		task.wait()
	end
	if session.released then
		return "released"
	end
	if session.readOnly then
		return "readonly"
	end
	session.saving = true
	local now = os.time()
	session.profile.lastOnline = now
	session.profile.stats.playtime += os.clock() - session.playtimeMark
	session.playtimeMark = os.clock()
	local status = sessionStore:save(session.key, session.profile, release)
	session.lastSave = os.clock()
	if release and (status == "released" or status == "lost_lock") then
		session.released = true
	end
	session.saving = false
	if status == "lost_lock" then
		-- another server took the profile over (our lock went stale). Stop writing.
		session.readOnly = true
		warn(`[DataService] lost the session lock for {session.key}; further saves are disabled`)
	elseif status ~= "saved" and status ~= "released" then
		warn(`[DataService] save {session.key} -> {status}`)
	end
	return status
end

local function release(player: Player)
	local session = sessions[player]
	if session == nil then
		return
	end
	if session.releaseStarted then
		-- PlayerRemoving and BindToClose can both get here; wait for the first one
		while sessions[player] == session do
			task.wait(0.1)
		end
		return
	end
	session.releaseStarted = true
	DataService.releasing:Fire(player, session.profile)
	save(session, true)
	sessions[player] = nil
end

local function onPlayerAdded(player: Player)
	if loading[player] or sessions[player] then
		return
	end
	loading[player] = true
	local key = keyFor(player.UserId)
	local result: SessionStore.LoadResult
	if ServerStorage:GetAttribute("SFT_ForceLoadFailure") == true and RunService:IsStudio() then
		result = {
			status = "error",
			profile = nil,
			readOnly = false,
			lastOnline = 0,
			compensation = 0,
			err = "forced (SFT_ForceLoadFailure)",
		}
	else
		result = sessionStore:load(key)
	end
	loading[player] = nil

	if result.status == "locked" then
		player:Kick("Your data is still saving in another server. Please rejoin in a moment.")
		return
	elseif result.status ~= "ok" and result.status ~= "new" and result.status ~= "newer" then
		warn(`[DataService] load {key} failed: {result.status} {result.err or ""}`)
		player:Kick("We couldn't load your data. Please rejoin. (Your saved progress is safe.)")
		return
	end

	local profile = result.profile :: Types.Profile
	local session: Session = {
		player = player,
		key = key,
		profile = profile,
		readOnly = result.readOnly,
		lastSave = os.clock(),
		playtimeMark = os.clock(),
		saving = false,
		released = false,
		releaseStarted = false,
	}
	sessions[player] = session

	if player.Parent == nil then
		-- left while loading: give the lock back right away
		release(player)
		return
	end

	DataService.loaded:Fire(player, profile, {
		isNew = result.status == "new",
		lastOnline = result.lastOnline,
		compensation = result.compensation,
		readOnly = result.readOnly,
	})
end

local function autosaveLoop()
	while true do
		task.wait(1)
		local now = os.clock()
		for _, session in sessions do
			if not session.saving and not session.readOnly and now - session.lastSave >= AUTOSAVE_SECONDS then
				task.spawn(save, session, false)
			end
		end
	end
end

local function onClose()
	local pending = 0
	for player in sessions do
		pending += 1
		task.spawn(function()
			release(player)
			pending -= 1
		end)
	end
	local deadline = os.clock() + SHUTDOWN_WAIT_SECONDS
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

function DataService.init()
	sessionStore = SessionStore.new(chooseStore(), {
		jobId = jobId,
		now = os.time,
	})
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		if sessions[player] then
			release(player)
		end
		-- if still loading, onPlayerAdded releases when the load returns
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	game:BindToClose(onClose)
	task.spawn(autosaveLoop)
end

--- Studio test only: release the player's profile (final save + unlock), move
--- the stored lastOnline back by `offlineSeconds`, then load it again as if the
--- player had rejoined. Works only with the MockStore.
function DataService.testRejoin(player: Player, offlineSeconds: number): string
	if not RunService:IsStudio() or mockStore == nil then
		return "only in Studio with the MockStore"
	end
	release(player)
	local raw = mockStore:rawGet(keyFor(player.UserId))
	if raw == nil then
		return "nothing stored"
	end
	local stored = HttpService:JSONDecode(raw)
	stored.lastOnline -= offlineSeconds
	mockStore:rawSet(keyFor(player.UserId), stored)
	onPlayerAdded(player)
	return if sessions[player] then "rejoined" else "load failed"
end

--- Studio test only: the MockStore in use (nil with a real DataStore or live).
function DataService.testMockStore(): MockStore.MockStore?
	return if RunService:IsStudio() then mockStore else nil
end

--- Dev/test: save now (no release). Returns the save status.
function DataService.saveNow(player: Player): string
	local session = sessions[player]
	if session == nil then
		return "no_session"
	end
	return save(session, false)
end

return DataService
