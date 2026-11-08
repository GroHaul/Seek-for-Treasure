--!strict
--[[
	StallController: walking up to a market stall and pressing its prompt opens
	that stall's panel (GDD §15.2). Prompts carry the attribute StallKind =
	"Tools" | "Potions" | "Upgrades", which is also the panel's name. A stall
	panel closes on its own when you walk more than 30 studs away.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local UI = script.Parent.Parent.UI
local Root = require(UI.Root)

local KINDS = { Tools = true, Potions = true, Upgrades = true }
local WALK_AWAY = 30

local Stall = {}

local openAt: { kind: string, position: Vector3 }? = nil

function Stall.init() end

function Stall.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player ~= Players.LocalPlayer then
			return
		end
		local kind = prompt:GetAttribute("StallKind")
		if type(kind) == "string" and KINDS[kind] then
			Root.open(kind)
			local parent = prompt.Parent
			if parent and parent:IsA("BasePart") then
				openAt = { kind = kind, position = parent.Position }
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local at = openAt
			if at then
				if not Root.isOpen(at.kind) then
					openAt = nil
				else
					local character = (Players.LocalPlayer :: Player).Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					if root and root:IsA("BasePart") and (root.Position - at.position).Magnitude > WALK_AWAY then
						Root.close()
						openAt = nil
					end
				end
			end
		end
	end)
end

return Stall
