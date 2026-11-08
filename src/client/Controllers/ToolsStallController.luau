--!strict
--[[
	ToolsStallController: the Tools stall's panel (GDD §5.1, §15.2). Opened by
	the stall's ProximityPrompt (StallController). Whistles are bought in order
	with cash; any owned one can be equipped (cosmetic).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Format = require(Shared:WaitForChild("Format"))
local Tools = require(Shared:WaitForChild("Config"):WaitForChild("Tools")) :: any

local UI = script.Parent.Parent.UI
local Root = require(UI.Root)
local Rows = require(UI.Rows)
local Remotes = require(script.Parent.Parent.Remotes)
local State = require(script.Parent.StateController)

local SEGMENT = "pets"

local ToolsStall = {}

local list: ScrollingFrame

local function render()
	if not Root.isOpen("Tools") or not State.loaded then
		return
	end
	Rows.clear(list)
	local profile = State.profile
	local segment = Catalog.segmentById[SEGMENT]
	local tool = profile.tools[SEGMENT]
	local owned, equipped = tool.owned, tool.equipped
	for _, entry in segment.tools do
		local stats = Tools.tiers[entry.tier]
		local price = stats.basePrice * segment.toolPriceMult
		local sub = string.format("Every %.2fs · Luck x%.2f · Mutation x%.2f", stats.interval, stats.luck, stats.mutation)
		local frame = Rows.row(list, entry.tier, "tool", entry.name, sub)
		if entry.tier == equipped then
			Rows.button(frame, "Equipped", "success", false, function() end)
		elseif entry.tier <= owned then
			Rows.button(frame, "Equip", "secondary", true, function()
				Remotes.fire(Net.Shop_EquipTool, entry.id)
			end)
		elseif entry.tier == owned + 1 then
			Rows.button(frame, "Buy " .. Format.cash(price), "primary", profile.cash >= price, function()
				Remotes.fire(Net.Shop_BuyTool, entry.id)
			end)
		else
			Rows.button(frame, "🔒 " .. Format.cash(price), "neutral", false, function() end)
		end
	end
end

function ToolsStall.init()
	local modal = Root.modal("Tools", "Tools Stall", Vector2.new(640, 420))
	list = Rows.list(modal.content, 0)
	modal.onOpen = render
end

function ToolsStall.start()
	State.watch({ "cash", "tools" }, render)
end

return ToolsStall
