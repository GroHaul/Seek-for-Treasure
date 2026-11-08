--!strict
--[[
	Remotes: client access to the server-created RemoteEvents (WaitForChild).
	Clients only ever send intents ("buy pets_t2"); the server validates all of it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local folder = ReplicatedStorage:WaitForChild(Net.folderName)

local Remotes = {}

function Remotes.get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.fire(name: string, ...: any)
	Remotes.get(name):FireServer(...)
end

function Remotes.on(name: string, handler: (...any) -> ()): RBXScriptConnection
	return Remotes.get(name).OnClientEvent:Connect(handler)
end

return Remotes
