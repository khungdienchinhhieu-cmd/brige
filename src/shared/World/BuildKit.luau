--!strict
--[[
	BuildKit — hàm dựng hình dùng chung cho mọi module trong World/Modules.
	Mọi thứ tạo ra đều nằm dưới folder root do rebuild_world_action.luau truyền vào.
]]

local BuildKit = {}

function BuildKit.part(root: Instance, props: {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	shape: Enum.PartType?,
}): Part
	local part = Instance.new("Part")
	part.Name = props.name
	part.Anchored = true
	part.Size = props.size
	part.CFrame = props.cframe
	part.Color = props.color or Color3.fromRGB(160, 170, 185)
	part.Material = props.material or Enum.Material.SmoothPlastic
	part.Transparency = props.transparency or 0
	part.Shape = props.shape or Enum.PartType.Block
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = root
	return part
end

function BuildKit.wedge(root: Instance, props: {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
}): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Name = props.name
	wedge.Anchored = true
	wedge.Size = props.size
	wedge.CFrame = props.cframe
	wedge.Color = props.color or Color3.fromRGB(160, 170, 185)
	wedge.Parent = root
	return wedge
end

function BuildKit.label(root: Instance, text: string, position: Vector3, color: Color3?): TextLabel
	local part = BuildKit.part(root, {
		name = "Label_" .. text,
		size = Vector3.new(0.2, 0.2, 0.2),
		cframe = CFrame.new(position),
		color = Color3.fromRGB(0, 0, 0),
		transparency = 1,
	})
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(14, 3)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 400
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color or Color3.fromRGB(232, 240, 252)
	label.TextStrokeTransparency = 0.4
	label.Parent = billboard
	return label
end

return BuildKit
