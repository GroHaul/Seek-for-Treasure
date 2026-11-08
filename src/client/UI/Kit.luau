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

--- Gradient from `top` to `bottom` on the parent's fill (children aren't affected).
function Kit.gradient(top: Color3, bottom: Color3, rotation: number?): any
	return Kit.new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = rotation or 90 })
end

--- Glossy shading for any fill color: full brightness on top, a soft shade at the bottom.
function Kit.shade(): any
	return Kit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(242, 242, 242)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(196, 196, 196)),
		}),
		Rotation = 90,
	})
end

--- Thin white border inset inside `target` (the double-outline toy look). Takes no input.
function Kit.innerBorder(target: GuiObject, radius: UDim, inset: number?, transparency: number?)
	local i = inset or 3
	local inner = if radius.Scale > 0 then radius else UDim.new(0, math.max(0, radius.Offset - i))
	Kit.new("Frame", {
		Name = "InnerBorder",
		BackgroundTransparency = 1,
		Active = false,
		Position = UDim2.fromOffset(i, i),
		Size = UDim2.new(1, -2 * i, 1, -2 * i),
		Parent = target,
	}, {
		Kit.corner(inner),
		Kit.new("UIStroke", {
			Color = C.white,
			Thickness = 2,
			Transparency = transparency or 0.35,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
end

--- Thick outline around a label's glyphs.
function Kit.outline(label: GuiObject, thickness: number?, color: Color3?): UIStroke
	return Kit.new("UIStroke", {
		Name = "Outline",
		Color = color or C.ink,
		Thickness = thickness or Theme.outline,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = label,
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

--- Display text: white Fredoka One with a thick ink outline (pass TextColor3 to tint it).
function Kit.label(text: string, props: { [string]: any }?, outline: number?): TextLabel
	local label = Kit.text(text, props)
	if props == nil or props.TextColor3 == nil then
		label.TextColor3 = C.white
	end
	Kit.outline(label, outline)
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
	local glyph = Kit.text(if asset then asset.glyph else "?", {
		Name = "Icon",
		Size = UDim2.fromOffset(size, size),
		FontFace = Theme.fonts.body,
	})
	-- let emoji fill the box like an image icon would
	local limit = glyph:FindFirstChildOfClass("UITextSizeConstraint")
	if limit then
		limit.MaxTextSize = math.floor(size * 1.1)
	end
	return glyph
end

--- Cream panel: glossy gradient, ink stroke, white inner border, rounded corners.
function Kit.panel(props: { [string]: any }?, radius: UDim?): Frame
	local r = radius or UDim.new(0, 18)
	local frame = Kit.new("Frame", {
		BackgroundColor3 = C.cream,
		BorderSizePixel = 0,
	}, { Kit.corner(r), Kit.stroke(), Kit.shade() })
	Kit.innerBorder(frame, r, 3, 0.2)
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

local BUTTON_RADIUS = UDim.new(0, 14)

--- Glossy toy button: color fill with a top-light gradient, thick ink outline,
--- white inner border and white outlined text (in the child TextLabel "Label").
--- kind: primary | secondary | danger | success | neutral.
function Kit.button(text: string, kind: string, onActivated: () -> (), props: { [string]: any }?): Button
	local base = (KIND_COLORS :: any)[kind] or C.sun
	local enabled = true
	local scale = Kit.new("UIScale", { Scale = 1 })
	local button = Kit.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = base,
		BorderSizePixel = 0,
		Text = "",
		Size = UDim2.fromOffset(150, 48),
	}, {
		Kit.corner(BUTTON_RADIUS),
		Kit.stroke(),
		Kit.shade(),
		scale,
	}) :: TextButton
	Kit.innerBorder(button, BUTTON_RADIUS)
	local label = Kit.label(text, {
		Name = "Label",
		Size = UDim2.new(1, -18, 1, -12),
		Position = UDim2.fromOffset(9, 6),
		Parent = button,
	})
	local labelOutline = label:FindFirstChild("Outline") :: UIStroke
	local sizeLimit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if sizeLimit then
		sizeLimit.MaxTextSize = 26
	end
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
			label.TextTransparency = if on then 0 else 0.3
			labelOutline.Transparency = if on then 0 else 0.3
		end,
		setText = function(t: string)
			label.Text = t
		end,
		setColor = function(color: Color3)
			base = color
			button.BackgroundColor3 = if enabled then base else Theme.desaturate(base)
		end,
	}
	return api
end

--- HUD menu tile: glossy rounded square with a big icon and an outlined caption
--- along the bottom edge. 66 x 66 reference size.
function Kit.menuButton(iconName: string, caption: string, onActivated: () -> (), color: Color3?): TextButton
	local button = Kit.button("", "secondary", onActivated, { Size = UDim2.fromOffset(66, 66), Name = caption })
	if color then
		button.setColor(color)
	end
	local inst = button.instance
	local icon = Kit.icon(iconName, 42)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 2)
	icon.Parent = inst
	-- the caption may spill a little past the sides, never below into the next tile
	Kit.label(caption, {
		Name = "Caption",
		Size = UDim2.new(1, 12, 0, 20),
		Position = UDim2.new(0.5, 0, 1, 1),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = inst,
	}, 2.5)
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
