--!strict
--[[
	DeepFreeze: recursively table.freeze a Config table so no system can mutate
	shared game data at runtime. Returns the same table for convenient chaining.
]]

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value :: any) then
		for _, child in value :: any do
			deepFreeze(child)
		end
		table.freeze(value :: any)
	end
	return value
end

return deepFreeze
