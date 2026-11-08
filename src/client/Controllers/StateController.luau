--!strict
--[[
	StateController: the client's read-only copy of its own profile, built from
	State_Snapshot and State_Delta. Controllers read State.profile / State.derived
	and subscribe with State.watch({ "cash", "plot" }, fn). The client never
	writes game state; it only displays it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Remotes = require(script.Parent.Parent.Remotes)

local State = {
	profile = {} :: any,
	derived = {} :: { [string]: any },
	loaded = false,
	-- fires with the top-level key that changed ("*" for a full snapshot)
	changed = Signal.new() :: Signal.Signal<string>,
}

--- Calls fn() now (if loaded) and whenever any of `keys` (or a snapshot) changes.
function State.watch(keys: { string }, fn: () -> ()): Signal.Connection
	local wanted: { [string]: boolean } = { ["*"] = true }
	for _, key in keys do
		wanted[key] = true
	end
	if State.loaded then
		task.spawn(fn)
	end
	return State.changed:Connect(function(key: string)
		if wanted[key] then
			fn()
		end
	end)
end

function State.init()
	Remotes.on(Net.State_Snapshot, function(payload: any)
		if type(payload) ~= "table" or type(payload.profile) ~= "table" then
			return
		end
		State.profile = payload.profile
		State.derived = if type(payload.derived) == "table" then payload.derived else {}
		State.loaded = true
		State.changed:Fire("*")
	end)
	Remotes.on(Net.State_Delta, function(payload: any)
		if type(payload) ~= "table" or not State.loaded then
			return
		end
		if type(payload.set) == "table" then
			for key, value in payload.set do
				State.profile[key] = value
				State.changed:Fire(key)
			end
		end
		if type(payload.inv) == "table" then
			local inventory = State.profile.inventory
			for uid, entry in payload.inv do
				inventory[uid] = if entry == false then nil else entry
			end
			State.changed:Fire("inventory")
		end
		if type(payload.derived) == "table" then
			for key, value in payload.derived do
				State.derived[key] = value
			end
			State.changed:Fire("derived")
		end
	end)
end

function State.start() end

return State
