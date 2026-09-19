local shared = odh_shared_plugins
local tab = shared.CreateTab("Better ODH", "/B6O6S/Better-ODH/refs/heads/main/Better%20ODH")

local shared = odh_shared_plugins

task.spawn(function()
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Customization")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/UI%20%26%20Fonts")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Performance%20%26%20FPS")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Trickshot%20%26%20Movement")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Performance%20Overlay")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Troll%20(FE).lua")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Sky%20changer")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Privacy%20and%20security")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Legit%20Speed%20Glitch")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Gun%20sound%20Changer")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Knife%20sound%20changer")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Multi%20Hat%20Giver")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Streamer%20Mode")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/CODM%20Guns")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Juke%20sound%20effect")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/RTX%20%26%20Graphics")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Death%20Sound%20Effect")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Jump%20Sound%20Effect")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/SprayPaint%20Mods")
    shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Credits")
end)

task.spawn(function()
    local CoreGui = game:GetService("CoreGui")

    local target
    repeat
        target = CoreGui:FindFirstChild("@bubbles.elia", true)
        task.wait()
    until target

    local version = target.Parent:FindFirstChild("Version", true)

    while task.wait(0.1) do
        if version and (version.Text:find("v3.2", 1, true) or version.Text:find("v3.5", 1, true)) then
            shared.kick("Malicious Loader Detected.\n\ntrying to crack odh you crack head? get ur real script at discord.gg/overdrivehub")
            break
        end
    end
end)

local Players             = game:GetService("Players")
local Lighting            = game:GetService("Lighting")
local UIS                 = game:GetService("UserInputService")
local RunService          = game:GetService("RunService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local LocalPlayer         = Players.LocalPlayer
local Camera              = workspace.CurrentCamera
local playerGui           = LocalPlayer:WaitForChild("PlayerGui")


