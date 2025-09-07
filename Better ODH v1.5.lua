local shared = odh_shared_plugins
local custom_tab = shared.AddSection("Customizations")

local Players     = game:GetService("Players")
local Lighting    = game:GetService("Lighting")
local UIS         = game:GetService("UserInputService")
local RunService  = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- =============================
-- 1) MOTION BLUR SETUP
-- =============================
local blur = Lighting:FindFirstChildOfClass("BlurEffect") or Instance.new("BlurEffect")
blur.Parent = Lighting
blur.Size = 0

local mb_enabled = false
local lastCFrame = Camera.CFrame
local lerpSpeed = 6
local maxBlur = 8
local minThreshold = 0.03

custom_tab:AddToggle("Enable Motion Blur", function(on)
    mb_enabled = on
    if not on then blur.Size = 0 end
end)

custom_tab:AddSlider("Blur Strength", 1, 20, maxBlur, function(v)
    maxBlur = v
end)

custom_tab:AddSlider("Blur Smoothness", 1, 15, lerpSpeed, function(v)
    lerpSpeed = v
end)

RunService.RenderStepped:Connect(function(delta)
    if not mb_enabled then return end
    local lastLook = lastCFrame.LookVector
    local currentLook = Camera.CFrame.LookVector
    local dot = math.clamp(lastLook:Dot(currentLook), -1, 1)
    local angle = math.acos(dot)

    local target = 0
    if angle > minThreshold then
        target = math.clamp(angle / 0.04, 0, 1) * maxBlur
    end

    blur.Size = blur.Size + (target - blur.Size) * math.clamp(lerpSpeed * delta, 0, 1)
    lastCFrame = Camera.CFrame
end)

-- =============================
-- 2) JUMP BUTTON SIZE CHANGER
-- =============================
local jb_enabled = false
local jb_size    = 100

local function findJumpButton()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local tg = pg:FindFirstChild("TouchGui")
    if not tg then return nil end
    local tcf = tg:FindFirstChild("TouchControlFrame")
    if tcf then
        local jb = tcf:FindFirstChild("JumpButton", true)
        if jb and (jb:IsA("ImageButton") or jb:IsA("TextButton")) then return jb end
    end
    for _, d in ipairs(tg:GetDescendants()) do
        if d.Name == "JumpButton" and (d:IsA("ImageButton") or d:IsA("TextButton")) then return d end
    end
    return nil
end

local function setJumpButtonSize(px)
    local jb = findJumpButton()
    if not jb then return end
    local screen = Camera.ViewportSize
    local maxSize = math.min(screen.X, screen.Y) * 0.25
    local clamped = math.clamp(px, 50, maxSize)
    jb.Size = UDim2.new(0, clamped, 0, clamped)
    jb.Position = UDim2.new(1, -clamped - 20, 1, -clamped - 20)
end

custom_tab:AddToggle("Jump Button Size Changer (Mobile & Tablet)", function(on)
    jb_enabled = on
    if not UIS.TouchEnabled then return end
    if on then setJumpButtonSize(jb_size) end
end)

custom_tab:AddSlider("Jump Button Size Changer (Mobile & Tablet)", 50, 125, jb_size, function(v)
    jb_size = v
    if jb_enabled and UIS.TouchEnabled then setJumpButtonSize(jb_size) end
end)

LocalPlayer.PlayerGui.ChildAdded:Connect(function(child)
    if jb_enabled and UIS.TouchEnabled and child.Name == "TouchGui" then
        task.defer(function() setJumpButtonSize(jb_size) end)
    end
end)

-- =============================
-- 3) TOOLS OUTLINE
-- =============================
local outline_enabled = false
local outline_rainbow = false
local tool_highlights = {}

local colors = {
    Black   = Color3.fromRGB(0,0,0),
    White   = Color3.fromRGB(255,255,255),
    Red     = Color3.fromRGB(255,0,0),
    Blue    = Color3.fromRGB(0,0,255),
    Pink    = Color3.fromRGB(255,105,180),
    Magenta = Color3.fromRGB(255,0,255),
    Purple  = Color3.fromRGB(128,0,128),
    Orange  = Color3.fromRGB(255,165,0),
    Green   = Color3.fromRGB(0,128,0),
    Cyan    = Color3.fromRGB(0,255,255),
    Yellow  = Color3.fromRGB(255,255,0),
    Gold    = Color3.fromRGB(255,215,0),
    Ocean   = Color3.fromRGB(0,128,255)
}

local defaultOutline = colors.Purple
local defaultFill    = colors.Black
local selectedOutline = defaultOutline
local selectedFill    = defaultFill

local function ensureOutline(tool)
    if not tool:IsA("Tool") then return end
    local handle = tool:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then return end
    handle.LocalTransparencyModifier = 0  -- slightly transparent

    local hl = tool:FindFirstChild("ToolOutline")
    if not hl then
        hl = Instance.new("Highlight")
        hl.Name = "ToolOutline"
        hl.Adornee = handle
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillTransparency = 0.8
        hl.OutlineTransparency = 0.8
        hl.Parent = tool
    end

    hl.Enabled = outline_enabled
    hl.OutlineColor = selectedOutline
    hl.FillColor = selectedFill
    tool_highlights[tool] = hl
end

local function applyOutlineToAllTools()
    tool_highlights = {}
    for _, t in ipairs(LocalPlayer.Backpack:GetChildren()) do ensureOutline(t) end
    local char = LocalPlayer.Character
    if char then for _, t in ipairs(char:GetChildren()) do ensureOutline(t) end end
end

local function removeOutlines()
    for tool, hl in pairs(tool_highlights) do
        if hl then hl:Destroy() end
        if tool and tool:FindFirstChild("Handle") then
            tool.Handle.LocalTransparencyModifier = 0.5
        end
    end
    tool_highlights = {}
end

local function applyOnRespawn()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    char:WaitForChild("HumanoidRootPart")
    applyOutlineToAllTools()
end

custom_tab:AddToggle("Enable Tool Outline Theme", function(on)
    outline_enabled = on
    if on then applyOnRespawn() else removeOutlines() end
end)

local colorNames = {}
for name,_ in pairs(colors) do table.insert(colorNames,name) end

custom_tab:AddDropdown("Select Outline Color", colorNames, function(selected)
    selectedOutline = colors[selected]
    for _, hl in pairs(tool_highlights) do
        if hl then hl.OutlineColor = selectedOutline end
    end
end)

custom_tab:AddDropdown("Select Fill Color", colorNames, function(selected)
    selectedFill = colors[selected]
    for _, hl in pairs(tool_highlights) do
        if hl then hl.FillColor = selectedFill end
    end
end)

custom_tab:AddToggle("Rainbow Tool Outline", function(on)
    outline_rainbow = on
end)

local hue = 0
RunService.RenderStepped:Connect(function()
    if not outline_rainbow then return end
    hue = (hue + 0.5) % 360 -- slower for smooth rainbow
    local color = Color3.fromHSV(hue/360, 1, 1)
    for _, hl in pairs(tool_highlights) do
        if hl then
            hl.OutlineColor = color
            hl.FillColor = color
        end
    end
end)

LocalPlayer.Backpack.ChildAdded:Connect(function(obj)
    if outline_enabled then ensureOutline(obj) end
end)
LocalPlayer.CharacterAdded:Connect(function()
    if outline_enabled then task.defer(applyOnRespawn) end
end)

-- =============================
-- PART 2 (Wide Screen & Fonts)
-- =============================
local shared = odh_shared_plugins
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local RunService = game:GetService("RunService")
local ui_tab = shared.AddSection("UI & Fonts")

-- =============================
-- WIDE SCREEN TOGGLE
-- =============================
local wideScreenEnabled = false
local wideScreenStrength = 0.7

ui_tab:AddToggle("Wide Screen", function(on)
    wideScreenEnabled = on
end)

RunService.RenderStepped:Connect(function()
    if wideScreenEnabled then
        Camera.CFrame = Camera.CFrame * CFrame.new(0,0,0,1,0,0,0,wideScreenStrength,0,0,0,1)
    end
end)

-- =============================
-- FONTS
-- =============================
local fonts = {
    ["SourceSans (Original)"] = Enum.Font.SourceSans,
    ["Gotham"] = Enum.Font.Gotham,
    ["Arcade"] = Enum.Font.Arcade,
    ["Arial"] = Enum.Font.Arial,
    ["ArialBold"] = Enum.Font.ArialBold,
    ["Cartoon"] = Enum.Font.Cartoon,
    ["Fantasy"] = Enum.Font.Fantasy,
    ["Highway"] = Enum.Font.Highway,
    ["Code"] = Enum.Font.Code,
    ["Legacy"] = Enum.Font.Legacy
}

local selectedFont = "SourceSans (Original)"

ui_tab:AddDropdown("Select Font", {
    "SourceSans (Original)","Gotham","Arcade","Arial","ArialBold","Cartoon","Fantasy","Highway","Code","Legacy"
}, function(option)
    selectedFont = option
    for _, gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
        if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
            gui.Font = fonts[selectedFont]
        end
    end
end)

-- Apply font to new GUI elements dynamically
LocalPlayer.PlayerGui.DescendantAdded:Connect(function(gui)
    if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
        gui.Font = fonts[selectedFont]
    end
end)

local shared = odh_shared_plugins
local perf_tab    = shared.AddSection("Performance & FPS")
local credits_tab = shared.AddSection("Credits")
local Lighting    = game:GetService("Lighting")
local Workspace   = game:GetService("Workspace")
local Players     = game:GetService("Players")

-- =============================
-- STATE STORAGE
-- =============================
local original_materials = {}
local original_particle_states = {}
local original_textures = {}
local original_mesh_transparency = {}
local original_accessories = {}
local conns = {}

-- =============================
-- HELPERS
-- =============================

local function isPlayerDescendant(obj)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character and obj:IsDescendantOf(plr.Character) then
            return true
        end
    end
    return false
end

local function applyMeshToObj(obj)
    if isPlayerDescendant(obj) then return end -- skip player meshes

    if obj:IsA("MeshPart") then
        if original_mesh_transparency[obj] == nil then
            original_mesh_transparency[obj] = obj.Transparency
        end
        obj.Transparency = 1
        return
    end

    if obj:IsA("SpecialMesh") or obj:IsA("BlockMesh") or obj:IsA("CylinderMesh") then
        local parent = obj.Parent
        if parent and parent:IsA("BasePart") and not isPlayerDescendant(parent) then
            if original_mesh_transparency[parent] == nil then
                original_mesh_transparency[parent] = parent.Transparency
            end
            parent.Transparency = 1
        end
    end
end

local function setMeshes(on)
    if on then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            applyMeshToObj(obj)
        end
        if not conns.Meshes then
            conns.Meshes = Workspace.DescendantAdded:Connect(function(obj)
                task.defer(function() applyMeshToObj(obj) end)
            end)
        end
    else
        for part, trans in pairs(original_mesh_transparency) do
            if part and part.Parent then
                pcall(function() part.Transparency = trans end)
            end
        end
        original_mesh_transparency = {}
        if conns.Meshes then
            conns.Meshes:Disconnect()
            conns.Meshes = nil
        end
    end
end

-- =============================
-- ACCESSORIES (unchanged)
-- =============================
local function setAccessories(on)
    if on then
        for _, plr in ipairs(Players:GetPlayers()) do
            local char = plr.Character
            if char then
                for _, acc in ipairs(char:GetChildren()) do
                    if acc:IsA("Accessory") then
                        original_accessories[acc] = plr
                        acc.Parent = nil
                    end
                end
            end
        end
        if not conns.CharacterAdded then
            conns.CharacterAdded = Players.PlayerAdded:Connect(function(p)
                p.CharacterAdded:Connect(function(ch)
                    task.defer(function()
                        for _, acc in ipairs(ch:GetChildren()) do
                            if acc:IsA("Accessory") then
                                original_accessories[acc] = p
                                acc.Parent = nil
                            end
                        end
                    end)
                end)
            end)
        end
    else
        for acc, owner in pairs(original_accessories) do
            if owner and owner.Character and acc and not acc.Parent then
                pcall(function() acc.Parent = owner.Character end)
            end
        end
        original_accessories = {}
        if conns.CharacterAdded then
            conns.CharacterAdded:Disconnect()
            conns.CharacterAdded = nil
        end
    end
end

-- =============================
-- SMOOTH PLASTIC, PARTICLES, TEXTURES, SHADOWS, SKY
-- (same as before)
-- =============================

local function setSmoothPlastic(on)
    if on then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") and not isPlayerDescendant(obj) and obj.Material ~= Enum.Material.SmoothPlastic then
                original_materials[obj] = obj.Material
                obj.Material = Enum.Material.SmoothPlastic
            end
        end
        if not conns.Smooth then
            conns.Smooth = Workspace.DescendantAdded:Connect(function(obj)
                if obj:IsA("BasePart") and not isPlayerDescendant(obj) then
                    original_materials[obj] = obj.Material
                    obj.Material = Enum.Material.SmoothPlastic
                end
            end)
        end
    else
        for part, mat in pairs(original_materials) do
            if part and part.Parent then
                pcall(function() part.Material = mat end)
            end
        end
        original_materials = {}
        if conns.Smooth then conns.Smooth:Disconnect() conns.Smooth = nil end
    end
end

local function setParticles(on)
    if on then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") then
                original_particle_states[obj] = obj.Enabled
                obj.Enabled = false
            end
        end
        if not conns.Particles then
            conns.Particles = Workspace.DescendantAdded:Connect(function(obj)
                if obj:IsA("ParticleEmitter") or obj:IsA("Trail") then
                    original_particle_states[obj] = obj.Enabled
                    obj.Enabled = false
                end
            end)
        end
    else
        for obj, state in pairs(original_particle_states) do
            if obj and obj.Parent then
                pcall(function() obj.Enabled = state end)
            end
        end
        original_particle_states = {}
        if conns.Particles then conns.Particles:Disconnect() conns.Particles = nil end
    end
end

local function setTextures(on)
    if on then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("Decal") or obj:IsA("Texture") then
                if original_textures[obj] == nil then
                    original_textures[obj] = obj.Texture
                end
                obj.Texture = ""
            end
        end
        if not conns.Textures then
            conns.Textures = Workspace.DescendantAdded:Connect(function(obj)
                if obj:IsA("Decal") or obj:IsA("Texture") then
                    if original_textures[obj] == nil then
                        original_textures[obj] = obj.Texture
                    end
                    obj.Texture = ""
                end
            end)
        end
    else
        for obj, tex in pairs(original_textures) do
            if obj and obj.Parent then
                pcall(function() obj.Texture = tex end)
            end
        end
        original_textures = {}
        if conns.Textures then conns.Textures:Disconnect() conns.Textures = nil end
    end
end

local function setShadows(on)
    Lighting.GlobalShadows = not on
end

local function setGraySky(on)
    if on then
        for _, obj in ipairs(Lighting:GetChildren()) do
            obj:Destroy()
        end
        local sky = Instance.new("Sky")
        local assetId = "rbxassetid://99742693890881"
        sky.SkyboxBk = assetId
        sky.SkyboxDn = assetId
        sky.SkyboxFt = assetId
        sky.SkyboxLf = assetId
        sky.SkyboxRt = assetId
        sky.SkyboxUp = assetId
        sky.Parent = Lighting
    else
        for _, obj in ipairs(Lighting:GetChildren()) do
            if obj:IsA("Sky") then
                obj:Destroy()
            end
        end
    end
end

-- =============================
-- UI CONTROLS
-- =============================
if perf_tab then
    perf_tab:AddToggle("No Textures (SmoothPlastic)", setSmoothPlastic)
    perf_tab:AddToggle("Disable Shadows", setShadows)
    perf_tab:AddToggle("Disable Particles/Trails", setParticles)
    perf_tab:AddToggle("Hide Meshes (world only)", setMeshes)
    perf_tab:AddToggle("Remove Textures/Decals", setTextures)
    perf_tab:AddToggle("Remove Accessories", setAccessories)
    perf_tab:AddToggle("Gray Skybox", setGraySky)
    perf_tab:AddButton("Remove Weapon Displays", function()
        local wd = Workspace:FindFirstChild("WeaponDisplays")
        if wd then wd:Destroy() end
    end)
end
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
-- =============================
-- SERVICES
-- =============================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- =============================
-- TRICKSHOT & MOVEMENT TAB
-- =============================
local trickTab = odh_shared_plugins.AddSection("Trickshot & Movement")

-- =============================
-- SETTINGS
-- =============================
local trickshotEnabled = false -- 360 spin
local strafeEnabled = false
local strafeSpeed = 16
local spinSpeed = math.rad(15) -- radians per frame
local spinning = false
local strafeDirection = 1 -- 1 = right, -1 = left

-- =============================
-- JUMP BOOST SETTINGS
-- =============================
local jumpBoostEnabled = false
local jumpBoostSize = 50
local jump360Enabled = false
local jump360Size = 100
local screenGuiJump, screenGui360
local buttonJump, button360
local humanoid
local boosted = false
local originalJumpPower = 50
local spinOnNextJump = false

-- =============================
-- HUMANOID SETUP
-- =============================
local function setupHumanoid(h)
    humanoid = h
    originalJumpPower = humanoid.JumpPower
    boosted = false

    humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
        if boosted and humanoid.Jump then
            task.wait(0.1)
            humanoid.JumpPower = originalJumpPower
            boosted = false
        end
        if jump360Enabled and spinOnNextJump and humanoid.Jump then
            local HRP = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if HRP then
                local totalSpin = math.rad(360)
                local steps = 30
                local stepAngle = totalSpin / steps
                local stepTime = 0.01
                for i = 1, steps do
                    HRP.CFrame = HRP.CFrame * CFrame.Angles(0, stepAngle * (spinSpeed / math.rad(15)), 0)
                    task.wait(stepTime)
                end
                spinOnNextJump = false
            end
        end
    end)
end

local function onCharacterAdded(char)
    local hum = char:WaitForChild("Humanoid")
    setupHumanoid(hum)
end

if LocalPlayer.Character then
    onCharacterAdded(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

-- =============================
-- JUMP BOOST BUTTON
-- =============================
local function setupJumpButton()
    if screenGuiJump then screenGuiJump:Destroy() end
    screenGuiJump = Instance.new("ScreenGui", LocalPlayer:WaitForChild("PlayerGui"))
    screenGuiJump.ResetOnSpawn = false

    buttonJump = Instance.new("TextButton")
    buttonJump.Size = UDim2.new(0, jumpBoostSize, 0, jumpBoostSize)
    buttonJump.Position = UDim2.new(0.5, -jumpBoostSize/2, 0.5, -jumpBoostSize/2)
    buttonJump.Text = "Jump Boost"
    buttonJump.BackgroundColor3 = Color3.new(0, 0, 0)
    buttonJump.TextColor3 = Color3.new(1, 1, 1)
    buttonJump.Font = Enum.Font.Arcade
    buttonJump.TextSize = 18
    buttonJump.Active = true
    buttonJump.Draggable = true
    buttonJump.Parent = screenGuiJump

    buttonJump.MouseButton1Click:Connect(function()
        if humanoid and not boosted then
            originalJumpPower = humanoid.JumpPower
            humanoid.JumpPower = 125
            boosted = true
        end
    end)
end

-- =============================
-- 360 Jump Button
-- =============================
local function setup360Button()
    if screenGui360 then screenGui360:Destroy() end
    screenGui360 = Instance.new("ScreenGui", LocalPlayer:WaitForChild("PlayerGui"))
    screenGui360.ResetOnSpawn = false

    button360 = Instance.new("TextButton")
    button360.Size = UDim2.new(0, jump360Size, 0, jump360Size)
    button360.Position = UDim2.new(0.5, -jump360Size/2, 0.5, -jump360Size/2)
    button360.Text = "360 Jump"
    button360.BackgroundColor3 = Color3.new(0, 0, 0)
    button360.TextColor3 = Color3.new(1, 1, 1)
    button360.Font = Enum.Font.Arcade
    button360.TextSize = 18
    button360.Active = true
    button360.Draggable = true
    button360.Parent = screenGui360

    button360.MouseButton1Click:Connect(function()
        spinOnNextJump = true -- will spin on next jump only
    end)
end

-- =============================
-- PLUGIN TOGGLES & SLIDERS
-- =============================
trickTab:AddToggle("Enable Automatic 360 Trickshot", function(on)
    trickshotEnabled = on
end)

trickTab:AddToggle("Enable Automatic Strafe", function(on)
    strafeEnabled = on
end)

trickTab:AddSlider("Strafe Speed", 4, 32, strafeSpeed, function(v)
    strafeSpeed = v
end)

trickTab:AddSlider("360 Spin Speed", 1, 50, math.deg(spinSpeed), function(v)
    spinSpeed = math.rad(v)
end)

trickTab:AddToggle("Enable Jump Boost Button", function(on)
    jumpBoostEnabled = on
    if on then
        setupJumpButton()
    elseif screenGuiJump then
        screenGuiJump:Destroy()
        screenGuiJump = nil
    end
end)

trickTab:AddSlider("Jump Boost Button Size", 20, 150, jumpBoostSize, function(v)
    jumpBoostSize = v
    if buttonJump then
        buttonJump.Size = UDim2.new(0, jumpBoostSize, 0, jumpBoostSize)
        buttonJump.Position = UDim2.new(0.5, -jumpBoostSize/2, 0.5, -jumpBoostSize/2)
    end
end)

trickTab:AddToggle("Enable 360 Jump Button", function(on)
    jump360Enabled = on
    if on then
        setup360Button()
    elseif screenGui360 then
        screenGui360:Destroy()
        screenGui360 = nil
    end
end)

trickTab:AddSlider("360 Jump Button Size", 50, 200, jump360Size, function(v)
    jump360Size = v
    if button360 then
        button360.Size = UDim2.new(0, jump360Size, 0, jump360Size)
        button360.Position = UDim2.new(0.5, -jump360Size/2, 0.5, -jump360Size/2)
    end
end)

-- =============================
-- APPLY MOVEMENTS
-- =============================
RunService.RenderStepped:Connect(function(delta)
    local char = LocalPlayer.Character
    if not char then return end
    local HRP = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not HRP or not humanoid then return end

    -- Automatic strafe
    if strafeEnabled then
        local moveVec = HRP.CFrame.RightVector * strafeDirection
        HRP.CFrame = HRP.CFrame + moveVec.Unit * strafeSpeed * delta
        if tick() % 1 < 0.5 then
            strafeDirection = 1
        else
            strafeDirection = -1
        end
    end

    -- Automatic 360 trickshot
    if trickshotEnabled then
        if humanoid:GetState() == Enum.HumanoidStateType.Freefall then
            spinning = true
        elseif spinning and humanoid:GetState() == Enum.HumanoidStateType.Landed then
            spinning = false
        end

        if spinning then
            HRP.CFrame = HRP.CFrame * CFrame.Angles(0, spinSpeed, 0)
        end
    end
end)

-- =============================
-- WALLHOP FEATURE
-- =============================
local wallhopEnabled = false
local InfiniteJumpEnabled = true
local wallRaycastParams = RaycastParams.new()
wallRaycastParams.FilterType = Enum.RaycastFilterType.Blacklist

local function getWallRaycastResult()
    local character = LocalPlayer.Character
    if not character then return nil end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    wallRaycastParams.FilterDescendantsInstances = {character}
    local closestHit, minDistance = nil, 3
    local hrpCF = hrp.CFrame
    for i = 0,7 do
        local angle = math.rad(i*45)
        local dir = (hrpCF*CFrame.Angles(0,angle,0)).LookVector
        local ray = Workspace:Raycast(hrp.Position, dir*2, wallRaycastParams)
        if ray and ray.Instance and ray.Distance < minDistance then
            minDistance = ray.Distance
            closestHit = ray
        end
    end
    return closestHit
end

local function performWallhop()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not (humanoid and rootPart and humanoid:GetState() ~= Enum.HumanoidStateType.Dead) then return end
    local wall = getWallRaycastResult()
    if not wall then return end

    rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + wall.Normal)
    RunService.Heartbeat:Wait()
    if humanoid:GetState() ~= Enum.HumanoidStateType.Dead then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        task.wait(0.1)
    end
end

trickTab:AddToggle("Enable Wallhop", function(on)
    wallhopEnabled = on
end)

trickTab:AddKeybind("Wallhop Jump Key", "J", performWallhop)

UserInputService.JumpRequest:Connect(function()
    if wallhopEnabled and InfiniteJumpEnabled then
        performWallhop()
    end

end)

trickTab:AddLabel('Credits To: <font color="rgb(255,0,255)">not_.gato (@HeyyCaf) - Owner of the feature</font>')

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local LocalPlayer = Players.LocalPlayer

-- =============================
-- SETTINGS
-- =============================
local overlayEnabled = false
local overlayScale = 50
local activeStats = {}
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local LocalPlayer = Players.LocalPlayer
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local LocalPlayer = Players.LocalPlayer

-- Use your shared plugin object directly
local overlayTab = odh_shared_plugins.AddSection("Overlay") -- Create the Overlay tab

-- =============================
-- SETTINGS
-- =============================
local overlayEnabled = false
local overlayScale = 50
local activeStats = {}

-- =============================
-- CREATE OVERLAY
-- =============================
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PerformanceOverlay"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Position = UDim2.new(0, 10, 0, 10)
mainFrame.BackgroundTransparency = 0.3
mainFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Visible = overlayEnabled
mainFrame.Parent = screenGui

-- Labels
local labels = {}
local function createLabel(name)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,0,0,20)
    lbl.BackgroundTransparency = 1
    lbl.TextScaled = true
    lbl.Font = Enum.Font.SourceSansBold
    lbl.TextColor3 = Color3.fromRGB(255,255,255)
    lbl.Text = name
    lbl.Visible = false
    lbl.Parent = mainFrame
    labels[name] = lbl
    return lbl
end

local fpsLabel = createLabel("FPS: 0")
local pingLabel = createLabel("Ping: 0 ms")
local playersLabel = createLabel("Players: 0")

local function updateOverlayLayout()
    local scale = overlayScale / 50 -- smooth scaling factor
    local yOffset = 0
    for _, lbl in ipairs(activeStats) do
        lbl.Position = UDim2.new(0,0,0,yOffset)
        lbl.Size = UDim2.new(1,0,0,20*scale)
        lbl.Visible = true
        yOffset = yOffset + 20*scale
    end
    mainFrame.Size = UDim2.new(0, 120*scale, 0, yOffset)
end

-- =============================
-- TOGGLES
-- =============================
overlayTab:AddToggle("Enable Overlay", function(on)
    overlayEnabled = on
    mainFrame.Visible = overlayEnabled
    updateOverlayLayout()
end)

local function toggleStat(labelObj, on)
    if on then
        table.insert(activeStats, labelObj)
    else
        for i,v in ipairs(activeStats) do
            if v == labelObj then table.remove(activeStats,i) break end
        end
        labelObj.Visible = false
    end
    updateOverlayLayout()
end

overlayTab:AddToggle("Show FPS", function(on) toggleStat(fpsLabel, on) end)
overlayTab:AddToggle("Show Ping", function(on) toggleStat(pingLabel, on) end)
overlayTab:AddToggle("Show Players in Server", function(on) toggleStat(playersLabel, on) end)

overlayTab:AddSlider("Overlay Scale", 1, 100, overlayScale, function(v)
    overlayScale = v
    updateOverlayLayout()
end)

-- =============================
-- UPDATE LOOP
-- =============================
local lastUpdate = tick()
local frameCount = 0

RunService.RenderStepped:Connect(function(delta)
    if not overlayEnabled then return end

    local now = tick()
    frameCount += 1
    if now - lastUpdate >= 1 then
        local fps = math.floor(frameCount / (now - lastUpdate))
        fpsLabel.Text = "FPS: "..fps
        if fps <= 30 then fpsLabel.TextColor3 = Color3.fromRGB(255,0,0)
        elseif fps <= 45 then fpsLabel.TextColor3 = Color3.fromRGB(255,165,0)
        else fpsLabel.TextColor3 = Color3.fromRGB(0,255,0) end

        frameCount = 0
        lastUpdate = now
    end

    -- Ping
    local pingVal = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    local ping = math.floor(pingVal)
    pingLabel.Text = "Ping: "..ping.." ms"
    if ping <= 170 then pingLabel.TextColor3 = Color3.fromRGB(0,255,0)
    elseif ping <= 200 then pingLabel.TextColor3 = Color3.fromRGB(255,165,0)
    else pingLabel.TextColor3 = Color3.fromRGB(255,0,0) end

    -- Players
    local playerCount = #Players:GetPlayers()
    playersLabel.Text = "Players: "..playerCount
    if playerCount >= 9 then
        playersLabel.TextColor3 = Color3.fromRGB(0,255,0)
    elseif playerCount >= 6 then
        playersLabel.TextColor3 = Color3.fromRGB(255,165,0)
    else
        playersLabel.TextColor3 = Color3.fromRGB(255,0,0) 
    end
end)

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- =====================================
-- PLUGIN TAB
-- =====================================
local pluginTab = odh_shared_plugins.AddSection("Troll (FE)")

-- =====================================
-- GUI SETUP
-- =====================================
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local function createKnifeGui(name, imageId)
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = name .. "GUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui
    screenGui.Enabled = false -- hidden until toggle

    local buttonSize = 100

    local imageButton = Instance.new("ImageButton")
    imageButton.Size = UDim2.new(0, buttonSize, 0, buttonSize)
    imageButton.Position = UDim2.new(0.5, -buttonSize/2, 0.5, -buttonSize/2)
    imageButton.Image = imageId
    imageButton.BackgroundTransparency = 0.8
    imageButton.Active = true
    imageButton.Draggable = true
    imageButton.Parent = screenGui

    return screenGui, imageButton
end

-- =====================================
-- ANIMATION FUNCTIONS
-- =====================================
local function playFakeKnifeAnimation(char)
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local knife = char:FindFirstChild("Knife")
    if knife then
        local animFolder = knife:FindFirstChild("Animations")
        if animFolder then
            local slash = animFolder:FindFirstChild("Slash")
            local down = animFolder:FindFirstChild("Down")

            if slash and slash:IsA("Animation") then
                local track = humanoid:LoadAnimation(slash)
                track:Play()
                if down and down:IsA("Animation") then
                    task.delay(1, function()
                        local downTrack = humanoid:LoadAnimation(down)
                        downTrack:Play()
                    end)
                end
            end
        end
    end
end

local function playDualKnifeAnimation(char)
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        local anim1 = Instance.new("Animation")
        anim1.AnimationId = "rbxassetid://2467577524" -- slash
        local track1 = humanoid:LoadAnimation(anim1)
        track1:Play()

        task.delay(1, function()
            local anim2 = Instance.new("Animation")
            anim2.AnimationId = "rbxassetid://2470501967" -- dual
            local track2 = humanoid:LoadAnimation(anim2)
            track2:Play()
        end)
    end
end

-- =====================================
-- FAKE KNIFE
-- =====================================
local fakeKnifeGui, fakeKnifeButton = createKnifeGui("FakeKnife", "rbxassetid://121774155770924")

pluginTab:AddToggle("Fake Knife", function(on)
    fakeKnifeGui.Enabled = on
end)
pluginTab:AddLabel("The murderer needs to hold the knife")

pluginTab:AddSlider("Fake Knife Size", 50, 200, 100, function(v)
    fakeKnifeButton.Size = UDim2.new(0, v, 0, v)
    fakeKnifeButton.Position = UDim2.new(0.5, -v/2, 0.5, -v/2)
end)

fakeKnifeButton.MouseButton1Click:Connect(function()
    playFakeKnifeAnimation(LocalPlayer.Character)
end)
fakeKnifeButton.TouchTap:Connect(function()
    playFakeKnifeAnimation(LocalPlayer.Character)
end)

-- =====================================
-- FAKE DUAL KNIFE
-- =====================================
local fakeDualGui, fakeDualButton = createKnifeGui("FakeDualKnife", "rbxassetid://131282777381667")

pluginTab:AddToggle("Fake Dual Slash", function(on)
    fakeDualGui.Enabled = on
end)
pluginTab:AddLabel("Works always... even in the lobby 😈")

pluginTab:AddSlider("Fake Dual Slash Size", 50, 200, 100, function(v)
    fakeDualButton.Size = UDim2.new(0, v, 0, v)
    fakeDualButton.Position = UDim2.new(0.5, -v/2, 0.5, -v/2)
end)

fakeDualButton.MouseButton1Click:Connect(function()
    playDualKnifeAnimation(LocalPlayer.Character)
end)
fakeDualButton.TouchTap:Connect(function()
    playDualKnifeAnimation(LocalPlayer.Character)
end)

-- local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Lighting = game:GetService("Lighting")
local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")

local odh_shared_plugins = odh_shared_plugins -- make sure your shared plugin object exists

local shared = odh_shared_plugins
local section = shared.AddSection("Theme Changer")

-- Predefined color options
local colorOptions = {
    Black = Color3.fromRGB(0,0,0),
    White = Color3.fromRGB(255,255,255),
    Red = Color3.fromRGB(255,0,0),
    Green = Color3.fromRGB(0,255,0),
    Blue = Color3.fromRGB(0,0,255),
    Yellow = Color3.fromRGB(255,255,0),
    Magenta = Color3.fromRGB(255,0,255),
    Purple = Color3.fromRGB(128,0,128),
    Pink = Color3.fromRGB(255,105,180),
    Orange = Color3.fromRGB(255,165,0),
    Cyan = Color3.fromRGB(0,255,255),
    Gold = Color3.fromRGB(255,215,0),
    Ocean = Color3.fromRGB(0,128,200)
}

local primaryColor = nil
local secondaryColor = nil
local originalColors = {} -- store original GUI colors

-- Dropdown lists
local colorNames = {}
for name,_ in pairs(colorOptions) do
    table.insert(colorNames, name)
end
table.sort(colorNames)

-- Pickers
section:AddDropdown("Choose Primary Color", colorNames, function(selected)
    primaryColor = colorOptions[selected]
end)

section:AddDropdown("Choose Secondary Color", colorNames, function(selected)
    secondaryColor = colorOptions[selected]
end)

-- Apply Theme Button
section:AddButton("Apply Theme", function()
    if not primaryColor and not secondaryColor then
        shared.Notify("Please select a primary or secondary color first.", 3)
        return
    end

    pcall(function()
        local gui = gethui and gethui()
        if gui then
            for _,element in ipairs(gui:GetDescendants()) do
                if element:IsA("GuiObject") then
                    if not originalColors[element] then
                        originalColors[element] = {
                            Background = element.BackgroundColor3,
                            Border = element.BorderColor3
                        }
                    end
                    if primaryColor then
                        element.BackgroundColor3 = primaryColor
                    end
                    if secondaryColor then
                        element.BorderColor3 = secondaryColor
                    end
                end
                if element:IsA("UIGradient") and primaryColor then
                    element.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, primaryColor),
                        ColorSequenceKeypoint.new(1, secondaryColor or primaryColor)
                    })
                end
            end
        end
    end)

    shared.Notify("Theme Applied!", 1)
end)

-- Reset Theme Button
section:AddButton("Reset Theme", function()
    pcall(function()
        for element, props in pairs(originalColors) do
            if element then
                if props.Background then element.BackgroundColor3 = props.Background end
                if props.Border then element.BorderColor3 = props.Border end
            end
        end
    end)
    shared.Notify("Theme Reset to Original", 1)
end)






-- Store original sky if it exists
local Lighting = game:GetService("Lighting")
local originalSkyProps = nil
local originalSky = Lighting:FindFirstChildOfClass("Sky")
if originalSky then
    originalSkyProps = {
        SkyboxBk = originalSky.SkyboxBk,
        SkyboxDn = originalSky.SkyboxDn,
        SkyboxFt = originalSky.SkyboxFt,
        SkyboxLf = originalSky.SkyboxLf,
        SkyboxRt = originalSky.SkyboxRt,
        SkyboxUp = originalSky.SkyboxUp,
        MoonTextureId = originalSky.MoonTextureId,
        SunTextureId = originalSky.SunTextureId,
        StarCount = originalSky.StarCount
    }
end
-- Part 2: Skybox Changer (First Half)
local skySection = shared.AddSection("Sky Changer")

-- Sky presets
local skyboxPresets = {
    ["Minecraft Sky"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky")
        sky.SkyboxBk = "rbxassetid://8735166756"
        sky.SkyboxDn = "rbxassetid://8735166707"
        sky.SkyboxFt = "rbxassetid://8735231668"
        sky.SkyboxLf = "rbxassetid://8735166755"
        sky.SkyboxRt = "rbxassetid://8735166751"
        sky.SkyboxUp = "rbxassetid://8735166729"
        sky.SunTextureId = "rbxassetid://8735166708"
        sky.MoonTextureId = "rbxassetid://8735166687"
        sky.Parent = Lighting
        Lighting.Ambient = Color3.fromRGB(2, 125, 157)
        Lighting.Brightness = 3.133
        Lighting.OutdoorAmbient = Color3.fromRGB(9, 111, 157)
    end,

    ["Realistic Sky"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky")
        sky.Name = "RealisticSky"
        sky.SkyboxBk = "rbxassetid://144933338"
        sky.SkyboxDn = "rbxassetid://144931530"
        sky.SkyboxFt = "rbxassetid://144933262"
        sky.SkyboxLf = "rbxassetid://144933244"
        sky.SkyboxRt = "rbxassetid://144933299"
        sky.SkyboxUp = "rbxassetid://144931564"
        sky.Parent = Lighting
        Lighting.Ambient = Color3.fromRGB(110, 157, 152)
        Lighting.Brightness = 3.133
        Lighting.OutdoorAmbient = Color3.fromRGB(117, 157, 151)
    end,

    ["Purple Nighty Sky #1"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky")
        sky.Name = "NebulaSky"
        sky.SkyboxBk = "rbxassetid://159454299"
        sky.SkyboxDn = "rbxassetid://159454296"
        sky.SkyboxFt = "rbxassetid://159454293"
        sky.SkyboxLf = "rbxassetid://159454286"
        sky.SkyboxRt = "rbxassetid://159454300"
        sky.SkyboxUp = "rbxassetid://159454288"
        sky.SunTextureId = ""
        sky.MoonTextureId = ""
        sky.Parent = Lighting
        Lighting.Ambient = Color3.fromRGB(87, 6, 105)
        Lighting.Brightness = -9
        Lighting.OutdoorAmbient = Color3.fromRGB(69, 0, 157)
    end,

    ["Purple Nighty Sky #2"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky")
        sky.SkyboxBk = "rbxassetid://14543264135"
        sky.SkyboxDn = "rbxassetid://14543358958"
        sky.SkyboxFt = "rbxassetid://14543257810"
        sky.SkyboxLf = "rbxassetid://14543275895"
        sky.SkyboxRt = "rbxassetid://14543280890"
        sky.SkyboxUp = "rbxassetid://14543371676"
        sky.SunTextureId = ""
        sky.MoonTextureId = ""
        sky.Parent = Lighting
        Lighting.Ambient = Color3.fromRGB(124, 1, 205)
        Lighting.Brightness = 0.23
        Lighting.OutdoorAmbient = Color3.fromRGB(95, 0, 182)
    end,

    ["Sunset"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky")
        sky.SkyboxBk = "rbxassetid://15502525195"
        sky.SkyboxDn = "rbxassetid://15502522797"
        sky.SkyboxFt = "rbxassetid://15502524520"
        sky.SkyboxLf = "rbxassetid://15502522129"
        sky.SkyboxRt = "rbxassetid://15502523711"
        sky.SkyboxUp = "rbxassetid://15502526102"
        sky.Parent = Lighting
        Lighting.Ambient = Color3.fromRGB(233, 191, 12)
        Lighting.Brightness = 1.7
        Lighting.OutdoorAmbient = Color3.fromRGB(210, 104, 0)
    end,

["Nighty Sky"] = function()
        for _, obj in pairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky"); sky.Name = "CustomSky"
        sky.SkyboxBk = "rbxassetid://168387023"
        sky.SkyboxDn = "rbxassetid://168387089"
        sky.SkyboxFt = "rbxassetid://168387054"
        sky.SkyboxLf = "rbxassetid://168534432"
        sky.SkyboxRt = "rbxassetid://168387190"
        sky.SkyboxUp = "rbxassetid://168387135"
        sky.Parent = Lighting
        Lighting.Ambient = Color3.new(0,0,0)
        Lighting.Brightness = 0.3
        Lighting.ClockTime = 14.5
        Lighting.ColorShift_Bottom = Color3.new(0,0,0)
        Lighting.ColorShift_Top = Color3.new(0,0,0)
        Lighting.OutdoorAmbient = Color3.new(0,0,0)
        Lighting.ShadowColor = Color3.new(0,0,0)
        Lighting.ShadowSoftness = 0.2
        Lighting.TimeOfDay = "14:30:00"
        Lighting.Technology = Enum.Technology.Future
    end,

    ["Sunset Sky"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky")
        sky.SkyboxBk = "rbxassetid://458016711"
        sky.SkyboxDn = "rbxassetid://458016826"
        sky.SkyboxFt = "rbxassetid://458016532"
        sky.SkyboxLf = "rbxassetid://458016655"
        sky.SkyboxRt = "rbxassetid://458016782"
        sky.SkyboxUp = "rbxassetid://458016792"
        sky.Parent = Lighting
        Lighting.Ambient = Color3.fromRGB(255,114,0)
        Lighting.Brightness = 2
        Lighting.ClockTime = 14.5
        Lighting.OutdoorAmbient = Color3.fromRGB(246,105,53)
        Lighting.ShadowColor = Color3.fromRGB(160,105,45)
        Lighting.ShadowSoftness = 0.2
    end,

    ["Night Fog"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky")
        sky.SkyboxBk = "rbxassetid://1370717244"
        sky.SkyboxDn = "rbxassetid://1370717336"
        sky.SkyboxFt = "rbxassetid://1370717438"
        sky.SkyboxLf = "rbxassetid://1370717567"
        sky.SkyboxRt = "rbxassetid://1370717698"
        sky.SkyboxUp = "rbxassetid://1370717782"
        sky.Parent = Lighting
        Lighting.Ambient = Color3.fromRGB(19,47,98)
        Lighting.Brightness = 0.2
        Lighting.ClockTime = 14.5
        Lighting.OutdoorAmbient = Color3.fromRGB(17,82,115)
        Lighting.ShadowColor = Color3.fromRGB(2,16,51)
        Lighting.ShadowSoftness = 0.2
    end,

    ["Blood Moon"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky")
        sky.SkyboxBk = "rbxassetid://401664839"
        sky.SkyboxDn = "rbxassetid://401664862"
        sky.SkyboxFt = "rbxassetid://401664960"
        sky.SkyboxLf = "rbxassetid://401664881"
        sky.SkyboxRt = "rbxassetid://401664901"
        sky.SkyboxUp = "rbxassetid://401664936"
        sky.Parent = Lighting
        Lighting.Ambient = Color3.fromRGB(207,71,6)
        Lighting.Brightness = 1
        Lighting.OutdoorAmbient = Color3.fromRGB(187,2,2)
        Lighting.ShadowColor = Color3.fromRGB(82,0,0)
        Lighting.ShadowSoftness = 0.2
    end,

    ["Spongebob Sky"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky")
        sky.SkyboxBk = "rbxassetid://15962101128"
        sky.SkyboxDn = "rbxassetid://15970246218"
        sky.SkyboxFt = "rbxassetid://15962101128"
        sky.SkyboxLf = "rbxassetid://15962101128"
        sky.SkyboxRt = "rbxassetid://15962101128"
        sky.SkyboxUp = "rbxassetid://15962901054"
        sky.Parent = Lighting
        Lighting.Ambient = Color3.fromRGB(19,171,207)
        Lighting.Brightness = 2
        Lighting.OutdoorAmbient = Color3.fromRGB(11,188,178)
        Lighting.ShadowColor = Color3.fromRGB(5,82,72)
    end,

    ["Pink Blossom"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky")
        sky.SkyboxBk = "rbxassetid://271042516"
        sky.SkyboxDn = "rbxassetid://271077243"
        sky.SkyboxFt = "rbxassetid://271042556"
        sky.SkyboxLf = "rbxassetid://271042310"
        sky.SkyboxRt = "rbxassetid://271042467"
        sky.SkyboxUp = "rbxassetid://271077958"
        sky.Parent = Lighting
        Lighting.Ambient = Color3.fromRGB(222,186,255)
        Lighting.Brightness = 3.135
        Lighting.OutdoorAmbient = Color3.fromRGB(231,216,255)
        Lighting.ShadowColor = Color3.fromRGB(163,137,184)
    end,

    ["Purple Sunset"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky")
        sky.SkyboxBk = "rbxassetid://264908339"
        sky.SkyboxDn = "rbxassetid://264907909"
        sky.SkyboxFt = "rbxassetid://264909420"
        sky.SkyboxLf = "rbxassetid://264909758"
        sky.SkyboxRt = "rbxassetid://264908886"
        sky.SkyboxUp = "rbxassetid://264907379"
        sky.Parent = Lighting
        Lighting.Ambient = Color3.fromRGB(63,21,176)
        Lighting.Brightness = 1
        Lighting.ClockTime = 14.5
        Lighting.OutdoorAmbient = Color3.fromRGB(57,29,125)
        Lighting.ShadowColor = Color3.fromRGB(14,4,39)
        Lighting.ShadowSoftness = 0.2
    end,

    ["Half-Life 2 Sky"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky")
        sky.SkyboxBk = "rbxassetid://9000922368"
        sky.SkyboxDn = "rbxassetid://9000922033"
        sky.SkyboxFt = "rbxassetid://9000921543"
        sky.SkyboxLf = "rbxassetid://9000920853"
        sky.SkyboxRt = "rbxassetid://9000920563"
        sky.SkyboxUp = "rbxassetid://9000920353"
        sky.Parent = Lighting
        Lighting.Ambient = Color3.fromRGB(169,177,133)
        Lighting.Brightness = 1.299
        Lighting.OutdoorAmbient = Color3.fromRGB(116,126,98)
        Lighting.ShadowColor = Color3.fromRGB(37,40,29)
    end,

    ["Void Sky"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky")
        sky.SkyboxBk = "rbxassetid://16262356578"
        sky.SkyboxDn = "rbxassetid://16262358026"
        sky.SkyboxFt = "rbxassetid://16262360469"
        sky.SkyboxLf = "rbxassetid://16262362003"
        sky.SkyboxRt = "rbxassetid://16262363873"
        sky.SkyboxUp = "rbxassetid://16262366016"
        sky.Parent = Lighting
        Lighting.Ambient = Color3.fromRGB(99,12,177)
        Lighting.Brightness = 1.7
        Lighting.ClockTime = 14.5
        Lighting.OutdoorAmbient = Color3.fromRGB(83,49,139)
        Lighting.ShadowColor = Color3.fromRGB(48,18,73)
    end,

    ["Purple Night"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky")
        sky.SkyboxBk = "rbxassetid://5084575798"
        sky.SkyboxDn = "rbxassetid://5084575916"
        sky.SkyboxFt = "rbxassetid://5103949679"
        sky.SkyboxLf = "rbxassetid://5103948542"
        sky.SkyboxRt = "rbxassetid://5103948784"
        sky.SkyboxUp = "rbxassetid://5084576400"
        sky.Parent = Lighting
        Lighting.Ambient = Color3.fromRGB(99,12,177)
        Lighting.Brightness = 1.7
        Lighting.ClockTime = 14.5
        Lighting.OutdoorAmbient = Color3.fromRGB(83,49,139)
        Lighting.ShadowColor = Color3.fromRGB(48,18,73)
    end,

    ["Pink Sky"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky")
        sky.SkyboxBk = "rbxassetid://271042516"
        sky.SkyboxDn = "rbxassetid://271077243"
        sky.SkyboxFt = "rbxassetid://271042556"
        sky.SkyboxLf = "rbxassetid://271042310"
        sky.SkyboxRt = "rbxassetid://271042467"
        sky.SkyboxUp = "rbxassetid://271077958"
        sky.Parent = Lighting
        Lighting.Ambient = Color3.fromRGB(177,112,170)
        Lighting.Brightness = 1.7
        Lighting.OutdoorAmbient = Color3.fromRGB(135,102,140)
        Lighting.ShadowColor = Color3.fromRGB(73,1,68)
    end,

    ["Realistic Moon"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        local sky = Instance.new("Sky")
        sky.SkyboxBk = "rbxassetid://2670643994"
        sky.SkyboxDn = "rbxassetid://2670643365"
        sky.SkyboxFt = "rbxassetid://2670643214"
        sky.SkyboxLf = "rbxassetid://2670643070"
        sky.SkyboxRt = "rbxassetid://2670644173"
        sky.SkyboxUp = "rbxassetid://2670644331"
        sky.Parent = Lighting
        Lighting.Ambient = Color3.fromRGB(34,39,61)
        Lighting.Brightness = 0.5
        Lighting.OutdoorAmbient = Color3.fromRGB(73,76,100)
        Lighting.ShadowColor = Color3.fromRGB(32,33,43)
        Lighting.ShadowSoftness = 0.2
    end,
}

-- Dropdown for the first half
local skyKeys = {}
for k, _ in pairs(skyboxPresets) do table.insert(skyKeys, k) end
table.sort(skyKeys)

local selectedSkybox = skyKeys[1]

skySection:AddDropdown("Predefined Skyboxes", skyKeys, function(value)
    selectedSkybox = value
end)

skySection:AddButton("Apply Selected Skybox", function()
    if selectedSkybox and skyboxPresets[selectedSkybox] then
        skyboxPresets[selectedSkybox]()
        shared.Notify("Applied "..selectedSkybox, 1)
    else
        shared.Notify("No skybox selected or preset missing.", 3)
    end
end)

skySection:AddLabel('Credits To: <font color="rgb(255,0,255)">not_.gato (@HeyyCaf) - Owner of the feature</font>')

local shared = odh_shared_plugins
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local privacyTab = shared.AddSection("Privacy & Security")

-- =============================
-- BUTTON: Hide Username Once
-- =============================
privacyTab:AddButton("Hide My Username", function()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")

    local function updateGuiNames()
        for _, obj in ipairs(playerGui:GetDescendants()) do
            if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.Text:find(LocalPlayer.Name) then
                obj.Text = "Hidden"
            end
        end
    end

    updateGuiNames()

    -- Also catch future GUI elements
    playerGui.DescendantAdded:Connect(function(obj)
        if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.Text:find(LocalPlayer.Name) then
            task.defer(function()
                obj.Text = "Hidden"
            end)
        end
    end)

    shared.Notify("Your username is now hidden in GUIs", 2)
end)

-- =============================
-- TOGGLE: Hide Avatar Thumbnail
-- =============================
local hideThumbnail = false
privacyTab:AddToggle("Hide My Avatar", function(state)
    hideThumbnail = state

    local function updateThumbnails()
        local playerGui = LocalPlayer:WaitForChild("PlayerGui")
        for _, obj in ipairs(playerGui:GetDescendants()) do
            if (obj:IsA("ImageLabel") or obj:IsA("ImageButton")) and obj.Image:find(tostring(LocalPlayer.UserId)) then
                if hideThumbnail then
                    obj.Image = "rbxasset://textures/transparent.png"
                else
                    -- Restore to default Roblox headshot
                    local success, thumb = pcall(function()
                        return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
                    end)
                    if success then obj.Image = thumb end
                end
            end
        end

        -- Hook new GUI elements
        if hideThumbnail then
            if not playerGui:FindFirstChild("__HideThumbnailConnection") then
                local conn = Instance.new("BoolValue")
                conn.Name = "__HideThumbnailConnection"
                conn.Parent = playerGui
                playerGui.DescendantAdded:Connect(function(obj)
                    if (obj:IsA("ImageLabel") or obj:IsA("ImageButton")) and obj.Image:find(tostring(LocalPlayer.UserId)) then
                        task.defer(function()
                            obj.Image = "rbxasset://textures/transparent.png"
                        end)
                    end
                end)
            end
        end
    end

    updateThumbnails()
end)




local shared = odh_shared_plugins

-- Create a new section
local gunSoundSection = shared.AddSection("Gun Sound Changer")

-- Sound options (default first)
local sounds = {
    "Default|10209803",
    "Meow|7148585764",
    "Laser|8561500387",
    "Pew|2216910282",
    "BoomHeadshot|7551341361",
    "Bruh|6349641063",
    "Fart|8551016315",
    "تفل على لويز (3RQ)|78710014998615",
    "خودلك دي|76578568305727",
    "Zrigha|97655350152777",
    "Custom|0" -- Placeholder for textbox input
}

local selectedSoundId = "rbxassetid://10209803" -- default selected
local customEnabled = false
local customTextboxId = nil -- Store user input for custom ID
local lastSelected = "Default" -- Track dropdown selection
local connections = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Function to layer custom sound
local function layerSound(origSound)
    if not selectedSoundId then return end
    origSound.Volume = 0

    if connections[origSound] then
        connections[origSound]:Disconnect()
    end

    connections[origSound] = origSound.Played:Connect(function()
        local custom = Instance.new("Sound")
        custom.SoundId = selectedSoundId
        custom.Volume = 1
        custom.PlayOnRemove = true
        custom.Parent = origSound.Parent
        custom:Destroy()
    end)
end

-- Function to apply custom sound to all gunshots
local function applySounds()
    if not customEnabled then return end
    local containers = {LocalPlayer.Backpack, LocalPlayer.Character}
    for _, container in ipairs(containers) do
        if container then
            for _, obj in ipairs(container:GetDescendants()) do
                if obj:IsA("Sound") and obj.Name == "Gunshot" then
                    layerSound(obj)
                end
            end
        end
    end
end

-- Heartbeat loop to handle new guns
RunService.Heartbeat:Connect(function()
    if customEnabled then
        applySounds()
    end
end)

-- Toggle for enabling/disabling custom sounds
gunSoundSection:AddToggle("Enable Custom Sound", function(bool)
    customEnabled = bool
    if bool then
        applySounds()
    end
end)

-- TextBox for custom SoundId
gunSoundSection:AddTextBox("Custom SoundId", function(text)
    if text and text ~= "" then
        if not string.find(text, "rbxassetid://") then
            customTextboxId = "rbxassetid://" .. text
        else
            customTextboxId = text
        end
        -- If the last selected dropdown option is Custom, update immediately
        if lastSelected == "Custom" then
            selectedSoundId = customTextboxId
            applySounds()
        end
    end
end)

-- Dropdown to select the custom sound
local dropdownOptions = {}
for _, data in ipairs(sounds) do
    local name = string.match(data, "(.-)|%d+")
    table.insert(dropdownOptions, name)
end

local dropdown = gunSoundSection:AddDropdown("Select Sound", dropdownOptions, function(selected)
    lastSelected = selected -- track selection
    if selected == "Custom" then
        selectedSoundId = customTextboxId -- may be nil until user types
    else
        for _, data in ipairs(sounds) do
            local name, id = string.match(data, "(.-)|(%d+)")
            if name == selected then
                selectedSoundId = "rbxassetid://" .. id
                break
            end
        end
    end
    applySounds() -- Apply immediately when changed
end)

-- Set initial dropdown selection to Default
dropdown.Select("Default")



local shared = odh_shared_plugins

-- Plugin Section
local speedSection = shared.AddSection("Legit speedglitch")

local LocalPlayer = game:GetService("Players").LocalPlayer
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Variables
local sideSpeed = 150
local buttonSize = 50
local emoteEnabled = false
local selectedEmoteId = nil
local customEmoteEnabled = false
local emoteButton
local moveInput = 0
local isJumping = false

local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local HRP = Character:WaitForChild("HumanoidRootPart")
local Camera = Workspace.CurrentCamera

-- Predefined emotes
local emotes = {
    ["Moonwalk"] = "79127989560307",
    ["Yungblud - Happier Jump"] = "15610015346",
    ["Baby Queen - Bouncy Twirl"] = "14353423348",
    ["Flex Walk"] = "15506506103"
}

-- ======= Character & Jump Handling =======
local function setupCharacter(char)
    Character = char
    Humanoid = Character:WaitForChild("Humanoid")
    HRP = Character:WaitForChild("HumanoidRootPart")
    isJumping = false

    Humanoid.Jumping:Connect(function() isJumping = true end)
    Humanoid.StateChanged:Connect(function(_, state)
        if state == Enum.HumanoidStateType.Landed then
            isJumping = false
        end
    end)
end
setupCharacter(Character)
LocalPlayer.CharacterAdded:Connect(setupCharacter)

-- ======= Keyboard input =======
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.A then moveInput = -1
    elseif input.KeyCode == Enum.KeyCode.D then moveInput = 1
    end
end)
UserInputService.InputEnded:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.D then moveInput = 0
    end
end)

-- ======= Play Emote =======
local function playEmote(assetId)
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local success, err = pcall(function()
        humanoid:PlayEmoteAndGetAnimTrackById(assetId)
    end)
    if not success then
        local anim = Instance.new("Animation")
        anim.AnimationId = "rbxassetid://"..assetId
        humanoid:LoadAnimation(anim):Play()
    end
end

-- ======= Create Emote Button =======
local function createEmoteButton()
    if emoteButton then return end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "SpeedGlitchGUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    emoteButton = Instance.new("TextButton")
    emoteButton.Size = UDim2.new(0, buttonSize, 0, buttonSize)
    emoteButton.Position = UDim2.new(0, 50, 0, 200)
    emoteButton.BackgroundColor3 = Color3.fromRGB(100, 40, 40)
    emoteButton.Text = "Speed Glitch"
    emoteButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    emoteButton.TextScaled = true
    emoteButton.AutoButtonColor = false
    emoteButton.Parent = screenGui

    -- Draggable
    local dragging, dragInput, mousePos, framePos = false
    emoteButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            mousePos = input.Position
            framePos = emoteButton.Position
        end
    end)
    emoteButton.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - mousePos
            emoteButton.Position = UDim2.new(0, framePos.X.Offset + delta.X, 0, framePos.Y.Offset + delta.Y)
        end
    end)
    emoteButton.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    -- Button click
    emoteButton.MouseButton1Click:Connect(function()
        emoteEnabled = not emoteEnabled
        if emoteEnabled then
            emoteButton.BackgroundColor3 = Color3.fromRGB(40, 100, 40)
            if selectedEmoteId then
                playEmote(selectedEmoteId)
            end
        else
            emoteButton.BackgroundColor3 = Color3.fromRGB(100, 40, 40)
        end
    end)
end

-- ======= Apply Speed =======
RunService.Heartbeat:Connect(function()
    if not emoteEnabled or not isJumping then return end

    local inputDir = moveInput
    if inputDir == 0 and Humanoid.MoveDirection.Magnitude > 0 then
        local camCF = CFrame.new(Vector3.new(), Camera.CFrame.LookVector)
        inputDir = (camCF.RightVector:Dot(Humanoid.MoveDirection) > 0) and 1 or -1
    end
    if inputDir ~= 0 then
        local camRight = Vector3.new(Camera.CFrame.RightVector.X, 0, Camera.CFrame.RightVector.Z).Unit
        HRP.Velocity = camRight * (inputDir * sideSpeed) + Vector3.new(0, HRP.Velocity.Y, 0)
    end
end)

-- =====================
-- SpeedGlitch GUI ( gato ik you are copying this 😭 )
-- =====================

-- Toggle to show button
speedSection:AddToggle("Speedglitch Button", function(bool)
    if bool then
        createEmoteButton()
    elseif emoteButton then
        emoteButton:Destroy()
        emoteButton = nil
        emoteEnabled = false
    end
end)

-- Slider: Side speed
speedSection:AddSlider("Side Speed", 10, 1000, sideSpeed, function(val)
    sideSpeed = val
end)

-- Slider: Button size
speedSection:AddSlider("Button Size", 30, 150, buttonSize, function(val)
    buttonSize = val
    if emoteButton then
        emoteButton.Size = UDim2.new(0, buttonSize, 0, buttonSize)
    end
end)

-- Dropdown: Emotes
local emoteDropdown = speedSection:AddDropdown("Select Emote", {"Moonwalk","Yungblud - Happier Jump","Baby Queen - Bouncy Twirl","Flex Walk","Custom"}, function(selected)
    if selected == "Custom" then
        customEmoteEnabled = true
        selectedEmoteId = nil
    else
        customEmoteEnabled = false
        selectedEmoteId = emotes[selected]
    end
end)

-- Textbox: Custom emote ID
speedSection:AddTextBox("Custom Emote ID", function(text)
    if text ~= "" then
        selectedEmoteId = text
        customEmoteEnabled = true
    end
end)


-- =============================
-- CREDITS
-- =============================
if credits_tab then
    credits_tab:AddLabel('Credits To: <font color="rgb(255,0,0)">B6O6S (@B6O6S) - Owner/Programmer</font>')
credits_tab:AddLabel('Credits To: <font color="rgb(255,0,0)">k.6z (@3r_q5) - Helper/Tester</font>')
credits_tab:AddLabel('Note: <font color="rgb(0,255,0)">We really spent alot of time trying to make the best</font>')
credits_tab:AddLabel('<font color="rgb(0,255,0)">and fun plugin for everyone to use for free and enjoy</font>')
credits_tab:AddLabel('<font color="rgb(0,255,0)">our dms is open feel free to ask or giving suggestions</font>')
credits_tab:AddLabel('<font color="rgb(0,255,0)">or reporting bugs, have fun ♥️</font>')
end

-- =============================
-- FINAL NOTIFICATION
-- =============================
if shared and shared.Notify then
    shared.Notify("Better ODH Plugin Loaded Successfully!", 3)
end