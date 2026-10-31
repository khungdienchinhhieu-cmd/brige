--!strict
--[[
	preview_cultivation_action.luau — XEM NGAY thanh tu luyện TRONG STUDIO EDIT MODE.
	Không cần bấm Play, không cần mở client.

	publish.mjs tự đính kèm file này vào studio-sync.json sau mỗi lần publish, nên:
		sửa src/ → publish → dán lệnh Command Bar → Studio hiện thanh tiến độ + sân tông môn.

	Nó cũng mô phỏng tu luyện ngay trong edit mode: khí tăng dần, tự đột phá, chạy hết
	45 tầng trong ~30 giây (tua nhanh ×2400) để bạn thấy được cả 5 cảnh giới đổi màu.
	Bấm nút "Tua nhanh" để bật/tắt, nút "Về tầng 1" để xem lại từ đầu.

	Chỉ ảnh hưởng Studio edit mode — Play thật vẫn do server/client lo.
]]

local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PREVIEW_NAME = "BrigeCultivationPreview"
local SPEED = 2400 -- giây tu luyện mỗi giây thật

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
-- GIAO DIỆN PREVIEW
-- ============================================================================
local gui = Instance.new("ScreenGui")
gui.Name = PREVIEW_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = CoreGui

local bar = BarView.new(gui)

-- nhãn nhỏ cho biết đây là preview trong edit mode + tốc độ tua
local tag = Instance.new("TextLabel")
tag.Name = "PreviewTag"
tag.AnchorPoint = Vector2.new(0.5, 1)
tag.Position = UDim2.new(0.5, 0, 1, -120)
tag.Size = UDim2.fromOffset(460, 18)
tag.BackgroundTransparency = 1
tag.Font = Enum.Font.Code
tag.TextSize = 11
tag.TextColor3 = Color3.fromRGB(148, 163, 184)
tag.Text = string.format("PREVIEW edit mode · tua ×%d · chỉ để xem giao diện", SPEED)
tag.Parent = gui

-- nút điều khiển preview
local function makeButton(text: string, offsetX: number): TextButton
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, offsetX, 1, -140)
	button.Size = UDim2.fromOffset(120, 24)
	button.BackgroundColor3 = Color3.fromRGB(42, 48, 64)
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 11
	button.TextColor3 = Color3.fromRGB(220, 228, 245)
	button.Text = text
	button.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = button
	return button
end

local speedBtn = makeButton("Tạm dừng tua", -66)
local resetBtn = makeButton("Về tầng 1", 66)

-- ============================================================================
-- MÔ PHỎNG TU LUYỆN NGAY TRONG EDIT MODE
-- ============================================================================
local state = Cultivation.newState(1, 1)
local running = true

bar.onSecludedToggle = function()
	Cultivation.setSecluded(state, not state.secluded)
	bar:setSnapshot(Cultivation.snapshot(state))
end

speedBtn.MouseButton1Click:Connect(function()
	running = not running
	speedBtn.Text = if running then "Tạm dừng tua" else "Tiếp tục tua"
end)

resetBtn.MouseButton1Click:Connect(function()
	state = Cultivation.newState(1, 1)
	bar:setSnapshot(Cultivation.snapshot(state))
end)

-- Đặt bi của người chơi lên bệ ngồi giữa đài để thấy tỉ lệ (không bắt buộc).
local function movePreviewCamera()
	local world = Workspace:FindFirstChild("BrigeWorld")
	if not world then
		return
	end
	local seat = world:FindFirstChild("MeditationSeat")
	local camera = Workspace.CurrentCamera
	if seat and camera then
		camera.CFrame = CFrame.lookAt(seat.Position + Vector3.new(0, 26, 62), seat.Position + Vector3.new(0, 6, 0))
	end
end
task.delay(0.3, movePreviewCamera)

-- vòng cập nhật: chỉ chạy trong edit mode để không tranh việc với server khi Play
local heartbeat = RunService.Heartbeat:Connect(function(dt)
	if not gui.Parent then
		return
	end
	if not RunService:IsEdit() then
		return
	end
	if running then
		Cultivation.tick(state, dt * SPEED)
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

bar:setSnapshot(Cultivation.snapshot(state))

print("[brige preview] ✅ Đang hiện thanh tu luyện trong edit mode (không cần Play).")
print(string.format("[brige preview] Mô phỏng tua ×%d — cả 45 tầng trong khoảng %d giây.", SPEED, 31 * 3600 / SPEED))
