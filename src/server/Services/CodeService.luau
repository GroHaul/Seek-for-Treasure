--!strict
--[[
	CodeService: redeem codes (GDD §9.7).

	Input is trimmed, case-insensitive, 1-20 characters of [A-Za-z0-9]. Each code
	works once per profile and can expire. Brute-force guard: 10 failed attempts
	within 10 minutes lock the player out of redeeming for 10 minutes (tracked by
	UserId for the life of the server, so rejoining the same server doesn't reset it).
	Code strings live only in ServerStorage.Secrets.Codes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Social = require(Shared.Config.Social) :: Types.SocialConfig

local RemoteService = require(script.Parent.RemoteService)
local StateService = require(script.Parent.StateService)
local PotionService = require(script.Parent.PotionService)
local Guard = require(script.Parent.Parent.Util.Guard)

type Reward = { cash: number?, potions: { [string]: number }? }
type Code = { reward: Reward, expires: number? }

local MAX_REDEEMED = 200
local MAX_RAW_LENGTH = 64

local CodeService = {
	-- (player, code, reward)
	redeemed = Signal.new() :: Signal.Signal<Player, string, Reward>,
}

local codes: { [string]: Code } = {}
type Attempts = { count: number, windowStart: number, lockedUntil: number }
local attempts: { [number]: Attempts } = {}

local function notify(player: Player, kind: string, data: { [string]: any }?)
	local payload: { [string]: any } = if data then data else {}
	payload.kind = kind
	RemoteService.fire(Net.Notify, player, payload)
end

local function attemptsFor(userId: number): Attempts
	local a = attempts[userId]
	if a == nil then
		a = { count = 0, windowStart = 0, lockedUntil = 0 }
		attempts[userId] = a
	end
	return a
end

local function registerFailure(userId: number, now: number)
	local a = attemptsFor(userId)
	if now - a.windowStart > Social.codes.failureWindowSeconds then
		a.count = 0
		a.windowStart = now
	end
	a.count += 1
	if a.count >= Social.codes.maxFailures then
		a.lockedUntil = now + Social.codes.cooldownSeconds
		a.count = 0
		a.windowStart = now
	end
end

--- Normalizes raw input to an upper-case code, or nil if it's malformed.
function CodeService.normalize(raw: unknown): string?
	if type(raw) ~= "string" or #raw > MAX_RAW_LENGTH then
		return nil
	end
	local trimmed = string.match(raw, "^%s*(.-)%s*$") :: string
	local code = Guard.alnum(trimmed, Social.codes.maxLength)
	return if code then string.upper(code) else nil
end

--- Returns the outcome kind: code_ok, code_invalid, code_used, code_cooldown, code_limit.
function CodeService.redeem(player: Player, profile: Types.Profile, raw: unknown): string
	local now = os.time()
	local a = attemptsFor(player.UserId)
	if a.lockedUntil > now then
		notify(player, "code_cooldown", { seconds = a.lockedUntil - now })
		return "code_cooldown"
	end
	local code = CodeService.normalize(raw)
	local entry = if code then codes[code] else nil
	if code == nil or entry == nil or (entry.expires ~= nil and entry.expires <= now) then
		registerFailure(player.UserId, now)
		notify(player, "code_invalid")
		return "code_invalid"
	end
	if profile.codes[code] ~= nil then
		notify(player, "code_used")
		return "code_used"
	end
	local redeemedCount = 0
	for _ in profile.codes do
		redeemedCount += 1
	end
	if redeemedCount >= MAX_REDEEMED then
		notify(player, "code_limit")
		return "code_limit"
	end

	local reward = entry.reward
	if reward.cash and reward.cash > 0 then
		profile.cash += reward.cash
		profile.lifetimeEarned += reward.cash
		StateService.markDirty(player, "cash", "lifetimeEarned")
	end
	if reward.potions then
		for potionId, doses in reward.potions do
			PotionService.add(player, profile, potionId, doses, true)
		end
	end
	profile.codes[code] = now
	notify(player, "code_ok", { code = code, reward = reward })
	CodeService.redeemed:Fire(player, code, reward)
	return "code_ok"
end

function CodeService.init()
	local secrets = ServerStorage:WaitForChild("Secrets")
	local module = secrets:FindFirstChild("Codes")
	if module and module:IsA("ModuleScript") then
		codes = require(module) :: any
	else
		warn("[CodeService] ServerStorage.Secrets.Codes is missing; no codes can be redeemed")
	end
end

function CodeService.start()
	RemoteService.on(Net.Code_Redeem, 0.5, 3, function(player, profile, codeArg)
		CodeService.redeem(player, profile, codeArg)
	end)
end

return CodeService
