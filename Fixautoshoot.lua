-- Onyx v67 | Arsenal Auto Shoot + Silent Aim
-- Optimized for Arsenal (ROBLOX FPS)
-- Uses mobile tap simulation, silent aim, auto reload, team check

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ============================================
-- CONFIGURATION
-- ============================================
local Config = {
    -- Main
    Enabled = true,
    SilentAim = true,           -- Silent aim (no camera movement visible)
    AutoShoot = true,           -- Auto fire when target in range
    TriggerBot = false,         -- Only shoot when crosshair is on target
    
    -- Targeting
    Range = 500,                -- Max distance
    FOV = 200,                  -- Field of view (pixels from center)
    TargetPart = "Head",        -- Head, HumanoidRootPart, UpperTorso
    PrioritizeHead = true,      -- Prefer headshots
    
    -- Combat
    FireRate = 0.08,            -- Min delay between shots
    BurstFire = false,          -- Burst mode
    BurstCount = 3,             -- Shots per burst
    BurstDelay = 0.15,          -- Delay between bursts
    
    -- Safety
    TeamCheck = true,           -- Don't shoot teammates
    VisibleCheck = true,        -- Only shoot visible enemies
    AutoReload = true,          -- Reload when empty
    MaxShotsBeforeReload = 30,  -- Force reload after X shots
    
    -- Arsenal Specific
    ArsenalMode = true,         -- Use Arsenal-specific features
    AntiGroundShot = true,      -- Don't shoot when looking at ground
    JumpShot = false,           -- Shoot while jumping
}

-- ============================================
-- STATE
-- ============================================
local State = {
    Character = nil,
    RootPart = nil,
    Humanoid = nil,
    CurrentGun = nil,
    Ammo = 0,
    MaxAmmo = 0,
    IsReloading = false,
    LastShotTime = 0,
    ShotsFired = 0,
    TargetLocked = nil,
    ScreenCenter = Vector2.new(0, 0),
    IsMobile = false,
}

-- ============================================
-- CHARACTER MANAGEMENT
-- ============================================
local function UpdateCharacter()
    State.Character = LocalPlayer.Character
    if State.Character then
        State.RootPart = State.Character:FindFirstChild("HumanoidRootPart")
        State.Humanoid = State.Character:FindFirstChild("Humanoid")
    else
        State.RootPart = nil
        State.Humanoid = nil
    end
end

UpdateCharacter()
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    UpdateCharacter()
end)
LocalPlayer.CharacterRemoving:Connect(function()
    State.RootPart = nil
    State.Humanoid = nil
    State.TargetLocked = nil
end)

-- ============================================
-- ARSENAL WEAPON DETECTION
-- ============================================
local function GetCurrentWeapon()
    if not State.Character then return nil end
    
    -- Arsenal stores weapon in character or backpack
    local tool = State.Character:FindFirstChildOfClass("Tool")
    if not tool then
        local backpack = LocalPlayer.Backpack
        if backpack then
            tool = backpack:FindFirstChildOfClass("Tool")
        end
    end
    
    if tool then
        State.CurrentGun = tool
        
        -- Try to get ammo info from weapon
        local ammoGui = tool:FindFirstChild("Ammo") or tool:FindFirstChild("AmmoGui")
        if ammoGui then
            local ammoText = ammoGui:FindFirstChildOfClass("TextLabel")
            if ammoText then
                local ammoStr = ammoText.Text
                local current, max = ammoStr:match("(%d+)%s*/%s*(%d+)")
                if current and max then
                    State.Ammo = tonumber(current)
                    State.MaxAmmo = tonumber(max)
                end
            end
        end
        
        return tool
    end
    
    return nil
end

-- ============================================
-- TARGETING SYSTEM
-- ============================================
local function WorldToScreen(position)
    local screenPos, onScreen = Camera:WorldToViewportPoint(position)
    return Vector2.new(screenPos.X, screenPos.Y), onScreen
end

local function IsInFOV(screenPos)
    local center = State.ScreenCenter
    local dx = screenPos.X - center.X
    local dy = screenPos.Y - center.Y
    return (dx * dx + dy * dy) <= (Config.FOV * Config.FOV)
end

local function IsEnemyVisible(targetPart)
    if not State.RootPart then return false end
    
    local origin = State.RootPart.Position
    local direction = (targetPart.Position - origin).Unit * Config.Range
    
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = {State.Character}
    rayParams.IgnoreWater = true
    
    local result = workspace:Raycast(origin, direction, rayParams)
    
    if result then
        local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
        local targetModel = targetPart:FindFirstAncestorOfClass("Model")
        return hitModel == targetModel
    end
    
    return false
end

local function GetNearestTarget()
    if not State.RootPart then return nil end
    
    local bestTarget = nil
    local bestScore = math.huge
    local rootPos = State.RootPart.Position
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if Config.TeamCheck and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then continue end
        
        local char = player.Character
        if not char then continue end
        
        local hum = char:FindFirstChild("Humanoid")
        local root = char:FindFirstChild("HumanoidRootPart")
        if not hum or hum.Health <= 0 or not root then continue end
        
        -- Distance check
        local dist = (rootPos - root.Position).Magnitude
        if dist > Config.Range then continue end
        
        -- Get target part
        local targetPart = nil
        if Config.TargetPart == "Head" then
            targetPart = char:FindFirstChild("Head") or char:FindFirstChild("UpperTorso") or root
        else
            targetPart = char:FindFirstChild(Config.TargetPart) or root
        end
        
        if not targetPart then continue end
        
        -- Screen position check
        local screenPos, onScreen = WorldToScreen(targetPart.Position)
        if not onScreen then continue end
        if not IsInFOV(screenPos) then continue end
        
        -- Visibility check
        if Config.VisibleCheck and not IsEnemyVisible(targetPart) then continue end
        
        -- Score calculation (lower is better)
        -- Prioritize: closer to crosshair + headshots + closer distance
        local dx = screenPos.X - State.ScreenCenter.X
        local dy = screenPos.Y - State.ScreenCenter.Y
        local fovDist = math.sqrt(dx * dx + dy * dy)
        
        local score = fovDist * 1.0  -- FOV priority
        if Config.PrioritizeHead and targetPart.Name == "Head" then
            score = score * 0.5  -- Prefer head
        end
        score = score + dist * 0.01  -- Slight distance factor
        
        if score < bestScore then
            bestScore = score
            bestTarget = {
                Player = player,
                Character = char,
                Part = targetPart,
                ScreenPos = screenPos,
                Distance = dist,
                IsHead = targetPart.Name == "Head",
                Humanoid = hum,
            }
        end
    end
    
    return bestTarget
end

-- ============================================
-- SHOOTING SYSTEM
-- ============================================
local function SimulateTapAt(screenPos)
    if not State.IsMobile then
        -- PC: use mouse event simulation
        VirtualUser:Button1Down(screenPos, Camera.CFrame)
        task.wait(0.03)
        VirtualUser:Button1Up(screenPos, Camera.CFrame)
    else
        -- Mobile: use VirtualUser tap
        VirtualUser:Button1Down(screenPos, Camera.CFrame)
        task.wait(0.02)
        VirtualUser:Button1Up(screenPos, Camera.CFrame)
    end
end

local function SilentAim(target)
    -- Arsenal silent aim: modify bullet trajectory via remote event manipulation
    -- This requires Arsenal-specific implementation
    -- Many Arsenal versions have a ShootRemote or BulletRemote
    
    -- Attempt to find the remote
    local shootRemote = nil
    
    -- Common Arsenal remotes
    local remotes = {"Shoot", "Fire", "Bullet", "FireServer", "ShootBullet"}
    for _, name in ipairs(remotes) do
        local remote = ReplicatedStorage:FindFirstChild(name, true)
        if remote then
            shootRemote = remote
            break
        end
    end
    
    if shootRemote and target then
        -- Fire with modified direction
        local args = {
            [1] = target.Part.Position,  -- Target position
            [2] = target.Part,           -- Target part
            [3] = target.Player,         -- Target player
        }
        
        pcall(function()
            shootRemote:FireServer(unpack(args))
        end)
        return true
    end
    
    return false
end

local function Shoot(target)
    if not target then return false end
    
    local currentTime = tick()
    if currentTime - State.LastShotTime < Config.FireRate then return false end
    
    -- Arsenal-specific silent aim
    if Config.ArsenalMode and Config.SilentAim then
        if SilentAim(target) then
            State.LastShotTime = currentTime
            State.ShotsFired += 1
            return true
        end
    end
    
    -- Standard aim + shoot
    if not Config.SilentAim then
        -- Aim camera at target
        Camera.CFrame = CFrame.new(
            Camera.CFrame.Position,
            target.Part.Position
        )
        task.wait(0.01)
    end
    
    -- Simulate shoot
    local shootPos = target.ScreenPos or State.ScreenCenter
    SimulateTapAt(shootPos)
    
    State.LastShotTime = currentTime
    State.ShotsFired += 1
    State.TargetLocked = target
    
    return true
end

-- ============================================
-- AUTO RELOAD
-- ============================================
local function AutoReload()
    if not Config.AutoReload then return end
    if State.ShotsFired < Config.MaxShotsBeforeReload then return end
    if State.IsReloading then return end
    
    State.IsReloading = true
    
    -- Press R key or reload button
    VirtualUser:Button2Down(Vector2.new(0, 0), Camera.CFrame)
    task.wait(0.1)
    VirtualUser:Button2Up(Vector2.new(0, 0), Camera.CFrame)
    
    task.wait(0.5) -- Wait for reload animation
    State.ShotsFired = 0
    State.IsReloading = false
end

-- ============================================
-- ANTI-DETECTION (Arsenal specific)
-- ============================================
local function AntiGroundShot()
    if not Config.AntiGroundShot then return false end
    if not State.RootPart then return false end
    
    -- Check if camera is looking at ground
    local rayOrigin = Camera.CFrame.Position
    local rayDirection = Camera.CFrame.LookVector * 50
    
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = {State.Character}
    
    local result = workspace:Raycast(rayOrigin, rayDirection, rayParams)
    
    if result then
        local material = result.Material
        -- If looking at ground/terrain, don't shoot
        if material == Enum.Material.Grass or 
           material == Enum.Material.Ground or
           material == Enum.Material.Sand or
           material == Enum.Material.Concrete then
            return true
        end
    end
    
    return false
end

-- ============================================
-- MAIN LOOP
-- ============================================
RunService.Heartbeat:Connect(function()
    -- Update screen center
    State.ScreenCenter = Vector2.new(
        Camera.ViewportSize.X / 2,
        Camera.ViewportSize.Y / 2
    )
    
    -- Check if enabled
    if not Config.Enabled then return end
    if not State.RootPart then return end
    if State.Humanoid and State.Humanoid.Health <= 0 then return end
    
    -- Mobile detection
    State.IsMobile = UserInputService.TouchEnabled
    
    -- Arsenal specific checks
    if Config.AntiGroundShot and AntiGroundShot() then return end
    
    -- Get current weapon
    GetCurrentWeapon()
    
    -- Get target
    local target = GetNearestTarget()
    
    -- TriggerBot mode: only shoot when target is near crosshair
    if Config.TriggerBot and target then
        local screenPos = target.ScreenPos
        local dx = math.abs(screenPos.X - State.ScreenCenter.X)
        local dy = math.abs(screenPos.Y - State.ScreenCenter.Y)
        if dx > 15 or dy > 15 then
            target = nil  -- Don't shoot, not close enough to crosshair
        end
    end
    
    -- Auto Shoot
    if Config.AutoShoot and target then
        -- Burst fire mode
        if Config.BurstFire then
            for i = 1, Config.BurstCount do
                if not Shoot(target) then break end
                task.wait(0.05)
            end
            task.wait(Config.BurstDelay)
        else
            Shoot(target)
        end
    end
    
    -- Auto reload
    AutoReload()
end)

-- ============================================
-- COMMANDS
-- ============================================
LocalPlayer.Chatted:Connect(function(msg)
    local cmd = msg:lower()
    
    if cmd == "/as on" then
        Config.Enabled = true
        print("[Onyx Arsenal] AutoShoot: ON")
    elseif cmd == "/as off" then
        Config.Enabled = false
        print("[Onyx Arsenal] AutoShoot: OFF")
    elseif cmd == "/as silent" then
        Config.SilentAim = not Config.SilentAim
        print("[Onyx Arsenal] Silent Aim: " .. (Config.SilentAim and "ON" or "OFF"))
    elseif cmd == "/as head" then
        Config.TargetPart = "Head"
        print("[Onyx Arsenal] Target: Head")
    elseif cmd == "/as body" then
        Config.TargetPart = "HumanoidRootPart"
        print("[Onyx Arsenal] Target: Body")
    elseif cmd == "/as fov" then
        local num = tonumber(msg:match("%d+"))
        if num then
            Config.FOV = num
            print("[Onyx Arsenal] FOV: " .. num)
        end
    elseif cmd == "/as range" then
        local num = tonumber(msg:match("%d+"))
        if num then
            Config.Range = num
            print("[Onyx Arsenal] Range: " .. num)
        end
    elseif cmd == "/as visible" then
        Config.VisibleCheck = not Config.VisibleCheck
        print("[Onyx Arsenal] Visible Check: " .. (Config.VisibleCheck and "ON" or "OFF"))
    elseif cmd == "/as trigger" then
        Config.TriggerBot = not Config.TriggerBot
        Config.AutoShoot = not Config.AutoShoot
        print("[Onyx Arsenal] TriggerBot: " .. (Config.TriggerBot and "ON" or "OFF"))
    elseif cmd == "/as burst" then
        Config.BurstFire = not Config.BurstFire
        print("[Onyx Arsenal] Burst Fire: " .. (Config.BurstFire and "ON" or "OFF"))
    elseif cmd == "/as info" then
        print("[Onyx Arsenal v67]")
        print("  Silent Aim: " .. tostring(Config.SilentAim))
        print("  Auto Shoot: " .. tostring(Config.AutoShoot))
        print("  TriggerBot: " .. tostring(Config.TriggerBot))
        print("  Target: " .. Config.TargetPart)
        print("  Range: " .. Config.Range)
        print("  FOV: " .. Config.FOV)
        print("  Visible Check: " .. tostring(Config.VisibleCheck))
        print("  Burst Fire: " .. tostring(Config.BurstFire))
    end
end)

-- ============================================
-- INITIALIZATION
-- ============================================
print("[Onyx v67] Arsenal AutoShoot + Silent Aim loaded")
print("[Onyx] Commands: /as on|off|silent|head|body|fov#|range#|visible|trigger|burst|info")
