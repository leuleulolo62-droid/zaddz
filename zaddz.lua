--[[
    zaddz — Roblox UI library, a 1:1 rebuild of the susano FiveM menu
    Figma: apFxClc2AyZM8QXSZwQoZF (node 1:3 "imgui :))")

    Every number below is measured from the Figma file, not eyeballed:
      window          851x597         sidebar 72w #101010 | body #131313 r7
      left panel      342x452 @103,125   #1e1e1e r12
      right panel     342x373 @456,123   #1e1e1e r12
      toggle box      23x23 @x115        #282828, checked = 19x19 #0596ff inset +2
      toggle rows     start y158, step 34
      row label       @x150              keybind glyph @x403 (24x24)
      panel scrollbar 2x247 @438,129     #416dbc
      slider row      301x34 @x476       #282828 + 2px #4583d9 underline (width = value)
      dropdown        301x34 + FULL 301x2 underline
      textbox         301x25             dim label sits ABOVE the box
      text            Inter 400 14 #ffffff -> Gotham 14

    Icons are the real exported Figma PNGs. They're fetched from the repo and mounted
    with getcustomasset(), so no Roblox upload is needed. Override via opts.Icons.

    Usage:
      local Library = loadstring(game:HttpGet(".../zaddz.lua"))()
      local Window  = Library:CreateWindow({ Title = "SUSANO.RE" })
      local Tab     = Window:AddTab("World", "globe")
      local Sec     = Tab:AddSection("Conditions", "Left")
      Sec:AddToggle("NoClip", { Text = "NoClip", Default = true, Callback = print })
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Library = {
    Flags = {}, Options = {}, Toggles = {}, Connections = {},
    Theme = {
        Body      = Color3.fromRGB(19, 19, 19),    -- #131313
        Sidebar   = Color3.fromRGB(16, 16, 16),    -- #101010
        Panel     = Color3.fromRGB(30, 30, 30),    -- #1e1e1e
        Element   = Color3.fromRGB(40, 40, 40),    -- #282828
        Hover     = Color3.fromRGB(52, 52, 52),
        Accent    = Color3.fromRGB(5, 150, 255),   -- #0596ff
        AccentDim = Color3.fromRGB(69, 131, 217),  -- #4583d9 (slider fill)
        Scroll    = Color3.fromRGB(65, 109, 188),  -- #416dbc
        Text      = Color3.fromRGB(255, 255, 255),
        TextDim   = Color3.fromRGB(138, 138, 138),
        Icon      = Color3.fromRGB(170, 170, 170), -- #aaaaaa
        Font      = Enum.Font.Gotham,
        FontBold  = Enum.Font.GothamBold,
        TextSize  = 14,
    },
    ToggleKey = Enum.KeyCode.RightShift,
    IconBase = "https://raw.githubusercontent.com/leuleulolo62-droid/zaddz/main/icons/",
    _icons = {},
}
local T = Library.Theme
local function TW(t, style)
    return TweenInfo.new(t or 0.18, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

-- ------------------------------------------------------------------ helpers

local function new(class, props, children)
    local i = Instance.new(class)
    for k, v in pairs(props or {}) do if k ~= "Parent" then i[k] = v end end
    for _, c in ipairs(children or {}) do c.Parent = i end
    if props and props.Parent then i.Parent = props.Parent end
    return i
end
local function corner(p, r) return new("UICorner", { CornerRadius = UDim.new(0, r or 6), Parent = p }) end
local function tween(o, p, t, s) local x = TweenService:Create(o, TW(t, s), p) x:Play() return x end
local function conn(sig, fn) local c = sig:Connect(fn) table.insert(Library.Connections, c) return c end

-- Mount the exported Figma PNGs as local assets. getcustomasset gives an rbxasset://
-- URL for a file in the executor workspace, so the real icons work with no upload.
-- Falls back to "" (no image) on executors without writefile/getcustomasset.
function Library:LoadIcon(name)
    if self._icons[name] then return self._icons[name] end
    local id = ""
    local ok = pcall(function()
        local path = "zaddz_icons/" .. name .. ".png"
        if not (isfile and isfile(path)) then
            if makefolder and not (isfolder and isfolder("zaddz_icons")) then makefolder("zaddz_icons") end
            local data = game:HttpGet(self.IconBase .. name .. ".png", true)
            writefile(path, data)
        end
        id = getcustomasset(path)
    end)
    if not ok then id = "" end
    self._icons[name] = id
    return id
end

function Library:Notify(text, duration)
    local holder = self._notify
    if not holder then return end
    local item = new("Frame", {
        BackgroundColor3 = T.Panel, Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1, BorderSizePixel = 0, Parent = holder,
    })
    corner(item, 8)
    local bar = new("Frame", {
        BackgroundColor3 = T.Accent, Size = UDim2.new(0, 3, 1, -12),
        Position = UDim2.fromOffset(6, 6), BorderSizePixel = 0, Parent = item,
    })
    corner(bar, 2)
    local lbl = new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, -22, 1, 0), Position = UDim2.fromOffset(16, 0),
        Font = T.Font, TextSize = 13, TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
        Text = tostring(text), TextTransparency = 1, Parent = item,
    })
    tween(item, { BackgroundTransparency = 0 }, 0.2)
    tween(lbl, { TextTransparency = 0 }, 0.2)
    task.delay(duration or 3, function()
        tween(item, { BackgroundTransparency = 1 }, 0.2)
        tween(lbl, { TextTransparency = 1 }, 0.2)
        task.delay(0.25, function() item:Destroy() end)
    end)
end

-- ------------------------------------------------------------------ window

function Library:CreateWindow(opts)
    opts = opts or {}
    local title = opts.Title or "SUSANO.RE"

    local parent = opts.Parent
    if not parent then
        local ok, hui = pcall(function() return gethui and gethui() end)
        parent = (ok and hui) or game:GetService("CoreGui")
    end

    local ScreenGui = new("ScreenGui", {
        Name = opts.Name or "zaddz", ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 9999, Parent = parent,
    })
    self._gui = ScreenGui

    self._notify = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.fromOffset(250, 400),
        Position = UDim2.new(1, -260, 0, 10), Parent = ScreenGui,
    })
    new("UIListLayout", { Padding = UDim.new(0, 6), Parent = self._notify })

    -- root 851x597
    local Main = new("Frame", {
        Name = "Main", BackgroundColor3 = T.Sidebar, Size = UDim2.fromOffset(0, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5),
        BorderSizePixel = 0, ClipsDescendants = true, Parent = ScreenGui,
    })
    corner(Main, 7)
    self._main = Main
    tween(Main, { Size = UDim2.fromOffset(851, 597) }, 0.3, Enum.EasingStyle.Back)

    -- body #131313 @x3 (Figma: Rectangle 1 at x=3, w=848)
    local Body = new("Frame", {
        BackgroundColor3 = T.Body, Position = UDim2.fromOffset(3, 0),
        Size = UDim2.fromOffset(848, 597), BorderSizePixel = 0, Parent = Main,
    })
    corner(Body, 7)
    -- sidebar 72w #101010 sits on top of the body's left edge
    local Sidebar = new("Frame", {
        BackgroundColor3 = T.Sidebar, Size = UDim2.fromOffset(72, 597),
        BorderSizePixel = 0, Parent = Main,
    })
    corner(Sidebar, 7)
    new("Frame", { -- square the sidebar's right edge
        BackgroundColor3 = T.Sidebar, Size = UDim2.fromOffset(10, 597),
        Position = UDim2.fromOffset(62, 0), BorderSizePixel = 0, Parent = Sidebar,
    })

    -- logo: Vector 1 @12,15 46x39, with the white glow from the render
    local LogoGlow = new("ImageLabel", {
        BackgroundTransparency = 1, Image = Library:LoadIcon("logo"),
        ImageColor3 = Color3.fromRGB(255, 255, 255), ImageTransparency = 0.72,
        Size = UDim2.fromOffset(66, 59), Position = UDim2.fromOffset(2, 5), Parent = Sidebar,
    })
    new("ImageLabel", {
        BackgroundTransparency = 1, Image = Library:LoadIcon("logo"),
        Size = UDim2.fromOffset(46, 39), Position = UDim2.fromOffset(12, 15), Parent = Sidebar,
    })
    task.spawn(function() -- slow logo breathe
        while ScreenGui.Parent do
            tween(LogoGlow, { ImageTransparency = 0.5 }, 1.4, Enum.EasingStyle.Sine)
            task.wait(1.4)
            tween(LogoGlow, { ImageTransparency = 0.82 }, 1.4, Enum.EasingStyle.Sine)
            task.wait(1.4)
        end
    end)

    -- breadcrumb: "World > " white + "Local Player" accent (Figma @104,30)
    local Crumb = new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(104, 30),
        Size = UDim2.fromOffset(400, 22), Font = T.Font, TextSize = 16, RichText = true,
        TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left, Text = title, Parent = Body,
    })
    self._crumb = Crumb

    -- gear, top-right
    local Gear = new("TextButton", {
        BackgroundTransparency = 1, Size = UDim2.fromOffset(26, 26),
        Position = UDim2.new(1, -50, 0, 28), Text = "", AutoButtonColor = false, Parent = Body,
    })
    local GearIco = new("ImageLabel", {
        BackgroundTransparency = 1, Image = "rbxassetid://11963341447", ImageColor3 = T.Icon,
        Size = UDim2.fromScale(1, 1), Parent = Gear,
    })
    conn(Gear.MouseEnter, function() tween(GearIco, { ImageColor3 = T.Text, Rotation = 45 }, 0.2) end)
    conn(Gear.MouseLeave, function() tween(GearIco, { ImageColor3 = T.Icon, Rotation = 0 }, 0.2) end)
    conn(Gear.MouseButton1Click, function() Library:Unload() end)

    -- pages live at the panel origin (Figma left panel @103,125 -> body-relative 100,125)
    local Container = new("Frame", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(100, 123),
        Size = UDim2.fromOffset(720, 460), Parent = Body,
    })

    -- drag by the header strip
    do
        local dragging, dragStart, startPos
        local Bar = new("TextButton", {
            BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
            Size = UDim2.new(1, -72, 0, 100), Position = UDim2.fromOffset(72, 0), Parent = Main,
        })
        conn(Bar.InputBegan, function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                dragging, dragStart, startPos = true, i.Position, Main.Position
            end
        end)
        conn(UserInputService.InputChanged, function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                local d = i.Position - dragStart
                Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
        conn(UserInputService.InputEnded, function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)
    end

    conn(UserInputService.InputBegan, function(i, gp)
        if not gp and i.KeyCode == Library.ToggleKey then ScreenGui.Enabled = not ScreenGui.Enabled end
    end)

    local Window = { Tabs = {}, _title = title, _current = nil }

    -- sidebar icon rail: Figma y = 101,158,214,264,298,351,405 (uneven -> use a table)
    local RAIL_Y = { 101, 158, 214, 264, 298, 351, 405, 459 }

    function Window:AddTab(name, icon)
        local idx = #Window.Tabs + 1
        local Tab = { Name = name, _window = Window }

        local y = RAIL_Y[idx] or (101 + (idx - 1) * 54)
        local Btn = new("TextButton", {
            BackgroundTransparency = 1, Size = UDim2.fromOffset(46, 46),
            Position = UDim2.fromOffset(13, y - 8), Text = "", AutoButtonColor = false, Parent = Sidebar,
        })
        -- glow behind the selected icon (the blue halo in the design)
        local Glow = new("ImageLabel", {
            BackgroundTransparency = 1, Image = icon and Library:LoadIcon(icon) or "",
            ImageColor3 = T.Accent, ImageTransparency = 1,
            Size = UDim2.fromOffset(40, 40), Position = UDim2.new(0.5, -20, 0.5, -20), Parent = Btn,
        })
        local Ico = new("ImageLabel", {
            BackgroundTransparency = 1, Image = icon and Library:LoadIcon(icon) or "",
            ImageColor3 = T.Icon, Size = UDim2.fromOffset(26, 26),
            Position = UDim2.new(0.5, -13, 0.5, -13), Parent = Btn,
        })
        if not icon then
            Ico.Image = ""
            new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
                Font = T.FontBold, TextSize = 12, TextColor3 = T.Icon, Text = name:sub(1, 2):upper(), Parent = Btn })
        end

        local Page = new("Frame", {
            Name = name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
            Visible = false, Parent = Container,
        })
        Tab._page, Tab._btn, Tab._ico, Tab._glow = Page, Btn, Ico, Glow

        function Tab:Select()
            for _, t in ipairs(Window.Tabs) do
                t._page.Visible = false
                tween(t._ico, { ImageColor3 = T.Icon, Size = UDim2.fromOffset(26, 26) }, 0.16)
                tween(t._glow, { ImageTransparency = 1, Size = UDim2.fromOffset(40, 40) }, 0.16)
            end
            Page.Visible = true
            tween(Ico, { ImageColor3 = T.Accent, Size = UDim2.fromOffset(30, 30) }, 0.18)
            tween(Glow, { ImageTransparency = 0.55, Size = UDim2.fromOffset(52, 52) }, 0.25)
            Window._current = Tab
            Library:SetCrumb(Window._title == name and name or (Window._root or "World"), name)
            Page.Position = UDim2.fromOffset(0, 8)
            tween(Page, { Position = UDim2.fromOffset(0, 0) }, 0.22)
        end
        conn(Btn.MouseButton1Click, function() Tab:Select() end)
        conn(Btn.MouseEnter, function()
            if Window._current ~= Tab then tween(Ico, { ImageColor3 = T.Text }, 0.12) end
        end)
        conn(Btn.MouseLeave, function()
            if Window._current ~= Tab then tween(Ico, { ImageColor3 = T.Icon }, 0.12) end
        end)

        -- Panels. Left = 342x452 @ (3,2) of the container, Right = 342x373 @ (356,0).
        function Tab:AddSection(sTitle, side)
            local right = (side == "Right")
            local Section = {}

            local Panel = new("Frame", {
                BackgroundColor3 = T.Panel,
                Size = UDim2.fromOffset(342, right and 373 or 452),
                Position = right and UDim2.fromOffset(356, 0) or UDim2.fromOffset(3, 2),
                BorderSizePixel = 0, Parent = Page,
            })
            corner(Panel, 12)

            -- title, centred (Figma "Conditions" / "Customization")
            new("TextLabel", {
                BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20),
                Position = UDim2.fromOffset(0, 6), Font = T.Font, TextSize = 16,
                TextColor3 = T.Text, Text = sTitle or "Section", Parent = Panel,
            })

            -- scrolling body. Left rows start at y=33 (Figma 158-125), right at y=46.
            local Body_ = new("ScrollingFrame", {
                BackgroundTransparency = 1, BorderSizePixel = 0,
                Position = UDim2.fromOffset(0, right and 40 or 28),
                Size = UDim2.new(1, 0, 1, right and -46 or -34),
                CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 2, ScrollBarImageColor3 = T.Scroll,
                ScrollBarImageTransparency = 0, Parent = Panel,
            })
            new("UIListLayout", { Padding = UDim.new(0, right and 17 or 11), SortOrder = Enum.SortOrder.LayoutOrder, Parent = Body_ })
            Section._panel, Section._body = Panel, Body_

            -- TOGGLE — Figma: box 23x23 @x115 (panel-rel 12), label @x150 (rel 47),
            -- keybind glyph @x403 (rel 300), row pitch 34.
            function Section:AddToggle(flag, o)
                o = o or {}
                local Tg = { Value = o.Default or false, Type = "Toggle" }
                local R = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 23), Parent = Body_ })

                local Box = new("Frame", {
                    BackgroundColor3 = T.Element, Size = UDim2.fromOffset(23, 23),
                    Position = UDim2.fromOffset(12, 0), BorderSizePixel = 0, Parent = R,
                })
                corner(Box, 5)
                local Fill = new("Frame", { -- checked = 19x19 #0596ff, inset +2
                    BackgroundColor3 = T.Accent, Size = UDim2.fromOffset(0, 0),
                    Position = UDim2.fromOffset(11, 11), AnchorPoint = Vector2.new(0.5, 0.5),
                    BorderSizePixel = 0, Parent = Box,
                })
                corner(Fill, 4)
                local L = new("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(47, 0),
                    Size = UDim2.new(1, -100, 1, 0), Font = T.Font, TextSize = T.TextSize,
                    TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
                    Text = o.Text or flag, Parent = R,
                })
                -- keybind glyph on the right of every row
                local KB
                if o.Keybind ~= false then
                    KB = new("ImageButton", {
                        BackgroundTransparency = 1, Image = Library:LoadIcon("keybind"),
                        ImageColor3 = T.Icon, Size = UDim2.fromOffset(24, 24),
                        Position = UDim2.fromOffset(300, 0), Parent = R,
                    })
                end

                local Hit = new("TextButton", { BackgroundTransparency = 1, Size = UDim2.new(1, -40, 1, 0),
                    Text = "", AutoButtonColor = false, Parent = R })

                function Tg:SetValue(v, silent)
                    self.Value = v and true or false
                    Library.Flags[flag] = self.Value
                    tween(Fill, { Size = self.Value and UDim2.fromOffset(19, 19) or UDim2.fromOffset(0, 0) }, 0.16, Enum.EasingStyle.Back)
                    if not silent and o.Callback then task.spawn(o.Callback, self.Value) end
                end
                function Tg:GetValue() return self.Value end
                conn(Hit.MouseButton1Click, function() Tg:SetValue(not Tg.Value) end)
                conn(Hit.MouseEnter, function() tween(Box, { BackgroundColor3 = Tg.Value and T.Accent or T.Hover }, 0.12) end)
                conn(Hit.MouseLeave, function() tween(Box, { BackgroundColor3 = T.Element }, 0.12) end)

                -- keybind picker on the glyph
                if KB then
                    local key, binding = o.Key or "None", false
                    conn(KB.MouseButton1Click, function()
                        binding = true
                        tween(KB, { ImageColor3 = T.Accent }, 0.12)
                    end)
                    conn(UserInputService.InputBegan, function(i, gp)
                        if binding and i.UserInputType == Enum.UserInputType.Keyboard then
                            binding = false
                            key = i.KeyCode.Name
                            Library.Flags[flag .. "_Key"] = key
                            tween(KB, { ImageColor3 = T.Icon }, 0.12)
                            return
                        end
                        if gp or binding or key == "None" then return end
                        if i.KeyCode == Enum.KeyCode[key] then Tg:SetValue(not Tg.Value) end
                    end)
                end

                Tg:SetValue(Tg.Value, true)
                Library.Toggles[flag] = Tg
                Library.Options[flag] = Tg
                return Tg
            end

            -- SLIDER — Figma: 301x34 #282828 box, label left + value right,
            -- 2px #4583d9 underline at the bottom whose WIDTH is the value.
            function Section:AddSlider(flag, o)
                o = o or {}
                local min, max = o.Min or 0, o.Max or 100
                local S = { Value = o.Default or min, Type = "Slider" }
                local R = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = Body_ })
                local Box = new("Frame", {
                    BackgroundColor3 = T.Element, Size = UDim2.fromOffset(301, 34),
                    Position = UDim2.fromOffset(20, 0), BorderSizePixel = 0, ClipsDescendants = true, Parent = R,
                })
                corner(Box, 6)
                new("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0),
                    Size = UDim2.new(1, -110, 1, 0), Font = T.FontBold, TextSize = T.TextSize,
                    TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
                    Text = o.Text or flag, Parent = Box,
                })
                local Val = new("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.new(1, -95, 0, 0),
                    Size = UDim2.fromOffset(85, 34), Font = T.Font, TextSize = T.TextSize,
                    TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Right,
                    Text = "0", Parent = Box,
                })
                local Under = new("Frame", { -- the fill IS the underline
                    BackgroundColor3 = T.AccentDim, Size = UDim2.fromOffset(0, 2),
                    Position = UDim2.new(0, 0, 1, -2), BorderSizePixel = 0, Parent = Box,
                })

                local function set(v, silent)
                    v = math.clamp(v, min, max)
                    local m = 10 ^ (o.Rounding or 2)
                    v = math.floor(v * m + 0.5) / m
                    S.Value = v
                    Library.Flags[flag] = v
                    local a = (max - min) == 0 and 0 or (v - min) / (max - min)
                    tween(Under, { Size = UDim2.new(a, 0, 0, 2) }, 0.08)
                    Val.Text = string.format(o.Format or "%.2f", v) .. (o.Suffix or "")
                    if not silent and o.Callback then task.spawn(o.Callback, v) end
                end
                S.SetValue = function(_, v, s) set(v, s) end
                S.GetValue = function() return S.Value end

                local dragging = false
                local function fromX(x)
                    local a = math.clamp((x - Box.AbsolutePosition.X) / math.max(Box.AbsoluteSize.X, 1), 0, 1)
                    set(min + (max - min) * a)
                end
                conn(Box.InputBegan, function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                        dragging = true; fromX(i.Position.X)
                        tween(Under, { BackgroundColor3 = T.Accent }, 0.1)
                    end
                end)
                conn(UserInputService.InputChanged, function(i)
                    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then fromX(i.Position.X) end
                end)
                conn(UserInputService.InputEnded, function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                        if dragging then tween(Under, { BackgroundColor3 = T.AccentDim }, 0.1) end
                        dragging = false
                    end
                end)
                conn(Box.MouseEnter, function() tween(Box, { BackgroundColor3 = T.Hover }, 0.12) end)
                conn(Box.MouseLeave, function() tween(Box, { BackgroundColor3 = T.Element }, 0.12) end)

                set(S.Value, true)
                Library.Options[flag] = S
                return S
            end

            -- DROPDOWN — same 301x34 box, but the underline spans the FULL width.
            function Section:AddDropdown(flag, o)
                o = o or {}
                local values = o.Values or {}
                local D = { Value = o.Default or values[1], Type = "Dropdown", Open = false }
                local R = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = Body_ })
                local Box = new("TextButton", {
                    BackgroundColor3 = T.Element, Size = UDim2.fromOffset(301, 34),
                    Position = UDim2.fromOffset(20, 0), Text = "", AutoButtonColor = false,
                    BorderSizePixel = 0, Parent = R,
                })
                corner(Box, 6)
                new("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0),
                    Size = UDim2.new(1, -130, 1, 0), Font = T.FontBold, TextSize = T.TextSize,
                    TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
                    Text = o.Text or flag, Parent = Box,
                })
                local Sel = new("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.new(1, -125, 0, 0),
                    Size = UDim2.fromOffset(115, 34), Font = T.Font, TextSize = T.TextSize,
                    TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Right,
                    Text = tostring(D.Value or "..."), Parent = Box,
                })
                new("Frame", { -- full-width underline
                    BackgroundColor3 = T.AccentDim, Size = UDim2.new(1, 0, 0, 2),
                    Position = UDim2.new(0, 0, 1, -2), BorderSizePixel = 0, Parent = Box,
                })
                local Menu = new("Frame", {
                    BackgroundColor3 = Color3.fromRGB(24, 24, 24), Size = UDim2.fromOffset(301, 0),
                    Position = UDim2.fromOffset(20, 36), ClipsDescendants = true, Visible = false,
                    BorderSizePixel = 0, ZIndex = 20, Parent = R,
                })
                corner(Menu, 6)
                new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = Menu })

                local function rebuild()
                    for _, c in ipairs(Menu:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
                    for _, v in ipairs(values) do
                        local It = new("TextButton", {
                            BackgroundColor3 = Color3.fromRGB(24, 24, 24), Size = UDim2.new(1, 0, 0, 26),
                            Text = "", AutoButtonColor = false, BorderSizePixel = 0, ZIndex = 21, Parent = Menu,
                        })
                        new("TextLabel", {
                            BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0),
                            Size = UDim2.new(1, -10, 1, 0), Font = T.Font, TextSize = 13,
                            TextColor3 = (v == D.Value) and T.Accent or T.TextDim,
                            TextXAlignment = Enum.TextXAlignment.Left, Text = tostring(v), ZIndex = 21, Parent = It,
                        })
                        conn(It.MouseEnter, function() tween(It, { BackgroundColor3 = T.Element }, 0.1) end)
                        conn(It.MouseLeave, function() tween(It, { BackgroundColor3 = Color3.fromRGB(24, 24, 24) }, 0.1) end)
                        conn(It.MouseButton1Click, function() D:SetValue(v) D:Close() end)
                    end
                end
                function D:SetValue(v, silent)
                    self.Value = v; Library.Flags[flag] = v
                    Sel.Text = tostring(v or "..."); rebuild()
                    if not silent and o.Callback then task.spawn(o.Callback, v) end
                end
                function D:SetValues(v) values = v or {}; rebuild() end
                function D:GetValue() return self.Value end
                function D:Close()
                    self.Open = false
                    R.Size = UDim2.new(1, 0, 0, 36)
                    tween(Menu, { Size = UDim2.fromOffset(301, 0) }, 0.14)
                    task.delay(0.15, function() if not self.Open then Menu.Visible = false end end)
                end
                conn(Box.MouseButton1Click, function()
                    D.Open = not D.Open
                    if D.Open then
                        Menu.Visible = true
                        local h = math.min(#values * 26, 130)
                        tween(Menu, { Size = UDim2.fromOffset(301, h) }, 0.16)
                        R.Size = UDim2.new(1, 0, 0, 36 + h + 4)
                    else D:Close() end
                end)
                conn(Box.MouseEnter, function() tween(Box, { BackgroundColor3 = T.Hover }, 0.12) end)
                conn(Box.MouseLeave, function() tween(Box, { BackgroundColor3 = T.Element }, 0.12) end)
                rebuild(); D:SetValue(D.Value, true)
                Library.Options[flag] = D
                return D
            end

            -- TEXTBOX — Figma: dim label ABOVE, then a 301x25 #282828 box.
            function Section:AddTextbox(flag, o)
                o = o or {}
                local B = { Value = o.Default or "", Type = "Textbox" }
                local R = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), Parent = Body_ })
                new("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(30, 0),
                    Size = UDim2.new(1, -40, 0, 20), Font = T.Font, TextSize = T.TextSize,
                    TextColor3 = T.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
                    Text = o.Text or flag, Parent = R,
                })
                local Box = new("Frame", {
                    BackgroundColor3 = T.Element, Size = UDim2.fromOffset(301, 25),
                    Position = UDim2.fromOffset(20, 22), BorderSizePixel = 0, Parent = R,
                })
                corner(Box, 5)
                local Input = new("TextBox", {
                    BackgroundTransparency = 1, Size = UDim2.new(1, -20, 1, 0),
                    Position = UDim2.fromOffset(10, 0), Font = T.Font, TextSize = T.TextSize,
                    TextColor3 = T.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
                    PlaceholderText = o.Placeholder or "", Text = tostring(B.Value),
                    ClearTextOnFocus = false, Parent = Box,
                })
                local Line = new("Frame", {
                    BackgroundColor3 = T.AccentDim, Size = UDim2.new(0, 0, 0, 2),
                    Position = UDim2.new(0, 0, 1, -2), BorderSizePixel = 0, Parent = Box,
                })
                conn(Input.Focused, function()
                    tween(Line, { Size = UDim2.new(1, 0, 0, 2) }, 0.15)
                    tween(Input, { TextColor3 = T.Text }, 0.15)
                end)
                conn(Input.FocusLost, function()
                    tween(Line, { Size = UDim2.new(0, 0, 0, 2) }, 0.15)
                    tween(Input, { TextColor3 = T.TextDim }, 0.15)
                    B.Value = Input.Text; Library.Flags[flag] = Input.Text
                    if o.Callback then task.spawn(o.Callback, Input.Text) end
                end)
                function B:SetValue(v) Input.Text = tostring(v); self.Value = tostring(v); Library.Flags[flag] = self.Value end
                function B:GetValue() return self.Value end
                Library.Options[flag] = B
                return B
            end

            function Section:AddButton(text, cb)
                local Btn = new("TextButton", {
                    BackgroundColor3 = T.Element, Size = UDim2.fromOffset(301, 30),
                    Position = UDim2.fromOffset(20, 0), Text = "", AutoButtonColor = false,
                    BorderSizePixel = 0, Parent = Body_,
                })
                corner(Btn, 6)
                new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
                    Font = T.Font, TextSize = T.TextSize, TextColor3 = T.Text, Text = text or "Button", Parent = Btn })
                new("Frame", { BackgroundColor3 = T.AccentDim, Size = UDim2.new(1, 0, 0, 2),
                    Position = UDim2.new(0, 0, 1, -2), BorderSizePixel = 0, Parent = Btn })
                conn(Btn.MouseEnter, function() tween(Btn, { BackgroundColor3 = T.Hover }, 0.12) end)
                conn(Btn.MouseLeave, function() tween(Btn, { BackgroundColor3 = T.Element }, 0.12) end)
                conn(Btn.MouseButton1Click, function() if cb then task.spawn(cb) end end)
                return Btn
            end

            function Section:AddLabel(text)
                local L = new("TextLabel", {
                    BackgroundTransparency = 1, Size = UDim2.new(1, -40, 0, 18),
                    Position = UDim2.fromOffset(20, 0), Font = T.Font, TextSize = 13,
                    TextColor3 = T.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
                    TextWrapped = true, Text = text or "", Parent = Body_,
                })
                local o = {} function o:SetText(t) L.Text = t end
                return o
            end

            return Section
        end

        table.insert(Window.Tabs, Tab)
        if #Window.Tabs == 1 then task.defer(function() Tab:Select() end) end
        return Tab
    end

    function Window:SetRoot(r) Window._root = r end
    Library._window = Window
    Library._root = "World"
    return Window
end

-- "World > Local Player" — root white, leaf accent
function Library:SetCrumb(root, leaf)
    if not self._crumb then return end
    local hex = string.format("#%02X%02X%02X",
        math.floor(T.Accent.R * 255), math.floor(T.Accent.G * 255), math.floor(T.Accent.B * 255))
    if leaf then
        self._crumb.Text = string.format('%s > <font color="%s">%s</font>', root or "World", hex, leaf)
    else
        self._crumb.Text = tostring(root)
    end
end

function Library:Unload()
    if self._main then
        tween(self._main, { Size = UDim2.fromOffset(0, 0) }, 0.22)
        task.wait(0.24)
    end
    for _, c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
    self.Connections = {}
    if self._gui then pcall(function() self._gui:Destroy() end) end
end

return Library
