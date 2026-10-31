-- brige ↔ Roblox Studio Live Bridge v3 (Atom Commit Stream + Raw CDN — Không giới hạn API 403!)
-- Repo đích: khungdienchinhhieu-cmd/brige (repo riêng, chạy độc lập với repo tham khảo).
-- Mặc định tải đúng commit SHA mà bạn dán vào Command Bar (ghim bản build, không dính cache CDN).
-- Cơ chế:
--   1. Đọc trực tiếp commit SHA mới nhất từ Atom Feed của github.com (max-age=0, không tốn quota 60 req/h của api.github.com)
--   2. Tải gói đồng bộ từ raw.githubusercontent.com/<COMMIT_SHA>/studio-sync.json (tức thì, không dính cache cũ, không bị lỗi HTTP 403)

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local CoreGui = game:GetService("CoreGui")
local ServerStorage = game:GetService("ServerStorage")

local okScriptEditor, ScriptEditorService = pcall(function()
	return game:GetService("ScriptEditorService")
end)

local okPlugin, pluginObj = pcall(function()
	return plugin
end)
local hasPlugin = okPlugin and pluginObj ~= nil

if hasPlugin and not RunService:IsEdit() then
	return
end

-- Dọn sạch vòng lặp cũ (bao gồm bản v1/v2 bị dính 403 trước đó)
if _G.__ARENA_LIVE_BRIDGE_CLEANUP then
	pcall(_G.__ARENA_LIVE_BRIDGE_CLEANUP)
	_G.__ARENA_LIVE_BRIDGE_CLEANUP = nil
end

local GITHUB_OWNER = "khungdienchinhhieu-cmd"
local GITHUB_REPO = "brige"
local MAIN_BRANCH = "main"
-- Nhánh làm việc: publish.mjs đẩy gói sync lên đây.
local WORKING_BRANCH = "arena/caf04b02-brige"
local DEFAULT_BRANCH = WORKING_BRANCH
-- Để trống = luôn lấy commit HEAD mới nhất của nhánh (qua Atom feed).
-- Điền 1 SHA = ghim cứng đúng bản build đó, bỏ qua Atom feed.
local BASE_COMMIT_SHA = ""
local activeBranch = DEFAULT_BRANCH

local function getAtomFeedUrl()
	return string.format(
		"https://github.com/%s/%s/commits/%s.atom",
		GITHUB_OWNER,
		GITHUB_REPO,
		activeBranch
	)
end

local function buildRawUrl(refOrSha, filePath)
	return string.format(
		"https://raw.githubusercontent.com/%s/%s/%s/%s",
		GITHUB_OWNER,
		GITHUB_REPO,
		refOrSha,
		filePath
	)
end

local state = {
	connected = false,
	running = true,
	pollGen = 0,
	lastCommitSha = "",
	syncedVersion = 0,
	syncedHash = "",
	syncedFiles = 0,
	lastStatus = "Sẵn sàng kết nối",
}

-- ============================================================================
-- HỖ TRỢ UNDO / REDO (Ctrl + Z)
-- ============================================================================
local function withUndoRecording(actionName, callback)
	local recordingId = nil
	pcall(function()
		recordingId = ChangeHistoryService:TryBeginRecording("Arena_" .. actionName, "Arena AI: " .. actionName)
	end)

	local ok, resultOrErr = pcall(callback)

	if recordingId then
		pcall(function()
			local op = if ok
				then Enum.FinishRecordingOperation.Commit
				else Enum.FinishRecordingOperation.Cancel
			ChangeHistoryService:FinishRecording(recordingId, op)
		end)
	elseif ok then
		pcall(function()
			ChangeHistoryService:SetWaypoint("Arena AI: " .. actionName)
		end)
	end

	return ok, resultOrErr
end

-- ============================================================================
-- ĐỒNG BỘ ROJO TỰ ĐỘNG VÀO DATAMODEL
-- ============================================================================
local function setScriptSourceSafe(scriptInst, newSource)
	local currentOk, currentSource = pcall(function()
		return scriptInst.Source
	end)
	if currentOk and currentSource == newSource then
		return false
	end

	if okScriptEditor and ScriptEditorService then
		local updated = pcall(function()
			ScriptEditorService:UpdateSourceAsync(scriptInst, function()
				return newSource
			end)
		end)
		if updated then
			return true
		end
	end

	scriptInst.Source = newSource
	return true
end

local function applyBasicProperty(inst, propName, propVal)
	pcall(function()
		if (propName == "Color" or propName == "Ambient") and type(propVal) == "table" and #propVal == 3 then
			inst[propName] = Color3.new(propVal[1], propVal[2], propVal[3])
		elseif (propName == "Position" or propName == "Size") and type(propVal) == "table" and #propVal == 3 then
			inst[propName] = Vector3.new(propVal[1], propVal[2], propVal[3])
		elseif propName == "Technology" and type(propVal) == "string" then
			local enumItem = Enum.Technology[propVal]
			if enumItem then
				inst.Technology = enumItem
			end
		elseif propName ~= "FilteringEnabled" and propName ~= "Outlines" and propName ~= "RespectFilteringEnabled" then
			inst[propName] = propVal
		end
	end)
end

local function reconcileNode(parentInst, nodeName, nodeSpec, stats)
	local targetClass = nodeSpec.className or "Folder"
	local isService = nodeSpec.isService == true

	local wasCreated = false
	local targetInst = nil
	if isService then
		local okSrv, srv = pcall(function()
			return game:GetService(nodeName)
		end)
		if okSrv and srv then
			targetInst = srv
		end
	else
		local existing = parentInst:FindFirstChild(nodeName)
		if existing and existing.ClassName ~= targetClass then
			if existing:GetAttribute("__ArenaRojoManaged") == true then
				existing:Destroy()
				existing = nil
			end
		end
		if not existing then
			local createdOk, created = pcall(function()
				return Instance.new(targetClass)
			end)
			if not createdOk or not created then
				return
			end
			created.Name = nodeName
			created:SetAttribute("__ArenaRojoManaged", true)
			created.Parent = parentInst
			targetInst = created
			wasCreated = true
			stats.created += 1
		else
			targetInst = existing
			if nodeSpec.managed then
				pcall(function()
					targetInst:SetAttribute("__ArenaRojoManaged", true)
				end)
			end
		end
	end

	if not targetInst then
		return
	end

	if type(nodeSpec.properties) == "table" and (wasCreated or nodeSpec.managed == true) then
		for propName, propVal in pairs(nodeSpec.properties) do
			applyBasicProperty(targetInst, propName, propVal)
		end
	end

	if type(nodeSpec.source) == "string" and targetInst:IsA("LuaSourceContainer") then
		stats.totalScripts += 1
		local changed = setScriptSourceSafe(targetInst, nodeSpec.source)
		if changed then
			stats.updated += 1
		end
		if type(nodeSpec.repoPath) == "string" then
			pcall(function()
				targetInst:SetAttribute("__ArenaRepoPath", nodeSpec.repoPath)
			end)
		end
	end

	local specChildren = nodeSpec.children or {}
	if nodeSpec.managed == true then
		for _, child in ipairs(targetInst:GetChildren()) do
			if child:GetAttribute("__ArenaRojoManaged") == true and specChildren[child.Name] == nil then
				child:Destroy()
				stats.deleted += 1
			end
		end
	end

	for childName, childSpec in pairs(specChildren) do
		reconcileNode(targetInst, childName, childSpec, stats)
	end
end

-- ============================================================================
-- THỰC THI CÁC TÁC VỤ DỰNG MAP / THÀNH PHỐ TỪ AI (ACTIONS)
-- ============================================================================
local function hasExecutedAction(actionId)
	local raw = ServerStorage:GetAttribute("__ArenaExecutedActions") or ""
	return string.find("," .. raw .. ",", "," .. tostring(actionId) .. ",", 1, true) ~= nil
end

local function markExecutedAction(actionId)
	local raw = ServerStorage:GetAttribute("__ArenaExecutedActions") or ""
	local updated = if raw == "" then tostring(actionId) else (raw .. "," .. tostring(actionId))
	if #updated > 4000 then
		updated = string.sub(updated, #updated - 3500)
	end
	pcall(function()
		ServerStorage:SetAttribute("__ArenaExecutedActions", updated)
	end)
end

--[[
	Khoá chống chạy trùng.
	Trước đây dùng mỗi `action.id` → tác vụ dựng thế giới có id cố định (băm từ nội dung
	file action), nên sau lần sync ĐẦU TIÊN nó không bao giờ chạy lại: script mới được ghi
	nhưng map đứng yên → "cập nhật không được".

	Giờ khoá = `<action.id>@<hash của gói>`:
		• hash gói đổi (có nội dung mới)  → chạy lại đúng 1 lần
		• sync lại y nguyên               → bỏ qua (không tốn thời gian)
		• action.once == true             → chỉ chạy 1 lần duy nhất, mãi mãi
]]
local function actionRunKey(action, bundleKey)
	if action.once == true then
		return tostring(action.id)
	end
	return tostring(action.id) .. "@" .. tostring(bundleKey or "")
end

local function runQueuedActions(actions, bundleKey)
	if type(actions) ~= "table" then
		return 0
	end
	local executedCount = 0
	for _, action in ipairs(actions) do
		if type(action) == "table" and action.id and type(action.code) == "string" then
			local runKey = actionRunKey(action, bundleKey)
			if not hasExecutedAction(runKey) then
				markExecutedAction(runKey)
				local fn, compileErr = loadstring(action.code, "=ArenaAction_" .. tostring(action.id))
				if not fn then
					warn("[brige Bridge] Lỗi biên dịch Action " .. tostring(action.id) .. ": " .. tostring(compileErr))
				else
					local desc = tostring(action.description or action.id)
					local okRun, runErr = withUndoRecording(desc, fn)
					if okRun then
						executedCount += 1
						print("[brige Bridge] ✨ Đã thực thi tác vụ: " .. desc)
					else
						warn("[brige Bridge] Lỗi khi chạy tác vụ '" .. desc .. "': " .. tostring(runErr))
					end
				end
			end
		end
	end
	return executedCount
end

local function applyBundle(bundle)
	local tStart = os.clock()
	local stats = {
		created = 0,
		updated = 0,
		deleted = 0,
		totalScripts = 0,
	}

	local ok, err = withUndoRecording("Đồng bộ Rojo v" .. tostring(bundle.version), function()
		local services = bundle.services or {}
		for serviceName, serviceSpec in pairs(services) do
			reconcileNode(game, serviceName, serviceSpec, stats)
		end
	end)

	if not ok then
		warn("[Arena Bridge] Lỗi đồng bộ Rojo: " .. tostring(err))
		state.lastStatus = "Lỗi quyền Script Injection"
		return false
	end

	local tAfterInject = os.clock()
	local ranActions = runQueuedActions(bundle.actions, bundle.hash)
	local tAfterActions = os.clock()

	state.syncedVersion = tonumber(bundle.version) or state.syncedVersion
	state.syncedHash = tostring(bundle.hash or "")
	state.syncedFiles = stats.totalScripts
	state.lastStatus = string.format("Đã đồng bộ lúc %s", os.date("%H:%M:%S"))

	print(
		string.format(
			"[Arena Bridge] ⏱ Nạp script %.2fs · Chạy tác vụ (dựng thành phố) %.2fs · TỔNG %.2fs",
			tAfterInject - tStart,
			tAfterActions - tAfterInject,
			tAfterActions - tStart
		)
	)

	print(
		string.format(
			"[Arena Bridge] ✅ Đồng bộ thành công Rojo v%s (+%d mới, ~%d cập nhật, -%d xoá, %d tác vụ)",
			tostring(bundle.version),
			stats.created,
			stats.updated,
			stats.deleted,
			ranActions
		)
	)
	return true
end

-- ============================================================================
-- XUẤT TÓM TẮT EXPLORER ĐỂ GỬI CHO AI KHI CẦN
-- ============================================================================
local function buildExplorerSummary()
	local lines = {
		string.format("=== Roblox Studio Snapshot (%s) ===", game.Name),
	}
	local selected = Selection:Get()
	if #selected > 0 then
		local selNames = {}
		for _, s in ipairs(selected) do
			table.insert(selNames, s:GetFullName() .. " [" .. s.ClassName .. "]")
		end
		table.insert(lines, "Đang chọn (Selection): " .. table.concat(selNames, ", "))
	end

	local servicesToScan = {
		"Workspace",
		"ReplicatedStorage",
		"ServerScriptService",
		"StarterGui",
		"StarterPlayer",
	}
	local function dumpInst(inst, indent, depth, maxDepth)
		if depth > maxDepth then
			return
		end
		table.insert(lines, string.format("%s- %s [%s]", indent, inst.Name, inst.ClassName))
		local children = inst:GetChildren()
		for i = 1, math.min(#children, 30) do
			if children[i].Name ~= "Camera" and children[i].Name ~= "Terrain" then
				dumpInst(children[i], indent .. "  ", depth + 1, maxDepth)
			end
		end
	end

	for _, srvName in ipairs(servicesToScan) do
		local okS, srv = pcall(function()
			return game:GetService(srvName)
		end)
		if okS and srv then
			dumpInst(srv, "", 1, 2)
		end
	end
	return table.concat(lines, "\n")
end

-- ============================================================================
-- GIAO DIỆN ĐIỀU KHIỂN TRONG ROBLOX STUDIO
-- ============================================================================
local uiUpdaters = {}
local function updateUi()
	for _, fn in ipairs(uiUpdaters) do
		pcall(fn)
	end
end

local startPolling
local stopPolling
local syncOnceNow

local function createBridgeUi(container, isFloating)
	local root = Instance.new("Frame")
	root.Name = "ArenaBridgeRoot"
	root.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
	root.BorderSizePixel = 0
	if isFloating then
		root.Size = UDim2.fromOffset(335, 218)
		root.Position = UDim2.new(1, -350, 1, -235)
		root.Active = true
		root.Draggable = true
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = root
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(16, 185, 129)
		stroke.Thickness = 1.5
		stroke.Parent = root
	else
		root.Size = UDim2.fromScale(1, 1)
	end
	root.Parent = container

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = root

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -28, 0, 20)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(240, 245, 255)
	title.Text = "⚡ brige ↔ Studio Bridge v3 (CDN)"
	title.Parent = root

	if isFloating then
		local closeBtn = Instance.new("TextButton")
		closeBtn.Size = UDim2.fromOffset(22, 22)
		closeBtn.Position = UDim2.new(1, -22, 0, -1)
		closeBtn.BackgroundColor3 = Color3.fromRGB(48, 54, 70)
		closeBtn.TextColor3 = Color3.fromRGB(220, 225, 240)
		closeBtn.Font = Enum.Font.GothamBold
		closeBtn.TextSize = 11
		closeBtn.Text = "X"
		closeBtn.Parent = root
		local cCorner = Instance.new("UICorner")
		cCorner.CornerRadius = UDim.new(0, 5)
		cCorner.Parent = closeBtn
		closeBtn.MouseButton1Click:Connect(function()
			if _G.__ARENA_LIVE_BRIDGE_CLEANUP then
				_G.__ARENA_LIVE_BRIDGE_CLEANUP()
			end
		end)
	end

	local statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.fromOffset(0, 24)
	statusLabel.Size = UDim2.new(1, 0, 0, 34)
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.TextSize = 12
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextColor3 = Color3.fromRGB(110, 231, 183)
	statusLabel.Text = "Đang kết nối CDN..."
	statusLabel.Parent = root

	local branchBox = Instance.new("TextBox")
	branchBox.Position = UDim2.fromOffset(0, 56)
	branchBox.Size = UDim2.new(0.76, 0, 0, 22)
	branchBox.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
	branchBox.TextColor3 = Color3.fromRGB(125, 211, 252)
	branchBox.PlaceholderText = "Nhập nhánh GitHub (vd: main hoặc arena/...)"
	branchBox.Font = Enum.Font.Code
	branchBox.TextSize = 10
	branchBox.ClearTextOnFocus = false
	branchBox.TextXAlignment = Enum.TextXAlignment.Left
	branchBox.Text = activeBranch
	branchBox.Parent = root
	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(0, 5)
	branchBox.ClipsDescendants = true
	bCorner.Parent = branchBox
	local bPad = Instance.new("UIPadding")
	bPad.PaddingLeft = UDim.new(0, 6)
	bPad.Parent = branchBox

	local mainSwitchBtn = Instance.new("TextButton")
	mainSwitchBtn.Position = UDim2.new(0.78, 0, 0, 56)
	mainSwitchBtn.Size = UDim2.new(0.22, 0, 0, 22)
	mainSwitchBtn.BackgroundColor3 = Color3.fromRGB(30, 58, 95)
	mainSwitchBtn.TextColor3 = Color3.fromRGB(224, 242, 254)
	mainSwitchBtn.Font = Enum.Font.GothamBold
	mainSwitchBtn.TextSize = 10
	mainSwitchBtn.Text = "⇄ main"
	mainSwitchBtn.Parent = root
	local msCorner = Instance.new("UICorner")
	msCorner.CornerRadius = UDim.new(0, 5)
	msCorner.Parent = mainSwitchBtn

	local function applyBranchInput(newBranch)
		local trimmed = string.gsub(newBranch or "", "^%s*(.-)%s*$", "%1")
		if trimmed ~= "" and trimmed ~= activeBranch then
			activeBranch = trimmed
			branchBox.Text = activeBranch
			state.lastCommitSha = ""
			state.syncedHash = ""
			state.lastStatus = "Đã chuyển sang nhánh: " .. activeBranch
			updateUi()
			task.spawn(syncOnceNow)
		end
	end

	branchBox.FocusLost:Connect(function()
		applyBranchInput(branchBox.Text)
	end)
	mainSwitchBtn.MouseButton1Click:Connect(function()
		local target = if activeBranch == MAIN_BRANCH then WORKING_BRANCH else MAIN_BRANCH
		applyBranchInput(target)
	end)

	local syncNowBtn = Instance.new("TextButton")
	syncNowBtn.Position = UDim2.fromOffset(0, 82)
	syncNowBtn.Size = UDim2.new(0.49, 0, 0, 32)
	syncNowBtn.BackgroundColor3 = Color3.fromRGB(37, 99, 235)
	syncNowBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	syncNowBtn.Font = Enum.Font.GothamBold
	syncNowBtn.TextSize = 12
	syncNowBtn.Text = "🔄 Đồng bộ ngay"
	syncNowBtn.Parent = root
	local sCorner = Instance.new("UICorner")
	sCorner.CornerRadius = UDim.new(0, 6)
	sCorner.Parent = syncNowBtn

	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Position = UDim2.new(0.51, 0, 0, 82)
	toggleBtn.Size = UDim2.new(0.49, 0, 0, 32)
	toggleBtn.BackgroundColor3 = Color3.fromRGB(185, 48, 60)
	toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.TextSize = 12
	toggleBtn.Text = "Tạm dừng"
	toggleBtn.Parent = root
	local tCorner = Instance.new("UICorner")
	tCorner.CornerRadius = UDim.new(0, 6)
	tCorner.Parent = toggleBtn

	local exportBox = Instance.new("TextBox")
	exportBox.Position = UDim2.fromOffset(0, 122)
	exportBox.Size = UDim2.new(1, 0, 0, 38)
	exportBox.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
	exportBox.TextColor3 = Color3.fromRGB(191, 219, 254)
	exportBox.PlaceholderText = "Bấm nút dưới để xuất cấu trúc Explorer gửi cho AI..."
	exportBox.Font = Enum.Font.Code
	exportBox.TextSize = 10
	exportBox.ClearTextOnFocus = false
	exportBox.TextEditable = false
	exportBox.MultiLine = true
	exportBox.TextWrapped = true
	exportBox.TextXAlignment = Enum.TextXAlignment.Left
	exportBox.Text = ""
	exportBox.Parent = root
	local eCorner = Instance.new("UICorner")
	eCorner.CornerRadius = UDim.new(0, 6)
	eCorner.Parent = exportBox
	local ePad = Instance.new("UIPadding")
	ePad.PaddingLeft = UDim.new(0, 6)
	ePad.PaddingRight = UDim.new(0, 6)
	ePad.PaddingTop = UDim.new(0, 4)
	ePad.Parent = exportBox

	local snapshotBtn = Instance.new("TextButton")
	snapshotBtn.Position = UDim2.fromOffset(0, 166)
	snapshotBtn.Size = if isFloating then UDim2.new(0.49, 0, 0, 28) else UDim2.new(1, 0, 0, 28)
	snapshotBtn.BackgroundColor3 = Color3.fromRGB(42, 48, 64)
	snapshotBtn.TextColor3 = Color3.fromRGB(220, 228, 245)
	snapshotBtn.Font = Enum.Font.GothamMedium
	snapshotBtn.TextSize = 11
	snapshotBtn.Text = "📋 Xuất Explorer"
	snapshotBtn.Parent = root
	local snCorner = Instance.new("UICorner")
	snCorner.CornerRadius = UDim.new(0, 6)
	snCorner.Parent = snapshotBtn

	if isFloating then
		local savePluginBtn = Instance.new("TextButton")
		savePluginBtn.Position = UDim2.new(0.51, 0, 0, 166)
		savePluginBtn.Size = UDim2.new(0.49, 0, 0, 28)
		savePluginBtn.BackgroundColor3 = Color3.fromRGB(42, 48, 64)
		savePluginBtn.TextColor3 = Color3.fromRGB(220, 228, 245)
		savePluginBtn.Font = Enum.Font.GothamMedium
		savePluginBtn.TextSize = 11
		savePluginBtn.Text = "💾 Lưu Local Plugin"
		savePluginBtn.Parent = root
		local spCorner = Instance.new("UICorner")
		spCorner.CornerRadius = UDim.new(0, 6)
		spCorner.Parent = savePluginBtn

		savePluginBtn.MouseButton1Click:Connect(function()
			local ref = if state.lastCommitSha ~= "" then state.lastCommitSha else activeBranch
			local rawPluginUrl = buildRawUrl(ref, "plugin/StudioLiveBridge.server.luau")
			local okP, body = pcall(function()
				return HttpService:GetAsync(rawPluginUrl, true)
			end)
			if okP and type(body) == "string" and #body > 100 then
				local old = ServerStorage:FindFirstChild("ArenaLiveBridgePlugin")
				if old then
					old:Destroy()
				end
				local s = Instance.new("Script")
				s.Name = "ArenaLiveBridgePlugin"
				s.Archivable = false
				s.Source = body
				s.Parent = ServerStorage
				Selection:Set({ s })
				state.lastStatus = "Chuột phải ArenaLiveBridgePlugin -> Save as Local Plugin"
				updateUi()
				print(
					"[Arena Bridge] Đã tạo ServerStorage.ArenaLiveBridgePlugin! Hãy chuột phải vào nó trong Explorer -> chọn 'Save as Local Plugin...'"
				)
			else
				warn("[Arena Bridge] Không tải được mã nguồn plugin từ CDN.")
			end
		end)
	end

	syncNowBtn.MouseButton1Click:Connect(function()
		state.lastCommitSha = ""
		state.syncedHash = ""
		state.lastStatus = "Đang tải bản mới nhất từ GitHub CDN..."
		updateUi()
		task.spawn(syncOnceNow)
	end)

	toggleBtn.MouseButton1Click:Connect(function()
		if state.connected then
			stopPolling("Đã tạm dừng tự động đồng bộ")
		else
			startPolling()
		end
	end)

	snapshotBtn.MouseButton1Click:Connect(function()
		local summary = buildExplorerSummary()
		exportBox.Text = summary
		exportBox:CaptureFocus()
		exportBox.SelectionStart = 1
		exportBox.CursorPosition = #summary + 1
		state.lastStatus = "Nhấn Ctrl+C để copy Explorer gửi cho AI"
		updateUi()
	end)

	table.insert(uiUpdaters, function()
		if state.connected then
			statusLabel.Text = string.format(
				"● ĐÃ KẾT NỐI CDN | Rojo v%d (%d script)\n%s",
				state.syncedVersion,
				state.syncedFiles,
				state.lastStatus
			)
			statusLabel.TextColor3 = Color3.fromRGB(110, 231, 183)
			toggleBtn.Text = "Tạm dừng"
			toggleBtn.BackgroundColor3 = Color3.fromRGB(185, 48, 60)
		else
			statusLabel.Text = "○ Tạm dừng — " .. state.lastStatus
			statusLabel.TextColor3 = Color3.fromRGB(252, 211, 77)
			toggleBtn.Text = "Kết nối lại"
			toggleBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
		end
	end)
end

-- ============================================================================
-- CƠ CHẾ ĐỒNG BỘ QUA ATOM FEED + RAW CDN (KHÔNG BAO GIỜ BỊ HTTP 403!)
-- ============================================================================
local syncingLock = false

syncOnceNow = function()
	if syncingLock then
		return
	end
	syncingLock = true

	local okAtom, atomResp = pcall(function()
		if BASE_COMMIT_SHA ~= "" then
			return { StatusCode = 0, Body = "" } -- không cần Atom feed khi đã ghim SHA
		end
		return HttpService:RequestAsync({
			Url = getAtomFeedUrl() .. "?_t=" .. tostring(os.time()),
			Method = "GET",
			Headers = {
				["Cache-Control"] = "no-cache",
			},
		})
	end)

	local targetRef = activeBranch
	local detectedSha = ""
	local pinned = BASE_COMMIT_SHA ~= ""

	if pinned then
		-- Ghim bản build: tải đúng SHA đã push, không hỏi Atom feed.
		targetRef = BASE_COMMIT_SHA
		detectedSha = BASE_COMMIT_SHA
	elseif okAtom and atomResp and atomResp.StatusCode == 200 and type(atomResp.Body) == "string" then
		detectedSha = string.match(atomResp.Body, "Commit/(%x+)") or ""
		if detectedSha ~= "" then
			targetRef = detectedSha
		end
	end

	-- Nếu SHA không đổi so với lần trước thì không cần tải lại file lớn
	if detectedSha ~= "" and detectedSha == state.lastCommitSha and state.syncedHash ~= "" then
		state.lastStatus = "Trực tuyến (Đã ở bản mới nhất)"
		updateUi()
		syncingLock = false
		return
	end

	local bundleUrl = buildRawUrl(targetRef, "studio-sync.json") .. "?_t=" .. tostring(os.time())
	local okRaw, rawBody = pcall(function()
		return HttpService:GetAsync(bundleUrl, true)
	end)

	if okRaw and type(rawBody) == "string" then
		local okJson, bundle = pcall(function()
			return HttpService:JSONDecode(rawBody)
		end)
		if okJson and type(bundle) == "table" then
			if detectedSha ~= "" then
				state.lastCommitSha = detectedSha
			end
			if tostring(bundle.hash or "") ~= state.syncedHash then
				state.pollInterval = 8
				applyBundle(bundle)
			else
				state.lastStatus = "Trực tuyến (Đã đồng bộ mới nhất)"
				state.pollInterval = 30
			end
		else
			state.lastStatus = "Lỗi đọc dữ liệu JSON"
		end
	else
		state.lastStatus = "Đang thử lại CDN..."
	end

	updateUi()
	syncingLock = false
end

stopPolling = function(reason)
	state.connected = false
	state.pollGen += 1
	state.lastStatus = reason or "Đã dừng"
	updateUi()
end

startPolling = function()
	state.pollGen += 1
	local myGen = state.pollGen
	state.connected = true
	state.lastStatus = "Đang tải gói brige từ GitHub CDN..."
	updateUi()

	task.spawn(function()
		while state.running and state.connected and state.pollGen == myGen do
			syncOnceNow()
			task.wait(state.pollInterval or 8)
		end
	end)
end

-- Khởi tạo giao diện Plugin hoặc Floating Panel
local floatingGui = nil
if hasPlugin then
	local toolbar = pluginObj:CreateToolbar("Arena Bridge")
	local pluginBtn = toolbar:CreateButton(
		"Arena Live Bridge",
		"Mở bảng kết nối trực tiếp brige ↔ Studio qua GitHub CDN",
		"rbxassetid://4458901886"
	)
	pluginBtn.ClickableWhenViewportHidden = true

	local widgetInfo = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Float,
		true,
		false,
		340,
		220,
		300,
		205
	)
	local dockWidget = pluginObj:CreateDockWidgetPluginGui("ArenaGitHubBridgeWidget_v3", widgetInfo)
	dockWidget.Title = "brige Live Bridge v3"
	createBridgeUi(dockWidget, false)

	pluginBtn.Click:Connect(function()
		dockWidget.Enabled = not dockWidget.Enabled
	end)

	pluginObj.Unloading:Connect(function()
		state.running = false
		stopPolling("Plugin tải lại")
	end)
else
	local oldGui = CoreGui:FindFirstChild("ArenaLiveBridgeFloatingGui")
	if oldGui then
		oldGui:Destroy()
	end
	floatingGui = Instance.new("ScreenGui")
	floatingGui.Name = "ArenaLiveBridgeFloatingGui"
	floatingGui.ResetOnSpawn = false
	floatingGui.Parent = CoreGui
	createBridgeUi(floatingGui, true)
end

_G.__ARENA_LIVE_BRIDGE_CLEANUP = function()
	state.running = false
	stopPolling("Đã đóng")
	if floatingGui then
		floatingGui:Destroy()
		floatingGui = nil
	end
end

print(string.format("[brige Bridge v3] 🚀 %s/%s · %s · %s", GITHUB_OWNER, GITHUB_REPO,
	if BASE_COMMIT_SHA ~= "" then ("ghim SHA " .. string.sub(BASE_COMMIT_SHA, 1, 7)) else activeBranch,
	"đang tải gói từ GitHub CDN..."))
startPolling()
