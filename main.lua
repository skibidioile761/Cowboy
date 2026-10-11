--[[
    TEST MENU v5 (Client)
    Đặt vào: StarterPlayer > StarterPlayerScripts (LocalScript)
    Phím tắt: RightShift = mở/đóng menu
    - Auto TP: tp dưới chân địch gần nhất (bỏ qua đồng đội), hết mục tiêu thì về chỗ cũ
    - Auto Hit: loop FireServer() của Knife.Melee, chỉnh tốc độ bằng Hit Delay
    - ESP Name, Chams, Rainbow, Menu Blur
]]

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------------
-- CONFIG / THEME
---------------------------------------------------------------------
local Config = {
	AutoTP = false,
	TeamCheck = true,   -- bật: bỏ qua đồng đội | tắt: coi tất cả là địch
	LayDown = true,     -- nằm ngang dưới đất, mặt hướng lên
	ESPName = false,
	Chams = false,
	Rainbow = true,     -- hiệu ứng cầu vồng (menu + ESP/Chams địch)
	MenuBlur = true,    -- làm mờ nền khi mở menu

	AutoHit = false,    -- loop đánh Knife.Melee
	HitDelay = 0.1,     -- giây giữa mỗi lần đánh

	Smoothness = 0.15,  -- 0 = tức thì, 1 = rất mượt/chậm
	Overlap = 1,        -- số studs người mình "ăn" vào chân mục tiêu (lớn = đụng sâu hơn)
	MaxRange = 250,     -- chỉ tp người trong phạm vi này (studs)
}

local THEME = {
	Bg = Color3.fromRGB(22, 22, 28),
	Title = Color3.fromRGB(32, 32, 42),
	Row = Color3.fromRGB(42, 42, 54),
	Text = Color3.fromRGB(240, 240, 250),
	SubText = Color3.fromRGB(165, 165, 185),
	On = Color3.fromRGB(90, 120, 255),
	Off = Color3.fromRGB(70, 70, 85),
	Stroke = Color3.fromRGB(70, 70, 90),
}

local COLORS = {
	Enemy = Color3.fromRGB(255, 70, 70),
	Team = Color3.fromRGB(80, 255, 120),
}

-- cập nhật mỗi frame bởi vòng lặp cầu vồng ở cuối file
local rainbowColor = Color3.fromRGB(255, 0, 0)
local accent = THEME.On
local rainbowGradients = {}  -- { grad = UIGradient, stroke = UIStroke|nil }
local accentUpdaters = {}    -- function(accent)

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------
local function new(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	inst.Parent = parent
	return inst
end

local function getRoot(char)
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function isAlive(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

---------------------------------------------------------------------
-- TEAM DETECTION (nhiều cách, tự dò xem game của bạn lưu team ở đâu)
---------------------------------------------------------------------
-- Nếu game bạn lưu team theo cách riêng, điền hàm này (trả về "khóa team"):
-- CUSTOM_TEAM_RESOLVER = function(plr) return plr:GetAttribute("Side") end
local CUSTOM_TEAM_RESOLVER = nil

local function hasTeamWord(name)
	return string.find(string.lower(name), "team", 1, true) ~= nil
end

local function attrKey(inst)
	if not inst then return nil end
	for name, v in pairs(inst:GetAttributes()) do
		if hasTeamWord(name) and v ~= nil then return v end
	end
	return nil
end

local function valueKey(inst)
	if not inst then return nil end
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("ValueBase") and hasTeamWord(c.Name) and c.Value ~= nil then
			return c.Value
		end
	end
	return nil
end

local TEAM_SOURCES = {
	{ name = "Team object", get = function(plr) return plr.Team end },
	{ name = "Player attribute", get = function(plr) return attrKey(plr) end },
	{ name = "Player value", get = function(plr)
		return valueKey(plr) or valueKey(plr:FindFirstChild("leaderstats"))
	end },
	{ name = "TeamColor", get = function(plr)
		if plr.Neutral then return nil end
		return plr.TeamColor
	end },
	{ name = "Character attribute", get = function(plr) return attrKey(plr.Character) end },
	{ name = "Character value", get = function(plr) return valueKey(plr.Character) end },
	-- thư mục chứa nhân vật (vd workspace.Red / workspace.Blue): cần ít nhất 2 nhóm khác nhau
	{ name = "Character folder", needsVariety = true, get = function(plr)
		local c = plr.Character
		local par = c and c.Parent
		if par and par ~= workspace then return par end
		return nil
	end },
}

local activeSource = nil

local function detectTeamSource()
	local players = Players:GetPlayers()
	for i, src in ipairs(TEAM_SOURCES) do
		local ok, mine = pcall(src.get, LocalPlayer)
		if ok and mine ~= nil then
			if not src.needsVariety then
				activeSource = i
				return
			end
			local seen, n = {}, 0
			for _, p in ipairs(players) do
				local ok2, k = pcall(src.get, p)
				if ok2 and k ~= nil and not seen[k] then
					seen[k] = true
					n += 1
				end
			end
			if n >= 2 then
				activeSource = i
				return
			end
		end
	end
	-- không tìm thấy thì giữ nguồn cũ (vd lúc mình đang chết/chưa có nhân vật)
end

if not CUSTOM_TEAM_RESOLVER then
	task.spawn(function()
		while true do
			detectTeamSource()
			task.wait(0.5)
		end
	end)
end

local function getTeamKey(plr)
	if CUSTOM_TEAM_RESOLVER then
		local ok, k = pcall(CUSTOM_TEAM_RESOLVER, plr)
		return ok and k or nil
	end
	if activeSource then
		local ok, k = pcall(TEAM_SOURCES[activeSource].get, plr)
		return ok and k or nil
	end
	return nil
end

-- cùng team thật sự (dùng để tô màu ESP)
local function sameTeam(plr)
	local mine = getTeamKey(LocalPlayer)
	return mine ~= nil and mine == getTeamKey(plr)
end

-- in ra Developer Console (F9 / Output) để kiểm tra việc nhận diện team
local function dumpTeams()
	local srcName = CUSTOM_TEAM_RESOLVER and "custom"
		or (activeSource and TEAM_SOURCES[activeSource].name)
		or "khong tim thay"
	print("[TeamCheck] nguon dang dung: " .. srcName)
	for _, p in ipairs(Players:GetPlayers()) do
		print(string.format("[TeamCheck] %s | cung team: %s | khoa: %s",
			p.Name, tostring(p == LocalPlayer or sameTeam(p)), tostring(getTeamKey(p))))
	end
end

-- đồng đội theo Team Check: tắt Team Check thì không ai bị coi là đồng đội
local function isTeammate(plr)
	return Config.TeamCheck and sameTeam(plr)
end

local function getNearestEnemy()
	local myRoot = getRoot(LocalPlayer.Character)
	if not myRoot then return nil end

	local best, bestDist = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and not isTeammate(plr) then
			local char = plr.Character
			local root = getRoot(char)
			if root and isAlive(char) then
				local d = (root.Position - myRoot.Position).Magnitude
				if d < bestDist and d <= Config.MaxRange then
					best, bestDist = plr, d
				end
			end
		end
	end
	return best
end

-- Y thấp nhất (đáy chân) của nhân vật, bỏ qua khối hitbox mở rộng
local function getFeetY(char)
	local lowest = math.huge
	for _, p in ipairs(char:GetChildren()) do
		if p:IsA("BasePart") then
			lowest = math.min(lowest, p.Position.Y - p.Size.Y / 2)
		end
	end
	return lowest
end

-- Khoảng cách từ tâm HRP của mình đến mặt trên cùng của cơ thể mình
local function getOwnTopOffset(char, root)
	if Config.LayDown then
		return root.Size.Z / 2 + 0.2 -- nằm ngang: độ dày cơ thể
	end
	local top = root.Position.Y
	for _, p in ipairs(char:GetChildren()) do
		if p:IsA("BasePart") then
			top = math.max(top, p.Position.Y + p.Size.Y / 2)
		end
	end
	return top - root.Position.Y
end

---------------------------------------------------------------------
-- AUTO TELEPORT (địch gần nhất trong Range, bỏ qua đồng đội)
---------------------------------------------------------------------
local savedCFrame = nil   -- vị trí "nhà": chỗ đứng trước khi tp tới địch
local attached = false     -- đang bám dưới đất địch hay không
local noTargetSince = nil  -- thời điểm bắt đầu không còn mục tiêu
local noclipCache = {}

local NO_TARGET_GRACE = 0.3 -- giây chờ trước khi quay về (tránh giật khi đổi mục tiêu)

-- Quay về chỗ cũ, bật lại va chạm, thoát PlatformStand
local function detach()
	local char = LocalPlayer.Character
	local root = getRoot(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")

	if hum then hum.PlatformStand = false end
	for part in pairs(noclipCache) do
		if part.Parent then part.CanCollide = true end
	end
	table.clear(noclipCache)

	if root and savedCFrame and attached then
		root.CFrame = savedCFrame
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end

	attached = false
	noTargetSince = nil
end

local function setAutoTP(state)
	Config.AutoTP = state
	if state then
		attached = false
		noTargetSince = nil
		local root = getRoot(LocalPlayer.Character)
		if root then savedCFrame = root.CFrame end
	else
		detach()
		savedCFrame = nil
	end
end

-- Noclip chỉ khi đang bám dưới đất địch
RunService.Stepped:Connect(function()
	if not Config.AutoTP or not attached then return end
	local char = LocalPlayer.Character
	if not char then return end
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") and p.CanCollide then
			noclipCache[p] = true
			p.CanCollide = false
		end
	end
end)

RunService.Heartbeat:Connect(function()
	if not Config.AutoTP then return end

	local char = LocalPlayer.Character
	local root = getRoot(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return end

	local target = getNearestEnemy()
	local tChar = target and target.Character
	local tRoot = getRoot(tChar)

	-- Không còn mục tiêu (chết/reset/ra khỏi Range)
	if not target or not tRoot then
		if attached then
			-- giữ yên một chút rồi quay về chỗ cũ, không để rơi xuống void
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			noTargetSince = noTargetSince or os.clock()
			if os.clock() - noTargetSince >= NO_TARGET_GRACE then
				detach()
			end
		else
			-- đang rảnh: luôn cập nhật "nhà" = chỗ bạn đang đứng
			savedCFrame = root.CFrame
		end
		return
	end

	noTargetSince = nil

	-- Mới bắt đầu bám mục tiêu: nhớ vị trí hiện tại
	if not attached then
		savedCFrame = root.CFrame
		attached = true
	end

	-- Chống rơi void: nếu tụt quá sâu thì về nhà ngay
	if root.Position.Y < workspace.FallenPartsDestroyHeight + 30 then
		detach()
		return
	end

	-- Giữ nguyên X/Z của mục tiêu. Y tính theo đáy chân thật của họ:
	-- mặt trên cơ thể mình nằm cao hơn đáy chân họ "Overlap" studs => chắc chắn chạm hitbox.
	local feetY = getFeetY(tChar)
	if feetY == math.huge then feetY = tRoot.Position.Y - 3 end

	local y = feetY + Config.Overlap - getOwnTopOffset(char, root)
	local goal = CFrame.new(tRoot.Position.X, y, tRoot.Position.Z)
	if Config.LayDown then
		goal = goal * CFrame.Angles(math.rad(90), 0, 0) -- nằm ngửa, nhìn lên
	end

	local alpha = math.clamp(1 - Config.Smoothness, 0.05, 1)
	hum.PlatformStand = true
	root.CFrame = root.CFrame:Lerp(goal, alpha)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end)

LocalPlayer.CharacterAdded:Connect(function()
	-- mình chết/respawn: reset trạng thái, auto tp tiếp tục với nhân vật mới
	attached = false
	noTargetSince = nil
	savedCFrame = nil
	table.clear(noclipCache)
end)

---------------------------------------------------------------------
-- AUTO HIT (loop FireServer của Knife.Melee)
---------------------------------------------------------------------
local hitToken = 0

local function getMeleeEvent()
	local char = LocalPlayer.Character
	local knife = char and char:FindFirstChild("Knife")
	return knife and knife:FindFirstChild("Melee")
end

local function setAutoHit(state)
	Config.AutoHit = state
	hitToken += 1 -- hủy vòng lặp cũ (tránh chạy chồng khi bật/tắt nhanh)
	if not state then return end

	local myToken = hitToken
	task.spawn(function()
		while Config.AutoHit and hitToken == myToken do
			local event = getMeleeEvent()
			if event and isAlive(LocalPlayer.Character) then
				pcall(function() event:FireServer() end)
			end
			task.wait(math.max(Config.HitDelay, 0.03))
		end
	end)
end

---------------------------------------------------------------------
-- ESP NAME + CHAMS
---------------------------------------------------------------------
local ESP = {}

local function destroyESP(plr)
	local d = ESP[plr]
	if d then
		if d.bb then d.bb:Destroy() end
		if d.hl then d.hl:Destroy() end
		ESP[plr] = nil
	end
end

local function buildESP(plr, char, head)
	local bb = new("BillboardGui", {
		Name = "ESP_Name",
		Adornee = head,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(160, 24),
		StudsOffset = Vector3.new(0, 2.2, 0),
		Parent = head,
	})
	local lbl = new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextStrokeTransparency = 0.4,
		Parent = bb,
	})
	local hl = new("Highlight", {
		Name = "ESP_Chams",
		Adornee = char,
		FillTransparency = 0.5,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Parent = char,
	})
	ESP[plr] = { char = char, bb = bb, lbl = lbl, hl = hl }
end

RunService.Heartbeat:Connect(function()
	local anyOn = Config.ESPName or Config.Chams
	local myRoot = getRoot(LocalPlayer.Character)

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			local char = plr.Character
			local head = char and char:FindFirstChild("Head")
			local data = ESP[plr]

			if not anyOn or not char or not head or not isAlive(char) then
				destroyESP(plr)
			else
				if data and data.char ~= char then
					destroyESP(plr)
					data = nil
				end
				if not data then
					buildESP(plr, char, head)
					data = ESP[plr]
				end

				local color
				if sameTeam(plr) then
					color = COLORS.Team
				else
					color = Config.Rainbow and rainbowColor or COLORS.Enemy
				end
				data.bb.Enabled = Config.ESPName
				data.hl.Enabled = Config.Chams
				data.hl.FillColor = color
				data.hl.OutlineColor = color
				data.lbl.TextColor3 = color

				local tRoot = getRoot(char)
				local dist = (myRoot and tRoot) and math.floor((tRoot.Position - myRoot.Position).Magnitude) or 0
				data.lbl.Text = string.format("%s [%dm]", plr.DisplayName, dist)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(destroyESP)

---------------------------------------------------------------------
-- GUI (v5)
---------------------------------------------------------------------
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local old = PlayerGui:FindFirstChild("Gui")
if old then old:Destroy() end
local oldBlur = Lighting:FindFirstChild("TestMenuBlur")
if oldBlur then oldBlur:Destroy() end

local gui = new("ScreenGui", {
	Name = "Kid's Gui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 999,
	Parent = PlayerGui,
})

local blur = new("BlurEffect", { Name = "TestMenuBlur", Size = 0, Parent = Lighting })
local BLUR_SIZE = 14

local function tween(obj, dur, props, style, dir)
	local t = TweenService:Create(
		obj,
		TweenInfo.new(dur, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

local isOpen = false

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
	ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
	ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
	ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
	ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
})

local function addRainbowStroke(parent, thickness)
	local stroke = new("UIStroke", { Thickness = thickness, Color = Color3.new(1, 1, 1), Parent = parent })
	local grad = new("UIGradient", { Color = RAINBOW, Parent = stroke })
	table.insert(rainbowGradients, { grad = grad, stroke = stroke })
	return stroke
end

local WIN_W, WIN_H = 500, 312
local FULL_SIZE = UDim2.fromOffset(WIN_W, WIN_H)

local main = new("CanvasGroup", {
	Name = "Main",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(WIN_W * 0.8, WIN_H * 0.8),
	GroupTransparency = 1,
	BackgroundColor3 = THEME.Bg,
	BorderSizePixel = 0,
	Visible = false,
	Parent = gui,
}, {
	new("UICorner", { CornerRadius = UDim.new(0, 16) }),
})
addRainbowStroke(main, 2)

local uiScale = new("UIScale", { Parent = main })
local function updateScale()
	local cam = workspace.CurrentCamera
	if cam then
		local vs = cam.ViewportSize
		uiScale.Scale = math.clamp(math.min((vs.X - 20) / WIN_W, (vs.Y - 20) / WIN_H), 0.5, 1)
	end
end
updateScale()

-- Lớp màu accent mờ ở góc trên trái (đổi màu theo cầu vồng)
local tint = new("Frame", {
	Name = "Tint",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	Parent = main,
})
local tintGrad = new("UIGradient", {
	Color = ColorSequence.new(THEME.On),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.65, 1),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Rotation = 40,
	Parent = tint,
})
table.insert(accentUpdaters, function(acc) tintGrad.Color = ColorSequence.new(acc) end)

-- Title bar (kéo ở đây)
local titleBar = new("Frame", {
	Name = "TitleBar",
	Size = UDim2.new(1, 0, 0, 38),
	BackgroundColor3 = THEME.Title,
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	Parent = main,
})

local titleLbl = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(16, 0),
	Size = UDim2.new(1, -60, 1, 0),
	Text = "COWBOY",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBlack,
	TextSize = 17,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = titleBar,
})
table.insert(rainbowGradients, { grad = new("UIGradient", { Color = RAINBOW, Parent = titleLbl }) })

new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(126, 3),
	Size = UDim2.fromOffset(30, 38),
	Text = "v5",
	TextColor3 = THEME.SubText,
	Font = Enum.Font.GothamMedium,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = titleBar,
})

local titleLine = new("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, 2),
	BackgroundColor3 = THEME.On,
	BorderSizePixel = 0,
	Parent = titleBar,
})
table.insert(accentUpdaters, function(acc) titleLine.BackgroundColor3 = acc end)

local closeBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(24, 24),
	BackgroundColor3 = Color3.fromRGB(210, 65, 75),
	Text = "X",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	AutoButtonColor = false,
	Parent = titleBar,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

closeBtn.MouseEnter:Connect(function()
	tween(closeBtn, 0.3, { BackgroundColor3 = Color3.fromRGB(240, 90, 100), Rotation = 90 }, Enum.EasingStyle.Back)
end)
closeBtn.MouseLeave:Connect(function()
	tween(closeBtn, 0.3, { BackgroundColor3 = Color3.fromRGB(210, 65, 75), Rotation = 0 }, Enum.EasingStyle.Back)
end)

---------------------------------------------------------------------
-- TOAST (thông báo nhỏ khi bật/tắt chức năng)
---------------------------------------------------------------------
local toast = new("Frame", {
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 70),
	Size = UDim2.fromOffset(200, 36),
	BackgroundColor3 = THEME.Bg,
	BorderSizePixel = 0,
	Parent = gui,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
addRainbowStroke(toast, 1.5)

local toastDot = new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 14, 0.5, 0),
	Size = UDim2.fromOffset(10, 10),
	BackgroundColor3 = COLORS.Team,
	BorderSizePixel = 0,
	Parent = toast,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

local toastLbl = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(34, 0),
	Size = UDim2.new(1, -46, 1, 0),
	Text = "",
	TextColor3 = THEME.Text,
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = toast,
})

local toastId = 0
local function showToast(text, on)
	toastId += 1
	local id = toastId
	toastLbl.Text = text
	toastDot.BackgroundColor3 = on and COLORS.Team or COLORS.Enemy
	tween(toast, 0.5, { Position = UDim2.new(0.5, 0, 1, -26) }, Enum.EasingStyle.Back)
	task.delay(1.6, function()
		if toastId == id then
			tween(toast, 0.35, { Position = UDim2.new(0.5, 0, 1, 70) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		end
	end)
end

---------------------------------------------------------------------
-- TABS + PAGES
---------------------------------------------------------------------
local tabOrder = { "Combat", "Visuals" }
local TAB_W, TAB_GAP = 92, 6

local tabBar = new("Frame", {
	Position = UDim2.fromOffset(12, 46),
	Size = UDim2.new(1, -24, 0, 30),
	BackgroundTransparency = 1,
	Parent = main,
})

new("Frame", { -- đường kẻ dưới tab
	Position = UDim2.fromOffset(0, 29),
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = THEME.Row,
	BorderSizePixel = 0,
	Parent = tabBar,
})

local tabButtons = {}
for i, name in ipairs(tabOrder) do
	tabButtons[name] = new("TextButton", {
		Position = UDim2.fromOffset((i - 1) * (TAB_W + TAB_GAP), 0),
		Size = UDim2.fromOffset(TAB_W, 27),
		BackgroundTransparency = 1,
		Text = string.upper(name),
		TextColor3 = THEME.SubText,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		AutoButtonColor = false,
		Parent = tabBar,
	})
end

local indicator = new("Frame", {
	Position = UDim2.fromOffset(0, 27),
	Size = UDim2.fromOffset(TAB_W, 3),
	BackgroundColor3 = THEME.On,
	BorderSizePixel = 0,
	Parent = tabBar,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
table.insert(accentUpdaters, function(acc) indicator.BackgroundColor3 = acc end)

local pagesFrame = new("Frame", {
	Position = UDim2.fromOffset(12, 86),
	Size = UDim2.new(1, -24, 1, -122),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	Parent = main,
})

local pages = {}
for _, name in ipairs(tabOrder) do
	pages[name] = new("CanvasGroup", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = pagesFrame,
	}, {
		new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -3, 0, 42),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

-- Footer
new("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -26),
	Size = UDim2.new(1, -24, 0, 1),
	BackgroundColor3 = THEME.Row,
	BorderSizePixel = 0,
	Parent = main,
})
local footerLbl = new("TextLabel", {
	AnchorPoint = Vector2.new(0, 1),
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 14, 1, -4),
	Size = UDim2.new(1, -28, 0, 18),
	Text = "RightShift: mo/dong menu",
	TextColor3 = THEME.SubText,
	Font = Enum.Font.GothamMedium,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = main,
})

-- Hiệu ứng ô bật lên lần lượt (stagger)
local function animateCells(page)
	local i = 0
	for _, slot in ipairs(page:GetChildren()) do
		local cell = slot:IsA("Frame") and slot:FindFirstChildOfClass("CanvasGroup")
		if cell then
			i += 1
			local pop = cell:FindFirstChild("Pop")
			cell.GroupTransparency = 1
			pop.Scale = 0.8
			task.delay((i - 1) * 0.05, function()
				tween(cell, 0.35, { GroupTransparency = 0 })
				tween(pop, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
			end)
		end
	end
end

local currentTab, currentIdx = nil, 0
local function selectTab(name)
	if currentTab == name then return end
	local idx = table.find(tabOrder, name)
	local dir = (idx > currentIdx) and 1 or -1
	local prev = currentTab and pages[currentTab]
	currentTab, currentIdx = name, idx

	if prev then
		tween(prev, 0.18, { GroupTransparency = 1, Position = UDim2.fromOffset(-30 * dir, 0) })
		task.delay(0.18, function()
			if pages[currentTab] ~= prev then prev.Visible = false end
		end)
	end

	local page = pages[name]
	page.Visible = true
	page.GroupTransparency = 1
	page.Position = UDim2.fromOffset(30 * dir, 0)
	tween(page, 0.4, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) })
	if isOpen then animateCells(page) end

	for i, n in ipairs(tabOrder) do
		tween(tabButtons[n], 0.25, { TextColor3 = (n == name) and THEME.Text or THEME.SubText })
		if n == name then
			tween(indicator, 0.45, {
				Position = UDim2.fromOffset((i - 1) * (TAB_W + TAB_GAP), 27),
			}, Enum.EasingStyle.Back)
		end
	end
end

for _, name in ipairs(tabOrder) do
	local b = tabButtons[name]
	b.Activated:Connect(function() selectTab(name) end)
	b.MouseEnter:Connect(function()
		if currentTab ~= name then tween(b, 0.15, { TextColor3 = THEME.Text }) end
	end)
	b.MouseLeave:Connect(function()
		if currentTab ~= name then tween(b, 0.15, { TextColor3 = THEME.SubText }) end
	end)
end

---------------------------------------------------------------------
-- COMPONENTS
---------------------------------------------------------------------
local order = 0
local function nextOrder()
	order += 1
	return order
end

local ROW_HOVER = Color3.fromRGB(54, 54, 72)

-- slot (để layout xếp) > cell (CanvasGroup, có UIScale "Pop" để zoom từ tâm)
local function makeCell(page)
	local slot = new("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
		Parent = page,
	})
	return new("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.Row,
		BorderSizePixel = 0,
		Parent = slot,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 10) }),
		new("UIScale", { Name = "Pop" }),
	})
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

-- Gợn sóng lan ra từ điểm bấm
local function ripple(cell, input)
	local rel = (Vector2.new(input.Position.X, input.Position.Y) - cell.AbsolutePosition)
		/ math.max(uiScale.Scale, 0.01)
	local r = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(rel.X, rel.Y),
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = cell,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	tween(r, 0.6, { Size = UDim2.fromOffset(220, 220), BackgroundTransparency = 1 })
	task.delay(0.65, function() r:Destroy() end)
end

-- Công tắc: bấm cả ô, núm trượt co giãn, thanh accent bên trái, ripple, toast
local function addToggle(page, text, default, callback)
	local state = default
	local cell = makeCell(page)
	local pop = cell:FindFirstChild("Pop")

	local bar = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, 3, state and 0.6 or 0, 0),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Parent = cell,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -74, 1, 0),
		Text = text,
		TextColor3 = state and THEME.Text or THEME.SubText,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = cell,
	})

	local sw = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(44, 22),
		BackgroundColor3 = state and accent or THEME.Off,
		BorderSizePixel = 0,
		Parent = cell,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = state and UDim2.fromOffset(33, 11) or UDim2.fromOffset(11, 11),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = sw,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

	local hit = new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 10,
		Parent = cell,
	})

	local function render()
		tween(knob, 0.3, {
			Position = state and UDim2.fromOffset(33, 11) or UDim2.fromOffset(11, 11),
		}, Enum.EasingStyle.Back)
		local s = tween(knob, 0.1, { Size = UDim2.fromOffset(22, 18) })
		s.Completed:Once(function()
			tween(knob, 0.3, { Size = UDim2.fromOffset(18, 18) }, Enum.EasingStyle.Back)
		end)
		tween(bar, 0.35, { Size = UDim2.new(0, 3, state and 0.6 or 0, 0) }, Enum.EasingStyle.Back)
		tween(label, 0.25, { TextColor3 = state and THEME.Text or THEME.SubText })
	end

	hit.InputBegan:Connect(function(input)
		if isPress(input) then ripple(cell, input) end
	end)
	hit.Activated:Connect(function()
		state = not state
		render()
		callback(state)
		showToast(text .. (state and "  ON" or "  OFF"), state)
	end)

	hit.MouseEnter:Connect(function()
		tween(cell, 0.2, { BackgroundColor3 = ROW_HOVER })
	end)
	hit.MouseLeave:Connect(function()
		tween(cell, 0.2, { BackgroundColor3 = THEME.Row })
		tween(pop, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	hit.MouseButton1Down:Connect(function()
		tween(pop, 0.1, { Scale = 0.95 })
	end)
	hit.MouseButton1Up:Connect(function()
		tween(pop, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end)

	table.insert(accentUpdaters, function(acc)
		sw.BackgroundColor3 = sw.BackgroundColor3:Lerp(state and acc or THEME.Off, 0.25)
		bar.BackgroundColor3 = acc
	end)
end

local function addSlider(page, text, min, max, default, decimals, callback)
	local cell = makeCell(page)

	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 4),
		Size = UDim2.new(0.6, 0, 0, 18),
		Text = text,
		TextColor3 = THEME.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = cell,
	})

	local valueLbl = new("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 4),
		Size = UDim2.new(0.35, 0, 0, 18),
		TextColor3 = THEME.SubText,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = cell,
	})

	local bar = new("Frame", {
		Position = UDim2.new(0, 14, 0, 29),
		Size = UDim2.new(1, -28, 0, 6),
		BackgroundColor3 = THEME.Off,
		BorderSizePixel = 0,
		Parent = cell,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

	local fill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = THEME.On,
		BorderSizePixel = 0,
		Parent = bar,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = bar,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

	table.insert(accentUpdaters, function(acc) fill.BackgroundColor3 = acc end)

	local function setRel(rel, fire)
		rel = math.clamp(rel, 0, 1)
		local mult = 10 ^ decimals
		local val = math.floor((min + (max - min) * rel) * mult + 0.5) / mult
		tween(fill, 0.1, { Size = UDim2.fromScale(rel, 1) }, Enum.EasingStyle.Quad)
		tween(knob, 0.1, { Position = UDim2.fromScale(rel, 0.5) }, Enum.EasingStyle.Quad)
		valueLbl.Text = tostring(val)
		if fire then callback(val) end
	end

	setRel((default - min) / (max - min), false)

	local dragging = false
	local function fromInput(input)
		setRel((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, true)
	end

	cell.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging = true
			tween(knob, 0.25, { Size = UDim2.fromOffset(18, 18) }, Enum.EasingStyle.Back)
			fromInput(input)
		end
	end)
	cell.MouseEnter:Connect(function()
		tween(cell, 0.2, { BackgroundColor3 = ROW_HOVER })
	end)
	cell.MouseLeave:Connect(function()
		tween(cell, 0.2, { BackgroundColor3 = THEME.Row })
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			fromInput(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if isPress(input) and dragging then
			dragging = false
			tween(knob, 0.25, { Size = UDim2.fromOffset(14, 14) }, Enum.EasingStyle.Back)
		end
	end)
end

-- Nội dung (chỉ dùng chữ không dấu vì font Gotham không hiển thị tiếng Việt có dấu)
addToggle(pages.Combat, "Auto TP", Config.AutoTP, setAutoTP)
addToggle(pages.Combat, "Auto Hit", Config.AutoHit, setAutoHit)
addToggle(pages.Combat, "Team Check", Config.TeamCheck, function(v)
	Config.TeamCheck = v
	if v then dumpTeams() end
end)
addToggle(pages.Combat, "Lay Down", Config.LayDown, function(v) Config.LayDown = v end)
addSlider(pages.Combat, "Smooth", 0, 1, Config.Smoothness, 2, function(v) Config.Smoothness = v end)
addSlider(pages.Combat, "Overlap", 0, 4, Config.Overlap, 1, function(v) Config.Overlap = v end)
addSlider(pages.Combat, "Range", 50, 1000, Config.MaxRange, 0, function(v) Config.MaxRange = v end)
addSlider(pages.Combat, "Hit Delay", 0.03, 1, Config.HitDelay, 2, function(v) Config.HitDelay = v end)

addToggle(pages.Visuals, "ESP Name", Config.ESPName, function(v) Config.ESPName = v end)
addToggle(pages.Visuals, "Chams", Config.Chams, function(v) Config.Chams = v end)
addToggle(pages.Visuals, "Rainbow", Config.Rainbow, function(v) Config.Rainbow = v end)
addToggle(pages.Visuals, "Menu Blur", Config.MenuBlur, function(v)
	Config.MenuBlur = v
	tween(blur, 0.4, { Size = (isOpen and v) and BLUR_SIZE or 0 })
end)

---------------------------------------------------------------------
-- DRAG MENU
---------------------------------------------------------------------
do
	local dragging, dragStart, startPos = false, nil, nil

	titleBar.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
			tween(main, 0.2, { GroupTransparency = 0.08 })
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					tween(main, 0.25, { GroupTransparency = 0 })
				end
			end)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			tween(main, 0.08, {
				Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y
				),
			}, Enum.EasingStyle.Quad)
		end
	end)
end

---------------------------------------------------------------------
-- NÚT MỞ MENU (kéo được, chạm nhẹ = mở/đóng, icon biến hình hamburger <-> X)
---------------------------------------------------------------------
local openBtn = new("TextButton", {
	Name = "OpenButton",
	Position = UDim2.new(0, 12, 0.5, -19),
	Size = UDim2.fromOffset(38, 38),
	BackgroundColor3 = THEME.Bg,
	BorderSizePixel = 0,
	Text = "",
	AutoButtonColor = false,
	Parent = gui,
}, {
	new("UICorner", { CornerRadius = UDim.new(1, 0) }),
	new("UIScale", { Name = "Hover" }),
})
addRainbowStroke(openBtn, 2)
local openHover = openBtn:FindFirstChild("Hover")

local lines = {}
for i = 0, 2 do
	lines[i + 1] = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(19, 12 + i * 7),
		Size = UDim2.fromOffset(18, 3),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = openBtn,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
end

local function morphIcon(open)
	local style = Enum.EasingStyle.Back
	if open then
		tween(lines[1], 0.4, { Position = UDim2.fromOffset(19, 19), Rotation = 45 }, style)
		tween(lines[2], 0.25, { Size = UDim2.fromOffset(0, 3), BackgroundTransparency = 1 })
		tween(lines[3], 0.4, { Position = UDim2.fromOffset(19, 19), Rotation = -45 }, style)
	else
		tween(lines[1], 0.4, { Position = UDim2.fromOffset(19, 12), Rotation = 0 }, style)
		tween(lines[2], 0.3, { Size = UDim2.fromOffset(18, 3), BackgroundTransparency = 0 }, style)
		tween(lines[3], 0.4, { Position = UDim2.fromOffset(19, 26), Rotation = 0 }, style)
	end
end

---------------------------------------------------------------------
-- OPEN / CLOSE ANIMATION
---------------------------------------------------------------------
local function setMenu(open)
	if isOpen == open then return end
	isOpen = open
	morphIcon(open)

	if open then
		main.Visible = true
		main.Size = UDim2.fromOffset(WIN_W * 0.8, WIN_H * 0.8)
		main.Rotation = -4
		tween(main, 0.6, { Size = FULL_SIZE, Rotation = 0 }, Enum.EasingStyle.Back)
		tween(main, 0.3, { GroupTransparency = 0 })
		if Config.MenuBlur then tween(blur, 0.5, { Size = BLUR_SIZE }) end

		titleLine.Size = UDim2.new(0, 0, 0, 2)
		tween(titleLine, 0.8, { Size = UDim2.new(1, 0, 0, 2) })
		animateCells(pages[currentTab])
	else
		tween(blur, 0.3, { Size = 0 })
		tween(main, 0.3, {
			Size = UDim2.fromOffset(WIN_W * 0.85, WIN_H * 0.85),
			Rotation = 3,
		}, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		local t = tween(main, 0.3, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		t.Completed:Connect(function()
			if not isOpen then main.Visible = false end
		end)
	end
end

closeBtn.Activated:Connect(function() setMenu(false) end)

do
	local dragging, moved = false, false
	local dragStart, startPos

	openBtn.MouseEnter:Connect(function()
		tween(openHover, 0.3, { Scale = 1.12 }, Enum.EasingStyle.Back)
	end)
	openBtn.MouseLeave:Connect(function()
		tween(openHover, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end)

	openBtn.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging = true
			moved = false
			dragStart = input.Position
			startPos = openBtn.Position
			tween(openHover, 0.1, { Scale = 0.9 })
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					tween(openHover, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
					if not moved then setMenu(not isOpen) end
				end
			end)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			if delta.Magnitude > 6 then moved = true end
			if moved then
				tween(openBtn, 0.08, {
					Position = UDim2.new(
						startPos.X.Scale, startPos.X.Offset + delta.X,
						startPos.Y.Scale, startPos.Y.Offset + delta.Y
					),
				}, Enum.EasingStyle.Quad)
			end
		end
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.RightShift then
		setMenu(not isOpen)
	end
end)

---------------------------------------------------------------------
-- RAINBOW LOOP + FPS
---------------------------------------------------------------------
do
	local hue, rot = 0, 0
	local fpsTime, fpsFrames = 0, 0

	RunService.RenderStepped:Connect(function(dt)
		hue = (hue + dt * 0.25) % 1
		rot = (rot + dt * 120) % 360
		rainbowColor = Color3.fromHSV(hue, 0.75, 1)
		accent = Config.Rainbow and rainbowColor or THEME.On

		for _, g in ipairs(rainbowGradients) do
			g.grad.Enabled = Config.Rainbow
			g.grad.Rotation = rot
			if g.stroke then
				g.stroke.Color = Config.Rainbow and Color3.new(1, 1, 1) or THEME.Stroke
			end
		end
		for _, fn in ipairs(accentUpdaters) do
			fn(accent)
		end

		fpsTime += dt
		fpsFrames += 1
		if fpsTime >= 0.5 then
			footerLbl.Text = string.format("RightShift: mo/dong menu   |   %d FPS", math.floor(fpsFrames / fpsTime + 0.5))
			fpsTime, fpsFrames = 0, 0
		end
	end)

	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
end

selectTab("Combat")
setMenu(true)
