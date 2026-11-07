--!strict
--[[
	Client bootstrap: the only LocalScript. Builds the UI root, then runs init()
	on every controller (build UI, no remote traffic) and start() (connect
	remotes and loops), in a fixed order.
]]

local Root = require(script:WaitForChild("UI"):WaitForChild("Root"))

local ORDER = {
	"StateController",
	"ToastController",
	"HudController",
	"SearchController",
	"ShopController",
	"InventoryController",
	"RebirthController",
	"CodesController",
	"SettingsController",
	"RevealController",
	"BannerController",
	"IndexController",
	"PlotVisualsController",
	"TutorialController",
}

type Controller = { init: () -> (), start: () -> () }

Root.init()

local folder = script:WaitForChild("Controllers")
local controllers: { Controller } = {}
for _, name in ORDER do
	table.insert(controllers, require(folder:WaitForChild(name) :: ModuleScript) :: any)
end
for i, controller in controllers do
	local ok, err = pcall(controller.init :: any)
	if not ok then
		warn(`[Client] {ORDER[i]}.init failed: {err}`)
	end
end
for i, controller in controllers do
	local ok, err = pcall(controller.start :: any)
	if not ok then
		warn(`[Client] {ORDER[i]}.start failed: {err}`)
	end
end
