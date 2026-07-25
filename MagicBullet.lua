-- Magic Bullet v67 | Mobile Delta X Optimized
-- Tương thích hoàn toàn với Delta X Executor trên Android/iOS
-- Tự động phát hiện mục tiêu, điều hướng đạn, không cần aim

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local HttpService = game:GetService("HttpService")

-- ============================================
-- DELTA X MOBILE CONFIG
-- ============================================
local Config = {
    -- Master
    Enabled = true,
    
    -- Target
    TargetPart = "Head",
    Range = 800,
    FOV = 360,
    TeamCheck = true,
    WallCheck = false,
    
    -- Combat
    AutoFire = true,
    FireRate = 0.06,
    HitChance = 100,
    
    -- Prediction
    Prediction = true,
    PredictionPower = 0.15,
    
    -- Mobile
    MobileMode = true,
    SmoothAim = 0.3,
    AutoReload = true,
    ReloadDelay = 1.5,
    
    -- Delta X Specific
    UseDeltaAPI = true,
    AutoAttach = true,
    DebugMode = false,
}

-- ============================================
-- DELTA X COMPATIBILITY
-- ============================================
local DeltaX = {
    Loaded = false,
    Version = "Unknown",
    Platform = "Unknown",
}

-- Detect Delta X
if identifyexecutor and type(identifyexecutor) == "function" then
    local executor = identifyexecutor()
    if executor and executor:lower():find("delta") then
        DeltaX.Loaded = true
        DeltaX.Version = executor
    end
end

if DeltaX.Loaded then
    print("[Magic Bullet] Delta X Detected")
else
    print("[Magic Bullet] Running on unknown executor")
end

-- Detect platform
if UserInputService.TouchEnabled then
    DeltaX.Platform = "Mobile"
    print("[Magic Bullet] Mobile Mode Active")
elseif UserInputService.KeyboardEnabled then
    DeltaX.Platform = "PC"
    print("[Magic Bullet] PC Mode Active")
end

-- ============================================
-- MOBILE UI (Delta X Compatible)
-- ============================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MagicBulletUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

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
MainFrame.Size = UDim2.new(0, 180, 0, 35)
MainFrame.Position = UDim2.new(0.5, -90, 0, 10)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
MainFrame.BackgroundTransparency = 0.3
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = MainFrame

-- Title
local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.Size = UDim2.new(1, 0, 0, 25)
Title.Position = UDim2.new(0, 0, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "🎯 Magic Bullet v67"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.Parent = MainFrame

-- Status
local Status = Instance.new("TextLabel")
Status.Name = "Status"
Status.Size = UDim2.new(1, 0, 0, 10)
Status.Position = UDim2.new(0, 0, 0, 25)
Status.BackgroundTransparency = 1
Status.Text = "🔴 OFF"
Status.TextColor3 = Color3.fromRGB(255, 80, 80)
Status.Font = Enum.Font.Gotham
Status.TextSize = 10
Status.Parent = MainFrame

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
}

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
                    if Config.DebugMode then
                        print("[MB] Found: " .. child:GetFullName())
                    end
                end
            end
            scan(child, depth + 1)
        end
    end
    
    scan(ReplicatedStorage, 0)
    
    if Config.DebugMode then
        print("[Magic Bullet] Found " .. #State.Remotes .. " remotes")
    end
end

-- ============================================
-- FIRE SYSTEM
-- ============================================
local function FireBullet(target)
    if not target then return false end
    
    -- Method 1: Remote Fire
    for _, remote in ipairs(State.Remotes) do
        local success = pcall(function()
            if remote:IsA("RemoteEvent") then
                remote:FireServer(
                    target.Predicted,
                    target.Part,
                    target.Character,
                    target.Player
                )
            elseif remote:IsA("RemoteFunction") then
                remote:InvokeServer(
                    target.Predicted,
                    target.Part,
                    target.Character,
                    target.Player
                )
            end
        end)
        
        if success then
            State.ShotsFired += 1
            return true
        end
    end
    
    -- Method 2: Tap simulation (mobile)
    if Config.MobileMode and target.ScreenPos then
        VirtualUser:Button1Down(target.ScreenPos, Camera.CFrame)
        task.wait(0.02)
        VirtualUser:Button1Up(target.ScreenPos, Camera.CFrame)
        State.ShotsFired += 1
        return true
    end
    
    return false
end

local function TryFire()
    local now = tick()
    if now - State.LastFire < Config.FireRate then return end
    if State.IsReloading then return end
    
    local target = GetBestTarget()
    State.CurrentTarget = target
    
    if not target then
        Status.Text = "🔍 Searching..."
        Status.TextColor3 = Color3.fromRGB(255, 255, 100)
        return
    end
    
    Status.Text = "🎯 Target: " .. (target.Player.Name or "Unknown")
    Status.TextColor3 = Color3.fromRGB(100, 255, 100)
    
    -- Smooth aim camera
    if Config.SmoothAim > 0 and target.Predicted then
        local current = Camera.CFrame
        local goal = CFrame.new(current.Position, target.Predicted)
        Camera.CFrame = current:Lerp(goal, Config.SmoothAim)
    end
    
    -- Fire
    if Config.AutoFire then
        if FireBullet(target) then
            State.LastFire = now
            
            -- Auto reload check
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
-- MOBILE GESTURES (Delta X)
-- ============================================
local function SetupMobileGestures()
    if not Config.MobileMode then return end
    
    -- Double tap to toggle
    local lastTap = 0
    UserInputService.TouchTapInWorld:Connect(function(pos, processed)
        if processed then return end
        
        local now = tick()
        if now - lastTap < 0.3 then
            Config.Enabled = not Config.Enabled
            Status.Text = Config.Enabled and "🟢 ON" or "🔴 OFF"
            Status.TextColor3 = Config.Enabled and Color3.fromRGB(100,255,100) or Color3.fromRGB(255,80,80)
        end
        lastTap = now
    end)
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
-- AUTO INIT
-- ============================================
task.spawn(function()
    task.wait(1)
    ScanRemotes()
    SetupMobileGestures()
    
    if Config.AutoAttach and State.RootPart then
        Config.Enabled = true
        Status.Text = "🟢 ON"
        Status.TextColor3 = Color3.fromRGB(100, 255, 100)
    end
    
    print("[Magic Bullet v67] Ready - Delta X Mobile")
    print("[Magic Bullet] Auto Fire: " .. tostring(Config.AutoFire))
    print("[Magic Bullet] Target: " .. Config.TargetPart)
    print("[Magic Bullet] Remotes: " .. #State.Remotes)
end)

-- ============================================
-- RETURN (for loadstring)
-- ============================================
return {
    Enable = function() Config.Enabled = true end,
    Disable = function() Config.Enabled = false end,
    Toggle = function() Config.Enabled = not Config.Enabled end,
    SetTarget = function(part) Config.TargetPart = part end,
    SetRange = function(range) Config.Range = range end,
    GetState = function() return State end,
    GetConfig = function() return Config end,
}
