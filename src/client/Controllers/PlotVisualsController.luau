--!strict
--[[
	PlotVisualsController: client-only idle motion for treasures on pedestals
	(gentle bob + slow spin) and the hue cycle for Rainbow / Prismatic finishes
	(GDD §3.1, §6). Only treasures within 140 studs of the camera animate.
	The server owns the parts; these local CFrame/Color changes never replicate.
]]

local RunService = game:GetService("RunService")

local RANGE = 140

local PlotVisuals = {}

type Tracked = { part: BasePart, base: CFrame, phase: number, hue: number? }
local tracked: { [BasePart]: Tracked } = {}

local function track(part: Instance)
	if not part:IsA("BasePart") or part.Name ~= "Body" then
		return
	end
	local model = part.Parent
	if model == nil or model.Name ~= "Treasure" then
		return
	end
	local hue = part:GetAttribute("Huefinish")
	tracked[part] = {
		part = part,
		base = part.CFrame,
		phase = math.random() * math.pi * 2,
		hue = if type(hue) == "number" then hue else nil,
	}
	part.Destroying:Connect(function()
		tracked[part] = nil
	end)
end

function PlotVisuals.init() end

function PlotVisuals.start()
	task.spawn(function()
		local world = workspace:WaitForChild("World")
		local plots = world:WaitForChild("Plots")
		for _, descendant in plots:GetDescendants() do
			track(descendant)
		end
		plots.DescendantAdded:Connect(track)
		plots.DescendantRemoving:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				tracked[descendant] = nil
			end
		end)
	end)

	RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if camera == nil then
			return
		end
		local eye = camera.CFrame.Position
		local t = os.clock()
		for part, info in tracked do
			if (info.base.Position - eye).Magnitude > RANGE then
				continue
			end
			part.CFrame = info.base * CFrame.new(0, math.sin(t * 2 + info.phase) * 0.3, 0) * CFrame.Angles(0, (t * 0.8 + info.phase) % (math.pi * 2), 0)
			if info.hue then
				part.Color = Color3.fromHSV((t / info.hue + info.phase) % 1, 0.65, 1)
			end
		end
	end)
end

return PlotVisuals
