--!strict
--[[
	Retry: pcall with exponential backoff for DataStore calls (GDD §11.3).
	Default: one attempt plus up to 5 retries, waiting 1, 2, 4, 8, 16 s (31 s total).
	Tests pass `delays = {0, 0, ...}` to run instantly.
]]

local Retry = {}

Retry.DEFAULT_DELAYS = table.freeze({ 1, 2, 4, 8, 16 })

--- Runs fn until it succeeds or the delays run out.
--- Returns (true, result) or (false, lastError).
function Retry.run<T>(label: string, fn: () -> T, delays: { number }?): (boolean, any)
	local waits = delays or Retry.DEFAULT_DELAYS
	local attempt = 0
	while true do
		attempt += 1
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		local waitFor = waits[attempt]
		if waitFor == nil then
			warn(`[Retry] {label} failed after {attempt} attempts: {result}`)
			return false, result
		end
		warn(`[Retry] {label} attempt {attempt} failed: {result}; retrying in {waitFor}s`)
		if waitFor > 0 then
			task.wait(waitFor)
		end
	end
end

return table.freeze(Retry)
