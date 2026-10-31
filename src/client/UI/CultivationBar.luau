--!strict
--[[
	CultivationBar — thanh tiến độ tu luyện kiểu thanh kinh nghiệm.

	Bố cục (góc dưới giữa màn hình):
		┌──────────────────────────────────────────────┐
		│  Trúc Cơ · Tầng 3                12.4K / 24.3K│
		│  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░  51%         │
		│  +33 khí/giây            [ Bế quan ]          │
		└──────────────────────────────────────────────┘

	Màu thanh + hiệu ứng sáng đổi theo cảnh giới (Luyện Khí lam → Hoá Thần đỏ).
	Khi sang cảnh giới mới, chữ bật to + phóng to rồi thu về (hiệu ứng đột phá).
]]

local TweenService = game:GetService("TweenService")

local CultivationBar = {}
CultivationBar.__index = CultivationBar

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

export type CultivationBar = {
	gui: ScreenGui,
	root: Frame,
	header: TextLabel,
	counter: TextLabel,
	fill: Frame,
	fillGradient: UIGradient,
	shine: Frame,
	percent: TextLabel,
	rateLabel: TextLabel,
	secludedBtn: TextButton,
	onSecludedToggle: (() -> ())?,
	lastRealm: number,
	lastStage: number,
	destroy: (self: CultivationBar) -> (),
	setSnapshot: (self: CultivationBar, snapshot: Snapshot) -> (),
}

local function formatQi(value: number): string
	if value >= 1_000_000 then
		return string.format("%.2fM", value / 1_000_000)
	elseif value >= 1_000 then
		return string.format("%.1fK", value / 1_000)
	end
	return tostring(math.floor(value))
end

local function corner(parent: Instance, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

function CultivationBar.new(playerGui: PlayerGui): CultivationBar
	local self = (setmetatable({}, CultivationBar) :: any) :: CultivationBar
	self.lastRealm = 0
	self.lastStage = 0

	local gui = Instance.new("ScreenGui")
	gui.Name = "BrigeCultivation"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Panel"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -18)
	root.Size = UDim2.fromOffset(460, 96)
	root.BackgroundColor3 = Color3.fromRGB(14, 17, 24)
	root.BackgroundTransparency = 0.08
	root.BorderSizePixel = 0
	root.Parent = gui
	corner(root, 12)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(96, 165, 250)
	stroke.Thickness = 1
	stroke.Transparency = 0.45
	stroke.Parent = root

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = root

	-- hàng 1: tên cảnh giới · tầng          khí hiện tại / cần
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(0.62, 0, 0, 20)
	header.Font = Enum.Font.GothamBold
	header.TextSize = 15
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = Color3.fromRGB(240, 245, 255)
	header.Text = "Luyện Khí · Tầng 1"
	header.Parent = root

	local counter = Instance.new("TextLabel")
	counter.Name = "Counter"
	counter.BackgroundTransparency = 1
	counter.Position = UDim2.new(0.62, 0, 0, 0)
	counter.Size = UDim2.new(0.38, 0, 0, 20)
	counter.Font = Enum.Font.Code
	counter.TextSize = 13
	counter.TextXAlignment = Enum.TextXAlignment.Right
	counter.TextColor3 = Color3.fromRGB(148, 163, 184)
	counter.Text = "0 / 120"
	counter.Parent = root

	-- hàng 2: thanh tiến độ
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(0, 26)
	track.Size = UDim2.new(1, 0, 0, 22)
	track.BackgroundColor3 = Color3.fromRGB(28, 33, 44)
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = root
	corner(track, 7)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(96, 165, 250)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(56, 189, 248)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(147, 197, 253)),
	})
	fillGradient.Parent = fill

	-- vệt sáng chạy trong phần đã đầy
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.Size = UDim2.new(0.18, 0, 1, 0)
	shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	shine.BackgroundTransparency = 0.72
	shine.BorderSizePixel = 0
	shine.Parent = fill

	task.spawn(function()
		while shine.Parent ~= nil do
			shine.Position = UDim2.fromScale(-0.3, 0)
			local tween = TweenService:Create(
				shine,
				TweenInfo.new(1.6, Enum.EasingStyle.Linear),
				{ Position = UDim2.fromScale(1.1, 0) }
			)
			tween:Play()
			task.wait(1.9)
		end
	end)

	local percent = Instance.new("TextLabel")
	percent.Name = "Percent"
	percent.AnchorPoint = Vector2.new(0.5, 0)
	percent.Position = UDim2.new(0.5, 0, 0, 26)
	percent.Size = UDim2.new(1, 0, 0, 22)
	percent.BackgroundTransparency = 1
	percent.Font = Enum.Font.GothamBold
	percent.TextSize = 12
	percent.TextColor3 = Color3.fromRGB(12, 16, 22)
	percent.Text = "0%"
	percent.ZIndex = 3
	percent.Parent = root

	-- hàng 3: tốc độ + nút bế quan
	local rateLabel = Instance.new("TextLabel")
	rateLabel.Name = "Rate"
	rateLabel.BackgroundTransparency = 1
	rateLabel.Position = UDim2.fromOffset(0, 54)
	rateLabel.Size = UDim2.new(0.6, 0, 0, 22)
	rateLabel.Font = Enum.Font.Code
	rateLabel.TextSize = 12
	rateLabel.TextXAlignment = Enum.TextXAlignment.Left
	rateLabel.TextColor3 = Color3.fromRGB(110, 231, 183)
	rateLabel.Text = "+15 khí/giây"
	rateLabel.Parent = root

	local secludedBtn = Instance.new("TextButton")
	secludedBtn.Name = "Secluded"
	secludedBtn.AnchorPoint = Vector2.new(1, 0)
	secludedBtn.Position = UDim2.new(1, 0, 0, 54)
	secludedBtn.Size = UDim2.fromOffset(120, 26)
	secludedBtn.BackgroundColor3 = Color3.fromRGB(37, 99, 235)
	secludedBtn.Font = Enum.Font.GothamBold
	secludedBtn.TextSize = 12
	secludedBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	secludedBtn.Text = "Bế quan ×2"
	secludedBtn.AutoButtonColor = true
	secludedBtn.Parent = root
	corner(secludedBtn, 6)

	secludedBtn.MouseButton1Click:Connect(function()
		local callback = self.onSecludedToggle
		if callback then
			callback()
		end
	end)

	self.gui = gui
	self.root = root
	self.header = header
	self.counter = counter
	self.fill = fill
	self.fillGradient = fillGradient
	self.shine = shine
	self.percent = percent
	self.rateLabel = rateLabel
	self.secludedBtn = secludedBtn
	return self
end

function CultivationBar.setSnapshot(self: CultivationBar, snapshot: Snapshot)
	self.header.Text = snapshot.stageLabel
	self.counter.Text = string.format(
		"%s / %s",
		formatQi(snapshot.qi),
		formatQi(snapshot.required)
	)
	self.percent.Text = if snapshot.isMax
		then "ĐỈNH PHONG"
		else string.format("%d%%", math.floor(snapshot.progress * 100))

	TweenService:Create(
		self.fill,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.Direction.Out),
		{ Size = UDim2.fromScale(snapshot.progress, 1) }
	):Play()

	self.rateLabel.Text = if snapshot.isMax
		then "Đã đạt Hoá Thần tầng 9 — đỉnh cao tu tiên"
		else string.format("+%d khí/giây%s", math.floor(snapshot.rate), if snapshot.secluded then " · bế quan" else "")
	self.rateLabel.TextColor3 = if snapshot.isMax then snapshot.realmGlow else Color3.fromRGB(110, 231, 183)

	-- đổi màu theo cảnh giới
	self.fillGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, snapshot.realmColor),
		ColorSequenceKeypoint.new(1, snapshot.realmGlow),
	})
	local rootStroke = self.root:FindFirstChildOfClass("UIStroke")
	if rootStroke then
		rootStroke.Color = snapshot.realmColor
	end

	self.secludedBtn.Text = if snapshot.secluded then "Xuất quan" else "Bế quan ×2"
	self.secludedBtn.BackgroundColor3 = if snapshot.secluded
		then Color3.fromRGB(16, 185, 129)
		else Color3.fromRGB(37, 99, 235)

	-- hiệu ứng đột phá: sang cảnh giới mới thì bật to rồi thu về
	if self.lastRealm > 0 and snapshot.realm > self.lastRealm then
		self.header.TextColor3 = snapshot.realmGlow
		self.header.Size = UDim2.new(0.62, 0, 0, 20)
		TweenService:Create(
			self.header,
			TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.Direction.Out),
			{ TextSize = 22 }
		):Play()
		task.delay(1.2, function()
			TweenService:Create(self.header, TweenInfo.new(0.4), { TextSize = 15 }):Play()
		end)
	elseif self.lastStage > 0 and snapshot.stage > self.lastStage then
		-- lên tầng: nháy nhẹ
		self.header.TextColor3 = Color3.fromRGB(255, 255, 255)
		task.delay(0.4, function()
			self.header.TextColor3 = Color3.fromRGB(240, 245, 255)
		end)
	end

	self.lastRealm = snapshot.realm
	self.lastStage = snapshot.stage
end

function CultivationBar.destroy(self: CultivationBar)
	self.gui:Destroy()
end

return CultivationBar
