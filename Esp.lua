-- Onyx v67 | Arsenal ESP — Mobile Optimized
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local ESPCfg = {
    BoxESP = true,
    NameESP = true,
    HealthBar = true,
    DistanceESP = true,
    TeamColor = true,
    EnemyColor = Color3.fromRGB(255, 60, 60),
    AllyColor = Color3.fromRGB(60, 180, 255),
}

local ESPFolder = Instance.new("Folder", game.CoreGui)
ESPFolder.Name = "OnyxESP_Arsenal"

local function buildESP(player)
    if player == LocalPlayer then return end

    local gui = Instance.new("BillboardGui", ESPFolder)
    gui.Name = "ESP_" .. player.Name
    gui.AlwaysOnTop = true
    gui.Size = UDim2.new(0, 120, 0, 70)
    gui.StudsOffset = Vector3.new(0, 3.5, 0)

    local nameLabel = Instance.new("TextLabel", gui)
    nameLabel.Name = "Name"
    nameLabel.Size = UDim2.new(1, 0, 0, 20)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 13
    nameLabel.TextStrokeTransparency = 0
    nameLabel.Text = player.Name

    local distLabel = Instance.new("TextLabel", gui)
    distLabel.Name = "Dist"
    distLabel.Size = UDim2.new(1, 0, 0, 16)
    distLabel.Position = UDim2.new(0, 0, 0, 20)
    distLabel.BackgroundTransparency = 1
    distLabel.Font = Enum.Font.Gotham
    distLabel.TextSize = 11
    distLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    distLabel.TextStrokeTransparency = 0

    local hpLabel = Instance.new("TextLabel", gui)
    hpLabel.Name = "HP"
    hpLabel.Size = UDim2.new(1, 0, 0, 14)
    hpLabel.Position = UDim2.new(0, 0, 0, 38)
    hpLabel.BackgroundTransparency = 1
    hpLabel.Font = Enum.Font.Gotham
    hpLabel.TextSize = 11
    hpLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    hpLabel.TextStrokeTransparency = 0

    RunService.RenderStepped:Connect(function()
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local root = player.Character.HumanoidRootPart
            local hum = player.Character:FindFirstChild("Humanoid")
            local localRoot = LocalPlayer.Character and
                LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

            gui.Adornee = root

            -- color by team
            local isEnemy = player.Team ~= LocalPlayer.Team
            nameLabel.TextColor3 = isEnemy and ESPCfg.EnemyColor or ESPCfg.AllyColor

            -- distance
            if localRoot then
                local dist = math.floor((localRoot.Position - root.Position).Magnitude)
                distLabel.Text = dist .. "m"
            end

            -- hp
            if hum then
                local hp = math.floor(hum.Health)
                local maxHp = math.floor(hum.MaxHealth)
                hpLabel.Text = "HP: " .. hp .. "/" .. maxHp
                local ratio = hp / maxHp
                hpLabel.TextColor3 = Color3.fromRGB(
                    255 - (ratio * 100),
                    55 + (ratio * 200),
                    55
                )
            end
        else
            gui.Adornee = nil
        end
    end)
end

for _, p in ipairs(Players:GetPlayers()) do buildESP(p) end
Players.PlayerAdded:Connect(buildESP)
Players.PlayerRemoving:Connect(function(p)
    local g = ESPFolder:FindFirstChild("ESP_" .. p.Name)
    if g then g:Destroy() end
end)

print("[Onyx v67] ESP Arsenal loaded")
