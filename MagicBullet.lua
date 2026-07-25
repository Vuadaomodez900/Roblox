-- Onyx v67 | Magic Bullet — Arsenal Roblox
-- Mobile + PC | Delta X compatible | Anti-Ban integrated

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local LocalPlayer       = Players.LocalPlayer
local Camera            = workspace.CurrentCamera

-- ============================================
-- CONFIG
-- ============================================
local Cfg = {
    Enabled         = true,
    TargetPart      = "Head",         -- Head / HumanoidRootPart
    FOV             = 360,            -- degrees, 360 = all screen
    Range           = 1500,           -- studs
    TeamCheck       = true,
    SilentAim       = true,           -- no camera movement
    SmoothAim       = false,          -- camera lerp (visible, off for silent)
    SmoothSpeed     = 0.25,
    Prediction      = true,
    PredictionMult  = 0.18,
    AutoFire        = true,
    FireRate        = 0.065,
    AutoReload      = true,
    MagazineSize    = 30,
    ReloadTime      = 1.8,
    MobileMode      = UserInputService.TouchEnabled,

    AntiBan = {
        MissChance      = 8,          -- % chance to intentionally miss
        HumanizeAim     = true,       -- add micro jitter
        RateLimit       = 420,        -- max shots/minute
        RandomDelay     = true,
        DelayMin        = 0.02,
        DelayMax        = 0.09,
        HideGUI         = true,       -- random gui name
        ProtectGUI      = true,       -- syn.protect_gui if available
    }
}

-- ============================================
-- STATE
-- ============================================
local State = {
    RootPart      = nil,
    Humanoid      = nil,
    LastFire      = 0,
    ShotsFired    = 0,
    IsReloading   = false,
    ShotsPerMin   = 0,
    RateReset     = tick(),
    ArsenalRemotes= {},
    HookActive    = false,
    CurrentTarget = nil,
}

-- ============================================
-- GUI
-- ============================================
pcall(function()
    local old = game.CoreGui:FindFirstChild("MB_Arsenal")
    if old then old:Destroy() end
end)

local Gui = Instance.new("ScreenGui")
Gui.Name = Cfg.AntiBan.HideGUI
    and HttpService:GenerateGUID(false):gsub("-",""):sub(1,8)
    or "MB_Arsenal"
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    if syn and syn.protect_gui and Cfg.AntiBan.ProtectGUI then
        syn.protect_gui(Gui)
    end
end)

Gui.Parent = (gethui and type(gethui)=="function")
    and gethui()
    or LocalPlayer:WaitForChild("PlayerGui")

local Frame = Instance.new("Frame", Gui)
Frame.Size = UDim2.new(0, 190, 0, 60)
Frame.Position = UDim2.new(0, 12, 0, 12)
Frame.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
Frame.BackgroundTransparency = 0.25
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Draggable = true
Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 8)

local function makeLabel(text, posY, size, color)
    local l = Instance.new("TextLabel", Frame)
    l.Size = UDim2.new(1, -10, 0, size or 14)
    l.Position = UDim2.new(0, 5, 0, posY)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or Color3.fromRGB(220,220,220)
    l.Font = Enum.Font.GothamBold
    l.TextSize = size or 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    return l
end

local LblTitle  = makeLabel("MB v67 | Arsenal", 3,  13, Color3.fromRGB(255,80,80))
local LblStatus = makeLabel("OFF",               20, 11, Color3.fromRGB(160,160,160))
local LblTarget = makeLabel("No target",         34, 10, Color3.fromRGB(120,120,120))
local LblBan    = makeLabel("Anti-Ban: ON",      47, 9,  Color3.fromRGB(100,255,100))

-- ============================================
-- CHARACTER
-- ============================================
local function RefreshChar()
    local char = LocalPlayer.Character
    if not char then return end
    State.RootPart = char:FindFirstChild("HumanoidRootPart")
    State.Humanoid = char:FindFirstChild("Humanoid")
end

RefreshChar()
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.6)
    RefreshChar()
    State.ShotsFired  = 0
    State.IsReloading = false
end)

-- ============================================
-- ARSENAL REMOTE SCANNER
-- ============================================
local ArsenalKeywords = {
    fire   = true,
    shoot  = true,
    bullet = true,
    hit    = true,
    gun    = true,
    weapon = true,
    damage = true,
    impact = true,
}

local function ScanArsenalRemotes()
    State.ArsenalRemotes = {}

    local function recurse(obj, depth)
        if depth > 8 then return end
        for _, child in ipairs(obj:GetChildren()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                local n = child.Name:lower()
                for kw in pairs(ArsenalKeywords) do
                    if n:find(kw) then
                        table.insert(State.ArsenalRemotes, child)
                        break
                    end
                end
            end
            recurse(child, depth + 1)
        end
    end

    -- Arsenal stores remotes here
    recurse(ReplicatedStorage, 0)

    -- also check workspace module scripts (Arsenal specific)
    pcall(function()
        local arsenalFolder = ReplicatedStorage:FindFirstChild("Arsenal")
            or ReplicatedStorage:FindFirstChild("Remotes")
            or ReplicatedStorage:FindFirstChild("Events")
        if arsenalFolder then
            recurse(arsenalFolder, 0)
        end
    end)

    print("[MB] Arsenal remotes: " .. #State.ArsenalRemotes)
end

-- ============================================
-- SILENT AIM HOOK (hookmetamethod)
-- ============================================
local SilentHook = nil

local function GetNearestEnemy()
    if not State.RootPart then return nil end
    local best, bestFOV = nil, math.huge
    local cx = Camera.ViewportSize.X / 2
    local cy = Camera.ViewportSize.Y / 2

    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        if Cfg.TeamCheck and p.Team and LocalPlayer.Team
            and p.Team == LocalPlayer.Team then continue end

        local char = p.Character
        if not char then continue end
        local hum = char:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        local part = char:FindFirstChild(Cfg.TargetPart)
            or char:FindFirstChild("HumanoidRootPart")
        if not part then continue end

        local dist = (State.RootPart.Position - part.Position).Magnitude
        if dist > Cfg.Range then continue end

        -- velocity prediction
        local vel = Vector3.zero
        pcall(function() vel = part.AssemblyLinearVelocity end)

        local predicted = part.Position
        if Cfg.Prediction then
            local t = dist / 3000
            predicted = part.Position + vel * t * Cfg.PredictionMult
        end

        local sp, onScreen = Camera:WorldToViewportPoint(predicted)
        if not onScreen then continue end

        local fov = math.sqrt((sp.X-cx)^2 + (sp.Y-cy)^2)
        if fov > Cfg.FOV then continue end

        if fov < bestFOV then
            bestFOV = fov
            best = {
                Player    = p,
                Part      = part,
                Character = char,
                Humanoid  = hum,
                Position  = predicted,
                Distance  = dist,
            }
        end
    end
    return best
end

local function EnableSilentAim()
    if State.HookActive then return end
    pcall(function()
        if not hookmetamethod then return end

        SilentHook = hookmetamethod(game, "__index", function(self, key)
            if not checkcaller() then
                if key == "Hit" or key == "Origin" then
                    if Cfg.Enabled and Cfg.SilentAim then
                        local target = GetNearestEnemy()
                        if target then
                            -- jitter biar keliatan human
                            local jitter = Vector3.zero
                            if Cfg.AntiBan.HumanizeAim then
                                jitter = Vector3.new(
                                    (math.random()-0.5)*0.15,
                                    (math.random()-0.5)*0.08,
                                    (math.random()-0.5)*0.15
                                )
                            end
                            return CFrame.new(target.Position + jitter)
                        end
                    end
                end
            end
            return SilentHook(self, key)
        end)

        State.HookActive = true
        print("[MB] Silent aim hook active")
    end)
end

-- ============================================
-- ANTI-BAN HELPERS
-- ============================================
local function RateOK()
    State.ShotsPerMin += 1
    if tick() - State.RateReset > 60 then
        State.ShotsPerMin = 0
        State.RateReset   = tick()
    end
    return State.ShotsPerMin <= Cfg.AntiBan.RateLimit
end

local function RandomDelay()
    if not Cfg.AntiBan.RandomDelay then return end
    task.wait(Cfg.AntiBan.DelayMin +
        math.random() * (Cfg.AntiBan.DelayMax - Cfg.AntiBan.DelayMin))
end

local function Miss()
    return math.random(1,100) <= (Cfg.AntiBan.MissChance or 0)
end

-- ============================================
-- FIRE REMOTE (Arsenal specific)
-- ============================================
local function FireRemote(target)
    if #State.ArsenalRemotes == 0 then return end
    if not RateOK() then return end

    local pos = target.Position
    if Miss() then
        pos = pos + Vector3.new(
            math.random(-8,8),
            math.random(-4,4),
            math.random(-8,8)
        )
    end

    for _, remote in ipairs(State.ArsenalRemotes) do
        pcall(function()
            if remote:IsA("RemoteEvent") then
                remote:FireServer(
                    pos,
                    target.Part,
                    target.Character,
                    target.Player,
                    target.Distance
                )
            elseif remote:IsA("RemoteFunction") then
                remote:InvokeServer(
                    pos,
                    target.Part,
                    target.Character,
                    target.Player
                )
            end
        end)
    end

    State.ShotsFired += 1
end

-- ============================================
-- VIRTUAL FIRE (mobile tap sim fallback)
-- ============================================
local function VirtualFire(target)
    if not target then return end
    -- aim camera at target (mobile needs visible aim)
    if not Cfg.SilentAim then
        local current = Camera.CFrame
        local goal = CFrame.new(current.Position, target.Position)
        if Cfg.SmoothAim then
            Camera.CFrame = current:Lerp(goal, Cfg.SmoothSpeed)
        else
            Camera.CFrame = goal
        end
    end

    -- simulate tap at screen center
    local cx = Camera.ViewportSize.X / 2
    local cy = Camera.ViewportSize.Y / 2
    pcall(function()
        local VU = game:GetService("VirtualUser")
        VU:Button1Down(Vector2.new(cx, cy), Camera.CFrame)
        task.wait(0.03)
        VU:Button1Up(Vector2.new(cx, cy), Camera.CFrame)
    end)
end

-- ============================================
-- MAIN FIRE LOOP
-- ============================================
local function TryFire()
    if not Cfg.Enabled then return end
    if not State.RootPart then return end
    if State.IsReloading then return end

    local now = tick()
    if now - State.LastFire < Cfg.FireRate then return end

    RandomDelay()

    local target = GetNearestEnemy()
    State.CurrentTarget = target

    if not target then
        LblStatus.Text      = "Searching..."
        LblStatus.TextColor3= Color3.fromRGB(255,255,80)
        LblTarget.Text      = "No target"
        return
    end

    LblStatus.Text       = "LOCKED"
    LblStatus.TextColor3 = Color3.fromRGB(100,255,100)
    LblTarget.Text       = target.Player.Name ..
        " | " .. math.floor(target.Distance) .. "m"

    if not Cfg.SilentAim then
        -- visible aim
        local camCF = Camera.CFrame
        local aimCF = CFrame.new(camCF.Position, target.Position)
        Camera.CFrame = Cfg.SmoothAim
            and camCF:Lerp(aimCF, Cfg.SmoothSpeed)
            or  aimCF
    end

    if Cfg.AutoFire then
        -- try remote first, fallback to VirtualUser
        if #State.ArsenalRemotes > 0 then
            FireRemote(target)
        else
            VirtualFire(target)
        end

        State.LastFire = now

        -- auto reload
        if Cfg.AutoReload and State.ShotsFired >= Cfg.MagazineSize then
            State.IsReloading = true
            LblStatus.Text      = "Reloading..."
            LblStatus.TextColor3= Color3.fromRGB(255,180,0)
            task.delay(Cfg.ReloadTime, function()
                State.ShotsFired  = 0
                State.IsReloading = false
            end)
        end
    end
end

-- ============================================
-- MOBILE TOGGLE (double tap)
-- ============================================
if Cfg.MobileMode then
    local lastTap = 0
    UserInputService.TouchTapInWorld:Connect(function(_, processed)
        if processed then return end
        local now = tick()
        if now - lastTap < 0.35 then
            Cfg.Enabled = not Cfg.Enabled
            if not Cfg.Enabled then
                LblStatus.Text       = "OFF"
                LblStatus.TextColor3 = Color3.fromRGB(255,80,80)
                LblTarget.Text       = "---"
            end
        end
        lastTap = now
    end)
end

-- PC toggle (F2)
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.F2 then
        Cfg.Enabled = not Cfg.Enabled
        print("[MB] Toggled:", Cfg.Enabled and "ON" or "OFF")
    end
    -- F3 = toggle silent aim
    if input.KeyCode == Enum.KeyCode.F3 then
        Cfg.SilentAim = not Cfg.SilentAim
        print("[MB] SilentAim:", Cfg.SilentAim and "ON" or "OFF")
    end
end)

-- ============================================
-- HEARTBEAT
-- ============================================
RunService.Heartbeat:Connect(function()
    if not Cfg.Enabled then
        LblStatus.Text       = "OFF"
        LblStatus.TextColor3 = Color3.fromRGB(255,80,80)
        State.CurrentTarget  = nil
        return
    end
    if not State.RootPart or
       (State.Humanoid and State.Humanoid.Health <= 0) then
        RefreshChar()
        return
    end
    TryFire()
end)

-- anti-ban periodic
task.spawn(function()
    while task.wait(6) do
        LblBan.Text       = "Anti-Ban: ON | " .. State.ShotsPerMin .. "/min"
        LblBan.TextColor3 = State.ShotsPerMin > Cfg.AntiBan.RateLimit * 0.85
            and Color3.fromRGB(255,200,0)
            or  Color3.fromRGB(100,255,100)
    end
end)

-- ============================================
-- INIT
-- ============================================
task.spawn(function()
    task.wait(1.5)  -- wait for Arsenal to fully load remotes

    ScanArsenalRemotes()
    EnableSilentAim()

    if Cfg.AutoFire then
        LblStatus.Text       = "ON"
        LblStatus.TextColor3 = Color3.fromRGB(100,255,100)
    end

    print("[MB v67] Arsenal Magic Bullet ready")
    print("[MB] Platform:", Cfg.MobileMode and "Mobile" or "PC")
    print("[MB] SilentAim:", Cfg.SilentAim and "ON" or "OFF")
    print("[MB] HookActive:", State.HookActive and "YES" or "NO (hookmetamethod unavailable)")
    print("[MB] Remotes:", #State.ArsenalRemotes)
    print("[MB] F2=Toggle | F3=SilentAim toggle | DoubleTap=Mobile toggle")
end)

-- ============================================
-- API
-- ============================================
return {
    Toggle      = function() Cfg.Enabled = not Cfg.Enabled end,
    Enable      = function() Cfg.Enabled = true end,
    Disable     = function() Cfg.Enabled = false end,
    SetFOV      = function(v) Cfg.FOV = v end,
    SetRange    = function(v) Cfg.Range = v end,
    SetFireRate = function(v) Cfg.FireRate = v end,
    GetState    = function() return State end,
    GetConfig   = function() return Cfg end,
    Rescan      = function() ScanArsenalRemotes() end,
}
