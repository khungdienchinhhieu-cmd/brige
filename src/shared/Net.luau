--!strict
--[[
	Net — tạo/lấy RemoteEvent dùng chung.
	Server gọi Net.getRemote("Notify") để tạo; client gọi cùng hàm và chờ remote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "BrigeRemotes"

local Net = {}

local function ensureFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

--[[ Tạo remote nếu chưa có (chỉ dùng phía server). ]]
function Net.createRemote(name: string): RemoteEvent
	local folder = ensureFolder()
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

--[[ Lấy remote, chờ tối đa timeout giây (dùng phía client). ]]
function Net.waitForRemote(name: string, timeout: number?): RemoteEvent?
	local deadline = os.clock() + (timeout or 10)
	repeat
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if folder then
			local remote = folder:FindFirstChild(name)
			if remote and remote:IsA("RemoteEvent") then
				return remote
			end
		end
		task.wait(0.1)
	until os.clock() > deadline
	return nil
end

return Net
