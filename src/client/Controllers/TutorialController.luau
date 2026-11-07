--!strict
--[[
	TutorialController: the 5-step first-minute tutorial (GDD §1.2, §9.5).
	walk -> watch -> collect -> buy -> back, each with a banner and a glowing
	arrow (Beam) from the character to the target. Skippable; when finished or
	skipped it sends Tutorial_Done so it never shows again.
	Only runs for profiles with flags.tutorialDone == false.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Onboarding = require(Shared:WaitForChild("Config"):WaitForChild("Onboarding")) :: any

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Root = require(UI.Root)
local Remotes = require(script.Parent.Parent.Remotes)
local State = require(script.Parent.StateController)
local Search = require(script.Parent.SearchController)
local Hud = require(script.Parent.HudController)

local C = Theme.colors
local MEADOW_TARGET = Vector3.new(0, 3, 0)

local Tutorial = {}

local banner: Frame
local bannerText: TextLabel
local step = 0
local running = false
local beam: Beam? = nil
local targetAttachment: Attachment? = nil
local pulseTween: Tween? = nil

local function clearArrow()
	if beam then
		beam:Destroy()
		beam = nil
	end
	if targetAttachment then
		targetAttachment:Destroy()
		targetAttachment = nil
	end
	if pulseTween then
		pulseTween:Cancel()
		pulseTween = nil
	end
end

local function arrowTo(position: Vector3?)
	clearArrow()
	local character = (Players.LocalPlayer :: Player).Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if position == nil or root == nil then
		return
	end
	local a0 = Kit.new("Attachment", { Name = "TutorialFrom", Parent = root }) :: Attachment
	local a1 = Kit.new("Attachment", { Name = "TutorialTo", Position = position, Parent = workspace.Terrain }) :: Attachment
	beam = Kit.new("Beam", {
		Attachment0 = a0,
		Attachment1 = a1,
		Color = ColorSequence.new(C.sun),
		LightEmission = 1,
		Width0 = 1.2,
		Width1 = 1.2,
		FaceCamera = true,
		Segments = 20,
		Transparency = NumberSequence.new(0.2),
		Parent = a0,
	})
	targetAttachment = a1
end

local function ownPadPosition(): Vector3?
	local index = tonumber(State.derived.plotIndex) or 0
	local plot = workspace:FindFirstChild("World") and workspace.World.Plots:FindFirstChild(string.format("Plot_%02d", index))
	local pad = plot and plot:FindFirstChild("CollectPad")
	return if pad and pad:IsA("BasePart") then pad.Position + Vector3.new(0, 2, 0) else nil
end

local function finish()
	running = false
	clearArrow()
	banner.Visible = false
	Remotes.fire(Net.Tutorial_Done)
end

local function show(index: number)
	step = index
	local info = Onboarding.tutorialSteps[index]
	if info == nil then
		finish()
		return
	end
	bannerText.Text = string.format("%d/%d  %s", index, #Onboarding.tutorialSteps, info.text)
	if info.id == "walk" or info.id == "back" then
		arrowTo(MEADOW_TARGET)
	elseif info.id == "collect" then
		arrowTo(ownPadPosition())
	else
		clearArrow()
	end
	if info.id == "buy" then
		local shopButton = Hud.menu.Shop
		if shopButton then
			local scale = shopButton:FindFirstChildOfClass("UIScale")
			if scale then
				pulseTween = TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.15 });
				(pulseTween :: Tween):Play()
			end
		end
	end
end

local function check()
	if not running then
		return
	end
	local profile = State.profile
	local id = Onboarding.tutorialSteps[step] and Onboarding.tutorialSteps[step].id
	local searches = tonumber(profile.stats and profile.stats.searches) or 0
	local owned = if profile.tools and profile.tools.pets then profile.tools.pets.owned else 1
	local done = (id == "walk" and Search.active)
		or (id == "watch" and searches >= 1)
		or (id == "collect" and (tonumber(profile.lifetimeEarned) or 0) > 0)
		or (id == "buy" and owned >= 2)
	if id == "back" and Search.active then
		finish()
	elseif done then
		show(step + 1)
	end
end

function Tutorial.init()
	banner = Kit.panel({
		Name = "TutorialBanner",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -82),
		Size = UDim2.fromOffset(540, 56),
		BackgroundColor3 = C.sun,
		Visible = false,
		Parent = Root.canvas,
	}, UDim.new(0.5, 0))
	bannerText =
		Kit.text("", { Size = UDim2.new(1, -120, 1, -10), Position = UDim2.fromOffset(16, 5), TextXAlignment = Enum.TextXAlignment.Left, Parent = banner })
	local skip =
		Kit.button("Skip", "neutral", finish, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(96, 48) })
	skip.instance.Parent = banner
	-- keep clear of the menu columns on narrow phones
	local canvas = Root.canvas :: Frame
	local function fit()
		banner.Size = UDim2.fromOffset(math.min(540, canvas.Size.X.Offset - 180), 56)
	end
	fit()
	canvas:GetPropertyChangedSignal("Size"):Connect(fit)
end

function Tutorial.start()
	State.watch({ "flags" }, function()
		local flags = State.profile.flags
		if running or type(flags) ~= "table" or flags.tutorialDone then
			if running and type(flags) == "table" and flags.tutorialDone then
				running = false
				clearArrow()
				banner.Visible = false
			end
			return
		end
		running = true
		banner.Visible = true
		show(1)
		check()
	end)
	State.watch({ "stats", "lifetimeEarned", "tools" }, check)
	Search.stateChanged:Connect(check);
	(Players.LocalPlayer :: Player).CharacterAdded:Connect(function()
		if running then
			task.wait(1)
			show(step)
		end
	end)
end

return Tutorial
