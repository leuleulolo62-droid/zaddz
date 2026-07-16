-- zaddz — full demo. 1:1 susano style, every tab populated.
-- INSERT opens/closes the menu (rebindable in Settings).
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/leuleulolo62-droid/zaddz/main/zaddz.lua"))()

local Window = Library:CreateWindow({ Title = "SUSANO.RE", ToggleKey = Enum.KeyCode.Insert })

-- sidebar rail, Figma order. Default = the globe, like the design.
local Fav   = Window:AddTab("Favourites",   "star")
local Net   = Window:AddTab("Network",      "wifi")
local World = Window:AddTab("Local Player", "globe", { Default = true })
local Vis   = Window:AddTab("Visuals",      "eye")
local Weap  = Window:AddTab("Weapons",      "pistol")
local Veh   = Window:AddTab("Vehicles",     "car")
local Misc  = Window:AddTab("Misc",         "grid")

-- ─────────────────────────── LOCAL PLAYER (the Figma screen)
local C = World:AddSection("Conditions", "Left")
C:AddToggle("GodMode",         { Text = "God Mode", Key = "G",
    Tooltip = "Blocks all incoming damage." })
C:AddToggle("SemGodMode",      { Text = "Sem God Mode" })
C:AddToggle("Invisible",       { Text = "Invsible" })
C:AddToggle("SuperJump",       { Text = "Super Jump",       Key = "Space", Mode = "Hold" })
C:AddToggle("InfiniteStamina", { Text = "Infinite Stamina" })
C:AddToggle("NoRagdoll",       { Text = "No Ragdoll" })
C:AddToggle("NoClip",          { Text = "NoClip", Default = true, Key = "N",
    Tooltip = "Walk through walls. Disables collision on your character." })
C:AddToggle("InvisibleNoClip", { Text = "Invisible NoClip", Default = true })
C:AddToggle("RunSpeedTgl",     { Text = "Run Speed" })
C:AddToggle("SwimSpeedTgl",    { Text = "Swim Speed" })
C:AddToggle("NeverWanted",     { Text = "Never Wanted" })
C:AddToggle("NoCollision",     { Text = "No Colliision" })

local Cu = World:AddSection("Customization", "Right")
Cu:AddSlider("NoClipSpeed", { Text = "NoClip Speed",          Min = 0, Max = 10, Default = 1 })
Cu:AddSlider("RunMult",     { Text = "Run Speed Multiplier",  Min = 0, Max = 10, Default = 1, Suffix = "x" })
Cu:AddSlider("SwimMult",    { Text = "Swim Speed Multiplier", Min = 0, Max = 10, Default = 1, Suffix = "x" })
Cu:AddDropdown("NoClipMode", { Text = "NoClip Mode", Values = { "Direction", "Camera", "Free" }, Default = "Direction",
    Tooltip = "Direction follows your input; Camera follows where you look." })
Cu:AddTextbox("HealthAmount", { Text = "Health Amount", Default = "100" })
Cu:AddTextbox("ArmorAmount",  { Text = "Armor Amount",  Default = "100" })

-- ─────────────────────────── FAVOURITES
local F1 = Fav:AddSection("Pinned", "Left")
F1:AddToggle("FavGod",   { Text = "God Mode",  Key = "F1" })
F1:AddToggle("FavNoclip",{ Text = "NoClip",    Key = "F2" })
F1:AddToggle("FavESP",   { Text = "Player ESP", Key = "F3" })
F1:AddSlider("FavSpeed", { Text = "Speed", Min = 0, Max = 100, Default = 16, Rounding = 0, Format = "%d" })
local F2 = Fav:AddSection("Quick", "Right")
F2:AddButton("Rejoin Server", function() Library:Notify("Rejoining...") end)
F2:AddButton("Unload Menu", function() Library:Unload() end)
F2:AddLabel("Pin anything here for one-key access.")

-- ─────────────────────────── NETWORK
local N1 = Net:AddSection("Session", "Left")
N1:AddToggle("AntiKick",   { Text = "Anti Kick" })
N1:AddToggle("AntiCrash",  { Text = "Anti Crash" })
N1:AddToggle("HideFromList", { Text = "Hide From Player List" })
N1:AddToggle("SpoofName",  { Text = "Spoof Name" })
local N2 = Net:AddSection("Players", "Right")
N2:AddDropdown("TargetPlayer", { Text = "Target", Values = { "None" }, Default = "None" })
N2:AddSlider("PingLimit", { Text = "Ping Limit", Min = 0, Max = 500, Default = 250, Rounding = 0, Format = "%d", Suffix = "ms" })
N2:AddButton("Refresh Players", function()
    local names = {}
    for _, p in ipairs(game:GetService("Players"):GetPlayers()) do table.insert(names, p.Name) end
    Library.Options.TargetPlayer:SetValues(names)
    Library:Notify(#names .. " players")
end)

-- ─────────────────────────── VISUALS  (colour pickers live here)
local V1 = Vis:AddSection("ESP", "Left")
V1:AddToggle("ESPEnabled", { Text = "Enabled", Key = "H" })
V1:AddToggle("ESPBox",     { Text = "2D Box" })
V1:AddToggle("ESPName",    { Text = "Names" })
V1:AddToggle("ESPHealth",  { Text = "Health Bar" })
V1:AddToggle("ESPTracer",  { Text = "Tracers" })
V1:AddToggle("ESPSkeleton",{ Text = "Skeleton" })
V1:AddSlider("ESPDistance", { Text = "Max Distance", Min = 50, Max = 2000, Default = 1000, Rounding = 0, Format = "%d" })

local V2 = Vis:AddSection("Colors", "Right")
V2:AddColorPicker("BoxColor",     { Text = "Box Color",     Default = Color3.fromRGB(5, 150, 255) })
V2:AddColorPicker("NameColor",    { Text = "Name Color",    Default = Color3.fromRGB(255, 255, 255) })
V2:AddColorPicker("HealthColor",  { Text = "Health Color",  Default = Color3.fromRGB(60, 220, 90) })
V2:AddColorPicker("TracerColor",  { Text = "Tracer Color",  Default = Color3.fromRGB(255, 80, 80), Alpha = true })
V2:AddColorPicker("ChamsColor",   { Text = "Chams Color",   Default = Color3.fromRGB(160, 90, 255), Alpha = true })
V2:AddDropdown("ChamsStyle", { Text = "Chams Style", Values = { "Flat", "Thermal", "Black Mat" }, Default = "Flat" })

-- ─────────────────────────── WEAPONS
local W1 = Weap:AddSection("Aimbot", "Left")
W1:AddToggle("AimEnabled", { Text = "Enabled", Key = "MouseButton2", Mode = "Hold" })
W1:AddToggle("AimVisible", { Text = "Visible Check" })
W1:AddToggle("AimTeam",    { Text = "Team Check" })
W1:AddToggle("SilentAim",  { Text = "Silent Aim",
    Tooltip = "Redirects the bullet server-side without moving your camera." })
W1:AddSlider("AimFOV",    { Text = "FOV", Min = 0, Max = 500, Default = 120, Rounding = 0, Format = "%d",
    Tooltip = "Radius in pixels the aimbot will search for a target." })
W1:AddSlider("AimSmooth", { Text = "Smoothing", Min = 0, Max = 1, Default = 0.25 })
W1:AddDropdown("AimPart", { Text = "Target Part", Values = { "Head", "Torso", "Nearest" }, Default = "Head" })
local W2 = Weap:AddSection("Weapon Mods", "Right")
W2:AddToggle("NoRecoil",  { Text = "No Recoil" })
W2:AddToggle("NoSpread",  { Text = "No Spread" })
W2:AddToggle("RapidFire", { Text = "Rapid Fire" })
W2:AddToggle("InfAmmo",   { Text = "Infinite Ammo" })
W2:AddSlider("FireRate",  { Text = "Fire Rate", Min = 0.01, Max = 1, Default = 0.1 })
W2:AddColorPicker("FOVColor", { Text = "FOV Circle", Default = Color3.fromRGB(5, 150, 255), Alpha = true })

-- ─────────────────────────── VEHICLES
local Ve1 = Veh:AddSection("Vehicle", "Left")
Ve1:AddToggle("VehGod",     { Text = "Vehicle God Mode" })
Ve1:AddToggle("VehFly",     { Text = "Vehicle Fly", Key = "V" })
Ve1:AddToggle("NoGrip",     { Text = "No Grip" })
Ve1:AddToggle("InstantStop",{ Text = "Instant Stop" })
Ve1:AddSlider("VehSpeed",   { Text = "Speed Multiplier", Min = 1, Max = 10, Default = 1, Suffix = "x" })
local Ve2 = Veh:AddSection("Spawn", "Right")
Ve2:AddDropdown("VehModel", { Text = "Model", Values = { "Sultan", "Adder", "Police" }, Default = "Sultan" })
Ve2:AddColorPicker("VehColor", { Text = "Paint", Default = Color3.fromRGB(30, 30, 30) })
Ve2:AddButton("Spawn Vehicle", function() Library:Notify("Spawned " .. tostring(Library.Flags.VehModel)) end)

-- ─────────────────────────── MISC / SETTINGS
local M1 = Misc:AddSection("Settings", "Left")
M1:AddToggle("Watermark", { Text = "Watermark", Default = true,
    Callback = function(v) Library:SetWatermark(v) end })
M1:AddToggle("Keybinds", { Text = "Keybind List", Key = "K",
    Callback = function(v) Library:SetKeybindList(v) end })
M1:AddColorPicker("Accent", { Text = "Menu Accent", Default = Color3.fromRGB(5, 150, 255),
    Callback = function(c) Library:SetAccent(c) end })
M1:AddDropdown("MenuKey", { Text = "Menu Key", Values = { "Insert", "RightShift", "RightControl", "F4" }, Default = "Insert",
    Callback = function(v) Library.ToggleKey = Enum.KeyCode[v] end })
local M2 = Misc:AddSection("Config", "Right")
M2:AddTextbox("ConfigName", { Text = "Config Name", Placeholder = "default" })
M2:AddButton("Save Config", function() Library:Notify("Saved " .. tostring(Library.Flags.ConfigName)) end)
M2:AddButton("Load Config", function() Library:Notify("Loaded") end)
M2:AddButton("Unload", function() Library:Unload() end, "Destroys the menu. Re-execute the script to get it back.")

-- Defaults are applied silently (no callback), so drive the initial HUD state directly.
Library:SetWatermark(true)

Library:Notify("zaddz loaded — INSERT to toggle", 4)
