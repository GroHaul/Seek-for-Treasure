--!strict
--[[
	Root: the one ScreenGui and its scaling. Layout is authored at a 660 x 336
	reference; the Canvas frame is sized to viewport / scale and a UIScale brings
	it back to full screen, so every Offset in the UI scales with the device.
	scale = clamp(min(w / 660, h / 336), 0.75, 1.6), measured inside the core-UI
	safe insets: landscape phones from iPhone SE (667 x 339) to iPhone 14
	(844 x 354) get ~1.0, so 48-unit buttons are >= 48 px; 1080p gets 1.6.
	Modal panels shrink to fit short screens; their lists scroll.

	Studio only: set the ScreenGui attribute EmulateViewport (Vector2) to lay the
	UI out as that device would, drawn in the top-left of the Studio viewport;
	EmulateZoom (number) draws that layout smaller so a 1080p layout fits on screen.

	Modals: open(name) shows one panel at a time over a dimmer; close() hides it.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local C = Theme.colors

export type Modal = {
	name: string,
	frame: Frame,
	content: Frame,
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
	designSize: Vector2,
}

local Root = {
	gui = nil :: ScreenGui?,
	canvas = nil :: Frame?,
	scale = 1,
}

local modals: { [string]: Modal } = {}
local openName: string? = nil
local dimmer: TextButton
local uiScale: UIScale

local function relayout()
	local gui = Root.gui :: ScreenGui
	local canvas = Root.canvas :: Frame
	local size = gui.AbsoluteSize
	local emulate = gui:GetAttribute("EmulateViewport")
	local zoom = 1
	if RunService:IsStudio() and typeof(emulate) == "Vector2" then
		size = emulate
		local z = gui:GetAttribute("EmulateZoom")
		zoom = if type(z) == "number" and z > 0 then z else 1
	end
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local scale = math.clamp(math.min(size.X / Theme.reference.X, size.Y / Theme.reference.Y), Theme.scaleMin, Theme.scaleMax)
	local logical = Vector2.new(size.X / scale, size.Y / scale)
	Root.scale = scale
	uiScale.Scale = scale * zoom
	canvas.Size = UDim2.fromOffset(logical.X, logical.Y)
	for _, modal in modals do
		modal.frame.Size = UDim2.fromOffset(math.min(modal.designSize.X, logical.X - 24), math.min(modal.designSize.Y, logical.Y - 16))
	end
end

function Root.init()
	local playerGui = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	local gui = Kit.new("ScreenGui", {
		Name = "SFT_UI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		IgnoreGuiInset = false,
	}) :: ScreenGui
	uiScale = Kit.new("UIScale")
	local canvas = Kit.new("Frame", {
		Name = "Canvas",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Theme.reference.X, Theme.reference.Y),
	}, { uiScale }) :: Frame
	dimmer = Kit.new("TextButton", {
		Name = "Dimmer",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.55,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 50,
		Parent = canvas,
	}) :: TextButton
	dimmer.Activated:Connect(function()
		Root.close()
	end)
	canvas.Parent = gui
	Root.gui = gui
	Root.canvas = canvas
	gui.Parent = playerGui
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	gui:GetAttributeChangedSignal("EmulateViewport"):Connect(relayout)
	gui:GetAttributeChangedSignal("EmulateZoom"):Connect(relayout)
	relayout()
end

--- Creates a hidden modal panel with a title bar and a close button.
function Root.modal(name: string, title: string, size: Vector2): Modal
	local canvas = Root.canvas :: Frame
	local frame = Kit.panel({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		Visible = false,
		ZIndex = 60,
		Parent = canvas,
	})
	Kit.shadow(frame)
	-- sky-blue header band with a glossy gradient and a big outlined title
	local header = Kit.new("Frame", {
		Name = "Header",
		BackgroundColor3 = C.white,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 50),
		ZIndex = 61,
		Parent = frame,
	}, { Kit.corner(UDim.new(0, 18)), Kit.gradient(C.skyLight, C.skyDeep) })
	-- square off the header's bottom corners
	Kit.new("Frame", {
		BackgroundColor3 = C.skyDeep,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -18),
		Size = UDim2.new(1, 0, 0, 18),
		ZIndex = 61,
		Parent = header,
	})
	Kit.new("Frame", {
		Name = "Rule",
		BackgroundColor3 = C.ink,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 3),
		ZIndex = 62,
		Parent = header,
	})
	Kit.label(title, {
		Size = UDim2.new(1, -120, 0, 38),
		Position = UDim2.fromOffset(20, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
		Parent = header,
	}, 3)
	local close = Kit.button("X", "danger", function()
		Root.close()
	end, { Size = UDim2.fromOffset(48, 48), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 10, 0, -10), ZIndex = 64, Name = "Close" })
	close.instance.Parent = frame
	local content = Kit.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.new(1, -32, 1, -76),
		ZIndex = 61,
		Parent = frame,
	}) :: Frame
	local modal: Modal = { name = name, frame = frame, content = content, designSize = size }
	modals[name] = modal
	relayout()
	return modal
end

function Root.open(name: string)
	if openName == name then
		return
	end
	Root.close()
	local modal = modals[name]
	if modal == nil then
		return
	end
	openName = name
	dimmer.Visible = true
	local frame = modal.frame
	local scale = frame:FindFirstChild("PopScale") :: UIScale?
	if scale == nil then
		scale = Kit.new("UIScale", { Name = "PopScale", Parent = frame })
	end
	local popScale = scale :: UIScale
	popScale.Scale = 0.85
	frame.Visible = true
	TweenService:Create(popScale, Theme.motion.bouncy, { Scale = 1 }):Play()
	if modal.onOpen then
		modal.onOpen()
	end
end

function Root.close()
	local name = openName
	if name == nil then
		return
	end
	openName = nil
	dimmer.Visible = false
	local modal = modals[name]
	if modal then
		modal.frame.Visible = false
		if modal.onClose then
			modal.onClose()
		end
	end
end

function Root.toggle(name: string)
	if openName == name then
		Root.close()
	else
		Root.open(name)
	end
end

function Root.isOpen(name: string): boolean
	return openName == name
end

return Root
