--!strict
--[[
	Cultivation — LOGIC THUẦN, không đụng Instance.

	Nhờ vậy chạy được cả ở server (thật) và ở Node (tools/cultivation_sim) để kiểm
	số liệu trước khi mở Studio. Mọi hàm nhận/trả `State` thuần dữ liệu.

	QUY ƯỚC: file này (và CultivationConfig) cố tình KHÔNG dùng cú pháp riêng của Luau
	(if-then-else dạng biểu thức, `continue`, generic <T>…) để tools/cultivation_sim
	có thể dịch thẳng sang JS và chạy thử ngoài Roblox. Thêm logic thì giữ luật này.

	Luật:
		• Mỗi giây hấp thụ `rate × multiplier` khí.
		• Đầy thanh → tự đột phá lên tầng kế (bế quan ×2 tốc độ).
		• Hết tầng 9 → sang cảnh giới mới, tầng 1, thanh reset.
		• Hoá Thần tầng 9 = đỉnh, khí dừng ở mức đầy.
]]

local CultivationConfig = require(script.Parent.CultivationConfig)

export type State = {
	realm: number,
	stage: number,
	qi: number,
	secluded: boolean,
	totalQi: number,
	breakthroughs: number,
}

export type Snapshot = {
	realm: number,
	stage: number,
	realmName: string,
	realmTitle: string,
	realmDescription: string,
	stageLabel: string,
	qi: number,
	required: number,
	progress: number,
	rate: number,
	secluded: boolean,
	isMax: boolean,
	totalQi: number,
	breakthroughs: number,
	realmColor: Color3,
	realmGlow: Color3,
}

export type TickResult = {
	stagesGained: number,
	realmsGained: number,
	newRealm: number,
	newStage: number,
}

local Cultivation = {}

function Cultivation.newState(realm, stage)
	local state = {
		realm = math.clamp(realm or 1, 1, CultivationConfig.maxRealm()),
		stage = math.clamp(stage or 1, 1, CultivationConfig.maxStage()),
		qi = 0,
		secluded = false,
		totalQi = 0,
		breakthroughs = 0,
	}
	return state
end

function Cultivation.isMax(state)
	local atLastRealm = state.realm >= CultivationConfig.maxRealm()
	local atLastStage = state.stage >= CultivationConfig.maxStage()
	local result = atLastRealm and atLastStage
	return result
end

function Cultivation.requirement(state)
	local need = CultivationConfig.stageRequirement(state.realm, state.stage)
	if need ~= nil then
		return need
	end
	-- đỉnh: dùng yêu cầu của tầng cuối để thanh luôn đầy
	local fallback = CultivationConfig.stageRequirement(
		CultivationConfig.maxRealm(),
		CultivationConfig.maxStage()
	)
	if fallback == nil then
		return 1
	end
	return fallback
end

function Cultivation.rate(state)
	local base = CultivationConfig.cultivationRate(state.realm)
	if state.secluded then
		return base * CultivationConfig.SecludedMultiplier
	end
	return base
end

function Cultivation.tick(state, deltaSeconds)
	local result = {
		stagesGained = 0,
		realmsGained = 0,
		newRealm = state.realm,
		newStage = state.stage,
	}

	if Cultivation.isMax(state) then
		state.qi = Cultivation.requirement(state)
		return result
	end

	local delta = deltaSeconds
	if delta == nil then
		delta = CultivationConfig.TickInterval
	end

	local gained = Cultivation.rate(state) * delta
	state.qi = state.qi + gained
	state.totalQi = state.totalQi + gained

	local guard = 0
	while state.qi >= Cultivation.requirement(state) and not Cultivation.isMax(state) and guard < 100 do
		guard = guard + 1
		local need = Cultivation.requirement(state)
		state.qi = state.qi - need
		state.breakthroughs = state.breakthroughs + 1
		result.stagesGained = result.stagesGained + 1

		if state.stage < CultivationConfig.maxStage() then
			state.stage = state.stage + 1
		else
			state.realm = state.realm + 1
			state.stage = 1
			result.realmsGained = result.realmsGained + 1
		end
	end

	if Cultivation.isMax(state) then
		state.qi = Cultivation.requirement(state)
	end

	result.newRealm = state.realm
	result.newStage = state.stage
	return result
end

function Cultivation.setSecluded(state, value)
	state.secluded = value
end

function Cultivation.stageLabel(state)
	local realm = CultivationConfig.getRealm(state.realm)
	local label = string.format("%s · Tầng %d", realm.name, state.stage)
	return label
end

function Cultivation.snapshot(state)
	local realm = CultivationConfig.getRealm(state.realm)
	local required = Cultivation.requirement(state)
	local maxed = Cultivation.isMax(state)

	local progress = state.qi / required
	if maxed then
		progress = 1
	end
	progress = math.clamp(progress, 0, 1)

	local snapshot = {
		realm = state.realm,
		stage = state.stage,
		realmName = realm.name,
		realmTitle = realm.title,
		realmDescription = realm.description,
		stageLabel = Cultivation.stageLabel(state),
		qi = math.floor(state.qi),
		required = required,
		progress = progress,
		rate = Cultivation.rate(state),
		secluded = state.secluded,
		isMax = maxed,
		totalQi = math.floor(state.totalQi),
		breakthroughs = state.breakthroughs,
		realmColor = realm.color,
		realmGlow = realm.glow,
	}
	return snapshot
end

--[[
	Dựng lại State từ một snapshot (vd: gói preview trong studio-sync.json).
	Dùng để client/preview chạy ĐÚNG cùng một logic tick, không viết lại công thức.
	`secluded`/`totalQi`/`breakthroughs` nhận giá trị mặc định hợp lý.
]]
function Cultivation.stateFromSnapshot(snapshot)
	local state = Cultivation.newState(snapshot.realm, snapshot.stage)
	state.qi = snapshot.qi or 0
	return state
end

--[[
	State phỏng vấn cho bản preview: trải đều 45 tầng để xem hình thức từng cảnh giới.
	`index` chạy từ 0 → 44 (0 = Luyện Khí tầng 1, 44 = Hoá Thần tầng 9).
]]
function Cultivation.previewStateAt(index)
	local perRealm = CultivationConfig.StagesPerRealm
	local total = CultivationConfig.StagesPerRealm * CultivationConfig.maxRealm()
	local clamped = math.clamp(index, 0, total - 1)
	local realm = math.floor(clamped / perRealm) + 1
	local stage = clamped % perRealm + 1
	local state = Cultivation.newState(realm, stage)
	state.qi = Cultivation.requirement(state) * 0.55
	return state
end

return Cultivation
