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
    IconVersion = "v2", -- bump on any icons/ change to invalidate the on-disk cache
    IconSize = 30,      -- sidebar glyph max dimension (Fit preserves each icon's aspect)
    GlowIntensity = 0.45, -- selected-tab halo strength (0 = solid, 1 = invisible)
    Blur = { Enabled = true, Size = 14, Tint = Color3.fromRGB(0, 0, 0), Alpha = 0.55 },
    _icons = {},
    _popups = {},
}
local T = Library.Theme
local function TW(t, style, dir)
    return TweenInfo.new(t or 0.18, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
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
local function tween(o, p, t, s, d) local x = TweenService:Create(o, TW(t, s, d), p) x:Play() return x end
local function conn(sig, fn) local c = sig:Connect(fn) table.insert(Library.Connections, c) return c end

-- Mount the exported Figma PNGs as local assets. getcustomasset gives an rbxasset://
-- URL for a file in the executor workspace, so the real icons work with no upload.
-- Falls back to "" (no image) on executors without writefile/getcustomasset.
function Library:LoadIcon(name)
    if self._icons[name] then return self._icons[name] end
    local id = ""
    local ok = pcall(function()
        -- Cache is keyed by IconVersion: icons are only fetched when the file is absent,
        -- so a folder populated by an older build keeps serving stale art forever. The
        -- icons were re-trimmed after the first release, and the stale padded copies then
        -- drew at the new ink-tight sizes -- i.e. shrunk twice. Bump IconVersion whenever
        -- icons/ changes; the new folder simply misses and re-downloads.
        local dir = "zaddz_icons_" .. Library.IconVersion
        local path = dir .. "/" .. name .. ".png"
        if not (isfile and isfile(path)) then
            if makefolder and not (isfolder and isfolder(dir)) then makefolder(dir) end
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
        -- Active = true so the panel ABSORBS input. A plain Frame is Active=false and Roblox
        -- passes clicks/drags straight through it, so a slider sitting behind an open colour
        -- picker still dragged while you were picking a colour.
        Visible = false, ClipsDescendants = true, BorderSizePixel = 0, Active = true,
        ZIndex = 51, Parent = self._popupLayer,
    })
    corner(frame, 12)
    new("UIStroke", { Color = Color3.fromRGB(48, 48, 48), Thickness = 1, Parent = frame })
    local body = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, -20, 1, -16),
        Position = UDim2.fromOffset(10, 8), ZIndex = 52, Parent = frame,
    })
    local P = { frame = frame, body = body, h = h, hovering = false, openedAt = 0 }
    conn(frame.MouseEnter, function() P.hovering = true end)
    conn(frame.MouseLeave, function() P.hovering = false end)

    -- hOverride lets a caller size the panel to its content (dropdowns grow with item count)
    function P.openAt(el, hOverride)
        Library:ClosePopups(P)
        P.h = hOverride or P.h
        -- position under the element, clamped inside the window
        local main = Library._main
        local rel = el.AbsolutePosition - main.AbsolutePosition
        local x = math.clamp(rel.X, 8, main.AbsoluteSize.X - w - 8)
        local y = rel.Y + el.AbsoluteSize.Y + 6
        if y + P.h > main.AbsoluteSize.Y - 8 then y = rel.Y - P.h - 6 end -- flip above
        -- InputBegan defers the outside-click sweep, and GUI click events fire after it,
        -- so the sweep can land on the popup this very click just opened. Stamp the open
        -- time and let the sweep ignore anything newer than a frame.
        P.openedAt = os.clock()
        frame.Position = UDim2.fromOffset(x, y)
        frame.Visible = true
        frame.Size = UDim2.fromOffset(w, 0)
        tween(frame, { Size = UDim2.fromOffset(w, P.h) }, 0.16, Enum.EasingStyle.Quad)
    end
    function P.close()
        tween(frame, { Size = UDim2.fromOffset(w, 0) }, 0.12)
        task.delay(0.13, function() frame.Visible = false end)
    end
    table.insert(self._popups, P)
    return P
end

-- TOOLTIP — one shared frame for the whole library, parented to the ScreenGui rather than
-- Main (which clips) so it can trail the cursor anywhere. Shown after a short dwell so it
-- doesn't strobe while the mouse crosses a panel.
function Library:AttachTooltip(gui, text)
    if not gui or not text or text == "" then return end
    local tip = self._tip
    if not tip then
        tip = new("Frame", {
            Name = "Tooltip", BackgroundColor3 = T.Panel, BorderSizePixel = 0, Visible = false,
            AutomaticSize = Enum.AutomaticSize.XY, ZIndex = 200, Parent = self._gui,
        })
        corner(tip, 5)
        new("UIStroke", { Color = Color3.fromRGB(48, 48, 48), Thickness = 1, Parent = tip })
        new("UIPadding", {
            PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7),
            PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = tip,
        })
        self._tipLabel = new("TextLabel", {
            BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY,
            Font = T.Font, TextSize = 12, TextColor3 = T.Text, ZIndex = 201, Text = "", Parent = tip,
        })
        self._tip = tip
    end

    local GuiService = game:GetService("GuiService")
    local token = 0
    local function place(x, y)
        -- MouseMoved reports screen space; a ScreenGui child's offset is measured from
        -- below the topbar, so take the inset out or the tip rides ~36px low.
        local inset = GuiService:GetGuiInset()
        tip.Position = UDim2.fromOffset(x - inset.X + 14, y - inset.Y + 18)
    end
    conn(gui.MouseEnter, function()
        token = token + 1
        local mine = token
        task.delay(0.35, function()
            if mine ~= token or self.TooltipsOn == false then return end -- left, or switched off
            self._tipLabel.Text = text
            tip.Visible = true
        end)
    end)
    conn(gui.MouseMoved, place)
    conn(gui.MouseLeave, function()
        token = token + 1
        tip.Visible = false
    end)
end

-- Draggable HUD overlay: the shared chrome behind the watermark and the keybind list.
-- HUDs get their OWN ScreenGui. Closing the menu sets _gui.Enabled = false, and a watermark
-- you can only see while the menu is open is pointless -- same for the keybind list, which
-- you want while playing, i.e. exactly when the menu is shut.
function Library:_makeHud(name, x, y, w)
    if not self._hudGui then
        self._hudGui = new("ScreenGui", {
            Name = "zaddz_hud", ResetOnSpawn = false, DisplayOrder = 9998,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = self._gui.Parent,
        })
    end
    local f = new("Frame", {
        Name = name, BackgroundColor3 = T.Panel, BorderSizePixel = 0, Visible = false,
        Size = UDim2.fromOffset(w, 28), Position = UDim2.fromOffset(x, y), Parent = self._hudGui,
    })
    corner(f, 6)
    new("UIStroke", { Color = Color3.fromRGB(48, 48, 48), Thickness = 1, Parent = f })
    new("Frame", { -- accent bar down the left edge
        BackgroundColor3 = T.Accent, Size = UDim2.new(0, 2, 1, -10),
        Position = UDim2.fromOffset(0, 5), BorderSizePixel = 0, Parent = f,
    })
    local dragging, startPos, startIn
    conn(f.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, startIn, startPos = true, i.Position, f.Position
        end
    end)
    conn(UserInputService.InputChanged, function(i)
        if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
            local d = i.Position - startIn
            f.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    conn(UserInputService.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    return f
end

-- WATERMARK — title + fps + ping + clock, refreshed once a second (not per frame).
function Library:SetWatermark(on, text)
    if text then self._wmText = text end
    local f = self._watermark
    if not f then
        f = self:_makeHud("Watermark", 12, 12, 240)
        self._watermark = f
        self._wmLabel = new("TextLabel", {
            BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0),
            Size = UDim2.new(1, -20, 1, 0), Font = T.FontBold, TextSize = 13,
            TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left, Text = "", Parent = f,
        })
        task.spawn(function()
            local RunService = game:GetService("RunService")
            local Stats, Players = game:GetService("Stats"), game:GetService("Players")
            while self._gui and self._gui.Parent do
                if f.Visible then
                    local fps = math.floor(1 / RunService.RenderStepped:Wait())
                    local ping = 0
                    pcall(function()
                        ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
                    end)
                    local txt = ("%s  |  %s  |  %d fps  |  %d ms  |  %s"):format(
                        self._wmText or "SUSANO.RE", Players.LocalPlayer and Players.LocalPlayer.Name or "?",
                        fps, ping, os.date("%H:%M:%S"))
                    self._wmLabel.Text = txt
                    f.Size = UDim2.fromOffset(math.max(180, self._wmLabel.TextBounds.X + 24), 28)
                end
                task.wait(1)
            end
        end)
    end
    f.Visible = on and true or false
end

-- KEYBIND LIST — one row per bound toggle, live-lit while the key is active.
function Library:SetKeybindList(on)
    local f = self._kbList
    if not f then
        f = self:_makeHud("Keybinds", 12, 52, 168)
        self._kbList = f
        new("TextLabel", {
            BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 4),
            Size = UDim2.new(1, -20, 0, 16), Font = T.FontBold, TextSize = 13,
            TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
            Text = "Keybinds", Parent = f,
        })
        self._kbRows = new("Frame", {
            BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 24),
            Size = UDim2.new(1, -20, 1, -28), Parent = f,
        })
        new("UIListLayout", { SortOrder = Enum.SortOrder.Name, Padding = UDim.new(0, 2), Parent = self._kbRows })
    end
    f.Visible = on and true or false
    if on then self:RefreshKeybinds() end
end

-- Rebuilt on demand (a bind changed / the list was shown), never polled.
function Library:RefreshKeybinds()
    local holder = self._kbRows
    if not holder then return end
    for _, c in ipairs(holder:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    local n = 0
    for flag, tg in pairs(self.Toggles) do
        local key = tg.Key
        if key and key ~= "None" then
            n = n + 1
            local row = new("Frame", {
                Name = tg._text or flag, BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 16), Parent = holder,
            })
            new("TextLabel", {
                BackgroundTransparency = 1, Size = UDim2.new(1, -54, 1, 0), Font = T.Font, TextSize = 12,
                TextColor3 = tg.Value and T.Accent or T.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
                Text = tg._text or flag, Parent = row,
            })
            new("TextLabel", {
                BackgroundTransparency = 1, Position = UDim2.new(1, -54, 0, 0), Size = UDim2.fromOffset(54, 16),
                Font = T.FontBold, TextSize = 12, TextColor3 = T.Icon,
                TextXAlignment = Enum.TextXAlignment.Right,
                Text = ("[%s] %s"):format(key, (tg.Mode or "Toggle"):sub(1, 1)), Parent = row,
            })
        end
    end
    if n == 0 then -- keep the panel up, say why it's empty rather than vanishing
        new("Frame", { Name = "zz", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), Parent = holder })
        new("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = T.Font, TextSize = 12,
            TextColor3 = T.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
            Text = "no binds set", Parent = holder.zz,
        })
        n = 1
    end
    if self._kbList then self._kbList.Size = UDim2.fromOffset(168, 28 + n * 18) end
end

-- Repaint any theme token live. Rather than registering every coloured object at build time
-- (bookkeeping that rots the moment someone adds a widget), sweep the tree and swap whatever
-- currently equals the OLD value of that token. Stays correct for widgets added later.
-- Caveat: it matches by colour, so two tokens sharing an exact value are indistinguishable.
local buildSection -- fwd decl: defined below, but OpenSettings above needs the upvalue
local COLOR_PROPS = { "BackgroundColor3", "ImageColor3", "TextColor3", "Color" }
local function sameColor(a, b)
    return math.abs(a.R - b.R) < 0.004 and math.abs(a.G - b.G) < 0.004 and math.abs(a.B - b.B) < 0.004
end
function Library:SetThemeColor(key, c)
    local old = T[key]
    if not c or typeof(old) ~= "Color3" or not self._gui then return end
    if sameColor(old, c) then return end
    for _, root in ipairs({ self._gui, self._hudGui }) do -- HUDs live on their own ScreenGui
        for _, d in ipairs(root:GetDescendants()) do
            for _, prop in ipairs(COLOR_PROPS) do
                local ok, v = pcall(function() return d[prop] end)
                if ok and typeof(v) == "Color3" and sameColor(v, old) then
                    pcall(function() d[prop] = c end)
                end
            end
        end
    end
    T[key] = c -- anything built from here on picks it up directly
end
function Library:SetAccent(c) return self:SetThemeColor("Accent", c) end

-- BLUR — a real Lighting BlurEffect plus a tint sheet, so the world behind the menu drops
-- back instead of the panel floating on a busy scene. Both are driven from Library.Blur.
function Library:_ensureBlur()
    if self._blurFx and self._blurFx.Parent then return end
    local Lighting = game:GetService("Lighting")
    self._blurFx = new("BlurEffect", { Name = "zaddz_blur", Size = 0, Enabled = true, Parent = Lighting })
    -- tint lives on its own ScreenGui UNDER the menu (DisplayOrder 9997 < 9998 hud < 9999 menu)
    if not self._tintGui then
        self._tintGui = new("ScreenGui", {
            Name = "zaddz_tint", ResetOnSpawn = false, DisplayOrder = 9997,
            IgnoreGuiInset = true, Parent = self._gui.Parent,
        })
        self._tint = new("Frame", {
            BackgroundColor3 = self.Blur.Tint, BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, Parent = self._tintGui,
        })
    end
end
-- `extra` lets the settings panel deepen the blur on top of the base menu blur.
function Library:ApplyBlur(on, extra)
    self:_ensureBlur()
    local B = self.Blur
    local size = (on and B.Enabled) and (B.Size + (extra or 0)) or 0
    tween(self._blurFx, { Size = size }, 0.25)
    self._tint.BackgroundColor3 = B.Tint
    tween(self._tint, { BackgroundTransparency = (on and B.Enabled) and (1 - B.Alpha) or 1 }, 0.25)
end

-- Animated show/hide. ScreenGui.Enabled is a hard cut, so drive Main's scale+fade and only
-- flip Enabled once the close finishes (keeps it from rendering while hidden).
function Library:SetOpen(open, instant)
    local main = self._main
    if not main or self._animating then return end
    self.Open = open and true or false
    if open then
        self._gui.Enabled = true
        self:ApplyBlur(true, self._settings and self._settings.Visible and 8 or 0)
        if instant then main.Size = UDim2.fromOffset(851, 597) return end
        main.Size = UDim2.fromOffset(0, 0)
        self._animating = true
        tween(main, { Size = UDim2.fromOffset(851, 597) }, 0.28, Enum.EasingStyle.Back)
        task.delay(0.29, function() self._animating = false end)
    else
        self:ClosePopups()
        -- The settings modal is a child of Main, so closing the window used to yank it away
        -- with no animation of its own. Collapse it first so it reads as one motion.
        if self._settings and self._settings.Visible then self:CloseSettings() end
        self:ApplyBlur(false)
        if instant then self._gui.Enabled = false return end
        self._animating = true
        -- Back/In anticipates (a small swell) before collapsing -- reads deliberate rather
        -- than dropped. Enabled goes false only after the tween has actually finished.
        tween(main, { Size = UDim2.fromOffset(0, 0) }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
        task.delay(0.21, function()
            self._animating = false
            if not self.Open then self._gui.Enabled = false end
        end)
    end
end
function Library:Toggle() self:SetOpen(not self.Open) end

-- SETTINGS — built from the SAME buildSection() controls as the menu, so every toggle,
-- slider and picker is pixel-identical to a real tab instead of a hand-rolled look-alike.
-- Grouped into panels (Menu / Colours / Background) exactly like a tab's sections.
local function settingsGroup(parent, title)
    local P = new("Frame", {
        BackgroundColor3 = T.Panel, Size = UDim2.new(1, -8, 1, 0),
        Position = UDim2.fromOffset(4, 0), BorderSizePixel = 0, ZIndex = 41, Parent = parent,
    })
    corner(P, 10)
    new("UIStroke", { Color = Color3.fromRGB(44, 44, 44), Thickness = 1, Parent = P })
    new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 6),
        Font = T.Font, TextSize = 14, TextColor3 = T.Text, Text = title, ZIndex = 42, Parent = P,
    })
    local body = new("ScrollingFrame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 28),
        Size = UDim2.new(1, 0, 1, -34), CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 2,
        ScrollBarImageColor3 = T.Scroll, ZIndex = 42, Parent = P,
    })
    new("UIListLayout", { Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
    return body
end

-- CONFIGS — flags + theme + keybinds serialised to JSON in the executor workspace.
-- Color3 can't survive JSONEncode, so colours are stored as {r,g,b} 0-255 triplets.
local HttpService = game:GetService("HttpService")
Library.ConfigFolder = "zaddz_configs"

local function packColor(c)
    return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end
local function unpackColor(t)
    if typeof(t) ~= "table" or #t < 3 then return nil end
    return Color3.fromRGB(t[1], t[2], t[3])
end

function Library:GetConfigList()
    local out = {}
    if not (isfolder and listfiles and isfolder(self.ConfigFolder)) then return out end
    local ok, files = pcall(listfiles, self.ConfigFolder)
    if not ok then return out end
    for _, f in ipairs(files) do
        local name = f:match("([^/\\]+)%.json$")
        if name then table.insert(out, name) end
    end
    table.sort(out)
    return out
end

-- Everything the UI owns: control values, the whole theme, the menu key, blur.
function Library:Serialize()
    local flags = {}
    for k, v in pairs(self.Flags) do
        local ty = typeof(v)
        if ty == "Color3" then flags[k] = { __c = packColor(v) }
        elseif ty == "number" or ty == "boolean" or ty == "string" then flags[k] = v end
    end
    local theme = {}
    for k, v in pairs(self.Theme) do
        if typeof(v) == "Color3" then theme[k] = packColor(v) end
    end
    return {
        version = 1, flags = flags, theme = theme,
        toggleKey = self.ToggleKey and self.ToggleKey.Name or "Insert",
        iconSize = self.IconSize, glow = self.GlowIntensity,
        blur = { Enabled = self.Blur.Enabled, Size = self.Blur.Size,
                 Alpha = self.Blur.Alpha, Tint = packColor(self.Blur.Tint) },
    }
end

function Library:Deserialize(data)
    if typeof(data) ~= "table" then return false, "bad config" end
    for k, v in pairs(data.theme or {}) do
        local c = unpackColor(v)
        if c and typeof(self.Theme[k]) == "Color3" then self:SetThemeColor(k, c) end
    end
    if data.blur then
        self.Blur.Enabled = data.blur.Enabled ~= false
        self.Blur.Size = tonumber(data.blur.Size) or self.Blur.Size
        self.Blur.Alpha = tonumber(data.blur.Alpha) or self.Blur.Alpha
        self.Blur.Tint = unpackColor(data.blur.Tint) or self.Blur.Tint
        self:ApplyBlur(self.Open)
    end
    if data.toggleKey and Enum.KeyCode[data.toggleKey] then self.ToggleKey = Enum.KeyCode[data.toggleKey] end
    if data.glow then self.GlowIntensity = data.glow end
    -- push values back THROUGH the controls, so the UI redraws and callbacks fire
    for k, v in pairs(data.flags or {}) do
        local opt = self.Options[k]
        if opt and opt.SetValue then
            local val = v
            if typeof(v) == "table" and v.__c then val = unpackColor(v.__c) end
            pcall(function() opt:SetValue(val) end)
        end
    end
    return true
end

function Library:SaveConfig(name)
    if not name or name == "" then return false, "name required" end
    if not writefile then return false, "executor has no writefile" end
    if makefolder and not (isfolder and isfolder(self.ConfigFolder)) then makefolder(self.ConfigFolder) end
    local ok, enc = pcall(function() return HttpService:JSONEncode(self:Serialize()) end)
    if not ok then return false, "encode failed" end
    local ok2, err = pcall(writefile, self.ConfigFolder .. "/" .. name .. ".json", enc)
    if not ok2 then return false, tostring(err) end
    return true
end

function Library:LoadConfig(name)
    if not (readfile and isfile) then return false, "executor has no readfile" end
    local path = self.ConfigFolder .. "/" .. name .. ".json"
    if not isfile(path) then return false, "no such config" end
    local ok, raw = pcall(readfile, path)
    if not ok then return false, "read failed" end
    local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok2 then return false, "corrupt json" end
    return self:Deserialize(data)
end

function Library:DeleteConfig(name)
    local path = self.ConfigFolder .. "/" .. name .. ".json"
    if delfile and isfile and isfile(path) then pcall(delfile, path) return true end
    return false, "no such config"
end

function Library:CloseSettings()
    local S = self._settings
    if not S or not S.Visible then return end
    self:ClosePopups()
    tween(S, { Size = UDim2.fromOffset(S.Size.X.Offset, 0) }, 0.16, Enum.EasingStyle.Quad)
    task.delay(0.17, function() if S then S.Visible = false end end)
    self:ApplyBlur(self.Open, 0) -- drop back to the plain menu blur
end

function Library:OpenSettings()
    local W, H = 720, 470
    local S = self._settings
    if S then
        if S.Visible then return self:CloseSettings() end
        S.Visible = true
        S.Size = UDim2.fromOffset(W, 0)
        S._openedAt = os.clock()
        tween(S, { Size = UDim2.fromOffset(W, H) }, 0.2, Enum.EasingStyle.Back)
        self:ApplyBlur(self.Open, 8)
        return
    end

    S = new("Frame", {
        Name = "Settings", BackgroundColor3 = T.Body, BorderSizePixel = 0, Active = true,
        Size = UDim2.fromOffset(W, 0), Position = UDim2.new(0.5, 0, 0.5, 0),
        -- ZIndex 40: BELOW MakePopup's 51. The colour pickers and dropdowns inside are
        -- siblings in the popup layer, so at 60 they would open behind this panel. It still
        -- draws over the tabs because the popup layer itself is ZIndex 50 within Main.
        AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 40, ClipsDescendants = true,
        Parent = self._popupLayer,
    })
    corner(S, 12)
    new("UIStroke", { Color = Color3.fromRGB(48, 48, 48), Thickness = 1, Parent = S })
    self._settings = S
    S._openedAt = os.clock()
    conn(S.MouseEnter, function() S._hovering = true end)
    conn(S.MouseLeave, function() S._hovering = false end)

    new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.fromOffset(200, 22), Position = UDim2.fromOffset(14, 8),
        Font = T.FontBold, TextSize = 16, TextColor3 = T.Text,
        TextXAlignment = Enum.TextXAlignment.Left, Text = "Settings", ZIndex = 41, Parent = S,
    })
    local X = new("TextButton", {
        BackgroundTransparency = 1, Position = UDim2.new(1, -30, 0, 8), Size = UDim2.fromOffset(22, 22),
        Font = T.FontBold, TextSize = 15, TextColor3 = T.Icon, Text = "X",
        AutoButtonColor = false, ZIndex = 41, Parent = S,
    })
    conn(X.MouseButton1Click, function() Library:CloseSettings() end)
    conn(X.MouseEnter, function() tween(X, { TextColor3 = T.Text }, 0.1) end)
    conn(X.MouseLeave, function() tween(X, { TextColor3 = T.Icon }, 0.1) end)

    -- three columns of groupboxes
    local colW = (W - 16) / 3
    local function col(i, title)
        local holder = new("Frame", {
            BackgroundTransparency = 1, Size = UDim2.fromOffset(colW, H - 44),
            Position = UDim2.fromOffset(8 + (i - 1) * colW, 36), ZIndex = 41, Parent = S,
        })
        return settingsGroup(holder, title)
    end

    -- ── Menu
    local Sec1 = buildSection(col(1, "Menu"))
    Sec1:AddKeybind("_MenuKey", { Text = "Menu key", Default = self.ToggleKey.Name,
        Tooltip = "Key that opens and closes this menu.",
        Callback = function(k) Library.ToggleKey = Enum.KeyCode[k] or Library.ToggleKey end })
    Sec1:AddSlider("_UIScale", { Text = "UI scale", Min = 60, Max = 140, Default = 100,
        Rounding = 0, Format = "%d", Suffix = "%", Tooltip = "Scales the whole window.",
        Callback = function(v)
            self._uiScale = self._uiScale or new("UIScale", { Scale = 1, Parent = self._main })
            self._uiScale.Scale = v / 100
        end })
    Sec1:AddSlider("_IconSize", { Text = "Icon size", Min = 18, Max = 40, Default = self.IconSize,
        Rounding = 0, Format = "%d", Tooltip = "Size of the sidebar tab icons.",
        Callback = function(v)
            self.IconSize = v
            for _, t in ipairs(self._window and self._window.Tabs or {}) do
                if t._ico then
                    t._ico.Size = UDim2.fromOffset(v, v)
                    t._ico.Position = UDim2.new(0.5, -v / 2, 0.5, -v / 2)
                end
            end
        end })
    Sec1:AddSlider("_Glow", { Text = "Tab glow", Min = 0, Max = 100,
        Default = math.floor((1 - self.GlowIntensity) * 100), Rounding = 0, Format = "%d", Suffix = "%",
        Tooltip = "Strength of the selected tab's halo.",
        Callback = function(v)
            self.GlowIntensity = 1 - v / 100
            local cur = self._window and self._window._current
            if cur and cur._glow then cur._glow.ImageTransparency = self.GlowIntensity end
        end })
    Sec1:AddToggle("_Watermark", { Text = "Watermark", Keybind = false,
        Default = self._watermark and self._watermark.Visible or false,
        Tooltip = "Title, fps, ping and clock. Stays up when the menu is closed.",
        Callback = function(v) Library:SetWatermark(v) end })
    Sec1:AddToggle("_KeybindList", { Text = "Keybind list", Keybind = false,
        Default = self._kbList and self._kbList.Visible or false,
        Tooltip = "On-screen list of every bound key.",
        Callback = function(v) Library:SetKeybindList(v) end })
    Sec1:AddToggle("_Tooltips", { Text = "Tooltips", Keybind = false, Default = self.TooltipsOn ~= false,
        Tooltip = "These little hover boxes.",
        Callback = function(v) Library.TooltipsOn = v end })
    Sec1:AddButton("Unload menu", function() Library:Unload() end,
        "Destroys the menu. Re-execute the script to get it back.")

    -- ── Colours: every theme token, not just the accent
    local Sec2 = buildSection(col(2, "Colours"))
    local TOKENS = {
        { "Accent", "Accent" }, { "AccentDim", "Accent dim" }, { "Scroll", "Scrollbar" },
        { "Body", "Background" }, { "Sidebar", "Sidebar" }, { "Panel", "Panel" },
        { "Element", "Element" }, { "Hover", "Hover" },
        { "Text", "Text" }, { "TextDim", "Text dim" }, { "Icon", "Icons" },
    }
    for _, tk in ipairs(TOKENS) do
        local key, label = tk[1], tk[2]
        Sec2:AddColorPicker("_C_" .. key, { Text = label, Default = T[key],
            Callback = function(c) Library:SetThemeColor(key, c) end })
    end

    -- ── Background blur
    local Sec3 = buildSection(col(3, "Background"))
    local function reblur() Library:ApplyBlur(Library.Open, S.Visible and 8 or 0) end
    Sec3:AddToggle("_BlurOn", { Text = "Blur", Keybind = false, Default = self.Blur.Enabled,
        Tooltip = "Blurs the world behind the menu.",
        Callback = function(v) self.Blur.Enabled = v reblur() end })
    Sec3:AddSlider("_BlurSize", { Text = "Blur amount", Min = 0, Max = 40, Default = self.Blur.Size,
        Rounding = 0, Format = "%d", Tooltip = "How strong the background blur is.",
        Callback = function(v) self.Blur.Size = v reblur() end })
    Sec3:AddSlider("_BlurAlpha", { Text = "Tint opacity", Min = 0, Max = 100,
        Default = math.floor(self.Blur.Alpha * 100), Rounding = 0, Format = "%d", Suffix = "%",
        Tooltip = "How heavily the tint colour washes the background.",
        Callback = function(v) self.Blur.Alpha = v / 100 reblur() end })
    Sec3:AddColorPicker("_BlurTint", { Text = "Tint colour", Default = self.Blur.Tint,
        Tooltip = "Colour washed over the world behind the menu.",
        Callback = function(c) self.Blur.Tint = c reblur() end })

    tween(S, { Size = UDim2.fromOffset(W, H) }, 0.2, Enum.EasingStyle.Back)
    self:ApplyBlur(self.Open, 8)
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

-- Every Section:Add* control, lifted out of Tab:AddSection. They only ever captured
-- Body_, so hoisting them costs nothing and lets the settings panel build REAL menu
-- controls instead of the hand-rolled pills/sliders it used to fake.
buildSection = function(Body_)
    local Section = {}
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
                -- fromScale(0.5,0.5), not fromOffset(11,11): the box is 23 wide so its true
                -- centre is 11.5, and that half-pixel error read as an off-centre fill.
                BackgroundColor3 = T.Accent, Size = UDim2.fromOffset(0, 0),
                Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
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

            Tg._text = o.Text or flag -- what the keybind list shows for this row
            function Tg:SetValue(v, silent)
                self.Value = v and true or false
                Library.Flags[flag] = self.Value
                -- Back easing OVERSHOOTS its target. Growing 0->19 that's a nice pop,
                -- but shrinking 19->0 it overshoots negative, which renders as nothing --
                -- the fill just blinked out and the un-toggle looked unanimated. So:
                -- Back only on the way in, a soft Quint collapse on the way out, with
                -- the fade riding along so it dissolves rather than snapping.
                if self.Value then
                    tween(Fill, { Size = UDim2.fromOffset(19, 19), BackgroundTransparency = 0 },
                        0.22, Enum.EasingStyle.Back)
                else
                    tween(Fill, { Size = UDim2.fromOffset(4, 4), BackgroundTransparency = 1 },
                        0.18, Enum.EasingStyle.Quint)
                end
                tween(Box, { BackgroundColor3 = self.Value and T.AccentDim or T.Element }, 0.18)
                -- keep the keybind list's lit state honest, but only while it's shown
                if Library._kbList and Library._kbList.Visible then Library:RefreshKeybinds() end
                if not silent and o.Callback then task.spawn(o.Callback, self.Value) end
            end
            function Tg:GetValue() return self.Value end
            conn(Hit.MouseButton1Click, function() Tg:SetValue(not Tg.Value) end)
            conn(Hit.MouseEnter, function() tween(Box, { BackgroundColor3 = Tg.Value and T.Accent or T.Hover }, 0.12) end)
            conn(Hit.MouseLeave, function() -- settle back to the state colour, not always Element
                tween(Box, { BackgroundColor3 = Tg.Value and T.AccentDim or T.Element }, 0.12)
            end)

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
                    Library:RefreshKeybinds()
                end
                local MODES = { "Toggle", "Hold", "Always" }
                conn(ModeBtn.MouseButton1Click, function()
                    local i = table.find(MODES, mode) or 1
                    mode = MODES[(i % #MODES) + 1]
                    Tg.Mode = mode
                    ModeTxt.Text = mode
                    Library.Flags[flag .. "_Mode"] = mode
                    Library:RefreshKeybinds()
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
            Library:AttachTooltip(R, o.Tooltip)
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

            local dragging, hovering = false, false
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
            conn(Box.MouseEnter, function() hovering = true tween(Box, { BackgroundColor3 = T.Hover }, 0.12) end)
            conn(Box.MouseLeave, function() hovering = false tween(Box, { BackgroundColor3 = T.Element }, 0.12) end)
            -- scroll wheel steps the value while hovered. Step is o.Step, else 1/50th of the
            -- range snapped to the slider's own rounding, so an int slider moves whole units.
            conn(Box.InputChanged, function(i)
                if not hovering or i.UserInputType ~= Enum.UserInputType.MouseWheel then return end
                local step = o.Step
                if not step then
                    step = (max - min) / 50
                    local m = 10 ^ (o.Rounding or 2)
                    step = math.max(math.floor(step * m + 0.5) / m, 1 / m)
                end
                set(S.Value + i.Position.Z * step)
            end)

            set(S.Value, true)
            Library:AttachTooltip(R, o.Tooltip)
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
            -- The menu lives in the POPUP LAYER, not under this row. ZIndexBehavior is
            -- Sibling, so a menu parented here would only be ordered within its own row:
            -- every row added after it draws on top and swallows the item clicks -- the
            -- menu opened fine but nothing was selectable. The popup layer is top-level,
            -- so it also escapes the section's ClipsDescendants.
            local P = Library:MakePopup(301, 120)
            local Menu = new("ScrollingFrame", {
                BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0,
                ScrollBarThickness = 3, ScrollBarImageColor3 = T.Scroll,
                CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ZIndex = 53, Parent = P.body,
            })
            new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = Menu })

            local function rebuild()
                for _, c in ipairs(Menu:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
                for _, v in ipairs(values) do
                    local sel = (v == D.Value)
                    local It = new("TextButton", {
                        BackgroundColor3 = sel and T.Element or Color3.fromRGB(24, 24, 24),
                        Size = UDim2.new(1, -4, 0, 26), Text = "", AutoButtonColor = false,
                        BorderSizePixel = 0, ZIndex = 54, Parent = Menu,
                    })
                    corner(It, 5)
                    new("TextLabel", {
                        BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0),
                        Size = UDim2.new(1, -10, 1, 0), Font = T.Font, TextSize = 13,
                        TextColor3 = sel and T.Accent or T.TextDim,
                        TextXAlignment = Enum.TextXAlignment.Left, Text = tostring(v), ZIndex = 55, Parent = It,
                    })
                    conn(It.MouseEnter, function() tween(It, { BackgroundColor3 = T.Hover }, 0.1) end)
                    conn(It.MouseLeave, function()
                        tween(It, { BackgroundColor3 = (v == D.Value) and T.Element or Color3.fromRGB(24, 24, 24) }, 0.1)
                    end)
                    conn(It.MouseButton1Click, function() D:SetValue(v); D:Close() end)
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
                P.close()
            end
            conn(Box.MouseButton1Click, function()
                if D.Open then D:Close() return end
                D.Open = true
                P.openAt(Box, math.clamp(#values * 28 + 16, 44, 190)) -- grow to fit, then scroll
            end)
            conn(P.frame:GetPropertyChangedSignal("Visible"), function()
                if not P.frame.Visible then D.Open = false end -- ClosePopups() closed us
            end)
            conn(Box.MouseEnter, function() tween(Box, { BackgroundColor3 = T.Hover }, 0.12) end)
            conn(Box.MouseLeave, function() tween(Box, { BackgroundColor3 = T.Element }, 0.12) end)
            rebuild(); D:SetValue(D.Value, true)
            Library:AttachTooltip(R, o.Tooltip)
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
            Library:AttachTooltip(R, o.Tooltip)
            Library.Options[flag] = B
            return B
        end

        function Section:AddButton(text, cb, tip)
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
            Library:AttachTooltip(Btn, tip)
            return Btn
        end

        -- KEYBIND — a standalone bind row. The toggle's keybind glyph only exists welded to
        -- a toggle, so there was no way to bind anything else. Same 301x34 element as a
        -- dropdown: label left, key right, click to listen.
        function Section:AddKeybind(flag, o)
            o = o or {}
            local K = { Value = o.Default or "None", Type = "Keybind" }
            local R = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = Body_ })
            local Box = new("TextButton", {
                BackgroundColor3 = T.Element, Size = UDim2.fromOffset(301, 34),
                Position = UDim2.fromOffset(20, 0), Text = "", AutoButtonColor = false,
                BorderSizePixel = 0, Parent = R,
            })
            corner(Box, 6)
            new("TextLabel", {
                BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0),
                Size = UDim2.new(1, -120, 1, 0), Font = T.FontBold, TextSize = T.TextSize,
                TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
                Text = o.Text or flag, Parent = Box,
            })
            local KeyTxt = new("TextLabel", {
                BackgroundTransparency = 1, Position = UDim2.new(1, -110, 0, 0),
                Size = UDim2.fromOffset(100, 34), Font = T.Font, TextSize = T.TextSize,
                TextColor3 = T.Icon, TextXAlignment = Enum.TextXAlignment.Right,
                Text = tostring(K.Value), Parent = Box,
            })
            new("Frame", {
                BackgroundColor3 = T.AccentDim, Size = UDim2.new(1, 0, 0, 2),
                Position = UDim2.new(0, 0, 1, -2), BorderSizePixel = 0, Parent = Box,
            })
            local listening = false
            function K:SetValue(k, silent)
                self.Value = k
                Library.Flags[flag] = k
                KeyTxt.Text = tostring(k)
                KeyTxt.TextColor3 = (k ~= "None") and T.Accent or T.Icon
                if not silent and o.Callback then task.spawn(o.Callback, k) end
            end
            function K:GetValue() return self.Value end
            conn(Box.MouseButton1Click, function()
                listening = true
                Library._rebinding = true -- stop the menu's own toggle key firing mid-bind
                KeyTxt.Text = "press a key..."
                KeyTxt.TextColor3 = T.Accent
            end)
            conn(UserInputService.InputBegan, function(i)
                if not listening or i.UserInputType ~= Enum.UserInputType.Keyboard then return end
                listening = false
                Library._rebinding = false
                K:SetValue(i.KeyCode == Enum.KeyCode.Backspace and "None" or i.KeyCode.Name)
            end)
            conn(Box.MouseEnter, function() tween(Box, { BackgroundColor3 = T.Hover }, 0.12) end)
            conn(Box.MouseLeave, function() tween(Box, { BackgroundColor3 = T.Element }, 0.12) end)
            K:SetValue(K.Value, true)
            Library:AttachTooltip(R, o.Tooltip)
            Library.Options[flag] = K
            return K
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
            Library:AttachTooltip(R, o.Tooltip)
            Library.Options[flag] = CP
            return CP
        end

        -- CONFIGS — drop a whole save/load UI into any section with one call. Lives in a
        -- TAB rather than the settings modal, so configs are a first-class feature.
        function Section:AddConfigManager()
            local list = Section:AddDropdown("ConfigList", { Text = "Config",
                Values = Library:GetConfigList(), Default = nil,
                Tooltip = "Saved configs in the executor's " .. Library.ConfigFolder .. " folder." })
            local nameBox = Section:AddTextbox("ConfigName", { Text = "Name", Placeholder = "my config" })
            local function refresh()
                local names = Library:GetConfigList()
                list:SetValues(names)
                return names
            end
            Section:AddButton("Save", function()
                local n = Library.Flags.ConfigName
                if not n or n == "" then return Library:Notify("Type a name first") end
                local ok, err = Library:SaveConfig(n)
                refresh()
                Library:Notify(ok and ("Saved " .. n) or ("Save failed: " .. tostring(err)))
            end, "Writes every control value, the theme and the blur to a .json file.")
            Section:AddButton("Load", function()
                local n = Library.Flags.ConfigList
                if not n then return Library:Notify("Pick a config first") end
                local ok, err = Library:LoadConfig(n)
                Library:Notify(ok and ("Loaded " .. n) or ("Load failed: " .. tostring(err)))
            end, "Applies the selected config to every control.")
            Section:AddButton("Delete", function()
                local n = Library.Flags.ConfigList
                if not n then return Library:Notify("Pick a config first") end
                Library:DeleteConfig(n)
                refresh()
                Library:Notify("Deleted " .. n)
            end, "Removes the selected config file. Not undoable.")
            Section:AddButton("Refresh list", function()
                Library:Notify(#refresh() .. " config(s)")
            end)
            return { Refresh = refresh }
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
    self.Open = true -- keeps the Insert toggle in sync with the intro animation
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

    -- Gear, top-right. Parented to Main (not Body) and given a ZIndex above the drag Bar:
    -- the Bar is a TextButton covering the whole top 100px and is created after Body, so
    -- under ZIndexBehavior.Sibling it drew over the gear and swallowed every click. Raising
    -- the gear's ZIndex inside Body would do nothing -- Body's subtree draws as one group,
    -- beneath the Bar. Screen position is unchanged: Body sits at x=3 and is 848 wide, so
    -- 3 + (848-50) == 851-50.
    local Gear = new("TextButton", {
        BackgroundTransparency = 1, Size = UDim2.fromOffset(26, 26), ZIndex = 5,
        Position = UDim2.new(1, -50, 0, 28), Text = "", AutoButtonColor = false, Parent = Main,
    })
    local GearIco = new("ImageLabel", {
        BackgroundTransparency = 1, Image = Library:LoadIcon("gear"), ImageColor3 = T.Icon,
        ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = Gear,
    })
    conn(Gear.MouseEnter, function() tween(GearIco, { ImageColor3 = T.Text, Rotation = 45 }, 0.2) end)
    conn(Gear.MouseLeave, function() tween(GearIco, { ImageColor3 = T.Icon, Rotation = 0 }, 0.2) end)
    conn(Gear.MouseButton1Click, function() Library:OpenSettings() end)

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
            Library:Toggle()
        end
        -- click outside closes any open popup
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            task.defer(function()
                for _, p in ipairs(Library._popups) do
                    if p.frame and p.frame.Visible and not p.hovering
                        and os.clock() - (p.openedAt or 0) > 0.1 then p.close() end
                end
                -- clicking outside the settings modal closes it too. Skip while a popup is
                -- hovered (its picker sits over the panel) and during the open frame.
                -- Hover flag, not coordinates: GetMouseLocation() includes the topbar inset
                -- while AbsolutePosition does not, so comparing them is 36px wrong.
                local S = Library._settings
                if S and S.Visible and not S._hovering
                    and os.clock() - (S._openedAt or 0) > 0.15 then
                    local onPopup = false
                    for _, pp in ipairs(Library._popups) do
                        if pp.frame and pp.frame.Visible and pp.hovering then onPopup = true break end
                    end
                    if not onPopup then Library:CloseSettings() end
                end
            end)
        end
    end)

    local Window = { Tabs = {}, _title = title, _current = nil }
    self._window = Window -- settings panel reaches the tab rail through this

    -- Sidebar rail centres, measured off the rendered Figma design (node 1:3).
    -- Only the centres come from the design. Sizing every glyph to its own Figma ink is
    -- technically 1:1 but reads small and uneven (globe 22, pistol 23x14), so all glyphs
    -- share one box instead: Library.IconSize is the max dimension and Fit keeps each
    -- PNG's aspect, so they land at a consistent visual weight. Tune the one number.
    local RAIL_CY = { 115.5, 171.8, 225.0, 273.3, 319.0, 366.5, 418.5 }
    local RAIL_CX = 38 -- glyph centre line; design varies 36-40, one line reads straighter
    local function railSlot(idx)
        local cy = RAIL_CY[idx] or (RAIL_CY[#RAIL_CY] + (idx - #RAIL_CY) * 53)
        return { cx = RAIL_CX, cy = cy }
    end
    -- Figma's selected-tab glow is a DROP_SHADOW: colour #387BDB, radius 15.3, offset 0.
    -- It is dimmer than the glyph accent and only spreads ~13px -- not a 58px accent bloom.
    local GLOW_COLOR, GLOW_PAD = Color3.fromRGB(56, 123, 219), 26

    function Window:AddTab(name, icon, tabOpts)
        tabOpts = tabOpts or {}
        local idx = #Window.Tabs + 1
        local Tab = { Name = name, _window = Window }

        local slot = railSlot(idx)
        local cx, cy = slot.cx, slot.cy
        local Btn = new("TextButton", { -- invisible hit area, centred on the glyph
            BackgroundTransparency = 1, Size = UDim2.fromOffset(46, 46),
            Position = UDim2.fromOffset(math.floor(cx - 23), math.floor(cy - 23)),
            Text = "", AutoButtonColor = false, Parent = Sidebar,
        })
        local isz = Library.IconSize
        local gw, gh = isz + GLOW_PAD, isz + GLOW_PAD
        -- Real radial bloom (glow.png), NOT a scaled copy of the icon -- a tinted enlarged
        -- glyph just reads as a big blurry duplicate, which is what the last build did.
        local Glow = new("ImageLabel", {
            BackgroundTransparency = 1, Image = Library:LoadIcon("glow"),
            ImageColor3 = GLOW_COLOR, ImageTransparency = 1,
            Size = UDim2.fromOffset(gw, gh), Position = UDim2.new(0.5, -gw / 2, 0.5, -gh / 2),
            ScaleType = Enum.ScaleType.Fit, ZIndex = 1, Parent = Btn,
        })
        -- One box for every glyph; Fit letterboxes inside it, so each PNG keeps its own
        -- aspect (the 140x86 pistol stays wide) while sharing a common visual weight.
        local Ico = new("ImageLabel", {
            BackgroundTransparency = 1, Image = icon and Library:LoadIcon(icon) or "",
            ImageColor3 = T.Icon, ScaleType = Enum.ScaleType.Fit,
            Size = UDim2.fromOffset(isz, isz),
            Position = UDim2.new(0.5, -isz / 2, 0.5, -isz / 2),
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
            tween(Glow, { ImageTransparency = Library.GlowIntensity }, 0.28)
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

            local S2 = buildSection(Body_)
            for k, v in pairs(S2) do Section[k] = v end
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
    -- Kill the blur FIRST. It lives in Lighting, OUTSIDE our ScreenGuis, so destroying the
    -- guis alone would leave the player's screen blurred for the rest of the session with
    -- no menu left to switch it off.
    if self._blurFx then pcall(function() self._blurFx:Destroy() end) end
    if self._tintGui then pcall(function() self._tintGui:Destroy() end) end
    if self._main then
        tween(self._main, { Size = UDim2.fromOffset(0, 0) }, 0.22)
        task.wait(0.24)
    end
    for _, c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
    self.Connections = {}
    if self._gui then pcall(function() self._gui:Destroy() end) end
    if self._hudGui then pcall(function() self._hudGui:Destroy() end) end
    -- drop refs to the destroyed instances so a later CreateWindow rebuilds them
    self._watermark, self._wmLabel, self._kbList, self._kbRows = nil, nil, nil, nil
    self._tip, self._tipLabel = nil, nil
    self._settings, self._uiScale, self._window, self._hudGui = nil, nil, nil, nil
    self._blurFx, self._tintGui, self._tint = nil, nil, nil
    self._popups, self._icons = {}, {}
end

return Library
