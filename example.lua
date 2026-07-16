-- zaddz demo — mirrors the susano Figma layout (World > Local Player)
local Library = loadstring(readfile("zaddz.lua"))()

local Window = Library:CreateWindow({ Title = "SUSANO.RE" })

-- Sidebar tabs (pass an rbxassetid for real icons)
local World  = Window:AddTab("World")
local Combat = Window:AddTab("Combat")
local Visual = Window:AddTab("Visuals")
local Config = Window:AddTab("Config")

-- LEFT panel
local LP = World:AddSection("Local Player", "Left")
LP:AddToggle("GodMode",         { Text = "God Mode",         Callback = function(v) print("god", v) end })
LP:AddToggle("SemGodMode",      { Text = "Sem God Mode" })
LP:AddToggle("Invisible",       { Text = "Invisible" })
LP:AddToggle("SuperJump",       { Text = "Super Jump" })
LP:AddToggle("InfiniteStamina", { Text = "Infinite Stamina" })
LP:AddToggle("NoRagdoll",       { Text = "No Ragdoll" })
LP:AddToggle("NoClip",          { Text = "NoClip" })
LP:AddToggle("InvisibleNoClip", { Text = "Invisible NoClip" })
LP:AddSlider("RunSpeed",  { Text = "Run Speed",  Min = 0, Max = 200, Default = 16 })
LP:AddSlider("SwimSpeed", { Text = "Swim Speed", Min = 0, Max = 200, Default = 16 })

-- RIGHT panel
local C = World:AddSection("Conditions", "Right")
C:AddToggle("NeverWanted", { Text = "Never Wanted" })
C:AddDropdown("Weather", { Text = "Weather", Values = { "Clear", "Rain", "Fog", "Storm" }, Default = "Clear" })
C:AddTextbox("PlayerName", { Text = "Target", Placeholder = "username" })
C:AddKeybind("PanicKey", { Text = "Panic", Default = "End", Pressed = function() Library:Notify("Panic!") end })
C:AddButton("Apply", function() Library:Notify("Applied") end)

local Cu = World:AddSection("Customization", "Right")
Cu:AddLabel("Accent, layout and animation all come from the Figma tokens.")
Cu:AddButton("Notify", function() Library:Notify("zaddz is alive") end)

Combat:AddSection("Aimbot", "Left"):AddToggle("Aim", { Text = "Enabled" })
Visual:AddSection("ESP", "Left"):AddToggle("Boxes", { Text = "Boxes" })
Config:AddSection("Menu", "Left"):AddButton("Unload", function() Library:Unload() end)

Library:Notify("zaddz loaded — RightShift to toggle", 4)
