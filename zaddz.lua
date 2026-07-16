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
    ToggleKey = Enum.KeyCode.Insert,
    IconBase = "https://raw.githubusercontent.com/leuleulolo62-droid/zaddz/main/icons/",
    _icons = {},
    _popups = {},
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

function Library:ClosePopups(except)
    for _, p in ipairs(self._popups) do
        if p ~= except and p.frame and p.frame.Visible then p.close() end
    end
end

-- Shared popup panel: same look as a section (#1e1e1e r12), floats in the popup layer,
-- anchored under whatever element opened it. Only one is ever open at a time.
function Library:MakePopup(w, h)
    local frame = new("Frame", {
        BackgroundColor3 = T.Panel, Size = UDim2.fromOffset(w, 0),
        Visible = false, ClipsDescendants = true, BorderSizePixel = 0,
        ZIndex = 51, Parent = self._popupLayer,
    })
    corner(frame, 12)
    new("UIStroke", { Color = Color3.fromRGB(48, 48, 48), Thickness = 1, Parent = frame })
    local body = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, -20, 1, -16),
        Position = UDim2.fromOffset(10, 8), ZIndex = 52, Parent = frame,
    })
    local P = { frame = frame, body = body, h = h, hovering = false }
    conn(frame.MouseEnter, function() P.hovering = true end)
    conn(frame.MouseLeave, function() P.hovering = false end)

    function P.openAt(el)
        Library:ClosePopups(P)
        -- position under the element, clamped inside the window
        local main = Library._main
        local rel = el.AbsolutePosition - main.AbsolutePosition
        local x = math.clamp(rel.X, 8, main.AbsoluteSize.X - w - 8)
        local y = rel.Y + el.AbsoluteSize.Y + 6
        if y + h > main.AbsoluteSize.Y - 8 then y = rel.Y - h - 6 end -- flip above
        frame.Position = UDim2.fromOffset(x, y)
        frame.Visible = true
        frame.Size = UDim2.fromOffset(w, 0)
        tween(frame, { Size = UDim2.fromOffset(w, h) }, 0.16, Enum.EasingStyle.Quad)
    end
    function P.close()
        tween(frame, { Size = UDim2.fromOffset(w, 0) }, 0.12)
        task.delay(0.13, function() frame.Visible = false end)
    end
    table.insert(self._popups, P)
    return P
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

    -- Logo. logo.png is the Figma vector rendered WITH its glow effect already baked in
    -- (406x378 for a 46x39 node -> ~8.8x of pure halo). So: no extra halo layer and no
    -- breathing — stacking another glow on top is what made it flash. Just draw the PNG
    -- once, centred on the vector's centre (12+23, 15+19.5), at its trimmed 283:296 aspect.
    new("ImageLabel", {
        BackgroundTransparency = 1, Image = Library:LoadIcon("logo"),
        ImageColor3 = Color3.fromRGB(255, 255, 255), ScaleType = Enum.ScaleType.Fit,
        -- The 283x296 PNG is glyph + halo. Its solid core measures 181x154 at (50,55),
        -- so 45.5/181 = 0.2514 scale puts the S at Figma's real 45.5x38.6, centred on
        -- (34.8, 34.3). Drawing the whole PNG at 46px shrank the S to nothing.
        Size = UDim2.fromOffset(71, 74), Position = UDim2.fromOffset(0, 1),
        ZIndex = 2, Parent = Sidebar,
    })

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
        BackgroundTransparency = 1, Image = Library:LoadIcon("gear"), ImageColor3 = T.Icon,
        ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromScale(1, 1), Parent = Gear,
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

    -- Popups (colour picker / keybind panel) live in their own top layer so they float
    -- above the panels instead of being clipped by a section's ScrollingFrame.
    local PopupLayer = new("Frame", {
        Name = "Popups", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
        ZIndex = 50, Parent = Main,
    })
    self._popupLayer = PopupLayer

    if opts.ToggleKey then Library.ToggleKey = opts.ToggleKey end
    conn(UserInputService.InputBegan, function(i, gp)
        if gp then return end
        if i.KeyCode == Library.ToggleKey and not Library._rebinding then
            ScreenGui.Enabled = not ScreenGui.Enabled
            Library:ClosePopups()
        end
        -- click outside closes any open popup
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            task.defer(function()
                for _, p in ipairs(Library._popups) do
                    if p.frame and p.frame.Visible and not p.hovering then p.close() end
                end
            end)
        end
    end)

    local Window = { Tabs = {}, _title = title, _current = nil }

    -- Sidebar rail, measured off Figma node 1:3. The icons are NOT evenly spaced and are
    -- NOT the same size, so both come from the table -- a single pitch/size is what made
    -- the eye->pistol gap collapse to 34px and crushed the 42px pistol into a 26px box.
    -- y is the node top; centres land at 115.5/172/225/275.5/319/365.5/418.5.
    local RAIL = {
        { x = 20, y = 101, w = 32, h = 29 }, -- star
        { x = 25, y = 158, w = 28, h = 28 }, -- wifi
        { x = 29, y = 214, w = 22, h = 22 }, -- globe
        { x = 28, y = 264, w = 23, h = 23 }, -- eye
        { x = 18, y = 298, w = 42, h = 42 }, -- pistol
        { x = 24, y = 351, w = 29, h = 29 }, -- car
        { x = 24, y = 405, w = 27, h = 27 }, -- grid
    }
    local function railSlot(idx)
        local s = RAIL[idx]
        if s then return s end
        local last = RAIL[#RAIL] -- extra tabs continue on the design's mean pitch
        return { x = 24, y = last.y + (idx - #RAIL) * 53, w = 27, h = 27 }
    end
    -- Figma's selected-tab glow is a DROP_SHADOW: colour #387BDB, radius 15.3, offset 0.
    -- It is dimmer than the glyph accent and only spreads ~13px -- not a 58px accent bloom.
    local GLOW_COLOR, GLOW_PAD = Color3.fromRGB(56, 123, 219), 26

    function Window:AddTab(name, icon, tabOpts)
        tabOpts = tabOpts or {}
        local idx = #Window.Tabs + 1
        local Tab = { Name = name, _window = Window }

        local slot = railSlot(idx)
        local cx, cy = slot.x + slot.w / 2, slot.y + slot.h / 2
        local Btn = new("TextButton", { -- invisible hit area, centred on the glyph
            BackgroundTransparency = 1, Size = UDim2.fromOffset(46, 46),
            Position = UDim2.fromOffset(math.floor(cx - 23), math.floor(cy - 23)),
            Text = "", AutoButtonColor = false, Parent = Sidebar,
        })
        local gw, gh = slot.w + GLOW_PAD, slot.h + GLOW_PAD
        -- Real radial bloom (glow.png), NOT a scaled copy of the icon -- a tinted enlarged
        -- glyph just reads as a big blurry duplicate, which is what the last build did.
        local Glow = new("ImageLabel", {
            BackgroundTransparency = 1, Image = Library:LoadIcon("glow"),
            ImageColor3 = GLOW_COLOR, ImageTransparency = 1,
            Size = UDim2.fromOffset(gw, gh), Position = UDim2.new(0.5, -gw / 2, 0.5, -gh / 2),
            ScaleType = Enum.ScaleType.Fit, ZIndex = 1, Parent = Btn,
        })
        -- Each glyph gets its own Figma node size; Fit keeps the real aspect, so the
        -- 140x86 pistol letterboxes to 42x26 instead of being squashed into a square.
        local Ico = new("ImageLabel", {
            BackgroundTransparency = 1, Image = icon and Library:LoadIcon(icon) or "",
            ImageColor3 = T.Icon, ScaleType = Enum.ScaleType.Fit,
            Size = UDim2.fromOffset(slot.w, slot.h),
            Position = UDim2.new(0.5, -slot.w / 2, 0.5, -slot.h / 2),
            ZIndex = 2, Parent = Btn,
        })
        if not icon then
            Ico.Image = ""
            new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
                Font = T.FontBold, TextSize = 12, TextColor3 = T.Icon, Text = name:sub(1, 2):upper(), ZIndex = 2, Parent = Btn })
        end

        local Page = new("Frame", {
            Name = name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
            Visible = false, Parent = Container,
        })
        Tab._page, Tab._btn, Tab._ico, Tab._glow = Page, Btn, Ico, Glow

        function Tab:Select()
            for _, t in ipairs(Window.Tabs) do
                t._page.Visible = false
                tween(t._ico, { ImageColor3 = T.Icon }, 0.16)
                tween(t._glow, { ImageTransparency = 1 }, 0.16)
            end
            Page.Visible = true
            -- Figma only recolours the selected glyph -- it never scales it, and the halo
            -- sits at a fixed radius. Growing/blooming both was the "not like the original".
            tween(Ico, { ImageColor3 = T.Accent }, 0.18)
            tween(Glow, { ImageTransparency = 0.55 }, 0.28)
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
                        ImageColor3 = T.Icon, ScaleType = Enum.ScaleType.Fit,
                        Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(300, 0), Parent = R,
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

                -- Keybind PANEL: clicking the glyph spawns a popup (key + mode + clear)
                -- rather than silently entering a listen state.
                if KB then
                    local key, mode, binding = o.Key or "None", o.Mode or "Toggle", false
                    Tg.Key, Tg.Mode = key, mode

                    local P = Library:MakePopup(178, 96)
                    new("TextLabel", {
                        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), Font = T.FontBold,
                        TextSize = 13, TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
                        Text = "Keybind", ZIndex = 53, Parent = P.body,
                    })
                    local KeyBtn = new("TextButton", {
                        BackgroundColor3 = T.Element, Size = UDim2.new(1, 0, 0, 26),
                        Position = UDim2.fromOffset(0, 20), Text = "", AutoButtonColor = false,
                        BorderSizePixel = 0, ZIndex = 53, Parent = P.body,
                    })
                    corner(KeyBtn, 5)
                    local KeyTxt = new("TextLabel", {
                        BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = T.Font,
                        TextSize = 13, TextColor3 = T.Text, Text = key, ZIndex = 54, Parent = KeyBtn,
                    })
                    new("Frame", { BackgroundColor3 = T.AccentDim, Size = UDim2.new(1, 0, 0, 2),
                        Position = UDim2.new(0, 0, 1, -2), BorderSizePixel = 0, ZIndex = 54, Parent = KeyBtn })

                    -- mode cycles Toggle -> Hold -> Always
                    local ModeBtn = new("TextButton", {
                        BackgroundColor3 = T.Element, Size = UDim2.new(1, -60, 0, 24),
                        Position = UDim2.fromOffset(0, 52), Text = "", AutoButtonColor = false,
                        BorderSizePixel = 0, ZIndex = 53, Parent = P.body,
                    })
                    corner(ModeBtn, 5)
                    local ModeTxt = new("TextLabel", {
                        BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = T.Font,
                        TextSize = 12, TextColor3 = T.TextDim, Text = mode, ZIndex = 54, Parent = ModeBtn,
                    })
                    local Clear = new("TextButton", {
                        BackgroundColor3 = T.Element, Size = UDim2.fromOffset(54, 24),
                        Position = UDim2.new(1, -54, 0, 52), Text = "", AutoButtonColor = false,
                        BorderSizePixel = 0, ZIndex = 53, Parent = P.body,
                    })
                    corner(Clear, 5)
                    new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
                        Font = T.Font, TextSize = 12, TextColor3 = T.TextDim, Text = "Clear", ZIndex = 54, Parent = Clear })

                    local function setKey(k)
                        key = k; Tg.Key = k
                        KeyTxt.Text = k
                        Library.Flags[flag .. "_Key"] = k
                        tween(KB, { ImageColor3 = (k ~= "None") and T.Accent or T.Icon }, 0.12)
                    end
                    local MODES = { "Toggle", "Hold", "Always" }
                    conn(ModeBtn.MouseButton1Click, function()
                        local i = table.find(MODES, mode) or 1
                        mode = MODES[(i % #MODES) + 1]
                        Tg.Mode = mode
                        ModeTxt.Text = mode
                        Library.Flags[flag .. "_Mode"] = mode
                    end)
                    conn(Clear.MouseButton1Click, function() setKey("None") end)
                    conn(KeyBtn.MouseButton1Click, function()
                        binding = true
                        Library._rebinding = true
                        KeyTxt.Text = "press a key..."
                        KeyTxt.TextColor3 = T.Accent
                    end)
                    conn(KB.MouseButton1Click, function()
                        if P.frame.Visible then P.close() else P.openAt(KB) end
                    end)
                    for _, b in ipairs({ KeyBtn, ModeBtn, Clear }) do
                        conn(b.MouseEnter, function() tween(b, { BackgroundColor3 = T.Hover }, 0.1) end)
                        conn(b.MouseLeave, function() tween(b, { BackgroundColor3 = T.Element }, 0.1) end)
                    end

                    conn(UserInputService.InputBegan, function(i, gp)
                        if binding and i.UserInputType == Enum.UserInputType.Keyboard then
                            binding = false
                            Library._rebinding = false
                            KeyTxt.TextColor3 = T.Text
                            setKey(i.KeyCode == Enum.KeyCode.Backspace and "None" or i.KeyCode.Name)
                            return
                        end
                        if gp or binding or key == "None" then return end
                        if i.KeyCode == Enum.KeyCode[key] then
                            if mode == "Toggle" then Tg:SetValue(not Tg.Value)
                            elseif mode == "Hold" then Tg:SetValue(true) end
                        end
                    end)
                    conn(UserInputService.InputEnded, function(i)
                        if mode == "Hold" and key ~= "None" and i.KeyCode == Enum.KeyCode[key] then
                            Tg:SetValue(false)
                        end
                    end)
                    if key ~= "None" then setKey(key) end
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

            -- COLOR PICKER — swatch on the row, click it for an HSV panel.
            -- The SV square is built from two UIGradients over a hue-coloured frame
            -- (white->clear horizontally, clear->black vertically), so no image assets.
            function Section:AddColorPicker(flag, o)
                o = o or {}
                local CP = { Value = o.Default or T.Accent, Type = "ColorPicker", Alpha = o.Alpha or 0 }
                local h, s, v = CP.Value:ToHSV()

                local R = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 23), Parent = Body_ })
                new("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 0),
                    Size = UDim2.new(1, -60, 1, 0), Font = T.Font, TextSize = T.TextSize,
                    TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
                    Text = o.Text or flag, Parent = R,
                })
                local Swatch = new("TextButton", {
                    BackgroundColor3 = CP.Value, Size = UDim2.fromOffset(34, 20),
                    Position = UDim2.fromOffset(288, 1), Text = "", AutoButtonColor = false,
                    BorderSizePixel = 0, Parent = R,
                })
                corner(Swatch, 5)
                new("UIStroke", { Color = Color3.fromRGB(60, 60, 60), Thickness = 1, Parent = Swatch })

                local P = Library:MakePopup(200, o.Alpha and 210 or 190)

                -- SV square
                local SV = new("Frame", {
                    BackgroundColor3 = Color3.fromHSV(h, 1, 1), Size = UDim2.fromOffset(180, 110),
                    BorderSizePixel = 0, ZIndex = 53, Parent = P.body,
                })
                corner(SV, 6)
                local White = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ZIndex = 54, Parent = SV })
                corner(White, 6)
                new("UIGradient", {
                    Color = ColorSequence.new(Color3.new(1, 1, 1)),
                    Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
                    Parent = White,
                })
                local Black = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ZIndex = 55, Parent = SV })
                corner(Black, 6)
                new("UIGradient", {
                    Rotation = 90,
                    Color = ColorSequence.new(Color3.new(0, 0, 0)),
                    Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
                    Parent = Black,
                })
                local Cursor = new("Frame", {
                    BackgroundTransparency = 1, Size = UDim2.fromOffset(10, 10),
                    AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 56, Parent = SV,
                })
                corner(Cursor, 5)
                new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Parent = Cursor })

                -- hue bar
                local Hue = new("Frame", {
                    BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(180, 12),
                    Position = UDim2.fromOffset(0, 118), BorderSizePixel = 0, ZIndex = 53, Parent = P.body,
                })
                corner(Hue, 6)
                new("UIGradient", {
                    Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
                        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
                        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
                        ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
                        ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
                        ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
                        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
                    }), Parent = Hue,
                })
                local HueKnob = new("Frame", {
                    BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(3, 16),
                    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
                    BorderSizePixel = 0, ZIndex = 54, Parent = Hue,
                })
                corner(HueKnob, 2)

                -- alpha bar (optional)
                local AlphaBar, AlphaKnob
                if o.Alpha then
                    AlphaBar = new("Frame", {
                        BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(180, 12),
                        Position = UDim2.fromOffset(0, 136), BorderSizePixel = 0, ZIndex = 53, Parent = P.body,
                    })
                    corner(AlphaBar, 6)
                    new("UIGradient", {
                        Color = ColorSequence.new(CP.Value),
                        Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
                        Parent = AlphaBar,
                    })
                    AlphaKnob = new("Frame", {
                        BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(3, 16),
                        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
                        BorderSizePixel = 0, ZIndex = 54, Parent = AlphaBar,
                    })
                    corner(AlphaKnob, 2)
                end

                -- hex box
                local HexY = o.Alpha and 156 or 138
                local HexBox = new("Frame", {
                    BackgroundColor3 = T.Element, Size = UDim2.fromOffset(180, 24),
                    Position = UDim2.fromOffset(0, HexY), BorderSizePixel = 0, ZIndex = 53, Parent = P.body,
                })
                corner(HexBox, 5)
                local Hex = new("TextBox", {
                    BackgroundTransparency = 1, Size = UDim2.new(1, -12, 1, 0),
                    Position = UDim2.fromOffset(6, 0), Font = T.Font, TextSize = 12,
                    TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
                    Text = "#FFFFFF", ClearTextOnFocus = false, ZIndex = 54, Parent = HexBox,
                })
                new("Frame", { BackgroundColor3 = T.AccentDim, Size = UDim2.new(1, 0, 0, 2),
                    Position = UDim2.new(0, 0, 1, -2), BorderSizePixel = 0, ZIndex = 54, Parent = HexBox })

                local function refresh(silent)
                    local col = Color3.fromHSV(h, s, v)
                    CP.Value = col
                    Library.Flags[flag] = col
                    Swatch.BackgroundColor3 = col
                    SV.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
                    Cursor.Position = UDim2.new(s, 0, 1 - v, 0)
                    HueKnob.Position = UDim2.new(h, 0, 0.5, 0)
                    Hex.Text = string.format("#%02X%02X%02X",
                        math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5))
                    if AlphaBar then
                        AlphaBar.UIGradient.Color = ColorSequence.new(col)
                        AlphaKnob.Position = UDim2.new(1 - CP.Alpha, 0, 0.5, 0)
                    end
                    if not silent and o.Callback then task.spawn(o.Callback, col, CP.Alpha) end
                end

                -- drag handling for SV / hue / alpha
                local drag = nil
                local function pick(input)
                    if drag == "sv" then
                        s = math.clamp((input.Position.X - SV.AbsolutePosition.X) / SV.AbsoluteSize.X, 0, 1)
                        v = 1 - math.clamp((input.Position.Y - SV.AbsolutePosition.Y) / SV.AbsoluteSize.Y, 0, 1)
                        refresh()
                    elseif drag == "hue" then
                        h = math.clamp((input.Position.X - Hue.AbsolutePosition.X) / Hue.AbsoluteSize.X, 0, 1)
                        refresh()
                    elseif drag == "alpha" and AlphaBar then
                        CP.Alpha = 1 - math.clamp((input.Position.X - AlphaBar.AbsolutePosition.X) / AlphaBar.AbsoluteSize.X, 0, 1)
                        refresh()
                    end
                end
                conn(SV.InputBegan, function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = "sv" pick(i) end
                end)
                conn(Hue.InputBegan, function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = "hue" pick(i) end
                end)
                if AlphaBar then
                    conn(AlphaBar.InputBegan, function(i)
                        if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = "alpha" pick(i) end
                    end)
                end
                conn(UserInputService.InputChanged, function(i)
                    if drag and i.UserInputType == Enum.UserInputType.MouseMovement then pick(i) end
                end)
                conn(UserInputService.InputEnded, function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = nil end
                end)
                conn(Hex.FocusLost, function()
                    local hx = Hex.Text:gsub("#", "")
                    if #hx == 6 and tonumber(hx, 16) then
                        local n = tonumber(hx, 16)
                        local col = Color3.fromRGB(bit32.band(bit32.rshift(n, 16), 255), bit32.band(bit32.rshift(n, 8), 255), bit32.band(n, 255))
                        h, s, v = col:ToHSV()
                    end
                    refresh()
                end)
                conn(Swatch.MouseButton1Click, function()
                    if P.frame.Visible then P.close() else P.openAt(Swatch) end
                end)

                function CP:SetValue(col, silent)
                    h, s, v = col:ToHSV()
                    refresh(silent)
                end
                function CP:GetValue() return self.Value end
                refresh(true)
                Library.Options[flag] = CP
                return CP
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
        -- Default = which tab opens selected. Without this the FIRST tab always lit up,
        -- so the star glowed blue instead of the globe like the design.
        if tabOpts.Default then Window._default = Tab end
        if #Window.Tabs == 1 then
            task.defer(function() (Window._default or Tab):Select() end)
        elseif tabOpts.Default then
            task.defer(function() Tab:Select() end)
        end
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
