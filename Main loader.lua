local shared = odh_shared_plugins
local tab = shared.CreateTab("Better ODH", "/B6O6S/Better-ODH/refs/heads/main/Better%20ODH")

local custom_section       = tab:AddSection("Customizations", "Active Configuration")
local ui_section           = tab:AddSection("UI & Fonts")
local perf_fps_section     = tab:AddSection("Performance & FPS")
local trickshot_section    = tab:AddSection("Trickshot & Movement")
local perf_overlay_section = tab:AddSection("Performance Overlay")
local troll_section        = tab:AddSection("Troll (FE)")
local sky_section          = tab:AddSection("Sky changer")
local privacy_section      = tab:AddSection("Privacy and security")
local speed_glitch_section = tab:AddSection("Legit Speed Glitch")
local gun_sound_section    = tab:AddSection("Gun sound Changer")
local knife_sound_section  = tab:AddSection("Knife sound changer")
local multi_hat_section    = tab:AddSection("Multi Hat Giver")
local streamer_section     = tab:AddSection("Streamer Mode")
local codm_guns_section    = tab:AddSection("CODM Guns")
local juke_section         = tab:AddSection("Juke sound effect")
local rtx_section          = tab:AddSection("RTX & Graphics")
local death_sound_section  = tab:AddSection("Death Sound Effect")
local jump_sound_section   = tab:AddSection("Jump Sound Effect")
local spraypaint_section   = tab:AddSection("SprayPaint Mods")
local credits_section      = tab:AddSection("Credits")

local Players             = game:GetService("Players")
local Lighting            = game:GetService("Lighting")
local UIS                 = game:GetService("UserInputService")
local RunService          = game:GetService("RunService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local LocalPlayer         = Players.LocalPlayer
local Camera              = workspace.CurrentCamera
local playerGui           = LocalPlayer:WaitForChild("PlayerGui")

-- =============================
-- CUSTOMIZATIONS SECTION
-- =============================
local blur = Lighting:FindFirstChild("DeltaMotionBlur") or Instance.new("BlurEffect", Lighting)
blur.Name = "DeltaMotionBlur"
blur.Size = 0

local mb_enabled = false
local maxBlurSize = 8  
local blurDecay = 0.5   
local lastCFrame = Camera.CFrame

custom_section:AddToggle("Enable Motion Blur", function(on)
    mb_enabled = on
    if not on then blur.Size = 0 end
end)

custom_section:AddSlider("Blur Strength", 1, 24, maxBlurSize, function(v)
    maxBlurSize = v
end)

RunService.RenderStepped:Connect(function(dt)
    if not mb_enabled then 
        blur.Size = 0
        lastCFrame = Camera.CFrame
        return 
    end

    if not Camera then 
        Camera = workspace.CurrentCamera 
        return 
    end

    local currentCFrame = Camera.CFrame
    
    local deltaMagnitude = math.abs(currentCFrame.X - lastCFrame.X) 
        + math.abs(currentCFrame.Y - lastCFrame.Y) 
        + math.abs(currentCFrame.Z - lastCFrame.Z)
        
    local rotationalDelta = (currentCFrame.LookVector - lastCFrame.LookVector).Magnitude
    
    local targetBlur = (deltaMagnitude + rotationalDelta) * 60
    
    blur.Size = math.clamp(
        math.lerp(blur.Size, targetBlur * 4, dt * 20), 
        0, 
        maxBlurSize
    )
    
    if blur.Size > 0.1 then
        blur.Size = math.clamp(blur.Size - (blurDecay * (dt * 60)), 0, maxBlurSize)
    end

    lastCFrame = currentCFrame
end)

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
        if jb and (jb:IsA("ImageButton") or jb:IsA("TextButton")) then
            return jb
        end
    end

    for _, d in ipairs(tg:GetDescendants()) do
        if d.Name == "JumpButton" and (d:IsA("ImageButton") or d:IsA("TextButton")) then
            return d
        end
    end

    return nil
end

local function setJumpButtonSize(px)
    local jb = findJumpButton()
    if not jb then return end

    local screen = Camera.ViewportSize
    local maxSize = math.min(screen.X, screen.Y) * 0.25
    local clamped = math.clamp(px, 50, maxSize)

    if jb.AbsoluteSize.X ~= clamped then
        jb.Size = UDim2.new(0, clamped, 0, clamped)
        jb.Position = UDim2.new(1, -clamped - 20, 1, -clamped - 20)
    end
end

custom_section:AddToggle("Jump Button Size Changer (Mobile & Tablet)", function(on)
    jb_enabled = on
end)

custom_section:AddSlider("Jump Button Size", 50, 125, jb_size, function(v)
    jb_size = v
end)

RunService.RenderStepped:Connect(function()
    if jb_enabled and UIS.TouchEnabled then
        setJumpButtonSize(jb_size)
    end
end)

local outline_enabled = false
local outline_rainbow = false
local tool_trans_enabled = false
local outline_always_on_top = false
local tool_highlights = {}

local selectedOutline = Color3.fromRGB(128, 0, 128)
local selectedFill    = Color3.fromRGB(0, 0, 0)
local fillTrans       = 8
local outlineTrans    = 8
local toolTrans       = 5

local function applyToolTransparency(tool)
    for _, part in ipairs(tool:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Transparency = tool_trans_enabled and (toolTrans / 10) or 0
        end
    end
end

local function ensureOutline(tool)
    if not tool:IsA("Tool") then return end

    local handle = tool:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then return end

    handle.LocalTransparencyModifier = 0
    if tool_trans_enabled then
        applyToolTransparency(tool)
    end

    local hl = tool:FindFirstChild("ToolOutline")
    if not hl then
        hl = Instance.new("Highlight")
        hl.Name = "ToolOutline"
        hl.Adornee = handle
        hl.Parent = tool
    end

    hl.DepthMode = outline_always_on_top and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
    hl.Enabled = outline_enabled
    hl.OutlineColor = selectedOutline
    hl.FillColor = selectedFill
    hl.FillTransparency = fillTrans / 10
    hl.OutlineTransparency = outlineTrans / 10

    tool_highlights[tool] = hl
end

local function applyOutlineToAllTools()
    tool_highlights = {}

    if LocalPlayer:FindFirstChild("Backpack") then
        for _, t in ipairs(LocalPlayer.Backpack:GetChildren()) do
            ensureOutline(t)
        end
    end

    local char = LocalPlayer.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            ensureOutline(t)
        end
    end
end

local function removeOutlines()
    for tool, hl in pairs(tool_highlights) do
        if hl then hl:Destroy() end
    end
    tool_highlights = {}
end

custom_section:AddToggle("Enable Tool Outline Theme", function(on)
    outline_enabled = on
    if on then applyOutlineToAllTools() else removeOutlines() end
end)

custom_section:AddToggle("Visible Behind Walls", function(on)
    outline_always_on_top = on
    for _, hl in pairs(tool_highlights) do
        if hl then
            hl.DepthMode = on and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
        end
    end
end)

custom_section:AddToggle("Tool Transparency", function(on)
    tool_trans_enabled = on
    
    local function updateTool(t)
        if on then
            applyToolTransparency(t)
        else
            for _, part in ipairs(t:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Transparency = 0
                end
            end
        end
    end

    if LocalPlayer:FindFirstChild("Backpack") then
        for _, t in ipairs(LocalPlayer.Backpack:GetChildren()) do
            updateTool(t)
        end
    end
    local char = LocalPlayer.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            updateTool(t)
        end
    end
end)

custom_section:AddSlider("Tool Transparency Level", 0, 10, toolTrans, function(v)
    toolTrans = v
    if tool_trans_enabled then
        if LocalPlayer:FindFirstChild("Backpack") then
            for _, t in ipairs(LocalPlayer.Backpack:GetChildren()) do
                applyToolTransparency(t)
            end
        end
        local char = LocalPlayer.Character
        if char then
            for _, t in ipairs(char:GetChildren()) do
                applyToolTransparency(t)
            end
        end
    end
end)

custom_section:AddColorpicker("Outline Color", selectedOutline, function(color)
    selectedOutline = color
    for _, hl in pairs(tool_highlights) do
        if hl then hl.OutlineColor = selectedOutline end
    end
end)

custom_section:AddColorpicker("Fill Color", selectedFill, function(color)
    selectedFill = color
    for _, hl in pairs(tool_highlights) do
        if hl then hl.FillColor = selectedFill end
    end
end)

custom_section:AddSlider("Fill Transparency", 0, 10, fillTrans, function(v)
    fillTrans = v
    for _, hl in pairs(tool_highlights) do
        if hl then hl.FillTransparency = fillTrans / 10 end
    end
end)

custom_section:AddSlider("Outline Transparency", 0, 10, outlineTrans, function(v)
    outlineTrans = v
    for _, hl in pairs(tool_highlights) do
        if hl then hl.OutlineTransparency = outlineTrans / 10 end
    end
end)

custom_section:AddToggle("Rainbow Outline", function(on)
    outline_rainbow = on
end)

local hue = 0
RunService.RenderStepped:Connect(function()
    if not outline_rainbow then return end

    hue = (hue + 0.5) % 360
    local color = Color3.fromHSV(hue/360, 1, 1)

    for _, hl in pairs(tool_highlights) do
        if hl then
            hl.OutlineColor = color
            hl.FillColor = color
        end
    end
end)

local function setupCharacter(char)
    char.ChildAdded:Connect(function(obj)
        if obj:IsA("Tool") then
            task.defer(function()
                if outline_enabled then ensureOutline(obj) end
                if tool_trans_enabled then applyToolTransparency(obj) end
            end)
        end
    end)
    
    if outline_enabled then
        task.defer(applyOutlineToAllTools)
    end
    if tool_trans_enabled then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then applyToolTransparency(t) end
        end
    end
end

if LocalPlayer.Character then
    setupCharacter(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(setupCharacter)

if LocalPlayer:FindFirstChild("Backpack") then
    LocalPlayer.Backpack.ChildAdded:Connect(function(obj)
        if obj:IsA("Tool") then
            task.defer(function()
                if outline_enabled then ensureOutline(obj) end
                if tool_trans_enabled then applyToolTransparency(obj) end
            end)
        end
    end)
end

local hide_controls_enabled = false

local function makeInvisible(object)
    if not object:IsA("GuiObject") then return end
    object.Visible = true
    object.BackgroundTransparency = 1
    if object:IsA("ImageButton") or object:IsA("ImageLabel") then
        object.ImageTransparency = 1
    end
    if object:IsA("TextButton") or object:IsA("TextLabel") then
        object.TextTransparency = 1
    end
    for _, descendant in ipairs(object:GetDescendants()) do
        if descendant:IsA("UIStroke") then
            descendant.Transparency = 1
        elseif descendant:IsA("ImageButton") or descendant:IsA("ImageLabel") then
            descendant.ImageTransparency = 1
        elseif descendant:IsA("TextButton") or descendant:IsA("TextLabel") then
            descendant.TextTransparency = 1
        end
    end
end

local function hideTouchGui(touchGui)
    if not touchGui then return end
    for _, descendant in ipairs(touchGui:GetDescendants()) do
        makeInvisible(descendant)
    end
    if not touchGui:GetAttribute("InvisibleLoopConnected") then
        touchGui:SetAttribute("InvisibleLoopConnected", true)
        touchGui.DescendantAdded:Connect(function(descendant)
            if hide_controls_enabled then
                task.wait()
                makeInvisible(descendant)
            end
        end)
    end
end

custom_section:AddToggle("Hide Joystick & Jump Button", function(on)
    hide_controls_enabled = on
end)

task.spawn(function()
    while true do
        if hide_controls_enabled then
            local touchGui = playerGui:FindFirstChild("TouchGui")
            if touchGui then
                hideTouchGui(touchGui)
            end
        end
        task.wait(0.1)
    end
end)

playerGui.ChildAdded:Connect(function(child)
    if child.Name == "TouchGui" and hide_controls_enabled then
        task.defer(function()
            hideTouchGui(child)
        end)
    end
end)

local crosshair_enabled = false
local CROSSHAIR_ID = "rbxassetid://128576456498323"
local CROSSHAIR_SIZE = 40

local crosshairGui = Instance.new("ScreenGui")
crosshairGui.Name = "ThirdPersonCrosshair"
crosshairGui.ResetOnSpawn = false
crosshairGui.IgnoreGuiInset = true
crosshairGui.Parent = playerGui

local crosshair = Instance.new("ImageLabel")
crosshair.Name = "Crosshair"
crosshair.BackgroundTransparency = 1
crosshair.Image = CROSSHAIR_ID
crosshair.ImageTransparency = 0
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Position = UDim2.fromScale(0.5, 0.5)
crosshair.Size = UDim2.fromOffset(CROSSHAIR_SIZE, CROSSHAIR_SIZE)
crosshair.Visible = false
crosshair.Parent = crosshairGui

custom_section:AddToggle("Show Fake PC Crosshair", function(on)
    crosshair_enabled = on
    if not on then
        crosshair.Visible = false
    end
end)

local function isShiftLockActive()
    return UIS.MouseBehavior == Enum.MouseBehavior.LockCenter
end

RunService.RenderStepped:Connect(function()
    if not crosshair_enabled then
        crosshair.Visible = false
        return
    end

    local camera = workspace.CurrentCamera
    if not camera then
        crosshair.Visible = false
        return
    end

    local character = LocalPlayer.Character
    local head = character and character:FindFirstChild("Head")
    if not head then
        crosshair.Visible = false
        return
    end

    local distance = (camera.CFrame.Position - head.Position).Magnitude
    local firstPerson = distance <= 1.5
    local shiftLock = isShiftLockActive()

    if not firstPerson and not shiftLock then
        crosshair.Visible = true
    else
        crosshair.Visible = false
    end
end)

-- =============================
-- UI & FONTS SECTION
-- =============================
local wideScreenEnabled = false
local wideScreenSliderValue = 7

ui_section:AddToggle("Stretch Screen", function(on)
    wideScreenEnabled = on
end)

ui_section:AddSlider("Stretch Screen Strength", 1, 10, wideScreenSliderValue, function(v)
    wideScreenSliderValue = v
end)

RunService.RenderStepped:Connect(function()
    if wideScreenEnabled then
        local wideScreenStrength = wideScreenSliderValue / 10
        Camera.CFrame = Camera.CFrame * CFrame.new(0, 0, 0, 1, 0, 0, 0, wideScreenStrength, 0, 0, 0, 1)
    end
end)

local tradeRequestsEnabled = true
local tradeEvent = ReplicatedStorage:WaitForChild("Trade"):WaitForChild("SetRequestsEnabled")

ui_section:AddToggle("Disable Trade Requests", function(on)
    tradeRequestsEnabled = not on
    pcall(function()
        tradeEvent:FireServer(tradeRequestsEnabled)
    end)
end)

local spooferActive = false
local statVal1 = "0"
local statVal2 = "0"
local statVal3 = "0"

ui_section:AddToggle("Enable Visual Stat Spoofer", function(on)
    spooferActive = on
end)

ui_section:AddTextBox("Stat 1 (Murderer / Eliminations)", function(text)
    statVal1 = tostring(text or "0")
end)

ui_section:AddTextBox("Stat 2 (Sheriff / Saves)", function(text)
    statVal2 = tostring(text or "0")
end)

ui_section:AddTextBox("Stat 3 (Innocent / Survivals)", function(text)
    statVal3 = tostring(text or "0")
end)

task.spawn(function()
    local cachedStatsElements = {}
    local lastCacheCheck = 0

    while true do
        task.wait(0.5)
        if spooferActive then
            pcall(function()
                local currentTime = tick()
                if currentTime - lastCacheCheck > 3 or #cachedStatsElements == 0 then
                    lastCacheCheck = currentTime
                    table.clear(cachedStatsElements)

                    local mainGui = playerGui and playerGui:FindFirstChild("MainGUI")
                    if mainGui then
                        for _, desc in ipairs(mainGui:GetDescendants()) do
                            if desc.Name == "Season1Stats" or desc.Name == "Stats" or desc.Name == "Container" then
                                local elim = desc:FindFirstChild("Eliminations")
                                local saves = desc:FindFirstChild("Saves")
                                local survivals = desc:FindFirstChild("Survivals")
                                
                                local entry = {}
                                if elim and elim:FindFirstChild("Amount") then
                                    entry.ElimAmount = elim.Amount
                                end
                                if saves and saves:FindFirstChild("Amount") then
                                    entry.SavesAmount = saves.Amount
                                end
                                if survivals and survivals:FindFirstChild("Amount") then
                                    entry.SurvivalsAmount = survivals.Amount
                                end
                                
                                if entry.ElimAmount or entry.SavesAmount or entry.SurvivalsAmount then
                                    table.insert(cachedStatsElements, entry)
                                end
                            end
                        end
                    end
                end

                for _, entry in ipairs(cachedStatsElements) do
                    if entry.ElimAmount and entry.ElimAmount.Parent then
                        entry.ElimAmount.Text = tostring(statVal1)
                    end
                    if entry.SavesAmount and entry.SavesAmount.Parent then
                        entry.SavesAmount.Text = tostring(statVal2)
                    end
                    if entry.SurvivalsAmount and entry.SurvivalsAmount.Parent then
                        entry.SurvivalsAmount.Text = tostring(statVal3)
                    end
                end
            end)
        else
            if #cachedStatsElements > 0 then
                table.clear(cachedStatsElements)
            end
        end
    end
end)

local fonts = {
    ["SourceSansBold (Original)"] = Enum.Font.SourceSansBold,
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

local selectedFont = "SourceSansBold (Original)"

ui_section:AddDropdown("Select Font", {
    "SourceSansBold (Original)", "Gotham", "Arcade", "Arial", "ArialBold", "Cartoon", "Fantasy", "Highway", "Code", "Legacy"
}, function(selected)
    selectedFont = selected
    local fontEnum = fonts[selectedFont] or Enum.Font.SourceSansBold
    for _, gui in ipairs(playerGui:GetDescendants()) do
        if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
            gui.Font = fontEnum
        end
    end
end)

playerGui.DescendantAdded:Connect(function(gui)
    if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
        gui.Font = fonts[selectedFont] or Enum.Font.SourceSansBold
    end
end)

-- =============================
-- PERFORMANCE & FPS SECTION
-- =============================
local original_materials = {}
local original_particle_states = {}
local original_textures = {}
local original_mesh_transparency = {}
local original_accessories = {}
local original_skies = {}
local perf_conns = {}

local function isPlayerDescendant(obj)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character and obj:IsDescendantOf(plr.Character) then
            return true
        end
    end
    return false
end

local function applyMeshToObj(obj)
    if isPlayerDescendant(obj) then return end

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
        for _, obj in ipairs(workspace:GetDescendants()) do
            applyMeshToObj(obj)
        end
        if not perf_conns.Meshes then
            perf_conns.Meshes = workspace.DescendantAdded:Connect(function(obj)
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
        if perf_conns.Meshes then
            perf_conns.Meshes:Disconnect()
            perf_conns.Meshes = nil
        end
    end
end

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
        if not perf_conns.CharacterAdded then
            perf_conns.CharacterAdded = Players.PlayerAdded:Connect(function(p)
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
        if perf_conns.CharacterAdded then
            perf_conns.CharacterAdded:Disconnect()
            perf_conns.CharacterAdded = nil
        end
    end
end

local function setSmoothPlastic(on)
    if on then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and not isPlayerDescendant(obj) and obj.Material ~= Enum.Material.SmoothPlastic then
                original_materials[obj] = obj.Material
                obj.Material = Enum.Material.SmoothPlastic
            end
        end
        if not perf_conns.Smooth then
            perf_conns.Smooth = workspace.DescendantAdded:Connect(function(obj)
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
        if perf_conns.Smooth then perf_conns.Smooth:Disconnect() perf_conns.Smooth = nil end
    end
end

local function setParticles(on)
    if on then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") then
                original_particle_states[obj] = obj.Enabled
                obj.Enabled = false
            end
        end
        if not perf_conns.Particles then
            perf_conns.Particles = workspace.DescendantAdded:Connect(function(obj)
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
        if perf_conns.Particles then perf_conns.Particles:Disconnect() perf_conns.Particles = nil end
    end
end

local function setTextures(on)
    if on then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Decal") or obj:IsA("Texture") then
                if original_textures[obj] == nil then
                    original_textures[obj] = obj.Texture
                end
                obj.Texture = ""
            end
        end
        if not perf_conns.Textures then
            perf_conns.Textures = workspace.DescendantAdded:Connect(function(obj)
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
        if perf_conns.Textures then perf_conns.Textures:Disconnect() perf_conns.Textures = nil end
    end
end

local function setShadows(on)
    Lighting.GlobalShadows = not on
end

local function setGraySky(on)
    if on then
        for _, obj in ipairs(Lighting:GetChildren()) do
            if obj:IsA("Sky") then
                original_skies[obj] = obj.Parent
                obj.Parent = nil
            end
        end
        local sky = Instance.new("Sky")
        sky.Name = "CustomGraySky"
        local assetId = "rbxassetid://99742693890881"
        sky.SkyboxBk = assetId
        sky.SkyboxDn = assetId
        sky.SkyboxFt = assetId
        sky.SkyboxLf = assetId
        sky.SkyboxRt = assetId
        sky.SkyboxUp = assetId
        sky.Parent = Lighting
    else
        local customSky = Lighting:FindFirstChild("CustomGraySky")
        if customSky then
            customSky:Destroy()
        end
        for sky, parent in pairs(original_skies) do
            if sky then
                sky.Parent = parent
            end
        end
        original_skies = {}
    end
end

if perf_fps_section then
    perf_fps_section:AddToggle("No Textures (SmoothPlastic)", setSmoothPlastic)
    perf_fps_section:AddToggle("Disable Shadows", setShadows)
    perf_fps_section:AddToggle("Disable Particles/Trails", setParticles)
    perf_fps_section:AddToggle("Hide Meshes (world only)", setMeshes)
    perf_fps_section:AddToggle("Remove Textures/Decals", setTextures)
    perf_fps_section:AddToggle("Remove Accessories", setAccessories)
    perf_fps_section:AddToggle("Gray Skybox", setGraySky)
    perf_fps_section:AddButton("Remove Weapon Displays", function()
        local wd = workspace:FindFirstChild("WeaponDisplays")
        if wd then wd:Destroy() end
    end)
end



 -- =============================
-- TRICKSHOT & MOVEMENT SECTION
-- =============================
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local trickshotEnabled = false
local strafeEnabled = false
local strafeSpeed = 16
local spinSpeed = math.rad(15)
local spinning = false
local strafeDirection = 1

trickshot_section:AddToggle("Enable Automatic 360 Trickshot", function(on) trickshotEnabled = on end)
trickshot_section:AddToggle("Enable Automatic Strafe", function(on) strafeEnabled = on end)
trickshot_section:AddSlider("Strafe Speed", 4, 32, strafeSpeed, function(v) strafeSpeed = v end)
trickshot_section:AddSlider("360 Spin Speed", 1, 50, math.deg(spinSpeed), function(v) spinSpeed = math.rad(v) end)

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

local function setupHumanoid(h)
    humanoid = h
    originalJumpPower = h.JumpPower
    boosted = false

    h:GetPropertyChangedSignal("Jump"):Connect(function()
        if boosted and h.Jump then
            task.wait(0.1)
            h.JumpPower = originalJumpPower
            boosted = false
        end
        if jump360Enabled and spinOnNextJump and h.Jump then
            local HRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if HRP then
                for i = 1, 30 do
                    HRP.CFrame = HRP.CFrame * CFrame.Angles(0, (math.rad(360)/30) * (spinSpeed / math.rad(15)), 0)
                    task.wait(0.01)
                end
                spinOnNextJump = false
            end
        end
    end)
end

if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
    setupHumanoid(LocalPlayer.Character.Humanoid)
end
LocalPlayer.CharacterAdded:Connect(function(char)
    setupHumanoid(char:WaitForChild("Humanoid"))
end)

trickshot_section:AddToggle("Enable Jump Boost Button", function(on)
    jumpBoostEnabled = on
    if on then
        if screenGuiJump then screenGuiJump:Destroy() end
        screenGuiJump = Instance.new("ScreenGui", LocalPlayer:WaitForChild("PlayerGui"))
        screenGuiJump.ResetOnSpawn = false
        buttonJump = Instance.new("TextButton", screenGuiJump)
        buttonJump.Size = UDim2.new(0, jumpBoostSize, 0, jumpBoostSize)
        buttonJump.Position = UDim2.new(0.5, -jumpBoostSize/2, 0.5, -jumpBoostSize/2)
        buttonJump.Text = "Jump Boost"
        buttonJump.BackgroundColor3 = Color3.new(0, 0, 0)
        buttonJump.TextColor3 = Color3.new(1, 1, 1)
        buttonJump.Font = Enum.Font.Arcade
        buttonJump.TextSize = 18
        buttonJump.Active = true
        buttonJump.Draggable = true
        buttonJump.MouseButton1Click:Connect(function()
            if humanoid and not boosted then
                originalJumpPower = humanoid.JumpPower
                humanoid.JumpPower = 125
                boosted = true
            end
        end)
    elseif screenGuiJump then
        screenGuiJump:Destroy()
        screenGuiJump = nil
    end
end)

trickshot_section:AddSlider("Jump Boost Button Size", 20, 150, jumpBoostSize, function(v)
    jumpBoostSize = v
    if buttonJump then
        buttonJump.Size = UDim2.new(0, jumpBoostSize, 0, jumpBoostSize)
        buttonJump.Position = UDim2.new(0.5, -jumpBoostSize/2, 0.5, -jumpBoostSize/2)
    end
end)

trickshot_section:AddToggle("Enable 360 Jump Button", function(on)
    jump360Enabled = on
    if on then
        if screenGui360 then screenGui360:Destroy() end
        screenGui360 = Instance.new("ScreenGui", LocalPlayer:WaitForChild("PlayerGui"))
        screenGui360.ResetOnSpawn = false
        button360 = Instance.new("TextButton", screenGui360)
        button360.Size = UDim2.new(0, jump360Size, 0, jump360Size)
        button360.Position = UDim2.new(0.5, -jump360Size/2, 0.5, -jump360Size/2)
        button360.Text = "360 Jump"
        button360.BackgroundColor3 = Color3.new(0, 0, 0)
        button360.TextColor3 = Color3.new(1, 1, 1)
        button360.Font = Enum.Font.Arcade
        button360.TextSize = 18
        button360.Active = true
        button360.Draggable = true
        button360.MouseButton1Click:Connect(function() spinOnNextJump = true end)
    elseif screenGui360 then
        screenGui360:Destroy()
        screenGui360 = nil
    end
end)

trickshot_section:AddSlider("360 Jump Button Size", 50, 200, jump360Size, function(v)
    jump360Size = v
    if button360 then
        button360.Size = UDim2.new(0, jump360Size, 0, jump360Size)
        button360.Position = UDim2.new(0.5, -jump360Size/2, 0.5, -jump360Size/2)
    end
end)

RunService.RenderStepped:Connect(function(delta)
    local char = LocalPlayer.Character
    if not char then return end
    local HRP = char:FindFirstChild("HumanoidRootPart")
    local h = char:FindFirstChildOfClass("Humanoid")
    if not HRP or not h then return end

    if strafeEnabled then
        local moveVec = HRP.CFrame.RightVector * strafeDirection
        HRP.CFrame = HRP.CFrame + moveVec.Unit * strafeSpeed * delta
        strafeDirection = (tick() % 1 < 0.5) and 1 or -1
    end

    if trickshotEnabled then
        local state = h:GetState()
        if state == Enum.HumanoidStateType.Freefall then spinning = true
        elseif spinning and state == Enum.HumanoidStateType.Landed then spinning = false end
        if spinning then HRP.CFrame = HRP.CFrame * CFrame.Angles(0, spinSpeed, 0) end
    end
end)

local wallhopEnabled = false
local backToNormalEnabled = false
local selectedLookDirection = "Back"
local InfiniteJumpEnabled = true
local wallRaycastParams = RaycastParams.new()
wallRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function performWallhop()
    local character = LocalPlayer.Character
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    local h = character:FindFirstChildOfClass("Humanoid")
    if not hrp or not h or h:GetState() == Enum.HumanoidStateType.Dead then return end

    wallRaycastParams.FilterDescendantsInstances = {character}
    local res = Workspace:Raycast(hrp.Position, hrp.CFrame.LookVector * 3, wallRaycastParams)
    if res then
        InfiniteJumpEnabled = false
        h:ChangeState(Enum.HumanoidStateType.Jumping)
        
        if backToNormalEnabled then
            local rotAngle = math.pi
            if selectedLookDirection == "Right" then rotAngle = -math.pi/2
            elseif selectedLookDirection == "Left" then rotAngle = math.pi/2 end
            hrp.CFrame = hrp.CFrame * CFrame.Angles(0, rotAngle, 0)
            task.wait(0.15)
            hrp.CFrame = hrp.CFrame * CFrame.Angles(0, (selectedLookDirection == "Back" and math.pi or (selectedLookDirection == "Right" and math.pi/2 or -math.pi/2)), 0)
        else
            hrp.CFrame = hrp.CFrame * CFrame.Angles(0, -1, 0)
            task.wait(0.1)
            hrp.CFrame = hrp.CFrame * CFrame.Angles(0, 1, 0)
        end
        task.wait(0.1)
        InfiniteJumpEnabled = true
    end
end

trickshot_section:AddToggle("Enable Wallhop", function(on) wallhopEnabled = on end)
trickshot_section:AddToggle("Back To Normal position after jump", function(on) backToNormalEnabled = on end)
trickshot_section:AddDropdown("Wallhop Look Direction", {"Back", "Right", "Left"}, function(sel) selectedLookDirection = sel end)
trickshot_section:AddKeybind("Wallhop Jump Key", "J", performWallhop)

UIS.JumpRequest:Connect(function()
    if wallhopEnabled and InfiniteJumpEnabled then performWallhop() end
end)

local finalToyEventRef = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Extras"):WaitForChild("ReplicateToy")
local autoSpawnToysEnabled = false
local selectedToy1 = "None"
local selectedToy2 = "None"
local availableToysList = {"None"}

local function getToysFolder()
    local bp = LocalPlayer:WaitForChild("Backpack", 5)
    return bp and bp:WaitForChild("Toys", 5) or nil
end

local function updateAvailableToys()
    local toysFolder = getToysFolder()
    local list = {"None"}
    if toysFolder then
        for _, toy in ipairs(toysFolder:GetChildren()) do table.insert(list, toy.Name) end
    end
    availableToysList = list
end
updateAvailableToys()

local function spawnSelectedToys()
    if not autoSpawnToysEnabled then return end
    task.spawn(function()
        local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        char:WaitForChild("Humanoid", 5)
        getToysFolder()
        task.wait(0.5)
        if selectedToy1 and selectedToy1 ~= "None" then pcall(function() finalToyEventRef:InvokeServer(selectedToy1) end) task.wait(0.3) end
        if selectedToy2 and selectedToy2 ~= "None" then pcall(function() finalToyEventRef:InvokeServer(selectedToy2) end) end
    end)
end

LocalPlayer.CharacterAdded:Connect(spawnSelectedToys)
trickshot_section:AddToggle("Auto Spawn Toys On Respawn", function(on) autoSpawnToysEnabled = on if on then spawnSelectedToys() end end)
trickshot_section:AddDropdown("Select Toy Slot 1", availableToysList, function(sel) selectedToy1 = sel end)
trickshot_section:AddDropdown("Select Toy Slot 2", availableToysList, function(sel) selectedToy2 = sel end)

local toyEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Extras"):WaitForChild("ReplicateToy")
local screenGuiBomb = CoreGui:FindFirstChild("AutoSequenceJumpDraggableGui")
local frameBomb, buttonBomb, strokeBomb
local bombJumpGuiSize = 220
local showBombJumpGui = false
local bombUseMode = "Toggle To Use Bomb"
local selectedBombType = "Bomb"

if not screenGuiBomb then
    screenGuiBomb = Instance.new("ScreenGui")
    screenGuiBomb.Name = "AutoSequenceJumpDraggableGui"
    screenGuiBomb.ResetOnSpawn = false
    screenGuiBomb.Enabled = false
    screenGuiBomb.Parent = CoreGui

    frameBomb = Instance.new("Frame")
    frameBomb.Size = UDim2.new(0, bombJumpGuiSize, 0, bombJumpGuiSize * (100/220))
    frameBomb.Position = UDim2.new(1, -240, 1, -210)
    frameBomb.BackgroundTransparency = 1
    frameBomb.Parent = screenGuiBomb

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 22)
    corner.Parent = frameBomb

    strokeBomb = Instance.new("UIStroke")
    strokeBomb.Color = Color3.fromRGB(255, 255, 255)
    strokeBomb.Thickness = 3.5
    strokeBomb.Parent = frameBomb

    buttonBomb = Instance.new("TextButton")
    buttonBomb.Size = UDim2.new(1, 0, 1, 0)
    buttonBomb.BackgroundTransparency = 1
    buttonBomb.Text = "Bomb Jump (OFF)"
    buttonBomb.TextColor3 = Color3.fromRGB(255, 255, 255)
    buttonBomb.TextSize = 18
    buttonBomb.Font = Enum.Font.GothamBold
    buttonBomb.Parent = frameBomb
else
    frameBomb = screenGuiBomb:FindFirstChildOfClass("Frame")
    strokeBomb = frameBomb and frameBomb:FindFirstChildOfClass("UIStroke")
    buttonBomb = frameBomb and frameBomb:FindFirstChildOfClass("TextButton")
end

local isActiveBomb, hasTriggeredBomb, isWaitingTimerBomb, timerTokenBomb = false, false, false, 0
local draggingBomb, dragInputBomb, dragStartBomb, startPosBomb, movedBomb = false, nil, nil, nil, false

if buttonBomb and frameBomb then
    buttonBomb.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingBomb, movedBomb = true, false
            dragStartBomb, startPosBomb = input.Position, frameBomb.Position
            input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then draggingBomb = false end end)
        else
            movedBomb = true
        end
    end)
    buttonBomb.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInputBomb = input
            movedBomb = true
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if input == dragInputBomb and draggingBomb then
            local delta = input.Position - dragStartBomb
            frameBomb.Position = UDim2.new(startPosBomb.X.Scale, startPosBomb.X.Offset + delta.X, startPosBomb.Y.Scale, startPosBomb.Y.Offset + delta.Y)
        end
    end)
end

local function getBombToolName() return selectedBombType == "Gold Bomb" and "GoldBomb" or "FakeBomb" end

local function executeBombJumpAction(isToggleMode)
    local character = LocalPlayer.Character
    if not character then return end
    local h, rootPart = character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart")
    if not h or not rootPart or not strokeBomb or not buttonBomb then return end

    hasTriggeredBomb, isActiveBomb = true, false
    task.spawn(function()
        if isToggleMode then task.wait(0.1) end
        local toolName = getBombToolName()
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        local tool = character:FindFirstChild(toolName) or (backpack and backpack:FindFirstChild(toolName))
        if tool then
            if tool.Parent == backpack then h:EquipTool(tool) end
            pcall(function() toyEvent:InvokeServer(toolName) end)
            pcall(function()
                local vu = game:GetService("VirtualUser")
                vu:Button1Down(Vector2.zero)
                vu:Button1Up(Vector2.zero)
            end)
            if tool.Parent == character then tool.Parent = backpack end
        end
        if isToggleMode then task.wait(0.1) end
        h:ChangeState(Enum.HumanoidStateType.Jumping)
        h.Jump = true
        
        isWaitingTimerBomb = true
        strokeBomb.Color = Color3.fromRGB(255, 0, 0)
        local currentToken, waitTime, startTime = timerTokenBomb, (selectedBombType == "Gold Bomb" and 3.2 or 21.7), tick()
        while true do
            if timerTokenBomb ~= currentToken then return end
            local elapsed = tick() - startTime
            local remaining = waitTime - elapsed
            if remaining <= 0 then break end
            buttonBomb.Text = string.format("Wait (%.1fs)", remaining)
            buttonBomb.TextColor3 = Color3.fromRGB(255, 0, 0)
            task.wait(0.05)
        end
        if timerTokenBomb ~= currentToken then return end
        isWaitingTimerBomb, hasTriggeredBomb = false, false
        buttonBomb.Text = (bombUseMode == "Toggle To Use Bomb") and "Bomb Jump (OFF)" or "Bomb Jump"
        buttonBomb.TextColor3, strokeBomb.Color = Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255)
    end)
end

if buttonBomb then
    buttonBomb.MouseButton1Click:Connect(function()
        if movedBomb or isWaitingTimerBomb then return end
        local toolName = getBombToolName()
        if bombUseMode == "Toggle To Use Bomb" then
            isActiveBomb = not isActiveBomb
            buttonBomb.Text = isActiveBomb and "Ready" or "Bomb Jump (OFF)"
            buttonBomb.TextColor3 = isActiveBomb and Color3.fromRGB(50, 255, 50) or Color3.fromRGB(255, 255, 255)
            strokeBomb.Color = isActiveBomb and Color3.fromRGB(50, 200, 50) or Color3.fromRGB(255, 255, 255)
            hasTriggeredBomb = false
            if isActiveBomb then pcall(function() toyEvent:InvokeServer(toolName) end) end
        elseif bombUseMode == "Click To Use Bomb" then
            pcall(function() toyEvent:InvokeServer(toolName) end)
            executeBombJumpAction(false)
        end
    end)
end

local function setupCharacterBomb(character)
    local h = character:WaitForChild("Humanoid")
    timerTokenBomb += 1
    isWaitingTimerBomb, hasTriggeredBomb = false, false
    if buttonBomb and strokeBomb then
        buttonBomb.Text = (bombUseMode == "Toggle To Use Bomb" and not isActiveBomb) and "Bomb Jump (OFF)" or "Bomb Jump"
        buttonBomb.TextColor3, strokeBomb.Color = Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255)
    end
    h.StateChanged:Connect(function(oldState, newState)
        if bombUseMode ~= "Toggle To Use Bomb" or not isActiveBomb or hasTriggeredBomb or isWaitingTimerBomb then return end
        if newState == Enum.HumanoidStateType.Jumping then executeBombJumpAction(true)
        elseif newState == Enum.HumanoidStateType.Landed and not isWaitingTimerBomb then hasTriggeredBomb = false end
    end)
end

if LocalPlayer.Character then setupCharacterBomb(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(setupCharacterBomb)

trickshot_section:AddToggle("Show Bomb Jump Button", function(on)
    showBombJumpGui = on
    if screenGuiBomb then screenGuiBomb.Enabled = on end
end)
trickshot_section:AddDropdown("Choose Bomb Type", {"Bomb", "Gold Bomb"}, function(sel) selectedBombType, isActiveBomb, hasTriggeredBomb = sel, false, false end)
trickshot_section:AddDropdown("Bomb Usage Mode", {"Toggle To Use Bomb", "Click To Use Bomb"}, function(sel)
    bombUseMode = sel
    isActiveBomb, hasTriggeredBomb = false, false
    if not isWaitingTimerBomb and buttonBomb and strokeBomb then
        buttonBomb.Text = (bombUseMode == "Toggle To Use Bomb") and "Bomb Jump (OFF)" or "Bomb Jump"
        buttonBomb.TextColor3, strokeBomb.Color = Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255)
    end
end)
trickshot_section:AddSlider("Bomb Jump GUI Size", 100, 300, bombJumpGuiSize, function(v)
    bombJumpGuiSize = v
    if frameBomb then frameBomb.Size = UDim2.new(0, bombJumpGuiSize, 0, bombJumpGuiSize * (100/220)) end
end)

local flickGui = CoreGui:FindFirstChild("AutoFlickShootDraggableGui")
local flickFrame, flickButton, flickStroke = nil, nil, nil
local flickGuiSize, showFlickGui, flickReloading, FLICK_RELOAD_TIME = 220, false, false, 2.7
local flickWallCheckEnabled, flickMode, flickSmoothSpeed, whitelistFriendsEnabled = false, "Instant", 10, false

if not flickGui then
    flickGui = Instance.new("ScreenGui", CoreGui)
    flickGui.Name = "AutoFlickShootDraggableGui"
    flickGui.ResetOnSpawn = false
    flickGui.Enabled = false

    flickFrame = Instance.new("Frame", flickGui)
    flickFrame.Name = "FlickFrame"
    flickFrame.Size = UDim2.new(0, flickGuiSize, 0, flickGuiSize * (100 / 220))
    flickFrame.Position = UDim2.new(1, -240, 1, -330)
    flickFrame.BackgroundTransparency = 1
    Instance.new("UICorner", flickFrame).CornerRadius = UDim.new(0, 22)

    flickStroke = Instance.new("UIStroke", flickFrame)
    flickStroke.Color, flickStroke.Thickness, flickStroke.Transparency = Color3.fromRGB(255, 255, 255), 3.5, 0

    flickButton = Instance.new("TextButton", flickFrame)
    flickButton.Name = "FlickButton"
    flickButton.Size = UDim2.new(1, 0, 1, 0)
    flickButton.BackgroundTransparency = 1
    flickButton.Text, flickButton.TextColor3, flickButton.TextSize, flickButton.Font = "Flick Shoot", Color3.fromRGB(255, 255, 255), 18, Enum.Font.GothamBold
else
    flickFrame = flickGui:FindFirstChild("FlickFrame") or flickGui:FindFirstChildOfClass("Frame")
    if flickFrame then
        flickStroke = flickFrame:FindFirstChildOfClass("UIStroke")
        flickButton = flickFrame:FindFirstChild("FlickButton") or flickFrame:FindFirstChildOfClass("TextButton")
    end
end

if flickButton and flickFrame then
    local flickDragging, flickMoved, flickDragStart, flickStartPos, flickDragInput = false, false, nil, nil, nil
    flickButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            flickDragging, flickMoved = true, false
            flickDragStart, flickStartPos = input.Position, flickFrame.Position
            input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then flickDragging = false end end)
        end
    end)
    flickButton.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then flickDragInput = input end
    end)
    UIS.InputChanged:Connect(function(input)
        if input == flickDragInput and flickDragging then
            local delta = input.Position - flickDragStart
            if math.abs(delta.X) > 5 or math.abs(delta.Y) > 5 then flickMoved = true end
            flickFrame.Position = UDim2.new(flickStartPos.X.Scale, flickStartPos.X.Offset + delta.X, flickStartPos.Y.Scale, flickStartPos.Y.Offset + delta.Y)
        end
    end)

    local function isFirstPerson()
        local cam, char = workspace.CurrentCamera, LocalPlayer.Character
        local head = char and char:FindFirstChild("Head")
        return cam and head and (cam.CFrame.Position - head.Position).Magnitude <= 1
    end

    local function isShiftLock()
        local s, res = pcall(function() return UIS.MouseBehavior == Enum.MouseBehavior.LockCenter end)
        return s and res == true
    end

    local function shouldSnapCamera()
        return isFirstPerson() or isShiftLock()
    end

    local function hasLineOfSight(targetCharacter)
        if not flickWallCheckEnabled then return true end
        local cam, targetPart = workspace.CurrentCamera, targetCharacter and (targetCharacter:FindFirstChild("HumanoidRootPart") or targetCharacter:FindFirstChild("Head"))
        if not cam or not targetPart then return false end
        local origin, dir = cam.CFrame.Position, targetPart.Position - cam.CFrame.Position
        if dir.Magnitude <= 0.01 then return true end
        local params = RaycastParams.new()
        params.FilterType, params.FilterDescendantsInstances, params.IgnoreWater = Enum.RaycastFilterType.Exclude, {LocalPlayer.Character}, true
        local res = workspace:Raycast(origin, dir, params)
        return not res or res.Instance:IsDescendantOf(targetCharacter)
    end

    local normalTextColor, normalStrokeColor, reloadColor = Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 0, 0)
    local function setReloadingVisuals()
        flickButton.TextColor3 = reloadColor
        if flickStroke then flickStroke.Color = reloadColor end
    end
    local function setNormalVisuals()
        flickButton.TextColor3 = normalTextColor
        if flickStroke then flickStroke.Color = normalStrokeColor end
    end

    local function startReload()
        flickReloading = true
        setReloadingVisuals()
        local endTime = os.clock() + FLICK_RELOAD_TIME
        while true do
            local remaining = endTime - os.clock()
            if remaining <= 0 then break end
            flickButton.Text = "Reloading... " .. string.format("%.1f", remaining)
            task.wait(0.05)
        end
        flickReloading = false
        flickButton.Text = "Flick Shoot"
        setNormalVisuals()
    end

    local function isFriend(player)
        if not player then return false end
        local s, res = pcall(function() return LocalPlayer:IsFriendsWith(player.UserId) end)
        return s and res == true
    end

    local function findMurderer()
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local s, role = pcall(function() return p.Role end)
                if s and role == "Murderer" and hasLineOfSight(p.Character) then return p end
            end
        end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local char, bp = p.Character, p:FindFirstChild("Backpack")
                if ((char and char:FindFirstChild("Knife")) or (bp and bp:FindFirstChild("Knife"))) and hasLineOfSight(char) then return p end
            end
        end
        return nil
    end

    local function getSmoothDuration()
        return 0.35 - ((0.35 - 0.035) * ((flickSmoothSpeed - 1) / 19))
    end

    local function smoothFlick(hrp, h, targetPosition, cam, useCamera)
        if not hrp or not h or not hrp.Parent or not h.Parent then return end
        local startPos = hrp.Position
        local flatTarget = Vector3.new(targetPosition.X, startPos.Y, targetPosition.Z)
        local dir = flatTarget - startPos
        if dir.Magnitude <= 0.01 then return end
        dir = dir.Unit
        local startCharCFrame = hrp.CFrame
        local startCamCFrame, targetCamCFrame = nil, nil
        if cam and useCamera then
            startCamCFrame = cam.CFrame
            targetCamCFrame = CFrame.lookAt(cam.CFrame.Position, targetPosition)
        end
        local oldAutoRotate = h.AutoRotate
        h.AutoRotate = false
        local duration = getSmoothDuration()
        local startTime = os.clock()
        local renderName = "FlickSmoothRotation_" .. tostring(math.random(100000, 999999))
        local finished = false

        local function update()
            if finished or not hrp.Parent then finished = true return end
            local alpha = math.clamp((os.clock() - startTime) / duration, 0, 1)
            local eased = alpha * alpha * (3 - 2 * alpha)
            local curPos = hrp.Position
            local desiredCFrame = CFrame.lookAt(curPos, curPos + dir)
            local newCFrame = startCharCFrame:Lerp(desiredCFrame, eased)
            hrp.CFrame = CFrame.new(curPos) * CFrame.fromMatrix(Vector3.zero, newCFrame.RightVector, newCFrame.UpVector)
            if cam and useCamera and targetCamCFrame and startCamCFrame then
                cam.CFrame = startCamCFrame:Lerp(targetCamCFrame, eased)
            end
            if alpha >= 1 then finished = true end
        end

        pcall(function() RunService:BindToRenderStep(renderName, Enum.RenderPriority.Camera.Value + 1, update) end)
        while not finished do
            if not hrp.Parent or not h.Parent then finished = true break end
            RunService.Heartbeat:Wait()
        end
        pcall(function() RunService:UnbindFromRenderStep(renderName) end)
        if hrp.Parent then
            local finalPos = hrp.Position
            hrp.CFrame = CFrame.lookAt(finalPos, finalPos + dir)
        end
        if cam and useCamera and targetCamCFrame then cam.CFrame = targetCamCFrame end
        h.AutoRotate = oldAutoRotate
    end

    local function executeFlickShoot()
        if flickReloading then return end
        local char = LocalPlayer.Character
        if not char then return end
        local h, hrp = char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
        if not h or not hrp then return end

        local targetPlayer = findMurderer()
        if not targetPlayer or not targetPlayer.Character then
            flickButton.Text = flickWallCheckEnabled and "No Clear Target" or "No Murderer Found"
            task.wait(1) if not flickReloading then flickButton.Text = "Flick Shoot" end
            return
        end

        if whitelistFriendsEnabled and isFriend(targetPlayer) then
            flickButton.Text = "Friend Is Murderer"
            task.wait(1) if not flickReloading then flickButton.Text = "Flick Shoot" end
            return
        end

        local targetHrp = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not targetHrp then return end
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        local gunTool = char:FindFirstChild("Gun") or (backpack and backpack:FindFirstChild("Gun"))
        if not gunTool then
            flickButton.Text = "No Gun Found"
            task.wait(1) if not flickReloading then flickButton.Text = "Flick Shoot" end
            return
        end
        if gunTool.Parent == backpack then h:EquipTool(gunTool) task.wait() end

        local origLook, cam, useCamera = hrp.CFrame.LookVector, workspace.CurrentCamera, shouldSnapCamera()
        local origCamCFrame = cam and useCamera and cam.CFrame or nil
        local curPos, targetPos = hrp.Position, Vector3.new(targetHrp.Position.X, hrp.Position.Y, targetHrp.Position.Z)
        local dir = targetPos - curPos
        if dir.Magnitude > 0.01 then
            dir = dir.Unit
            if flickMode == "Smooth" then
                smoothFlick(hrp, h, targetHrp.Position, cam, useCamera)
            else
                hrp.CFrame = CFrame.lookAt(curPos, curPos + dir)
                if cam and useCamera then cam.CFrame = CFrame.lookAt(cam.CFrame.Position, targetHrp.Position) end
            end
        end

        gunTool:Activate()
        pcall(function()
            local vu = game:GetService("VirtualUser")
            vu:Button1Down(Vector2.zero)
            vu:Button1Up(Vector2.zero)
        end)
        task.wait(0.15)
        local restorePos = hrp.Position
        local flatLook = Vector3.new(origLook.X, 0, origLook.Z)
        if flatLook.Magnitude > 0.01 then
            flatLook = flatLook.Unit
            hrp.CFrame = CFrame.lookAt(restorePos, restorePos + flatLook)
        end
        if cam and origCamCFrame and useCamera then cam.CFrame = origCamCFrame end
        if gunTool.Parent == char then gunTool.Parent = backpack end
        task.spawn(startReload)
    end

    flickButton.MouseButton1Click:Connect(function()
        if not flickMoved and not flickReloading then executeFlickShoot() end
    end)

    trickshot_section:AddLabel("⚠️ Use Gun Silent Aim For It To Work")
    trickshot_section:AddToggle("Show Flick Shoot Button", function(on)
        showFlickGui = on
        if flickGui then flickGui.Enabled = on end
    end)
    trickshot_section:AddToggle("Flick Wall Check", function(on) flickWallCheckEnabled = on end)
    trickshot_section:AddToggle("Whitelist Friends", function(on) whitelistFriendsEnabled = on end)
    trickshot_section:AddDropdown("Flick Mode", {"Instant", "Smooth"}, function(choice) flickMode = choice end)
    trickshot_section:AddSlider("Smooth Flick Speed", 1, 20, flickSmoothSpeed, function(v) flickSmoothSpeed = v end)
    trickshot_section:AddSlider("Flick Shoot GUI Size", 100, 300, flickGuiSize, function(v)
        flickGuiSize = v
        if flickFrame then flickFrame.Size = UDim2.new(0, flickGuiSize, 0, flickGuiSize * (100 / 220)) end
    end)
end


-- =============================
-- PERFORMANCE OVERLAY SECTION
-- =============================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local overlayEnabled = false
local overlayScale = 50
local activeStats = {}

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
local regionLabel = createLabel("Region: Unknown")

local function getCountryFlag(countryCode)
    local flag = ""
    for i = 1, #countryCode do
        local c = countryCode:sub(i, i)
        flag = flag .. utf8.char(127397 + string.byte(c))
    end
    return flag
end

task.spawn(function()
    local success, result = pcall(function()
        local response = game:HttpGet("http://ip-api.com/json/?fields=countryCode")
        return HttpService:JSONDecode(response)
    end)
    if success and result and result.countryCode then
        local flag = getCountryFlag(result.countryCode)
        regionLabel.Text = "Region: " .. flag .. " " .. result.countryCode:upper()
        regionLabel.TextColor3 = Color3.fromRGB(0, 255, 255)
    else
        regionLabel.Text = "Region: 🌐 UN"
    end
end)

local function updateOverlayLayout()
    local scale = overlayScale / 50
    local yOffset = 0
    for _, lbl in ipairs(activeStats) do
        lbl.Position = UDim2.new(0,0,0,yOffset)
        lbl.Size = UDim2.new(1,0,0,20*scale)
        lbl.Visible = true
        yOffset = yOffset + 20*scale
    end
    mainFrame.Size = UDim2.new(0, 120*scale, 0, yOffset)
end

if perf_overlay_section then
    perf_overlay_section:AddToggle("Enable Overlay", function(on)
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

    perf_overlay_section:AddToggle("Show FPS", function(on) toggleStat(fpsLabel, on) end)
    perf_overlay_section:AddToggle("Show Ping", function(on) toggleStat(pingLabel, on) end)
    perf_overlay_section:AddToggle("Show Players in Server", function(on) toggleStat(playersLabel, on) end)
    perf_overlay_section:AddToggle("Show Region", function(on) toggleStat(regionLabel, on) end)
    perf_overlay_section:AddSlider("Overlay Scale", 1, 100, overlayScale, function(v)
        overlayScale = v
        updateOverlayLayout()
    end)
end

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

    local pingVal = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    local ping = math.floor(pingVal)
    pingLabel.Text = "Ping: "..ping.." ms"
    if ping <= 170 then pingLabel.TextColor3 = Color3.fromRGB(0,255,0)
    elseif ping <= 200 then pingLabel.TextColor3 = Color3.fromRGB(255,165,0)
    else pingLabel.TextColor3 = Color3.fromRGB(255,0,0) end

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
