--!strict
--[[
	Step 2 tests: SessionStore on a MockStore with injected failures, two fake
	servers (job A and job B) and a controllable clock. No waits (delays = 0).
	Usage: require(game.ServerStorage.SFT_Tests["SessionStore.spec"])()
]]

local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

return function(): string
	local Data = ServerScriptService:WaitForChild("Server"):WaitForChild("Data")
	local SessionStore = require(Data:WaitForChild("SessionStore") :: ModuleScript) :: any
	local MockStore = require(Data:WaitForChild("MockStore") :: ModuleScript) :: any

	local out: { string } = {}
	local failures, checks = 0, 0
	local function check(label: string, cond: boolean)
		checks += 1
		if cond then
			table.insert(out, "ok   " .. label)
		else
			failures += 1
			table.insert(out, "FAIL " .. label)
		end
	end

	local clock = 1_800_000_000
	local function now(): number
		return clock
	end
	local zero = { 0, 0, 0, 0, 0 }
	local store = MockStore.new()
	local A = SessionStore.new(store, { jobId = "A", now = now, retryDelays = zero, lockRetryDelays = { 0, 0 } })
	local B = SessionStore.new(store, { jobId = "B", now = now, retryDelays = zero, lockRetryDelays = { 0, 0 } })
	local KEY = "u_1"
	local function raw(key: string?): any
		local s = store:rawGet(key or KEY)
		return if s then HttpService:JSONDecode(s) else nil
	end

	-- new profile + lock
	local r1 = A:load(KEY)
	check("new player -> status new", r1.status == "new")
	check("new profile is schema 2 with 6 slots", r1.profile.schema == 2 and r1.profile.plot.slots == 6)
	check("lock stamped for job A", raw()._lock.jobId == "A" and raw()._lock.t == clock)

	-- save keeps lock, persists data
	r1.profile.cash = 1234
	clock += 90
	check("autosave -> saved", A:save(KEY, r1.profile, false) == "saved")
	check("cash persisted", raw().cash == 1234)
	check("autosave refreshed the lock time", raw()._lock.t == clock)

	-- another server can't load a live lock, and doesn't change the data
	local before = store:rawGet(KEY)
	local r2 = B:load(KEY)
	check("job B blocked by A's live lock -> locked", r2.status == "locked" and r2.profile == nil)
	check("blocked load left stored data unchanged", store:rawGet(KEY) == before)

	-- release then B takes over
	check("leave -> released", A:save(KEY, r1.profile, true) == "released")
	check("release cleared the lock", raw()._lock == nil)
	local r3 = B:load(KEY)
	check("job B loads after release", r3.status == "ok" and r3.profile.cash == 1234 and raw()._lock.jobId == "B")

	-- A must not write once B owns the profile
	r1.profile.cash = 999999
	before = store:rawGet(KEY)
	check("job A save after B took over -> lost_lock", A:save(KEY, r1.profile, false) == "lost_lock")
	check("lost_lock save left data unchanged", store:rawGet(KEY) == before)

	-- stale lock (crashed server) is taken over
	store:rawSet("u_2", { schema = 1, cash = 50, _lock = { jobId = "dead", t = clock - 301 } })
	local r4 = A:load("u_2")
	check("stale lock (301 s) is taken over", r4.status == "ok" and raw("u_2")._lock.jobId == "A")
	store:rawSet("u_3", { schema = 1, cash = 50, _lock = { jobId = "live", t = clock - 200 } })
	check("fresh lock (200 s) is respected", A:load("u_3").status == "locked")

	-- forced load failure: retries exhausted -> error, nothing written
	before = store:rawGet(KEY)
	local writes = store.writes
	store:setFailAlways(true)
	local r5 = B:load(KEY)
	store:setFailAlways(false)
	check("forced load failure -> status error, no profile", r5.status == "error" and r5.profile == nil)
	check("forced load failure left stored data unchanged", store:rawGet(KEY) == before and store.writes == writes)

	-- transient failures are retried
	store:failNext(3)
	local r6 = B:load(KEY)
	check("3 transient failures then success -> ok", r6.status == "ok")

	-- newer schema -> read-only, not overwritten
	store:rawSet("u_4", { schema = 99, cash = 7 })
	before = store:rawGet("u_4")
	local r7 = A:load("u_4")
	check("newer schema -> read-only profile", r7.status == "newer" and r7.readOnly == true and r7.profile.cash == 7)
	check("save on a read-only (unlocked) profile is refused", A:save("u_4", r7.profile, true) == "lost_lock")
	check("newer-schema data unchanged", store:rawGet("u_4") == before)

	-- corrupt value
	store:rawSet("u_5", "not a table")
	before = store:rawGet("u_5")
	check("corrupt value -> corrupt", A:load("u_5").status == "corrupt")
	check("corrupt value unchanged", store:rawGet("u_5") == before)

	-- NaN is never written
	local r8 = A:load("u_6")
	r8.profile.cash = 0 / 0
	check("NaN cash -> save refused (invalid)", A:save("u_6", r8.profile, false) == "invalid")
	check("stored cash still 0 after NaN attempt", raw("u_6").cash == 0)

	-- migrate/reconcile/sanitize on load
	store:rawSet("u_7", {
		schema = 1,
		cash = 10,
		foo = "old field",
		inventory = {
			t1 = {
				id = "pets_ember_fox",
				segment = "x",
				rarity = 1,
				mutation = { "golden" },
				level = 1,
				t = 1,
			},
			t2 = {
				id = "removed_thing",
				segment = "pets",
				rarity = 5,
				mutation = {},
				level = 1,
				t = 1,
			},
		},
		plot = { slots = 6, layout = { ["1"] = "t1", ["2"] = "t2", ["9"] = "t1" } },
		lastOnline = clock - 3600,
	})
	local r9 = A:load("u_7")
	local p = r9.profile
	check("reconcile filled missing settings", p.settings ~= nil and p.settings.reduceShake == false)
	check("schema 1 -> 2 migration", p.schema == 2)
	check(
		"schema 2 fields added (diamonds, upgrades, potion bag/stock, diamond potion)",
		p.diamonds == 0 and next(p.upgrades) == nil and next(p.potionBag) == nil and p.potionStock.cycle == 0 and p.potions.diamond == 0
	)
	check("unknown key moved to _legacy", p.foo == nil and p._legacy and p._legacy.foo == "old field")
	check("Config wins for rarity/segment", p.inventory.t1.rarity == 4 and p.inventory.t1.segment == "pets")
	check("unknown treasure -> 60 s of income (Legendary 200/s = 12,000)", p.inventory.t2 == nil and p.cash == 10 + 12000)
	check("broken layout refs dropped", p.plot.layout["1"] == "t1" and p.plot.layout["2"] == nil and p.plot.layout["9"] == nil)
	check("lastOnline reported for offline earnings", r9.lastOnline == clock - 3600)

	table.insert(out, 1, string.format("SessionStore.spec: %d/%d checks passed", checks - failures, checks))
	return table.concat(out, "\n")
end
