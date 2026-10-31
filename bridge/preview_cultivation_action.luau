--!strict
--[[
	preview_cultivation_action.luau — XEM UI TU LUYỆN NGAY TRONG STUDIO EDIT MODE.
	Không cần bấm Play, không cần mở client, KHÔNG dựng/xoá bất kỳ thứ gì trong Workspace.

	Chạy ở TỐC ĐỘ THẬT (1 giây = 1 giây) nên thanh chạy êm, không giật.

	Hai nguồn dữ liệu:
		• PREVIEW_MODEL = "loop"  → tự mô phỏng tu luyện (mượt, tốc độ thật)
		• PREVIEW_MODEL = "snap"  → publish.mjs ghi đè bằng state thật (realm/stage/qi)
		  để xem đúng cảnh giới đang muốn chỉnh

	Nút bấm:
		[ Tầng trước ] [ Tầng sau ]  → nhảy xem hình thức từng cảnh giới (không đổi dữ liệu)
		[ Bế quan ×2 ]               → bật/tắt tốc độ
		[ Tốc độ: ×1 ]               → ×1 (thật) / ×10 (xem nhanh) / ×60
]]

local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PREVIEW_NAME = "BrigeCultivationPreview"

-- publish.mjs thay 2 dòng dưới bằng state thật khi publish
local PREVIEW_MODEL = "loop"
local PREVIEW_SNAPSHOT = nil

-- Dọn bản preview cũ (chạy lại lệnh nhiều lần không bị chồng)
local existing = CoreGui:FindFirstChild(PREVIEW_NAME)
if existing then
	existing:Destroy()
end
if _G.__BRIGE_PREVIEW_CLEANUP then
	pcall(_G.__BRIGE_PREVIEW_CLEANUP)
	_G.__BRIGE_PREVIEW_CLEANUP = nil
end

local shared = ReplicatedStorage:WaitForChild("Shared", 30)
if not shared then
	warn("[brige preview] Không thấy ReplicatedStorage.Shared — gói sync chưa được áp?")
	return
end

local CultivationConfig = require(shared:WaitForChild("CultivationConfig"))
local Cultivation = require(shared:WaitForChild("Cultivation"))
local BarView = require(shared:WaitForChild("UI"):WaitForChild("CultivationBarView"))

-- ============================================================================
-- GIAO DIỆN PREVIEW (chỉ UI, không tạo/xoá part nào)
-- ============================================================================
local gui = Instance.new("ScreenGui")
gui.Name = PREVIEW_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = CoreGui

local bar = BarView.new(gui, { autoFade = false })

-- nhãn nhỏ
local tag = Instance.new("TextLabel")
tag.Name = "PreviewTag"
tag.AnchorPoint = Vector2.new(0.5, 1)
tag.Position = UDim2.new(0.5, 0, 1, -134)
tag.Size = UDim2.fromOffset(520, 18)
tag.BackgroundTransparency = 1
tag.Font = Enum.Font.Code
tag.TextSize = 11
tag.TextColor3 = Color3.fromRGB(120, 132, 150)
tag.Text = "PREVIEW edit mode · không dựng map · tốc độ thật"
tag.Parent = gui

local function makeButton(text: string, offsetX: number, width: number?): TextButton
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, offsetX, 1, -154)
	button.Size = UDim2.fromOffset(width or 118, 24)
	button.BackgroundColor3 = Color3.fromRGB(28, 33, 44)
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 11
	button.TextColor3 = Color3.fromRGB(210, 220, 235)
	button.Text = text
	button.AutoButtonColor = false
	button.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = button
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(70, 82, 104)
	s.Thickness = 1
	s.Transparency = 0.4
	s.Parent = button
	return button
end

local prevBtn = makeButton("◀ Tầng trước", -192)
local nextBtn = makeButton("Tầng sau ▶", -64)
local speedBtn = makeButton("Tốc độ ×1", 64)
local loopBtn = makeButton("Tự chạy: BẬT", 192)

-- ============================================================================
-- TRẠNG THÁI
-- ============================================================================
local totalStages = CultivationConfig.StagesPerRealm * CultivationConfig.maxRealm()
local cursor = 0 -- vị trí đang xem (0..totalStages-1)
local state = Cultivation.newState(1, 1)
local speeds = { 1, 10, 60 }
local speedIndex = 1
local autoRun = true

if PREVIEW_MODEL == "snap" and type(PREVIEW_SNAPSHOT) == "table" then
	-- state thật do publish ghi vào: hiện đúng cảnh giới, không tự chạy
	state = Cultivation.stateFromSnapshot(PREVIEW_SNAPSHOT)
	cursor = (state.realm - 1) * CultivationConfig.StagesPerRealm + (state.stage - 1)
	autoRun = false
	tag.Text = "PREVIEW edit mode · state thật từ studio-sync.json · không dựng map"
end

local function refresh()
	bar:setSnapshot(Cultivation.snapshot(state))
	loopBtn.Text = if autoRun then "Tự chạy: BẬT" else "Tự chạy: TẮT"
	speedBtn.Text = string.format("Tốc độ ×%d", speeds[speedIndex])
end

local function jumpTo(index: number)
	cursor = math.clamp(index, 0, totalStages - 1)
	state = Cultivation.previewStateAt(cursor)
	refresh()
end

prevBtn.MouseButton1Click:Connect(function()
	autoRun = false
	jumpTo(cursor - 1)
end)

nextBtn.MouseButton1Click:Connect(function()
	autoRun = false
	jumpTo(cursor + 1)
end)

speedBtn.MouseButton1Click:Connect(function()
	speedIndex = speedIndex % #speeds + 1
	refresh()
end)

loopBtn.MouseButton1Click:Connect(function()
	autoRun = not autoRun
	refresh()
end)

bar.onSecludedToggle = function()
	Cultivation.setSecluded(state, not state.secluded)
	refresh()
end

-- ============================================================================
-- VÒNG CẬP NHẬT — chỉ chạy trong edit mode, tốc độ thật
-- ============================================================================
local heartbeat = RunService.Heartbeat:Connect(function(dt)
	if not gui.Parent then
		return
	end
	if not RunService:IsEdit() then
		return
	end
	if autoRun then
		local speed = speeds[speedIndex]
		Cultivation.tick(state, math.min(dt, 0.1) * speed)
		cursor = (state.realm - 1) * CultivationConfig.StagesPerRealm + (state.stage - 1)
	end
	bar:setSnapshot(Cultivation.snapshot(state))
end)

_G.__BRIGE_PREVIEW_CLEANUP = function()
	if heartbeat then
		heartbeat:Disconnect()
	end
	if gui then
		gui:Destroy()
	end
end

jumpTo(cursor)

print("[brige preview] ✅ Thanh tu luyện đang hiện trong edit mode (không cần Play, không dựng map).")
print("[brige preview] Dùng nút ◀ ▶ để xem nhanh cảnh giới · Tốc độ ×1/×10/×60 · Tự chạy BẬT/TẮT.")
