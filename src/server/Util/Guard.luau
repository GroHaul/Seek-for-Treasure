--!strict
--[[
	Guard: type and range checks for remote arguments. Every check returns the
	narrowed value or nil, so a handler reads:
		local slot = Guard.int(arg, 1, maxSlots); if slot == nil then return end
]]

local Guard = {}

function Guard.finite(value: unknown): number?
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

function Guard.int(value: unknown, min: number, max: number): number?
	local n = Guard.finite(value)
	if n == nil or n % 1 ~= 0 or n < min or n > max then
		return nil
	end
	return n
end

function Guard.str(value: unknown, maxLength: number): string?
	if type(value) ~= "string" or #value == 0 or #value > maxLength then
		return nil
	end
	return value
end

--- ASCII letters and digits only.
function Guard.alnum(value: unknown, maxLength: number): string?
	local s = Guard.str(value, maxLength)
	if s == nil or string.find(s, "[^%w]") then
		return nil
	end
	return s
end

function Guard.bool(value: unknown): boolean?
	if type(value) ~= "boolean" then
		return nil
	end
	return value
end

--- A string that is a key of `map`.
function Guard.oneOf<T>(value: unknown, map: { [string]: T }, maxLength: number?): string?
	local s = Guard.str(value, maxLength or 64)
	if s == nil or map[s] == nil then
		return nil
	end
	return s
end

return table.freeze(Guard)
