--!strict
--[[
	CodesController: the Codes panel (GDD §9.7) and the in-world code board text.
	The client only sends the typed string; validation, rewards and the
	brute-force lockout are all on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Social = require(Shared:WaitForChild("Config"):WaitForChild("Social")) :: any

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Root = require(UI.Root)
local Remotes = require(script.Parent.Parent.Remotes)

local C = Theme.colors

local Codes = {}

local box: TextBox
local status: TextLabel

local STATUS: { [string]: { text: string, color: Color3 } } = {
	code_ok = { text = "Redeemed! Check your potions.", color = C.cash },
	code_invalid = { text = "That code doesn't exist (or it expired).", color = C.coral },
	code_used = { text = "You already redeemed that code.", color = C.sun },
	code_cooldown = { text = "Too many tries. Please wait a few minutes.", color = C.coral },
	code_limit = { text = "Code limit reached.", color = C.coral },
}

function Codes.init()
	local modal = Root.modal("Codes", "Codes", Vector2.new(480, 320))
	local content = modal.content
	Kit.list(Enum.FillDirection.Vertical, 10).Parent = content
	Kit.text("Enter a code for free rewards!", { Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, Parent = content })
	box = Kit.new("TextBox", {
		Name = "CodeBox",
		PlaceholderText = "Type a code",
		Text = "",
		ClearTextOnFocus = false,
		FontFace = Theme.fonts.number,
		TextScaled = true,
		TextColor3 = C.ink,
		PlaceholderColor3 = C.muted,
		BackgroundColor3 = C.white,
		Size = UDim2.new(1, -40, 0, 50),
		LayoutOrder = 2,
		Parent = content,
	}, {
		Kit.corner(UDim.new(0, 12)),
		Kit.stroke(),
		Kit.padding(8),
		Kit.new("UITextSizeConstraint", { MaxTextSize = 28 }),
	}) :: TextBox
	local redeem = Kit.button("Redeem", "primary", function()
		local text = box.Text
		if #text > 0 then
			Remotes.fire(Net.Code_Redeem, string.sub(text, 1, 64))
		end
	end, { Size = UDim2.fromOffset(200, 54), LayoutOrder = 3 })
	redeem.instance.Parent = content
	status = Kit.text("", { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 4, Parent = content })
	local nextMilestone = Social.codeBoard.likeMilestones[1]
	Kit.text(string.gsub(Social.codeBoard.fallbackText, "{n}", string.format("%d", nextMilestone)), {
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = C.grape,
		LayoutOrder = 5,
		Parent = content,
	})
	modal.onOpen = function()
		status.Text = ""
	end
end

function Codes.start()
	Remotes.on(Net.Notify, function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		local entry = STATUS[payload.kind]
		if entry then
			status.Text = entry.text
			status.TextColor3 = entry.color
			if payload.kind == "code_ok" then
				box.Text = ""
			end
		end
	end)
end

return Codes
