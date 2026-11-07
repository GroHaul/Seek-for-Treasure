--!strict
--[[
	Kit: small UI builders in the Sunny Toybox style. Every builder sets Parent
	last. Buttons use Activated, so mouse, touch and gamepad all work.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Assets = require(script.Parent.Assets)

local C = Theme.colors

export type Button = {
	instance: TextButton,
	setEnabled: (enabled: boolean) -> (),
	setText: (text: string) -> (),
	setColor: (color: Color3) -> (),
}

local Kit = {}

--- Generic creator: Kit.new("Frame", { Size = ... }, { children }). Parent is applied last.
function Kit.new(className: string, props: { [string]: any }?, children: { any }?): any
	local inst = Instance.new(className :: any)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Kit.corner(radius: UDim?): any
	return Kit.new("UICorner", { CornerRadius = radius or UDim.new(0.2, 0) })
end

function Kit.stroke(color: Color3?, thickness: number?): any
	return Kit.new("UIStroke", {
		Color = color or C.ink,
		Thickness = thickness or Theme.stroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Kit.padding(px: number): any
	local u = UDim.new(0, px)
	return Kit.new("UIPadding", { PaddingLeft = u, PaddingRight = u, PaddingTop = u, PaddingBottom = u })
end

function Kit.list(direction: Enum.FillDirection, gap: number, align: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): any
	return Kit.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Center,
	})
end

function Kit.text(text: string, props: { [string]: any }?): TextLabel
	local label = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		FontFace = Theme.fonts.heading,
		TextColor3 = C.ink,
		TextScaled = true,
		RichText = true,
		Size = UDim2.new(1, 0, 0, 24),
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 40, MinTextSize = 9, Parent = label })
	if props then
		for key, value in props do
			(label :: any)[key] = value
		end
	end
	return label
end

--- Icon from Assets: ImageLabel when an uploaded image exists, else the emoji glyph.
function Kit.icon(name: string, size: number): GuiObject
	local asset = Assets[name]
	if asset and asset.image then
		return Kit.new("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Image = asset.image,
			Size = UDim2.fromOffset(size, size),
			ScaleType = Enum.ScaleType.Fit,
		})
	end
	return Kit.text(if asset then asset.glyph else "?", {
		Name = "Icon",
		Size = UDim2.fromOffset(size, size),
		FontFace = Theme.fonts.body,
	})
end

--- Cream panel with ink stroke and rounded corners.
function Kit.panel(props: { [string]: any }?, radius: UDim?): Frame
	local frame = Kit.new("Frame", {
		BackgroundColor3 = C.cream,
		BorderSizePixel = 0,
	}, { Kit.corner(radius or UDim.new(0, 18)), Kit.stroke() })
	if props then
		for key, value in props do
			(frame :: any)[key] = value
		end
	end
	return frame
end

--- Drop shadow (0, 4) ink at 30%, as a sibling behind `frame` that follows its
--- size, position and visibility. Call after frame has its final parent.
function Kit.shadow(frame: GuiObject, radius: UDim?)
	local shadow = Kit.new("Frame", {
		Name = frame.Name .. "Shadow",
		BackgroundColor3 = C.ink,
		BackgroundTransparency = Theme.shadowTransparency,
		BorderSizePixel = 0,
		ZIndex = frame.ZIndex - 1,
	}, { Kit.corner(radius or UDim.new(0, 18)) })
	local function sync()
		shadow.Size = frame.Size
		shadow.AnchorPoint = frame.AnchorPoint
		shadow.Position = frame.Position + UDim2.fromOffset(0, Theme.shadowOffset)
		shadow.Visible = frame.Visible
	end
	sync()
	frame:GetPropertyChangedSignal("Size"):Connect(sync)
	frame:GetPropertyChangedSignal("Position"):Connect(sync)
	frame:GetPropertyChangedSignal("Visible"):Connect(sync)
	frame.Destroying:Connect(function()
		shadow:Destroy()
	end)
	shadow.Parent = frame.Parent
end

local KIND_COLORS = {
	primary = C.sun,
	secondary = C.sky,
	danger = C.coral,
	success = C.cash,
	neutral = C.white,
}

--- Pill button. kind: primary | secondary | danger | success | neutral.
function Kit.button(text: string, kind: string, onActivated: () -> (), props: { [string]: any }?): Button
	local base = (KIND_COLORS :: any)[kind] or C.sun
	local enabled = true
	local scale = Kit.new("UIScale", { Scale = 1 })
	local button = Kit.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = base,
		BorderSizePixel = 0,
		Text = text,
		FontFace = Theme.fonts.heading,
		TextColor3 = C.ink,
		TextScaled = true,
		RichText = true,
		Size = UDim2.fromOffset(150, 48),
	}, {
		Kit.corner(UDim.new(0.5, 0)),
		Kit.stroke(),
		scale,
		Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }),
		Kit.new("UITextSizeConstraint", { MaxTextSize = 26, MinTextSize = 9 }),
	}) :: TextButton
	if props then
		for key, value in props do
			(button :: any)[key] = value
		end
	end
	button.MouseButton1Down:Connect(function()
		if enabled then
			TweenService:Create(scale, Theme.motion.fast, { Scale = 0.94 }):Play()
			button.BackgroundColor3 = Theme.darken(base)
		end
	end)
	local function release()
		TweenService:Create(scale, Theme.motion.bouncy, { Scale = 1 }):Play()
		button.BackgroundColor3 = if enabled then base else Theme.desaturate(base)
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.Activated:Connect(function()
		if enabled then
			onActivated()
		end
	end)

	local api: Button = {
		instance = button,
		setEnabled = function(on: boolean)
			enabled = on
			button.Active = on
			button.BackgroundColor3 = if on then base else Theme.desaturate(base)
			button.TextTransparency = if on then 0 else 0.35
		end,
		setText = function(t: string)
			button.Text = t
		end,
		setColor = function(color: Color3)
			base = color
			button.BackgroundColor3 = if enabled then base else Theme.desaturate(base)
		end,
	}
	return api
end

--- Round HUD menu button: icon + caption, 66 x 66 reference size.
function Kit.menuButton(iconName: string, caption: string, onActivated: () -> ()): TextButton
	local button = Kit.button("", "neutral", onActivated, { Size = UDim2.fromOffset(66, 66), Name = caption })
	local inst = button.instance
	local corner = inst:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.3, 0)
	end
	local icon = Kit.icon(iconName, 34)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 2)
	icon.Parent = inst
	Kit.text(caption, {
		Size = UDim2.new(1, 8, 0, 16),
		Position = UDim2.new(0.5, 0, 1, -2),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = inst,
	})
	return inst
end

--- A rarity color that stays readable on cream/white: very light colors
--- (Common grey, Divine white-gold, Celestial cyan) are darkened.
function Kit.readable(color: Color3): Color3
	local luminance = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	if luminance > 0.62 then
		local h, s, v = color:ToHSV()
		return Color3.fromHSV(h, math.min(1, s + 0.25), v * 0.62)
	end
	return color
end

--- Rarity frame: stroke in the rarity color, thicker and gradient-filled for top tiers.
function Kit.rarityStroke(target: GuiObject, color: Color3, order: number)
	local stroke = target:FindFirstChildOfClass("UIStroke") or Kit.stroke()
	stroke.Color = color
	stroke.Thickness = if order >= 8 then 5 elseif order >= 5 then 4 else 3
	stroke.Parent = target
end

return Kit
