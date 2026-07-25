-- Onyx v67 | Speed + BunnyHop — Arsenal Mobile
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local Cfg = {
    SpeedEnabled = true,
    WalkSpeed = 42,         -- Arsenal default = 16, 42 = fast but not obvious
    BunnyHop = true,
    JumpPower = 60,
    AutoHop = true,         -- auto jump when hitting ground
}

local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")

-- apply speed
if Cfg.SpeedEnabled then
    Humanoid.WalkSpeed = Cfg.WalkSpeed
    Humanoid.JumpPower = Cfg.JumpPower

    LocalPlayer.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid")
        hum.WalkSpeed = Cfg.WalkSpeed
        hum.JumpPower = Cfg.JumpPower
    end)
end

-- bunny hop
if Cfg.BunnyHop and Cfg.AutoHop then
    local hopping = false

    Humanoid.StateChanged:Connect(function(_, new)
        if new == Enum.HumanoidStateType.Landed then
            task.wait(0.01)
            Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)
end

print("[Onyx v67] Speed + BunnyHop loaded")
