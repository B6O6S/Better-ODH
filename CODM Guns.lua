local shared = odh_shared_plugins  

-- Create a new section  
local gunEffectSection = shared.AddSection("CODM Guns")  

local Players = game:GetService("Players")  
local Workspace = game:GetService("Workspace")  
local RunService = game:GetService("RunService")  

local player = Players.LocalPlayer  

-- State Management with Defaults  
local activeMode = nil -- "KRM", "HSO", "BY15", "AK117", "Locus", or nil
local customEnabled = false  

local connections = {}  
local activeParts = {}  
local soundConnections = {}  

-- Sound & Image IDs for all guns  
local KRM_SOUND_ID = "rbxassetid://97368006504538"  
local KRM_IMAGE_ID = "rbxassetid://94304455969490"  

local HSO_SOUND_ID = "rbxassetid://111847172291163"  
local HSO_IMAGE_ID = "rbxassetid://113047166963396"  

local BY15_SOUND_ID = "rbxassetid://76617339840905"  
local BY15_IMAGE_ID = "rbxassetid://129113381334409"  

local AK117_SOUND_ID = "rbxassetid://93841867819927"  
local AK117_IMAGE_ID = "rbxassetid://111808586316090"  

local LOCUS_SOUND_ID = "rbxassetid://76400730899881"  
local LOCUS_IMAGE_ID = "rbxassetid://71439057975044"  

-- Track original gun textures  
local originalTextures = {}  

-- Forward declarations for loaders  
local loadKRM, loadHSO, loadBY15, loadAK117, loadLocus  

-- Strict check to ensure we only target tools named "gun"  
local function isGunTool(obj)  
    return obj and (obj:IsA("Tool") or obj:IsA("Model")) and obj.Name:lower() == "gun"  
end  

local function cleanup()  
    local containers = {player.Backpack, player.Character}  
    for _, container in ipairs(containers) do  
        if container then  
            for _, obj in ipairs(container:GetDescendants()) do  
                if isGunTool(obj) then  
                    if originalTextures[obj] ~= nil then  
                        obj.TextureId = originalTextures[obj]  
                    end  
                end  
            end  
        end  
    end  

    for _, conn in ipairs(connections) do  
        pcall(function() conn:Disconnect() end)  
    end  
    for _, part in ipairs(activeParts) do  
        pcall(function() part:Destroy() end)  
    end  
    connections = {}  
    activeParts = {}  
end  

-- Refresh and update textures strictly for tools named "gun"  
local function refreshToolTextures()  
    if not customEnabled or not activeMode then return end  
    local targetImage  
    if activeMode == "KRM" then  
        targetImage = KRM_IMAGE_ID  
    elseif activeMode == "HSO" then  
        targetImage = HSO_IMAGE_ID  
    elseif activeMode == "BY15" then  
        targetImage = BY15_IMAGE_ID  
    elseif activeMode == "AK117" then  
        targetImage = AK117_IMAGE_ID  
    elseif activeMode == "Locus" then  
        targetImage = LOCUS_IMAGE_ID  
    end  

    local containers = {player.Backpack, player.Character}  
    for _, container in ipairs(containers) do  
        if container then  
            for _, obj in ipairs(container:GetDescendants()) do  
                if isGunTool(obj) then  
                    if not originalTextures[obj] then  
                        originalTextures[obj] = obj.TextureId  
                    end  
                    obj.TextureId = targetImage  
                end  
            end  
        end  
    end  
end  

-- Sound Overhaul Method  
local function layerSound(origSound)  
    if not customEnabled or not activeMode then return end  
    origSound.Volume = 0  

    if not soundConnections[origSound] or not soundConnections[origSound].Connected then  
        if soundConnections[origSound] then  
            pcall(function() soundConnections[origSound]:Disconnect() end)  
        end  

        soundConnections[origSound] = origSound.Played:Connect(function()  
            if not customEnabled or not activeMode then return end  
            local custom = Instance.new("Sound")  
            if activeMode == "KRM" then  
                custom.SoundId = KRM_SOUND_ID  
            elseif activeMode == "HSO" then  
                custom.SoundId = HSO_SOUND_ID  
            elseif activeMode == "BY15" then  
                custom.SoundId = BY15_SOUND_ID  
            elseif activeMode == "AK117" then  
                custom.SoundId = AK117_SOUND_ID  
            elseif activeMode == "Locus" then  
                custom.SoundId = LOCUS_SOUND_ID  
            end  
            custom.Volume = 2  
            custom.PlayOnRemove = true  
            custom.Parent = origSound.Parent  
            custom:Destroy()  
            table.insert(activeParts, custom)  
        end)  
    end  
end  

local function applySounds()  
    if not customEnabled or not activeMode then return end  
    local containers = {player.Backpack, player.Character}  
    for _, container in ipairs(containers) do  
        if container then  
            for _, obj in ipairs(container:GetDescendants()) do  
                if obj:IsA("Sound") then  
                    if obj.Name == "Reload" then  
                        obj.Volume = 0  
                    elseif obj.Name == "Gunshot" then  
                        layerSound(obj)  
                    end  
                end  
            end  
        end  
    end  
end  

local function setupLocalSound(sound)  
    if not sound:IsA("Sound") then return end  
    if sound.Name == "Reload" then  
        sound.Volume = customEnabled and 0 or 1  
    elseif sound.Name == "Gunshot" then  
        if customEnabled and activeMode then  
            layerSound(sound)  
        else  
            sound.Volume = 1  
        end  
    end  
end  

local function monitorContainerForSounds(container)  
    if not container then return end  
    for _, obj in ipairs(container:GetDescendants()) do  
        setupLocalSound(obj)  
    end  
    table.insert(connections, container.DescendantAdded:Connect(function(obj)  
        setupLocalSound(obj)  
    end))  
end  

local function setupPlayerContainers(char)  
    monitorContainerForSounds(char)  
    local bp = player:FindFirstChild("Backpack")  
    if bp then  
        monitorContainerForSounds(bp)  
    end  
end  

-- Trigger current active mode load safely  
local function triggerActiveMode()  
    if not customEnabled or not activeMode then return end  
    if activeMode == "KRM" then  
        loadKRM()  
    elseif activeMode == "HSO" then  
        loadHSO()  
    elseif activeMode == "BY15" then  
        loadBY15()  
    elseif activeMode == "AK117" then  
        loadAK117()  
    elseif activeMode == "Locus" then  
        loadLocus()  
    end  
    applySounds()  
    refreshToolTextures()  
end  

-- Visuals Loader for KRM262  
loadKRM = function()  
    activeMode = "KRM"  
    setupPlayerContainers(player.Character)  
    applySounds()  
    refreshToolTextures()  

    local IMAGE1_ID = "94304455969490"  
    local IMAGE2_ID = "111320755715910"  
    local IMAGE_SCALE = 6  
    local SEPARATION = 0.08  
    local BASE_ROTATION = CFrame.Angles(0, math.rad(90), 0)  

    local function applyVisuals(gunTool)  
        if not originalTextures[gunTool] then  
            originalTextures[gunTool] = gunTool.TextureId  
        end  
        gunTool.TextureId = KRM_IMAGE_ID  

        local handle = gunTool:FindFirstChild("Handle") or gunTool:FindFirstChildWhichIsA("BasePart")  
        if not handle then return end  

        for _, obj in ipairs(gunTool:GetDescendants()) do  
            if obj:IsA("BasePart") then  
                obj.Transparency = 1  
                obj.CanCollide = false  
            end  
        end  

        local gunSize = handle.Size * 1.5  
        local function createImage(name, imageId)  
            local part = Instance.new("Part")  
            part.Name = name  
            part.Size = Vector3.new(gunSize.X * IMAGE_SCALE, gunSize.Y * IMAGE_SCALE, 0.05)  
            part.Transparency = 1  
            part.Anchored = true  
            part.CanCollide = false  
            part.CanTouch = false  
            part.CanQuery = false  
            part.CastShadow = false  
            part.Parent = Workspace  
            table.insert(activeParts, part)  

            local surface = Instance.new("SurfaceGui")  
            surface.Face = Enum.NormalId.Front  
            surface.AlwaysOnTop = false  
            surface.LightInfluence = 0  
            surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud  
            surface.PixelsPerStud = 100  
            surface.Parent = part  

            local image = Instance.new("ImageLabel")  
            image.BackgroundTransparency = 1  
            image.BorderSizePixel = 0  
            image.Size = UDim2.fromScale(1, 1)  
            image.Image = "rbxassetid://" .. imageId  
            image.ScaleType = Enum.ScaleType.Fit  
            image.Parent = surface  
            return part  
        end  

        local img1 = createImage("KRM_Img1", IMAGE1_ID)  
        local img2 = createImage("KRM_Img2", IMAGE2_ID)  

        local renderConn  
        renderConn = RunService.RenderStepped:Connect(function()  
            local isEquipped = gunTool.Parent == player.Character  
            if not customEnabled or activeMode ~= "KRM" or not handle or not handle.Parent or not gunTool.Parent then  
                pcall(function() img1:Destroy() end)  
                pcall(function() img2:Destroy() end)  
                if renderConn then renderConn:Disconnect() end  
                return  
            end  

            if isEquipped then  
                img1.Transparency = 1  
                img2.Transparency = 1  
                local cf = handle.CFrame  
                img1.CFrame = cf * BASE_ROTATION * CFrame.new(0, 0, -(SEPARATION / 2))  
                img2.CFrame = cf * BASE_ROTATION * CFrame.Angles(0, math.rad(180), 0) * CFrame.new(0, 0, -(SEPARATION / 2))  
            else  
                img1.CFrame = CFrame.new(0, -9999, 0)  
                img2.CFrame = CFrame.new(0, -9999, 0)  
            end  
        end)  
        table.insert(connections, renderConn)  
    end  

    local function watchLocalContainer(container)  
        if not container then return end  
        local function checkItem(obj)  
            if isGunTool(obj) then  
                applyVisuals(obj)  
            end  
        end  
        for _, obj in ipairs(container:GetDescendants()) do checkItem(obj) end  
        table.insert(connections, container.DescendantAdded:Connect(checkItem))  
    end  

    if player.Character then watchLocalContainer(player.Character) end  
    local bp = player:FindFirstChild("Backpack")  
    if bp then watchLocalContainer(bp) end  
end  

-- Visuals Loader for HS0405  
loadHSO = function()  
    activeMode = "HSO"  
    setupPlayerContainers(player.Character)  
    applySounds()  
    refreshToolTextures()  

    local IMAGE1_ID = "113047166963396"  
    local IMAGE2_ID = "112064279195812"  
    local IMAGE_SCALE = 9  
    local SEPARATION = 0.08  
    local BASE_ROTATION = CFrame.Angles(0, math.rad(90), 0)  

    local function applyVisuals(gunTool)  
        if not originalTextures[gunTool] then  
            originalTextures[gunTool] = gunTool.TextureId  
        end  
        gunTool.TextureId = HSO_IMAGE_ID  

        local handle = gunTool:FindFirstChild("Handle") or gunTool:FindFirstChildWhichIsA("BasePart")  
        if not handle then return end  

        for _, obj in ipairs(gunTool:GetDescendants()) do  
            if obj:IsA("BasePart") then  
                obj.Transparency = 1  
                obj.CanCollide = false  
            end  
        end  

        local gunSize = handle.Size * 1.5  
        local function createImage(name, imageId)  
            local part = Instance.new("Part")  
            part.Name = name  
            part.Size = Vector3.new(gunSize.X * IMAGE_SCALE, gunSize.Y * IMAGE_SCALE, 0.05)  
            part.Transparency = 1  
            part.Anchored = true  
            part.CanCollide = false  
            part.CanTouch = false  
            part.CanQuery = false  
            part.CastShadow = false  
            part.Parent = Workspace  
            table.insert(activeParts, part)  

            local surface = Instance.new("SurfaceGui")  
            surface.Face = Enum.NormalId.Front  
            surface.AlwaysOnTop = false  
            surface.LightInfluence = 0  
            surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud  
            surface.PixelsPerStud = 100  
            surface.Parent = part  

            local image = Instance.new("ImageLabel")  
            image.BackgroundTransparency = 1  
            image.BorderSizePixel = 0  
            image.Size = UDim2.fromScale(1, 1)  
            image.Image = "rbxassetid://" .. imageId  
            image.ScaleType = Enum.ScaleType.Fit  
            image.Parent = surface  
            return part  
        end  

        local img1 = createImage("HSO_Img1", IMAGE1_ID)  
        local img2 = createImage("HSO_Img2", IMAGE2_ID)  

        local renderConn  
        renderConn = RunService.RenderStepped:Connect(function()  
            local isEquipped = gunTool.Parent == player.Character  
            if not customEnabled or activeMode ~= "HSO" or not handle or not handle.Parent or not gunTool.Parent then  
                pcall(function() img1:Destroy() end)  
                pcall(function() img2:Destroy() end)  
                if renderConn then renderConn:Disconnect() end  
                return  
            end  

            if isEquipped then  
                img1.Transparency = 1  
                img2.Transparency = 1  
                local cf = handle.CFrame  
                img1.CFrame = cf * BASE_ROTATION * CFrame.new(0, 0, -(SEPARATION / 2))  
                img2.CFrame = cf * BASE_ROTATION * CFrame.Angles(0, math.rad(180), 0) * CFrame.new(0, 0, -(SEPARATION / 2))  
            else  
                img1.CFrame = CFrame.new(0, -9999, 0)  
                img2.CFrame = CFrame.new(0, -9999, 0)  
            end  
        end)  
        table.insert(connections, renderConn)  
    end  

    local function watchLocalContainer(container)  
        if not container then return end  
        local function checkItem(obj)  
            if isGunTool(obj) then  
                applyVisuals(obj)  
            end  
        end  
        for _, obj in ipairs(container:GetDescendants()) do checkItem(obj) end  
        table.insert(connections, container.DescendantAdded:Connect(checkItem))  
    end  

    if player.Character then watchLocalContainer(player.Character) end  
    local bp = player:FindFirstChild("Backpack")  
    if bp then watchLocalContainer(bp) end  
end  

-- Visuals Loader for BY15 - Boba Blaster  
loadBY15 = function()  
    activeMode = "BY15"  
    setupPlayerContainers(player.Character)  
    applySounds()  
    refreshToolTextures()  

    local IMAGE1_ID = "129113381334409"  
    local IMAGE2_ID = "96589231246361"  
    local IMAGE_SCALE = 6  
    local SEPARATION = 0.08  
    local BASE_ROTATION = CFrame.Angles(0, math.rad(90), 0)  

    local function applyVisuals(gunTool)  
        if not originalTextures[gunTool] then  
            originalTextures[gunTool] = gunTool.TextureId  
        end  
        gunTool.TextureId = BY15_IMAGE_ID  

        local handle = gunTool:FindFirstChild("Handle") or gunTool:FindFirstChildWhichIsA("BasePart")  
        if not handle then return end  

        for _, obj in ipairs(gunTool:GetDescendants()) do  
            if obj:IsA("BasePart") then  
                obj.Transparency = 1  
                obj.CanCollide = false  
            end  
        end  

        local gunSize = handle.Size * 1.5  
        local function createImage(name, imageId)  
            local part = Instance.new("Part")  
            part.Name = name  
            part.Size = Vector3.new(gunSize.X * IMAGE_SCALE, gunSize.Y * IMAGE_SCALE, 0.05)  
            part.Transparency = 1  
            part.Anchored = true  
            part.CanCollide = false  
            part.CanTouch = false  
            part.CanQuery = false  
            part.CastShadow = false  
            part.Parent = Workspace  
            table.insert(activeParts, part)  

            local surface = Instance.new("SurfaceGui")  
            surface.Face = Enum.NormalId.Front  
            surface.AlwaysOnTop = false  
            surface.LightInfluence = 0  
            surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud  
            surface.PixelsPerStud = 100  
            surface.Parent = part  

            local image = Instance.new("ImageLabel")  
            image.BackgroundTransparency = 1  
            image.BorderSizePixel = 0  
            image.Size = UDim2.fromScale(1, 1)  
            image.Image = "rbxassetid://" .. imageId  
            image.ScaleType = Enum.ScaleType.Fit  
            image.Parent = surface  
            return part  
        end  

        local img1 = createImage("BY15_Img1", IMAGE1_ID)  
        local img2 = createImage("BY15_Img2", IMAGE2_ID)  

        local renderConn  
        renderConn = RunService.RenderStepped:Connect(function()  
            local isEquipped = gunTool.Parent == player.Character  
            if not customEnabled or activeMode ~= "BY15" or not handle or not handle.Parent or not gunTool.Parent then  
                pcall(function() img1:Destroy() end)  
                pcall(function() img2:Destroy() end)  
                if renderConn then renderConn:Disconnect() end  
                return  
            end  

            if isEquipped then  
                img1.Transparency = 1  
                img2.Transparency = 1  
                local cf = handle.CFrame  
                img1.CFrame = cf * BASE_ROTATION * CFrame.new(0, 0, -(SEPARATION / 2))  
                img2.CFrame = cf * BASE_ROTATION * CFrame.Angles(0, math.rad(180), 0) * CFrame.new(0, 0, -(SEPARATION / 2))  
            else  
                img1.CFrame = CFrame.new(0, -9999, 0)  
                img2.CFrame = CFrame.new(0, -9999, 0)  
            end  
        end)  
        table.insert(connections, renderConn)  
    end  

    local function watchLocalContainer(container)  
        if not container then return end  
        local function checkItem(obj)  
            if isGunTool(obj) then  
                applyVisuals(obj)  
            end  
        end  
        for _, obj in ipairs(container:GetDescendants()) do checkItem(obj) end  
        table.insert(connections, container.DescendantAdded:Connect(checkItem))  
    end  

    if player.Character then watchLocalContainer(player.Character) end  
    local bp = player:FindFirstChild("Backpack")  
    if bp then watchLocalContainer(bp) end  
end  

-- Visuals Loader for AK117 - Grim Ending  
loadAK117 = function()  
    activeMode = "AK117"  
    setupPlayerContainers(player.Character)  
    applySounds()  
    refreshToolTextures()  

    local IMAGE1_ID = "111808586316090"  
    local IMAGE2_ID = "138254940403316"  
    local IMAGE_SCALE = 6  
    local SEPARATION = 0.08  
    local BASE_ROTATION = CFrame.Angles(0, math.rad(90), 0)  

    local function applyVisuals(gunTool)  
        if not originalTextures[gunTool] then  
            originalTextures[gunTool] = gunTool.TextureId  
        end  
        gunTool.TextureId = AK117_IMAGE_ID  

        local handle = gunTool:FindFirstChild("Handle") or gunTool:FindFirstChildWhichIsA("BasePart")  
        if not handle then return end  

        for _, obj in ipairs(gunTool:GetDescendants()) do  
            if obj:IsA("BasePart") then  
                obj.Transparency = 1  
                obj.CanCollide = false  
            end  
        end  

        local gunSize = handle.Size * 1.5  
        local function createImage(name, imageId)  
            local part = Instance.new("Part")  
            part.Name = name  
            part.Size = Vector3.new(gunSize.X * IMAGE_SCALE, gunSize.Y * IMAGE_SCALE, 0.05)  
            part.Transparency = 1  
            part.Anchored = true  
            part.CanCollide = false  
            part.CanTouch = false  
            part.CanQuery = false  
            part.CastShadow = false  
            part.Parent = Workspace  
            table.insert(activeParts, part)  

            local surface = Instance.new("SurfaceGui")  
            surface.Face = Enum.NormalId.Front  
            surface.AlwaysOnTop = false  
            surface.LightInfluence = 0  
            surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud  
            surface.PixelsPerStud = 100  
            surface.Parent = part  

            local image = Instance.new("ImageLabel")  
            image.BackgroundTransparency = 1  
            image.BorderSizePixel = 0  
            image.Size = UDim2.fromScale(1, 1)  
            image.Image = "rbxassetid://" .. imageId  
            image.ScaleType = Enum.ScaleType.Fit  
            image.Parent = surface  
            return part  
        end  

        local img1 = createImage("AK117_Img1", IMAGE1_ID)  
        local img2 = createImage("AK117_Img2", IMAGE2_ID)  

        local renderConn  
        renderConn = RunService.RenderStepped:Connect(function()  
            local isEquipped = gunTool.Parent == player.Character  
            if not customEnabled or activeMode ~= "AK117" or not handle or not handle.Parent or not gunTool.Parent then  
                pcall(function() img1:Destroy() end)  
                pcall(function() img2:Destroy() end)  
                if renderConn then renderConn:Disconnect() end  
                return  
            end  

            if isEquipped then  
                img1.Transparency = 1  
                img2.Transparency = 1  
                local cf = handle.CFrame  
                img1.CFrame = cf * BASE_ROTATION * CFrame.new(0, 0, -(SEPARATION / 2))  
                img2.CFrame = cf * BASE_ROTATION * CFrame.Angles(0, math.rad(180), 0) * CFrame.new(0, 0, -(SEPARATION / 2))  
            else  
                img1.CFrame = CFrame.new(0, -9999, 0)  
                img2.CFrame = CFrame.new(0, -9999, 0)  
            end  
        end)  
        table.insert(connections, renderConn)  
    end  

    local function watchLocalContainer(container)  
        if not container then return end  
        local function checkItem(obj)  
            if isGunTool(obj) then  
                applyVisuals(obj)  
            end  
        end  
        for _, obj in ipairs(container:GetDescendants()) do checkItem(obj) end  
        table.insert(connections, container.DescendantAdded:Connect(checkItem))  
    end  

    if player.Character then watchLocalContainer(player.Character) end  
    local bp = player:FindFirstChild("Backpack")  
    if bp then watchLocalContainer(bp) end  
end  

-- Visuals Loader for Locus - Electron  
loadLocus = function()  
    activeMode = "Locus"  
    setupPlayerContainers(player.Character)  
    applySounds()  
    refreshToolTextures()  

    local IMAGE1_ID = "71439057975044"  
    local IMAGE2_ID = "113075933742938"  
    local IMAGE_SCALE = 8.5  
    local SEPARATION = 0.08  
    local BASE_ROTATION = CFrame.Angles(0, math.rad(90), 0)  

    local function applyVisuals(gunTool)  
        if not originalTextures[gunTool] then  
            originalTextures[gunTool] = gunTool.TextureId  
        end  
        gunTool.TextureId = LOCUS_IMAGE_ID  

        local handle = gunTool:FindFirstChild("Handle") or gunTool:FindFirstChildWhichIsA("BasePart")  
        if not handle then return end  

        for _, obj in ipairs(gunTool:GetDescendants()) do  
            if obj:IsA("BasePart") then  
                obj.Transparency = 1  
                obj.CanCollide = false  
            end  
        end  

        local gunSize = handle.Size * 1.5  
        local function createImage(name, imageId)  
            local part = Instance.new("Part")  
            part.Name = name  
            part.Size = Vector3.new(gunSize.X * IMAGE_SCALE, gunSize.Y * IMAGE_SCALE, 0.05)  
            part.Transparency = 1  
            part.Anchored = true  
            part.CanCollide = false  
            part.CanTouch = false  
            local function createImage(name, imageId)  
            end  
            part.CanQuery = false  
            part.CastShadow = false  
            part.Parent = Workspace  
            table.insert(activeParts, part)  

            local surface = Instance.new("SurfaceGui")  
            surface.Face = Enum.NormalId.Front  
            surface.AlwaysOnTop = false  
            surface.LightInfluence = 0  
            surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud  
            surface.PixelsPerStud = 100  
            surface.Parent = part  

            local image = Instance.new("ImageLabel")  
            image.BackgroundTransparency = 1  
            image.BorderSizePixel = 0  
            image.Size = UDim2.fromScale(1, 1)  
            image.Image = "rbxassetid://" .. imageId  
            image.ScaleType = Enum.ScaleType.Fit  
            image.Parent = surface  
            return part  
        end  

        local img1 = createImage("Locus_Img1", IMAGE1_ID)  
        local img2 = createImage("Locus_Img2", IMAGE2_ID)  

        local renderConn  
        renderConn = RunService.RenderStepped:Connect(function()  
            local isEquipped = gunTool.Parent == player.Character  
            if not customEnabled or activeMode ~= "Locus" or not handle or not handle.Parent or not gunTool.Parent then  
                pcall(function() img1:Destroy() end)  
                pcall(function() img2:Destroy() end)  
                if renderConn then renderConn:Disconnect() end  
                return  
            end  

            if isEquipped then  
                img1.Transparency = 1  
                img2.Transparency = 1  
                local cf = handle.CFrame  
                img1.CFrame = cf * BASE_ROTATION * CFrame.new(0, 0, -(SEPARATION / 2))  
                img2.CFrame = cf * BASE_ROTATION * CFrame.Angles(0, math.rad(180), 0) * CFrame.new(0, 0, -(SEPARATION / 2))  
            else  
                img1.CFrame = CFrame.new(0, -9999, 0)  
                img2.CFrame = CFrame.new(0, -9999, 0)  
            end  
        end)  
        table.insert(connections, renderConn)  
    end  

    local function watchLocalContainer(container)  
        if not container then return end  
        local function checkItem(obj)  
            if isGunTool(obj) then  
                applyVisuals(obj)  
            end  
        end  
        for _, obj in ipairs(container:GetDescendants()) do checkItem(obj) end  
        table.insert(connections, container.DescendantAdded:Connect(checkItem))  
    end  

    if player.Character then watchLocalContainer(player.Character) end  
    local bp = player:FindFirstChild("Backpack")  
    if bp then watchLocalContainer(bp) end  
end  

-- Global Auto-Refresh Listener for Respawn / Tool Pickups
player.CharacterAdded:Connect(function(newChar)
    task.spawn(function()
        -- Wait a short moment for backpack and character tools to load on respawn
        task.wait(0.5)
        if customEnabled and activeMode then
            cleanup()
            triggerActiveMode()
        end
        
        -- Watch backpack changes dynamically for new tool additions
        local bp = player:FindFirstChild("Backpack")
        if bp then
            bp.DescendantAdded:Connect(function(obj)
                if isGunTool(obj) and customEnabled and activeMode then
                    task.wait(0.1)
                    triggerActiveMode()
                end
            end)
        end
        
        newChar.ChildAdded:Connect(function(obj)
            if isGunTool(obj) and customEnabled and activeMode then
                task.wait(0.1)
                triggerActiveMode()
            end
        end)
    end)
end)

-- Also monitor existing backpack for items added anytime
local initialBp = player:FindFirstChild("Backpack")
if initialBp then
    initialBp.DescendantAdded:Connect(function(obj)
        if isGunTool(obj) and customEnabled and activeMode then
            task.wait(0.1)
            triggerActiveMode()
        end
    end)
end  

-- Loop for continuous sync  
RunService.Heartbeat:Connect(function()  
    if customEnabled and activeMode then  
        applySounds()  
        refreshToolTextures()  
    end  
end)  

-- UI Layout Configuration  

-- 1. Toggle CODM Gun  
gunEffectSection:AddToggle("Toggle codm gun", function(bool)  
    customEnabled = bool  
    if bool then  
        triggerActiveMode()  
    else  
        cleanup()  
        activeMode = nil  
    end  
end)  

-- 2. Select Gun Dropdown  
local gunOptions = {  
    "KRM262 - Glorious Blaze",  
    "HS0405 - Songstress",  
    "BY15 - Boba Blaster",  
    "AK117 - Grim Ending",  
    "Locus - Electron"  
}  

gunEffectSection:AddDropdown("Select Gun", gunOptions, function(selected)  
    cleanup()  
    if string.find(selected, "KRM262") then  
        activeMode = "KRM"  
    elseif string.find(selected, "HS0405") then  
        activeMode = "HSO"  
    elseif string.find(selected, "BY15") then  
        activeMode = "BY15"  
    elseif string.find(selected, "AK117") then  
        activeMode = "AK117"  
    elseif string.find(selected, "Locus") then  
        activeMode = "Locus"  
    end  

    if customEnabled then  
        triggerActiveMode()  
    end  
end)
