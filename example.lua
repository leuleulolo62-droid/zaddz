-- zaddz — 1:1 rebuild of the susano "World > Local Player" screen
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/leuleulolo62-droid/zaddz/main/zaddz.lua"))()

local Window = Library:CreateWindow({ Title = "SUSANO.RE" })

-- Sidebar rail, in the Figma's order (icons are the real exported PNGs)
local Fav    = Window:AddTab("Favourites", "star")
local Net    = Window:AddTab("Network", "wifi")
local World  = Window:AddTab("Local Player", "globe")   -- selected in the design
local Vis    = Window:AddTab("Visuals", "eye")
local Weap   = Window:AddTab("Weapons", "pistol")
local Veh    = Window:AddTab("Vehicles", "car")
local Misc   = Window:AddTab("Misc", "grid")

-- LEFT: Conditions
local C = World:AddSection("Conditions", "Left")
C:AddToggle("GodMode",         { Text = "God Mode" })
C:AddToggle("SemGodMode",      { Text = "Sem God Mode" })
C:AddToggle("Invisible",       { Text = "Invsible" })
C:AddToggle("SuperJump",       { Text = "Super Jump" })
C:AddToggle("InfiniteStamina", { Text = "Infinite Stamina" })
C:AddToggle("NoRagdoll",       { Text = "No Ragdoll" })
C:AddToggle("NoClip",          { Text = "NoClip", Default = true })          -- blue in the design
C:AddToggle("InvisibleNoClip", { Text = "Invisible NoClip", Default = true }) -- blue in the design
C:AddToggle("RunSpeedTgl",     { Text = "Run Speed" })
C:AddToggle("SwimSpeedTgl",    { Text = "Swim Speed" })
C:AddToggle("NeverWanted",     { Text = "Never Wanted" })
C:AddToggle("NoCollision",     { Text = "No Colliision" })

-- RIGHT: Customization
local Cu = World:AddSection("Customization", "Right")
Cu:AddSlider("NoClipSpeed", { Text = "NoClip Speed",         Min = 0, Max = 10, Default = 1 })
Cu:AddSlider("RunMult",     { Text = "Run Speed Multiplier",  Min = 0, Max = 10, Default = 1, Suffix = "x" })
Cu:AddSlider("SwimMult",    { Text = "Swim Speed Multiplier", Min = 0, Max = 10, Default = 1, Suffix = "x" })
Cu:AddDropdown("NoClipMode", { Text = "NoClip Mode", Values = { "Direction", "Camera", "Free" }, Default = "Direction" })
Cu:AddTextbox("HealthAmount", { Text = "Health Amount", Default = "100" })
Cu:AddTextbox("ArmorAmount",  { Text = "Armor Amount",  Default = "100" })

-- read:  Library.Flags.NoClip / Library.Flags.NoClipSpeed
-- write: Library.Toggles.NoClip:SetValue(true) / Library.Options.NoClipSpeed:SetValue(5)
Library:Notify("zaddz loaded — RightShift to toggle", 4)
