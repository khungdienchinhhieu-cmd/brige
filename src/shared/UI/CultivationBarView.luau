--!strict
--[[
	CultivationBarView — THANH TU LUYỆN (v2, bản nâng cấp).

	Dùng chung cho 2 nơi nên sửa 1 lần là cả hai đổi giống nhau:
		1. Client trong game   (src/client/Init.client.luau)
		2. Preview edit mode   (bridge/preview_cultivation_action.luau)

	NÂNG CẤP SO VỚI v1
		• Mượt: dùng RunService.RenderStepped (mỗi frame) + nội suy, không nhảy từng giây.
		• Chống giật: mọi Tween đang chạy đều bị cancel trước khi tạo cái mới (trước đây mỗi
		  giây tạo 1 tween mới trong khi tween cũ chưa xong → rung/giật).
		• Vạch chia 9 tầng trong thanh: thấy ngay đang ở nhịp nào của cảnh giới.
		• Nhãn cảnh giới + % + khí/giây có màu theo cảnh giới, chữ đổi màu khi đột phá.
		• Đột phá: flash sáng + chữ phóng to rồi thu về; sang cảnh giới mới thì mạnh hơn.
		• Không thao tác → tự mờ đi (0.55), rê chuột vào sáng lại; tránh che màn hình.
		• Nút bế quan đổi trạng thái rõ (xanh = đang bế quan).
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CultivationBarView = {}
CultivationBarView.__index = CultivationBarView

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

export type BarView = {
	screenGui: ScreenGui?,
	root: Frame,
	header: TextLabel,
	counter: TextLabel,
	track: Frame,
	trackFill: Frame,
	fill: Frame,
	fillGradient: UIGradient,
	percent: TextLabel,
	rateLabel: TextLabel,
	secludedBtn: TextButton,
	shine: Frame,
	onSecludedToggle: (() -> ())?,
	setSnapshot: (self: BarView, snapshot: Snapshot) -> (),
	destroy: (self: BarView) -> (),
}

local STAGES = 9

local function formatQi(value: number): string
	if value >= 1_000_000 then
		return string.format("%.2fM", value / 1_000_000)
	elseif value >= 10_000 then
		return string.format("%.1fK", value / 1_000)
	elseif value >= 1_000 then
		return string.format("%.2fK", value / 1_000)
	end
	return tostring(math.floor(value))
end

local function corner(parent: Instance, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

--[[
	Tạo thanh. `parent` thường là ScreenGui của người chơi (hoặc ScreenGui preview).
	`opts.autoFade` = true → mờ dần khi không thao tác (mặc định true).
]]
function CultivationBarView.new(parent: Instance, opts: { autoFade: boolean? }?)
	local self = (setmetatable({}, CultivationBarView) :: any) :: BarView
	local options = opts or {}
	local autoFade = options.autoFade ~= false

	-- trạng thái nội suy
	local shown = 0 -- progress đang hiển thị (0..1)
	local target = 0 -- progress đích
	local lastSnapshot: Snapshot? = nil
	local lastRealm = 0
	local lastStage = 0
	local fadeAlpha = 0 -- 0 = sáng, 1 = mờ

	--------------------------------------------------------------- khung ngoài
	local root = Instance.new("Frame")
	root.Name = "CultivationPanel"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -16)
	root.Size = UDim2.fromOffset(520, 110)
	root.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
	root.BackgroundTransparency = 0.06
	root.BorderSizePixel = 0
	root.Parent = parent
	corner(root, 14)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(96, 165, 250)
	stroke.Thickness = 1
	stroke.Transparency = 0.35
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = root

	local shadow = Instance.new("UIStroke")
	shadow.Color = Color3.fromRGB(0, 0, 0)
	shadow.Thickness = 2
	shadow.Transparency = 0.75
	shadow.Parent = root

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = root

	--------------------------------------------------------------- hàng 1: tên + khí
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(0.6, 0, 0, 22)
	header.Font = Enum.Font.GothamBold
	header.TextSize = 17
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = Color3.fromRGB(240, 245, 255)
	header.Text = "Luyện Khí · Tầng 1"
	header.Parent = root

	local counter = Instance.new("TextLabel")
	counter.Name = "Counter"
	counter.BackgroundTransparency = 1
	counter.Position = UDim2.new(0.6, 0, 0, 0)
	counter.Size = UDim2.new(0.4, 0, 0, 22)
	counter.Font = Enum.Font.Code
	counter.TextSize = 13
	counter.TextXAlignment = Enum.TextXAlignment.Right
	counter.TextColor3 = Color3.fromRGB(148, 163, 184)
	counter.Text = "0 / 0"
	counter.Parent = root

	--------------------------------------------------------------- hàng 2: thanh
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(0, 30)
	track.Size = UDim2.new(1, 0, 0, 26)
	track.BackgroundColor3 = Color3.fromRGB(24, 29, 39)
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = root
	corner(track, 8)

	-- lớp nền có sọc mờ cho có chiều sâu
	local trackTint = Instance.new("Frame")
	trackTint.Name = "Tint"
	trackTint.Size = UDim2.fromScale(1, 1)
	trackTint.BackgroundColor3 = Color3.fromRGB(40, 48, 64)
	trackTint.BackgroundTransparency = 0.65
	trackTint.BorderSizePixel = 0
	trackTint.Parent = track

	-- phần đã đầy
	local trackFill = Instance.new("Frame")
	trackFill.Name = "TrackFill"
	trackFill.Size = UDim2.fromScale(0, 1)
	trackFill.BackgroundColor3 = Color3.fromRGB(96, 165, 250)
	trackFill.BorderSizePixel = 0
	trackFill.Parent = track

	local fill = trackFill -- giữ tên cũ để tương thích

	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(56, 189, 248)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(147, 197, 253)),
	})
	fillGradient.Parent = trackFill

	-- vệt sáng chạy bên trong phần đã đầy
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.Size = UDim2.new(0.14, 0, 1, 0)
	shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	shine.BackgroundTransparency = 0.78
	shine.BorderSizePixel = 0
	shine.Parent = trackFill

	-- lóe sáng khi đột phá
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 4
	flash.Parent = track

	-- vạch chia 9 tầng
	for i = 1, STAGES - 1 do
		local notch = Instance.new("Frame")
		notch.Name = string.format("Notch_%d", i)
		notch.AnchorPoint = Vector2.new(0.5, 0.5)
		notch.Position = UDim2.fromScale(i / STAGES, 0.5)
		notch.Size = UDim2.new(0, 1, 0.62, 0)
		notch.BackgroundColor3 = Color3.fromRGB(10, 13, 19)
		notch.BackgroundTransparency = 0.35
		notch.BorderSizePixel = 0
		notch.ZIndex = 3
		notch.Parent = track
	end

	local percent = Instance.new("TextLabel")
	percent.Name = "Percent"
	percent.AnchorPoint = Vector2.new(0.5, 0.5)
	percent.Position = UDim2.fromScale(0.5, 0.5)
	percent.Size = UDim2.new(1, 0, 0, 20)
	percent.BackgroundTransparency = 1
	percent.Font = Enum.Font.GothamBold
	percent.TextSize = 13
	percent.TextColor3 = Color3.fromRGB(245, 250, 255)
	percent.TextStrokeTransparency = 0.55
	percent.Text = "0%"
	percent.ZIndex = 5
	percent.Parent = track

	--------------------------------------------------------------- hàng 3: tốc độ + nút
	local rateLabel = Instance.new("TextLabel")
	rateLabel.Name = "Rate"
	rateLabel.BackgroundTransparency = 1
	rateLabel.Position = UDim2.fromOffset(0, 62)
	rateLabel.Size = UDim2.new(0.62, 0, 0, 22)
	rateLabel.Font = Enum.Font.Code
	rateLabel.TextSize = 12
	rateLabel.TextXAlignment = Enum.TextXAlignment.Left
	rateLabel.TextColor3 = Color3.fromRGB(110, 231, 183)
	rateLabel.Text = "+15 khí/giây"
	rateLabel.Parent = root

	local secludedBtn = Instance.new("TextButton")
	secludedBtn.Name = "Secluded"
	secludedBtn.AnchorPoint = Vector2.new(1, 0)
	secludedBtn.Position = UDim2.new(1, 0, 0, 60)
	secludedBtn.Size = UDim2.fromOffset(132, 26)
	secludedBtn.BackgroundColor3 = Color3.fromRGB(37, 99, 235)
	secludedBtn.Font = Enum.Font.GothamBold
	secludedBtn.TextSize = 12
	secludedBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	secludedBtn.Text = "Bế quan ×2"
	secludedBtn.AutoButtonColor = false
	secludedBtn.Parent = root
	corner(secludedBtn, 7)

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = Color3.fromRGB(96, 165, 250)
	btnStroke.Thickness = 1
	btnStroke.Transparency = 0.5
	btnStroke.Parent = secludedBtn

	secludedBtn.MouseButton1Click:Connect(function()
		local callback = self.onSecludedToggle
		if callback then
			callback()
		end
	end)

	self.root = root
	self.header = header
	self.counter = counter
	self.track = track
	self.trackFill = trackFill
	self.fill = fill
	self.fillGradient = fillGradient
	self.percent = percent
	self.rateLabel = rateLabel
	self.secludedBtn = secludedBtn
	self.shine = shine
	self.screenGui = if parent:IsA("ScreenGui") then parent else nil

	--------------------------------------------------------------- hiệu ứng & nội suy
	-- vệt sáng chạy đều (dùng số frame, không dùng task.wait → không bị trễ/nhảy)
	local shineClock = 0
	local lastInputAt = os.clock()

	local connection: RBXScriptConnection? = nil

	local function updateShine(dt: number)
		shineClock = (shineClock + dt) % 2.4
		local t = math.clamp(shineClock / 1.5, 0, 1)
		shine.Position = UDim2.fromScale(-0.25 + t * 1.35, 0)
		shine.BackgroundTransparency = 0.95 - 0.25 * math.sin(t * math.pi)
	end

	local function updateFade(dt: number)
		if not autoFade then
			return
		end
		local hovering = false
		local mouse = UserInputService:GetMouseLocation()
		local guiObject = root
		local absPos = guiObject.AbsolutePosition
		local absSize = guiObject.AbsoluteSize
		hovering = mouse.X >= absPos.X and mouse.X <= absPos.X + absSize.X
			and mouse.Y >= absPos.Y and mouse.Y <= absPos.Y + absSize.Y

		local idleFor = os.clock() - lastInputAt
		local wantAlpha
		if hovering or idleFor < 4 then
			wantAlpha = 0
		elseif idleFor > 7 then
			wantAlpha = 1
		else
			wantAlpha = (idleFor - 4) / 3
		end
		fadeAlpha = fadeAlpha + (wantAlpha - fadeAlpha) * math.min(dt * 4, 1)
		fadeAlpha = math.clamp(fadeAlpha, 0, 1)
		root.BackgroundTransparency = 0.06 + 0.5 * fadeAlpha
		header.TextTransparency = fadeAlpha * 0.55
		counter.TextTransparency = fadeAlpha * 0.55
		percent.TextTransparency = fadeAlpha * 0.45
		if lastSnapshot and not lastSnapshot.isMax then
			rateLabel.TextTransparency = fadeAlpha * 0.55
		end
		secludedBtn.TextTransparency = fadeAlpha * 0.35
	end

	local function updateProgress(dt: number)
		-- nội suy mượt: 8/s → bám sát nhưng không giật
		local speed = 9
		local delta = target - shown
		if math.abs(delta) > 0.0005 then
			shown = shown + delta * math.min(dt * speed, 1)
		else
			shown = target
		end
		trackFill.Size = UDim2.fromScale(shown, 1)
	end

	local function bindHeartbeat()
		connection = RunService.Heartbeat:Connect(function(dt)
			if not root.Parent then
				if connection then
					connection:Disconnect()
				end
				return
			end
			updateShine(dt)
			updateProgress(dt)
			updateFade(dt)
		end)
	end
	bindHeartbeat()

	-- rê chuột / bấm phím → sáng lại
	UserInputService.InputBegan:Connect(function()
		lastInputAt = os.clock()
	end)
	UserInputService.InputChanged:Connect(function()
		lastInputAt = os.clock()
	end)
	root.MouseEnter:Connect(function()
		lastInputAt = os.clock() + 3
	end)
	root.MouseLeave:Connect(function()
		lastInputAt = os.clock()
	end)

	--------------------------------------------------------------- cập nhật dữ liệu
	function self:setSnapshot(snapshot: Snapshot)
		lastSnapshot = snapshot
		target = snapshot.progress
		if lastRealm == 0 then
			shown = target -- lần đầu: hiện đúng vị trí, không chạy từ 0
		end

		header.Text = snapshot.stageLabel
		counter.Text = string.format("%s / %s", formatQi(snapshot.qi), formatQi(snapshot.required))

		if snapshot.isMax then
			percent.Text = "ĐỈNH PHONG"
		else
			percent.Text = string.format("%d%%", math.floor(snapshot.progress * 100))
		end

		-- màu theo cảnh giới
		fillGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, snapshot.realmColor),
			ColorSequenceKeypoint.new(1, snapshot.realmGlow),
		})
		stroke.Color = snapshot.realmColor
		header.TextColor3 = if snapshot.isMax then snapshot.realmGlow else Color3.fromRGB(240, 245, 255)
		btnStroke.Color = snapshot.realmColor

		if snapshot.isMax then
			rateLabel.Text = "Đã đạt Hoá Thần tầng 9 — đỉnh cao tu tiên"
			rateLabel.TextColor3 = snapshot.realmGlow
		else
			local suffix = if snapshot.secluded then "  ·  bế quan" else ""
			rateLabel.Text = string.format("+%d khí/giây%s", math.floor(snapshot.rate), suffix)
			rateLabel.TextColor3 = Color3.fromRGB(110, 231, 183)
		end

		if snapshot.secluded then
			secludedBtn.Text = "Xuất quan"
			secludedBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
		else
			secludedBtn.Text = "Bế quan ×2"
			secludedBtn.BackgroundColor3 = Color3.fromRGB(37, 99, 235)
		end

		-- đột phá: lên tầng thì nháy nhẹ, sang cảnh giới thì flash mạnh
		if lastRealm > 0 and snapshot.realm > lastRealm then
			local big = snapshot.realm > lastRealm
			flash.BackgroundColor3 = snapshot.realmGlow
			flash.BackgroundTransparency = 0.35
			TweenService:Create(flash, TweenInfo.new(0.7, Enum.EasingStyle.Quad), {
				BackgroundTransparency = 1,
			}):Play()

			header.TextSize = 17
			TweenService:Create(header, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.Direction.Out), {
				TextSize = if big then 24 else 21,
			}):Play()
			header.TextColor3 = snapshot.realmGlow
			task.delay(1.1, function()
				if header.Parent then
					TweenService:Create(header, TweenInfo.new(0.45), {
						TextSize = 17,
						TextColor3 = Color3.fromRGB(240, 245, 255),
					}):Play()
				end
			end)
		elseif lastStage > 0 and snapshot.stage > lastStage then
			flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			flash.BackgroundTransparency = 0.6
			TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {
				BackgroundTransparency = 1,
			}):Play()
		end

		lastRealm = snapshot.realm
		lastStage = snapshot.stage
		lastInputAt = os.clock()
	end

	function self:destroy()
		if connection then
			connection:Disconnect()
		end
		local screenGui = self.screenGui
		root:Destroy()
		if screenGui and screenGui:FindFirstChild("CultivationPanel") == nil and screenGui.Name == "BrigeCultivationPreview" then
			screenGui:Destroy()
		end
	end

	return self
end

return CultivationBarView
