--!strict
--[[
	Config/Segments: ordered list of every segment in the build. MVP = Pets only.
	Fish, Cars and Anime are in the GDD backlog; each is added as one module here.
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Segments: { Types.Segment } = {
	require(script.Pets),
}

return DeepFreeze(Segments)
