local shared = odh_shared_plugins
local tab = shared.CreateTab("Better ODH", "/B6O6S/Better-ODH/refs/heads/main/Better%20ODH")

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


