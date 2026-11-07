--!strict
--[[
	RateLimiter: token bucket per player (GDD §12.1). `rate` tokens refill per
	second up to `burst`; each allowed call spends one. Buckets for a player are
	dropped with forget(player) on PlayerRemoving.
]]

export type Limiter = {
	allow: (self: Limiter, player: Player) -> boolean,
	forget: (self: Limiter, player: Player) -> (),
}

type Bucket = { tokens: number, last: number }

local RateLimiter = {}

function RateLimiter.new(rate: number, burst: number?): Limiter
	local capacity = burst or math.max(1, rate)
	local buckets: { [Player]: Bucket } = {}

	local limiter = {} :: Limiter

	function limiter.allow(_: Limiter, player: Player): boolean
		local now = os.clock()
		local bucket = buckets[player]
		if bucket == nil then
			bucket = { tokens = capacity, last = now }
			buckets[player] = bucket
		end
		bucket.tokens = math.min(capacity, bucket.tokens + (now - bucket.last) * rate)
		bucket.last = now
		if bucket.tokens >= 1 then
			bucket.tokens -= 1
			return true
		end
		return false
	end

	function limiter.forget(_: Limiter, player: Player)
		buckets[player] = nil
	end

	return limiter
end

return table.freeze(RateLimiter)
