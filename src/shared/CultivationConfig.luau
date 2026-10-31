--!strict
--[[
	CultivationConfig — toàn bộ số liệu tu luyện nằm ở ĐÂY, không rải trong code.

	5 cảnh giới × 9 tầng = 45 tầng (như tu tiên cổ điển).

	THIẾT KẾ THEO THỜI GIAN (không phải theo số khí), vì người chơi cảm nhận thời gian:
		thời gian 1 tầng = StageSeconds × GrowthPerStage^(tầng-1) × RealmTimeMultiplier^(cảnh-1)
	Suy ra:
		• trong một cảnh giới: tầng 9 lâu hơn tầng 1 khoảng ×2.5  (mỗi tầng ×1.12)
		• qua cảnh giới mới  : chậm hơn ×2.8 và tầng 1 cảnh mới VẪN khó hơn tầng 9 cảnh cũ
		  (điều kiện: RealmTimeMultiplier > GrowthPerStage^8 = 2.48 → chọn 2.8)
		• số khí cần = thời gian × tốc độ hấp thụ (tốc độ tăng ×2 mỗi cảnh giới)

	Thời gian tham chiếu (tu luyện liên tục, chưa bế quan):
		Luyện Khí 1.5→3.7 phút/tầng, cả cảnh 0.4 giờ
		Trúc Cơ   4.2→10.4 phút,      1.0 giờ
		Kim Đan   11.8→29.1 phút,     2.9 giờ
		Nguyên Anh 32.9→81.5 phút,    8.1 giờ
		Hoá Thần  92.2→228.3 phút,   22.7 giờ
		TỔNG ≈ 35 giờ (bế quan ×2 → ≈ 17.6 giờ)
	Kiểm bằng: node tools/cultivation_sim/run.mjs

	QUY ƯỚC: cùng với Cultivation.luau, file này chỉ dùng cú pháp Lua 5.3-compatible
	(không if-then-else biểu thức, không continue) để tools/cultivation_sim dịch sang
	JS chạy thử ngoài Roblox.
]]

local CultivationConfig = {}

CultivationConfig.StagesPerRealm = 9
CultivationConfig.TickInterval = 1
CultivationConfig.SecludedMultiplier = 2

-- Thời gian & độ khó
CultivationConfig.StageSeconds = 90
CultivationConfig.GrowthPerStage = 1.12
CultivationConfig.RealmTimeMultiplier = 2.8

-- Tốc độ hấp thụ linh khí (khí/giây)
CultivationConfig.BaseRate = 15
CultivationConfig.RealmRateMultiplier = 2.0

export type Realm = {
	name: string,
	title: string,
	description: string,
	color: Color3,
	glow: Color3,
}

CultivationConfig.Realms = {
	{
		name = "Luyện Khí",
		title = "Luyện Khí Cảnh",
		description = "Dẫn linh khí nhập thể, mở kinh mạch. Bước đầu tiên của đạo trường sinh.",
		color = Color3.fromRGB(96, 165, 250),
		glow = Color3.fromRGB(56, 189, 248),
	},
	{
		name = "Trúc Cơ",
		title = "Trúc Cơ Cảnh",
		description = "Linh khí hoá dịch, xây nền đạo cơ. Thân thể bắt đầu thoát phàm.",
		color = Color3.fromRGB(52, 211, 153),
		glow = Color3.fromRGB(16, 185, 129),
	},
	{
		name = "Kim Đan",
		title = "Kim Đan Cảnh",
		description = "Linh khí kết đan, đan điền toả sáng. Linh lực dồi dào, thọ nguyên tăng.",
		color = Color3.fromRGB(251, 191, 36),
		glow = Color3.fromRGB(245, 158, 11),
	},
	{
		name = "Nguyên Anh",
		title = "Nguyên Anh Cảnh",
		description = "Kim đan phá xác, nguyên anh xuất khiếu. Thần thức quét ngàn dặm.",
		color = Color3.fromRGB(167, 139, 250),
		glow = Color3.fromRGB(139, 92, 246),
	},
	{
		name = "Hoá Thần",
		title = "Hoá Thần Cảnh",
		description = "Nguyên anh hoá thần, thần hồn bất diệt. Gần chạm ngưỡng phi thăng.",
		color = Color3.fromRGB(248, 113, 113),
		glow = Color3.fromRGB(239, 68, 68),
	},
}

-- Tốc độ hấp thụ linh khí (khí/giây) ở cảnh giới hiện tại.
function CultivationConfig.cultivationRate(realm)
	local clamped = math.clamp(realm, 1, CultivationConfig.Realms and #CultivationConfig.Realms or 1)
	local base = CultivationConfig.BaseRate * CultivationConfig.RealmRateMultiplier ^ (clamped - 1)
	return base
end

-- Thời gian (giây) để vượt 1 tầng — dùng cho tài liệu và cho tools kiểm tra.
function CultivationConfig.stageSeconds(realm, stage)
	local clampedRealm = math.clamp(realm, 1, #CultivationConfig.Realms)
	local time = CultivationConfig.StageSeconds
		* CultivationConfig.GrowthPerStage ^ (stage - 1)
		* CultivationConfig.RealmTimeMultiplier ^ (clampedRealm - 1)
	return time
end

-- Khí cần để vượt `stage` của `realm` (1-based). Nil nếu ngoài phạm vi.
function CultivationConfig.stageRequirement(realm, stage)
	if realm < 1 or realm > #CultivationConfig.Realms then
		return nil
	end
	if stage < 1 or stage > CultivationConfig.StagesPerRealm then
		return nil
	end
	local seconds = CultivationConfig.stageSeconds(realm, stage)
	local rate = CultivationConfig.cultivationRate(realm)
	local need = math.floor(seconds * rate + 0.5)
	return need
end

function CultivationConfig.getRealm(realm)
	local clamped = math.clamp(realm, 1, #CultivationConfig.Realms)
	local realmData = CultivationConfig.Realms[clamped]
	return realmData
end

function CultivationConfig.maxStage()
	return CultivationConfig.StagesPerRealm
end

function CultivationConfig.maxRealm()
	return #CultivationConfig.Realms
end

return CultivationConfig
