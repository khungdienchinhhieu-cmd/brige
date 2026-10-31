--!strict
--[[
	Client — điểm vào phía client.

	1. Dựng HUD nhỏ (tên game / version).
	2. Dựng thanh tiến độ tu luyện, nhận snapshot mỗi giây từ server.
	3. Nút "Bế quan" gửi lệnh lên server (hấp thụ linh khí ×2).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Hud = require(script.Parent:WaitForChild("UI"):WaitForChild("Hud"))
-- Thanh tiến độ dùng CHUNG với preview edit mode (src/shared/UI/CultivationBarView.luau)
local CultivationBarView = require(Shared:WaitForChild("UI"):WaitForChild("CultivationBarView"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local hud = Hud.new(playerGui, Config)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BrigeCultivation"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local bar = CultivationBarView.new(screenGui)

local StateRemote = Net.waitForRemote("CultivationState", 20)
local ActionRemote = Net.waitForRemote("CultivationAction", 20)

if StateRemote then
	StateRemote.OnClientEvent:Connect(function(snapshot)
		if type(snapshot) == "table" then
			bar:setSnapshot(snapshot)
		end
	end)

	bar.onSecludedToggle = function()
		if ActionRemote then
			ActionRemote:FireServer("secluded")
		end
	end

	-- xin snapshot ngay, không chờ vòng tick
	if ActionRemote then
		task.delay(1, function()
			ActionRemote:FireServer("request")
		end)
	end
else
	hud:setStatus("Không thấy RemoteEvent CultivationState — kiểm tra server script.")
end

-- Thông báo chung (giữ nguyên hợp đồng cũ)
local Notify = Net.waitForRemote("Notify", 5)
if Notify then
	Notify.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" then
			hud:setStatus(tostring(payload.message or payload.title or ""))
		end
	end)
end

print("[brige] client đã chạy — thanh tu luyện sẵn sàng.")
