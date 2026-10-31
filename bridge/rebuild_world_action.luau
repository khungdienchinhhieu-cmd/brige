--!strict
--[[
	rebuild_world_action.luau — tác vụ "Dựng lại thế giới" chạy SAU khi plugin
	đã áp Rojo (publish.mjs đính kèm file này vào studio-sync.json mỗi lần publish).

	Vì sao cần: plugin chỉ ghi Source vào các Script/ModuleScript. Nếu module dựng
	thế giới đã chạy từ trước, sửa Source KHÔNG làm thế giới đổi → mở Studio ra vẫn
	thấy y hệt bản cũ. Tác vụ này xoá + dựng lại từ mã nguồn mới.

	Hợp đồng với từng module trong ReplicatedStorage.Shared.World.Modules:
		module.build(root: Folder, kit: table) -> ()   -- tuỳ chọn
		module.FOUNDATION = true                        -- tuỳ chọn: đổi là dựng lại toàn bộ
	Không có module nào cũng không sao: chỉ dọn thế giới cũ.

	Băm từng module để chỉ dựng lại khi thật sự có thay đổi (tăng dần).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local WORLD_NAME = "BrigeWorld"
local MODULES_KEY = "Shared.World.Modules"
local HASH_ATTR = "__BrigeWorldHash"

local function log(...: any)
	print("[brige World]", ...)
end

local function findModules(): Instance?
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	if not shared then
		return nil
	end
	local world = shared:FindFirstChild("World")
	if not world then
		return nil
	end
	return world:FindFirstChild("Modules")
end

-- Băm Source của mọi module (sắp xếp theo tên để băm ổn định).
local function hashModules(modules: Instance): (string, number)
	local parts = {}
	local count = 0
	for _, child in ipairs(modules:GetChildren()) do
		if child:IsA("ModuleScript") then
			local ok, src = pcall(function()
				return (child :: any).Source
			end)
			table.insert(parts, child.Name .. ":" .. tostring(if ok then src else ""))
			count += 1
		end
	end
	table.sort(parts)
	return tostring(#table.concat(parts)) .. ":" .. tostring(#parts), count
end

local modules = findModules()
if not modules then
	log("không thấy", MODULES_KEY, "→ chỉ dọn thế giới cũ (nếu có).")
end

local signature = if modules then hashModules(modules) else "0:0"
local previous = ServerStorage:GetAttribute(HASH_ATTR)
local existingRoot = workspace:FindFirstChild(WORLD_NAME)

if existingRoot and previous == signature then
	log("thế giới đã đúng bản hiện tại (" .. tostring(signature) .. ") → bỏ qua dựng lại.")
	return
end

-- Dọn thế giới cũ (chỉ đụng vào folder do bridge quản lý).
if existingRoot then
	existingRoot:Destroy()
end

local root = Instance.new("Folder")
root.Name = WORLD_NAME
root.Parent = workspace

local kit = {
	root = root,
	modules = modules,
	log = log,
	makePart = function(name: string, size: Vector3, cframe: CFrame, color: Color3): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = cframe
		part.Anchored = true
		part.Color = color
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = root
		return part
	end,
}

local built, failed = 0, 0
if modules then
	for _, child in ipairs(modules:GetChildren()) do
		if child:IsA("ModuleScript") then
			local okRun, modOrErr = pcall(require, child)
			if not okRun or type(modOrErr) ~= "table" then
				failed += 1
				warn("[brige World] bỏ qua module lỗi:", child.Name, modOrErr)
				continue
			end
			local mod = modOrErr :: any
			if type(mod.build) == "function" then
				local okBuild, err = pcall(mod.build, root, kit)
				if okBuild then
					built += 1
				else
					failed += 1
					warn("[brige World] build lỗi ở", child.Name, err)
				end
			end
		end
	end
end

ServerStorage:SetAttribute(HASH_ATTR, signature)
log(string.format("dựng lại xong: %d module, %d lỗi, %d part (băm %s)", built, failed, #root:GetChildren(), signature))
