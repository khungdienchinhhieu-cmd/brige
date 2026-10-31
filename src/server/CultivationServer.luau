--!strict
--[[
	CultivationServer — giữ trạng thái tu luyện từng người chơi, chạy vòng tick,
	phát snapshot cho client vẽ thanh tiến độ.

	Remote:
		"CultivationState"  (RemoteEvent, server → client)  snapshot mỗi giây
		"CultivationAction" (RemoteEvent, client → server)  "secluded" | "request"
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CultivationConfig = require(Shared:WaitForChild("CultivationConfig"))
local Cultivation = require(Shared:WaitForChild("Cultivation"))
local Net = require(Shared:WaitForChild("Net"))

local CultivationServer = {}

local StateRemote = Net.createRemote("CultivationState")
local ActionRemote = Net.createRemote("CultivationAction")

local states: { [Player]: Cultivation.State } = {}

local function broadcast(player: Player)
	local state = states[player]
	if not state then
		return
	end
	StateRemote:FireClient(player, Cultivation.snapshot(state))
end

local function onAction(player: Player, action: any)
	local state = states[player]
	if not state then
		return
	end
	if action == "secluded" then
		Cultivation.setSecluded(state, not state.secluded)
	elseif action == "request" then
		broadcast(player)
	end
end

local function onPlayerAdded(player: Player)
	states[player] = Cultivation.newState(1, 1)
	-- chờ client dựng UI xong rồi mới gửi
	task.delay(1, function()
		if player.Parent then
			broadcast(player)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	states[player] = nil
end

function CultivationServer.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	ActionRemote.OnServerEvent:Connect(onAction)

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	-- Một vòng tick cho tất cả người chơi.
	task.spawn(function()
		while true do
			task.wait(CultivationConfig.TickInterval)
			for player, state in pairs(states) do
				if player.Parent then
					local result = Cultivation.tick(state, CultivationConfig.TickInterval)
					if result.stagesGained > 0 then
						local realm = CultivationConfig.getRealm(state.realm)
						print(
							string.format(
								"[brige] %s đột phá → %s · Tầng %d%s",
								player.Name,
								realm.name,
								state.stage,
								if result.realmsGained > 0 then "  (cảnh giới mới!)" else ""
							)
						)
					end
					broadcast(player)
				else
					states[player] = nil
				end
			end
		end
	end)

	print(string.format("[brige] hệ tu luyện sẵn sàng — %d cảnh giới × %d tầng", CultivationConfig.maxRealm(), CultivationConfig.maxStage()))
end

return CultivationServer
