--!strict
--[[
	Server bootstrap: the only server Script. Requires every service in a fixed
	order, then runs init() on all of them (create instances, no cross-calls),
	then start() (connect events, start loops).
]]

local ORDER = {
	"DataService",
	"RemoteService",
	"StateService",
	"WorldService",
	"ZoneService",
	"SocialService",
	"InventoryService",
	"PlotService",
	"ShopService",
	"PotionService",
	"RebirthService",
	"CodeService",
	"SettingsService",
	"SearchService",
	"IndexService",
	"AnnounceService",
	"TelemetryService",
	"DevService",
}

type Service = { init: () -> (), start: () -> () }

local folder = script:WaitForChild("Services")
local services: { Service } = {}
for _, name in ORDER do
	local module = folder:WaitForChild(name) :: ModuleScript
	table.insert(services, require(module) :: any)
end

for i, service in services do
	local ok, err = pcall(service.init :: any)
	if not ok then
		error(`[Server] {ORDER[i]}.init failed: {err}`)
	end
end
for i, service in services do
	local ok, err = pcall(service.start :: any)
	if not ok then
		error(`[Server] {ORDER[i]}.start failed: {err}`)
	end
end

workspace:SetAttribute("SFT_ServerReady", true)
print(`[Server] Seek for Treasure ready ({#services} services)`)
