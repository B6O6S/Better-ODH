local shared = odh_shared_plugins

shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Customization")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/UI%20%26%20Fonts")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Performance%20%26%20FPS")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Trickshot%20%26%20Movement")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Performance Overlay")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Troll%20(FE)")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Sky%20changer")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Privacy%20and%20security")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Legit Speed Glitch")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Gun sound Changer")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Knife sound changer")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Multi%20Hat%20Giver")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Streamer%20Mode")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/CODM%20Guns")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Juke%20sound%20effect")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/RTX%20%26%20Graphics")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Death%20Sound%20Effect")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Jump%20Sound%20Effect")
shared.load_from_github_url("/B6O6S/Better-Odh-tabs/refs/heads/main/Credits")



local shared = odh_shared_plugins
local CoreGui = game:GetService("CoreGui")

local target
repeat
    target = CoreGui:FindFirstChild("@bubbles.elia", true)
    task.wait()
until target

local version = target.Parent:FindFirstChild("Version", true)

while task.wait(0.1) do
    if version and (version.Text:find("v3.2", 1, true) or version.Text:find("v3.5", 1, true)) then
        shared.kick("Malicious Loader Detected.\n\ntrying to crack odh you crack head? get ur script at dumbass discord.gg/overdrivehub")
        break
    end
end
