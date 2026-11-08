--!strict
--[[
	Rows: list rows for stall and shop panels: icon, outlined title, a subtitle,
	and an action button on the right. Shared by the Tools and Potions stalls.
]]

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local C = Theme.colors

local Rows = {}

--- Scrolling list filling `parent` below `top` px.
function Rows.list(parent: Instance, top: number): ScrollingFrame
	return Kit.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -top),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.ink,
		Parent = parent,
	}, { Kit.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top), Kit.padding(4) }) :: ScrollingFrame
end

function Rows.clear(list: Instance)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

--- A row panel; `rightWidth` px on the right are left free for the button.
function Rows.row(list: Instance, order: number, iconName: string, titleText: string, subText: string, rightWidth: number?): Frame
	local right = rightWidth or 180
	local frame = Kit.panel({
		Name = "Row" .. order,
		Size = UDim2.new(1, -12, 0, 60),
		LayoutOrder = order,
		BackgroundColor3 = C.white,
		Parent = list,
	}, UDim.new(0, 12))
	local icon = Kit.icon(iconName, 40)
	icon.Position = UDim2.fromOffset(10, 10)
	icon.Parent = frame
	Kit.label(titleText, {
		Name = "Title",
		Size = UDim2.new(1, -(right + 64), 0, 24),
		Position = UDim2.fromOffset(58, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	Kit.text(subText, {
		Name = "Sub",
		Size = UDim2.new(1, -(right + 64), 0, 18),
		Position = UDim2.fromOffset(58, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.fonts.body,
		TextColor3 = C.muted,
		Parent = frame,
	})
	return frame
end

--- Action button at the right edge of a row.
function Rows.button(frame: Frame, text: string, kind: string, enabled: boolean, onActivated: () -> (), width: number?): any
	local button = Kit.button(text, kind, onActivated, {
		Name = "Action",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(width or 160, 48),
	})
	button.setEnabled(enabled)
	button.instance.Parent = frame
	return button
end

return Rows
