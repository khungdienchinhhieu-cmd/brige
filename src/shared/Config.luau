--!strict
--[[
	Config — cấu hình chung của brige.
	Game thể loại TU TIÊN: cơ chế tu luyện 5 cảnh giới × 9 tầng
	(Luyện Khí → Trúc Cơ → Kim Đan → Nguyên Anh → Hoá Thần).
]]

local Config = {
	GameName = "brige",
	Tagline = "Tu Tiên — Luyện Khí nhập thể",
	Version = "0.2.0",

	-- Tên folder thế giới do bridge/rebuild_world_action.luau dựng trong Workspace.
	WorldName = "BrigeWorld",

	-- Màu chủ đạo (dùng chung cho module thế giới và UI).
	Theme = {
		Background = Color3.fromRGB(14, 17, 24),
		Surface = Color3.fromRGB(28, 32, 42),
		Accent = Color3.fromRGB(96, 165, 250),
		Gold = Color3.fromRGB(251, 191, 36),
		Text = Color3.fromRGB(232, 240, 252),
		Muted = Color3.fromRGB(148, 163, 184),
	},
}

return Config
