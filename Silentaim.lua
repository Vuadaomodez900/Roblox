-- Onyx v67 | Arsenal Silent Aim — Mobile Compatible
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- CONFIG
local SilentAim = {
    Enabled = true,
    TargetPart = "Head",
    MaxRange = 500,
    TeamCheck = true,   -- true = only hit enemies
    VisibilityCheck = false,  -- false = shoot through walls
    FOV = 360,          -- degrees, 360 = no FOV limit
}

-- get target
local function getTarget()
    local closest = nil
    local closestDist = math.huge
    local viewportCenter = Vector2.new(
        Camera.ViewportSize.X / 2,
        Camera.ViewportSize.Y / 2
    )

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local hum = player.Character:FindFirstChild("Humanoid")
            local part = player.Character:FindFirstChild(SilentAim.TargetPart)

            if hum and hum.Health > 0 and part then
                -- team check
                if SilentAim.TeamCheck and player.Team == LocalPlayer.Team then
                    continue
                end

                local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen then
                    local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - viewportCenter).Magnitude
                    local fovRad = math.rad(SilentAim.FOV / 2)
                    local fovPx = math.tan(fovRad) * Camera.ViewportSize.X

                    if screenDist < fovPx and screenDist < closestDist then
                        closestDist = screenDist
                        closest = player
                    end
                end
            end
        end
    end
    return closest
end

-- hook
local oldIndex
oldIndex = hookmetamethod(game, "__index", function(self, key)
    if not checkcaller() then
        if key == "Hit" or key == "Origin" then
            local target = getTarget()
            if SilentAim.Enabled and target and target.Character then
                local part = target.Character:FindFirstChild(SilentAim.TargetPart)
                if part then
                    if key == "Hit" then
                        return CFrame.new(part.Position)
                    elseif key == "Origin" then
                        return CFrame.new(part.Position)
                    end
                end
            end
        end
    end
    return oldIndex(self, key)
end)

print("[Onyx v67] Silent Aim loaded — Arsenal Mobile")
