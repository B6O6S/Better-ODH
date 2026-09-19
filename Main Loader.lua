-- Better ODH: consolidated new-API loader, 2026-09-19.
-- Original features/authorship: B6O6S / Better-ODH and Better-Odh-tabs.
-- All module sources are embedded below. No loadstring, GetTab dependency,
-- load_from_github_url, or remote Lua downloads are needed at runtime.
-- Each module has its own function scope and initialization task.
local host = odh_shared_plugins
if not host or type(host.CreateTab) ~= "function" then
    warn("[Better ODH] Load this file through the current Overdrive H plugin menu.")
    return
end
local RUNTIME_KEY = "BetterODH_ModularLoader_20260919"
if type(_G[RUNTIME_KEY]) == "table" then
    if type(host.Notify) == "function" then
        pcall(host.Notify, "Better ODH is already loaded. Restart the game before replacing this loader.", 5)
    end
    return
end
local tabOK, rootTab = pcall(host.CreateTab, "Better ODH", "/B6O6S/Better-ODH/refs/heads/main/Better%20ODH%20Logo")
if not tabOK or not rootTab then
    warn("[Better ODH] CreateTab failed: " .. tostring(rootTab))
    return
end
local runtime = { modules = {}, pending = 0, ready = 0, failed = 0, version = "2026-09-19 modular + persistent preferences" }
_G[RUNTIME_KEY] = runtime
local definitions = {}
local function notify(text, seconds)
    if type(host.Notify) == "function" then pcall(host.Notify, text, seconds or 4) end
end
local function traceback(err)
    if debug and debug.traceback then return debug.traceback(tostring(err), 2) end
    return tostring(err)
end
local function setStatus(record, state, detail)
    record.state, record.detail = state, detail
    if record.statusLabel and type(record.statusLabel.SetValue) == "function" then
        pcall(function() record.statusLabel:SetValue(state .. (detail and (" | " .. detail) or "")) end)
    end
end
-- Durable preferences. Save on change, not on exit (mobile apps may be killed).
local preferences = (function()
    local P = {file="BetterODH_settings.json", data={version=1, controls={}}, status="Not saved"}
    local env={}
    if type(getgenv)=="function" then
        local ok,result=pcall(getgenv)
        if ok and type(result)=="table" then env=result end
    end
    local read=type(readfile)=="function" and readfile or env.readfile
    local write=type(writefile)=="function" and writefile or env.writefile
    local exists=type(isfile)=="function" and isfile or env.isfile
    local okHttp,http=pcall(function() return game:GetService("HttpService") end)
    P.available=type(read)=="function" and type(write)=="function" and okHttp and http~=nil
    local reported={}
    local function report(message)
        if reported[message] then return end
        reported[message]=true
        warn("[Better ODH Save] " .. message)
        notify("Better ODH: settings save/load unavailable. See console.",5)
    end
    function P.Finite(v)
        return type(v)=="number" and v==v and v>-math.huge and v<math.huge
    end
    function P.Get(section,key)
        local group=P.data.controls[section]
        if type(group)=="table" then return group[key] end
    end
    function P.Save()
        if not P.available then return false end
        local ok,err=pcall(function() write(P.file,http:JSONEncode(P.data)) end)
        if not ok then
            P.status="Write error"
            report("Cannot write " .. P.file .. ": " .. tostring(err))
            return false
        end
        P.status="Saved"
        return true
    end
    function P.Set(section,key,value)
        if typeof(value)=="Color3" then value={color3={value.R,value.G,value.B}} end
        if type(P.data.controls[section])~="table" then P.data.controls[section]={} end
        P.data.controls[section][key]=value
        return P.Save()
    end
    if not P.available then
        P.status="Unavailable"
        report("readfile/writefile or HttpService is unavailable; preferences cannot survive a new session.")
        return P
    end
    local found=true
    if type(exists)=="function" then
        local ok,result=pcall(exists,P.file)
        if ok then found=result end
    end
    if found then
        local ok,text=pcall(read,P.file)
        if ok then
            local decoded,data=pcall(function() return http:JSONDecode(text) end)
            if decoded and type(data)=="table" and data.version==1 and type(data.controls)=="table" then
                P.data=data
                P.status="Loaded"
            else
                P.status="Invalid file"
                report("Invalid settings file. It is kept unchanged until you change a preference.")
            end
        elseif type(exists)=="function" then
            P.status="Read error"
            report("Cannot read " .. P.file .. ": " .. tostring(text))
        end
    end
    -- Do not overwrite a missing/unreadable/corrupt file just because UI initialized.
    return P
end)()
runtime.preferences=preferences

local function contextFor(record)
    local ctx = { section=nil, initializing=true, controls=0, errors={}, settings={}, muted=false, restoring=false }
    local raw=record.rawSection
    local section={}
    ctx.section=section
    local function failure(name,err)
        local message=tostring(name) .. ": " .. tostring(err)
        if not ctx.errors[message] then
            ctx.errors[message]=true
            warn("[Better ODH / " .. record.name .. "] " .. message)
            notify(record.name .. ": action/restore failed; see console.",4)
        end
    end
    local function validate(entry,value)
        local kind=entry.kind
        if kind=="AddToggle" then
            if type(value)=="boolean" then return value end
        elseif kind=="AddSlider" then
            if preferences.Finite(value) then return math.clamp(value,entry.minimum,entry.maximum) end
        elseif kind=="AddTextBox" then
            if type(value)=="string" then return value:sub(1,2048) end
        elseif kind=="AddDropdown" then
            for _,item in ipairs(entry.items) do if value==item then return value end end
        elseif kind=="AddColorpicker" then
            if typeof(value)=="Color3" then return value end
            if type(value)=="table" and type(value.color3)=="table" then
                local c=value.color3
                if preferences.Finite(c[1]) and preferences.Finite(c[2]) and preferences.Finite(c[3]) then
                    return Color3.new(math.clamp(c[1],0,1),math.clamp(c[2],0,1),math.clamp(c[3],0,1))
                end
            end
        end
        return nil
    end
    local function textHint(entry,value)
        if entry.hint and type(entry.hint.SetValue)=="function" then
            -- AddTextBox returns void in the documented API. Show the restored
            -- backing value in a separate label rather than inventing a setter.
            pcall(function()
                entry.hint:SetValue("Saved " .. entry.name .. ": " .. tostring(value):gsub("[\r\n]"," "):sub(1,120))
            end)
        end
    end
    local function invoke(entry,value)
        local ok,result=pcall(entry.callback,value)
        if not ok then failure(entry.name,result) end
        return ok,result
    end
    local function applySaved(entry,value)
        local prior=ctx.muted
        ctx.muted=true
        local ok,err=pcall(function()
            if entry.kind=="AddToggle" then
                if entry.visual~=value then
                    assert(type(entry.handle)=="function","AddToggle did not return a toggle closure")
                    entry.handle()
                end
            elseif entry.kind=="AddSlider" then entry.handle:SetValue(value)
            elseif entry.kind=="AddColorpicker" then entry.handle:SetRGBValue(value)
            elseif entry.kind=="AddDropdown" then entry.handle:Select(value) end
        end)
        ctx.muted=prior
        if not ok then failure(entry.name,err); return false end
        local applied=invoke(entry,value)
        if applied then entry.value=value; textHint(entry,value) end
        return applied
    end
    local callbackPositions={
        AddToggle=2,AddSlider=5,AddColorpicker=3,AddDropdown=3,
        AddPlayerDropdown=2,AddTextBox=2,AddButton=2,AddKeybind=3,
    }
    local persistent={AddToggle=true,AddSlider=true,AddColorpicker=true,AddDropdown=true,AddTextBox=true}
    local phase={AddTextBox=1,AddSlider=2,AddColorpicker=2,AddDropdown=3,AddToggle=4}
    for method,position in pairs(callbackPositions) do
        section[method]=function(_, ...)
            local args=table.pack(...)
            assert(type(args[position])=="function",method .. ": missing callback")
            local entry={kind=method,name=tostring(args[1]),callback=args[position],visual=false}
            entry.key=method .. " / " .. entry.name
            if method=="AddSlider" then entry.minimum,entry.maximum=args[2],args[3] end
            if method=="AddDropdown" then entry.items=args[2] end
            if persistent[method] then ctx.settings[#ctx.settings+1]=entry end
            args[position]=function(...)
                local value=...
                if method=="AddToggle" then entry.visual=(value==true) end
                if ctx.initializing or ctx.muted then return end
                if persistent[method] then
                    value=validate(entry,value)
                    if value==nil then return end
                    entry.value=value
                    -- Persist intent immediately even if an in-game callback yields.
                    if not ctx.restoring then preferences.Set(record.name,entry.key,value) end
                    textHint(entry,value)
                    return select(2,invoke(entry,value))
                end
                -- Button presses, player selections and key presses are actions,
                -- not preferences. Never save/replay them on rejoin.
                local ok,result=pcall(entry.callback,...)
                if not ok then failure(entry.name,result) end
                return ok and result or nil
            end
            entry.handle=raw[method](raw,table.unpack(args,1,args.n))
            ctx.controls=ctx.controls+1
            if method=="AddTextBox" then
                pcall(function() entry.hint=raw:AddLabel("Saved " .. entry.name .. ": --",true) end)
            end
            if method=="AddDropdown" then
                -- Track later item-list refreshes (e.g. inventory arriving after login).
                local real=entry.handle
                local proxy={}
                function proxy:Select(value) return real:Select(value) end
                function proxy:ChangeItems(items)
                    entry.items=items
                    local muted=ctx.muted;ctx.muted=true
                    local changed,result=pcall(function() return real:ChangeItems(items) end)
                    ctx.muted=muted
                    if not changed then error(result) end
                    if entry.pending~=nil and not ctx.initializing then
                        local value=validate(entry,entry.pending)
                        if value~=nil then
                            entry.pending=nil
                            local prior=ctx.restoring;ctx.restoring=true
                            applySaved(entry,value)
                            ctx.restoring=prior
                        end
                    end
                    return result
                end
                return proxy
            end
            return entry.handle
        end
    end
    function ctx.Restore()
        ctx.restoring=true
        -- Text/custom IDs, then numeric/color parameters, then choices, and
        -- finally enabled modes. Never replace absent preferences with defaults.
        for pass=1,4 do
            local i=1
            while i<=#ctx.settings do
                local entry=ctx.settings[i]
                if phase[entry.kind]==pass then
                    local stored=preferences.Get(record.name,entry.key)
                    local value=validate(entry,stored)
                    if value~=nil then
                        applySaved(entry,value)
                    elseif entry.kind=="AddDropdown" and type(stored)=="string" then
                        entry.pending=stored -- preserve unavailable inventory selections on disk
                    end
                end
                i=i+1
            end
        end
        ctx.restoring=false
    end
    function section:AddLabel(...)
        local result=raw:AddLabel(...);ctx.controls=ctx.controls+1;return result
    end
    function section:AddParagraph(...)
        local result=raw:AddParagraph(...);ctx.controls=ctx.controls+1;return result
    end
    local shared=setmetatable({}, {__index=host})
    local tabProxy={}
    function tabProxy:AddSection(name,subtitle) return section end
    shared.AddSection=function() return section end
    shared.CreateTab=function() return tabProxy end
    shared.GetTab=function() return tabProxy end
    shared.Notify=function(text,seconds) if not ctx.restoring then notify(text,seconds) end end
    ctx.shared,ctx.tab=shared,tabProxy
    ctx.toyRemote={InvokeServer=function(_, ...)
        local storage=game:GetService("ReplicatedStorage")
        local remotes=storage:FindFirstChild("Remotes")
        local extras=remotes and remotes:FindFirstChild("Extras")
        local remote=extras and extras:FindFirstChild("ReplicateToy")
        if not remote then
            notify("ReplicateToy is not available yet in this game/server.",3)
            return nil
        end
        return remote:InvokeServer(...)
    end}
    return ctx
end

-- ================================================================
-- Module: Customizations
-- Source: User attachment: Main loader.lua.txt
definitions[#definitions + 1] = { name = "Customizations", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

local custom_section = ctx.section
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
        blur.Size + (targetBlur * 4 - blur.Size) * math.clamp(dt * 20, 0, 1), 
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
end }

-- ================================================================
-- Module: UI & Fonts
-- Source: User attachment: Main loader.lua.txt
definitions[#definitions + 1] = { name = "UI & Fonts", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

local ui_section = ctx.section
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
-- Resolve the trade remote only when used; missing remotes must not block the rest of the menu.

ui_section:AddToggle("Disable Trade Requests", function(on)
    tradeRequestsEnabled = not on
    local trade = ReplicatedStorage:FindFirstChild("Trade")
    local tradeEvent = trade and trade:FindFirstChild("SetRequestsEnabled")
    if tradeEvent then
        tradeEvent:FireServer(tradeRequestsEnabled)
    else
        shared.Notify("Trade requests are unavailable in this game/server.", 3)
    end
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
end }

-- ================================================================
-- Module: Performance & FPS
-- Source: User attachment: Main loader.lua.txt
definitions[#definitions + 1] = { name = "Performance & FPS", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

local perf_fps_section = ctx.section
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
end }

-- ================================================================
-- Module: Trickshot & Movement
-- Source: User attachment: Main loader.lua.txt
definitions[#definitions + 1] = { name = "Trickshot & Movement", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

local trickshot_section = ctx.section
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

local finalToyEventRef = ctx.toyRemote
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

local toyEvent = ctx.toyRemote
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
    timerTokenBomb = timerTokenBomb + 1
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
end }

-- ================================================================
-- Module: Performance Overlay
-- Source: User attachment: Main loader.lua.txt
definitions[#definitions + 1] = { name = "Performance Overlay", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

local perf_overlay_section = ctx.section
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
    frameCount = frameCount + 1
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
end }

-- ================================================================
-- Module: Troll (FE)
-- Source: https://raw.githubusercontent.com/B6O6S/Better-Odh-tabs/main/Troll%20(FE).lua | Git blob 1a0403f274d3d8cf2d5fc446da0b038a0780845d
definitions[#definitions + 1] = { name = "Troll (FE)", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

-- ===================================== -- PART 1: TROLL (FE) + BACKSHOTS -- ===================================== 
if not odh_shared_plugins then
    warn("ODH Shared Plugins environment not found! Load the main hub first.")
    return
end

local pluginTab = odh_shared_plugins.AddSection("Troll (FE)") 

local Players = game:GetService("Players") 
local LocalPlayer = Players.LocalPlayer 
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera

-- ===================================== -- GUI SETUP (DUAL KNIFE) -- ===================================== 
local playerGui = LocalPlayer:WaitForChild("PlayerGui") 

local function createKnifeGui(name, imageId) 
    local screenGui = Instance.new("ScreenGui") 
    screenGui.Name = name .. "GUI" 
    screenGui.ResetOnSpawn = false 
    screenGui.Parent = playerGui 
    screenGui.Enabled = false 

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

local function playDualKnifeAnimation(char) 
    if not char then return end 
    local humanoid = char:FindFirstChildOfClass("Humanoid") 
    if humanoid then 
        local anim1 = Instance.new("Animation") 
        anim1.AnimationId = "rbxassetid://2467577524" 
        local track1 = humanoid:LoadAnimation(anim1) 
        track1:Play() 
        task.delay(1, function() 
            local anim2 = Instance.new("Animation") 
            anim2.AnimationId = "rbxassetid://2470501967" 
            local track2 = humanoid:LoadAnimation(anim2) 
            track2:Play() 
        end) 
    end 
end 

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

-- ===================================== -- BACKSHOTS FEATURE -- ===================================== 
local backshotsGui = Instance.new("ScreenGui")
backshotsGui.Name = "ToggleMovementGui"
backshotsGui.ResetOnSpawn = false
pcall(function()
    backshotsGui.Parent = CoreGui
end)
if not backshotsGui.Parent then
    backshotsGui.Parent = playerGui
end
backshotsGui.Enabled = false

local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "backshots"
toggleBtn.Size = UDim2.new(0, 120, 0, 50)
toggleBtn.Position = UDim2.new(0.1, 0, 0.1, 0)
toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.TextSize = 14
toggleBtn.Font = Enum.Font.SourceSansBold
toggleBtn.Text = "backshots: OFF"
toggleBtn.Parent = backshotsGui

-- Draggable Logic
local dragging, dragInput, dragStart, startPos
toggleBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = toggleBtn.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

toggleBtn.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        toggleBtn.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

local function setNoPlayerCollision(enabled)
    local character = LocalPlayer.Character
    if not character then return end
    
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= LocalPlayer and otherPlayer.Character then
            for _, part in ipairs(otherPlayer.Character:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = not enabled
                end
            end
        end
    end
end

local active = false
local connection = nil
local centerPos = nil
local walkDir = 1
local landDelayTick = 0
local wasInAir = false

local movementSpeed = 0.25
local maxDistance = 0.1

local function toggleBackshots(state)
    active = state
    local character = LocalPlayer.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if active then
        toggleBtn.Text = "backshots: ON"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)

        if rootPart and humanoid then
            centerPos = rootPart.Position
            walkDir = 1
            humanoid.AutoRotate = false
            landDelayTick = 0
            wasInAir = false

            connection = RunService.RenderStepped:Connect(function()
                if not character or not character.Parent or humanoid.Health <= 0 then
                    return
                end

                setNoPlayerCollision(true)

                local lookVector = Camera.CFrame.LookVector
                local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
                if flatLook.Magnitude > 0 then
                    flatLook = flatLook.Unit
                else
                    flatLook = rootPart.CFrame.LookVector
                    flatLook = Vector3.new(flatLook.X, 0, flatLook.Z).Unit
                end

                local state = humanoid:GetState()
                local inAir = (state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.FallingDown)

                if inAir then
                    wasInAir = true
                    centerPos = rootPart.Position
                    walkDir = 1
                    landDelayTick = tick() + 0.1
                elseif wasInAir and not inAir then
                    wasInAir = false
                end

                if humanoid.MoveDirection.Magnitude > 0 then
                    centerPos = rootPart.Position
                    walkDir = 1
                end

                if tick() < landDelayTick then
                    centerPos = rootPart.Position
                    return
                end

                local lockedLookCFrame = CFrame.lookAt(centerPos, centerPos + flatLook)
                local currentPos = rootPart.Position
                local displacement = (currentPos - centerPos):Dot(flatLook)

                if displacement >= maxDistance then
                    walkDir = -1
                elseif displacement <= -maxDistance then
                    walkDir = 1
                end

                local targetPosition = lockedLookCFrame.Position + (centerPos - lockedLookCFrame.Position) + (flatLook * displacement)

                local raycastParams = RaycastParams.new()
                raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                raycastParams.FilterDescendantsInstances = {character}
                
                local raycastResult = workspace:Raycast(centerPos + Vector3.new(0, 2, 0), (targetPosition - centerPos), raycastParams)
                if raycastResult then
                    targetPosition = raycastResult.Position - (flatLook * 0.2)
                end

                local goalCFrame = lockedLookCFrame + (targetPosition - centerPos)
                rootPart.CFrame = rootPart.CFrame:Lerp(goalCFrame, movementSpeed)
                
                humanoid:Move(flatLook * walkDir, false)
            end)
        end
    else
        toggleBtn.Text = "backshots: OFF"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)

        if connection then
            connection:Disconnect()
            connection = nil
        end

        setNoPlayerCollision(false)

        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.AutoRotate = true
                humanoid:Move(Vector3.zero, true)
            end
        end
        centerPos = nil
    end
end

toggleBtn.MouseButton1Click:Connect(function()
    toggleBackshots(not active)
end)

pluginTab:AddToggle("Show Backshots Button", function(on)
    backshotsGui.Enabled = on
    if not on and active then
        toggleBackshots(false)
    end
end)

pluginTab:AddKeybind("Backshots Keybind", "B", function()
    if backshotsGui.Enabled then
        toggleBackshots(not active)
    end
end)

pluginTab:AddSlider("Backshots Speed", 1, 100, 25, function(v)
    movementSpeed = v / 100
end)

pluginTab:AddSlider("Backshots Distance", 1, 50, 10, function(v)
    maxDistance = v / 100
end)

pluginTab:AddSlider("Backshots GUI Size", 50, 250, 120, function(v)
    local numV = tonumber(v) or 120
    toggleBtn.Size = UDim2.new(0, numV, 0, math.floor(numV * (50/120)))
    toggleBtn.TextSize = math.clamp(math.floor(numV / 8), 10, 24)
end)


-- ===================================== -- PART 2: DELTA RC CAR CORE LOGIC & SOUNDS -- ===================================== 
local rcEnabled = false
local dashcamEnabled = false
local customSpeedEnabled = false
local customSoundsEnabled = false
local speedometerEnabled = false
local sitOnCarEnabled = false
local freezeWhenUsingEnabled = false
local sitHeightOffset = 2.15
local maxSpeedVal = 80
local horsePowerVal = 500

local globalEngineConnection = nil
local lastPosition = nil
local lastVelCalcTime = tick()
local trackedCarInstance = nil
local toolActivationConn = nil
local wasTrackingCar = false
local isSpectatingPlayer = false

local speedGui = Instance.new("ScreenGui")
speedGui.Name = "RCCarSpeedometerCompact"
speedGui.ResetOnSpawn = false
pcall(function() speedGui.Parent = CoreGui end)
if not speedGui.Parent then speedGui.Parent = playerGui end
speedGui.Enabled = false

local speedValueLabel = Instance.new("TextLabel")
speedValueLabel.Size = UDim2.new(0, 110, 0, 36)
speedValueLabel.Position = UDim2.new(0.5, -55, 0.75, 0)
speedValueLabel.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
speedValueLabel.BackgroundTransparency = 0.25
speedValueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
speedValueLabel.TextSize = 16
speedValueLabel.Font = Enum.Font.GothamBold
speedValueLabel.Text = "0 km/h"
speedValueLabel.Active = true
speedValueLabel.Draggable = true
speedValueLabel.Parent = speedGui

local labelCorner = Instance.new("UICorner")
labelCorner.CornerRadius = UDim.new(0, 10)
labelCorner.Parent = speedValueLabel

local labelStroke = Instance.new("UIStroke")
labelStroke.Color = Color3.fromRGB(0, 242, 254)
labelStroke.Transparency = 0.4
labelStroke.Thickness = 1.2
labelStroke.Parent = speedValueLabel

local idleSound = Instance.new("Sound")
idleSound.SoundId = "rbxassetid://98076378627817"
idleSound.Looped = true
idleSound.Volume = 0
idleSound.RollOffMaxDistance = 100
idleSound.RollOffMinDistance = 10

local drivingSound = Instance.new("Sound")
drivingSound.SoundId = "rbxassetid://140713709172971"
drivingSound.Looped = true
drivingSound.Volume = 0
drivingSound.RollOffMaxDistance = 100
drivingSound.RollOffMinDistance = 10

pcall(function()
    idleSound.Parent = CoreGui
    drivingSound.Parent = CoreGui
end)
if not idleSound.Parent then
    idleSound.Parent = playerGui
    drivingSound.Parent = playerGui
end

pcall(function()
    idleSound:Play()
    drivingSound:Play()
end)

-- External spectate detector (detects if user is viewing another player's character)
Camera:GetPropertyChangedSignal("CameraSubject"):Connect(function()
    local subject = Camera.CameraSubject
    if subject and subject:IsA("Humanoid") then
        local char = subject.Parent
        if char and char ~= LocalPlayer.Character then
            local p = Players:GetPlayerFromCharacter(char)
            if p then
                isSpectatingPlayer = true
                return
            end
        end
    end
    isSpectatingPlayer = false
end)

local function resetCameraToPlayer()
    if isSpectatingPlayer then return end
    Camera.CameraType = Enum.CameraType.Custom
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        Camera.CameraSubject = hum
    end
end

local function getSpawnTool()
    local char = LocalPlayer.Character
    if char then
        local t = char:FindFirstChild("RCCar26")
        if t and t:IsA("Tool") then return t end
    end
    local userFolder = workspace:FindFirstChild(LocalPlayer.Name)
    if userFolder then
        local fTool = userFolder:FindFirstChild("RCCar26")
        if fTool and fTool:IsA("Tool") then return fTool end
    end
    return nil
end

local function isToolEquippedInHand()
    local char = LocalPlayer.Character
    if not char then return false end
    local tool = char:FindFirstChild("RCCar26")
    return tool ~= nil and tool:IsA("Tool")
end

local function isOwnedCar(carModel)
    if not carModel or not carModel:IsA("Model") or not carModel.Parent then return false end
    return carModel.Name == LocalPlayer.Name 
        or (carModel:FindFirstChild("Owner") and carModel.Owner.Value == LocalPlayer)
        or (carModel:GetAttribute("Owner") == LocalPlayer.UserId)
        or (carModel.Name == "RCCar" and getSpawnTool() ~= nil)
end

local function findNearbyOwnedCar()
    local char = LocalPlayer.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil end

    local carsFolder = workspace:FindFirstChild("RCCars")
    if carsFolder then
        for _, car in ipairs(carsFolder:GetChildren()) do
            if car:IsA("Model") and isOwnedCar(car) then
                local primary = car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart")
                if primary then
                    local dist = (primary.Position - rootPart.Position).Magnitude
                    if dist <= 8 then
                        return car
                    end
                end
            end
        end
    end
    return nil
end

local function setupToolTracking()
    if toolActivationConn then toolActivationConn:Disconnect() end
    local tool = getSpawnTool()
    if tool then
        toolActivationConn = tool.Activated:Connect(function()
            task.wait(0.03)
            if not trackedCarInstance or not trackedCarInstance.Parent then
                local nearbyCar = findNearbyOwnedCar()
                if nearbyCar then
                    trackedCarInstance = nearbyCar
                end
            end
        end)
    end
end

local function updateSoundParent(targetPart)
    pcall(function()
        if targetPart and targetPart.Parent then
            if idleSound.Parent ~= targetPart then
                idleSound.Parent = targetPart
                drivingSound.Parent = targetPart
            end
        else
            if idleSound.Parent ~= CoreGui then
                idleSound.Parent = CoreGui
                drivingSound.Parent = CoreGui
            end
        end
    end)
end

local function evaluateGlobalEngineState()
    local needsEngine = rcEnabled or dashcamEnabled or customSpeedEnabled or customSoundsEnabled or speedometerEnabled

    if needsEngine then
        if not globalEngineConnection then
            setupToolTracking()
            lastPosition = nil
            lastVelCalcTime = tick()

            globalEngineConnection = RunService.RenderStepped:Connect(function(dt)
                pcall(function()
                    if isSpectatingPlayer then return end

                    if trackedCarInstance and (not trackedCarInstance.Parent or not isOwnedCar(trackedCarInstance)) then
                        trackedCarInstance = nil
                        resetCameraToPlayer()
                    end

                    if not trackedCarInstance and isToolEquippedInHand() then
                        local found = findNearbyOwnedCar()
                        if found then
                            trackedCarInstance = found
                        end
                    end

                    local targetCar = trackedCarInstance
                    if targetCar and targetCar.Parent and isOwnedCar(targetCar) then
                        local targetPart = targetCar.PrimaryPart or targetCar:FindFirstChildWhichIsA("BasePart")
                        local currentSpeedStuds = 0

                        if targetPart and not targetPart.Anchored then
                            updateSoundParent(targetPart)
                            local currentPos = targetPart.Position
                            local measuredVelMag = targetPart.AssemblyLinearVelocity.Magnitude

                            if lastPosition then
                                local deltaT = math.clamp(tick() - lastVelCalcTime, 0.001, 0.1)
                                local dist = (currentPos - lastPosition).Magnitude
                                local rawVelMag = dist / deltaT

                                if dist > 0.02 then
                                    local moveDir = (currentPos - lastPosition).Unit
                                    local filterList = {targetCar, LocalPlayer.Character}
                                    local result
                                    while true do
                                        local rayParams = RaycastParams.new()
                                        rayParams.FilterDescendantsInstances = filterList
                                        rayParams.FilterType = Enum.RaycastFilterType.Exclude
                                        local tempRes = workspace:Raycast(currentPos, moveDir * 3, rayParams)
                                        if tempRes and tempRes.Instance and not tempRes.Instance.CanCollide then
                                            table.insert(filterList, tempRes.Instance)
                                        else
                                            result = tempRes
                                            break
                                        end
                                    end

                                    if not result then
                                        if customSpeedEnabled then
                                            local hpMultiplier = math.clamp(horsePowerVal / 500, 0.2, 2.0)
                                            local targetVelMag = math.min(rawVelMag * hpMultiplier, maxSpeedVal)
                                            targetPart.AssemblyLinearVelocity = moveDir * targetVelMag
                                            currentSpeedStuds = math.floor(targetVelMag + 0.5)
                                        else
                                            currentSpeedStuds = math.floor(math.max(measuredVelMag, rawVelMag) + 0.5)
                                        end
                                    else
                                        currentSpeedStuds = math.floor(math.max(measuredVelMag, math.min(rawVelMag, targetPart.AssemblyLinearVelocity.Magnitude)) + 0.5)
                                    end
                                else
                                    currentSpeedStuds = math.floor(measuredVelMag + 0.5)
                                end
                            else
                                currentSpeedStuds = math.floor(measuredVelMag + 0.5)
                            end
                            lastPosition = currentPos
                            lastVelCalcTime = tick()

                            speedGui.Enabled = speedometerEnabled
                            local kmhVal = math.floor(currentSpeedStuds * 1.60934 + 0.5)
                            speedValueLabel.Text = string.format("%d km/h", kmhVal)

                            local alpha = math.clamp(currentSpeedStuds / math.max(maxSpeedVal, 10), 0, 1)
                            if alpha > 0.88 then
                                labelStroke.Color = Color3.fromRGB(255, 45, 85)
                            else
                                labelStroke.Color = Color3.fromRGB(0, 242, 254)
                            end

                            if customSoundsEnabled then
                                if currentSpeedStuds > 0.8 then
                                    idleSound.Volume = 0
                                    drivingSound.Volume = math.clamp(currentSpeedStuds / 25, 0.25, 1.0)
                                    local drivingSpeedVal = math.clamp(0.6 + (currentSpeedStuds / math.max(maxSpeedVal, 10)) * 1.4, 0.6, 2.2)
                                    pcall(function() drivingSound.PlaybackSpeed = drivingSpeedVal end)
                                else
                                    idleSound.Volume = 0.5
                                    drivingSound.Volume = 0
                                end
                            else
                                idleSound.Volume = 0
                                drivingSound.Volume = 0
                            end

                            if rcEnabled and not isSpectatingPlayer then
                                Camera.CameraType = Enum.CameraType.Custom
                                local humObj = targetCar:FindFirstChildOfClass("Humanoid")
                                Camera.CameraSubject = humObj or targetCar
                            end

                            if dashcamEnabled and not isSpectatingPlayer then
                                Camera.CameraType = Enum.CameraType.Scriptable
                                Camera.CFrame = targetPart.CFrame * CFrame.new(0, 0.9, -0.4)
                            elseif not rcEnabled and not isSpectatingPlayer then
                                resetCameraToPlayer()
                            end
                        end
                    else
                        updateSoundParent(nil)
                        speedGui.Enabled = false
                        idleSound.Volume = 0
                        drivingSound.Volume = 0
                        lastPosition = nil
                        trackedCarInstance = nil
                        resetCameraToPlayer()
                    end
                end)
            end)
        end
    else
        if globalEngineConnection then
            globalEngineConnection:Disconnect()
            globalEngineConnection = nil
        end
        if toolActivationConn then
            toolActivationConn:Disconnect()
            toolActivationConn = nil
        end
        updateSoundParent(nil)
        speedGui.Enabled = false
        idleSound.Volume = 0
        drivingSound.Volume = 0
        lastPosition = nil
        trackedCarInstance = nil
        resetCameraToPlayer()
    end
end


-- ===================================== -- PART 3: RC CAR SIT, FREEZE & UI CONTROLS -- ===================================== 
local sitConnection = nil
local freezeConnection = nil

local function safeAntiFlingJump()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local rootPart = char:FindFirstChild("HumanoidRootPart")
    
    if hum and rootPart then
        pcall(function()
            rootPart.AssemblyLinearVelocity = Vector3.zero
            rootPart.AssemblyAngularVelocity = Vector3.zero
        end)
        hum.Sit = false
        hum.PlatformStand = false
        rootPart.Anchored = false
    end
end

local function evaluateSitState()
    if sitOnCarEnabled then
        if not sitConnection then
            setupToolTracking()
            sitConnection = RunService.RenderStepped:Connect(function(dt)
                pcall(function()
                    if not sitOnCarEnabled or isSpectatingPlayer then return end

                    if not isToolEquippedInHand() then
                        if wasTrackingCar then
                            safeAntiFlingJump()
                            wasTrackingCar = false
                        end
                        trackedCarInstance = nil
                        resetCameraToPlayer()
                        return
                    end

                    if not trackedCarInstance or not trackedCarInstance.Parent or not isOwnedCar(trackedCarInstance) then
                        local found = findNearbyOwnedCar()
                        if found then
                            trackedCarInstance = found
                        else
                            trackedCarInstance = nil
                            resetCameraToPlayer()
                        end
                    end

                    local targetCar = trackedCarInstance
                    if targetCar and targetCar.Parent and isOwnedCar(targetCar) then
                        wasTrackingCar = true
                        local targetPart = targetCar.PrimaryPart or targetCar:FindFirstChildWhichIsA("BasePart")
                        local char = LocalPlayer.Character
                        local hum = char and char:FindFirstChildOfClass("Humanoid")
                        local rootPart = char and char:FindFirstChild("HumanoidRootPart")

                        if hum and rootPart and targetPart then
                            hum.PlatformStand = false
                            rootPart.Anchored = false
                            hum.Sit = true
                            local lookAheadCFrame = targetPart.CFrame + (targetPart.AssemblyLinearVelocity * math.min(dt, 0.025))
                            local goalCFrame = lookAheadCFrame * CFrame.new(0, sitHeightOffset, 0)
                            rootPart.CFrame = rootPart.CFrame:Lerp(goalCFrame, math.clamp(dt * 30, 0.45, 1.0))
                            rootPart.AssemblyLinearVelocity = targetPart.AssemblyLinearVelocity
                        end
                    else
                        if wasTrackingCar then
                            safeAntiFlingJump()
                            wasTrackingCar = false
                        end
                        resetCameraToPlayer()
                    end
                end)
            end)
        end
    else
        if sitConnection then
            sitConnection:Disconnect()
            sitConnection = nil
        end
        wasTrackingCar = false
        safeAntiFlingJump()
        resetCameraToPlayer()
    end
end

local function evaluateFreezeState()
    if freezeWhenUsingEnabled then
        if not freezeConnection then
            setupToolTracking()
            freezeConnection = RunService.RenderStepped:Connect(function()
                pcall(function()
                    if not freezeWhenUsingEnabled then return end
                    
                    if sitOnCarEnabled and wasTrackingCar then
                        local char = LocalPlayer.Character
                        local rootPart = char and char:FindFirstChild("HumanoidRootPart")
                        local hum = char and char:FindFirstChildOfClass("Humanoid")
                        if rootPart and rootPart:IsA("BasePart") and rootPart.Anchored then
                            rootPart.Anchored = false
                        end
                        if hum and hum.PlatformStand then
                            hum.PlatformStand = false
                        end
                        return
                    end

                    local char = LocalPlayer.Character
                    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    
                    if not isToolEquippedInHand() then
                        trackedCarInstance = nil
                        if rootPart and rootPart:IsA("BasePart") and rootPart.Anchored then
                            rootPart.Anchored = false
                        end
                        if hum and hum.PlatformStand then
                            hum.PlatformStand = false
                        end
                        resetCameraToPlayer()
                        return
                    end

                    if not trackedCarInstance or not trackedCarInstance.Parent or not isOwnedCar(trackedCarInstance) then
                        local found = findNearbyOwnedCar()
                        if found then
                            trackedCarInstance = found
                        else
                            trackedCarInstance = nil
                            resetCameraToPlayer()
                        end
                    end

                    if trackedCarInstance and trackedCarInstance.Parent and isOwnedCar(trackedCarInstance) then
                        if rootPart and rootPart:IsA("BasePart") then
                            rootPart.Anchored = true
                        end
                        if hum then
                            hum.PlatformStand = true
                        end
                    else
                        if rootPart and rootPart:IsA("BasePart") and rootPart.Anchored then
                            rootPart.Anchored = false
                        end
                        if hum and hum.PlatformStand then
                            hum.PlatformStand = false
                        end
                        resetCameraToPlayer()
                    end
                end)
            end)
        end
    else
        if freezeConnection then
            freezeConnection:Disconnect()
            freezeConnection = nil
        end
        local char = LocalPlayer.Character
        local rootPart = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if rootPart and rootPart:IsA("BasePart") then
            rootPart.Anchored = false
        end
        if hum and hum.PlatformStand then
            hum.PlatformStand = false
        end
        resetCameraToPlayer()
    end
end

pluginTab:AddToggle("Spectate RCCar", function(on)
    rcEnabled = on
    if not on and dashcamEnabled then
        dashcamEnabled = false
    end
    evaluateGlobalEngineState()
end)

pluginTab:AddToggle("Sit on RCCar", function(on)
    sitOnCarEnabled = on
    evaluateSitState()
    if not on then
        trackedCarInstance = nil
        wasTrackingCar = false
        safeAntiFlingJump()
        resetCameraToPlayer()
    end
end)

pluginTab:AddToggle("Freeze When Using RCCar", function(on)
    freezeWhenUsingEnabled = on
    evaluateFreezeState()
end)

pluginTab:AddSlider("Sit Height Offset", 10, 500, 215, function(v)
    sitHeightOffset = (tonumber(v) or 215) / 100
end)

pluginTab:AddToggle("Dashcam Mode", function(on)
    dashcamEnabled = on
    if on and rcEnabled then
        rcEnabled = false
    end
    evaluateGlobalEngineState()
end)

pluginTab:AddToggle("Custom RCCar sound", function(on)
    customSoundsEnabled = on
    evaluateGlobalEngineState()
end)

pluginTab:AddToggle("Custom RCCar Speed", function(on)
    customSpeedEnabled = on
    evaluateGlobalEngineState()
end)

pluginTab:AddToggle("RCCar Speedometer", function(on)
    speedometerEnabled = on
    evaluateGlobalEngineState()
end)

pluginTab:AddSlider("Max Speed", 1, 200, 80, function(v)
    maxSpeedVal = tonumber(v) or 80
end)

pluginTab:AddSlider("Horse Power ( HP )", 10, 1000, 500, function(v)
    horsePowerVal = tonumber(v) or 500
end)



end }

-- ================================================================
-- Module: Sky changer
-- Source: https://raw.githubusercontent.com/B6O6S/Better-Odh-tabs/main/Sky%20changer | Git blob a79e4ac1c49aea2d573b665c4b65679ea09dd051
definitions[#definitions + 1] = { name = "Sky changer", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Lighting = game:GetService("Lighting")
local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")

local odh_shared_plugins = odh_shared_plugins -- make sure your shared plugin object exists

-- Store original sky if it exists
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

-- Part 2: Skybox Changer
local skySection = odh_shared_plugins.AddSection("Sky Changer")

-- Sky presets
local skyboxPresets = {
    ["Default"] = function()
        for _, obj in ipairs(Lighting:GetChildren()) do if obj:IsA("Sky") then obj:Destroy() end end
        if originalSkyProps then
            local sky = Instance.new("Sky")
            for prop, val in pairs(originalSkyProps) do
                sky[prop] = val
            end
            sky.Parent = Lighting
        end
        Lighting.Ambient = Color3.fromRGB(127, 127, 127)
        Lighting.Brightness = 2
        Lighting.OutdoorAmbient = Color3.fromRGB(127, 127, 127)
    end,

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

-- Dropdown population (forcing "Default" to be first)
local skyKeys = {"Default"}
for k, _ in pairs(skyboxPresets) do
    if k ~= "Default" then
        table.insert(skyKeys, k)
    end
end
-- Sort the rest alphabetically while keeping "Default" at index 1
local remainingKeys = {}
for i = 2, #skyKeys do table.insert(remainingKeys, skyKeys[i]) end
table.sort(remainingKeys)
for i, v in ipairs(remainingKeys) do skyKeys[i + 1] = v end

local selectedSkybox = skyKeys[1]

skySection:AddDropdown("Predefined Skyboxes", skyKeys, function(value)
    selectedSkybox = value
end)

skySection:AddButton("Apply Selected Skybox", function()
    if selectedSkybox and skyboxPresets[selectedSkybox] then
        skyboxPresets[selectedSkybox]()
        if shared and shared.Notify then
            shared.Notify("Applied "..selectedSkybox, 1)
        end
    else
        if shared and shared.Notify then
            shared.Notify("No skybox selected or preset missing.", 3)
        end
    end
end)

end }

-- ================================================================
-- Module: Privacy and security
-- Source: https://raw.githubusercontent.com/B6O6S/Better-Odh-tabs/main/Privacy%20and%20security | Git blob 95aef180e30dd8770419e88959733ab78b30ea09
definitions[#definitions + 1] = { name = "Privacy and security", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

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

end }

-- ================================================================
-- Module: Legit Speed Glitch
-- Source: https://raw.githubusercontent.com/B6O6S/Better-Odh-tabs/main/Legit%20Speed%20Glitch | Git blob 70f3ad6650b03f7f3746a21e2bbfd6e32fa86f58
definitions[#definitions + 1] = { name = "Legit Speed Glitch", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

local speedSection = odh_shared_plugins.AddSection("Legit Speed Glitch")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------

local uiEnabled = false
local enabled = false
local sideSpeed = 150
local moveInput = 0
local isJumping = false
local selectedEmoteId
local toggleSize = 80

local onlyWorkSideways = false

local Character
local Humanoid
local HRP

local screenGui
local toggleButton

local customEmoteId = nil

----------------------------------------------------------------
-- CHARACTER BINDING
----------------------------------------------------------------

local function bindCharacter(char)
    Character = char
    Humanoid = char:WaitForChild("Humanoid")
    HRP = char:WaitForChild("HumanoidRootPart")

    isJumping = false

    Humanoid.Jumping:Connect(function()
        isJumping = true
    end)

    Humanoid.StateChanged:Connect(function(_, state)
        if state == Enum.HumanoidStateType.Landed then
            isJumping = false
        end
    end)
end

-- Do not delay UI creation until the player respawns.
if LocalPlayer.Character then task.spawn(bindCharacter, LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(bindCharacter)

----------------------------------------------------------------
-- INPUT
----------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end

    if input.KeyCode == Enum.KeyCode.A then
        moveInput = -1
    elseif input.KeyCode == Enum.KeyCode.D then
        moveInput = 1
    end
end)

UserInputService.InputEnded:Connect(function(input, gp)
    if gp then return end

    if input.KeyCode == Enum.KeyCode.A
        or input.KeyCode == Enum.KeyCode.D then
        moveInput = 0
    end
end)

----------------------------------------------------------------
-- EMOTE SYSTEM
----------------------------------------------------------------

local function playEmote(id)
    if not Character then return end

    local hum = Character:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    local ok = pcall(function()
        hum:PlayEmoteAndGetAnimTrackById(id)
    end)

    if not ok then
        local anim = Instance.new("Animation")
        anim.AnimationId = "rbxassetid://" .. id

        local track = hum:LoadAnimation(anim)

        if track then
            track:Play()
        end
    end
end

----------------------------------------------------------------
-- MOVEMENT LOOP
----------------------------------------------------------------

RunService.Heartbeat:Connect(function()
    if not enabled then return end
    if not Character or not Humanoid or not HRP then return end
    if not isJumping then return end

    local moveDirection = Humanoid.MoveDirection

    if moveDirection.Magnitude <= 0 then
        return
    end

    local directionToUse

    ------------------------------------------------------------
    -- ONLY WORK SIDEWAYS
    ------------------------------------------------------------

    if onlyWorkSideways then

        -- Get camera's horizontal right direction
        local right = Camera.CFrame.RightVector
        local flatRight = Vector3.new(
            right.X,
            0,
            right.Z
        )

        if flatRight.Magnitude <= 0 then
            return
        end

        flatRight = flatRight.Unit

        -- Check how much the player is moving sideways
        local sidewaysAmount = flatRight:Dot(moveDirection)

        -- Only activate when movement is actually sideways
        if math.abs(sidewaysAmount) < 0.35 then
            return
        end

        -- Determine left/right direction
        local sideDirection

        if sidewaysAmount > 0 then
            sideDirection = 1
        else
            sideDirection = -1
        end

        directionToUse = flatRight * sideDirection

    ------------------------------------------------------------
    -- NORMAL MODE
    ------------------------------------------------------------

    else

        -- When Only Work Sideways is OFF,
        -- use whatever direction the player is moving.
        directionToUse = moveDirection.Unit

    end

    ------------------------------------------------------------
    -- APPLY SPEED
    ------------------------------------------------------------

    HRP.Velocity =
        directionToUse * sideSpeed
        + Vector3.new(0, HRP.Velocity.Y, 0)
end)

----------------------------------------------------------------
-- EMOTES
----------------------------------------------------------------

local emotes = {
    ["Moonwalk"] = "79127989560307",
    ["Happier Jump"] = "15610015346",
    ["Bouncy Twirl"] = "14353423348",
    ["Flex Walk"] = "15506506103"
}

----------------------------------------------------------------
-- UI FUNCTIONS
----------------------------------------------------------------

local function updateButtonVisual()
    if not toggleButton then return end

    toggleButton.BackgroundColor3 =
        enabled
        and Color3.fromRGB(0, 200, 0)
        or Color3.fromRGB(200, 0, 0)
end

function createToggleButton()

    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")

    if not playerGui then
        return
    end

    if screenGui and toggleButton then
        return
    end

    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "SpeedGlitchUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    toggleButton = Instance.new("TextButton")

    toggleButton.Size = UDim2.new(
        0,
        toggleSize,
        0,
        toggleSize
    )

    toggleButton.Position = UDim2.new(
        0.5,
        -(toggleSize / 2),
        0.7,
        0
    )

    toggleButton.BackgroundColor3 =
        Color3.fromRGB(200, 0, 0)

    toggleButton.TextColor3 =
        Color3.fromRGB(255, 255, 255)

    toggleButton.TextScaled = true
    toggleButton.Text = "Speed Glitch"
    toggleButton.BorderSizePixel = 0
    toggleButton.AutoButtonColor = false
    toggleButton.Parent = screenGui

    local stroke = Instance.new("UIStroke")

    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = toggleButton

    local corner = Instance.new("UICorner")

    corner.CornerRadius = UDim.new(0, 0)
    corner.Parent = toggleButton

    toggleButton.Active = true
    toggleButton.Draggable = true

    toggleButton.MouseButton1Click:Connect(function()

        enabled = not enabled

        updateButtonVisual()

        if enabled and selectedEmoteId then
            playEmote(selectedEmoteId)
        end

    end)

    updateButtonVisual()
end

function destroyToggleButton()

    if screenGui then
        screenGui:Destroy()
    end

    screenGui = nil
    toggleButton = nil
    enabled = false
end

----------------------------------------------------------------
-- UI CONTROLS
----------------------------------------------------------------

speedSection:AddToggle("Enable Speed Glitch UI", function(v)

    uiEnabled = v

    if v then
        createToggleButton()
    else
        destroyToggleButton()
    end

end)

----------------------------------------------------------------
-- ONLY WORK SIDEWAYS
----------------------------------------------------------------

speedSection:AddToggle("Only Work Sideways", function(v)

    onlyWorkSideways = v

end)

----------------------------------------------------------------
-- SIDE SPEED
----------------------------------------------------------------

speedSection:AddSlider(
    "Side Speed",
    10,
    1000,
    sideSpeed,
    function(v)
        sideSpeed = v
    end
)

----------------------------------------------------------------
-- TOGGLE SIZE
----------------------------------------------------------------

speedSection:AddSlider(
    "Toggle Size",
    40,
    150,
    toggleSize,
    function(v)

        toggleSize = v

        if toggleButton then

            toggleButton.Size = UDim2.new(
                0,
                toggleSize,
                0,
                toggleSize
            )

            toggleButton.Position = UDim2.new(
                0.5,
                -(toggleSize / 2),
                0.7,
                0
            )

        end

    end
)

----------------------------------------------------------------
-- DROPDOWN
----------------------------------------------------------------

speedSection:AddDropdown("Select Emote", {

    "Moonwalk",
    "Happier Jump",
    "Bouncy Twirl",
    "Flex Walk",
    "Custom"

}, function(choice)

    if choice == "Custom" then
        selectedEmoteId = customEmoteId
    else
        selectedEmoteId = emotes[choice]
    end

end)

----------------------------------------------------------------
-- CUSTOM EMOTE
----------------------------------------------------------------

speedSection:AddTextBox("Custom Emote ID", function(text)

    if text and text ~= "" then

        customEmoteId = text
        selectedEmoteId = text

    end

end)

----------------------------------------------------------------
-- AUTO UI RECOVERY LOOP
----------------------------------------------------------------

task.spawn(function()

    while true do

        task.wait(1)

        if uiEnabled then

            local playerGui =
                LocalPlayer:FindFirstChild("PlayerGui")

            if playerGui
                and (
                    not screenGui
                    or not screenGui.Parent
                    or not toggleButton
                )
            then

                destroyToggleButton()
                createToggleButton()

            end

        end

    end

end)

end }

-- ================================================================
-- Module: Gun sound Changer
-- Source: https://raw.githubusercontent.com/B6O6S/Better-Odh-tabs/main/Gun%20sound%20Changer | Git blob 75550c4df0baf4148f11b4dc2f9a16f00f34842f
definitions[#definitions + 1] = { name = "Gun sound Changer", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

-- =============================
-- GUN SOUND CHANGER
-- SHOOT DETECTION ONLY
-- =============================

local shared = odh_shared_plugins
local gunSoundSection = shared.AddSection("Gun Sound Changer")

-- =============================
-- SOUND OPTIONS
-- =============================

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
    "miskeen (B6O6S)|71767902510649",
    "Custom|0"
}

-- =============================
-- SAVED SETTINGS
-- =============================

if getgenv().GunSound_SavedId == nil then
    getgenv().GunSound_SavedId = "rbxassetid://10209803"
end

if getgenv().GunSound_SavedName == nil then
    getgenv().GunSound_SavedName = "Default"
end

if getgenv().GunSound_CustomId == nil then
    getgenv().GunSound_CustomId = ""
end

if getgenv().GunSound_Enabled == nil then
    getgenv().GunSound_Enabled = false
end

if getgenv().GunSound_Volume == nil then
    getgenv().GunSound_Volume = 1
end

if getgenv().GunSound_MuteReload == nil then
    getgenv().GunSound_MuteReload = false
end

if getgenv().GunSound_PlayAllFE == nil then
    getgenv().GunSound_PlayAllFE = false
end

local selectedSoundId = getgenv().GunSound_SavedId
local lastSelected = getgenv().GunSound_SavedName
local customTextboxId = getgenv().GunSound_CustomId
local customEnabled = getgenv().GunSound_Enabled
local soundVolume = getgenv().GunSound_Volume
local muteReloadEnabled = getgenv().GunSound_MuteReload
local playAllFEEnabled = getgenv().GunSound_PlayAllFE

-- =============================
-- SERVICES
-- =============================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

-- =============================
-- CONNECTIONS
-- =============================

local connections = {}
local reloadConnections = {}
local processedSounds = {}

-- =============================
-- TEST SOUND
-- =============================

local function playSound(soundId, volume)
    if not soundId or soundId == "" then
        return
    end

    local soundObj = Instance.new("Sound")
    soundObj.SoundId = soundId
    soundObj.Volume = volume or 1
    soundObj.PlayOnRemove = true
    soundObj.Parent = workspace
    soundObj:Destroy()
end

-- =============================
-- GET EQUIPPED TOOL
-- =============================

local function getEquippedTool()
    local character = LocalPlayer.Character

    if not character then
        return nil
    end

    for _, object in ipairs(character:GetChildren()) do
        if object:IsA("Tool") then
            return object
        end
    end

    return nil
end

-- =============================
-- CHECK WEAPON
-- =============================

local function hasWeaponRole()
    local character = LocalPlayer.Character

    if not character then
        return false
    end

    local equippedTool = getEquippedTool()

    if not equippedTool then
        return false
    end

    local toolName = string.lower(equippedTool.Name)

    if toolName == "gun"
        or toolName == "revolver"
        or toolName == "weapon"
        or toolName == "sheriff" then

        return true
    end

    -- Check if the equipped tool contains a shooting sound
    for _, object in ipairs(equippedTool:GetDescendants()) do
        if object:IsA("Sound") then

            local soundName = string.lower(object.Name)

            if soundName == "shoot"
                or soundName == "fire"
                or soundName == "gunshot" then

                return true
            end
        end
    end

    -- Check PlayerData
    local playerData = ReplicatedStorage:FindFirstChild("PlayerData")

    if not playerData then
        playerData = LocalPlayer:FindFirstChild("PlayerData")
    end

    if playerData then

        local role = playerData:FindFirstChild("Role")

        if not role then
            role = playerData:FindFirstChild("CurrentRole")
        end

        if role and role:IsA("StringValue") then

            local value = string.lower(role.Value)

            if value == "sheriff"
                or value == "hero"
                or value == "gun" then

                return true
            end
        end
    end

    return false
end

-- =============================
-- VALID SHOOT SOUND
-- =============================

local function isValidShootSound(sound)

    if not sound then
        return false
    end

    if not sound:IsA("Sound") then
        return false
    end

    -- Exact names only
    local name = string.lower(sound.Name)

    if name ~= "shoot"
        and name ~= "fire"
        and name ~= "gunshot" then

        return false
    end

    -- Must have an equipped weapon
    local equippedTool = getEquippedTool()

    if not equippedTool then
        return false
    end

    -- The shooting sound must actually be inside
    -- the currently equipped tool
    if not sound:IsDescendantOf(equippedTool) then
        return false
    end

    -- Must have a sound ID
    if not sound.SoundId or sound.SoundId == "" then
        return false
    end

    -- Must actually have the weapon role
    if not hasWeaponRole() then
        return false
    end

    return true
end

-- =============================
-- MUTE RELOAD
-- =============================

local function checkReloadSound(sound)

    if not muteReloadEnabled then
        return
    end

    local soundId = sound.SoundId

    if soundId and string.find(soundId, "4753414199") then

        sound.Volume = 0

        if reloadConnections[sound] then
            reloadConnections[sound]:Disconnect()
        end

        reloadConnections[sound] =
            sound:GetPropertyChangedSignal("Volume"):Connect(function()

                if muteReloadEnabled then
                    sound.Volume = 0
                end

            end)
    end
end

-- =============================
-- LAYER CUSTOM SOUND
-- =============================

local function layerSound(originalSound)

    if connections[originalSound] then
        connections[originalSound]:Disconnect()
        connections[originalSound] = nil
    end

    connections[originalSound] =
        originalSound.Played:Connect(function()

            -- Custom sound must be enabled
            if not customEnabled then
                return
            end

            -- Must have a selected sound
            if not selectedSoundId or selectedSoundId == "" then
                return
            end

            -- =================================
            -- IMPORTANT:
            -- ONLY CONTINUE IF ACTUAL SHOOTING
            -- WAS DETECTED
            -- =================================

            if not isValidShootSound(originalSound) then
                return
            end

            -- Mute original shooting sound
            pcall(function()
                originalSound.Volume = 0
            end)

            -- Get numeric ID
            local pureId = string.match(selectedSoundId, "%d+")

            if not pureId then
                return
            end

            local assetUrl =
                "https://www.roblox.com/asset/?id=" .. pureId

            -- Find PlaySong remote
            local remotes = ReplicatedStorage:FindFirstChild("Remotes")
            local inventory = nil
            local playSongRemote = nil

            if remotes then
                inventory = remotes:FindFirstChild("Inventory")
            end

            if inventory then
                playSongRemote = inventory:FindFirstChild("PlaySong")
            end

            -- =============================
            -- PLAY FOR ALL
            -- =============================

            local effectiveVolume = soundVolume

            if playAllFEEnabled and playSongRemote then

                pcall(function()
                    playSongRemote:FireServer(assetUrl)
                end)

                effectiveVolume = 0
            end

            -- =============================
            -- LOCAL CUSTOM SOUND
            -- =============================

            local custom = Instance.new("Sound")

            custom.SoundId = selectedSoundId
            custom.Volume = effectiveVolume
            custom.Parent = originalSound.Parent

            custom:Play()

            -- =============================
            -- CLEANUP
            -- =============================

            custom.Ended:Connect(function()

                if playAllFEEnabled and playSongRemote then

                    pcall(function()
                        playSongRemote:FireServer(
                            "https://www.roblox.com/asset/?id=0"
                        )
                    end)

                end

                pcall(function()
                    custom:Destroy()
                end)

            end)

            task.spawn(function()

                local startTime = tick()

                while custom.TimeLength == 0 do

                    if tick() - startTime > 2 then
                        break
                    end

                    task.wait(0.05)
                end

                local length = custom.TimeLength

                if not length or length <= 0 then
                    length = 0.5
                end

                task.wait(length + 0.1)

                if playAllFEEnabled and playSongRemote then

                    pcall(function()
                        playSongRemote:FireServer(
                            "https://www.roblox.com/asset/?id=0"
                        )
                    end)

                end

                pcall(function()
                    if custom then
                        custom:Destroy()
                    end
                end)

            end)

        end)
end

-- =============================
-- SETUP SOUND
-- =============================

local function setupSoundInstance(object)

    if not object:IsA("Sound") then
        return
    end

    if processedSounds[object] then
        return
    end

    processedSounds[object] = true

    local name = string.lower(object.Name)

    -- Only hook shooting sounds
    if name == "shoot"
        or name == "fire"
        or name == "gunshot" then

        layerSound(object)
    end

    checkReloadSound(object)

    -- Cleanup when destroyed
    object.Destroying:Connect(function()

        processedSounds[object] = nil

        if connections[object] then
            connections[object]:Disconnect()
            connections[object] = nil
        end

        if reloadConnections[object] then
            reloadConnections[object]:Disconnect()
            reloadConnections[object] = nil
        end

    end)
end

-- =============================
-- HOOK CONTAINER
-- =============================

local function hookContainer(container)

    if not container then
        return
    end

    for _, object in ipairs(container:GetDescendants()) do
        setupSoundInstance(object)
    end

    container.DescendantAdded:Connect(function(object)
        setupSoundInstance(object)
    end)
end

-- =============================
-- BACKPACK
-- =============================

if LocalPlayer.Backpack then
    hookContainer(LocalPlayer.Backpack)

    LocalPlayer.Backpack.ChildAdded:Connect(function(tool)

        task.spawn(function()

            task.wait(0.1)

            hookContainer(tool)

        end)

    end)
end

-- =============================
-- CHARACTER
-- =============================

LocalPlayer.CharacterAdded:Connect(function(character)

    task.spawn(function()

        character:WaitForChild("HumanoidRootPart", 5)

        hookContainer(character)

    end)

end)

if LocalPlayer.Character then
    hookContainer(LocalPlayer.Character)
end

-- =============================
-- TOGGLE
-- =============================

gunSoundSection:AddToggle(
    "Enable Custom Sound [ Client Sided ]",
    function(bool)

        customEnabled = bool
        getgenv().GunSound_Enabled = bool

    end
)

-- =============================
-- PLAY FOR ALL
-- =============================

gunSoundSection:AddToggle(
    "Play For all [ FE ]",
    function(bool)

        playAllFEEnabled = bool
        getgenv().GunSound_PlayAllFE = bool

    end
)

-- =============================
-- MUTE RELOAD
-- =============================

gunSoundSection:AddToggle(
    "Mute Reload Sound",
    function(bool)

        muteReloadEnabled = bool
        getgenv().GunSound_MuteReload = bool

    end
)

-- =============================
-- CUSTOM SOUND ID
-- =============================

gunSoundSection:AddTextBox(
    "Custom SoundId",
    function(text)

        if text and text ~= "" then

            if string.find(text, "rbxassetid://") then
                customTextboxId = text
            else
                customTextboxId = "rbxassetid://" .. text
            end

            getgenv().GunSound_CustomId =
                customTextboxId

            if lastSelected == "Custom" then

                selectedSoundId = customTextboxId

                getgenv().GunSound_SavedId =
                    selectedSoundId

            end
        end

    end
)

-- =============================
-- DROPDOWN
-- =============================

local dropdownOptions = {}

for _, data in ipairs(sounds) do

    local name = string.match(data, "^(.-)|%d+$")

    if name then
        table.insert(dropdownOptions, name)
    end

end

local dropdown =
    gunSoundSection:AddDropdown(
        "Select Sound",
        dropdownOptions,
        function(selected)

            lastSelected = selected

            getgenv().GunSound_SavedName =
                selected

            if selected == "Custom" then

                selectedSoundId = customTextboxId

            else

                for _, data in ipairs(sounds) do

                    local name, id =
                        string.match(data, "^(.-)|(%d+)$")

                    if name == selected then

                        selectedSoundId =
                            "rbxassetid://" .. id

                        break
                    end

                end

            end

            getgenv().GunSound_SavedId =
                selectedSoundId

        end
    )

-- Restore dropdown selection
if dropdown and dropdown.Select then

    pcall(function()
        dropdown.Select(
            getgenv().GunSound_SavedName
        )
    end)

end

-- =============================
-- VOLUME
-- =============================

pcall(function()

    gunSoundSection:AddSlider(
        "Volume",
        0,
        10,
        soundVolume * 10,
        function(value)

            soundVolume = value / 10

            getgenv().GunSound_Volume =
                soundVolume

        end
    )

end)

-- =============================
-- TEST SOUND
-- =============================

gunSoundSection:AddButton(
    "Test Sound Effect",
    function()

        playSound(
            selectedSoundId,
            soundVolume
        )

    end
)

end }

-- ================================================================
-- Module: Knife sound changer
-- Source: https://raw.githubusercontent.com/B6O6S/Better-Odh-tabs/main/Knife%20sound%20changer | Git blob 1da442ab12b1156f9bde09218ff1ca0d67aeb8c4
definitions[#definitions + 1] = { name = "Knife sound changer", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

-- =============================
-- ODH KNIFE SOUND CHANGER
-- =============================

if not odh_shared_plugins then
    warn("ODH Shared Plugins environment not found! Load the main hub first.")
    return
end

local shared = odh_shared_plugins
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local knifeSoundSection = shared.AddSection("Knife Sound Changer")

-- =============================
-- SOUND LIST
-- =============================

local sounds = {
    "Default|142247768",
    "Tom scream|133946057163378",
    "Cat laugh|136958794247658",
    "miskeen (B6O6S)|71767902510649",
    "يلعن ابو لعبك (3RQ)|89850487492275",
    "FAH|137533276939300",
    "Arabic kid|84433159756169",
    "Custom|0"
}

-- =============================
-- SETTINGS
-- =============================

if getgenv().KnifeSound_SavedId == nil then
    getgenv().KnifeSound_SavedId = "rbxassetid://142247768"
end

if getgenv().KnifeSound_SavedName == nil then
    getgenv().KnifeSound_SavedName = "Default"
end

if getgenv().KnifeSound_CustomId == nil then
    getgenv().KnifeSound_CustomId = ""
end

if getgenv().KnifeSound_Enabled == nil then
    getgenv().KnifeSound_Enabled = false
end

if getgenv().KnifeSound_Volume == nil then
    getgenv().KnifeSound_Volume = 1
end

if getgenv().KnifeSound_PlayAllFE == nil then
    getgenv().KnifeSound_PlayAllFE = false
end

-- =============================
-- CONNECTION STORAGE
-- =============================

local connections = {}
local processedSounds = {}

-- =============================
-- TEST SOUND
-- =============================

local function playSound(soundId, volume)
    if not soundId or soundId == "" then
        return
    end

    local sound = Instance.new("Sound")
    sound.SoundId = soundId
    sound.Volume = volume
    sound.Parent = workspace
    sound:Play()

    task.delay(3, function()
        if sound then
            sound:Destroy()
        end
    end)
end

-- =============================
-- KILL SOUND CHECK
-- =============================

local function isKillSound(sound)
    if not sound or not sound:IsA("Sound") then
        return false
    end

    if string.lower(sound.Name) ~= "kill" then
        return false
    end

    if not sound.SoundId or sound.SoundId == "" then
        return false
    end

    return true
end

-- =============================
-- PLAY CUSTOM KILL SOUND
-- =============================

local function playCustomKillSound(originalSound)
    -- Fetch live values from getgenv() to prevent stale closures
    local currentEnabled = getgenv().KnifeSound_Enabled
    local currentSoundId = getgenv().KnifeSound_SavedId
    local currentVolume = getgenv().KnifeSound_Volume
    local currentFE = getgenv().KnifeSound_PlayAllFE

    if not currentEnabled then
        return
    end

    if not currentSoundId or currentSoundId == "" then
        return
    end

    if not isKillSound(originalSound) then
        return
    end

    -- Mute original kill sound safely
    pcall(function()
        originalSound.Volume = 0
    end)

    local pureId = string.match(currentSoundId, "%d+")
    if not pureId then
        return
    end

    local assetUrl = "https://www.roblox.com/asset/?id=" .. pureId

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local inventory = remotes and remotes:FindFirstChild("Inventory")
    local playSongRemote = inventory and inventory:FindFirstChild("PlaySong")

    -- =============================
    -- FE SOUND
    -- =============================

    if currentFE and playSongRemote then
        pcall(function()
            playSongRemote:FireServer(assetUrl)
        end)
    end

    -- =============================
    -- CLIENT SOUND
    -- =============================

    local custom = Instance.new("Sound")
    custom.SoundId = currentSoundId

    if currentFE and playSongRemote then
        custom.Volume = 0
    else
        custom.Volume = currentVolume
    end

    custom.Parent = originalSound.Parent
    custom:Play()

    -- =============================
    -- CLEANUP
    -- =============================

    local function cleanupRemote()
        if currentFE and playSongRemote then
            pcall(function()
                playSongRemote:FireServer("https://www.roblox.com/asset/?id=0")
            end)
        end
    end

    custom.Ended:Connect(function()
        cleanupRemote()
        pcall(function()
            custom:Destroy()
        end)
    end)

    task.delay(5, function()
        if custom and custom.Parent then
            cleanupRemote()
            pcall(function()
                custom:Destroy()
            end)
        end
    end)
end

-- =============================
-- SETUP KILL SOUND
-- =============================

local function setupSound(object)
    if not object:IsA("Sound") then
        return
    end

    if processedSounds[object] then
        return
    end

    processedSounds[object] = true

    if string.lower(object.Name) == "kill" then
        connections[object] = object.Played:Connect(function()
            playCustomKillSound(object)
        end)
    end

    object.Destroying:Connect(function()
        processedSounds[object] = nil
        if connections[object] then
            connections[object]:Disconnect()
            connections[object] = nil
        end
    end)
end

-- =============================
-- HOOK CONTAINER
-- =============================

local function hookContainer(container)
    if not container then
        return
    end

    for _, object in ipairs(container:GetDescendants()) do
        setupSound(object)
    end

    container.DescendantAdded:Connect(function(object)
        setupSound(object)
    end)
end

-- =============================
-- CHARACTER & BACKPACK HOOKS
-- =============================

if LocalPlayer.Character then
    hookContainer(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(function(character)
    task.wait(0.5)
    hookContainer(character)
end)

if LocalPlayer.Backpack then
    hookContainer(LocalPlayer.Backpack)
    LocalPlayer.Backpack.ChildAdded:Connect(function(object)
        task.wait(0.1)
        hookContainer(object)
    end)
end

-- =============================
-- UI ELEMENTS
-- =============================

knifeSoundSection:AddToggle(
    "Custom Knife Sound [ Client Sided ]",
    function(bool)
        getgenv().KnifeSound_Enabled = bool
    end
)

knifeSoundSection:AddToggle(
    "Play For all [ FE ]",
    function(bool)
        getgenv().KnifeSound_PlayAllFE = bool
    end
)

knifeSoundSection:AddTextBox(
    "Custom SoundId",
    function(text)
        if not text or text == "" then
            return
        end

        local customId = string.find(text, "rbxassetid://") and text or ("rbxassetid://" .. text)
        getgenv().KnifeSound_CustomId = customId

        if getgenv().KnifeSound_SavedName == "Custom" then
            getgenv().KnifeSound_SavedId = customId
        end
    end
)

local dropdownOptions = {}
for _, data in ipairs(sounds) do
    local name = string.match(data, "^(.-)|%d+$")
    if name then
        table.insert(dropdownOptions, name)
    end
end

knifeSoundSection:AddDropdown(
    "Select Sound",
    dropdownOptions,
    function(selected)
        getgenv().KnifeSound_SavedName = selected

        if selected == "Custom" then
            getgenv().KnifeSound_SavedId = getgenv().KnifeSound_CustomId
        else
            for _, data in ipairs(sounds) do
                local name, id = string.match(data, "^(.-)|(%d+)$")
                if name == selected then
                    getgenv().KnifeSound_SavedId = "rbxassetid://" .. id
                    break
                end
            end
        end
    end
)

pcall(function()
    if dropdown and dropdown.Select then
        dropdown.Select(getgenv().KnifeSound_SavedName)
    end
end)

pcall(function()
    knifeSoundSection:AddSlider(
        "Volume",
        0,
        10,
        getgenv().KnifeSound_Volume * 10,
        function(value)
            getgenv().KnifeSound_Volume = value / 10
        end
    )
end)

knifeSoundSection:AddButton(
    "Test Sound Effect",
    function()
        playSound(getgenv().KnifeSound_SavedId, getgenv().KnifeSound_Volume)
    end
)

end }

-- ================================================================
-- Module: Multi Hat Giver
-- Source: https://raw.githubusercontent.com/B6O6S/Better-Odh-tabs/main/Multi%20Hat%20Giver | Git blob 192dea9b0ae1d013011298b9c4e58a62c45fffc4
definitions[#definitions + 1] = { name = "Multi Hat Giver", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

--------------------------------------------------------------------------------
-- 2. Multi Hat Giver
--------------------------------------------------------------------------------
do
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
    
    local odh_shared_plugins = odh_shared_plugins -- make sure your shared plugin object exists
    local section = odh_shared_plugins.AddSection("Multi Hat Giver")  
    local isEnabled = false
    local customIds = {Slot1 = 0, Slot2 = 0, Slot3 = 0}
    local selectedIds = {Slot1 = 0, Slot2 = 0, Slot3 = 0}
    local activeHats = {Slot1 = nil, Slot2 = nil, Slot3 = nil}

    local hatOptions = {  
        "None|0",
        "Dominus Astra|162067148",  
        "Valkyrie|1365767",  
        "Clockwork|1235488",
        "Extreme Headphones|96079043",
        "Fiery Horns|215718515",
        "Frozen Horns|74891470",
        "Poisoned Horns|1744060292",
        "Custom|0"  
    }

    local function weldParts(part0, part1, c0, c1)
        local weld = Instance.new("Weld")
        weld.Part0, weld.Part1 = part0, part1
        weld.C0, weld.C1 = c0, c1
        weld.Parent = part0
        return weld
    end

    local function findAttachment(rootPart, name)
        for _, descendant in pairs(rootPart:GetDescendants()) do
            if descendant:IsA("Attachment") and descendant.Name == name then
                return descendant
            end
        end
    end

    local function clearSlot(slot)
        if activeHats[slot] then 
            activeHats[slot]:Destroy() 
            activeHats[slot] = nil
        end
    end

    local function applyHat(slot, accessoryId)
        clearSlot(slot)
        if not isEnabled or accessoryId == 0 then return end
        
        local character = LocalPlayer.Character
        if not character or not character:FindFirstChild("Head") then return end

        local success, objects = pcall(function() return game:GetObjects("rbxassetid://" .. tostring(accessoryId)) end)
        if not success or #objects == 0 then return end
        
        local accessory = objects[1]
        local handle = accessory:FindFirstChild("Handle")
        
        if handle then
            handle.CanCollide, handle.CanTouch, handle.CanQuery, handle.Massless = false, false, false, true
            accessory.Parent = character
            local attachment = handle:FindFirstChildOfClass("Attachment")
            
            if attachment then
                local parentAttachment = findAttachment(character.Head, attachment.Name)
                if parentAttachment then
                    weldParts(character.Head, handle, parentAttachment.CFrame, attachment.CFrame)
                end
            else
                weldParts(character.Head, handle, CFrame.new(0, 0.5, 0), accessory.AttachmentPoint)
            end
            activeHats[slot] = accessory
        end
    end

    local function refreshAllHats()
        applyHat("Slot1", selectedIds["Slot1"])
        applyHat("Slot2", selectedIds["Slot2"])
        applyHat("Slot3", selectedIds["Slot3"])
    end

    section:AddToggle("Enable Hat Giver", function(bool)  
        isEnabled = bool  
        if isEnabled then refreshAllHats() else clearSlot("Slot1"); clearSlot("Slot2"); clearSlot("Slot3") end
    end)

    local dropdownNames = {}
    for _, v in ipairs(hatOptions) do table.insert(dropdownNames, string.match(v, "(.-)|")) end

    for i = 1, 3 do
        local slotName = "Slot" .. i
        section:AddDropdown("Hat Slot " .. i, dropdownNames, function(selected)
            if selected == "Custom" then
                selectedIds[slotName] = customIds[slotName]
            else
                for _, data in ipairs(hatOptions) do
                    local name, id = string.match(data, "(.-)|(%d+)")
                    if name == selected then
                        selectedIds[slotName] = tonumber(id)
                        break
                    end
                end
            end
            if isEnabled then applyHat(slotName, selectedIds[slotName]) end
        end)

        section:AddTextBox("Custom ID Slot " .. i, function(text)
            local id = tonumber(text)
            if id then
                customIds[slotName] = id
                if isEnabled then applyHat(slotName, id) end
            end
        end)
    end

    LocalPlayer.CharacterAdded:Connect(function()
        task.wait(1.5)
        if isEnabled then refreshAllHats() end
    end)
end

end }

-- ================================================================
-- Module: Streamer Mode
-- Source: https://raw.githubusercontent.com/B6O6S/Better-Odh-tabs/main/Streamer%20Mode | Git blob 7700c1c7fe497d1c431b6302f50c1d523d9a48f0
definitions[#definitions + 1] = { name = "Streamer Mode", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

--------------------------------------------------------------------------------
-- 3. Streamer Mode & Hide Executor (Combined)
--------------------------------------------------------------------------------
do
    local shared = odh_shared_plugins
    local CoreGui = game:GetService("CoreGui")
    local section = shared.AddSection("Streamer Mode")

    section:AddLabel("⚠️ To hide Delta enable the Streamer Mode and open Delta!")

    local enabled = false

    -- Streamer Mode Variables
    local sConnections = {}
    local originals = setmetatable({}, { __mode = "k" })

    -- Hide Executor Variables
    local executorFolder = CoreGui:FindFirstChild("218592778d1caa348c8e88e7d1ee04e75b93e002ddea7d9270c85e7f9f348528")
    local hConnections = {}
    local hOriginals = setmetatable({}, { __mode = "k" })

    -- Streamer Mode Functions
    local function GetUI()
        for _, inst in ipairs(CoreGui:GetDescendants()) do
            if inst.Name == "@bubbles.elia" then
                return inst:FindFirstAncestorWhichIsA("LayerCollector")
            end
        end
    end

    local function ShouldIgnore(inst)
        local p = inst
        while p do
            if p:IsA("CanvasGroup") then return true end
            if p:IsA("Folder") and (p.Name == "ESP" or p.Name == "Chams") then return true end
            p = p.Parent
        end
        return false
    end

    local function Save(inst, prop)
        local t = originals[inst]
        if not t then t = {}; originals[inst] = t end
        if t[prop] == nil then
            local ok, value = pcall(function() return inst[prop] end)
            if ok then t[prop] = value end
        end
    end

    local function ApplyHiddenProperties(inst)
        if inst:IsA("GuiObject") then
            Save(inst, "BackgroundTransparency"); inst.BackgroundTransparency = 1
            Save(inst, "BorderSizePixel"); inst.BorderSizePixel = 0
        end
        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            Save(inst, "TextTransparency"); inst.TextTransparency = 1
            Save(inst, "TextStrokeTransparency"); inst.TextStrokeTransparency = 1
        end
        if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
            Save(inst, "ImageTransparency"); inst.ImageTransparency = 1
            Save(inst, "AutoButtonColor"); inst.AutoButtonColor = false
        end
        if inst:IsA("VideoFrame") then Save(inst, "VideoTransparency"); inst.VideoTransparency = 1 end
        if inst:IsA("UIStroke") then Save(inst, "Transparency"); inst.Transparency = 1 end
        if inst:IsA("UIGradient") then Save(inst, "Transparency"); inst.Transparency = NumberSequence.new(1) end
        if inst:IsA("ScrollingFrame") then Save(inst, "ScrollBarImageTransparency"); inst.ScrollBarImageTransparency = 1 end
    end

    local function Hide(inst)
        if ShouldIgnore(inst) then return end
        ApplyHiddenProperties(inst)
        local conn = inst.Changed:Connect(function()
            if enabled then ApplyHiddenProperties(inst) end
        end)
        table.insert(sConnections, conn)
    end

    local function Restore()
        for inst, props in pairs(originals) do
            if inst then
                for prop, value in pairs(props) do
                    pcall(function() inst[prop] = value end)
                end
            end
        end
        table.clear(originals)
        for _, conn in pairs(sConnections) do conn:Disconnect() end
        table.clear(sConnections)
    end

    local function Apply()
        local ui = GetUI()
        if ui then
            Hide(ui)
            for _, obj in ipairs(ui:GetDescendants()) do Hide(obj) end

            local conn = ui.DescendantAdded:Connect(function(obj)
                if enabled then Hide(obj) end
            end)
            table.insert(sConnections, conn)
        end
    end

    -- Hide Executor Functions
    local function SaveProp(inst, prop)
        local t = hOriginals[inst]
        if not t then t = {}; hOriginals[inst] = t end
        if t[prop] == nil then
            local ok, value = pcall(function() return inst[prop] end)
            if ok then t[prop] = value end
        end
    end

    local function HideProps(inst)
        if inst:IsA("LayerCollector") or inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
            SaveProp(inst, "Enabled"); inst.Enabled = false
        end
        if inst:IsA("GuiObject") then
            SaveProp(inst, "BackgroundTransparency"); inst.BackgroundTransparency = 1
            SaveProp(inst, "BorderSizePixel"); inst.BorderSizePixel = 0
            SaveProp(inst, "Visible"); inst.Visible = false
        end
        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            SaveProp(inst, "TextTransparency"); inst.TextTransparency = 1
            SaveProp(inst, "TextStrokeTransparency"); inst.TextStrokeTransparency = 1
            SaveProp(inst, "Text"); inst.Text = ""
            SaveProp(inst, "Visible"); inst.Visible = false
        end
        if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
            SaveProp(inst, "ImageTransparency"); inst.ImageTransparency = 1
            SaveProp(inst, "Image"); inst.Image = ""
            SaveProp(inst, "AutoButtonColor"); inst.AutoButtonColor = false
            SaveProp(inst, "Visible"); inst.Visible = false
        end
        if inst:IsA("Decal") or inst:IsA("Texture") then
            SaveProp(inst, "Transparency"); inst.Transparency = 1
            SaveProp(inst, "Texture"); inst.Texture = ""
        end
        if inst:IsA("UIStroke") then
            SaveProp(inst, "Transparency"); inst.Transparency = 1
        end
        if inst:IsA("UIGradient") then
            SaveProp(inst, "Transparency"); inst.Transparency = NumberSequence.new(1)
        end
        if inst:IsA("ScrollingFrame") then
            SaveProp(inst, "ScrollBarImageTransparency"); inst.ScrollBarImageTransparency = 1
        end
    end

    local function HideObj(inst)
        HideProps(inst)
        local conn = inst.Changed:Connect(function()
            if enabled then HideProps(inst) end
        end)
        table.insert(hConnections, conn)
    end

    local function RestoreExecutor()
        for inst, props in pairs(hOriginals) do
            if inst then
                for prop, value in pairs(props) do
                    pcall(function() inst[prop] = value end)
                end
            end
        end
        table.clear(hOriginals)
        for _, conn in pairs(hConnections) do conn:Disconnect() end
        table.clear(hConnections)
    end

    local function ApplyExecutorHide()
        if executorFolder then
            HideObj(executorFolder)
            for _, obj in ipairs(executorFolder:GetDescendants()) do HideObj(obj) end

            local conn = executorFolder.DescendantAdded:Connect(function(obj)
                if enabled then HideObj(obj) end
            end)
            table.insert(hConnections, conn)
        end
    end

    -- Combined Toggle & Keybind Actions
    local function ToggleState(bool)
        enabled = bool
        if enabled then
            Apply()
            ApplyExecutorHide()
        else
            Restore()
            RestoreExecutor()
        end
    end

    section:AddToggle("Streamer Mode", function(bool)
        ToggleState(bool)
    end)

    section:AddKeybind("Unhide Keybind", "H", function()
        ToggleState(not enabled)
    end)
end

end }

-- ================================================================
-- Module: CODM Guns
-- Source: https://raw.githubusercontent.com/B6O6S/Better-Odh-tabs/main/CODM%20Guns | Git blob 785c60cfd3b4e78bef55e3d9435f05f2c80d1eb8
definitions[#definitions + 1] = { name = "CODM Guns", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

local shared = odh_shared_plugins  

  
local codm_tab = shared.CreateTab("Better ODH", "/B6O6S/Better-ODH/refs/heads/main/Better%20ODH")
local gunEffectSection = codm_tab:AddSection("CODM Guns")
 
gunEffectSection:AddLabel("⚠️ It's only work on godly guns")
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

end }

-- ================================================================
-- Module: Juke sound effect
-- Source: https://raw.githubusercontent.com/B6O6S/Better-Odh-tabs/main/Juke%20sound%20effect | Git blob 8385911b247ab5d9a307a7299cd823ea0ca96a09
definitions[#definitions + 1] = { name = "Juke sound effect", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

-- =============================
-- SERVICES & CORE VARIABLES
-- =============================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local shared = odh_shared_plugins

-- =============================
-- JUKE SOUND SECTION (OPTIMIZED & LAG-FREE)
-- =============================
local jukeSoundSection = shared.AddSection("Juke Sound effect")

-- Sound options ordered normally, with new options included and Custom at the very end
local sounds = {
    "Ankle break|116630605163027",
    "Where are you going|140099088033128",
    "Please Speed i need this|96825144718073",
    "Haki|131717855995267",
    "Michael Myers|103625247693766",
    "بالراحة (B6O6S)|90233621241303",
    "بسم الله عليك (B6O6S)|109098054743197",
    "عجيب والله (B6O6S)|131846507499000",
    "Fah|139259088251978",
    "Meow|7148585764",
    "Bruh|6349641063",
    "Fart|8551016315",
    "Custom|0" -- Placeholder for textbox input
}

-- Use getgenv() to save choices across script re-executions
getgenv().JukeSound_SavedId = getgenv().JukeSound_SavedId or "rbxassetid://116630605163027"
getgenv().JukeSound_SavedName = getgenv().JukeSound_SavedName or "Ankle break"
getgenv().JukeSound_CustomId = getgenv().JukeSound_CustomId or nil
getgenv().JukeSound_Enabled = getgenv().JukeSound_Enabled or false
getgenv().JukeSound_Distance = getgenv().JukeSound_Distance or 15
getgenv().JukeSound_Volume = getgenv().JukeSound_Volume or 1
getgenv().JukeSound_PlayAllFE = getgenv().JukeSound_PlayAllFE or false

local selectedSoundId = getgenv().JukeSound_SavedId
local customEnabled = getgenv().JukeSound_Enabled
local customTextboxId = getgenv().JukeSound_CustomId
local lastSelected = getgenv().JukeSound_SavedName
local JUKE_DISTANCE = getgenv().JukeSound_Distance
local soundVolume = getgenv().JukeSound_Volume
local playAllFEEnabled = getgenv().JukeSound_PlayAllFE

local Murder = nil
local hasPlayedJuke = false
local isLocalPlayerMurderer = false
local isRoundActive = false

-- Function to play sound (used for testing)
local function playSound(soundId, volume)
    if not soundId or soundId == "" then return end
    local soundObj = Instance.new("Sound")
    soundObj.SoundId = soundId
    soundObj.Volume = volume or 1
    soundObj.PlayOnRemove = true
    soundObj.Parent = workspace
    soundObj:Destroy()
end

-- Function to play the custom juke sound and handle FE radio broadcast & volume sync
local function playJukeSound()
    if not selectedSoundId or not customEnabled or not isRoundActive then return end

    local pureId = string.match(selectedSoundId, "(%d+)") or "116630605163027"
    local assetUrl = "https://www.roblox.com/asset/?id=" .. pureId

    local playSongRemote = ReplicatedStorage:FindFirstChild("Remotes") 
        and ReplicatedStorage.Remotes:FindFirstChild("Inventory") 
        and ReplicatedStorage.Remotes.Inventory:FindFirstChild("PlaySong")

    local effectiveVolume = soundVolume
    if playAllFEEnabled and playSongRemote then
        pcall(function()
            playSongRemote:FireServer(assetUrl)
        end)
        effectiveVolume = 0
    end

    local soundObj = Instance.new("Sound")
    soundObj.SoundId = selectedSoundId
    soundObj.Volume = effectiveVolume
    soundObj.PlayOnRemove = true
    soundObj.Parent = workspace
    soundObj:Play()

    soundObj.Ended:Connect(function()
        if playAllFEEnabled and playSongRemote then
            pcall(function()
                playSongRemote:FireServer("https://www.roblox.com/asset/?id=0")
            end)
        end
    end)

    task.spawn(function()
        local startTime = tick()
        while soundObj.TimeLength == 0 and tick() - startTime < 2 do
            task.wait(0.05)
        end
        local length = soundObj.TimeLength
        if not length or length == 0 then
            length = 0.5
        end
        task.wait(length)
        if playAllFEEnabled and playSongRemote then
            pcall(function()
                playSongRemote:FireServer("https://www.roblox.com/asset/?id=0")
            end)
        end
    end)
end

-- Function to check distance to the murderer (strict checks: round must be active and murderer must be alive)
local lastCheck = 0
local function checkJuke()
    if not customEnabled or not isRoundActive or not Murder or isLocalPlayerMurderer then return end

    local murdererPlayer = Players:FindFirstChild(Murder)
    if murdererPlayer and murdererPlayer.Character and murdererPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local mRoot = murdererPlayer.Character.HumanoidRootPart
        local lpRoot = LocalPlayer.Character.HumanoidRootPart
        
        local distance = (mRoot.Position - lpRoot.Position).Magnitude
        
        if distance <= JUKE_DISTANCE then
            if not hasPlayedJuke then
                playJukeSound()
                hasPlayedJuke = true
            end
        else
            if distance > (JUKE_DISTANCE + 5) then
                hasPlayedJuke = false
            end
        end
    end
end

-- Background loop: Validates active roles, round states, and eliminates post-round lagging audio
task.spawn(function()
    local playerDataFunc = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
    while true do
        if playerDataFunc then
            local success, res = pcall(function()
                return playerDataFunc:InvokeServer()
            end)
            if success and res and type(res) == "table" then
                local foundMurderer = nil
                local userIsMurderer = false
                local roundRunning = false

                for playerName, data in pairs(res) do
                    if data and type(data) == "table" then
                        -- Check if any player is actively playing in the round
                        if data.Role and data.Role ~= "Spectator" and data.Role ~= "" then
                            roundRunning = true
                        end

                        if data.Role == "Murderer" then
                            -- Ensure the murderer is truly spawned, active, and alive
                            if not data.Killed and not data.Dead and data.Alive ~= false then
                                foundMurderer = playerName
                                if playerName == LocalPlayer.Name then
                                    userIsMurderer = true
                                end
                            end
                        end
                    end
                end

                isRoundActive = roundRunning
                Murder = foundMurderer
                isLocalPlayerMurderer = userIsMurderer
                
                -- Reset trigger state immediately if round ends or murderer is dead
                if not roundRunning or not foundMurderer then
                    hasPlayedJuke = false
                end
            else
                isRoundActive = false
                Murder = nil
                hasPlayedJuke = false
            end
        else
            isRoundActive = false
            Murder = nil
            hasPlayedJuke = false
        end
        task.wait(1) -- Check status every 1 second to stay completely lag-free
    end
end)

-- Lightweight Heartbeat throttle (0.15s interval) to safely monitor distance
RunService.Heartbeat:Connect(function(dt)
    if not customEnabled or not isRoundActive or isLocalPlayerMurderer then return end
    lastCheck = lastCheck + dt
    if lastCheck >= 0.15 then
        lastCheck = 0
        checkJuke()
    end
end)

-- Toggle for enabling/disabling custom juke sound
jukeSoundSection:AddToggle("Juke Sound [ Client Sided ]", function(bool)
    customEnabled = bool
    getgenv().JukeSound_Enabled = bool
    hasPlayedJuke = false
end)

-- Toggle for Play For all [ FE ]
jukeSoundSection:AddToggle("Play For all [ FE ]", function(bool)
    playAllFEEnabled = bool
    getgenv().JukeSound_PlayAllFE = bool
end)

-- Slider to control juke trigger distance (min: 5, max: 50, default: 15)
jukeSoundSection:AddSlider("Juke Distance", 5, 50, JUKE_DISTANCE, function(value)
    JUKE_DISTANCE = value
    getgenv().JukeSound_Distance = value
end)

-- TextBox for custom SoundId
jukeSoundSection:AddTextBox("Custom SoundId", function(text)
    if text and text ~= "" then
        if not string.find(text, "rbxassetid://") then
            customTextboxId = "rbxassetid://" .. text
        else
            customTextboxId = text
        end
        getgenv().JukeSound_CustomId = customTextboxId
        
        if lastSelected == "Custom" then
            selectedSoundId = customTextboxId
            getgenv().JukeSound_SavedId = selectedSoundId
        end
    end
end)

-- Dropdown to select the custom sound
local dropdownOptions = {}
for _, data in ipairs(sounds) do
    local name = string.match(data, "(.-)|%d+")
    table.insert(dropdownOptions, name)
end

local dropdown = jukeSoundSection:AddDropdown("Select Juke Sound", dropdownOptions, function(selected)
    lastSelected = selected
    getgenv().JukeSound_SavedName = selected

    if selected == "Custom" then
        selectedSoundId = customTextboxId
    else
        for _, data in ipairs(sounds) do
            local name, id = string.match(data, "(.-)|(%d+)")
            if name == selected then
                selectedSoundId = "rbxassetid://" .. id
                break
            end
        end
    end
    getgenv().JukeSound_SavedId = selectedSoundId
end)

pcall(function() 
    if dropdown and dropdown.Select then
        dropdown.Select(getgenv().JukeSound_SavedName) 
    end
end)

-- Volume Slider
pcall(function()
    jukeSoundSection:AddSlider("Volume", 0, 10, soundVolume * 10, function(value)
        soundVolume = value / 10
        getgenv().JukeSound_Volume = soundVolume
    end)
end)

-- Test Sound Effect Button
jukeSoundSection:AddButton("Test Sound Effect", function()
    playSound(selectedSoundId, soundVolume)
end)

end }

-- ================================================================
-- Module: RTX & Graphics
-- Source: https://raw.githubusercontent.com/B6O6S/Better-Odh-tabs/main/RTX%20%26%20Graphics | Git blob 240e959286a71577c8fb24243f1f0d9207e9ca49
definitions[#definitions + 1] = { name = "RTX & Graphics", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

local shared = odh_shared_plugins
local rtx_tab = shared.AddSection("RTX & Graphics")

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Terrain = Workspace:FindFirstChildOfClass("Terrain")

-- Master States
local rtx_enabled = false
local time_of_day_enabled = false
local custom_graphics_enabled = false
local current_time_mode = "Default (Original Game Time)"

-- Stored Custom Settings
local custom_brightness = 20
local custom_saturation = 35
local custom_contrast = 30
local custom_bloom_intensity = 0.45
local custom_bloom_size = 3500
local custom_sunrays_intensity = 0.35
local custom_reflections = 2.5

-- Default lighting backup for restore
local defaultLighting = {
    Technology = Lighting.Technology,
    GlobalShadows = Lighting.GlobalShadows,
    Brightness = Lighting.Brightness,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    ColorShift_Bottom = Lighting.ColorShift_Bottom,
    ColorShift_Top = Lighting.ColorShift_Top,
    EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
    EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
    ShadowSoftness = Lighting.ShadowSoftness,
    GeographicLatitude = Lighting.GeographicLatitude,
    ExposureCompensation = Lighting.ExposureCompensation,
    ClockTime = Lighting.ClockTime,
    WaterTransparency = Terrain and Terrain.WaterTransparency or 0.3,
    WaterReflectance = Terrain and Terrain.WaterReflectance or 0,
}

-- Effect Instances
local rtx_instances = {}
local atmosphere_instance, sky_instance

local function removeEffects(tbl)
    for _, obj in ipairs(tbl) do
        if obj and obj.Parent then
            obj:Destroy()
        end
    end
    table.clear(tbl)
    if atmosphere_instance then atmosphere_instance:Destroy() atmosphere_instance = nil end
    if sky_instance then sky_instance:Destroy() sky_instance = nil end
end

local function applyTimeOfDay(mode)
    if not time_of_day_enabled then return end
    
    -- Cleanup previous atmosphere/sky
    if atmosphere_instance then atmosphere_instance:Destroy() atmosphere_instance = nil end
    if sky_instance then sky_instance:Destroy() sky_instance = nil end

    if mode == "Default (Original Game Time)" then
        Lighting.ClockTime = defaultLighting.ClockTime
        Lighting.GeographicLatitude = defaultLighting.GeographicLatitude
        Lighting.Brightness = defaultLighting.Brightness
        Lighting.Ambient = defaultLighting.Ambient
        Lighting.OutdoorAmbient = defaultLighting.OutdoorAmbient
        Lighting.ColorShift_Bottom = defaultLighting.ColorShift_Bottom
        Lighting.ColorShift_Top = defaultLighting.ColorShift_Top
        Lighting.ExposureCompensation = defaultLighting.ExposureCompensation

    elseif mode == "Morning (Clean Golden)" then
        Lighting.ClockTime = 7.0
        Lighting.Brightness = 3.2
        Lighting.Ambient = Color3.fromRGB(55, 50, 45)
        Lighting.OutdoorAmbient = Color3.fromRGB(190, 160, 130)
        Lighting.ColorShift_Bottom = Color3.fromRGB(20, 15, 10)
        Lighting.ColorShift_Top = Color3.fromRGB(255, 235, 205)
        Lighting.ExposureCompensation = 0.3
        Lighting.GeographicLatitude = -25

        atmosphere_instance = Instance.new("Atmosphere", Lighting)
        atmosphere_instance.Density = 0.3
        atmosphere_instance.Offset = 0.2
        atmosphere_instance.Color = Color3.fromRGB(255, 225, 185)
        atmosphere_instance.Decay = Color3.fromRGB(110, 85, 65)
        atmosphere_instance.Glare = 0.4
        atmosphere_instance.Haze = 2

    elseif mode == "Midday (Vibrant Sun)" then
        Lighting.ClockTime = 13.0
        Lighting.Brightness = 4.0
        Lighting.Ambient = Color3.fromRGB(60, 65, 80)
        Lighting.OutdoorAmbient = Color3.fromRGB(180, 200, 230)
        Lighting.ColorShift_Bottom = Color3.fromRGB(20, 30, 50)
        Lighting.ColorShift_Top = Color3.fromRGB(255, 255, 245)
        Lighting.ExposureCompensation = 0.35
        Lighting.GeographicLatitude = 10

        atmosphere_instance = Instance.new("Atmosphere", Lighting)
        atmosphere_instance.Density = 0.2
        atmosphere_instance.Offset = 0
        atmosphere_instance.Color = Color3.fromRGB(200, 220, 255)
        atmosphere_instance.Decay = Color3.fromRGB(90, 120, 160)
        atmosphere_instance.Glare = 0.4
        atmosphere_instance.Haze = 1

    elseif mode == "Afternoon (Golden Hour)" then
        Lighting.ClockTime = 16.5
        Lighting.Brightness = 3.6
        Lighting.Ambient = Color3.fromRGB(70, 45, 35)
        Lighting.OutdoorAmbient = Color3.fromRGB(220, 140, 70)
        Lighting.ColorShift_Bottom = Color3.fromRGB(70, 30, 15)
        Lighting.ColorShift_Top = Color3.fromRGB(255, 180, 90)
        Lighting.ExposureCompensation = 0.38
        Lighting.GeographicLatitude = -15

        atmosphere_instance = Instance.new("Atmosphere", Lighting)
        atmosphere_instance.Density = 0.35
        atmosphere_instance.Offset = 0.4
        atmosphere_instance.Color = Color3.fromRGB(255, 150, 60)
        atmosphere_instance.Decay = Color3.fromRGB(110, 50, 25)
        atmosphere_instance.Glare = 0.7
        atmosphere_instance.Haze = 3

    elseif mode == "Sunset (Natural Warmth)" then
        Lighting.ClockTime = 18.2
        Lighting.Brightness = 3.4
        Lighting.Ambient = Color3.fromRGB(65, 45, 40)
        Lighting.OutdoorAmbient = Color3.fromRGB(210, 130, 85)
        Lighting.ColorShift_Bottom = Color3.fromRGB(50, 20, 20)
        Lighting.ColorShift_Top = Color3.fromRGB(255, 170, 110)
        Lighting.ExposureCompensation = 0.35
        Lighting.GeographicLatitude = -50

        atmosphere_instance = Instance.new("Atmosphere", Lighting)
        atmosphere_instance.Density = 0.3
        atmosphere_instance.Offset = 0.4
        atmosphere_instance.Color = Color3.fromRGB(255, 160, 100)
        atmosphere_instance.Decay = Color3.fromRGB(90, 50, 40)
        atmosphere_instance.Glare = 0.6
        atmosphere_instance.Haze = 3

    elseif mode == "Night (Cool Moonlight)" then
        Lighting.ClockTime = 0.0
        Lighting.Brightness = 2.0
        Lighting.Ambient = Color3.fromRGB(25, 35, 60)
        Lighting.OutdoorAmbient = Color3.fromRGB(40, 70, 120)
        Lighting.ColorShift_Bottom = Color3.fromRGB(10, 20, 45)
        Lighting.ColorShift_Top = Color3.fromRGB(130, 190, 255)
        Lighting.ExposureCompensation = 0.5
        Lighting.GeographicLatitude = 45

        atmosphere_instance = Instance.new("Atmosphere", Lighting)
        atmosphere_instance.Density = 0.4
        atmosphere_instance.Offset = 0
        atmosphere_instance.Color = Color3.fromRGB(30, 50, 90)
        atmosphere_instance.Decay = Color3.fromRGB(15, 25, 50)
        atmosphere_instance.Glare = 0.3
        atmosphere_instance.Haze = 2

        sky_instance = Instance.new("Sky", Lighting)
        sky_instance.SkyboxBk = "rbxassetid://826027103"
        sky_instance.SkyboxDn = "rbxassetid://826027117"
        sky_instance.SkyboxFt = "rbxassetid://826027137"
        sky_instance.SkyboxLf = "rbxassetid://826027161"
        sky_instance.SkyboxRt = "rbxassetid://826027189"
        sky_instance.SkyboxUp = "rbxassetid://826027228"

    elseif mode == "Midnight (Pitch Black & Stars)" then
        Lighting.ClockTime = 1.5
        Lighting.Brightness = 1.2
        Lighting.Ambient = Color3.fromRGB(10, 12, 20)
        Lighting.OutdoorAmbient = Color3.fromRGB(15, 25, 45)
        Lighting.ColorShift_Bottom = Color3.fromRGB(5, 8, 15)
        Lighting.ColorShift_Top = Color3.fromRGB(80, 120, 200)
        Lighting.ExposureCompensation = 0.2
        Lighting.GeographicLatitude = 90

        atmosphere_instance = Instance.new("Atmosphere", Lighting)
        atmosphere_instance.Density = 0.6
        atmosphere_instance.Offset = 0
        atmosphere_instance.Color = Color3.fromRGB(10, 20, 40)
        atmosphere_instance.Decay = Color3.fromRGB(5, 10, 20)
        atmosphere_instance.Glare = 0.2
        atmosphere_instance.Haze = 6

        sky_instance = Instance.new("Sky", Lighting)
        sky_instance.SkyboxBk = "rbxassetid://826027103"
        sky_instance.SkyboxDn = "rbxassetid://826027117"
        sky_instance.SkyboxFt = "rbxassetid://826027137"
        sky_instance.SkyboxLf = "rbxassetid://826027161"
        sky_instance.SkyboxRt = "rbxassetid://826027189"
        sky_instance.SkyboxUp = "rbxassetid://826027228"
    end
end

local function applyRTXPreset()
    if not rtx_enabled then return end
    
    removeEffects(rtx_instances)

    Lighting.Technology = Enum.Technology.Future
    Lighting.GlobalShadows = true
    Lighting.ShadowSoftness = 0.02
    Lighting.EnvironmentDiffuseScale = 1.0  
    Lighting.EnvironmentSpecularScale = custom_reflections

    if Terrain then
        Terrain.WaterTransparency = 0.01
        Terrain.WaterReflectance = 1.0
        Terrain.WaterWaveSize = 0.25
        Terrain.WaterWaveSpeed = 16
    end

    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level21
    end)

    -- INSANE HIGH BLOOM
    local b = Instance.new("BloomEffect", Lighting)
    b.Enabled = true
    b.Intensity = 0.40
    b.Size = 3500
    b.Threshold = 0.65
    table.insert(rtx_instances, b)

    -- Color Correction Grading
    local c = Instance.new("ColorCorrectionEffect", Lighting)
    c.Brightness = 0.15
    c.Contrast = 0.45
    c.Saturation = 0.35
    c.Enabled = true
    c.TintColor = Color3.fromRGB(255, 245, 230)
    table.insert(rtx_instances, c)

    -- Cinematic Depth of Field
    local d = Instance.new("DepthOfFieldEffect", Lighting)
    d.Enabled = true
    d.FarIntensity = 0.08
    d.FocusDistance = 28.0
    d.InFocusRadius = 20.0
    d.NearIntensity = 0.15
    table.insert(rtx_instances, d)

    -- INSANE MAXIMUM SUNRAYS
    local s = Instance.new("SunRaysEffect", Lighting)
    s.Enabled = true
    s.Intensity = 0.35
    s.Spread = 0.85
    table.insert(rtx_instances, s)
end

local custom_cc, custom_bloom, custom_rays

local function removeCustomEffects()
    if custom_cc then custom_cc:Destroy() custom_cc = nil end
    if custom_bloom then custom_bloom:Destroy() custom_bloom = nil end
    if custom_rays then custom_rays:Destroy() custom_rays = nil end
    
    -- Reset lighting settings affected by custom graphics sliders
    Lighting.Brightness = defaultLighting.Brightness
    Lighting.EnvironmentSpecularScale = defaultLighting.EnvironmentSpecularScale
end

local function applyCustomGraphics()
    if not custom_graphics_enabled then return end

    Lighting.Brightness = custom_brightness / 10
    Lighting.EnvironmentSpecularScale = custom_reflections

    if not custom_cc or not custom_cc.Parent then
        custom_cc = Instance.new("ColorCorrectionEffect", Lighting)
    end
    custom_cc.Saturation = custom_saturation / 100
    custom_cc.Contrast = custom_contrast / 100

    if not custom_bloom or not custom_bloom.Parent then
        custom_bloom = Instance.new("BloomEffect", Lighting)
    end
    custom_bloom.Intensity = custom_bloom_intensity
    custom_bloom.Size = custom_bloom_size

    if not custom_rays or not custom_rays.Parent then
        custom_rays = Instance.new("SunRaysEffect", Lighting)
    end
    custom_rays.Intensity = custom_sunrays_intensity
    custom_rays.Spread = 0.85
end

-- 1) MASTER RTX TOGGLE
rtx_tab:AddToggle("Enable RTX (Ultra Realistic)", function(on)
    rtx_enabled = on
    if on then
        applyRTXPreset()
    else
        Lighting.Technology = defaultLighting.Technology
        Lighting.GlobalShadows = defaultLighting.GlobalShadows
        Lighting.Brightness = defaultLighting.Brightness
        Lighting.Ambient = defaultLighting.Ambient
        Lighting.OutdoorAmbient = defaultLighting.OutdoorAmbient
        Lighting.ColorShift_Bottom = defaultLighting.ColorShift_Bottom
        Lighting.ColorShift_Top = defaultLighting.ColorShift_Top
        Lighting.EnvironmentDiffuseScale = defaultLighting.EnvironmentDiffuseScale
        Lighting.EnvironmentSpecularScale = defaultLighting.EnvironmentSpecularScale
        Lighting.ShadowSoftness = defaultLighting.ShadowSoftness
        Lighting.GeographicLatitude = defaultLighting.GeographicLatitude
        Lighting.ExposureCompensation = defaultLighting.ExposureCompensation
        Lighting.ClockTime = defaultLighting.ClockTime
        
        if Terrain then
            Terrain.WaterTransparency = defaultLighting.WaterTransparency
            Terrain.WaterReflectance = defaultLighting.WaterReflectance
        end

        pcall(function()
            settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
        end)
        
        removeEffects(rtx_instances)
    end
end)

-- 2) TIME OF DAY TOGGLE & DROPDOWN
rtx_tab:AddToggle("Enable Custom Time of Day", function(on)
    time_of_day_enabled = on
    if on then
        applyTimeOfDay(current_time_mode)
    else
        if atmosphere_instance then atmosphere_instance:Destroy() atmosphere_instance = nil end
        if sky_instance then sky_instance:Destroy() sky_instance = nil end
        Lighting.ClockTime = defaultLighting.ClockTime
        Lighting.GeographicLatitude = defaultLighting.GeographicLatitude
        Lighting.Brightness = defaultLighting.Brightness
        Lighting.Ambient = defaultLighting.Ambient
        Lighting.OutdoorAmbient = defaultLighting.OutdoorAmbient
        Lighting.ColorShift_Bottom = defaultLighting.ColorShift_Bottom
        Lighting.ColorShift_Top = defaultLighting.ColorShift_Top
        Lighting.ExposureCompensation = defaultLighting.ExposureCompensation
    end
end)

rtx_tab:AddDropdown("Time of Day Preset", {"Default (Original Game Time)", "Morning (Clean Golden)", "Midday (Vibrant Sun)", "Afternoon (Golden Hour)", "Sunset (Natural Warmth)", "Night (Cool Moonlight)", "Midnight (Pitch Black & Stars)"}, function(selected)
    current_time_mode = selected
    if time_of_day_enabled then
        applyTimeOfDay(selected)
    end
end)

-- 3) CUSTOM GRAPHICS TOGGLE
rtx_tab:AddToggle("Enable Custom Graphics", function(on)
    custom_graphics_enabled = on
    if on then
        applyCustomGraphics()
    else
        removeCustomEffects()
    end
end)

-- Custom Graphics Sliders
rtx_tab:AddSlider("Custom Brightness", 5, 40, custom_brightness, function(v)
    custom_brightness = v
    if custom_graphics_enabled then
        Lighting.Brightness = v / 10
    end
end)

rtx_tab:AddSlider("Custom Saturation", 0, 100, custom_saturation, function(v)
    custom_saturation = v
    if custom_graphics_enabled then applyCustomGraphics() end
end)

rtx_tab:AddSlider("Custom Contrast", 0, 100, custom_contrast, function(v)
    custom_contrast = v
    if custom_graphics_enabled then applyCustomGraphics() end
end)

rtx_tab:AddSlider("Bloom Intensity", 0, 100, math.floor(custom_bloom_intensity * 100), function(v)
    custom_bloom_intensity = v / 100
    if custom_graphics_enabled then applyCustomGraphics() end
end)

rtx_tab:AddSlider("SunRays Intensity", 0, 100, math.floor(custom_sunrays_intensity * 100), function(v)
    custom_sunrays_intensity = v / 100
    if custom_graphics_enabled then applyCustomGraphics() end
end)

rtx_tab:AddSlider("Reflections Intensity", 0, 50, math.floor(custom_reflections * 10), function(v)
    custom_reflections = v / 10
    if custom_graphics_enabled then
        Lighting.EnvironmentSpecularScale = custom_reflections
    end
end)

end }

-- ================================================================
-- Module: Death Sound Effect
-- Source: https://raw.githubusercontent.com/B6O6S/Better-Odh-tabs/main/Death%20Sound%20Effect | Git blob dc252da40d30da83428641f1e5e39bf1b0aaaa4e
definitions[#definitions + 1] = { name = "Death Sound Effect", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

local shared = odh_shared_plugins


local sound_tab = shared.CreateTab("Better ODH", "/B6O6S/Better-ODH/refs/heads/main/Better%20ODH")
local jukeSoundSection = sound_tab:AddSection("Death Sound Effect")


-- Sound options ordered normally, with Custom at the very end
local sounds = {
    "Arab dad fart|126753086907254",
    "iraqi kid \"wow\" *fart*|107988548317949",
    "يلعن ابو لعبك (3RQ)|89850487492275",
    "عجيب والله (B6O6S)|131846507499000",
    "OOUUGGHH|97843302606905",
    "Meow|7148585764",
    "Bruh|6349641063",
    "Screams|94314745898930",
    "Custom|0" -- Placeholder for textbox input
}

-- Use getgenv() to save choices across script re-executions
getgenv().DeathSound_SavedId = getgenv().DeathSound_SavedId or "rbxassetid://126753086907254"
getgenv().DeathSound_SavedName = getgenv().DeathSound_SavedName or "Arab dad fart"
getgenv().DeathSound_CustomId = getgenv().DeathSound_CustomId or nil
getgenv().DeathSound_Enabled = getgenv().DeathSound_Enabled or false
getgenv().DeathSound_Volume = getgenv().DeathSound_Volume or 1

local selectedSoundId = getgenv().DeathSound_SavedId
local customEnabled = getgenv().DeathSound_Enabled
local customTextboxId = getgenv().DeathSound_CustomId
local lastSelected = getgenv().DeathSound_SavedName
local soundVolume = getgenv().DeathSound_Volume

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local hasPlayedDeathSound = false
local lastCharacter = nil

-- Function to play sound (used for both death and testing)
local function playSound(soundId, volume)
    if not soundId or soundId == "" then return end
    local soundObj = Instance.new("Sound")
    soundObj.SoundId = soundId
    soundObj.Volume = volume or 1
    soundObj.PlayOnRemove = true
    soundObj.Parent = workspace
    soundObj:Destroy()
end

-- Function to play custom sound and mute/remove Roblox default death sound
local function playDeathSound(char)
    if not selectedSoundId or not customEnabled then return end
    
    -- Mute/remove default death sound inside character head or Humanoid
    local head = char:FindFirstChild("Head")
    if head then
        for _, obj in ipairs(head:GetChildren()) do
            if obj:IsA("Sound") then
                obj.Volume = 0
                obj.SoundId = ""
            end
        end
    end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        for _, obj in ipairs(humanoid:GetChildren()) do
            if obj:IsA("Sound") then
                obj.Volume = 0
                obj.SoundId = ""
            end
        end
    end

    -- Play custom sound with selected volume
    playSound(selectedSoundId, soundVolume)
end

-- Function to setup death detection on the current character
local function setupCharacter(char)
    hasPlayedDeathSound = false
    lastCharacter = char
    
    -- Continuously clear default death sound as soon as character spawns
    task.spawn(function()
        local head = char:WaitForChild("Head", 5)
        if head then
            for _, obj in ipairs(head:GetChildren()) do
                if obj:IsA("Sound") then
                    obj.Volume = 0
                    obj.SoundId = ""
                end
            end
            head.ChildAdded:Connect(function(obj)
                if obj:IsA("Sound") then
                    obj.Volume = 0
                    obj.SoundId = ""
                end
            end)
        end
    end)

    local humanoid = char:WaitForChild("Humanoid", 5)
    if humanoid then
        -- Method 1: Standard Humanoid.Died event
        humanoid.Died:Connect(function()
            if customEnabled and not hasPlayedDeathSound then
                hasPlayedDeathSound = true
                playDeathSound(char)
            end
        end)

        -- Method 2: Health-based fallback for custom death systems
        humanoid:GetPropertyChangedSignal("Health"):Connect(function()
            if humanoid.Health <= 0 and customEnabled and not hasPlayedDeathSound then
                hasPlayedDeathSound = true
                playDeathSound(char)
            end
        end)
    end

    -- Method 3: State-based fallback for custom death/ragdoll systems
    if humanoid then
        humanoid.StateChanged:Connect(function(_, newState)
            if (newState == Enum.HumanoidStateType.Dead or newState == Enum.HumanoidStateType.Ragdoll) and customEnabled and not hasPlayedDeathSound then
                hasPlayedDeathSound = true
                playDeathSound(char)
            end
        end)
    end
end

if LocalPlayer.Character then
    setupCharacter(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(setupCharacter)

-- Toggle for enabling/disabling death sound
jukeSoundSection:AddToggle("Enable Death Sound", function(bool)
    customEnabled = bool
    getgenv().DeathSound_Enabled = bool
    hasPlayedDeathSound = false
end)

-- TextBox for custom SoundId
jukeSoundSection:AddTextBox("Custom SoundId", function(text)
    if text and text ~= "" then
        if not string.find(text, "rbxassetid://") then
            customTextboxId = "rbxassetid://" .. text
        else
            customTextboxId = text
        end
        getgenv().DeathSound_CustomId = customTextboxId
        
        if lastSelected == "Custom" then
            selectedSoundId = customTextboxId
            getgenv().DeathSound_SavedId = selectedSoundId
        end
    end
end)

-- Dropdown to select the sound
local dropdownOptions = {}
for _, data in ipairs(sounds) do
    local name = string.match(data, "(.-)|%d+")
    table.insert(dropdownOptions, name)
end

local dropdown = jukeSoundSection:AddDropdown("Select Death Sound", dropdownOptions, function(selected)
    lastSelected = selected
    getgenv().DeathSound_SavedName = selected

    if selected == "Custom" then
        selectedSoundId = customTextboxId
    else
        for _, data in ipairs(sounds) do
            local name, id = string.match(data, "(.-)|(%d+)")
            if name == selected then
                selectedSoundId = "rbxassetid://" .. id
                break
            end
        end
    end
    getgenv().DeathSound_SavedId = selectedSoundId
end)

pcall(function() 
    if dropdown and dropdown.Select then
        dropdown.Select(getgenv().DeathSound_SavedName) 
    end
end)

-- Volume Slider
pcall(function()
    jukeSoundSection:AddSlider("Volume", 0, 10, soundVolume * 10, function(value)
        soundVolume = value / 10
        getgenv().DeathSound_Volume = soundVolume
    end)
end)

-- Test Sound Button using AddButton format
jukeSoundSection:AddButton("Test Sound Effect", function()
    playSound(selectedSoundId, soundVolume)
end)

end }

-- ================================================================
-- Module: Jump Sound Effect
-- Source: https://raw.githubusercontent.com/B6O6S/Better-Odh-tabs/main/Jump%20Sound%20Effect | Git blob 86473a55c7f3e57e2099dc1851bffc5755984ea5
definitions[#definitions + 1] = { name = "Jump Sound Effect", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

-- =============================
-- SERVICES & CORE VARIABLES
-- =============================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local shared = odh_shared_plugins

-- =============================
-- JUMP SOUND SECTION
-- =============================
local jumpSoundSection = shared.AddSection("Jump Sound Changer")

-- Sound options
local sounds = {
    "Default|9114408107",
    "8 Bit|271111328",
    "Mario|120089981011454",
    "Trampoline|114384110581799",
    "Old Roblox Jump|98548477938162",
    "Meow|7148585764",
    "Bruh|6349641063",
    "Fart|8551016315",
    "Custom|0"
}

-- Use getgenv() to save choices across script re-executions
getgenv().JumpSound_SavedId = getgenv().JumpSound_SavedId or "rbxassetid://9114408107"
getgenv().JumpSound_SavedName = getgenv().JumpSound_SavedName or "Default"
getgenv().JumpSound_CustomId = getgenv().JumpSound_CustomId or nil
getgenv().JumpSound_Enabled = getgenv().JumpSound_Enabled or false
getgenv().JumpSound_Volume = getgenv().JumpSound_Volume or 1
getgenv().JumpSound_PlayAllFE = getgenv().JumpSound_PlayAllFE or false

local selectedSoundId = getgenv().JumpSound_SavedId
local customEnabled = getgenv().JumpSound_Enabled
local customTextboxId = getgenv().JumpSound_CustomId
local lastSelected = getgenv().JumpSound_SavedName
local soundVolume = getgenv().JumpSound_Volume
local playAllFEEnabled = getgenv().JumpSound_PlayAllFE

local connection = nil

-- Function to play sound (used for testing)
local function playSound(soundId, volume)
    if not soundId or soundId == "" then return end
    local soundObj = Instance.new("Sound")
    soundObj.SoundId = soundId
    soundObj.Volume = volume or 1
    soundObj.PlayOnRemove = true
    soundObj.Parent = workspace
    soundObj:Destroy()
end

-- Function to handle jump sound execution and FE radio broadcast
local function triggerJumpSound()
    if not selectedSoundId or not customEnabled then return end

    local pureId = string.match(selectedSoundId, "(%d+)") or "9114408107"
    local assetUrl = "https://www.roblox.com/asset/?id=" .. pureId

    local playSongRemote = ReplicatedStorage:FindFirstChild("Remotes") 
        and ReplicatedStorage.Remotes:FindFirstChild("Inventory") 
        and ReplicatedStorage.Remotes.Inventory:FindFirstChild("PlaySong")

    local effectiveVolume = soundVolume
    if playAllFEEnabled and playSongRemote then
        pcall(function()
            playSongRemote:FireServer(assetUrl)
        end)
        effectiveVolume = 0
    end

    local soundObj = Instance.new("Sound")
    soundObj.SoundId = selectedSoundId
    soundObj.Volume = effectiveVolume
    soundObj.PlayOnRemove = true
    soundObj.Parent = workspace
    soundObj:Play()

    soundObj.Ended:Connect(function()
        if playAllFEEnabled and playSongRemote then
            pcall(function()
                playSongRemote:FireServer("https://www.roblox.com/asset/?id=0")
            end)
        end
    end)

    task.spawn(function()
        local startTime = tick()
        while soundObj.TimeLength == 0 and tick() - startTime < 2 do
            task.wait(0.05)
        end
        local length = soundObj.TimeLength
        if not length or length == 0 then
            length = 0.5
        end
        task.wait(length)
        if playAllFEEnabled and playSongRemote then
            pcall(function()
                playSongRemote:FireServer("https://www.roblox.com/asset/?id=0")
            end)
        end
    end)
end

-- Function to hook into the character's humanoid state changes
local function setupCharacter(char)
    if connection then
        connection:Disconnect()
        connection = nil
    end

    local humanoid = char:WaitForChild("Humanoid", 5)
    if humanoid then
        connection = humanoid.StateChanged:Connect(function(old, new)
            if customEnabled and new == Enum.HumanoidStateType.Jumping then
                triggerJumpSound()
            end
        end)
    end
end

if LocalPlayer.Character then
    setupCharacter(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(setupCharacter)

-- Toggle for enabling/disabling jump sound
jumpSoundSection:AddToggle("Jump Sound [ Client Sided ]", function(bool)
    customEnabled = bool
    getgenv().JumpSound_Enabled = bool
end)

-- Toggle for Play For all [ FE ]
jumpSoundSection:AddToggle("Play For all [ FE ]", function(bool)
    playAllFEEnabled = bool
    getgenv().JumpSound_PlayAllFE = bool
end)

-- TextBox for custom SoundId
jumpSoundSection:AddTextBox("Custom SoundId", function(text)
    if text and text ~= "" then
        if not string.find(text, "rbxassetid://") then
            customTextboxId = "rbxassetid://" .. text
        else
            customTextboxId = text
        end
        getgenv().JumpSound_CustomId = customTextboxId
        
        if lastSelected == "Custom" then
            selectedSoundId = customTextboxId
            getgenv().JumpSound_SavedId = selectedSoundId
        end
    end
end)

-- Dropdown to select the custom sound
local dropdownOptions = {}
for _, data in ipairs(sounds) do
    local name = string.match(data, "(.-)|%d+")
    table.insert(dropdownOptions, name)
end

local dropdown = jumpSoundSection:AddDropdown("Select Jump Sound", dropdownOptions, function(selected)
    lastSelected = selected
    getgenv().JumpSound_SavedName = selected

    if selected == "Custom" then
        selectedSoundId = customTextboxId
    else
        for _, data in ipairs(sounds) do
            local name, id = string.match(data, "(.-)|(%d+)")
            if name == selected then
                selectedSoundId = "rbxassetid://" .. id
                break
            end
        end
    end
    getgenv().JumpSound_SavedId = selectedSoundId
end)

pcall(function() 
    if dropdown and dropdown.Select then
        dropdown.Select(getgenv().JumpSound_SavedName) 
    end
end)

-- Volume Slider
pcall(function()
    jumpSoundSection:AddSlider("Volume", 0, 10, soundVolume * 10, function(value)
        soundVolume = value / 10
        getgenv().JumpSound_Volume = soundVolume
    end)
end)

-- Test Sound Effect Button
jumpSoundSection:AddButton("Test Sound Effect", function()
    playSound(selectedSoundId, soundVolume)
end)

end }

-- ================================================================
-- Module: SprayPaint Mods
-- Source: https://raw.githubusercontent.com/B6O6S/Better-Odh-tabs/main/SprayPaint%20Mods | Git blob 356d23d1bb6258c4208958cdf750fec479b8e37d
definitions[#definitions + 1] = { name = "SprayPaint Mods", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

local shared = odh_shared_plugins
local spray_tab = shared.CreateTab("Better ODH", "/axioriasolver/testplugin/refs/heads/main/icon")
local spray_section = spray_tab:AddSection("SprayPaint Mods", "Active Configuration")

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Variables for IDs (6 images) and Sequential state
local imageIds = {"", "", "", "", "", ""}
local loopSprayEnabled = false
local infiniteDistanceEnabled = false
local isSeqRunning = false

spray_section:AddLabel("⚠️ You need to manually click (Add)")

-- UI Setup: Toggles FIRST on top
spray_section:AddToggle("Loop Add SprayPaints IDs", function(bool)
    loopSprayEnabled = bool
    if not bool then
        isSeqRunning = false
    end
end)

spray_section:AddToggle("Infinite Spray Distance (Buggy)", function(on)
    infiniteDistanceEnabled = on
end)


-- 6 Textboxes BELOW label/toggles
for i = 1, 6 do
    spray_section:AddTextBox("Image " .. i, function(text)
        imageIds[i] = text or ""
    end)
end

local function getGameTextBox()
    return playerGui:FindFirstChild("SprayGui")
        and playerGui.SprayGui:FindFirstChild("Main")
        and playerGui.SprayGui.Main:FindFirstChild("Container")
        and playerGui.SprayGui.Main.Container:FindFirstChild("Add")
        and playerGui.SprayGui.Main.Container.Add:FindFirstChild("Frame")
        and playerGui.SprayGui.Main.Container.Add.Frame:FindFirstChild("Container")
        and playerGui.SprayGui.Main.Container.Add.Frame.Container:FindFirstChild("TextBox")
end

local function getSprayTool()
    local char = player.Character
    if char and char:FindFirstChild("SprayPaint") then
        return char.SprayPaint
    end
    local bp = player:FindFirstChild("Backpack")
    if bp and bp:FindFirstChild("SprayPaint") then
        return bp.SprayPaint
    end
    return nil
end

local function invokeRemote(assetId)
    local sprayPaint = getSprayTool()
    if not sprayPaint then return false end
    local remote = sprayPaint:FindFirstChild("SprayClient") and sprayPaint.SprayClient:FindFirstChild("GetAssetApproved")
    if remote and remote:IsA("RemoteFunction") then
        local success, result = pcall(function()
            return remote:InvokeServer(tonumber(assetId) or assetId)
        end)
        return success, result
    end
    return false
end

-- Checks if image asset ID rendered in spray list GUI right now
local function isImageLoadedInGui(assetId)
    local targetStr = tostring(assetId)
    local searchRoot = playerGui:FindFirstChild("SprayGui") or playerGui
    for _, desc in ipairs(searchRoot:GetDescendants()) do
        if (desc:IsA("ImageLabel") or desc:IsA("ImageButton")) and string.find(desc.Image, targetStr, 1, true) then
            return true
        end
    end
    return false
end

-- Collect valid non-empty IDs list (up to 6)
local function getValidIds()
    local valid = {}
    for i = 1, 6 do
        local clean = tostring(imageIds[i] or ""):gsub("%s+", "")
        if clean ~= "" and clean ~= "nil" then
            table.insert(valid, {index = i, id = clean})
        end
    end
    return valid
end

-- Continuous Enforcer / Monitor Loop: Checks if all valid IDs (1-6) are detected; restarts from start if any missing
task.spawn(function()
    while task.wait(0.8) do
        if loopSprayEnabled and not isSeqRunning then
            local tool = getSprayTool()
            if tool then
                local validList = getValidIds()
                if #validList > 0 then
                    local allLoaded = true
                    for _, item in ipairs(validList) do
                        if not isImageLoadedInGui(item.id) then
                            allLoaded = false
                            break
                        end
                    end
                    
                    -- If any image 1-6 is not detected in game UI, restart sequence from beginning
                    if not allLoaded then
                        isSeqRunning = true
                        task.spawn(function()
                            for _, item in ipairs(validList) do
                                if not loopSprayEnabled then break end
                                while loopSprayEnabled and not getSprayTool() do
                                    task.wait(0.5)
                                end
                                if not loopSprayEnabled then break end
                                
                                local cleanId = item.id
                                local tb = getGameTextBox()
                                if tb and tb:IsA("TextBox") then
                                    tb.Text = cleanId
                                end
                                invokeRemote(cleanId)
                                
                                -- Wait until detected in UI or retry slice
                                local elapsed = 0
                                while loopSprayEnabled and elapsed < 4.0 do
                                    if isImageLoadedInGui(cleanId) then break end
                                    invokeRemote(cleanId)
                                    task.wait(0.4)
                                    elapsed = elapsed + 0.4
                                end
                                task.wait(0.2)
                            end
                            isSeqRunning = false
                        end)
                    end
                end
            end
        end
    end
end)

-- Infinite Spray Distance (Buggy) override loop
task.spawn(function()
    while true do
        task.wait(0.3)
        if infiniteDistanceEnabled then
            local sprayPaint = getSprayTool()
            if sprayPaint then
                pcall(function()
                    sprayPaint:SetAttribute("MaxDistance", math.huge)
                    sprayPaint:SetAttribute("Range", math.huge)
                    sprayPaint:SetAttribute("SprayDistance", math.huge)
                    sprayPaint:SetAttribute("Reach", math.huge)
                    for _, v in ipairs(sprayPaint:GetDescendants()) do
                        if v:IsA("NumberValue") or v:IsA("IntValue") then
                            local n = v.Name:lower()
                            if n:find("dist") or n:find("range") or n:find("reach") then
                                v.Value = math.huge
                            end
                        end
                    end
                end)
            end
        end
    end
end)

if hookmetamethod and getnamecallmethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if infiniteDistanceEnabled and (method == "Raycast" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRay") then
            -- Intercept ray reach if game uses native ray casting
        end
        return oldNamecall(self, ...)
    end)
end


end }

-- ================================================================
-- Module: Credits
-- Source: https://raw.githubusercontent.com/B6O6S/Better-Odh-tabs/main/Credits | Git blob e550fc4490675f885cd624e271c69d233ddbdf5d
definitions[#definitions + 1] = { name = "Credits", initialize = function(ctx)
    -- Some original sound modules use getgenv; keep an in-session fallback.
    local getgenv = type(getgenv) == "function" and getgenv or function() return _G end
    local odh_shared_plugins = ctx.shared
    local shared = ctx.shared
    local tab = ctx.tab
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = assert(Players.LocalPlayer, "LocalPlayer unavailable; run on the client")
    local Camera = workspace.CurrentCamera
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not become available within 10 seconds")

local shared = odh_shared_plugins

local credits_tab = shared.CreateTab("Better ODH", "/B6O6S/Better-ODH/refs/heads/main/Better%20ODH")
local credits_section = credits_tab:AddSection("Credits", "Author Info")

credits_section:AddLabel('Credits To: <font color="rgb(255,0,0)">B6O6S (@B6O6S) - Owner/Programmer</font>')
credits_section:AddLabel('Credits To: <font color="rgb(255,0,0)">k.6z (@3r_q5) - Helper/Tester</font>')
credits_section:AddLabel('Note: <font color="rgb(0,255,0)">We really spent alot of time trying to make the best</font>')
credits_section:AddLabel('<font color="rgb(0,255,0)">and fun plugin for everyone to use for free and enjoy</font>')
credits_section:AddLabel('<font color="rgb(0,255,0)">our dms is open feel free to ask or giving suggestions</font>')
credits_section:AddLabel('<font color="rgb(0,255,0)">or reporting bugs, have fun ♥️</font>')

if shared and shared.Notify then
    shared.Notify("Better ODH Plugin Loaded Successfully!", 1)
end

end }

-- Create all sections on ONE tab, in a deterministic order.
for _,definition in ipairs(definitions) do
    local record = { name=definition.name, state="Queued", controls=0 }
    runtime.modules[#runtime.modules+1] = record
    local ok,section = pcall(function() return rootTab:AddSection(definition.name, "UNIVERSAL") end)
    if not ok or not section then
        runtime.failed=runtime.failed+1
        setStatus(record,"ERROR",tostring(section))
        warn("[Better ODH / " .. definition.name .. "] AddSection failed: " .. tostring(section))
    else
        record.rawSection=section
        pcall(function() record.statusLabel=section:AddLabel("Loading module...",true) end)
        record.context=contextFor(record)
        record.definition=definition
        runtime.pending=runtime.pending+1
    end
end

for _,record in ipairs(runtime.modules) do
    if record.context then
        task.spawn(function()
            setStatus(record,"Loading")
            local ctx=record.context
            local ok,err=xpcall(function() record.definition.initialize(ctx) end,traceback)
            ctx.initializing=false
            if ok and ctx.controls>0 then
                local restored,restoreErr=xpcall(ctx.Restore,traceback)
                if not restored then
                    ctx.restoring=false
                    record.restoreError=tostring(restoreErr)
                    warn("[Better ODH Save / " .. record.name .. "] " .. tostring(restoreErr))
                end
            end
            record.controls=ctx.controls
            record.definition=nil
            runtime.pending=runtime.pending-1
            if ok and ctx.controls>0 then
                runtime.ready=runtime.ready+1
                setStatus(record,"Ready",tostring(ctx.controls) .. " elements")
            else
                runtime.failed=runtime.failed+1
                local message=ok and "Module did not add any controls" or tostring(err)
                setStatus(record,"ERROR","See [Better ODH / " .. record.name .. "] in console")
                record.error=message
                warn("[Better ODH / " .. record.name .. "] " .. message)
            end
            if runtime.pending==0 then
                notify("Better ODH: " .. runtime.ready .. "/20 modules initialized"
                    .. (runtime.failed>0 and ("; errors: " .. runtime.failed .. ". See console.") or "."),5)
            end
        end)
    end
end

task.delay(20,function()
    if runtime.pending>0 then
        for _,record in ipairs(runtime.modules) do
            if record.state=="Loading" or record.state=="Queued" then
                setStatus(record,"Waiting","Game objects are not ready; other modules are independent")
                warn("[Better ODH / " .. record.name .. "] Still waiting for game objects. Other sections continue to load.")
            end
        end
    end
end)
