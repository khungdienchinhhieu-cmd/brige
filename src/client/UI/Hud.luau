--!strict
--[[
	Hud — bảng nhỏ ở góc trên trái: tên game, version, dòng trạng thái.
	Mục đích: nhìn 1 giây là biết Studio đang chạy bản vừa publish hay bản cũ.
]]

export type HudConfig = {
	GameName: string,
	Tagline: string,
	Version: string,
	Theme: {
		Background: Color3,
		Surface: Color3,
		Accent: Color3,
		Text: Color3,
		Muted: Color3,
	},
}

export type Hud = {
	gui: ScreenGui,
	status: TextLabel,
	setStatus: (self: Hud, message: string) -> (),
	destroy: (self: Hud) -> (),
}

local Hud = {}
Hud.__index = Hud

function Hud.new(playerGui: PlayerGui, config: HudConfig): Hud
	local self = (setmetatable({} :: any, Hud) :: any) :: Hud

	local gui = Instance.new("ScreenGui")
	gui.Name = "BrigeHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.Position = UDim2.fromOffset(16, 16)
	frame.Size = UDim2.fromOffset(248, 96)
	frame.BackgroundColor3 = config.Theme.Background
	frame.BackgroundTransparency = 0.12
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = config.Theme.Accent
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = config.Theme.Text
	title.Text = string.format("%s · v%s", config.GameName, config.Version)
	title.Parent = frame

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(0, 24)
	subtitle.Size = UDim2.new(1, 0, 0, 18)
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextSize = 12
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextColor3 = config.Theme.Muted
	subtitle.Text = config.Tagline
	subtitle.Parent = frame

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(0, 48)
	status.Size = UDim2.new(1, 0, 0, 28)
	status.Font = Enum.Font.Code
	status.TextSize = 12
	status.TextWrapped = true
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = config.Theme.Accent
	status.Text = "đang tải..."
	status.Parent = frame

	self.gui = gui
	self.status = status
	return self
end

function Hud.setStatus(self: Hud, message: string)
	self.status.Text = message
end

function Hud.destroy(self: Hud)
	self.gui:Destroy()
end

return Hud
