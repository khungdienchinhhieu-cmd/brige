--!strict
--[[
	SectGrounds — sân tông môn làm bối cảnh cho hệ tu luyện (FOUNDATION).

	Bố cục:
		• Đài chính giữa có 5 trụ đá, mỗi trụ = 1 cảnh giới, khắc tên + toả sáng màu cảnh giới.
		• Vòng tròn đá (đại trận) quanh đài, phát sáng nhẹ.
		• 4 bậc đá dẫn lên đài từ 4 hướng (nơi người chơi ngồi thiền).
		• Cột cờ + đèn lồng phía nam, biển "Tông Môn".

	Toạ độ ghi trong README mục "Bảng toạ độ".
]]

local Shared = script.Parent.Parent.Parent
local BuildKit = require(Shared.World.BuildKit)
local Config = require(Shared.Config)
local CultivationConfig = require(Shared.CultivationConfig)

local SectGrounds = {}

SectGrounds.FOUNDATION = true

local PLATFORM_RADIUS = 46
local TOWER_RADIUS = 22

function SectGrounds.build(root: Instance, _kit: any)
	local accent = Config.Theme.Accent

	-- Nền đá lớn
	BuildKit.part(root, {
		name = "GroundFloor",
		size = Vector3.new(200, 2, 200),
		cframe = CFrame.new(0, -1, 0),
		color = Color3.fromRGB(34, 39, 50),
		material = Enum.Material.Slate,
	})

	-- Đài tròn chính (dùng Part hình trụ)
	BuildKit.part(root, {
		name = "MainPlatform",
		size = Vector3.new(PLATFORM_RADIUS * 2, 2, PLATFORM_RADIUS * 2),
		cframe = CFrame.new(0, 1, 0),
		color = Color3.fromRGB(52, 60, 76),
		material = Enum.Material.Cobblestone,
		shape = Enum.PartType.Cylinder,
	})

	-- Vòng tròn đá phát sáng quanh đài (đại trận)
	for i = 0, 23 do
		local angle = (i / 24) * math.pi * 2
		BuildKit.part(root, {
			name = "Rune" .. tostring(i),
			size = Vector3.new(4, 0.6, 8),
			cframe = CFrame.new(math.cos(angle) * (PLATFORM_RADIUS - 5), 2.3, math.sin(angle) * (PLATFORM_RADIUS - 5))
				* CFrame.Angles(0, -angle, 0),
			color = accent,
			material = Enum.Material.Neon,
			transparency = 0.45,
		})
	end

	-- 5 trụ cảnh giới: xếp thành vòng cung quanh tâm
	local realmCount = CultivationConfig.maxRealm()
	for index = 1, realmCount do
		local realm = CultivationConfig.getRealm(index)
		local angle = math.pi * (0.15 + (index - 1) * 0.175)
		local x = math.cos(angle) * TOWER_RADIUS
		local z = -math.sin(angle) * TOWER_RADIUS + 8
		local height = 14 + index * 4 -- trụ cao dần theo cảnh giới

		-- thân trụ
		BuildKit.part(root, {
			name = string.format("RealmTower_%d", index),
			size = Vector3.new(7, height, 7),
			cframe = CFrame.new(x, 2 + height / 2, z),
			color = Color3.fromRGB(70, 78, 95),
			material = Enum.Material.Granite,
		})

		-- đỉnh trụ phát sáng màu cảnh giới
		BuildKit.part(root, {
			name = string.format("RealmCrystal_%d", index),
			size = Vector3.new(5, 5, 5),
			cframe = CFrame.new(x, 2 + height + 3, z),
			color = realm.glow,
			material = Enum.Material.Neon,
			transparency = 0.15,
		})

		-- điểm sáng nhỏ phía trên (hào quang)
		local halo = Instance.new("PointLight")
		halo.Color = realm.glow
		halo.Range = 26
		halo.Brightness = 1.6
		local crystal = root:FindFirstChild(string.format("RealmCrystal_%d", index))
		if crystal then
			halo.Parent = crystal
		end

		-- tên cảnh giới khắc trên trụ
		BuildKit.label(
			root,
			string.format("%d · %s", index, realm.name),
			Vector3.new(x, 2 + height + 9, z),
			realm.color
		)
	end

	-- Bục giữa: nơi người chơi ngồi tu luyện
	BuildKit.part(root, {
		name = "MeditationSeat",
		size = Vector3.new(16, 3, 16),
		cframe = CFrame.new(0, 3.5, 0),
		color = Color3.fromRGB(26, 31, 41),
		material = Enum.Material.SmoothPlastic,
	})
	BuildKit.part(root, {
		name = "SeatGlow",
		size = Vector3.new(10, 0.4, 10),
		cframe = CFrame.new(0, 5.2, 0),
		color = accent,
		material = Enum.Material.Neon,
		transparency = 0.35,
	})

	-- 4 bậc dẫn lên đài
	local directions = {
		{ Vector3.new(0, 0, 1), "North" },
		{ Vector3.new(0, 0, -1), "South" },
		{ Vector3.new(1, 0, 0), "East" },
		{ Vector3.new(-1, 0, 0), "West" },
	}
	for _, dir in ipairs(directions) do
		local offset = dir[1] :: Vector3
		for step = 1, 3 do
			local distance = PLATFORM_RADIUS + step * 6
			BuildKit.part(root, {
				name = string.format("Stair_%s_%d", dir[2], step),
				size = Vector3.new(18, 1.6, 8),
				cframe = CFrame.new(offset.X * distance, 1.6 - step * 0.5, offset.Z * distance),
				color = Color3.fromRGB(60, 67, 82),
				material = Enum.Material.Cobblestone,
			})
		end
	end

	-- Cổng tông môn phía nam + đèn lồng
	for side = -1, 1, 2 do
		BuildKit.part(root, {
			name = string.format("GatePillar_%d", side),
			size = Vector3.new(6, 26, 6),
			cframe = CFrame.new(side * 20, 13, 92),
			color = Color3.fromRGB(44, 50, 63),
			material = Enum.Material.Granite,
		})
		BuildKit.part(root, {
			name = string.format("Lantern_%d", side),
			size = Vector3.new(4, 4, 4),
			cframe = CFrame.new(side * 20, 28, 92),
			color = Color3.fromRGB(251, 191, 36),
			material = Enum.Material.Neon,
			transparency = 0.2,
		})
	end
	BuildKit.part(root, {
		name = "GateBeam",
		size = Vector3.new(48, 4, 7),
		cframe = CFrame.new(0, 28, 92),
		color = Color3.fromRGB(34, 39, 50),
		material = Enum.Material.WoodPlanks,
	})
	BuildKit.label(root, "TÔNG MÔN", Vector3.new(0, 36, 92), Color3.fromRGB(251, 191, 36))
end

return SectGrounds
