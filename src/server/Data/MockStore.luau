--!strict
--[[
	MockStore: in-memory stand-in for a DataStore with the same UpdateAsync shape.
	Values are stored as JSON strings, so every read is a fresh copy and anything
	that wouldn't survive a real DataStore fails here too.

	Used by tests (with failure injection) and in Studio when the place has no
	API access. Never used outside Studio (DataService enforces that).
]]

local HttpService = game:GetService("HttpService")

export type MockStore = {
	UpdateAsync: (self: MockStore, key: string, transform: (any, any) -> any) -> any,
	GetAsync: (self: MockStore, key: string) -> any,
	-- test helpers
	failNext: (self: MockStore, count: number, message: string?) -> (),
	setFailAlways: (self: MockStore, fail: boolean) -> (),
	rawGet: (self: MockStore, key: string) -> string?,
	rawSet: (self: MockStore, key: string, value: any) -> (),
	calls: number,
	writes: number,
}

local MockStore = {}

function MockStore.new(): MockStore
	local data: { [string]: string } = {}
	local pendingFailures = 0
	local failMessage = "MockStore: injected failure"
	local failAlways = false

	local store = { calls = 0, writes = 0 } :: MockStore

	local function maybeFail()
		store.calls += 1
		if failAlways then
			error(failMessage)
		end
		if pendingFailures > 0 then
			pendingFailures -= 1
			error(failMessage)
		end
	end

	function store.UpdateAsync(self: MockStore, key: string, transform: (any, any) -> any): any
		maybeFail()
		local raw = data[key]
		local current = if raw then HttpService:JSONDecode(raw) else nil
		local nextValue = transform(current, nil)
		if nextValue == nil then
			return nil
		end
		local encoded = HttpService:JSONEncode(nextValue)
		data[key] = encoded
		self.writes += 1
		return HttpService:JSONDecode(encoded)
	end

	function store.GetAsync(_: MockStore, key: string): any
		maybeFail()
		local raw = data[key]
		return if raw then HttpService:JSONDecode(raw) else nil
	end

	function store.failNext(_: MockStore, count: number, message: string?)
		pendingFailures = count
		failMessage = message or failMessage
	end

	function store.setFailAlways(_: MockStore, fail: boolean)
		failAlways = fail
	end

	function store.rawGet(_: MockStore, key: string): string?
		return data[key]
	end

	function store.rawSet(_: MockStore, key: string, value: any)
		data[key] = if value == nil then nil else HttpService:JSONEncode(value)
	end

	return store
end

return table.freeze(MockStore)
