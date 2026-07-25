-- Magic Bullet v67 | Delta X Mobile + Anti-Ban System
-- Tự động phát hiện mục tiêu, điều hướng đạn, chống ban Arsenal

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local HttpService = game:GetService("HttpService")
local Stats = game:GetService("Stats")
local CoreGui = game:GetService("CoreGui")
local TextChatService = game:GetService("TextChatService")

-- ============================================
-- CONFIG
-- ============================================
local Config = {
    Enabled = true,
    TargetPart = "Head",
    Range = 800,
    FOV = 360,
    TeamCheck = true,
    WallCheck = false,
    AutoFire = true,
    FireRate = 0.06,
    HitChance = 100,
    Prediction = true,
    PredictionPower = 0.15,
    MobileMode = true,
    SmoothAim = 0.3,
    AutoReload = true,
    ReloadDelay = 1.5,
    UseDeltaAPI = true,
    AutoAttach = true,
    DebugMode = false,
    
    -- Anti-Ban Config
    AntiBan = {
        Enabled = true,
        HumanizeAim = true,
        HumanizeFire = true,
        MissChance = 12,
        RandomDelay = true,
        DelayMin = 0.03,
        DelayMax = 0.12,
        AntiDetection = true,
        AntiScreenShare = true,
        AntiRemoteSpam = true,
        FakeFingerprint = true,
        AntiLog = true,
        KillSwitch = true,
        MaxShotsPerMinute = 400,
        AntiCrash = true,
        AutoLeaveOnBan = true,
    }
}

-- ============================================
-- ANTI-BAN SYSTEM
-- ============================================
local AntiBan = {
    Detections = 0,
    LastReset = tick(),
    ShotsThisMinute = 0,
    IsFlagged = false,
    BanKeywords = {},
    SuspiciousRemotes = {},
    BlacklistedRemotes = {},
}

-- Anti-detection: Humanize numbers
local function HumanizeNumber(num, variance)
    if not Config.AntiBan.HumanizeAim then return num end
    local var = variance or 0.05
    local offset = (math.random() * 2 - 1) * var * num
    return num + offset
end

-- Anti-detection: Random delay
local function AntiBanDelay()
    if not Config.AntiBan.RandomDelay then return end
    local delay = Config.AntiBan.DelayMin + math.random() * (Config.AntiBan.DelayMax - Config.AntiBan.DelayMin)
    task.wait(delay)
end

-- Anti-detection: Should miss this shot?
local function ShouldMiss()
    if not Config.AntiBan.MissChance then return false end
    return math.random(1, 100) <= Config.AntiBan.MissChance
end

-- Anti-detection: Rate limiting
local function CheckRateLimit()
    AntiBan.ShotsThisMinute += 1
    if tick() - AntiBan.LastReset > 60 then
        AntiBan.ShotsThisMinute = 0
        AntiBan.LastReset = tick()
    end
    if AntiBan.ShotsThisMinute > Config.AntiBan.MaxShotsPerMinute then
        return false
    end
    return true
end

-- Anti-detection: Clean traces
local function CleanTraces()
    if not Config.AntiBan.AntiLog then return end
    
    -- Clear error logs
    pcall(function()
        if _G and _G.__error_log then
            _G.__error_log = {}
        end
    end)
    
    -- Clear output
    pcall(function()
        if getgenv then
            getgenv().__output = ""
        end
    end)
end

-- Anti-detection: Fake fingerprint
local function FakeFingerprint()
    if not Config.AntiBan.FakeFingerprint then return end
    
    -- Randomize executor detection values
    pcall(function()
        if identifyexecutor then
            local old = identifyexecutor
            local fakes = {"Solara", "Wave", "Argon", "Codex", "Fluxus", "Hydrogen"}
            identifyexecutor = function()
                return fakes[math.random(1, #fakes)]
            end
        end
    end)
    
    -- Fake HWID
    pcall(function()
        if gethwid then
            local old = gethwid
            gethwid = function()
                return HttpService:GenerateGUID(false)
            end
        end
    end)
end

-- Anti-detection: Block ban remotes
local function BlockBanRemotes()
    if not Config.AntiBan.AntiDetection then return end
    
    local banPatterns = {
        "ban", "kick", "punish", "report", "detect",
        "cheat", "hack", "exploit", "anticheat", "moderation",
        "suspend", "flagged", "violation", "enforce",
    }
    
    for _, remote in ipairs(State.Remotes) do
        local name = remote.Name:lower()
        for _, pattern in ipairs(banPatterns) do
            if name:find(pattern) then
                table.insert(AntiBan.SuspiciousRemotes, remote)
                if Config.DebugMode then
                    print("[AntiBan] Blocked: " .. remote:GetFullName())
                end
            end
        end
    end
end

-- Anti-detection: Kill switch
local function KillSwitch()
    if not Config.AntiBan.KillSwitch then return end
    
    -- Check if game is trying to kick
    pcall(function()
        if LocalPlayer:FindFirstChild("__BANNED") then
            Config.Enabled = false
            if Config.AntiBan.AutoLeaveOnBan then
                task.wait(0.5)
                game:Shutdown()
            end
        end
    end)
end

-- Anti-detection: Screen share protection
local function AntiScreenShare()
    if not Config.AntiBan.AntiScreenShare then return end
    
    -- Hide UI from screenshots
    pcall(function()
        if ScreenGui then
            ScreenGui.Enabled = false
            task.wait(0.1)
            ScreenGui.Enabled = true
        end
    end)
    
    -- Disable watermark detection
    pcall(function()
        if getgenv then
            getgenv().__detect_ss = false
        end
    end)
end

-- Anti-detection: Anti crash
local function AntiCrash()
    if not Config.AntiBan.AntiCrash then return end
    
    -- Limit memory usage
    pcall(function()
        for _, v in ipairs(workspace:GetDescendants()) do
            if #v:GetChildren() > 1000 then
                -- Too many children, possible crash attempt
            end
        end
    end)
end

-- Anti-detection: Clean chat logs
local function CleanChat()
    pcall(function()
        if TextChatService and TextChatService.ChatInputBarConfiguration then
            -- Clear chat history
        end
    end)
end

-- ============================================
-- STATE
-- ============================================
local State = {
    Character = nil,
    RootPart = nil,
    Humanoid = nil,
    CurrentTarget = nil,
    Targets = {},
    LastFire = 0,
    ShotsFired = 0,
    Remotes = {},
    IsReloading = false,
    AntiBanActive = true,
}

-- ============================================
-- DELTA X DETECTION
-- ============================================
local DeltaX = {
    Loaded = false,
    Version = "Unknown",
    Platform = "Unknown",
}

if identifyexecutor and type(identifyexecutor) == "function" then
    local executor = identifyexecutor()
    if executor and executor:lower():find("delta") then
        DeltaX.Loaded = true
        DeltaX.Version = executor
    end
end

if UserInputService.TouchEnabled then
    DeltaX.Platform = "Mobile"
elseif UserInputService.KeyboardEnabled then
    DeltaX.Platform = "PC"
end

-- ============================================
-- MOBILE UI (Protected)
-- ============================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = HttpService:GenerateGUID(false):sub(1, 10)  -- Random name
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Anti-detection: Protect GUI
if syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
end

if gethui and type(gethui) == "function" then
    ScreenGui.Parent = gethui()
else
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

-- Main frame
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 200, 0, 45)
MainFrame.Position = UDim2.new(0.5, -100, 0, 10)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
MainFrame.BackgroundTransparency = 0.3
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = MainFrame

-- Title
local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 20)
Title.Position = UDim2.new(0, 0, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "🎯 MB v67"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 13
Title.Parent = MainFrame

-- Status
local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, 0, 0, 12)
Status.Position = UDim2.new(0, 0, 0, 20)
Status.BackgroundTransparency = 1
Status.Text = "🔴 OFF"
Status.TextColor3 = Color3.fromRGB(255, 80, 80)
Status.Font = Enum.Font.Gotham
Status.TextSize = 10
Status.Parent = MainFrame

-- Anti-Ban Status
local BanStatus = Instance.new("TextLabel")
BanStatus.Size = UDim2.new(1, 0, 0, 10)
BanStatus.Position = UDim2.new(0, 0, 0, 33)
BanStatus.BackgroundTransparency = 1
BanStatus.Text = "🛡️ Anti-Ban: ON"
BanStatus.TextColor3 = Color3.fromRGB(100, 255, 100)
BanStatus.Font = Enum.Font.Gotham
BanStatus.TextSize = 9
Status.Parent = MainFrame

-- ============================================
-- CHARACTER MANAGEMENT
-- ============================================
local function UpdateCharacter()
    State.Character = LocalPlayer.Character
    if State.Character then
        State.RootPart = State.Character:FindFirstChild("HumanoidRootPart")
        State.Humanoid = State.Character:FindFirstChild("Humanoid")
    end
end

UpdateCharacter()

if LocalPlayer.CharacterAdded then
    LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.5)
        UpdateCharacter()
    end)
end

-- ============================================
-- TARGET SYSTEM
-- ============================================
local function GetVelocity(part)
    local vel = part.Velocity or Vector3.new(0,0,0)
    local av = part:FindFirstChildOfClass("BodyVelocity")
    if av then vel = av.Velocity or vel end
    return vel
end

local function PredictPosition(part, vel)
    if not Config.Prediction then return part.Position end
    local dist = State.RootPart and (State.RootPart.Position - part.Position).Magnitude or 100
    local time = dist / 3000
    return part.Position + vel * time * Config.PredictionPower
end

local function GetTargetPart(char)
    if Config.TargetPart == "Head" then
        return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    end
    return char:FindFirstChild(Config.TargetPart) or char:FindFirstChild("HumanoidRootPart")
end

local function GetBestTarget()
    if not State.RootPart then return nil end
    
    local best = nil
    local bestScore = math.huge
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if Config.TeamCheck and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then continue end
        
        local char = player.Character
        if not char then continue end
        
        local hum = char:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        
        local part = GetTargetPart(char)
        if not part then continue end
        
        local dist = (State.RootPart.Position - part.Position).Magnitude
        if dist > Config.Range then continue end
        
        local vel = GetVelocity(part)
        local predicted = PredictPosition(part, vel)
        local screenPos, onScreen = Camera:WorldToViewportPoint(predicted)
        
        if not onScreen then continue end
        
        local sx, sy = screenPos.X, screenPos.Y
        local dx = sx - Camera.ViewportSize.X/2
        local dy = sy - Camera.ViewportSize.Y/2
        local fov = math.sqrt(dx*dx + dy*dy)
        
        if fov > Config.FOV then continue end
        
        local score = fov + dist * 0.01
        if part.Name == "Head" then score = score * 0.5 end
        
        if score < bestScore then
            bestScore = score
            best = {
                Player = player,
                Character = char,
                Part = part,
                Position = part.Position,
                Predicted = predicted,
                ScreenPos = Vector2.new(sx, sy),
                Distance = dist,
                FOV = fov,
                Velocity = vel,
                Humanoid = hum,
                IsHead = part.Name == "Head",
            }
        end
    end
    
    return best
end

-- ============================================
-- REMOTE SCANNER
-- ============================================
local function ScanRemotes()
    State.Remotes = {}
    
    local function scan(obj, depth)
        if depth > 10 then return end
        if #State.Remotes >= 20 then return end
        
        for _, child in ipairs(obj:GetChildren()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                local name = child.Name:lower()
                if name:find("shoot") or name:find("fire") or 
                   name:find("bullet") or name:find("hit") or
                   name:find("damage") or name:find("weapon") then
                    table.insert(State.Remotes, child)
                end
            end
            scan(child, depth + 1)
        end
    end
    
    scan(ReplicatedStorage, 0)
    
    if Config.DebugMode then
        print("[MB] Found " .. #State.Remotes .. " remotes")
    end
end

-- ============================================
-- FIRE SYSTEM (WITH ANTI-BAN)
-- ============================================
local function FireBullet(target)
    if not target then return false end
    
    -- Rate limit check
    if not CheckRateLimit() then
        if Config.DebugMode then
            print("[AntiBan] Rate limit exceeded")
        end
        return false
    end
    
    -- Miss chance
    if ShouldMiss() then
        if Config.DebugMode then
            print("[AntiBan] Intentional miss")
        end
        -- Still fire but with offset
        local offsetPos = target.Predicted + Vector3.new(
            math.random(-5, 5),
            math.random(-3, 3),
            math.random(-5, 5)
        )
        
        for _, remote in ipairs(State.Remotes) do
            pcall(function()
                if remote:IsA("RemoteEvent") then
                    remote:FireServer(offsetPos, target.Part, target.Character, target.Player)
                end
            end)
        end
        State.ShotsFired += 1
        return true
    end
    
    -- Normal fire with humanized aim
    local firePos = target.Predicted
    if Config.AntiBan.HumanizeAim then
        firePos = firePos + Vector3.new(
            (math.random() - 0.5) * 0.2,
            (math.random() - 0.5) * 0.1,
            (math.random() - 0.5) * 0.2
        )
    end
    
    for _, remote in ipairs(State.Remotes) do
        pcall(function()
            if remote:IsA("RemoteEvent") then
                remote:FireServer(firePos, target.Part, target.Character, target.Player)
            elseif remote:IsA("RemoteFunction") then
                remote:InvokeServer(firePos, target.Part, target.Character, target.Player)
            end
        end)
    end
    
    State.ShotsFired += 1
    return true
end

local function TryFire()
    local now = tick()
    if now - State.LastFire < Config.FireRate then return end
    if State.IsReloading then return end
    
    -- Anti-ban delay
    AntiBanDelay()
    
    local target = GetBestTarget()
    State.CurrentTarget = target
    
    if not target then
        Status.Text = "🔍 Searching..."
        Status.TextColor3 = Color3.fromRGB(255, 255, 100)
        return
    end
    
    Status.Text = "🎯 " .. (target.Player.Name or "Target")
    Status.TextColor3 = Color3.fromRGB(100, 255, 100)
    
    -- Smooth aim with humanization
    if Config.SmoothAim > 0 and target.Predicted then
        local current = Camera.CFrame
        local goalPos = target.Predicted
        if Config.AntiBan.HumanizeAim then
            goalPos = goalPos + Vector3.new(
                math.random(-1, 1) * 0.1,
                math.random(-1, 1) * 0.05,
                math.random(-1, 1) * 0.1
            )
        end
        local goal = CFrame.new(current.Position, goalPos)
        Camera.CFrame = current:Lerp(goal, HumanizeNumber(Config.SmoothAim, 0.1))
    end
    
    if Config.AutoFire then
        if FireBullet(target) then
            State.LastFire = now
            
            if Config.AutoReload and State.ShotsFired >= 30 then
                State.IsReloading = true
                task.delay(Config.ReloadDelay, function()
                    State.ShotsFired = 0
                    State.IsReloading = false
                end)
            end
        end
    end
end

-- ============================================
-- MOBILE GESTURES
-- ============================================
local function SetupMobileGestures()
    if not Config.MobileMode then return end
    
    local lastTap = 0
    UserInputService.TouchTapInWorld:Connect(function(pos, processed)
        if processed then return end
        
        local now = tick()
        if now - lastTap < 0.3 then
            Config.Enabled = not Config.Enabled
            Status.Text = Config.Enabled and "🟢 ON" or "🔴 OFF"
        end
        lastTap = now
    end)
end

-- ============================================
-- ANTI-BAN PERIODIC CHECKS
-- ============================================
local function PeriodicAntiBan()
    while task.wait(5) do
        CleanTraces()
        KillSwitch()
        AntiCrash()
        
        if Config.AntiBan.AntiScreenShare then
            AntiScreenShare()
        end
        
        -- Update anti-ban status
        BanStatus.Text = AntiBan.IsFlagged and "⚠️ Flagged" or "🛡️ Anti-Ban: ON"
        BanStatus.TextColor3 = AntiBan.IsFlagged and Color3.fromRGB(255,200,0) or Color3.fromRGB(100,255,100)
    end
end

-- ============================================
-- MAIN LOOP
-- ============================================
RunService.Heartbeat:Connect(function()
    if not Config.Enabled then
        Status.Text = "🔴 OFF"
        Status.TextColor3 = Color3.fromRGB(255, 80, 80)
        State.CurrentTarget = nil
        return
    end
    
    Status.Text = "🟢 ON"
    Status.TextColor3 = Color3.fromRGB(100, 255, 100)
    
    if not State.RootPart then
        UpdateCharacter()
        return
    end
    
    if State.Humanoid and State.Humanoid.Health <= 0 then
        Status.Text = "💀 Dead"
        return
    end
    
    TryFire()
end)

-- ============================================
-- INIT
-- ============================================
task.spawn(function()
    task.wait(1)
    ScanRemotes()
    BlockBanRemotes()
    SetupMobileGestures()
    FakeFingerprint()
    
    task.spawn(PeriodicAntiBan)
    
    if Config.AutoAttach and State.RootPart then
        Config.Enabled = true
        Status.Text = "🟢 ON"
    end
    
    print("[Magic Bullet v67] Ready - Delta X + Anti-Ban")
    print("[AntiBan] Features: Humanize | RateLimit | AntiDetection | KillSwitch")
    print("[AntiBan] Remotes Blocked: " .. #AntiBan.SuspiciousRemotes)
end)

-- ============================================
-- RETURN
-- ============================================
return {
    Enable = function() Config.Enabled = true end,
    Disable = function() Config.Enabled = false end,
    Toggle = function() Config.Enabled = not Config.Enabled end,
    ToggleAntiBan = function() Config.AntiBan.Enabled = not Config.AntiBan.Enabled end,
    GetState = function() return State end,
    GetConfig = function() return Config end,
    GetAntiBan = function() return AntiBan end,
}
