--!strict
--[[
	Client — điểm vào phía client: dựng HUD nhỏ để xác nhận script đã đồng bộ.
	HUD do src/client/UI/Hud.luau vẽ, dữ liệu từ RemoteEvent "Notify".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Hud = require(script.Parent:WaitForChild("UI"):WaitForChild("Hud"))

local player = Players.LocalPlayer
local hud = Hud.new(player:WaitForChild("PlayerGui"), Config)

local Notify = Net.waitForRemote("Notify", 15)
if Notify then
	Notify.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" then
			hud:setStatus(tostring(payload.message or payload.title or ""))
		end
	end)
else
	hud:setStatus("Không thấy RemoteEvent Notify — kiểm tra server script.")
end

print("[brige] client đã chạy — chờ đồng bộ từ GitHub.")
