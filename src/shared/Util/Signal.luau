--!strict
--[[
	Signal: a tiny in-process event (no BindableEvent, no Instance cost).
	Handlers run in their own thread via task.spawn, so one failing handler
	can't break the others or the code that fired the signal.
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local handlers: { [Connection]: (T...) -> () } = {}

	local self = {} :: Signal<T...>

	function self.Connect(_: Signal<T...>, handler: (T...) -> ()): Connection
		local conn = { Connected = true } :: Connection
		function conn.Disconnect(c: Connection)
			c.Connected = false
			handlers[c] = nil
		end
		handlers[conn] = handler
		return conn
	end

	function self.Fire(_: Signal<T...>, ...: T...)
		for _, handler in handlers do
			task.spawn(handler, ...)
		end
	end

	function self.DisconnectAll(_: Signal<T...>)
		for conn in handlers do
			conn.Connected = false
		end
		table.clear(handlers)
	end

	return self
end

return Signal
