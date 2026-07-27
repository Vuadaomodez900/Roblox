-- Sentinel Arsenal v2.0 | FIXED
-- Fixes: Forward declaration, UICorner orphans, FrameCount logic, stale target

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local Config = {
    SilentAim = {Enabled = true, FOV = 200, TargetPart = "UpperTorso", TeamCheck = true},
    SpinBot = {Enabled = false, Speed = 5, Axis = "Y"},
    AutoShoot = {Enabled = true, FireRate = 0.08, UseRemote = true},
    UI = {Visible = true, Draggable = true},
}

local State = {
    Character = nil, Root = nil, Humanoid = nil,
    Target = nil, LastShot = 0, ShotCount = 0,
    Remote = nil, SpinAngle = 0,
}

-- ============================================
-- UTILS
-- ============================================
local function Debug(msg, level)
    local prefix = {INFO="🔵",WARN="🟡",ERROR="🔴",SUCCESS="🟢",TARGET="🎯"}
    print(string.format("[Sentinel] %s [%s] %s", prefix[level] or "⚪", level or "INFO", msg))
end

local function MakeCorner(parent, radius)
    -- FIX Bug 2 & 3: satu function, langsung parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = parent
    return c
end

-- ============================================
-- CHARACTER
-- ============================================
local function UpdateCharacter()
    State.Character = LocalPlayer.Character
    if State.Character then
        State.Root = State.Character:FindFirstChild("HumanoidRootPart")
        State.Humanoid = State.Character:FindFirstChild("Humanoid")
        return true
    end
    return false
end

UpdateCharacter()
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.3)
    if UpdateCharacter() then Debug("Character spawned", "SUCCESS") end
end)
LocalPlayer.CharacterRemoving:Connect(function()
    State.Root = nil; State.Humanoid = nil; State.Target = nil
end)

-- ============================================
-- REMOTE FINDER
-- ============================================
local function FindRemotes()
    local remotes = {}
    local function scan(parent, depth)
        if depth > 15 or #remotes >= 10 then return end
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                local name = child.Name:lower()
                if name:find("shoot") or name:find("fire") or name:find("bullet")
                   or name:find("cast") or name:find("weapon") or name:find("hit") or name:find("damage") then
                    local priority = name:find("shoot") and 1 or name:find("bullet") and 2 or 3
                    table.insert(remotes, {Remote = child, Priority = priority})
                end
            end
            scan(child, depth + 1)
        end
    end
    scan(ReplicatedStorage, 0)
    table.sort(remotes, function(a, b) return a.Priority < b.Priority end)
    State.Remote = remotes[1] and remotes[1].Remote or nil
    if State.Remote then
        Debug("Remote: " .. State.Remote:GetFullName(), "SUCCESS")
    else
        Debug("No remote, using VirtualUser fallback", "WARN")
    end
end

-- ============================================
-- TARGET ACQUISITION
-- ============================================
local function GetTarget()
    if not State.Root then return nil end
    local bestTarget, bestScore = nil, Config.SilentAim.FOV
    local rootPos = State.Root.Position
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if Config.SilentAim.TeamCheck and player.Team
           and LocalPlayer.Team and player.Team == LocalPlayer.Team then continue end

        local char = player.Character
        if not char then continue end
        local hum = char:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then continue end

        local targetPart = char:FindFirstChild(Config.SilentAim.TargetPart)
                        or char:FindFirstChild("HumanoidRootPart")
        if not targetPart then continue end

        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
        if not onScreen then continue end

        local screenVec = Vector2.new(screenPos.X, screenPos.Y)
        local distFromCenter = (screenVec - screenCenter).Magnitude
        if distFromCenter >= bestScore then continue end

        bestScore = distFromCenter
        bestTarget = {
            Player = player, Character = char, Part = targetPart,
            Position = targetPart.Position, ScreenPos = screenVec,
            Distance3D = (rootPos - targetPart.Position).Magnitude,
            FOVDist = distFromCenter, Humanoid = hum,
            IsHead = targetPart.Name == "Head",
        }
    end

    State.Target = bestTarget
    return bestTarget
end

-- ============================================
-- SILENT AIM
-- ============================================
local function SilentAim(target)
    if not Config.SilentAim.Enabled or not target then return false end
    if not Config.AutoShoot.UseRemote or not State.Remote then return false end

    local success = pcall(function()
        if State.Remote:IsA("RemoteEvent") then
            State.Remote:FireServer(target.Position, target.Part, target.Character, target.Player)
        elseif State.Remote:IsA("RemoteFunction") then
            State.Remote:InvokeServer(target.Position, target.Part, target.Character, target.Player)
        end
    end)

    if success then
        State.ShotCount += 1
        Debug("Fired at " .. target.Player.Name, "TARGET")
    end
    return success
end

-- ============================================
-- AUTO SHOOT
-- ============================================
local function AutoShoot(target)
    if not Config.AutoShoot.Enabled or not target then return false end
    local now = tick()
    if now - State.LastShot < Config.AutoShoot.FireRate then return false end

    if SilentAim(target) then
        State.LastShot = now
        return true
    end

    if target.ScreenPos then
        pcall(function()
            VirtualUser:Button1Down(target.ScreenPos, Camera.CFrame)
            task.wait(0.02)
            VirtualUser:Button1Up(target.ScreenPos, Camera.CFrame)
        end)
        State.LastShot = now
        State.ShotCount += 1
        Debug("Tap shot at " .. target.Player.Name, "TARGET")
        return true
    end
    return false
end

-- ============================================
-- SPINBOT
-- ============================================
local function SpinBot()
    if not Config.SpinBot.Enabled or not State.Root then return end
    State.SpinAngle = (State.SpinAngle + Config.SpinBot.Speed) % 360
    State.Root.CFrame = State.Root.CFrame * CFrame.Angles(0, math.rad(Config.SpinBot.Speed), 0)
end

-- ============================================
-- UI — definisi SEBELUM OnRender (FIX Bug 1)
-- ============================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SentinelArsenal"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(ScreenGui) end
    if gethui then
        ScreenGui.Parent = gethui()
    else
        ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end)

local MainFrame = Instance.new("Frame")
MainFrame.Name = "Main"
MainFrame.Size = UDim2.new(0, 220, 0, 175)
MainFrame.Position = UDim2.new(0.5, -110, 0.3, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
MainFrame.BackgroundTransparency = 0.2
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui
MakeCorner(MainFrame, 8) -- FIX: satu UICorner, langsung parent

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 25)
Title.BackgroundTransparency = 1
Title.Text = "Sentinel Arsenal v2.0"
Title.TextColor3 = Color3.fromRGB(0, 255, 200)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.Parent = MainFrame

local function CreateToggle(name, yPos, default, callback)
    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(1, -20, 0, 25)
    toggle.Position = UDim2.new(0, 10, 0, yPos)
    toggle.BackgroundColor3 = default and Color3.fromRGB(0, 180, 100) or Color3.fromRGB(180, 0, 0)
    toggle.Text = name .. ": " .. (default and "ON" or "OFF")
    toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggle.Font = Enum.Font.Gotham
    toggle.TextSize = 12
    toggle.BorderSizePixel = 0
    toggle.Parent = MainFrame
    MakeCorner(toggle, 5) -- FIX: MakeCorner utility

    local state = default
    toggle.MouseButton1Click:Connect(function()
        state = not state
        toggle.BackgroundColor3 = state and Color3.fromRGB(0, 180, 100) or Color3.fromRGB(180, 0, 0)
        toggle.Text = name .. ": " .. (state and "ON" or "OFF")
        callback(state)
    end)
    return toggle
end

local function CreateSlider(name, yPos, min, max, default, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -20, 0, 35)
    frame.Position = UDim2.new(0, 10, 0, yPos)
    frame.BackgroundTransparency = 1
    frame.Parent = MainFrame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 15)
    label.BackgroundTransparency = 1
    label.Text = name .. ": " .. default
    label.TextColor3 = Color3.fromRGB(200, 200, 200)
    label.Font = Enum.Font.Gotham
    label.TextSize = 11
    label.Parent = frame

    local slider = Instance.new("TextButton")
    slider.Size = UDim2.new(1, 0, 0, 15)
    slider.Position = UDim2.new(0, 0, 0, 18)
    slider.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    slider.Text = ""
    slider.BorderSizePixel = 0
    slider.Parent = frame
    MakeCorner(slider, 4) -- FIX

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
    fill.BorderSizePixel = 0
    fill.Parent = slider
    MakeCorner(fill, 4) -- FIX

    local function update(val)
        local clamped = math.clamp(val, min, max)
        fill.Size = UDim2.new((clamped - min) / (max - min), 0, 1, 0)
        label.Text = name .. ": " .. math.round(clamped)
        callback(clamped)
    end

    local dragging = false
    slider.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        dragging = true
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local mouseX = UserInputService:GetMouseLocation().X
        local percent = math.clamp((mouseX - slider.AbsolutePosition.X) / slider.AbsoluteSize.X, 0, 1)
        update(min + percent * (max - min))
    end)

    return update
end

-- StatusLabel — definisi di sini (SEBELUM UpdateUIStatus & OnRender)
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -20, 0, 20)
StatusLabel.Position = UDim2.new(0, 10, 0, 152)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "🔍 Searching..."
StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 10
StatusLabel.Parent = MainFrame

-- FIX Bug 1: UpdateUIStatus SEBELUM OnRender
local function UpdateUIStatus(target)
    if target then
        StatusLabel.Text = string.format("🎯 %s | %.0fm | %s",
            target.Player.Name, target.Distance3D,
            target.IsHead and "HEAD" or "BODY")
        StatusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    else
        StatusLabel.Text = "🔍 Searching..."
        StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
    end
end

CreateToggle("Silent Aim", 30, Config.SilentAim.Enabled, function(v) Config.SilentAim.Enabled = v end)
CreateToggle("SpinBot",    58, Config.SpinBot.Enabled,   function(v) Config.SpinBot.Enabled = v end)
CreateToggle("Auto Shoot", 86, Config.AutoShoot.Enabled, function(v) Config.AutoShoot.Enabled = v end)
CreateSlider("FOV",   115, 50, 500, Config.SilentAim.FOV,  function(v) Config.SilentAim.FOV = v end)
CreateSlider("Speed", 138, 1,  20,  Config.SpinBot.Speed,  function(v) Config.SpinBot.Speed = v end)

-- ============================================
-- RENDER LOOP (SETELAH semua definisi)
-- ============================================
local FrameCount = 0
local function OnRender(deltaTime)
    FrameCount += 1
    if not UpdateCharacter() then return end
    if State.Humanoid and State.Humanoid.Health <= 0 then return end

    -- FIX Bug 4: SpinBot setiap frame (tanpa % 1 yang useless)
    SpinBot()

    -- Target acquisition setiap 3 frame
    local target
    if FrameCount % 3 == 0 then
        target = GetTarget()
    else
        -- FIX Bug 5: fallback ke State.Target yang sudah divalidasi
        target = State.Target
    end

    if target and Config.AutoShoot.Enabled then
        AutoShoot(target)
    end

    if FrameCount % 10 == 0 then
        UpdateUIStatus(target)
    end
end

-- ============================================
-- INIT
-- ============================================
task.spawn(function()
    task.wait(1)
    FindRemotes()
    Debug("Sentinel Arsenal v2.0 FIXED loaded", "SUCCESS")
    Debug("Silent Aim | SpinBot | Auto Shoot | UI clean", "INFO")
end)

RunService.RenderStepped:Connect(OnRender)

return {
    Config = Config,
    State = State,
    Enable = function()
        Config.SilentAim.Enabled = true
        Config.AutoShoot.Enabled = true
    end,
    Disable = function()
        Config.SilentAim.Enabled = false
        Config.AutoShoot.Enabled = false
        Config.SpinBot.Enabled = false
    end,
    ToggleSpinBot = function()
        Config.SpinBot.Enabled = not Config.SpinBot.Enabled
    end,
    GetTarget = GetTarget,
    FindRemotes = FindRemotes,
}
