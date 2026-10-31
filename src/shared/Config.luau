--!strict
--[[
	Config — cấu hình chung của brige.
	Thể loại game CHƯA CHỐT: hiện repo dựng "Sync Yard", một sân thử để kiểm tra
	đường ống Rojo → studio-sync.json → Studio trước khi chọn hướng game thật.
]]

local Config = {
	GameName = "brige",
	Tagline = "Sync Yard — sân thử đồng bộ trực tiếp",
	Version = "0.1.0",

	-- Tên folder thế giới do bridge/rebuild_world_action.luau dựng trong Workspace.
	WorldName = "BrigeWorld",

	-- Kích thước sân thử (studs).
	YardSize = 240,
	YardTileSize = 24,

	-- Màu chủ đạo (dùng chung cho module thế giới và UI).
	Theme = {
		Background = Color3.fromRGB(18, 21, 28),
		Surface = Color3.fromRGB(28, 32, 42),
		Accent = Color3.fromRGB(56, 189, 248),
		Text = Color3.fromRGB(232, 240, 252),
		Muted = Color3.fromRGB(148, 163, 184),
	},
}

return Config
