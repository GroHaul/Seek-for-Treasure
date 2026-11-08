--!strict
--[[
	ToastController: short messages at the top of the screen (max 3 at once),
	the "Welcome back" popup for offline earnings, and text for every server
	Notify kind. Other controllers call Toast.show(text, color?, seconds?).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Format"))
local Catalog = require(Shared:WaitForChild("Catalog"))

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Root = require(UI.Root)
local Remotes = require(script.Parent.Parent.Remotes)

local C = Theme.colors
local MAX_VISIBLE = 2

local Toast = {}

local stack: Frame
local welcome: Root.Modal

function Toast.show(text: string, color: Color3?, seconds: number?)
	local visible = 0
	for _, child in stack:GetChildren() do
		if child:IsA("Frame") then
			visible += 1
		end
	end
	if visible >= MAX_VISIBLE then
		local oldest: Instance? = nil
		local oldestOrder = math.huge
		for _, child in stack:GetChildren() do
			if child:IsA("Frame") and child.LayoutOrder < oldestOrder then
				oldest, oldestOrder = child, child.LayoutOrder
			end
		end
		if oldest then
			oldest:Destroy()
		end
	end
	local toast = Kit.panel({
		Name = "Toast",
		Size = UDim2.fromOffset(410, 36),
		BackgroundColor3 = C.cream,
		LayoutOrder = math.floor(os.clock() * 1000),
	}, UDim.new(0.5, 0))
	local stroke = toast:FindFirstChildOfClass("UIStroke")
	if stroke and color then
		stroke.Color = color
		stroke.Thickness = 4
	end
	Kit.text(text, { Size = UDim2.new(1, -24, 1, -8), Position = UDim2.fromOffset(12, 4), Parent = toast })
	local scale = Kit.new("UIScale", { Scale = 0.6, Parent = toast })
	toast.Parent = stack
	TweenService:Create(scale, Theme.motion.bouncy, { Scale = 1 }):Play()
	task.delay(seconds or 2.6, function()
		if toast.Parent then
			toast:Destroy()
		end
	end)
end

local function potionName(id: any): string
	local potion = if type(id) == "string" then Catalog.potionById[id] else nil
	return if potion then potion.name else "Potion"
end

local NOTIFY_TEXT: { [string]: (any) -> (string, Color3?) } = {
	cant_afford = function(p)
		return "Not enough cash: need " .. Format.cash(tonumber(p.price) or 0), C.coral
	end,
	bought_tool = function(p)
		local tool = Catalog.toolById[p.toolId]
		return "Equipped " .. (if tool then tool.name else "new tool") .. "!", C.cash
	end,
	potion_max = function(p)
		return potionName(p.potionId) .. " is at the 60 min maximum", C.coral
	end,
	rebirth = function(p)
		return string.format("🌟 Rebirth %d! +50%% cash and +10%% luck forever", tonumber(p.count) or 1), C.grape
	end,
	code_ok = function()
		return "🎁 Code redeemed! Rewards added", C.cash
	end,
	code_invalid = function()
		return "That code doesn't exist (or it expired)", C.coral
	end,
	code_used = function()
		return "You already redeemed that code", C.sun
	end,
	code_cooldown = function(p)
		return "Too many tries. Wait " .. Format.duration(tonumber(p.seconds) or 600), C.coral
	end,
	code_limit = function()
		return "Code limit reached", C.coral
	end,
}

local function showWelcome(amount: number, seconds: number)
	local content = welcome.content
	content:ClearAllChildren()
	Kit.list(Enum.FillDirection.Vertical, 10).Parent = content
	Kit.text("While you were away for " .. Format.duration(seconds) .. ",", { Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, Parent = content })
	Kit.text("your pets earned", { Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 2, Parent = content })
	Kit.text(Format.cash(amount), {
		Size = UDim2.new(1, 0, 0, 56),
		TextColor3 = C.cash,
		TextStrokeColor3 = C.ink,
		TextStrokeTransparency = 0,
		LayoutOrder = 3,
		Parent = content,
	})
	Kit.text("Offline earnings: 50% rate, up to 2 hours", { Size = UDim2.new(1, 0, 0, 20), TextColor3 = C.muted, LayoutOrder = 4, Parent = content })
	local ok = Kit.button("Collect!", "primary", function()
		Root.close()
	end, { Size = UDim2.fromOffset(200, 54), LayoutOrder = 5 })
	ok.instance.Parent = content
	Root.open("Welcome")
end

function Toast.init()
	stack = Kit.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -140),
		Size = UDim2.fromOffset(420, 76),
		ZIndex = 80,
		Parent = Root.canvas,
	}, { Kit.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom) })
	welcome = Root.modal("Welcome", "Welcome back!", Vector2.new(440, 330))
end

function Toast.start()
	Remotes.on(Net.Notify, function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.kind == "welcome_back" then
			showWelcome(tonumber(payload.amount) or 0, tonumber(payload.seconds) or 0)
			return
		end
		local builder = NOTIFY_TEXT[payload.kind]
		if builder then
			local text, color = builder(payload)
			Toast.show(text, color)
		end
	end)
end

return Toast
