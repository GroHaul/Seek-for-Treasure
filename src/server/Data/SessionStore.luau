--!strict
--[[
	SessionStore: session-locked load/save on top of any store with UpdateAsync
	(a real DataStore or MockStore). No Players, no signals: DataService wires it
	to the player lifecycle, and tests drive it directly.

	Rules (GDD §11.3, roblox-datastores):
	- Every call: pcall + backoff retries (Retry), UpdateAsync only.
	- load stamps _lock = {jobId, t} only if the lock is empty, ours, or stale.
	  A live lock from another server -> retry with backoff, then "locked".
	- A schema newer than this code -> "newer": usable read-only, never saved.
	- A failed load returns "error" and the caller must never save that profile.
	- save writes only while the stored lock is ours; release clears it in the
	  same UpdateAsync. Transforms never yield and only set local outcomes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared").Types)
local Retry = require(script.Parent.Parent.Util.Retry)
local Migrations = require(script.Parent.Migrations)
local ProfileTemplate = require(script.Parent.ProfileTemplate)

export type Store = {
	UpdateAsync: (self: any, key: string, transform: (any, any) -> any) -> any,
}

export type Options = {
	jobId: string,
	now: () -> number,
	lockStaleSeconds: number?, -- default 300
	retryDelays: { number }?, -- per-call backoff (default 1, 2, 4, 8, 16)
	lockRetryDelays: { number }?, -- waits while another server holds the lock
}

export type LoadStatus = "ok" | "new" | "locked" | "newer" | "corrupt" | "error"
export type LoadResult = {
	status: LoadStatus,
	profile: Types.Profile?,
	readOnly: boolean,
	lastOnline: number, -- stored lastOnline before this load (0 for new)
	compensation: number,
	err: string?,
}

export type SaveStatus = "saved" | "released" | "lost_lock" | "invalid" | "error"

export type SessionStore = {
	load: (self: SessionStore, key: string) -> LoadResult,
	save: (self: SessionStore, key: string, profile: Types.Profile, release: boolean) -> SaveStatus,
}

local SessionStore = {}

function SessionStore.new(store: Store, options: Options): SessionStore
	local staleAfter = options.lockStaleSeconds or 300
	local lockWaits = options.lockRetryDelays or Retry.DEFAULT_DELAYS
	local jobId = options.jobId

	local self = {} :: SessionStore

	function self.load(_: SessionStore, key: string): LoadResult
		local attempt = 0
		while true do
			attempt += 1
			-- outcome of the latest transform run (UpdateAsync may run it more than once)
			local outcome: LoadStatus = "error"
			local lastOnline = 0
			local compensation = 0
			local readOnlyCopy: Types.Profile? = nil
			local transformError: string? = nil

			local ok, result = Retry.run("load " .. key, function()
				return store:UpdateAsync(key, function(stored: any)
					outcome, lastOnline, compensation, readOnlyCopy, transformError = "error", 0, 0, nil, nil
					local now = options.now()
					if stored == nil then
						local fresh = ProfileTemplate.new()
						fresh._lock = { jobId = jobId, t = now }
						outcome = "new"
						return fresh
					end
					if type(stored) ~= "table" then
						outcome = "corrupt"
						return nil
					end
					if type(stored.schema) == "number" and stored.schema > ProfileTemplate.CURRENT_SCHEMA then
						outcome = "newer"
						readOnlyCopy = Migrations.deepCopy(stored)
						return nil
					end
					local lock = stored._lock
					if type(lock) == "table" and lock.jobId ~= jobId and type(lock.t) == "number" and now - lock.t < staleAfter then
						outcome = "locked"
						return nil
					end
					local prepOk, prepared, comp = pcall(Migrations.prepare, stored)
					if not prepOk then
						outcome = "corrupt"
						transformError = tostring(prepared)
						return nil
					end
					lastOnline = if type(stored.lastOnline) == "number" then stored.lastOnline else 0
					compensation = comp
					prepared._lock = { jobId = jobId, t = now }
					outcome = "ok"
					return prepared
				end)
			end, options.retryDelays)

			if not ok then
				return {
					status = "error",
					profile = nil,
					readOnly = false,
					lastOnline = 0,
					compensation = 0,
					err = tostring(result),
				}
			end
			if outcome == "ok" or outcome == "new" then
				if type(result) ~= "table" then
					return {
						status = "error",
						profile = nil,
						readOnly = false,
						lastOnline = 0,
						compensation = 0,
						err = "UpdateAsync returned no value",
					}
				end
				return {
					status = outcome,
					profile = result,
					readOnly = false,
					lastOnline = lastOnline,
					compensation = compensation,
				}
			end
			if outcome == "newer" then
				local profile = readOnlyCopy :: any
				return {
					status = "newer",
					profile = profile,
					readOnly = true,
					lastOnline = 0,
					compensation = 0,
				}
			end
			if outcome == "locked" then
				local waitFor = lockWaits[attempt]
				if waitFor == nil then
					return {
						status = "locked",
						profile = nil,
						readOnly = false,
						lastOnline = 0,
						compensation = 0,
					}
				end
				if waitFor > 0 then
					task.wait(waitFor)
				end
				continue
			end
			return {
				status = outcome,
				profile = nil,
				readOnly = false,
				lastOnline = 0,
				compensation = 0,
				err = transformError,
			}
		end
	end

	function self.save(_: SessionStore, key: string, profile: Types.Profile, release: boolean): SaveStatus
		if not Migrations.isSerializable(profile) then
			warn(`[SessionStore] refusing to save {key}: profile has NaN/inf or unsupported values`)
			return "invalid"
		end
		local snapshot = Migrations.deepCopy(profile)
		local now = options.now()
		snapshot._lock = if release then nil else { jobId = jobId, t = now }

		local outcome: SaveStatus = "error"
		local ok = Retry.run("save " .. key, function()
			return store:UpdateAsync(key, function(stored: any)
				outcome = "error"
				local lock = if type(stored) == "table" then stored._lock else nil
				if type(lock) ~= "table" or lock.jobId ~= jobId then
					outcome = "lost_lock"
					return nil
				end
				outcome = if release then "released" else "saved"
				return snapshot
			end)
		end, options.retryDelays)

		if not ok then
			return "error"
		end
		return outcome
	end

	return self
end

return table.freeze(SessionStore)
