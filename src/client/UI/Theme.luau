--!strict
--[[
	Theme: the "Sunny Toybox" style guide (GDD §13.1) as UI tokens.
	Panels: cream fill, 3 px ink stroke, drop shadow (0, 4) ink at 30%.
	Buttons: pill; primary Sun, secondary Sky, danger Coral; pressed 0.94 scale.
	Layout is authored at a 660 x 336 reference (the smallest landscape phone below
	the Roblox top bar) and scaled with UIScale: phones ~1.0, tablets ~1.5, desktop up to 1.6.
]]

local BUILDER_SANS = "rbxasset://fonts/families/BuilderSans.json"

local Theme = {
	colors = {
		sky = Color3.fromHex("#49B6FF"),
		sun = Color3.fromHex("#FFD23F"),
		leaf = Color3.fromHex("#5BD66B"),
		coral = Color3.fromHex("#FF6B6B"),
		grape = Color3.fromHex("#8E5CFF"),
		cream = Color3.fromHex("#FFF4DF"),
		ink = Color3.fromHex("#1D2340"),
		cash = Color3.fromHex("#3DDC84"),
		white = Color3.new(1, 1, 1),
		muted = Color3.fromHex("#8A90A6"),
		disabled = Color3.fromHex("#B9BCC6"),
	},
	fonts = {
		heading = Font.fromEnum(Enum.Font.FredokaOne),
		number = Font.new(BUILDER_SANS, Enum.FontWeight.Bold),
		body = Font.new(BUILDER_SANS, Enum.FontWeight.Medium),
	},
	stroke = 3,
	shadowOffset = 4,
	shadowTransparency = 0.7,
	motion = {
		fast = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		bouncy = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	},
	reference = Vector2.new(660, 336),
	scaleMin = 0.75,
	scaleMax = 1.6,
	minTouch = 48, -- dp; every button is authored >= 48 tall, and phones get scale >= 1
}

--- Darker variant for pressed states.
function Theme.darken(color: Color3, amount: number?): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.max(0, v - (amount or 0.12)))
end

--- 50% desaturated variant for disabled states.
function Theme.desaturate(color: Color3): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s * 0.5, v * 0.85)
end

return table.freeze(Theme)
