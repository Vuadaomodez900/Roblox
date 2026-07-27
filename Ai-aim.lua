-- Sentinel Arsenal v2.0 | Silent Aim + Spinbot + Auto Shoot
-- Optimized for Arsenal | RenderStepped | Delta X Compatible
-- Author: SentinelCore | Lines: ~180

-- ============================================
-- SERVICES
-- ============================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Workspace = workspace

-- ============================================
-- CONFIG
-- ============================================
local Config = {
    SilentAim = {Enabled = true, FOV = 200, TargetPart = "UpperTorso", TeamCheck = true},
    SpinBot = {Enabled = false, Speed = 5, Axis = "Y"},
    AutoShoot = {Enabled = true, FireRate = 0.08, UseRemote = true},
    UI = {Visible = true, Draggable = true},
}

-- ============================================
-- STATE
-- ============================================
local State = {
    Character = nil, Root = nil, Humanoid = nil,
    Target = nil, LastShot = 0, ShotCount = 0,
    Remote = nil, IsReloading = false,
    SpinAngle = 0, FOVCircle = nil,
}

-- ============================================
-- ANTI-DEBUG LOGGING
-- ============================================
local function Debug(msg, level)
    level = level or "INFO"
    local prefix = {
        INFO = "🔵", WARN = "🟡", ERROR = "🔴", SUCCESS = "🟢", TARGET = "🎯"
    }
    print(string.format("[Sentinel] %s [%s] %s", prefix[level] or "⚪", level, msg))
end

-- ============================================
-- CHARACTER MANAGEMENT
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
    if UpdateCharacter() then
        Debug("Character spawned", "SUCCESS")
    end
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
                   or name:find("cast") or name:find("reel") or name:find("sell")
                   or name:find("weapon") or name:find("hit") or name:find("damage") then
                    table.insert(remotes, {Remote = child, Priority = name:find("shoot") and 1 or name:find("bullet") and 2 or 3})
                end
            end
            scan(child, depth + 1)
        end
    end
    scan(ReplicatedStorage, 0)
    table.sort(remotes, function(a, b) return a.Priority < b.Priority end)
    
    State.Remote = remotes[1] and remotes[1].Remote or nil
    if State.Remote then
        Debug("Remote found: " .. State.Remote:GetFullName(), "SUCCESS")
    else
        Debug("No remote found, using VirtualUser fallback", "WARN")
    end
    return remotes
end

-- ============================================
-- TARGET ACQUISITION
-- ============================================
local function GetTarget()
    if not State.Root then return nil end
    
    local bestTarget, bestScore = nil, Config.SilentAim.FOV
    local rootPos, screenCenter = State.Root.Position, Vector2.new(
        Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2
    )
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if Config.SilentAim.TeamCheck and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then continue end
        
        local char = player.Character
        if not char then continue end
        
        local hum = char:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        
        local targetPart = char:FindFirstChild(Config.SilentAim.TargetPart) or char:FindFirstChild("HumanoidRootPart")
        if not targetPart then continue end
        
        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
        if not onScreen then continue end
        
        local screenVec = Vector2.new(screenPos.X, screenPos.Y)
        local distFromCenter = (screenVec - screenCenter).Magnitude
        
        if distFromCenter >= bestScore then continue end
        
        local dist3D = (rootPos - targetPart.Position).Magnitude
        bestScore = distFromCenter
        bestTarget = {
            Player = player, Character = char, Part = targetPart,
            Position = targetPart.Position, ScreenPos = screenVec,
            Distance3D = dist3D, FOVDist = distFromCenter,
            Humanoid = hum, IsHead = targetPart.Name == "Head",
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
        Debug("Silent aim fired at " .. target.Player.Name, "TARGET")
    end
    return success
end

-- ============================================
-- AUTO SHOOT
-- ============================================
local function AutoShoot(target)
    if not Config.AutoShoot.Enabled then return false end
    if not target then return false end
    
    local now = tick()
    if now - State.LastShot < Config.AutoShoot.FireRate then return false end
    
    -- Thử silent aim trước
    if SilentAim(target) then
        State.LastShot = now
        return true
    end
    
    -- Fallback: VirtualUser tap
    if target.ScreenPos then
        pcall(function()
            VirtualUser:Button1Down(target.ScreenPos, Camera.CFrame)
            task.wait(0.02)
            VirtualUser:Button1Up(target.ScreenPos, Camera.CFrame)
        end)
        State.LastShot = now
        State.ShotCount += 1
        Debug("Auto shoot (tap) at " .. target.Player.Name, "TARGET")
        return true
    end
    
    return false
end

-- ============================================
-- SPINBOT
-- ============================================
local function SpinBot()
    if not Config.SpinBot.Enabled then return end
    if not State.Root then return end
    
    State.SpinAngle = (State.SpinAngle + Config.SpinBot.Speed) % 360
    State.Root.CFrame = State.Root.CFrame * CFrame.Angles(
        0, math.rad(Config.SpinBot.Speed), 0
    )
end

-- ============================================
-- ANTI-LAG: RENDER PRIORITY
-- ============================================
local FrameCount = 0
local function OnRender(deltaTime)
    FrameCount += 1
    if not UpdateCharacter() then return end
    if State.Humanoid and State.Humanoid.Health <= 0 then return end
    
    -- Spinbot (mỗi frame)
    if FrameCount % 1 == 0 then
        SpinBot()
    end
    
    -- Target acquisition (mỗi 3 frame để tiết kiệm)
    local target = nil
    if FrameCount % 3 == 0 then
        target = GetTarget()
    else
        target = State.Target
    end
    
    -- Auto shoot (theo FireRate)
    if target and Config.AutoShoot.Enabled then
        AutoShoot(target)
    end
    
    -- Cập nhật UI status (mỗi 10 frame)
    if FrameCount % 10 == 0 then
        UpdateUIStatus(target)
    end
end

-- ============================================
-- UI SYSTEM
-- ============================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SentinelArsenal"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(ScreenGui) end
    if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
end)

-- Main Frame
local MainFrame = Instance.new("Frame")
MainFrame.Name = "Main"
MainFrame.Size = UDim2.new(0, 220, 0, 160)
MainFrame.Position = UDim2.new(0.5, -110, 0.3, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
MainFrame.BackgroundTransparency = 0.2
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

Instance.new("UICorner").CornerRadius = UDim.new(0, 8); -- Parent = MainFrame (inline fix: add after)
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = MainFrame

-- Title
local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 25)
Title.BackgroundTransparency = 1
Title.Text = "Sentinel Arsenal v2.0"
Title.TextColor3 = Color3.fromRGB(0, 255, 200)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.Parent = MainFrame

-- Toggles
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
    Instance.new("UICorner").CornerRadius = UDim.new(0, 5); -- Parent fix
    local c2 = Instance.new("UICorner"); c2.CornerRadius = UDim.new(0, 5); c2.Parent = toggle
    
    local state = default
    toggle.MouseButton1Click:Connect(function()
        state = not state
        toggle.BackgroundColor3 = state and Color3.fromRGB(0, 180, 100) or Color3.fromRGB(180, 0, 0)
        toggle.Text = name .. ": " .. (state and "ON" or "OFF")
        callback(state)
    end)
    
    return toggle, state
end

-- Sliders
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
    local c3 = Instance.new("UICorner"); c3.CornerRadius = UDim.new(0, 4); c3.Parent = slider
    
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
    fill.BorderSizePixel = 0
    fill.Parent = slider
    Instance.new("UICorner").CornerRadius = UDim.new(0, 4); -- Parent fix
    local c4 = Instance.new("UICorner"); c4.CornerRadius = UDim.new(0, 4); c4.Parent = fill
    
    local value = default
    local function update(val)
        value = math.clamp(val, min, max)
        fill.Size = UDim2.new((value - min) / (max - min), 0, 1, 0)
        label.Text = name .. ": " .. math.round(value)
        callback(value)
    end
    
    slider.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local connection
            connection = UserInputService.InputChanged:Connect(function(change)
                if change.UserInputType == Enum.UserInputType.MouseMovement then
                    local mousePos = UserInputService:GetMouseLocation()
                    local sliderPos = slider.AbsolutePosition.X
                    local sliderWidth = slider.AbsoluteSize.X
                    local percent = math.clamp((mousePos.X - sliderPos) / sliderWidth, 0, 1)
                    update(min + percent * (max - min))
                end
            end)
            UserInputService.InputEnded:Connect(function(endInput)
                if endInput.UserInputType == Enum.UserInputType.MouseButton1 then
                    connection:Disconnect()
                end
            end)
        end
    end)
    
    return update
end

-- Status
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -20, 0, 20)
StatusLabel.Position = UDim2.new(0, 10, 0, 140)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "🎯 Target: None"
StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 10
StatusLabel.Parent = MainFrame

-- Init UI elements
CreateToggle("Silent Aim", 30, Config.SilentAim.Enabled, function(v) Config.SilentAim.Enabled = v end)
CreateToggle("SpinBot", 58, Config.SpinBot.Enabled, function(v) Config.SpinBot.Enabled = v end)
CreateToggle("Auto Shoot", 86, Config.AutoShoot.Enabled, function(v) Config.AutoShoot.Enabled = v end)
CreateSlider("FOV", 115, 50, 500, Config.SilentAim.FOV, function(v) Config.SilentAim.FOV = v end)
CreateSlider("Speed", 135, 1, 20, Config.SpinBot.Speed, function(v) Config.SpinBot.Speed = v end)

function UpdateUIStatus(target)
    if target then
        StatusLabel.Text = string.format("🎯 %s | %.0fm | %s", target.Player.Name, target.Distance3D, target.IsHead and "HEAD" or "BODY")
        StatusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    else
        StatusLabel.Text = "🔍 Searching..."
        StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
    end
end

-- ============================================
-- INIT
-- ============================================
task.spawn(function()
    task.wait(1)
    FindRemotes()
    Debug("Sentinel Arsenal v2.0 loaded", "SUCCESS")
    Debug("Features: Silent Aim | SpinBot | Auto Shoot", "INFO")
    Debug("Remote: " .. (State.Remote and State.Remote:GetFullName() or "VirtualUser fallback"), "INFO")
end)

RunService.RenderStepped:Connect(OnRender)

-- ============================================
-- RETURN (for loadstring compatibility)
-- ============================================
return {
    Config = Config,
    State = State,
    Enable = function() Config.SilentAim.Enabled = true; Config.AutoShoot.Enabled = true end,
    Disable = function() Config.SilentAim.Enabled = false; Config.AutoShoot.Enabled = false; Config.SpinBot.Enabled = false end,
    ToggleSpinBot = function() Config.SpinBot.Enabled = not Config.SpinBot.Enabled end,
    GetTarget = GetTarget,
    FindRemotes = FindRemotes,
}
