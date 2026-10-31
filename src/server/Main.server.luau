--!strict
--[[
	Server — điểm vào phía server.

	1. Tạo remote dùng chung (Net).
	2. Khởi động hệ tu luyện (CultivationServer).
	3. Chờ module thế giới do rebuild_world_action.luau dựng.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local CultivationServer = require(script.Parent:WaitForChild("CultivationServer"))

-- Remote dùng cho thông báo chung (giữ nguyên hợp đồng cũ).
Net.createRemote("Notify")

print(string.format("[brige] server khởi động — %s v%s", Config.GameName, Config.Version))

CultivationServer.start()

-- Chờ thế giới được dựng (tối đa 20s) rồi báo số part cho dễ kiểm tra.
task.spawn(function()
	local deadline = os.clock() + 20
	repeat
		task.wait(0.5)
	until workspace:FindFirstChild(Config.WorldName) ~= nil or os.clock() > deadline

	local world = workspace:FindFirstChild(Config.WorldName)
	if world then
		local children = world:GetChildren()
		print(string.format("[brige] thế giới '%s' sẵn sàng — %d part", world.Name, #children))
	else
		warn("[brige] chưa thấy thế giới trong Workspace — kiểm tra tác vụ dựng lại trong studio-sync.json.")
	end
end)
