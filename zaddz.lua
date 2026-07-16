--[[
    zaddz — Roblox UI library
    Styled 1:1 from the "susano FiveM Cheat" Figma (apFxClc2AyZM8QXSZwQoZF).

    Design tokens pulled straight from the file:
      window   848x597  #131313  radius 7
      sidebar  72w      #101010
      panel    342w     #1e1e1e  radius 12
      element  23x23    #282828   (checked inner 19x19 #0596ff)
      accent            #0596ff
      text     Inter 400 14px #ffffff  -> Gotham 14

    Usage:
      local Library = loadstring(readfile("zaddz.lua"))()
      local Window  = Library:CreateWindow({ Title = "SUSANO.RE" })
      local Tab     = Window:AddTab("World", "rbxassetid://...")
      local Sec     = Tab:AddSection("Local Player", "Left")
      Sec:AddToggle("GodMode", { Text = "God Mode", Default = false, Callback = function(v) end })
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local Library = {
    Flags = {},
    Options = {},
    Toggles = {},
    Connections = {},
    Theme = {
        Background = Color3.fromRGB(19, 19, 19),   -- #131313
        Sidebar    = Color3.fromRGB(16, 16, 16),   -- #101010
        Panel      = Color3.fromRGB(30, 30, 30),   -- #1e1e1e
        Element    = Color3.fromRGB(40, 40, 40),   -- #282828
        ElementHover = Color3.fromRGB(52, 52, 52),
        Accent     = Color3.fromRGB(5, 150, 255),  -- #0596ff
        Text       = Color3.fromRGB(255, 255, 255),
        TextDim    = Color3.fromRGB(138, 138, 138),
        Stroke     = Color3.fromRGB(44, 44, 44),
        Font       = Enum.Font.Gotham,
        FontBold   = Enum.Font.GothamBold,
        TextSize   = 14,
    },
    ToggleKey = Enum.KeyCode.RightShift,
    Unloaded = false,
}

local T = Library.Theme
local TW = function(t) return TweenInfo.new(t or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) end

-- ---------------------------------------------------------------- helpers

local function new(class, props, children)
    local i = Instance.new(class)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then i[k] = v end
    end
    for _, c in ipairs(children or {}) do c.Parent = i end
    if props and props.Parent then i.Parent = props.Parent end
    return i
end

local function corner(parent, r)
    return new("UICorner", { CornerRadius = UDim.new(0, r or 6), Parent = parent })
end

local function stroke(parent, col, th)
    return new("UIStroke", {
        Color = col or T.Stroke, Thickness = th or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent,
    })
end

local function pad(parent, l, r, t, b)
    return new("UIPadding", {
        PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0),
        PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0),
        Parent = parent,
    })
end

local function tween(obj, props, t)
    local tw = TweenService:Create(obj, TW(t), props)
    tw:Play()
    return tw
end

local function conn(signal, fn)
    local c = signal:Connect(fn)
    table.insert(Library.Connections, c)
    return c
end

-- Hover tint on any frame-ish element.
local function hoverify(button, target, base, hover)
    conn(button.MouseEnter, function() tween(target, { BackgroundColor3 = hover }, 0.12) end)
    conn(button.MouseLeave, function() tween(target, { BackgroundColor3 = base }, 0.12) end)
end

local function ripple(parent)
    -- Subtle click feedback: a white flash that fades. Cheap stand-in for a real ripple.
    local f = new("Frame", {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.85,
        Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ZIndex = 20, Parent = parent,
    })
    corner(f, 6)
    tween(f, { BackgroundTransparency = 1 }, 0.25)
    task.delay(0.28, function() f:Destroy() end)
end

function Library:Notify(text, duration)
    duration = duration or 3
    local gui = self._notifyHolder
    if not gui then return end
    local item = new("Frame", {
        BackgroundColor3 = T.Panel, Size = UDim2.new(1, 0, 0, 34),
        BorderSizePixel = 0, BackgroundTransparency = 1, Parent = gui,
    })
    corner(item, 8)
    stroke(item, T.Stroke)
    local bar = new("Frame", {
        BackgroundColor3 = T.Accent, Size = UDim2.new(0, 3, 1, -12),
        Position = UDim2.fromOffset(6, 6), BorderSizePixel = 0, Parent = item,
    })
    corner(bar, 2)
    local lbl = new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, -20, 1, 0),
        Position = UDim2.fromOffset(16, 0), Font = T.Font, TextSize = 13,
        TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
        Text = tostring(text), TextTransparency = 1, Parent = item,
    })
    tween(item, { BackgroundTransparency = 0 }, 0.2)
    tween(lbl, { TextTransparency = 0 }, 0.2)
    task.delay(duration, function()
        tween(item, { BackgroundTransparency = 1 }, 0.2)
        tween(lbl, { TextTransparency = 1 }, 0.2)
        task.delay(0.25, function() item:Destroy() end)
    end)
end

-- ---------------------------------------------------------------- window

function Library:CreateWindow(opts)
    opts = opts or {}
    local title = opts.Title or "SUSANO.RE"
    local size = opts.Size or UDim2.fromOffset(851, 597)

    -- gethui keeps the UI out of PlayerGui (where anticheats scan); CoreGui is the fallback.
    local parent = opts.Parent
    if not parent then
        local ok, hui = pcall(function() return gethui and gethui() end)
        parent = (ok and hui) or game:GetService("CoreGui")
    end

    local ScreenGui = new("ScreenGui", {
        Name = opts.Name or "zaddz", ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 9999, Parent = parent,
    })
    self._gui = ScreenGui

    -- notification stack (top-right)
    self._notifyHolder = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.fromOffset(260, 400),
        Position = UDim2.new(1, -270, 0, 10), Parent = ScreenGui,
    })
    new("UIListLayout", {
        Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Top, Parent = self._notifyHolder,
    })

    -- root (Figma: 848x597 #131313 r7)
    local Main = new("Frame", {
        Name = "Main", BackgroundColor3 = T.Background,
        Size = UDim2.fromOffset(0, 0), -- animated in
        Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5),
        BorderSizePixel = 0, ClipsDescendants = true, Parent = ScreenGui,
    })
    corner(Main, 7)
    stroke(Main, Color3.fromRGB(38, 38, 38))
    self._main = Main

    -- open animation
    tween(Main, { Size = size }, 0.28)

    -- sidebar (Figma: 72w #101010)
    local Sidebar = new("Frame", {
        Name = "Sidebar", BackgroundColor3 = T.Sidebar,
        Size = UDim2.new(0, 72, 1, 0), BorderSizePixel = 0, Parent = Main,
    })
    -- square off the right edge so only the window's outer corners are round
    new("Frame", {
        BackgroundColor3 = T.Sidebar, Size = UDim2.new(0, 10, 1, 0),
        Position = UDim2.new(1, -10, 0, 0), BorderSizePixel = 0, Parent = Sidebar,
    })
    corner(Sidebar, 7)

    -- logo
    local Logo = new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.fromOffset(0, 18), Font = T.FontBold, TextSize = 15,
        TextColor3 = T.Accent, Text = "S", Parent = Sidebar,
    })
    if opts.LogoImage then
        Logo.Text = ""
        new("ImageLabel", {
            BackgroundTransparency = 1, Image = opts.LogoImage,
            Size = UDim2.fromOffset(30, 30), Position = UDim2.new(0.5, -15, 0, 5),
            Parent = Logo,
        })
    end

    -- tab icon rail
    local TabRail = new("Frame", {
        Name = "TabRail", BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, -110), Position = UDim2.fromOffset(0, 70), Parent = Sidebar,
    })
    new("UIListLayout", {
        Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = TabRail,
    })

    -- breadcrumb header (Figma: "World > Local Player" @ 104,30, Inter 14)
    local Crumb = new("TextLabel", {
        Name = "Breadcrumb", BackgroundTransparency = 1,
        Position = UDim2.fromOffset(104, 24), Size = UDim2.fromOffset(400, 24),
        Font = T.Font, TextSize = T.TextSize, TextColor3 = T.Text,
        TextXAlignment = Enum.TextXAlignment.Left, Text = title, Parent = Main,
    })
    self._crumb = Crumb

    local TitleLbl = new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(1, -220, 0, 24),
        Size = UDim2.fromOffset(200, 24), Font = T.FontBold, TextSize = 14,
        TextColor3 = T.TextDim, TextXAlignment = Enum.TextXAlignment.Right,
        Text = title, Parent = Main,
    })

    -- close
    local Close = new("TextButton", {
        BackgroundColor3 = T.Element, Size = UDim2.fromOffset(22, 22),
        Position = UDim2.new(1, -32, 0, 24), Text = "", AutoButtonColor = false,
        BorderSizePixel = 0, Parent = Main,
    })
    corner(Close, 6)
    new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = T.FontBold,
        TextSize = 12, TextColor3 = T.TextDim, Text = "X", Parent = Close,
    })
    hoverify(Close, Close, T.Element, Color3.fromRGB(200, 45, 45))
    conn(Close.MouseButton1Click, function() Library:Unload() end)

    -- tab pages live here (Figma panels start at x=103, y=123)
    local Container = new("Frame", {
        Name = "Container", BackgroundTransparency = 1,
        Position = UDim2.fromOffset(103, 123), Size = UDim2.new(1, -103 - 50, 1, -123 - 20),
        Parent = Main,
    })

    -- dragging (header strip)
    do
        local dragging, dragStart, startPos
        local DragBar = new("TextButton", {
            BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
            Size = UDim2.new(1, -72, 0, 70), Position = UDim2.fromOffset(72, 0),
            Parent = Main,
        })
        conn(DragBar.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true; dragStart = input.Position; startPos = Main.Position
            end
        end)
        conn(UserInputService.InputChanged, function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local d = input.Position - dragStart
                Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
        conn(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
    end

    -- toggle visibility
    conn(UserInputService.InputBegan, function(input, gp)
        if gp then return end
        if input.KeyCode == Library.ToggleKey then
            ScreenGui.Enabled = not ScreenGui.Enabled
        end
    end)

    local Window = { Tabs = {}, _container = Container, _rail = TabRail, _current = nil, _title = title }

    function Window:AddTab(name, icon)
        local Tab = { Name = name, Sections = { Left = nil, Right = nil }, _window = Window }

        -- sidebar icon button
        local Btn = new("TextButton", {
            BackgroundColor3 = T.Sidebar, Size = UDim2.fromOffset(42, 42),
            Text = "", AutoButtonColor = false, BorderSizePixel = 0, Parent = TabRail,
        })
        corner(Btn, 10)
        local Ind = new("Frame", { -- accent selection pill
            BackgroundColor3 = T.Accent, Size = UDim2.fromOffset(3, 0),
            Position = UDim2.fromOffset(-9, 0), AnchorPoint = Vector2.new(0, 0.5),
            BorderSizePixel = 0, Parent = Btn,
        })
        Ind.Position = UDim2.new(0, -9, 0.5, 0)
        corner(Ind, 2)

        local Ico
        if icon then
            Ico = new("ImageLabel", {
                BackgroundTransparency = 1, Image = icon, ImageColor3 = T.TextDim,
                Size = UDim2.fromOffset(20, 20), Position = UDim2.new(0.5, -10, 0.5, -10),
                Parent = Btn,
            })
        else
            Ico = new("TextLabel", {
                BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = T.FontBold,
                TextSize = 13, TextColor3 = T.TextDim, Text = name:sub(1, 2):upper(), Parent = Btn,
            })
        end

        -- page
        local Page = new("Frame", {
            Name = name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
            Visible = false, Parent = Container,
        })
        Tab._page = Page

        -- two panel columns (Figma: left 342 @x103, right 342 @x456 -> gap 11)
        local Left = new("ScrollingFrame", {
            BackgroundTransparency = 1, Size = UDim2.new(0, 342, 1, 0),
            Position = UDim2.fromOffset(0, 0), ScrollBarThickness = 2,
            ScrollBarImageColor3 = T.Element, CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, Parent = Page,
        })
        new("UIListLayout", { Padding = UDim.new(0, 11), SortOrder = Enum.SortOrder.LayoutOrder, Parent = Left })
        local Right = new("ScrollingFrame", {
            BackgroundTransparency = 1, Size = UDim2.new(0, 342, 1, 0),
            Position = UDim2.fromOffset(353, 0), ScrollBarThickness = 2,
            ScrollBarImageColor3 = T.Element, CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, Parent = Page,
        })
        new("UIListLayout", { Padding = UDim.new(0, 11), SortOrder = Enum.SortOrder.LayoutOrder, Parent = Right })
        Tab._left, Tab._right = Left, Right

        function Tab:Select()
            for _, t in ipairs(Window.Tabs) do
                t._page.Visible = false
                tween(t._ind, { Size = UDim2.fromOffset(3, 0) }, 0.15)
                tween(t._btn, { BackgroundColor3 = T.Sidebar }, 0.15)
                if t._ico:IsA("ImageLabel") then tween(t._ico, { ImageColor3 = T.TextDim }, 0.15)
                else tween(t._ico, { TextColor3 = T.TextDim }, 0.15) end
            end
            Page.Visible = true
            tween(Ind, { Size = UDim2.fromOffset(3, 22) }, 0.18)
            tween(Btn, { BackgroundColor3 = T.Panel }, 0.18)
            if Ico:IsA("ImageLabel") then tween(Ico, { ImageColor3 = T.Accent }, 0.18)
            else tween(Ico, { TextColor3 = T.Accent }, 0.18) end
            Window._current = Tab
            Library._crumb.Text = name
            -- fade the page in
            Page.Position = UDim2.fromOffset(0, 6)
            tween(Page, { Position = UDim2.fromOffset(0, 0) }, 0.2)
        end

        Tab._btn, Tab._ind, Tab._ico = Btn, Ind, Ico
        conn(Btn.MouseButton1Click, function() Tab:Select() end)
        conn(Btn.MouseEnter, function()
            if Window._current ~= Tab then tween(Btn, { BackgroundColor3 = Color3.fromRGB(26, 26, 26) }, 0.12) end
        end)
        conn(Btn.MouseLeave, function()
            if Window._current ~= Tab then tween(Btn, { BackgroundColor3 = T.Sidebar }, 0.12) end
        end)

        function Tab:AddSection(sTitle, side)
            local holder = (side == "Right") and Right or Left
            local Section = { _tab = Tab }

            -- panel (Figma: #1e1e1e r12)
            local Panel = new("Frame", {
                BackgroundColor3 = T.Panel, Size = UDim2.new(1, -4, 0, 40),
                AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, Parent = holder,
            })
            corner(Panel, 12)
            stroke(Panel, Color3.fromRGB(36, 36, 36))
            pad(Panel, 12, 12, 12, 12)
            local List = new("UIListLayout", {
                Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = Panel,
            })

            new("TextLabel", {
                BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18),
                Font = T.FontBold, TextSize = 13, TextColor3 = T.Text,
                TextXAlignment = Enum.TextXAlignment.Left, Text = sTitle or "Section",
                LayoutOrder = -1, Parent = Panel,
            })

            Section._panel = Panel

            -- a standard 26px row with a label on the left
            local function row(text, h)
                local R = new("Frame", {
                    BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h or 26), Parent = Panel,
                })
                local L = new("TextLabel", {
                    BackgroundTransparency = 1, Size = UDim2.new(1, -40, 1, 0),
                    Position = UDim2.fromOffset(32, 0), Font = T.Font, TextSize = T.TextSize,
                    TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
                    Text = text or "", Parent = R,
                })
                return R, L
            end

            -- TOGGLE (Figma: 23x23 #282828 box, checked inner 19x19 #0596ff)
            function Section:AddToggle(flag, o)
                o = o or {}
                local Toggle = { Value = o.Default or false, Type = "Toggle" }
                local R, L = row(o.Text or flag)

                local Box = new("TextButton", {
                    BackgroundColor3 = T.Element, Size = UDim2.fromOffset(23, 23),
                    Position = UDim2.new(0, 0, 0.5, -11), Text = "", AutoButtonColor = false,
                    BorderSizePixel = 0, Parent = R,
                })
                corner(Box, 6)
                local Fill = new("Frame", {
                    BackgroundColor3 = T.Accent, Size = UDim2.fromOffset(0, 0),
                    Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5),
                    BorderSizePixel = 0, Parent = Box,
                })
                corner(Fill, 4)
                local Check = new("TextLabel", {
                    BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = T.FontBold,
                    TextSize = 12, TextColor3 = Color3.fromRGB(255, 255, 255),
                    Text = "", TextTransparency = 1, Parent = Box,
                })

                local Hit = new("TextButton", {
                    BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "",
                    AutoButtonColor = false, Parent = R,
                })

                function Toggle:SetValue(v, silent)
                    self.Value = v and true or false
                    Library.Flags[flag] = self.Value
                    -- animate the 19x19 accent fill in/out
                    tween(Fill, { Size = self.Value and UDim2.fromOffset(19, 19) or UDim2.fromOffset(0, 0) }, 0.16)
                    tween(Check, { TextTransparency = self.Value and 0 or 1 }, 0.16)
                    tween(L, { TextColor3 = self.Value and T.Text or T.TextDim }, 0.16)
                    if not silent and o.Callback then task.spawn(o.Callback, self.Value) end
                end
                function Toggle:GetValue() return self.Value end

                conn(Hit.MouseButton1Click, function()
                    Toggle:SetValue(not Toggle.Value)
                    ripple(Box)
                end)
                hoverify(Hit, Box, T.Element, T.ElementHover)

                Toggle:SetValue(Toggle.Value, true)
                L.TextColor3 = Toggle.Value and T.Text or T.TextDim
                Library.Toggles[flag] = Toggle
                Library.Options[flag] = Toggle
                return Toggle
            end

            -- SLIDER
            function Section:AddSlider(flag, o)
                o = o or {}
                local min, max = o.Min or 0, o.Max or 100
                local Slider = { Value = o.Default or min, Type = "Slider" }
                local R = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), Parent = Panel })
                local L = new("TextLabel", {
                    BackgroundTransparency = 1, Size = UDim2.new(1, -60, 0, 16),
                    Font = T.Font, TextSize = T.TextSize, TextColor3 = T.Text,
                    TextXAlignment = Enum.TextXAlignment.Left, Text = o.Text or flag, Parent = R,
                })
                local Val = new("TextLabel", {
                    BackgroundTransparency = 1, Size = UDim2.new(0, 56, 0, 16),
                    Position = UDim2.new(1, -56, 0, 0), Font = T.Font, TextSize = 13,
                    TextColor3 = T.Accent, TextXAlignment = Enum.TextXAlignment.Right,
                    Text = "0", Parent = R,
                })
                local Bar = new("Frame", {
                    BackgroundColor3 = T.Element, Size = UDim2.new(1, 0, 0, 6),
                    Position = UDim2.fromOffset(0, 24), BorderSizePixel = 0, Parent = R,
                })
                corner(Bar, 3)
                local Fill = new("Frame", {
                    BackgroundColor3 = T.Accent, Size = UDim2.fromScale(0, 1),
                    BorderSizePixel = 0, Parent = Bar,
                })
                corner(Fill, 3)
                local Knob = new("Frame", {
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255), Size = UDim2.fromOffset(10, 10),
                    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
                    BorderSizePixel = 0, ZIndex = 3, Parent = Bar,
                })
                corner(Knob, 5)

                local function set(v, silent)
                    v = math.clamp(v, min, max)
                    if o.Rounding == 0 or o.Rounding == nil then v = math.floor(v + 0.5)
                    else local m = 10 ^ o.Rounding; v = math.floor(v * m + 0.5) / m end
                    Slider.Value = v
                    Library.Flags[flag] = v
                    local a = (max - min) == 0 and 0 or (v - min) / (max - min)
                    tween(Fill, { Size = UDim2.fromScale(a, 1) }, 0.08)
                    tween(Knob, { Position = UDim2.new(a, 0, 0.5, 0) }, 0.08)
                    Val.Text = tostring(v) .. (o.Suffix or "")
                    if not silent and o.Callback then task.spawn(o.Callback, v) end
                end
                Slider.SetValue = function(_, v, s) set(v, s) end
                Slider.GetValue = function() return Slider.Value end

                local dragging = false
                local function fromX(x)
                    local a = math.clamp((x - Bar.AbsolutePosition.X) / math.max(Bar.AbsoluteSize.X, 1), 0, 1)
                    set(min + (max - min) * a)
                end
                conn(Bar.InputBegan, function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                        dragging = true; fromX(i.Position.X)
                        tween(Knob, { Size = UDim2.fromOffset(14, 14) }, 0.1)
                    end
                end)
                conn(UserInputService.InputChanged, function(i)
                    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                        fromX(i.Position.X)
                    end
                end)
                conn(UserInputService.InputEnded, function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                        if dragging then tween(Knob, { Size = UDim2.fromOffset(10, 10) }, 0.1) end
                        dragging = false
                    end
                end)

                set(Slider.Value, true)
                Library.Options[flag] = Slider
                return Slider
            end

            -- BUTTON
            function Section:AddButton(text, callback)
                local B = new("TextButton", {
                    BackgroundColor3 = T.Element, Size = UDim2.new(1, 0, 0, 30),
                    Text = "", AutoButtonColor = false, BorderSizePixel = 0, Parent = Panel,
                })
                corner(B, 8)
                new("TextLabel", {
                    BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = T.Font,
                    TextSize = T.TextSize, TextColor3 = T.Text, Text = text or "Button", Parent = B,
                })
                hoverify(B, B, T.Element, T.ElementHover)
                conn(B.MouseButton1Click, function()
                    ripple(B)
                    if callback then task.spawn(callback) end
                end)
                return B
            end

            -- LABEL
            function Section:AddLabel(text)
                local L = new("TextLabel", {
                    BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18),
                    Font = T.Font, TextSize = 13, TextColor3 = T.TextDim,
                    TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
                    Text = text or "", Parent = Panel,
                })
                local o = {}
                function o:SetText(t) L.Text = t end
                return o
            end

            -- DROPDOWN
            function Section:AddDropdown(flag, o)
                o = o or {}
                local values = o.Values or {}
                local Drop = { Value = o.Default or (o.AllowNull and nil) or values[1], Type = "Dropdown", Open = false }
                local R = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), ClipsDescendants = false, Parent = Panel })
                new("TextLabel", {
                    BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), Font = T.Font,
                    TextSize = T.TextSize, TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
                    Text = o.Text or flag, Parent = R,
                })
                local Btn = new("TextButton", {
                    BackgroundColor3 = T.Element, Size = UDim2.new(1, 0, 0, 24),
                    Position = UDim2.fromOffset(0, 20), Text = "", AutoButtonColor = false,
                    BorderSizePixel = 0, Parent = R,
                })
                corner(Btn, 6)
                local Sel = new("TextLabel", {
                    BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, 0),
                    Position = UDim2.fromOffset(8, 0), Font = T.Font, TextSize = 13,
                    TextColor3 = T.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
                    Text = tostring(Drop.Value or "..."), Parent = Btn,
                })
                local Arrow = new("TextLabel", {
                    BackgroundTransparency = 1, Size = UDim2.fromOffset(20, 24),
                    Position = UDim2.new(1, -22, 0, 0), Font = T.Font, TextSize = 11,
                    TextColor3 = T.TextDim, Text = "v", Parent = Btn,
                })
                local Menu = new("Frame", {
                    BackgroundColor3 = Color3.fromRGB(24, 24, 24), Size = UDim2.new(1, 0, 0, 0),
                    Position = UDim2.fromOffset(0, 46), ClipsDescendants = true, Visible = false,
                    BorderSizePixel = 0, ZIndex = 10, Parent = R,
                })
                corner(Menu, 6)
                stroke(Menu, T.Stroke)
                local MList = new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = Menu })

                local function rebuild()
                    for _, c in ipairs(Menu:GetChildren()) do
                        if c:IsA("TextButton") then c:Destroy() end
                    end
                    for _, v in ipairs(values) do
                        local Item = new("TextButton", {
                            BackgroundColor3 = Color3.fromRGB(24, 24, 24), Size = UDim2.new(1, 0, 0, 24),
                            Text = "", AutoButtonColor = false, BorderSizePixel = 0, ZIndex = 11, Parent = Menu,
                        })
                        new("TextLabel", {
                            BackgroundTransparency = 1, Size = UDim2.new(1, -8, 1, 0),
                            Position = UDim2.fromOffset(8, 0), Font = T.Font, TextSize = 13,
                            TextColor3 = (v == Drop.Value) and T.Accent or T.TextDim,
                            TextXAlignment = Enum.TextXAlignment.Left, Text = tostring(v), ZIndex = 11, Parent = Item,
                        })
                        hoverify(Item, Item, Color3.fromRGB(24, 24, 24), T.Element)
                        conn(Item.MouseButton1Click, function()
                            Drop:SetValue(v)
                            Drop:Close()
                        end)
                    end
                end

                function Drop:SetValue(v, silent)
                    self.Value = v
                    Library.Flags[flag] = v
                    Sel.Text = tostring(v or "...")
                    Sel.TextColor3 = v and T.Text or T.TextDim
                    rebuild()
                    if not silent and o.Callback then task.spawn(o.Callback, v) end
                end
                function Drop:SetValues(v) values = v or {}; rebuild() end
                function Drop:GetValue() return self.Value end
                function Drop:Close()
                    self.Open = false
                    R.Size = UDim2.new(1, 0, 0, 44)
                    tween(Menu, { Size = UDim2.new(1, 0, 0, 0) }, 0.14)
                    tween(Arrow, { Rotation = 0 }, 0.14)
                    task.delay(0.15, function() if not self.Open then Menu.Visible = false end end)
                end
                function Drop:Toggle()
                    self.Open = not self.Open
                    if self.Open then
                        Menu.Visible = true
                        local h = math.min(#values * 24, 120)
                        tween(Menu, { Size = UDim2.new(1, 0, 0, h) }, 0.16)
                        tween(Arrow, { Rotation = 180 }, 0.16)
                        R.Size = UDim2.new(1, 0, 0, 44 + h + 4)
                    else
                        self:Close()
                    end
                end

                conn(Btn.MouseButton1Click, function() Drop:Toggle() end)
                hoverify(Btn, Btn, T.Element, T.ElementHover)
                rebuild()
                Drop:SetValue(Drop.Value, true)
                Library.Options[flag] = Drop
                return Drop
            end

            -- TEXTBOX
            function Section:AddTextbox(flag, o)
                o = o or {}
                local Box = { Value = o.Default or "", Type = "Textbox" }
                local R = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = Panel })
                new("TextLabel", {
                    BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), Font = T.Font,
                    TextSize = T.TextSize, TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
                    Text = o.Text or flag, Parent = R,
                })
                local Input = new("TextBox", {
                    BackgroundColor3 = T.Element, Size = UDim2.new(1, 0, 0, 24),
                    Position = UDim2.fromOffset(0, 20), Font = T.Font, TextSize = 13,
                    TextColor3 = T.Text, PlaceholderText = o.Placeholder or "...",
                    Text = Box.Value, ClearTextOnFocus = false, BorderSizePixel = 0, Parent = R,
                })
                corner(Input, 6)
                pad(Input, 8, 8, 0, 0)
                local Line = new("Frame", {
                    BackgroundColor3 = T.Accent, Size = UDim2.new(0, 0, 0, 1),
                    Position = UDim2.new(0, 0, 1, -1), BorderSizePixel = 0, Parent = Input,
                })
                conn(Input.Focused, function() tween(Line, { Size = UDim2.new(1, 0, 0, 1) }, 0.15) end)
                conn(Input.FocusLost, function()
                    tween(Line, { Size = UDim2.new(0, 0, 0, 1) }, 0.15)
                    Box.Value = Input.Text
                    Library.Flags[flag] = Input.Text
                    if o.Callback then task.spawn(o.Callback, Input.Text) end
                end)
                function Box:SetValue(v) Input.Text = tostring(v); self.Value = tostring(v); Library.Flags[flag] = self.Value end
                function Box:GetValue() return self.Value end
                Library.Options[flag] = Box
                return Box
            end

            -- KEYBIND
            function Section:AddKeybind(flag, o)
                o = o or {}
                local Key = { Value = o.Default or "None", Type = "Keybind", Binding = false }
                local R, L = row(o.Text or flag)
                L.Position = UDim2.fromOffset(0, 0)
                L.Size = UDim2.new(1, -80, 1, 0)
                local Btn = new("TextButton", {
                    BackgroundColor3 = T.Element, Size = UDim2.fromOffset(74, 22),
                    Position = UDim2.new(1, -74, 0.5, -11), Text = "", AutoButtonColor = false,
                    BorderSizePixel = 0, Parent = R,
                })
                corner(Btn, 6)
                local KL = new("TextLabel", {
                    BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = T.Font,
                    TextSize = 12, TextColor3 = T.TextDim, Text = tostring(Key.Value), Parent = Btn,
                })
                hoverify(Btn, Btn, T.Element, T.ElementHover)
                conn(Btn.MouseButton1Click, function()
                    Key.Binding = true
                    KL.Text = "..."
                    KL.TextColor3 = T.Accent
                end)
                conn(UserInputService.InputBegan, function(input, gp)
                    if Key.Binding and input.UserInputType == Enum.UserInputType.Keyboard then
                        Key.Binding = false
                        Key.Value = input.KeyCode.Name
                        Library.Flags[flag] = Key.Value
                        KL.Text = Key.Value
                        KL.TextColor3 = T.TextDim
                        if o.Callback then task.spawn(o.Callback, Key.Value) end
                        return
                    end
                    if gp or Key.Binding then return end
                    if Key.Value ~= "None" and input.KeyCode == Enum.KeyCode[Key.Value] and o.Pressed then
                        task.spawn(o.Pressed)
                    end
                end)
                function Key:SetValue(v) self.Value = v; KL.Text = tostring(v); Library.Flags[flag] = v end
                function Key:GetValue() return self.Value end
                Library.Options[flag] = Key
                return Key
            end

            return Section
        end

        table.insert(Window.Tabs, Tab)
        if #Window.Tabs == 1 then task.defer(function() Tab:Select() end) end
        return Tab
    end

    function Window:SetCrumb(text) Library._crumb.Text = text end

    Library._window = Window
    return Window
end

function Library:SetAccent(color)
    T.Accent = color
    -- Live-recolour anything already using the accent.
    if not self._gui then return end
    for _, d in ipairs(self._gui:GetDescendants()) do
        if d:IsA("Frame") or d:IsA("TextLabel") or d:IsA("ImageLabel") then
            pcall(function()
                if d.Name == "Fill" then d.BackgroundColor3 = color end
            end)
        end
    end
end

function Library:Unload()
    self.Unloaded = true
    if self._main then
        tween(self._main, { Size = UDim2.fromOffset(0, 0) }, 0.2)
        task.wait(0.22)
    end
    for _, c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
    self.Connections = {}
    if self._gui then pcall(function() self._gui:Destroy() end) end
end

return Library
