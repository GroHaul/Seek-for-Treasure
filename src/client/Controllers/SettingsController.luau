--!strict
--[[
	SettingsController: Reduce screen shake (accessibility, GDD §0 MVP*), Music,
	Sound effects. Toggles send Settings_Set; the saved value comes back in State.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Root = require(UI.Root)
local Remotes = require(script.Parent.Parent.Remotes)
local State = require(script.Parent.StateController)

local C = Theme.colors

local Settings = {}

local ROWS = {
	{ key = "reduceShake", label = "Reduce screen shake" },
	{ key = "music", label = "Music" },
	{ key = "sfx", label = "Sound effects" },
}

local toggles: { [string]: Kit.Button } = {}

local function refresh()
	local settings = State.profile.settings
	if type(settings) ~= "table" then
		return
	end
	for key, toggle in toggles do
		local on = settings[key] == true
		toggle.setText(if on then "ON" else "OFF")
		toggle.setColor(if on then C.cash else C.white)
	end
end

function Settings.init()
	local modal = Root.modal("Settings", "Settings", Vector2.new(440, 300))
	local content = modal.content
	Kit.list(Enum.FillDirection.Vertical, 12).Parent = content
	for i, row in ROWS do
		local frame = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 56),
			LayoutOrder = i,
			Parent = content,
		})
		Kit.text(row.label, {
			Size = UDim2.new(1, -140, 1, -12),
			Position = UDim2.fromOffset(4, 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		local toggle = Kit.button("OFF", "neutral", function()
			local settings = State.profile.settings
			local current = type(settings) == "table" and settings[row.key] == true
			Remotes.fire(Net.Settings_Set, row.key, not current)
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(110, 48) })
		toggle.instance.Parent = frame
		toggles[row.key] = toggle
	end
	modal.onOpen = refresh
end

function Settings.start()
	State.watch({ "settings" }, refresh)
end

--- For the reveal cinematic (step 7).
function Settings.reduceShake(): boolean
	local settings = State.profile.settings
	return type(settings) == "table" and settings.reduceShake == true
end

return Settings
