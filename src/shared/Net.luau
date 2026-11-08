--!strict
--[[
	Net: the one list of remote names (GDD §12.1). The server creates every
	RemoteEvent from this list at boot; clients WaitForChild them by name.
	Dev_Command is created only in Studio (DevService).
]]

local Net = {
	folderName = "Remotes",

	-- client -> server (each has a server-side rate limit and validator)
	Plot_Place = "Plot_Place",
	Plot_Remove = "Plot_Remove",
	Plot_PlaceBest = "Plot_PlaceBest",
	Inv_Sell = "Inv_Sell",
	Shop_BuyTool = "Shop_BuyTool",
	Shop_EquipTool = "Shop_EquipTool",
	Shop_BuyPotion = "Shop_BuyPotion",
	Shop_BuySlot = "Shop_BuySlot",
	Shop_Prompt = "Shop_Prompt", -- ask the server to prompt a Robux pass/product
	Potion_Use = "Potion_Use",
	Upgrade_Buy = "Upgrade_Buy",
	Segment_Unlock = "Segment_Unlock",
	Rebirth_Request = "Rebirth_Request",
	Code_Redeem = "Code_Redeem",
	Settings_Set = "Settings_Set",
	Tutorial_Done = "Tutorial_Done",
	Dev_Command = "Dev_Command",

	-- server -> client
	State_Snapshot = "State_Snapshot",
	State_Delta = "State_Delta",
	Search_State = "Search_State",
	Search_Reveal = "Search_Reveal",
	Announce_Banner = "Announce_Banner",
	Notify = "Notify",
}

Net.all = {
	Net.Plot_Place,
	Net.Plot_Remove,
	Net.Plot_PlaceBest,
	Net.Inv_Sell,
	Net.Shop_BuyTool,
	Net.Shop_EquipTool,
	Net.Shop_BuyPotion,
	Net.Shop_BuySlot,
	Net.Shop_Prompt,
	Net.Potion_Use,
	Net.Upgrade_Buy,
	Net.Segment_Unlock,
	Net.Rebirth_Request,
	Net.Code_Redeem,
	Net.Settings_Set,
	Net.Tutorial_Done,
	Net.State_Snapshot,
	Net.State_Delta,
	Net.Search_State,
	Net.Search_Reveal,
	Net.Announce_Banner,
	Net.Notify,
}

return table.freeze(Net)
