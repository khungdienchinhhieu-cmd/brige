--!strict
--[[
	SyncYard — module dựng thế giới mẫu (FOUNDATION).
	Sân thử có lưới ô + cột mốc để nhìn là biết pipeline đồng bộ đã chạy bản mới.

	Hợp đồng: module.build(root, kit) được rebuild_world_action.luau gọi.
]]

local Shared = script.Parent.Parent.Parent
local BuildKit = require(Shared.World.BuildKit)
local Config = require(Shared.Config)

local SyncYard = {}

SyncYard.FOUNDATION = true

function SyncYard.build(root: Instance, kit: any)
	local size = Config.YardSize
	local tile = Config.YardTileSize
	local half = size / 2

	-- Sàn chính.
	BuildKit.part(root, {
		name = "YardFloor",
		size = Vector3.new(size, 2, size),
		cframe = CFrame.new(0, 0, 0),
		color = Color3.fromRGB(42, 48, 62),
		material = Enum.Material.Slate,
	})

	-- Lưới ô sáng màu để thấy rõ tỉ lệ.
	local count = math.floor(size / tile)
	for ix = 0, count - 1 do
		for iz = 0, count - 1 do
			if (ix + iz) % 2 == 0 then
				local x = -half + tile / 2 + ix * tile
				local z = -half + tile / 2 + iz * tile
				BuildKit.part(root, {
					name = string.format("Tile_%d_%d", ix, iz),
					size = Vector3.new(tile - 1, 0.4, tile - 1),
					cframe = CFrame.new(x, 1.1, z),
					color = Color3.fromRGB(30, 36, 48),
					material = Enum.Material.SmoothPlastic,
				})
			end
		end
	end

	-- Bốn cột mốc ở góc sân.
	local corners = {
		Vector3.new(-half + 6, 12, -half + 6),
		Vector3.new(half - 6, 12, -half + 6),
		Vector3.new(-half + 6, 12, half - 6),
		Vector3.new(half - 6, 12, half - 6),
	}
	for index, position in ipairs(corners) do
		BuildKit.part(root, {
			name = "Pylon" .. tostring(index),
			size = Vector3.new(4, 24, 4),
			cframe = CFrame.new(position),
			color = Config.Theme.Accent,
			material = Enum.Material.Neon,
		})
	end

	-- Bục giữa + biển tên game.
	BuildKit.part(root, {
		name = "CenterPlinth",
		size = Vector3.new(36, 3, 36),
		cframe = CFrame.new(0, 2.5, 0),
		color = Color3.fromRGB(24, 28, 38),
		material = Enum.Material.SmoothPlastic,
	})
	BuildKit.label(root, Config.Tagline, Vector3.new(0, 16, 0), Config.Theme.Accent)

	-- Cổng vào phía nam.
	BuildKit.part(root, {
		name = "GateLeft",
		size = Vector3.new(4, 20, 4),
		cframe = CFrame.new(-14, 10, half - 4),
		color = Color3.fromRGB(90, 100, 120),
	})
	BuildKit.part(root, {
		name = "GateRight",
		size = Vector3.new(4, 20, 4),
		cframe = CFrame.new(14, 10, half - 4),
		color = Color3.fromRGB(90, 100, 120),
	})
	BuildKit.part(root, {
		name = "GateBeam",
		size = Vector3.new(32, 3, 4),
		cframe = CFrame.new(0, 21.5, half - 4),
		color = Config.Theme.Accent,
		material = Enum.Material.Metal,
	})
end

return SyncYard
