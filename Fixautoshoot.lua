-- Magic Bullet v67 | Delta X Mobile + Anti-Ban System
-- Fixed by Onyx v67

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local VirtualUser      = game:GetService("VirtualUser")
local HttpService      = game:GetService("HttpService")
local TextChatService  = game:GetService("TextChatService")
local LocalPlayer      = Players.LocalPlayer
local Camera           = workspace.CurrentCamera

-- ============================================
-- CONFIG
-- ============================================
local Config = {
    Enabled        = true,
    TargetPart     = "Head",
    Range          = 800,
    FOV            = 360,
    TeamCheck      = true,
    WallCheck      = true,
    AutoFire       = true,
    FireRate       = 0.06,
    HitChance      = 100,
    Prediction     = true,
    PredictionPower= 0.15,
    MobileMode     = true,
    SmoothAim      = 0.3,
    AutoReload     = true,
    ReloadDelay    = 1.5,
    UseDeltaAPI    = true,
    AutoAttach     = true,
    DebugMode      = false,

    AntiBan = {
        Enabled           = true,
        HumanizeAim       = true,
        HumanizeFire      = true,
        MissChance        = 12,
        RandomDelay       = true,
        DelayMin          = 0.03,
        DelayMax          = 0.12,
        AntiDetection     = true,
        AntiScreenShare   = true,
        AntiRemoteSpam    = true,
        FakeFingerprint   = true,
        AntiLog           = true,
        KillSwitch        = true,
        MaxShotsPerMinute = 400,
        AntiCrash         = true,
        AutoLeaveOnBan    = true,
    }
}

-- ============================================
-- STATE (defined FIRST — before any function uses it)
-- ============================================
local State = {
    Character     = nil,
    RootPart      = nil,
    Humanoid      = nil,
    CurrentTarget = nil,
    Targets       = {},
    LastFire      = 0,
    ShotsFired    = 0,
    Remotes       = {},
    IsReloading   = false,
    AntiBanActive = true,
}

local AntiBan = {
    Detections         = 0,
    LastReset          = tick(),
    ShotsThisMinute    = 0,
    IsFlagged          = false,
    BanKeywords        = {},
    SuspiciousRemotes  = {},
    BlacklistedRemotes = {},
}

-- ============================================
-- DELTA X DETECTION
-- ============================================
local DeltaX = {
    Loaded   = true,
    Version  = "Unknown",
    Platform = "Unknown",
}

pcall(function()
    if identifyexecutor and type(identifyexecutor) == "function" then
        local executor = identifyexecutor()
        if executor and executor:lower():find("delta") then
            DeltaX.Loaded  = true
            DeltaX.Version = executor
        end
    end
end)

DeltaX.Platform = UserInputService.TouchEnabled and "Mobile" or "PC"

-- ============================================
-- MOBILE UI
-- ============================================
-- destroy old instance
pcall(function()
    if game.CoreGui:FindFirstChild("MB67") then
        game.CoreGui.MB67:Destroy()
    end
end)

local ScreenGui      = Instance.new("ScreenGui")
ScreenGui.Name       = "MB67"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(ScreenGui) end
end)

if gethui and type(gethui) == "function" then
    ScreenGui.Parent = gethui()
else
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local MainFrame                      = Instance.new("Frame", ScreenGui)
MainFrame.Name                       = "MainFrame"
MainFrame.Size                       = UDim2.new(0, 200, 0, 50)
MainFrame.Position                   = UDim2.new(0.5, -100, 0, 10)
MainFrame.BackgroundColor3           = Color3.fromRGB(20, 20, 30)
MainFrame.BackgroundTransparency     = 0.3
MainFrame.BorderSizePixel            = 0
MainFrame.Active                     = true
MainFrame.Draggable                  = true

local UICorner              = Instance.new("UICorner", MainFrame)
UICorner.CornerRadius       = UDim.new(0, 8)

local Title                 = Instance.new("TextLabel", MainFrame)
Title.Size                  = UDim2.new(1, 0, 0, 20)
Title.Position              = UDim2.new(0, 0, 0, 0)
Title.BackgroundTransparency= 1
Title.Text                  = "MB v67"
Title.TextColor3            = Color3.fromRGB(255, 255, 255)
Title.Font                  = Enum.Font.GothamBold
Title.TextSize              = 13

local Status                = Instance.new("TextLabel", MainFrame)
Status.Size                 = UDim2.new(1, 0, 0, 14)
Status.Position             = UDim2.new(0, 0, 0, 20)
Status.BackgroundTransparency = 1
Status.Text                 = "OFF"
Status.TextColor3           = Color3.fromRGB(255, 80, 80)
Status.Font                 = Enum.Font.Gotham
Status.TextSize             = 11

-- FIX #2: BanStatus parent was wrongly set to Status
local BanStatus             = Instance.new("TextLabel", MainFrame)
BanStatus.Size              = UDim2.new(1, 0, 0, 12)
BanStatus.Position          = UDim2.new(0, 0, 0, 36)
BanStatus.BackgroundTransparency = 1
BanStatus.Text              = "Anti-Ban: ON"
BanStatus.TextColor3        = Color3.fromRGB(100, 255, 100)
BanStatus.Font              = Enum.Font.Gotham
BanStatus.TextSize          = 9

-- ============================================
-- ANTI-BAN FUNCTIONS (after State is defined)
-- ============================================

-- FIX #8: HumanizeNumber defined before TryFire uses it
local function HumanizeNumber(num, variance)
    if not Config.AntiBan.HumanizeAim then return num end
    local var = variance or 0.05
    return num + (math.random() * 2 - 1) * var * num
end

local function AntiBanDelay()
    if not Config.AntiBan.RandomDelay then return end
    local d = Config.AntiBan.DelayMin +
              math.random() * (Config.AntiBan.DelayMax - Config.AntiBan.DelayMin)
    task.wait(d)
end

local function ShouldMiss()
    if not Config.AntiBan.MissChance then return false end
    return math.random(1, 100) <= Config.AntiBan.MissChance
end

local function CheckRateLimit()
    AntiBan.ShotsThisMinute += 1
    if tick() - AntiBan.LastReset > 60 then
        AntiBan.ShotsThisMinute = 0
        AntiBan.LastReset = tick()
    end
    return AntiBan.ShotsThisMinute <= Config.AntiBan.MaxShotsPerMinute
end

local function CleanTraces()
    if not Config.AntiBan.AntiLog then return end
    pcall(function()
        if _G and _G.__error_log then _G.__error_log = {} end
    end)
    pcall(function()
        if getgenv then getgenv().__output = "" end
    end)
end

local function FakeFingerprint()
    if not Config.AntiBan.FakeFingerprint then return end
    -- FIX #7: removed unused 'old' capture
    pcall(function()
        if identifyexecutor then
            local fakes = {"Solara","Wave","Argon","Codex","Fluxus","Hydrogen"}
            identifyexecutor = function()
                return fakes[math.random(1, #fakes)]
            end
        end
    end)
    pcall(function()
        if gethwid then
            gethwid = function()
                return HttpService:GenerateGUID(false)
            end
        end
    end)
end

local function KillSwitch()
    if not Config.AntiBan.KillSwitch then return end
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

-- FIX #3: AntiScreenShare now uses the ScreenGui already in scope
local function AntiScreenShare()
    if not Config.AntiBan.AntiScreenShare then return end
    pcall(function()
        ScreenGui.Enabled = false
        task.wait(0.1)
        ScreenGui.Enabled = true
    end)
    pcall(function()
        if getgenv then getgenv().__detect_ss = false end
    end)
end

local function AntiCrash()
    if not Config.AntiBan.AntiCrash then return end
    pcall(function()
        for _, v in ipairs(workspace:GetDescendants()) do
            if #v:GetChildren() > 1000 then
                -- flood detected, optionally break
                break
            end
        end
    end)
end

-- FIX #1: BlockBanRemotes now uses State.Remotes which is defined
local function BlockBanRemotes()
    if not Config.AntiBan.AntiDetection then return end
    local banPatterns = {
        "ban","kick","punish","report","detect",
        "cheat","hack","exploit","anticheat","moderation",
        "suspend","flagged","violation","enforce",
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

-- ============================================
-- CHARACTER MANAGEMENT
-- ============================================
local function UpdateCharacter()
    State.Character = LocalPlayer.Character
    if State.Character then
        State.RootPart  = State.Character:FindFirstChild("HumanoidRootPart")
        State.Humanoid  = State.Character:FindFirstChild("Humanoid")
    end
end

UpdateCharacter()
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    UpdateCharacter()
end)

-- ============================================
-- TARGET SYSTEM
-- ============================================

-- FIX #4: AssemblyLinearVelocity instead of deprecated .Velocity
local function GetVelocity(part)
    local ok, vel = pcall(function()
        return part.AssemblyLinearVelocity
    end)
    return (ok and vel) or Vector3.zero
end

local function PredictPosition(part, vel)
    if not Config.Prediction then return part.Position end
    local dist = State.RootPart and
        (State.RootPart.Position - part.Position).Magnitude or 100
    local t = dist / 3000
    return part.Position + vel * t * Config.PredictionPower
end

local function GetTargetPart(char)
    return char:FindFirstChild(Config.TargetPart)
        or char:FindFirstChild("HumanoidRootPart")
end

local function GetBestTarget()
    if not State.RootPart then return nil end
    local best, bestScore = nil, math.huge
    local cx, cy = Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if Config.TeamCheck and player.Team
            and LocalPlayer.Team
            and player.Team == LocalPlayer.Team then continue end

        local char = player.Character
        if not char then continue end
        local hum = char:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        local part = GetTargetPart(char)
        if not part then continue end

        local dist = (State.RootPart.Position - part.Position).Magnitude
        if dist > Config.Range then continue end

        local vel       = GetVelocity(part)
        local predicted = PredictPosition(part, vel)
        local sp, onScreen = Camera:WorldToViewportPoint(predicted)
        if not onScreen then continue end

        local fov = math.sqrt((sp.X-cx)^2 + (sp.Y-cy)^2)
        if fov > Config.FOV then continue end

        local score = fov + dist * 0.01
        if part.Name == "Head" then score = score * 0.5 end

        if score < bestScore then
            bestScore = score
            best = {
                Player    = player,
                Character = char,
                Part      = part,
                Position  = part.Position,
                Predicted = predicted,
                ScreenPos = Vector2.new(sp.X, sp.Y),
                Distance  = dist,
                FOV       = fov,
                Velocity  = vel,
                Humanoid  = hum,
                IsHead    = part.Name == "Head",
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
        if depth > 10 or #State.Remotes >= 20 then return end
        for _, child in ipairs(obj:GetChildren()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                local n = child.Name:lower()
                if n:find("shoot") or n:find("fire") or n:find("bullet")
                or n:find("hit")   or n:find("damage") or n:find("weapon") then
                    table.insert(State.Remotes, child)
                end
            end
            scan(child, depth + 1)
        end
    end
    scan(ReplicatedStorage, 0)
    if Config.DebugMode then
        print("[MB] Remotes found: " .. #State.Remotes)
    end
end

-- ============================================
-- FIRE SYSTEM
-- ============================================
local function FireBullet(target)
    if not target then return false end
    if not CheckRateLimit() then return false end

    local firePos = target.Predicted

    if ShouldMiss() then
        firePos = firePos + Vector3.new(
            math.random(-5, 5),
            math.random(-3, 3),
            math.random(-5, 5)
        )
    elseif Config.AntiBan.HumanizeAim then
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

    AntiBanDelay()

    local target = GetBestTarget()
    State.CurrentTarget = target

    if not target then
        Status.Text      = "Searching..."
        Status.TextColor3= Color3.fromRGB(255, 255, 100)
        return
    end

    Status.Text       = "-> " .. (target.Player.Name or "Target")
    Status.TextColor3 = Color3.fromRGB(100, 255, 100)

    if Config.SmoothAim > 0 and target.Predicted then
        local current = Camera.CFrame
        local goalPos = target.Predicted
        if Config.AntiBan.HumanizeAim then
            goalPos = goalPos + Vector3.new(
                (math.random()-0.5) * 0.2,
                (math.random()-0.5) * 0.1,
                (math.random()-0.5) * 0.2
            )
        end
        Camera.CFrame = current:Lerp(
            CFrame.new(current.Position, goalPos),
            HumanizeNumber(Config.SmoothAim, 0.1)
        )
    end

    if Config.AutoFire then
        if FireBullet(target) then
            State.LastFire = now
            if Config.AutoReload and State.ShotsFired >= 30 then
                State.IsReloading = true
                task.delay(Config.ReloadDelay, function()
                    State.ShotsFired  = 0
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
    UserInputService.TouchTapInWorld:Connect(function(_, processed)
        if processed then return end
        local now = tick()
        if now - lastTap < 0.3 then
            Config.Enabled    = not Config.Enabled
            Status.Text       = Config.Enabled and "ON" or "OFF"
            Status.TextColor3 = Config.Enabled
                and Color3.fromRGB(100,255,100)
                or  Color3.fromRGB(255,80,80)
        end
        lastTap = now
    end)
end

-- ============================================
-- ANTI-BAN LOOP
-- ============================================
local function PeriodicAntiBan()
    while task.wait(5) do
        CleanTraces()
        KillSwitch()
        AntiCrash()
        if Config.AntiBan.AntiScreenShare then AntiScreenShare() end
        BanStatus.Text       = AntiBan.IsFlagged and "!! Flagged" or "Anti-Ban: ON"
        BanStatus.TextColor3 = AntiBan.IsFlagged
            and Color3.fromRGB(255,200,0)
            or  Color3.fromRGB(100,255,100)
    end
end

-- ============================================
-- MAIN LOOP
-- ============================================
RunService.Heartbeat:Connect(function()
    if not Config.Enabled then
        Status.Text       = "OFF"
        Status.TextColor3 = Color3.fromRGB(255,80,80)
        State.CurrentTarget = nil
        return
    end

    if not State.RootPart then
        UpdateCharacter()
        return
    end

    if State.Humanoid and State.Humanoid.Health <= 0 then
        Status.Text = "Dead"
        return
    end

    TryFire()
end)

-- ============================================
-- INIT
-- FIX #5: BlockBanRemotes called AFTER ScanRemotes completes
-- ============================================
task.spawn(function()
    task.wait(1)
    ScanRemotes()          -- scan first
    BlockBanRemotes()      -- then filter — no race condition
    SetupMobileGestures()
    FakeFingerprint()
    task.spawn
