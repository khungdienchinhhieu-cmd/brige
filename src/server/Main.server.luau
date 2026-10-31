--!strict
--[[
	Server — điểm vào phía server.
	1. Tạo remote dùng chung (Net.createRemote).
	2. Chờ module thế giới do rebuild_world_action.luau dựng.
	3. Chào người chơi mới bằng thông tin sync (để thấy ngay pipeline đã chạy).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Notify = Net.createRemote("Notify")

print(string.format("[brige] server khởi động — %s v%s", Config.GameName, Config.Version))

-- Chờ thế giới được dựng (tối đa 20s) rồi báo số part cho dễ kiểm tra.
task.spawn(function()
	local deadline = os.clock() + 20
	repeat
		task.wait(0.5)
	until workspace:FindFirstChild(Config.WorldName) ~= nil or os.clock() > deadline

	local world = workspace:FindFirstChild(Config.WorldName)
	if world then
		local parts = world:GetChildren()
		print(string.format("[brige] thế giới '%s' sẵn sàng — %d part", world.Name, #parts))
	else
		warn("[brige] chưa thấy thế giới trong Workspace — kiểm tra tác vụ dựng lại trong studio-sync.json.")
	end
end)

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function()
		task.wait(1)
		Notify:FireClient(player, {
			title = Config.GameName,
			message = string.format("%s · v%s", Config.Tagline, Config.Version),
		})
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
