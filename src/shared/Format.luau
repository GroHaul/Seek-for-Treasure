--!strict
--[[
	Format: short number formatting for UI and billboards (GDD §8.1 suffixes).
	Format.cash(1234567) -> "1.23M"; Format.duration(3725) -> "1:02:05".
]]

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local Format = {}

function Format.number(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	local value = math.abs(n)
	if value < 1000 then
		local s = if value % 1 == 0 then tostring(value) else string.format("%.1f", value)
		return if negative then "-" .. s else s
	end
	local tier = math.min(#SUFFIXES - 1, math.floor(math.log10(value) / 3))
	local scaled = value / 10 ^ (tier * 3)
	local digits = if scaled >= 100 then 0 elseif scaled >= 10 then 1 else 2
	local text = string.format("%." .. digits .. "f", math.floor(scaled * 10 ^ digits) / 10 ^ digits)
	if digits > 0 then
		text = string.gsub(string.gsub(text, "0+$", ""), "%.$", "")
	end
	return (if negative then "-" else "") .. text .. SUFFIXES[tier + 1]
end

function Format.cash(n: number): string
	return "$" .. Format.number(math.floor(n))
end

function Format.oneIn(n: number): string
	if n <= 0 then
		return "common"
	end
	local s = tostring(math.floor(n))
	local formatted = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	if string.sub(formatted, 1, 1) == "," then
		formatted = string.sub(formatted, 2)
	end
	return "1 in " .. formatted
end

function Format.duration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	local sec = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%d:%02d", m, sec)
end

return table.freeze(Format)
