-- Onyx v67 | Auto Shoot — Mobile tap simulation
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local AutoShoot = {
    Enabled = true,
    Range = 300,
    FireRate = 0.07,    -- seconds between shots
    TargetPart = "Head",
}

local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local RootPart = Character:WaitForChild("HumanoidRootPart")

local function getNearestEnemy()
    local closest = nil
    local closestDist = AutoShoot.Range

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hum = p.Character:FindFirstChild("Humanoid")
            local root = p.Character:FindFirstChild("HumanoidRootPart")
            if hum and hum.Health > 0 and root then
                local dist = (RootPart.Position - root.Position).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closest = p
                end
            end
        end
    end
    return closest
end

task.spawn(function()
    while task.wait(AutoShoot.FireRate) do
        if AutoShoot.Enabled then
            local target = getNearestEnemy()
            if target and target.Character then
                local part = target.Character:FindFirstChild(AutoShoot.TargetPart)
                if part then
                    -- aim camera
                    Camera.CFrame = CFrame.new(
                        Camera.CFrame.Position,
                        part.Position
                    )
                    -- simulate tap on shoot button center
                    local cx = Camera.ViewportSize.X / 2
                    local cy = Camera.ViewportSize.Y / 2
                    VirtualUser:Button1Down(Vector2.new(cx, cy), Camera.CFrame)
                    task.wait(0.03)
                    VirtualUser:Button1Up(Vector2.new(cx, cy), Camera.CFrame)
                end
            end
        end
    end
end)

print("[Onyx v67] AutoShoot Mobile loaded")
