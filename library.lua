local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

if _G.InterceptionUI and _G.InterceptionUI.unload then
    pcall(function()
        _G.InterceptionUI:unload()
    end)
end

local floor, min, max, abs, sin = math.floor, math.min, math.max, math.abs, math.sin
local band, bxor, rshift = bit32.band, bit32.bxor, bit32.rshift
local vec2 = Vector2.new
local dim2 = UDim2.new
local rgb = Color3.fromRGB
local hsv = Color3.fromHSV

local FONT = Drawing.Fonts.UI
local FONT_SIZE = 13
local CHAR_W = 7
local TEXT_H = 13
local Z_BASE = 2000
local GUI_INSET = 58

local Util = {}

function Util.round(v)
    return floor(v + 0.5)
end

function Util.clamp(v, lo, hi)
    if v < lo then
        return lo
    end
    if v > hi then
        return hi
    end
    return v
end

function Util.textWidth(s)
    return #s * CHAR_W
end

function Util.pack(r, g, b, a)
    a = floor(a + 0.5)
    if a < 0 then
        a = 0
    elseif a > 255 then
        a = 255
    end
    return ((floor(r + 0.5) * 256 + floor(g + 0.5)) * 256 + floor(b + 0.5)) * 256 + a
end

function Util.packColor(c, alpha)
    return Util.pack(c.R * 255, c.G * 255, c.B * 255, (alpha or 1) * 255)
end

function Util.unpackColor(c)
    local a = c % 256
    c = (c - a) / 256
    local b = c % 256
    c = (c - b) / 256
    local g = c % 256
    return (c - g) / 256, g, b, a
end

function Util.grey(v, a)
    return Util.pack(v, v, v, a or 255)
end

function Util.toHSV(c)
    local r, g, b = c.R, c.G, c.B
    local hi, lo = max(r, g, b), min(r, g, b)
    local d = hi - lo
    local h = 0
    if d > 0 then
        if hi == r then
            h = ((g - b) / d) % 6
        elseif hi == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h / 6
    end
    return h, hi == 0 and 0 or d / hi, hi
end

function Util.toHex(c)
    return string.format("%02X%02X%02X", Util.round(c.R * 255), Util.round(c.G * 255), Util.round(c.B * 255))
end

function Util.lerpColor(a, b, t)
    return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

function Util.quadInOut(t)
    if t < 0.5 then
        return 2 * t * t
    end
    return 1 - ((-2 * t + 2) ^ 2) / 2
end

function Util.expoInOut(t)
    if t <= 0 then
        return 0
    end
    if t >= 1 then
        return 1
    end
    if t < 0.5 then
        return (2 ^ (20 * t - 10)) / 2
    end
    return (2 - 2 ^ (-20 * t + 10)) / 2
end

function Util.viewport()
    local cam = workspace.CurrentCamera
    if cam then
        local ok, size = pcall(function()
            return cam.ViewportSize
        end)
        if ok and size then
            return size.X, size.Y
        end
    end
    return 1920, 1080
end

function Util.resolveAxis(udim2, axis, parentSize, default)
    local ok, value = pcall(function()
        local udim = udim2[axis]
        return (udim.Scale or 0) * parentSize + (udim.Offset or 0)
    end)
    if ok and type(value) == "number" and value > 0 then
        return floor(value + 0.5)
    end
    return default
end

local round, clamp, textWidth, pack, packColor, grey = Util.round, Util.clamp, Util.textWidth, Util.pack, Util.packColor, Util.grey

local COL = {
    c0 = grey(0),
    c8 = grey(8),
    c19 = grey(19),
    c22 = grey(22),
    c26 = grey(26),
    c33 = grey(33),
    c38 = grey(38),
    c40 = grey(40),
    c56 = grey(56),
    c57 = grey(57),
    c65 = grey(65),
    text = grey(170),
    placeholder = grey(90),
    heading = grey(120),
    white = grey(255),
    black50 = grey(0, 128),
    shadow = grey(0, 153),
    fillBorder = pack(27, 42, 53, 255),
    marker = grey(200),
}

local Png = {}

do
    local crcTable = {}
    for i = 0, 255 do
        local c = i
        for _ = 1, 8 do
            if band(c, 1) == 1 then
                c = bxor(0xEDB88320, rshift(c, 1))
            else
                c = rshift(c, 1)
            end
        end
        crcTable[i] = c
    end

    local function crc32(s)
        local c = 0xFFFFFFFF
        for i = 1, #s do
            c = bxor(crcTable[band(bxor(c, string.byte(s, i)), 0xFF)], rshift(c, 8))
        end
        return bxor(c, 0xFFFFFFFF)
    end

    local function adler32(s)
        local a, b = 1, 0
        for i = 1, #s do
            a = (a + string.byte(s, i)) % 65521
            b = (b + a) % 65521
        end
        return b * 65536 + a
    end

    local function be32(n)
        return string.char(band(rshift(n, 24), 255), band(rshift(n, 16), 255), band(rshift(n, 8), 255), band(n, 255))
    end

    local function chunk(kind, data)
        return be32(#data) .. kind .. data .. be32(crc32(kind .. data))
    end

    function Png.encode(width, height, pixel)
        local rows = {}
        for y = 0, height - 1 do
            local row = { "\0" }
            for x = 0, width - 1 do
                row[x + 2] = string.char(pixel(x, y))
            end
            rows[y + 1] = table.concat(row)
        end
        local raw = table.concat(rows)
        local deflate = { "\120\1" }
        local pos, total = 1, #raw
        while pos <= total do
            local len = min(65535, total - pos + 1)
            local final = (pos + len > total) and 1 or 0
            local nlen = 65535 - len
            deflate[#deflate + 1] = string.char(final, len % 256, floor(len / 256), nlen % 256, floor(nlen / 256))
            deflate[#deflate + 1] = string.sub(raw, pos, pos + len - 1)
            pos = pos + len
        end
        deflate[#deflate + 1] = be32(adler32(raw))
        return "\137PNG\r\n\26\n"
            .. chunk("IHDR", be32(width) .. be32(height) .. "\8\6\0\0\0")
            .. chunk("IDAT", table.concat(deflate))
            .. chunk("IEND", "")
    end
end

local HUE_KEYS = {
    { 0, 255, 0, 0 },
    { 0.167, 255, 255, 0 },
    { 0.333, 0, 255, 0 },
    { 0.5, 0, 255, 255 },
    { 0.667, 0, 0, 255 },
    { 0.833, 255, 0, 255 },
    { 1, 255, 0, 0 },
}

local function hueAt(t)
    for i = 1, #HUE_KEYS - 1 do
        local a, b = HUE_KEYS[i], HUE_KEYS[i + 1]
        if t <= b[1] then
            local k = (t - a[1]) / (b[1] - a[1])
            return a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k, a[4] + (b[4] - a[4]) * k
        end
    end
    return 255, 0, 0
end

local function checkerValue(x, y, cell)
    return (floor(x / cell) + floor(y / cell)) % 2 == 0 and 255 or 204
end

local IMAGES = {
    hue = Png.encode(126, 6, function(x)
        local r, g, b = hueAt((x + 0.5) / 126)
        return round(r), round(g), round(b), 255
    end),
    satWhite = Png.encode(126, 88, function(x)
        return 255, 255, 255, round(255 * (1 - (x + 0.5) / 126))
    end),
    satBlack = Png.encode(126, 88, function(_, y)
        return 0, 0, 0, round(255 * ((y + 0.5) / 88))
    end),
    alphaChecker = Png.encode(126, 6, function(x, y)
        local v = checkerValue(x, y, 3)
        return v, v, v, round(255 * ((x + 0.5) / 126))
    end),
    previewChecker = Png.encode(12, 12, function(x, y)
        local v = checkerValue(x, y, 3)
        return v, v, v, 255
    end),
}

local Render = {
    pools = {},
    objects = {},
    z = Z_BASE,
    alpha = 1,
    clip = nil,
    clipStack = {},
}

local function initSquare(o)
    o.Filled = true
end

local function initText(o)
    o.Font = FONT
    o.Size = FONT_SIZE
    o.Center = false
    o.Outline = false
end

local function initFilled(o)
    o.Filled = true
end

local imageInit = {}
for key, data in pairs(IMAGES) do
    imageInit[key] = function(o)
        o.Data = data
    end
end

function Render.acquire(poolKey, kind, init)
    local pool = Render.pools[poolKey]
    if not pool then
        pool = { n = 0, items = {} }
        Render.pools[poolKey] = pool
    end
    local n = pool.n + 1
    pool.n = n
    local item = pool.items[n]
    if not item then
        local o = Drawing.new(kind)
        o.Visible = false
        if init then
            init(o)
        end
        Render.objects[#Render.objects + 1] = o
        item = { o = o, visible = false }
        pool.items[n] = item
    end
    return item
end

function Render.place(item)
    local z = Render.z + 1
    Render.z = z
    if item.z ~= z then
        item.z = z
        item.o.ZIndex = z
    end
    if not item.visible then
        item.visible = true
        item.o.Visible = true
    end
end

function Render.commit(item, color)
    local ga = Render.alpha
    if ga < 1 then
        local a = color % 256
        color = color - a + floor(a * ga + 0.5)
    end
    if item.color ~= color then
        local r, g, b, a = Util.unpackColor(color)
        local rgbKey = (r * 256 + g) * 256 + b
        if item.rgb ~= rgbKey then
            item.rgb = rgbKey
            item.o.Color = Color3.fromRGB(r, g, b)
        end
        if item.a ~= a then
            item.a = a
            item.o.Transparency = a / 255
        end
        item.color = color
    end
    Render.place(item)
end

function Render.beginFrame()
    for _, pool in pairs(Render.pools) do
        pool.n = 0
    end
    Render.z = Z_BASE
    Render.alpha = 1
    Render.clip = nil
    table.clear(Render.clipStack)
end

function Render.endFrame()
    for _, pool in pairs(Render.pools) do
        local items = pool.items
        for i = pool.n + 1, #items do
            local item = items[i]
            if item.visible then
                item.visible = false
                item.o.Visible = false
            end
        end
    end
end

function Render.pushClip(x0, y0, x1, y1)
    local c = Render.clip
    Render.clipStack[#Render.clipStack + 1] = c or false
    if c then
        x0, y0, x1, y1 = max(x0, c[1]), max(y0, c[2]), min(x1, c[3]), min(y1, c[4])
    end
    Render.clip = { x0, y0, x1, y1 }
end

function Render.popClip()
    local n = #Render.clipStack
    local c = Render.clipStack[n]
    Render.clipStack[n] = nil
    Render.clip = c or nil
end

local function fillRect(x0, y0, x1, y1, color)
    if color % 256 == 0 then
        return
    end
    local c = Render.clip
    if c then
        if x0 < c[1] then
            x0 = c[1]
        end
        if y0 < c[2] then
            y0 = c[2]
        end
        if x1 > c[3] then
            x1 = c[3]
        end
        if y1 > c[4] then
            y1 = c[4]
        end
    end
    x0, y0, x1, y1 = round(x0), round(y0), round(x1), round(y1)
    local w, h = x1 - x0, y1 - y0
    if w <= 0 or h <= 0 then
        return
    end
    local item = Render.acquire("Square", "Square", initSquare)
    if item.x ~= x0 or item.y ~= y0 then
        item.x, item.y = x0, y0
        item.o.Position = vec2(x0, y0)
    end
    if item.w ~= w or item.h ~= h then
        item.w, item.h = w, h
        item.o.Size = vec2(w, h)
    end
    Render.commit(item, color)
end

local function drawText(x, y, s, color, outline, poolKey)
    if s == nil or s == "" or color % 256 == 0 then
        return
    end
    local c = Render.clip
    if c then
        local cy = y + TEXT_H * 0.5
        if cy < c[2] or cy > c[4] or x + textWidth(s) <= c[1] or x >= c[3] then
            return
        end
    end
    x, y = round(x), round(y)
    local item = Render.acquire(poolKey or "Text", "Text", initText)
    if item.x ~= x or item.y ~= y then
        item.x, item.y = x, y
        item.o.Position = vec2(x, y)
    end
    if item.s ~= s then
        item.s = s
        item.o.Text = s
    end
    outline = outline == true
    if item.outline ~= outline then
        item.outline = outline
        item.o.Outline = outline
    end
    Render.commit(item, color)
end

local function alignedText(x, y, w, h, s, color, alignX, alignY, outline)
    if s == nil or s == "" then
        return
    end
    drawText(x + (w - textWidth(s)) * alignX, y + (h - TEXT_H) * alignY, s, color, outline)
end

local GLYPH_LB = "3201013221111211111111111310111011111111211101111110100101212102111111112112011111121101111310"
local GLYPH_RB = "3465663445525255555655555325665666665566446566656666666666454563555555553453655555555565555356"

local function glyphBearings(ch)
    local b = string.byte(ch)
    if b and b >= 33 and b <= 126 then
        local i = b - 32
        return tonumber(string.sub(GLYPH_LB, i, i)) or 1, tonumber(string.sub(GLYPH_RB, i, i)) or 5
    end
    return 1, 5
end

local function inkX(x, s)
    if s == nil or s == "" then
        return x
    end
    local lb = glyphBearings(string.sub(s, 1, 1))
    return x + 1 - lb
end

local function inkWidth(s)
    local lb = glyphBearings(string.sub(s, 1, 1))
    local _, rb = glyphBearings(string.sub(s, -1))
    return textWidth(s) - CHAR_W + rb + 1 - lb, lb
end

local function bracketPulls(inner)
    local lb = glyphBearings(string.sub(inner, 1, 1))
    local _, rb = glyphBearings(string.sub(inner, -1))
    return 2 + lb, 8 - rb
end

local function bracketWidth(prefix, inner)
    local pullOpen, pullClose = bracketPulls(inner)
    return textWidth(prefix) + textWidth(inner) + 2 * CHAR_W - pullOpen - pullClose
end

local function tightAdvance(ch)
    if ch == " " then
        return 3
    end
    local lb, rb = glyphBearings(ch)
    return rb - lb + 2
end

local function tightWidth(s)
    local w = 0
    for i = 1, #s do
        w = w + tightAdvance(string.sub(s, i, i))
    end
    return max(0, w - 1)
end

local function drawTight(x, y, s, color, outline)
    for i = 1, #s do
        local ch = string.sub(s, i, i)
        if ch ~= " " then
            local lb = glyphBearings(ch)
            drawText(x - lb, y, ch, color, outline)
        end
        x = x + tightAdvance(ch)
    end
end

local function drawBracketed(x, y, prefix, open, inner, close, color, outline)
    local pullOpen, pullClose = bracketPulls(inner)
    if prefix ~= "" then
        drawText(x, y, prefix, color, outline)
        x = x + textWidth(prefix)
    end
    drawText(x, y, open, color, outline)
    x = x + CHAR_W - pullOpen
    drawText(x, y, inner, color, outline)
    x = x + textWidth(inner) - pullClose
    drawText(x, y, close, color, outline)
end

local function fillTriangle(ax, ay, bx, by, cx, cy, color)
    if color % 256 == 0 then
        return
    end
    local item = Render.acquire("Triangle", "Triangle", initFilled)
    if item.ax ~= ax or item.ay ~= ay or item.bx ~= bx or item.by ~= by or item.cx ~= cx or item.cy ~= cy then
        item.ax, item.ay, item.bx, item.by, item.cx, item.cy = ax, ay, bx, by, cx, cy
        item.o.PointA = vec2(ax, ay)
        item.o.PointB = vec2(bx, by)
        item.o.PointC = vec2(cx, cy)
    end
    Render.commit(item, color)
end

local function drawImage(key, x, y, w, h, alpha)
    local c = Render.clip
    if c and (x + w <= c[1] or x >= c[3] or y + h <= c[2] or y >= c[4]) then
        return
    end
    local a = floor(clamp((alpha or 1) * Render.alpha, 0, 1) * 255 + 0.5)
    if a <= 0 then
        return
    end
    local item = Render.acquire(key, "Image", imageInit[key])
    x, y = round(x), round(y)
    if item.x ~= x or item.y ~= y then
        item.x, item.y = x, y
        item.o.Position = vec2(x, y)
    end
    if item.w ~= w or item.h ~= h then
        item.w, item.h = w, h
        item.o.Size = vec2(w, h)
    end
    if item.a ~= a then
        item.a = a
        item.o.Transparency = a / 255
    end
    Render.place(item)
end

local function frame(x, y, w, h, bg, border, borderSize)
    if border then
        local b = borderSize or 1
        fillRect(x - b, y - b, x + w + b, y + h + b, border)
    end
    if bg then
        fillRect(x, y, x + w, y + h, bg)
    end
end

local function strokedFrame(x, y, w, h, bg, border, borderSize, stroke)
    local b = borderSize or 1
    fillRect(x - b, y - b, x + w + b, y + h + b, border)
    fillRect(x - 1, y - 1, x + w + 1, y + h + 1, stroke)
    fillRect(x, y, x + w, y + h, bg)
end

local function hgradient(x0, y0, x1, y1, c0, c1, a0, a1, strip)
    strip = strip or 2
    local width = x1 - x0
    if width <= 0 then
        return
    end
    for s = 0, width - 1, strip do
        local e = min(s + strip, width)
        local t = (s + e) * 0.5 / width
        local c = Util.lerpColor(c0, c1, t)
        fillRect(x0 + s, y0, x0 + e, y1, pack(c.R * 255, c.G * 255, c.B * 255, (a0 + (a1 - a0) * t) * 255))
    end
end

local Input = {
    mx = 0,
    my = 0,
    moved = false,
    active = false,
    down = false,
    pressed = false,
    released = false,
    rdown = false,
    rpressed = false,
    rreleased = false,
    mdown = false,
}

local Errors = { last = -100 }

local function reportError(err)
    local now = tick()
    if now - Errors.last > 2 then
        Errors.last = now
        warn("interception: " .. tostring(err))
    end
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(fn)
    local handler = { fn = fn }
    local handlers = self.handlers
    handlers[#handlers + 1] = handler
    local connection = { Connected = true }
    function connection.Disconnect(conn)
        if not conn.Connected then
            return
        end
        conn.Connected = false
        for i = #handlers, 1, -1 do
            if handlers[i] == handler then
                table.remove(handlers, i)
                break
            end
        end
    end
    return connection
end

function Signal:Fire(...)
    local handlers = self.handlers
    local count = #handlers
    if count == 0 then
        return
    end
    local snapshot = {}
    for i = 1, count do
        snapshot[i] = handlers[i]
    end
    for i = 1, count do
        local ok, err = pcall(snapshot[i].fn, ...)
        if not ok then
            reportError(err)
        end
    end
end

local uis = {
    InputBegan = Signal.new(),
    InputEnded = Signal.new(),
    InputChanged = Signal.new(),
}

local function enumItem(enumType, name)
    local ok, item = pcall(function()
        return Enum[enumType][name]
    end)
    if ok and item ~= nil then
        return item
    end
    return nil
end

local UIT = {}
for _, name in ipairs({ "Keyboard", "MouseButton1", "MouseButton2", "MouseButton3", "MouseButton4", "MouseButton5", "MouseMovement" }) do
    UIT[name] = enumItem("UserInputType", name) or ("Enum.UserInputType." .. name)
end
local KEY_UNKNOWN = enumItem("KeyCode", "Unknown") or "Enum.KeyCode.Unknown"
local KEY_ESCAPE = enumItem("KeyCode", "Escape") or "Enum.KeyCode.Escape"
local KEY_BACKSPACE = enumItem("KeyCode", "Backspace") or "Enum.KeyCode.Backspace"

local Keys = { byVk = {}, vkOf = {}, list = {} }

do
    local function bind(name, vk)
        local item = enumItem("KeyCode", name)
        if item ~= nil then
            Keys.byVk[vk] = item
            Keys.vkOf[item] = vk
            Keys.list[#Keys.list + 1] = vk
        end
    end
    for i = 0, 25 do
        bind(string.char(65 + i), 0x41 + i)
    end
    local digits = { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
    for i = 0, 9 do
        bind(digits[i + 1], 0x30 + i)
        bind("Keypad" .. digits[i + 1], 0x60 + i)
    end
    for i = 1, 15 do
        bind("F" .. i, 0x6F + i)
    end
    local other = {
        { "Insert", 0x2D }, { "Delete", 0x2E }, { "Home", 0x24 }, { "End", 0x23 }, { "PageUp", 0x21 }, { "PageDown", 0x22 },
        { "Up", 0x26 }, { "Down", 0x28 }, { "Left", 0x25 }, { "Right", 0x27 }, { "Backspace", 0x08 }, { "Tab", 0x09 },
        { "Return", 0x0D }, { "Escape", 0x1B }, { "Space", 0x20 }, { "LeftShift", 0xA0 }, { "RightShift", 0xA1 },
        { "LeftControl", 0xA2 }, { "RightControl", 0xA3 }, { "LeftAlt", 0xA4 }, { "RightAlt", 0xA5 }, { "CapsLock", 0x14 },
        { "Pause", 0x13 }, { "Print", 0x2C }, { "NumLock", 0x90 }, { "ScrollLock", 0x91 }, { "LeftSuper", 0x5B },
        { "RightSuper", 0x5C }, { "Menu", 0x5D }, { "KeypadMultiply", 0x6A }, { "KeypadPlus", 0x6B },
        { "KeypadMinus", 0x6D }, { "KeypadPeriod", 0x6E }, { "KeypadDivide", 0x6F }, { "Minus", 0xBD },
        { "Equals", 0xBB }, { "LeftBracket", 0xDB }, { "RightBracket", 0xDD }, { "BackSlash", 0xDC },
        { "Semicolon", 0xBA }, { "Quote", 0xDE }, { "Comma", 0xBC }, { "Period", 0xBE }, { "Slash", 0xBF },
        { "Backquote", 0xC0 },
    }
    for _, entry in ipairs(other) do
        bind(entry[1], entry[2])
    end
end

local CHAR_MAP = {}

do
    for i = 0, 25 do
        CHAR_MAP[0x41 + i] = { string.char(97 + i), string.char(65 + i) }
    end
    local shifted = { ")", "!", "@", "#", "$", "%", "^", "&", "*", "(" }
    for i = 0, 9 do
        CHAR_MAP[0x30 + i] = { tostring(i), shifted[i + 1] }
        CHAR_MAP[0x60 + i] = { tostring(i), tostring(i) }
    end
    local symbols = {
        [0x20] = { " ", " " }, [0xBD] = { "-", "_" }, [0xBB] = { "=", "+" }, [0xDB] = { "[", "{" },
        [0xDD] = { "]", "}" }, [0xDC] = { "\\", "|" }, [0xBA] = { ";", ":" }, [0xDE] = { "'", "\"" },
        [0xBC] = { ",", "<" }, [0xBE] = { ".", ">" }, [0xBF] = { "/", "?" }, [0xC0] = { "`", "~" },
        [0x6A] = { "*", "*" }, [0x6B] = { "+", "+" }, [0x6D] = { "-", "-" }, [0x6E] = { ".", "." }, [0x6F] = { "/", "/" },
    }
    for vk, pair in pairs(symbols) do
        CHAR_MAP[vk] = pair
    end
end

local MOUSE_BUTTONS = {
    { vk = 0x01, item = UIT.MouseButton1 },
    { vk = 0x02, item = UIT.MouseButton2 },
    { vk = 0x04, item = UIT.MouseButton3 },
    { vk = 0x05, item = UIT.MouseButton4 },
    { vk = 0x06, item = UIT.MouseButton5 },
}

local Hit = {
    list = {},
    n = 0,
    hover = nil,
    hoverAny = false,
    press = nil,
    rpress = nil,
    drag = nil,
}

local function region(x, y, w, h, owner)
    local x1, y1 = x + w, y + h
    local c = Render.clip
    if c then
        if x < c[1] then
            x = c[1]
        end
        if y < c[2] then
            y = c[2]
        end
        if x1 > c[3] then
            x1 = c[3]
        end
        if y1 > c[4] then
            y1 = c[4]
        end
    end
    if x1 <= x or y1 <= y then
        return
    end
    local n = Hit.n + 1
    Hit.n = n
    local r = Hit.list[n]
    if not r then
        r = {}
        Hit.list[n] = r
    end
    r[1], r[2], r[3], r[4], r[5] = x, y, x1, y1, owner
end

local function hovered(owner)
    return Hit.hover == owner and owner ~= nil
end

local Popups = { n = 0, list = {} }

local function registerPopup(x0, y0, x1, y1, owner, button, close)
    local n = Popups.n + 1
    Popups.n = n
    local p = Popups.list[n]
    if not p then
        p = {}
        Popups.list[n] = p
    end
    p[1], p[2], p[3], p[4] = x0, y0, x1, y1
    p.owner, p.button, p.close = owner, button, close
end

local Focus = { box = nil, blink = 0 }

local function blurBox(enter)
    local box = Focus.box
    if not box then
        return
    end
    Focus.box = nil
    if box.onFocusLost then
        local ok, err = pcall(box.onFocusLost, enter)
        if not ok then
            reportError(err)
        end
    end
end

local function focusBox(box)
    if Focus.box == box then
        return
    end
    blurBox(false)
    Focus.box = box
    Focus.blink = tick()
    if box.clearOnFocus then
        box.setText("")
    end
end

local function typeKey(vk)
    local box = Focus.box
    if not box then
        return
    end
    if vk == 0x08 then
        if #box.text > 0 then
            box.setText(string.sub(box.text, 1, -2))
        end
    elseif vk == 0x0D then
        blurBox(true)
    elseif vk == 0x1B then
        blurBox(false)
    else
        local pair = CHAR_MAP[vk]
        if pair then
            local shift = iskeypressed(0x10) == true
            box.setText(box.text .. (shift and pair[2] or pair[1]))
        end
    end
end

local KeyState = { down = {}, repeatAt = {} }
local MouseState = { down = {} }

local function pollInput(now)
    local active = isrbxactive() == true
    local mx, my = Mouse.X or Input.mx, Mouse.Y or Input.my
    Input.moved = mx ~= Input.mx or my ~= Input.my
    Input.mx, Input.my = mx, my
    Input.active = active
    local down = active and ismouse1pressed() == true
    local rdown = active and ismouse2pressed() == true
    Input.pressed = down and not Input.down
    Input.released = Input.down and not down
    Input.rpressed = rdown and not Input.rdown
    Input.rreleased = Input.rdown and not rdown
    Input.down, Input.rdown = down, rdown
    local position = nil
    local typing = Focus.box ~= nil
    for i = 1, #Keys.list do
        local vk = Keys.list[i]
        local isDown = active and iskeypressed(vk) == true
        local was = KeyState.down[vk] == true
        if isDown ~= was then
            KeyState.down[vk] = isDown
            position = position or vec2(mx, my)
            local input = { UserInputType = UIT.Keyboard, KeyCode = Keys.byVk[vk], Position = position }
            if isDown then
                KeyState.repeatAt[vk] = now + 0.45
                if Focus.box then
                    typeKey(vk)
                end
                uis.InputBegan:Fire(input, typing)
            else
                uis.InputEnded:Fire(input, typing)
            end
        elseif isDown and Focus.box and now >= (KeyState.repeatAt[vk] or math.huge) then
            KeyState.repeatAt[vk] = now + 0.035
            typeKey(vk)
        end
    end
    local overGui = Hit.hoverAny
    for i = 1, #MOUSE_BUTTONS do
        local button = MOUSE_BUTTONS[i]
        local isDown
        if button.vk == 0x01 then
            isDown = down
        elseif button.vk == 0x02 then
            isDown = rdown
        else
            isDown = active and iskeypressed(button.vk) == true
        end
        local was = MouseState.down[button.vk] == true
        if isDown ~= was then
            MouseState.down[button.vk] = isDown
            position = position or vec2(mx, my)
            local input = { UserInputType = button.item, KeyCode = KEY_UNKNOWN, Position = position }
            if isDown then
                uis.InputBegan:Fire(input, overGui)
            else
                uis.InputEnded:Fire(input, overGui)
            end
        end
    end
    if Input.moved then
        uis.InputChanged:Fire({ UserInputType = UIT.MouseMovement, KeyCode = KEY_UNKNOWN, Position = vec2(mx, my) }, false)
    end
end

local function callOwner(owner, name, ...)
    local fn = owner and owner[name]
    if fn then
        local ok, err = pcall(fn, ...)
        if not ok then
            reportError(err)
        end
    end
end

local function resolveHover()
    local mx, my = Input.mx, Input.my
    local list = Hit.list
    for i = Hit.n, 1, -1 do
        local r = list[i]
        if mx >= r[1] and mx < r[3] and my >= r[2] and my < r[4] then
            return r[5]
        end
    end
    return nil
end

local function closePopupsOutside(hover, button)
    local mx, my = Input.mx, Input.my
    local list = Popups.list
    for i = 1, Popups.n do
        local p = list[i]
        local inside = mx >= p[1] and mx < p[3] and my >= p[2] and my < p[4]
        local onOwner = hover ~= nil and hover == p.owner and button == p.button
        if not inside and not onOwner then
            local ok, err = pcall(p.close)
            if not ok then
                reportError(err)
            end
        end
    end
end

local function dispatchMouse()
    local hover = nil
    if Input.active then
        hover = resolveHover()
    end
    Hit.hover = hover
    Hit.hoverAny = hover ~= nil
    if Input.pressed then
        closePopupsOutside(hover, "left")
    end
    if Input.rpressed then
        closePopupsOutside(hover, "right")
    end
    if Input.pressed then
        if Focus.box and (hover == nil or hover ~= Focus.box.owner) then
            blurBox(false)
        end
        Hit.press = hover
        if hover then
            callOwner(hover, "onDown", Input.mx, Input.my)
            if hover.onDragStart then
                Hit.drag = hover
                callOwner(hover, "onDragStart", Input.mx, Input.my)
            end
        end
    end
    local drag = Hit.drag
    if drag then
        if Input.down then
            if Input.moved then
                callOwner(drag, "onDragMove", Input.mx, Input.my)
            end
        else
            Hit.drag = nil
            callOwner(drag, "onDragEnd", Input.mx, Input.my)
        end
    end
    if Input.released then
        local pressed = Hit.press
        Hit.press = nil
        if pressed and pressed == hover then
            callOwner(pressed, "onClick")
        end
    end
    if Input.rpressed then
        Hit.rpress = hover
    end
    if Input.rreleased then
        local pressed = Hit.rpress
        Hit.rpress = nil
        if pressed and pressed == hover then
            callOwner(pressed, "onRightClick")
        end
    end
end

local function tintFor(owner, color, enabled)
    if enabled == false or not owner then
        return color
    end
    if Hit.press == owner and Hit.hover == owner and Input.down then
        local r, g, b, a = Util.unpackColor(color)
        return pack(r * 0.5, g * 0.5, b * 0.5, a)
    end
    if Hit.hover == owner then
        local r, g, b, a = Util.unpackColor(color)
        return pack(r * 0.75, g * 0.75, b * 0.75, a)
    end
    return color
end

local Surfaces = { list = {}, seq = 0 }

local function addSurface(z, draw)
    Surfaces.seq = Surfaces.seq + 1
    local surface = { z = z, seq = Surfaces.seq, draw = draw, removed = false }
    local list = Surfaces.list
    local index = #list + 1
    for i = 1, #list do
        local other = list[i]
        if other.z > z then
            index = i
            break
        end
    end
    table.insert(list, index, surface)
    return surface
end

local function removeSurface(surface)
    surface.removed = true
    local list = Surfaces.list
    for i = #list, 1, -1 do
        if list[i] == surface then
            table.remove(list, i)
            break
        end
    end
end

local Updaters = {}

local function addUpdater(fn)
    Updaters[#Updaters + 1] = fn
    return fn
end

local function removeUpdater(fn)
    for i = #Updaters, 1, -1 do
        if Updaters[i] == fn then
            table.remove(Updaters, i)
        end
    end
end

local function makeDraggable(target)
    local owner = {}
    function owner.onDragStart(mx, my)
        owner.sx, owner.sy = mx, my
        owner.ox, owner.oy = target.x, target.y
    end
    function owner.onDragMove(mx, my)
        target.x = owner.ox + (mx - owner.sx)
        target.y = owner.oy + (my - owner.sy)
    end
    return owner
end

local function makeResizer(target)
    local owner = {}
    function owner.onDragStart(mx, my)
        owner.sx, owner.sy = mx, my
        owner.ow, owner.oh = target.w, target.h
    end
    function owner.onDragMove(mx, my)
        local vw, vh = Util.viewport()
        target.w = clamp(owner.ow + (mx - owner.sx), target.minW, max(target.minW, vw))
        target.h = clamp(owner.oh + (my - owner.sy), target.minH, max(target.minH, vh))
    end
    return owner
end

local function drawFieldText(x, y, w, h, text, placeholder, focused, tight)
    local shown, color = text, COL.text
    if shown == "" and not focused then
        shown, color = placeholder, COL.placeholder
    end
    local measure = tight and tightWidth or textWidth
    local room = w - 8
    while #shown > 0 and measure(shown) > room do
        shown = focused and string.sub(shown, 2) or string.sub(shown, 1, -2)
    end
    local tw = measure(shown)
    local tx = x + round((w - tw) * 0.5)
    local ty = y + (h - TEXT_H) * 0.5
    if tight then
        drawTight(tx, ty, shown, color, true)
    else
        drawText(tx, ty, shown, color, true)
    end
    if focused and (tick() - Focus.blink) % 1 < 0.5 then
        local cx = tx + tw + 1
        fillRect(cx, y + 2, cx + 1, y + h - 2, COL.text)
    end
end

local library = {
    flags = {},
    config_flags = {},
    connections = {},
    notifications = {},
    instances = {},
    main_frame = {},
    config_holder = nil,
    current_tab = nil,
    current_element_open = nil,
    dock_button_holder = nil,
    gui = nil,
    sin = 0,
    keybind_path = nil,
    panel_open = false,
    directory = "Pepsi UI",
    game_name = nil,
    font = nil,
}
library.__index = library

local flags = library.flags
local config_flags = library.config_flags

local themes = {
    preset = {
        ["outline"] = rgb(32, 32, 38),
        ["inline"] = rgb(60, 55, 75),
        ["accent"] = rgb(255, 191, 248),
        ["contrast"] = rgb(35, 35, 47),
        ["text"] = rgb(170, 170, 170),
        ["unselected_text"] = rgb(90, 90, 90),
        ["text_outline"] = rgb(0, 0, 0),
    },
}

local keys = {}

do
    local labels = {
        LeftShift = "LS", RightShift = "RS", LeftControl = "LC", RightControl = "RC", Insert = "INS",
        Backspace = "BS", Return = "Ent", LeftAlt = "LA", RightAlt = "RA", CapsLock = "CAPS", One = "1",
        Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
        Zero = "0", KeypadOne = "Num1", KeypadTwo = "Num2", KeypadThree = "Num3", KeypadFour = "Num4",
        KeypadFive = "Num5", KeypadSix = "Num6", KeypadSeven = "Num7", KeypadEight = "Num8",
        KeypadNine = "Num9", KeypadZero = "Num0", Minus = "-", Equals = "=", Tilde = "~", LeftBracket = "[",
        RightBracket = "]", RightParenthesis = ")", LeftParenthesis = "(", Semicolon = ",", Quote = "'",
        BackSlash = "\\", Comma = ",", Period = ".", Slash = "/", Asterisk = "*", Plus = "+", Backquote = "`",
        Escape = "ESC", Space = "SPC",
    }
    for name, label in pairs(labels) do
        local item = enumItem("KeyCode", name)
        if item ~= nil then
            keys[item] = label
        end
    end
    keys[UIT.MouseButton1] = "MB1"
    keys[UIT.MouseButton2] = "MB2"
    keys[UIT.MouseButton3] = "MB3"
    keys[UIT.MouseButton4] = "X1"
    keys[UIT.MouseButton5] = "X2"
end

local function keyName(key)
    if key == nil then
        return "..."
    end
    local text = tostring(key) ~= "Enums" and (keys[key] or (tostring(key):gsub("Enum.", ""))) or nil
    local result = text and (tostring(text):gsub("KeyCode.", ""):gsub("UserInputType.", ""))
    return result or "..."
end

local function isKeyItem(value)
    return value ~= nil and value ~= "..." and tostring(value):find("Enum") ~= nil
end

local LIST_KEY_NAMES = { MB1 = "M1", MB2 = "M2", MB3 = "M3" }

local function listKeyName(key)
    local name = keyName(key)
    return LIST_KEY_NAMES[name] or name
end

local function capitalize(text)
    return (string.gsub(tostring(text), "^%l", string.upper))
end

pcall(makefolder, library.directory)

function library.to_screen_point(position)
    local cam = workspace.CurrentCamera
    local ok, cf, fov = pcall(function()
        return cam.CFrame, cam.FieldOfView
    end)
    if not ok or not cf or not fov then
        local screen, onScreen = WorldToScreen(position)
        return Vector3.new(screen.X, screen.Y, 0), onScreen
    end
    local d = position - cf.Position
    local rx, ry, depth = d:Dot(cf.RightVector), d:Dot(cf.UpVector), d:Dot(cf.LookVector)
    local vw, vh = Util.viewport()
    local focal = (vh * 0.5) / math.tan(math.rad(fov) * 0.5)
    local sx = vw * 0.5 + (rx / depth) * focal
    local sy = vh * 0.5 - (ry / depth) * focal
    return Vector3.new(sx, sy, depth), depth > 0 and sx >= 0 and sx <= vw and sy >= 0 and sy <= vh
end

function library:convert_string_rgb(str)
    local values = {}
    for value in string.gmatch(str, "[^,]+") do
        table.insert(values, tonumber(value))
    end
    if #values == 4 then
        return values[1], values[2], values[3], values[4]
    else
        library:notification({ text = "Input a correct RGBA value (in the format 255, 255, 255, 0.5)" })
    end
end

function library:connection(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(library.connections, connection)
    return connection
end

function library:animation(text)
    local pattern = {}
    for i = 1, tonumber(text:len()) do
        table.insert(pattern, string.sub(text, 1, i))
    end
    for i = tonumber(text:len()) - 1, 0, -1 do
        table.insert(pattern, string.sub(text, 1, i))
    end
    return pattern
end

function library:convert_enum(enum)
    for _, item in pairs(UIT) do
        if type(item) == "string" and item == enum then
            return item
        end
    end
    local enum_parts = {}
    for part in string.gmatch(enum, "[%w_]+") do
        table.insert(enum_parts, part)
    end
    local enum_table = Enum
    for i = 2, #enum_parts do
        local ok, enum_item = pcall(function()
            return enum_table[enum_parts[i]]
        end)
        if not ok then
            return nil
        end
        enum_table = enum_item
    end
    return enum_table
end

function library:config_folder()
    local game_name = tostring(library.game_name or ""):gsub('[<>:"/\\|%?%*%c]', ""):gsub("^%s+", ""):gsub("[%s%.]+$", "")
    local folder = library.directory .. "/" .. (game_name ~= "" and game_name or "configs")
    if not isfolder(folder) then
        makefolder(folder)
    end
    return folder
end

function library:config_path(name)
    return library:config_folder() .. "/" .. name .. ".cfg"
end

function library:config_list_update()
    if not library.config_holder then
        return
    end
    local list = {}
    for _, file in next, listfiles(library:config_folder()) do
        local normalized = file:gsub("\\", "/")
        local parts = normalized:split("/")
        local filename = parts[#parts]
        if filename:sub(-4) == ".cfg" then
            table.insert(list, filename:sub(1, -5))
        end
    end
    library.config_holder:refresh_options(list)
end

function library:get_config()
    local config = {}
    for i, v in next, flags do
        if type(v) == "table" and v.key then
            config[i] = { active = v.active, mode = v.mode, key = tostring(v.key) }
            if type(v.keys) == "table" then
                config[i].keys = {}
                for n, key in ipairs(v.keys) do
                    config[i].keys[n] = tostring(key)
                end
            end
        elseif type(v) == "table" and v.Transparency and v.Color then
            local color_hex = "ffffff"
            if typeof(v.Color) == "Color3" then
                color_hex = Util.toHex(v.Color)
            end
            config[i] = { Transparency = v.Transparency, Color = color_hex }
        else
            config[i] = v
        end
    end
    if library.layout_snapshot then
        config.__layout = library.layout_snapshot()
    end
    return HttpService:JSONEncode(config)
end

function library:load_config(config_json)
    local success, config = pcall(function()
        return HttpService:JSONDecode(config_json)
    end)
    if not success or type(config) ~= "table" then
        return
    end
    for i, v in next, config do
        local function_set = library.config_flags[i]
        if function_set then
            if type(v) == "table" and v.Transparency and v.Color then
                function_set(Color3.fromHex(v.Color), v.Transparency)
            else
                function_set(v)
            end
        end
    end
    if type(config.__layout) == "table" and library.apply_layout then
        library.apply_layout(config.__layout)
    end
end

function library:round(number, float)
    local multiplier = 1 / (float or 1)
    return math.floor(number * multiplier + 0.5) / multiplier
end

function library:apply_theme() end

function library:update_theme(theme, color)
    themes.preset[theme] = color
end

local function accentColor(alpha)
    return packColor(themes.preset.accent, alpha)
end

local function resizeGrip(rx, ry, owner)
    region(rx - 10, ry - 10, 12, 12, owner)
    local color = Hit.drag == owner and accentColor() or hovered(owner) and grey(170) or grey(110)
    for i = 0, 2 do
        for j = 0, 2 - i do
            fillRect(rx - i * 3 - 2, ry - j * 3 - 2, rx - i * 3, ry - j * 3, color)
        end
    end
end

local POPUP_ROW, POPUP_HEAD = 15, 15

local function popupHeight(rows, title)
    return rows * POPUP_ROW + 2 + (title and POPUP_HEAD + 1 or 0)
end

local function popupChrome(x, y, w, h, title)
    fillRect(x - 1, y - 1, x + w + 1, y + h + 1, COL.c0)
    fillRect(x, y, x + w, y + h, COL.c40)
    fillRect(x + 1, y + 1, x + w - 1, y + h - 1, COL.c19)
    if not title then
        return y + 1
    end
    fillRect(x + 1, y + 1, x + w - 1, y + 1 + POPUP_HEAD, COL.c22)
    alignedText(x, y + 1, w, POPUP_HEAD, title, COL.heading, 0.5, 0.5, true)
    fillRect(x, y + 1 + POPUP_HEAD, x + w, y + 2 + POPUP_HEAD, accentColor())
    return y + 2 + POPUP_HEAD
end

local function popupRow(x, y, w, owner, text, color, enabled)
    region(x + 1, y, w - 2, POPUP_ROW, owner)
    if enabled ~= false and hovered(owner) then
        fillRect(x + 1, y, x + w - 1, y + POPUP_ROW, COL.c33)
    end
    drawText(x + 7, y + 1, text, color, true)
    return y + POPUP_ROW
end

local ColorClipboard = { color = nil, alpha = nil }

local function optionColor(owner, selected, enabled)
    if enabled == false then
        return COL.placeholder
    end
    if selected then
        return accentColor()
    end
    if hovered(owner) then
        return accentColor(140 / 255)
    end
    return COL.text
end

local function closeOpenElement(except)
    local open = library.current_element_open
    if open and open ~= except then
        open.set_visible(false)
        open.open = false
        library.current_element_open = nil
    end
end

local KeybindList = { entries = {}, x = 20, py = nil, visible = true }

function library:new_keybind(properties)
    local cfg = {
        text = properties.name or properties.text or "aimbot",
        key = properties.key or nil,
        mode = properties.mode or "hold",
        _visible = true,
        _listed = properties.listed ~= false,
        _parent = properties.parent,
        _active = false,
        _label = "",
    }
    KeybindList.entries[#KeybindList.entries + 1] = cfg

    function cfg.set_visible(bool)
        cfg._visible = bool and true or false
    end

    function cfg.set_active(bool)
        cfg._active = bool and true or false
    end

    function cfg.change_text(text)
        cfg._label = tostring(text)
        cfg._prefix, cfg._key, cfg._unbound = nil, nil, false
    end

    function cfg.set_parts(name, keyText)
        cfg._prefix = capitalize(name) .. " "
        cfg._key = tostring(keyText)
        cfg._label = cfg._prefix .. "(" .. cfg._key .. ")"
        cfg._unbound = false
    end

    function cfg.update(n_properties)
        if n_properties.keyText then
            cfg.set_parts(n_properties.text, n_properties.keyText)
        elseif n_properties.key == nil or n_properties.key == "..." then
            cfg._prefix, cfg._key = nil, nil
            cfg._label = capitalize(n_properties.text)
            cfg._unbound = true
        else
            cfg.set_parts(n_properties.text, listKeyName(n_properties.key))
        end
    end

    cfg.update(cfg)

    return cfg
end

local function listed(entry)
    return entry._visible and entry._listed and not entry._unbound and (entry._parent == nil or entry._parent.state)
end

local function menuOpen()
    for _, window in ipairs(library.main_frame) do
        if window.visible then
            return true
        end
    end
    return false
end

local function drawKeybindList()
    if not KeybindList.visible then
        return
    end
    local _, vh = Util.viewport()
    local width, count = textWidth("keybinds"), 0
    for _, entry in ipairs(KeybindList.entries) do
        if listed(entry) then
            count = count + 1
            if entry._prefix then
                width = max(width, bracketWidth(entry._prefix, entry._key))
            else
                width = max(width, textWidth(entry._label))
            end
        end
    end
    local empty = count == 0
    if empty then
        if not menuOpen() then
            return
        end
        width, count = max(width, textWidth("none active")), 1
    end
    local w, h = width + 40, count * 14 + 25
    KeybindList.py = KeybindList.py or GUI_INSET + (vh - GUI_INSET) * 0.5
    local x, y = KeybindList.x, KeybindList.py - h * 0.5
    KeybindList.w, KeybindList.h = w, h
    if menuOpen() then
        region(x, y, w, h, KeybindList.drag)
    end
    frame(x, y, w, h, COL.c40, COL.c0)
    fillRect(x, y, x + w, y + 2, accentColor())
    fillRect(x + 2, y + 2, x + w - 2, y + h - 2, COL.c26)
    frame(x + 4, y + 4, w - 8, h - 8, COL.c26, COL.c57)
    local ey = y + 14
    if empty then
        alignedText(x, ey, w, 0, "none active", COL.placeholder, 0.5, 0, true)
    end
    for _, entry in ipairs(KeybindList.entries) do
        if listed(entry) then
            local color = entry._active and accentColor() or COL.text
            if entry._prefix then
                local ew = bracketWidth(entry._prefix, entry._key)
                drawBracketed(x + (w - ew) * 0.5, ey, entry._prefix, "(", entry._key, ")", color, true)
            else
                alignedText(x, ey, w, 0, entry._label, color, 0.5, 0, true)
            end
            ey = ey + 14
        end
    end
    fillRect(x, y + 1, x + w, y + 2, COL.black50)
    alignedText(x, y - 1, w, 1, "keybinds", COL.text, 0.5, 0.5, true)
end

KeybindList.drag = {}
function KeybindList.drag.onDragStart(mx, my)
    KeybindList.drag.sx, KeybindList.drag.sy = mx, my
    KeybindList.drag.ox, KeybindList.drag.oy = KeybindList.x, KeybindList.py
end
function KeybindList.drag.onDragMove(mx, my)
    KeybindList.x = KeybindList.drag.ox + (mx - KeybindList.drag.sx)
    KeybindList.py = KeybindList.drag.oy + (my - KeybindList.drag.sy)
end

local InfoList = { visible = false, x = nil, y = nil, docked = true, title = "info list", lines = {} }

local function drawInfoList()
    if not InfoList.visible then
        return
    end
    local vw, vh = Util.viewport()
    local lineW, rows = 0, 0
    for _, line in ipairs(InfoList.lines) do
        if line.label then
            local head = textWidth(line.label) + 2 * CHAR_W
            lineW = max(lineW, head + textWidth(line.value))
            for _, item in ipairs(line.list) do
                lineW = max(lineW, head + textWidth(item))
            end
            rows = rows + 1 + #line.list
        else
            lineW = max(lineW, textWidth(line.text))
            rows = rows + 1
        end
    end
    local w = max(textWidth(InfoList.title) + 40, lineW + 24)
    local h = rows * 14 + 25
    local win = library.main_frame[1]
    if InfoList.docked and win then
        InfoList.x, InfoList.y = win.x + win.w + 5, win.y
    end
    InfoList.y = InfoList.y or GUI_INSET + (vh - GUI_INSET - h) * 0.5
    InfoList.x = InfoList.x or vw - 20 - w
    local x, y = InfoList.x, InfoList.y
    if menuOpen() then
        region(x, y, w, h, InfoList.drag)
    end
    frame(x, y, w, h, COL.c40, COL.c0)
    fillRect(x, y, x + w, y + 2, accentColor())
    fillRect(x + 2, y + 2, x + w - 2, y + h - 2, COL.c26)
    frame(x + 4, y + 4, w - 8, h - 8, COL.c26, COL.c57)
    local ly = y + 14
    for _, line in ipairs(InfoList.lines) do
        if line.label then
            local head = line.label .. ":"
            local lx = inkX(x + 12, head)
            drawText(lx, ly, head, accentColor(), true)
            local vx = lx + textWidth(head) + CHAR_W
            drawText(vx, ly, line.value, COL.white, true)
            local ink = vx + glyphBearings(string.sub(line.value, 1, 1))
            for _, item in ipairs(line.list) do
                ly = ly + 14
                drawText(inkX(ink - 1, item), ly, item, accentColor(140 / 255), true)
            end
        else
            drawText(inkX(x + 12, line.text), ly, line.text, line.color, true)
        end
        ly = ly + 14
    end
    fillRect(x, y + 1, x + w, y + 2, COL.black50)
    alignedText(x, y - 1, w, 1, InfoList.title, COL.text, 0.5, 0.5, true)
end

InfoList.drag = {}
function InfoList.drag.onDragStart(mx, my)
    InfoList.docked = false
    InfoList.drag.sx, InfoList.drag.sy = mx, my
    InfoList.drag.ox, InfoList.drag.oy = InfoList.x, InfoList.y
end
function InfoList.drag.onDragMove(mx, my)
    InfoList.x = InfoList.drag.ox + (mx - InfoList.drag.sx)
    InfoList.y = InfoList.drag.oy + (my - InfoList.drag.sy)
end

local Layout = { watermarks = {}, previews = {} }

local function finiteNumber(v)
    return type(v) == "number" and v == v and v > -100000 and v < 100000
end

function library.layout_snapshot()
    local _, vh = Util.viewport()
    local windows, watermarks, previews = {}, {}, {}
    for i, win in ipairs(library.main_frame) do
        windows[i] = { w = win.w, h = win.h }
    end
    for i, mark in ipairs(Layout.watermarks) do
        watermarks[i] = { x = mark.x, y = mark.y }
    end
    for i, panel in ipairs(Layout.previews) do
        previews[i] = { x = panel.x, y = panel.y, w = panel.w, h = panel.h }
    end
    return {
        windows = windows,
        watermarks = watermarks,
        previews = previews,
        keybinds = { x = KeybindList.x, y = KeybindList.py or GUI_INSET + (vh - GUI_INSET) * 0.5 },
        info = { x = InfoList.x, y = InfoList.y, docked = InfoList.docked },
    }
end

function library.apply_layout(layout)
    local vw, vh = Util.viewport()
    local function place(target, saved, w, h)
        if type(saved) ~= "table" then
            return
        end
        if finiteNumber(saved.x) then
            target.x = clamp(saved.x, 0, max(0, vw - (w or 40)))
        end
        if finiteNumber(saved.y) then
            target.y = clamp(saved.y, 0, max(0, vh - (h or 20)))
        end
    end
    local function resize(target, saved)
        if target.minW and finiteNumber(saved.w) and finiteNumber(saved.h) then
            target.w = clamp(saved.w, target.minW, max(target.minW, vw))
            target.h = clamp(saved.h, target.minH, max(target.minH, vh))
        end
    end
    for i, saved in ipairs(type(layout.windows) == "table" and layout.windows or {}) do
        local win = library.main_frame[i]
        if win and type(saved) == "table" then
            resize(win, saved)
            win.x = clamp(win.x, 0, max(0, vw - win.w))
            win.y = clamp(win.y, 0, max(0, vh - win.h))
        end
    end
    for i, saved in ipairs(type(layout.watermarks) == "table" and layout.watermarks or {}) do
        if Layout.watermarks[i] then
            place(Layout.watermarks[i], saved, 120, 26)
        end
    end
    for i, saved in ipairs(type(layout.previews) == "table" and layout.previews or {}) do
        local panel = Layout.previews[i]
        if panel and type(saved) == "table" then
            resize(panel, saved)
            place(panel, saved, panel.w, panel.h)
        end
    end
    local keybinds = layout.keybinds
    if type(keybinds) == "table" then
        if finiteNumber(keybinds.x) then
            KeybindList.x = clamp(keybinds.x, 0, max(0, vw - (KeybindList.w or 80)))
        end
        if finiteNumber(keybinds.y) then
            KeybindList.py = clamp(keybinds.y, 0, vh)
        end
    end
    local info = layout.info
    if type(info) == "table" then
        if type(info.docked) == "boolean" then
            InfoList.docked = info.docked
        end
        if not InfoList.docked then
            place(InfoList, info, 120, 60)
        end
    end
end

local Notifications = { inset = 0 }

function library:notification(properties)
    local cfg = {
        time = properties.time or 5,
        text = tostring(properties.text or properties.name or ""),
    }
    local now = tick()
    local noteH = 26
    local function slotY(slot)
        local _, vh = Util.viewport()
        return vh - 20 - noteH - Notifications.inset - slot * (noteH + 4)
    end
    local note = {
        text = cfg.text,
        start = now,
        slot = #library.notifications,
        yFrom = nil,
        yStart = 0,
        removed = false,
    }
    note.y = slotY(note.slot)
    note.w = textWidth(note.text) + 24

    function cfg:refresh_notifications()
        local t = tick()
        for index, other in next, library.notifications do
            other.yFrom = other.y
            other.slot = index - 1
            other.yStart = t
        end
    end

    local function draw()
        local t = tick()
        local age = t - note.start
        local anchor
        local alpha = 1
        local slideIn = min(1, cfg.time)
        if age < slideIn then
            anchor = 1 - Util.quadInOut(age)
        elseif age < cfg.time then
            anchor = 0
        else
            local start = 1 - Util.quadInOut(slideIn)
            local k = Util.quadInOut(clamp(age - cfg.time, 0, 1))
            anchor = start + (1 - start) * k
            alpha = 1 - k
        end
        local target = slotY(note.slot)
        if note.yFrom then
            local k = Util.expoInOut(clamp((t - note.yStart) / 0.3, 0, 1))
            note.y = note.yFrom + (target - note.yFrom) * k
            if k >= 1 then
                note.yFrom = nil
            end
        else
            note.y = target
        end
        local w, h = note.w, noteH
        local x, y = 20 - anchor * (w + 22), note.y
        local remaining = clamp(1 - age / cfg.time, 0, 1)
        Render.alpha = alpha
        frame(x, y, w, h, COL.c40, COL.c0)
        fillRect(x + 2, y + 2, x + w - 2, y + h - 2, COL.c26)
        frame(x + 4, y + 4, w - 8, h - 8, COL.c26, COL.c57)
        drawText(inkX(x + 10, note.text), y + 6, note.text, COL.text, true)
        if remaining > 0 then
            fillRect(x + 4, y + h - 5, x + 4 + (w - 8) * remaining, y + h - 4, accentColor())
        end
        fillRect(x, y, x + w, y + 2, accentColor())
        fillRect(x, y + 1, x + w, y + 2, COL.black50)
        Render.alpha = 1
    end

    note.surface = addSurface(2, draw)
    table.insert(library.notifications, note)

    local updater
    updater = addUpdater(function()
        local age = tick() - note.start
        if not note.removed and age >= cfg.time + 0.1 then
            note.removed = true
            local index = table.find(library.notifications, note)
            if index then
                table.remove(library.notifications, index)
            end
            cfg:refresh_notifications()
        end
        if age >= cfg.time + 0.6 then
            removeSurface(note.surface)
            removeUpdater(updater)
        end
    end)
end

local WATERMARK_ANCHORS = {
    ["top left"] = { 0, 0 },
    ["top center"] = { 0.5, 0 },
    ["top right"] = { 1, 0 },
    ["bottom left"] = { 0, 1 },
    ["bottom center"] = { 0.5, 1 },
    ["bottom right"] = { 1, 1 },
}

function library:window(properties)
    local cfg = {
        name = properties.Name or properties.name or properties.Title or properties.title or "sp4m.wtf",
        size = properties.Size or properties.size or dim2(0, 500, 0, 650),
        game = properties.Game or properties.game,
    }
    library.game_name = cfg.game or library.game_name
    local vw, vh = Util.viewport()
    local watermark = {
        x = 20,
        y = 20,
        visible = true,
        parts = { cfg.name, cfg.game or "Apocalypse Rising 2" },
    }
    local user = tostring(LocalPlayer.Name or "")
    if user ~= "" then
        watermark.parts[3] = user
    end
    watermark.text = table.concat(watermark.parts, " | ")
    watermark.drag = makeDraggable(watermark)
    Layout.watermarks[#Layout.watermarks + 1] = watermark

    addSurface(2, function()
        if not watermark.visible then
            Notifications.inset = 0
            return
        end
        local text = watermark.text
        local lb = glyphBearings(string.sub(text, 1, 1))
        local _, rb = glyphBearings(string.sub(text, -1))
        local w, h = textWidth(text) - CHAR_W + rb + 1 - lb + 20, 26
        local anchor = WATERMARK_ANCHORS[watermark.position]
        if anchor then
            local vw, vh = Util.viewport()
            watermark.x = round(20 + (vw - 40 - w) * anchor[1])
            watermark.y = round(20 + (vh - 40 - h) * anchor[2])
        end
        Notifications.inset = watermark.position == "bottom left" and h + 4 or 0
        local x, y = watermark.x, watermark.y
        if not anchor and menuOpen() then
            region(x, y, w, h, watermark.drag)
        end
        frame(x, y, w, h, COL.c40, COL.c0)
        fillRect(x + 2, y + 2, x + w - 2, y + h - 2, COL.c26)
        frame(x + 4, y + 4, w - 8, h - 8, COL.c26, COL.c57)
        local tx = x + 10 - lb
        for i, part in ipairs(watermark.parts) do
            if i > 1 then
                drawText(tx + CHAR_W, y + 6, "|", COL.placeholder, true, "WatermarkText")
                tx = tx + 3 * CHAR_W
            end
            drawText(tx, y + 6, part, i == 1 and accentColor() or COL.text, true, "WatermarkText")
            tx = tx + textWidth(part)
        end
        fillRect(x, y, x + w, y + 2, accentColor())
        fillRect(x, y + 1, x + w, y + 2, COL.black50)
    end)

    local window = {
        w = Util.resolveAxis(cfg.size, "X", vw, 500),
        h = Util.resolveAxis(cfg.size, "Y", vh - GUI_INSET, 650),
        visible = true,
        tabs = {},
    }
    window.minW, window.minH = window.w, window.h
    window.x = round(vw * 0.5 - window.w * 0.5)
    window.y = round(GUI_INSET + (vh - GUI_INSET) * 0.5 - window.h * 0.5)
    window.drag = makeDraggable(window)
    window.resize = makeResizer(window)
    table.insert(library.main_frame, window)
    cfg._window = window
    cfg.tab_holder = window
    cfg.tab_instance_holder = window

    local espPreview = {
        visible = false,
        w = 328,
        h = 376,
        x = window.x + window.w + 8,
        y = window.y + 1,
        chams = false,
        corner = false,
        box = true,
        bar = true,
        weapon = true,
        icons = true,
        armor = true,
        health = true,
        filler = true,
        names = true,
    }
    espPreview.minW, espPreview.minH = espPreview.w, espPreview.h
    Layout.previews[#Layout.previews + 1] = espPreview
    espPreview.drag = makeDraggable(espPreview)
    espPreview.resize = makeResizer(espPreview)

    local function drawTabs(x, y, w, h)
        local tab = window.current
        if not tab then
            return
        end
        local cx, cy, cw, ch = x + 6, y + 6, w - 12, h - 12
        local colW = (cw - 5) * 0.5
        Render.pushClip(cx, cy, cx + cw, cy + ch)
        tab.left:draw(cx, cy, colW, ch)
        tab.right:draw(cx + colW + 5, cy, colW, ch)
        Render.popClip()
    end

    addSurface(2, function()
        if not window.visible then
            return
        end
        local x, y, w, h = window.x, window.y, window.w, window.h
        region(x, y, w, h, window.drag)
        frame(x, y, w, h, COL.c40, COL.c8)
        fillRect(x + 2, y + 2, x + w - 2, y + h - 2, COL.c26)
        local mx, my, mw, mh = x + 4, y + 4, w - 8, h - 8
        frame(mx, my, mw, mh, COL.c26, COL.c57)
        local tix, tiy, tiw, tih = mx + 15, my + 33, mw - 30, mh - 48
        fillRect(tix, tiy, tix + tiw, tiy + tih, COL.c19)
        frame(tix + 2, tiy + 2, tiw - 4, tih - 4, COL.c22, COL.c56)
        drawTabs(tix + 2, tiy + 2, tiw - 4, tih - 4)
        local count = #window.tabs
        if count > 0 then
            local areaX, areaW = mx + 16, mw - 32
            local bw = (areaW - 6 * (count - 1)) / count
            local by = my + 4
            for i, tab in ipairs(window.tabs) do
                local bx = areaX + (i - 1) * (bw + 6)
                local selected = window.current == tab
                region(bx, by, bw, 22, tab.button)
                alignedText(bx, by, bw, 22, tab.name, packColor(selected and themes.preset.text or themes.preset.unselected_text), 0.5, 0.5, true)
                fillRect(bx, by + 22, bx + bw, by + 24, selected and accentColor() or COL.c57)
                fillRect(bx, by + 23, bx + bw, by + 24, COL.black50)
            end
        end
        fillRect(x, y, x + w, y + 2, accentColor())
        fillRect(x, y + 1, x + w, y + 2, COL.black50)
        alignedText(x, y - 1, w, 1, cfg.name, COL.text, 0.5, 0.5, true)
        resizeGrip(mx + mw - 3, my + mh - 3, window.resize)
    end)

    local HITPART = {
        { -25, 16, 50, 44 },
        { -42, 64, 84, 90 },
        { -86, 64, 40, 90 },
        { 46, 64, 40, 90 },
        { 2, 158, 40, 90 },
        { -42, 158, 40, 90 },
    }

    local function drawEspPreview()
        local p = espPreview
        if not p.visible then
            return
        end
        local x, y, w, h = p.x, p.y, p.w, p.h
        if menuOpen() then
            region(x, y, w, h, p.drag)
        end
        frame(x, y, w, h, grey(56), COL.c8)
        local mx, my, mw, mh = x + 4, y + 4, w - 8, h - 8
        strokedFrame(mx, my, mw, mh, COL.c26, COL.c26, 2, COL.c57)
        local tx, ty, tw, th = mx + 8, my + 8, mw - 16, mh - 16
        strokedFrame(tx, ty, tw, th, COL.c22, COL.c8, 2, COL.c57)
        local hx, hy, hw = tx + 2, ty + 20, tw - 4
        local center = hx + hw * 0.5
        for _, part in ipairs(HITPART) do
            fillRect(center + part[1], hy + part[2], center + part[1] + part[3], hy + part[2] + part[4], p.chams and accentColor() or COL.c38)
        end
        local bx, by = tx + 43, ty + 28
        local bw, bh = tw - 86, th - 106
        if p.filler then
            hgradient(bx, by, bx + bw, by + bh, rgb(0, 0, 0), rgb(255, 0, 0), 0.5, 0.5, 3)
        end
        if p.box and not p.corner then
            local function ring(x0, y0, x1, y1, color)
                fillRect(x0, y0, x1, y0 + 1, color)
                fillRect(x0, y1 - 1, x1, y1, color)
                fillRect(x0, y0 + 1, x0 + 1, y1 - 1, color)
                fillRect(x1 - 1, y0 + 1, x1, y1 - 1, color)
            end
            ring(bx - 2, by - 2, bx + bw + 2, by + bh + 2, COL.c0)
            ring(bx - 1, by - 1, bx + bw + 1, by + bh + 1, COL.white)
            ring(bx, by, bx + bw, by + bh, COL.c0)
        end
        if p.corner then
            local lw, lh = floor(bw * 0.4), floor(bh * 0.3)
            fillRect(bx, by, bx + 1, by + lh, COL.white)
            fillRect(bx, by - 1, bx + lw, by, COL.white)
            fillRect(bx + bw - 1, by, bx + bw, by + lh, COL.white)
            fillRect(bx + bw - lw - 1, by - 1, bx + bw - 1, by, COL.white)
            fillRect(bx, by + bh - lh, bx + 1, by + bh, COL.white)
            fillRect(bx, by + bh - 1, bx + lw, by + bh, COL.white)
            fillRect(bx + bw - 1, by + bh - lh, bx + bw, by + bh, COL.white)
            fillRect(bx + bw - lw - 1, by + bh - 1, bx + bw - 1, by + bh, COL.white)
        end
        if p.health then
            fillRect(bx - 8, by - 2, bx - 4, by + bh + 2, COL.c0)
            fillRect(bx - 7, by - 1, bx - 5, by + bh + 1, pack(0, 255, 42, 255))
        end
        if p.armor then
            fillRect(bx - 14, by - 2, bx - 10, by + bh + 2, COL.c0)
            fillRect(bx - 13, by - 1, bx - 11, by + bh + 1, pack(0, 13, 255, 255))
            alignedText(bx - 14 - 2 - textWidth("100"), by - 2 + (bh + 4) * 0.75 - 2, textWidth("100"), 0, "100", pack(0, 13, 255, 255), 1, 0, true)
        end
        if p.names then
            alignedText(bx - 2, by - 4 - 1 - TEXT_H, bw + 4, TEXT_H, "hello there", COL.white, 0.5, 0, true)
        end
        local bottomY = by + bh + 3 + 1
        if p.bar then
            fillRect(bx - 1, bottomY, bx + bw + 1, bottomY + 4, COL.c0)
            fillRect(bx, bottomY + 1, bx + (bw + 2) * 0.5 - 2, bottomY + 3, pack(0, 255, 238, 255))
            bottomY = bottomY + 4 + 2
        end
        if p.weapon then
            alignedText(bx - 1, bottomY, bw + 2, TEXT_H, "double barrel", COL.white, 0.5, 0, true)
            bottomY = bottomY + TEXT_H + 2
        end
        fillRect(x, y, x + w, y + 2, accentColor())
        fillRect(x, y + 1, x + w, y + 2, COL.black50)
        alignedText(x, y - 1, w, 1, "esp preview", COL.text, 0.5, 0.5, true)
        if menuOpen() then
            resizeGrip(tx + tw - 3, ty + th - 3, p.resize)
        end
    end

    addSurface(1, drawEspPreview)

    if not InfoList.surface then
        InfoList.surface = addSurface(2, drawInfoList)
    end

    if not KeybindList.surface then
        KeybindList.surface = addSurface(2, drawKeybindList)
    end
    library.keybind_path = KeybindList

    function cfg.preview_chams(bool)
        espPreview.chams = bool and true or false
    end

    function cfg.preview_corner_boxes(bool)
        espPreview.corner = bool == "Corner"
        espPreview.box = bool ~= "Corner"
    end

    function cfg.preview_bounding_box(bool)
        espPreview.box = bool and true or false
    end

    function cfg.preview_reload_bar(bool)
        espPreview.bar = bool and true or false
    end

    function cfg.preview_weapon(bool)
        espPreview.weapon = bool and true or false
    end

    function cfg.preview_icons(bool)
        espPreview.icons = bool and true or false
    end

    function cfg.preview_armor(bool)
        espPreview.armor = bool and true or false
    end

    function cfg.preview_health(bool)
        espPreview.health = bool and true or false
    end

    function cfg.preview_filler(bool)
        espPreview.filler = bool and true or false
    end

    function cfg.preview_names(bool)
        espPreview.names = bool and true or false
    end

    function cfg.toggle_esp_preview(bool)
        espPreview.visible = bool and true or false
    end

    function cfg.toggle_list(bool)
        KeybindList.visible = bool and true or false
    end

    function cfg.toggle_info_list(bool)
        InfoList.visible = bool and true or false
    end

    function cfg.set_info(title, lines)
        InfoList.title = tostring(title or "")
        local out = {}
        for _, line in ipairs(lines or {}) do
            if type(line) == "table" and line.label then
                local list = {}
                for _, item in ipairs(line.list or {}) do
                    list[#list + 1] = tostring(item)
                end
                out[#out + 1] = { label = tostring(line.label), value = tostring(line.value or ""), list = list }
            elseif type(line) == "table" then
                out[#out + 1] = { text = tostring(line.text or line[1] or ""), color = line.color and packColor(line.color) or COL.text }
            else
                out[#out + 1] = { text = tostring(line), color = COL.text }
            end
        end
        InfoList.lines = out
    end

    function cfg.toggle_watermark(bool)
        watermark.visible = bool and true or false
    end

    function cfg.set_watermark_position(position)
        watermark.position = position
    end

    function cfg.set_menu_visibility(bool)
        window.visible = bool and true or false
        if not bool then
            closeOpenElement()
        end
    end

    return setmetatable(cfg, library)
end

local Column = {}
Column.__index = Column

function Column.new()
    local column = setmetatable({ items = {}, scroll = 0 }, Column)
    column.owner = {}
    function column.owner.onDragStart(_, my)
        column.owner.sy, column.owner.os = my, column.scroll
    end
    function column.owner.onDragMove(_, my)
        local before = column.scroll
        column.scroll = column.owner.os - (my - column.owner.sy)
        if column.scroll ~= before then
            closeOpenElement()
        end
    end
    return column
end

function Column:draw(x, y, w, h)
    region(x, y, w, h, self.owner)
    local content = 0
    for i, item in ipairs(self.items) do
        content = content + item:height(w) + (i > 1 and 6 or 0)
    end
    content = content + 15
    self.scroll = clamp(self.scroll, 0, max(0, content - h))
    local cy = y - self.scroll
    for _, item in ipairs(self.items) do
        local ih = item:height(w)
        if cy + ih >= y - 40 and cy <= y + h + 40 then
            item:draw(x, cy, w)
        else
            item:skip()
        end
        cy = cy + ih + 6
    end
end

function library:tab(properties)
    local cfg = {
        name = properties.name or "tab",
        enabled = false,
    }
    local window = self._window
    cfg._window = window
    cfg.left = Column.new()
    cfg.right = Column.new()
    cfg.column_holder = cfg

    function cfg.open_tab()
        window.current = cfg
        library.current_tab = { cfg, cfg }
        if library.current_element_open and library.current_element_open ~= cfg then
            closeOpenElement()
        end
    end

    cfg.button = { onClick = cfg.open_tab }
    table.insert(window.tabs, cfg)
    return setmetatable(cfg, library)
end

local Section = {}
Section.__index = Section

function Section:addPage(name)
    local page = { name = name, holder = { items = {} }, owner = {} }
    local index = #self.pages + 1
    page.owner.onClick = function()
        if self.current ~= index then
            self.current = index
            closeOpenElement()
        end
    end
    self.pages[index] = page
    return page
end

function Section:contentHeight(w)
    local total = 0
    local items = self.pages[self.current].holder.items
    for i, item in ipairs(items) do
        total = total + item:height(w - 28) + (i > 1 and 3 or 0)
    end
    return total
end

function Section:height(w)
    return 33 + self:contentHeight(w)
end

function Section:drawTitles(x, y)
    if #self.pages == 1 then
        drawText(x, y, self.name, COL.text, true)
        return
    end
    local tx = x
    for i, page in ipairs(self.pages) do
        if i > 1 then
            tx = tx + 8
        end
        local tw = textWidth(page.name)
        region(tx, y, tw, 12, page.owner)
        local color = COL.text
        if i ~= self.current then
            color = hovered(page.owner) and COL.heading or packColor(themes.preset.unselected_text)
        end
        drawText(tx, y, page.name, color, true)
        tx = tx + tw
    end
end

function Section:draw(x, y, w)
    local h = self:height(w)
    fillRect(x, y + 4, x + w, y + h, COL.c8)
    frame(x + 2, y + 6, w - 4, h - 8, COL.c22, COL.c56)
    local ex, ey, ew = x + 14, y + 18, w - 28
    for i, page in ipairs(self.pages) do
        if i == self.current then
            for _, item in ipairs(page.holder.items) do
                local ih = item:height(ew)
                item:draw(ex, ey, ew)
                ey = ey + ih + 3
            end
        else
            for _, item in ipairs(page.holder.items) do
                item:skip()
            end
        end
    end
    self:drawTitles(x + 8, y + 4 - 6)
end

function Section:skip()
    for _, page in ipairs(self.pages) do
        for _, item in ipairs(page.holder.items) do
            item:skip()
        end
    end
end

function library:section(properties)
    local cfg = {
        name = properties.name or properties.Name or "Section",
        side = properties.side or properties.Side or "left",
    }
    local column = self[cfg.side] or self.left
    local section = setmetatable({ name = cfg.name, pages = {}, current = 1 }, Section)
    section.holder = section:addPage(cfg.name).holder
    table.insert(column.items, section)
    cfg.holder = section.holder
    cfg._section = section
    return setmetatable(cfg, library)
end

function library:subtab(properties)
    local section = self._section
    if not section then
        return nil
    end
    if type(properties) == "string" then
        properties = { name = properties }
    end
    local cfg = {
        name = properties.name or properties.Name or "Page",
        side = self.side,
    }
    cfg.holder = section:addPage(cfg.name).holder
    cfg._section = section
    return setmetatable(cfg, library)
end

local Element = {}
Element.__index = Element

function Element.new(kind)
    return setmetatable({ kind = kind }, Element)
end

function Element:skip()
    if self.onSkip then
        self:onSkip()
    end
end

local function drawRightItems(list, xEnd, y)
    local total = 0
    for i, item in ipairs(list.items) do
        total = total + item:width() + (i > 1 and 3 or 0)
    end
    local x = xEnd - total
    for _, item in ipairs(list.items) do
        local w = item:width()
        item:drawRight(x, y)
        x = x + w + 3
    end
end

local function bottomHeight(list, w)
    local total = 0
    for i, item in ipairs(list.items) do
        total = total + item:barHeight(w) + (i > 1 and 4 or 0)
    end
    return total
end

local function drawBottomItems(list, x, y, w)
    local cy = y
    for _, item in ipairs(list.items) do
        item:drawBar(x, cy, w)
        cy = cy + item:barHeight(w) + 4
    end
end

local function skipList(list)
    for _, item in ipairs(list.items) do
        item:skip()
    end
end

function library:toggle(properties)
    local cfg = {
        enabled = properties.enabled or nil,
        name = properties.name or "Toggle",
        flag = properties.flag or tostring(math.random(1, 9999999)),
        callback = properties.callback or function() end,
        default = properties.default or false,
        previous_holder = self,
    }
    local element = Element.new("toggle")
    element.name = cfg.name
    element.right = { items = {} }
    element.bottom = { items = {} }
    element.state = false
    element.labelOwner = {}
    element.iconOwner = {}

    function element:height(w)
        if #self.bottom.items > 0 then
            return 13 + bottomHeight(self.bottom, w)
        end
        return 12
    end

    function element:draw(x, y, w)
        local rx, rw = x + 13, w - 26
        local h = self:height(w)
        region(rx, y, rw, h, self.labelOwner)
        if #self.bottom.items > 0 then
            drawText(inkX(rx, cfg.name), y, cfg.name, COL.text, true)
        else
            alignedText(inkX(rx, cfg.name), y, rw, 12, cfg.name, COL.text, 0, 0.5, true)
        end
        drawRightItems(self.right, rx + rw + 15, y + 1)
        local ix, iy = rx - 15, y + 1
        region(ix, iy, 10, 10, self.iconOwner)
        fillRect(ix, iy, ix + 10, iy + 10, COL.c8)
        frame(ix + 2, iy + 2, 6, 6, COL.c22, COL.c56)
        if self.state then
            frame(ix + 2, iy + 2, 6, 6, accentColor(), COL.c56)
        end
        drawBottomItems(self.bottom, rx, y + 13, w)
    end

    function element:onSkip()
        skipList(self.right)
        skipList(self.bottom)
    end

    function cfg.set(bool)
        element.state = bool and true or false
        cfg.enabled = element.state
        flags[cfg.flag] = bool
        cfg.callback(bool)
    end

    local function click()
        cfg.enabled = not cfg.enabled
        cfg.set(cfg.enabled)
    end
    element.labelOwner.onClick = click
    element.iconOwner.onClick = click

    table.insert(self.holder.items, element)
    cfg.set(cfg.default)

    self.previous_holder = nil
    self.bottom_holder = element.bottom
    self.right_holder = element.right
    self.bottom_element = element
    cfg.holder = self.holder
    cfg.bottom_holder = element.bottom
    cfg.right_holder = element.right
    cfg.bottom_element = element

    config_flags[cfg.flag] = cfg.set
    return setmetatable(cfg, library)
end

local function namedRow(element, name, x, y, w)
    drawText(inkX(x + 13, name), y, name, COL.text, true)
end

function library:slider(properties)
    local cfg = {
        name = properties.name or nil,
        suffix = properties.suffix or "",
        flag = properties.flag or tostring(2 ^ 789),
        callback = properties.callback or function() end,
        min = properties.min or properties.minimum or 0,
        max = properties.max or properties.maximum or 100,
        intervals = properties.interval or properties.decimal or 1,
        default = properties.default or 10,
        dragging = false,
        value = properties.default or 10,
        previous_holder = self,
    }
    local element = Element.new("slider")
    element.fraction = 0
    element.text = ""
    element.barOwner = {}
    element.addOwner = {}
    element.subOwner = {}

    function element:barHeight()
        return 10
    end

    function element:height(w)
        if cfg.name then
            return 13 + 10
        end
        return 10
    end

    function element:drawBar(x, y, w)
        local sx, sy, sw = x, y + 1, w - 26
        self.trackX, self.trackW = sx + 2, sw - 4
        region(sx, sy, sw, 8, self.barOwner)
        fillRect(sx, sy, sx + sw, sy + 8, COL.c8)
        if cfg.value < cfg.max then
            region(sx + sw + 5, sy - 1, 8, 8, self.addOwner)
            alignedText(sx + sw + 5, sy - 1, 8, 8, "+", COL.text, 0.5, 0.5, true)
        end
        if cfg.value > cfg.min then
            region(sx - 15, sy - 1, 8, 8, self.subOwner)
            alignedText(sx - 15, sy - 1, 8, 8, "-", COL.text, 0.5, 0.5, true)
        end
        frame(sx + 2, sy + 2, sw - 4, 4, COL.c22, COL.c56)
        local fw = sw * self.fraction
        local aw = (sw - 4) * self.fraction
        fillRect(sx, sy, sx + fw, sy + 8, COL.c19)
        frame(sx + 2, sy + 2, aw, 4, accentColor(), COL.fillBorder)
        local tw = textWidth(self.text)
        local lb = glyphBearings(string.sub(self.text, 1, 1))
        local _, rb = glyphBearings(string.sub(self.text, -1))
        local left, right = round(sx) - lb, round(sx + sw) - (tw - CHAR_W + rb + 1)
        drawText(clamp(sx + 2 + aw + 0.5 - tw * 0.5, left, right), sy, self.text, COL.text, true)
    end

    function element:draw(x, y, w)
        if cfg.name then
            namedRow(self, cfg.name, x, y, w)
            self:drawBar(x + 13, y + 13, w)
        else
            self:drawBar(x + 13, y, w)
        end
    end

    function cfg.set(value)
        if type(value) ~= "number" then
            return
        end
        cfg.value = math.clamp(library:round(value, cfg.intervals), cfg.min, cfg.max)
        element.fraction = cfg.max ~= cfg.min and (cfg.value - cfg.min) / (cfg.max - cfg.min) or 0
        element.text = tostring(cfg.value) .. cfg.suffix
        flags[cfg.flag] = cfg.value
        cfg.callback(flags[cfg.flag])
    end

    function element.barOwner.onDragStart()
        cfg.dragging = true
    end

    function element.barOwner.onDragMove(mx)
        if cfg.dragging and element.trackW and element.trackW > 0 then
            local size_x = (mx - element.trackX) / element.trackW
            cfg.set(((cfg.max - cfg.min) * size_x) + cfg.min)
        end
    end

    function element.barOwner.onDragEnd()
        cfg.dragging = false
    end

    function element.addOwner.onDown()
        cfg.value = cfg.value + cfg.intervals
        cfg.set(cfg.value)
    end

    function element.subOwner.onDown()
        cfg.value = cfg.value - cfg.intervals
        cfg.set(cfg.value)
    end

    if cfg.name then
        table.insert(self.holder.items, element)
    else
        table.insert((self.bottom_holder or self.holder).items, element)
    end

    cfg.set(cfg.default)
    config_flags[cfg.flag] = cfg.set
    library.config_flags[cfg.flag] = cfg.set
    return setmetatable(cfg, library)
end

local DROPDOWN_H = 20

function library:dropdown(properties)
    local cfg = {
        name = properties.name or nil,
        flag = properties.flag or tostring(math.random(1, 9999999)),
        items = properties.items or { "1", "2", "3" },
        callback = properties.callback or function() end,
        multi = properties.multi or false,
        open = false,
        option_instances = {},
        multi_items = {},
        previous_holder = self,
    }
    cfg.default = properties.default or (cfg.multi and { cfg.items[1] }) or cfg.items[1] or nil

    local element = Element.new("dropdown")
    element.buttonOwner = {}
    element.text = ""
    element.anchor = { x = 0, y = 0, w = 0 }

    function element:barHeight()
        return DROPDOWN_H
    end

    function element:height()
        if cfg.name then
            return 13 + DROPDOWN_H
        end
        return DROPDOWN_H
    end

    function element:drawBar(x, y, w)
        local dx, dy, dw = x, y, w - 26
        local fh = DROPDOWN_H - 4
        self.anchor.x, self.anchor.y, self.anchor.w = dx, dy, dw
        fillRect(dx, dy, dx + dw, dy + DROPDOWN_H, COL.c8)
        region(dx + 2, dy + 2, dw - 4, fh, self.buttonOwner)
        frame(dx + 2, dy + 2, dw - 4, fh, tintFor(self.buttonOwner, COL.c38), COL.c56)
        local text, color = self.text, COL.text
        if text == "" then
            text, color = "none", COL.placeholder
        end
        local room = dw - 4 - 5 - 14
        if textWidth(text) > room then
            local fit = max(0, floor(room / CHAR_W) - 3)
            text = string.sub(text, 1, fit) .. "..."
        end
        alignedText(dx + 2 + 5, dy + 2, 0, fh, text, color, 0, 0.5, true)
        local iconColor = cfg.open and accentColor() or COL.text
        local ix, iy = dx + dw - 13, dy + DROPDOWN_H / 2
        if cfg.multi then
            fillRect(ix, iy - 2, ix + 5, iy - 1, iconColor)
            fillRect(ix, iy, ix + 5, iy + 1, iconColor)
            fillRect(ix, iy + 2, ix + 5, iy + 3, iconColor)
        else
            fillRect(ix, iy, ix + 5, iy + 1, iconColor)
        end
    end

    function element:draw(x, y, w)
        if cfg.name then
            namedRow(self, cfg.name, x, y, w)
            self:drawBar(x + 13, y + 13, w)
        else
            self:drawBar(x + 13, y, w)
        end
    end

    local options = {}

    local function closeList()
        if cfg.open then
            cfg.set_visible(false)
            cfg.open = false
        end
        if library.current_element_open == cfg then
            library.current_element_open = nil
        end
    end

    local function drawList()
        if not cfg.open then
            return
        end
        local a = element.anchor
        local x, y, w = a.x, a.y + DROPDOWN_H + 2, a.w
        local h = popupHeight(#options)
        registerPopup(x, y, x + w, y + h, element.buttonOwner, "left", closeList)
        local oy = popupChrome(x, y, w, h)
        for _, option in ipairs(options) do
            oy = popupRow(x, oy, w, option.owner, option.text, optionColor(option.owner, option.selected))
        end
    end

    addSurface(5, drawList)

    function cfg.set_visible(bool)
        cfg.open = bool and true or false
        if bool then
            if library.current_element_open and library.current_element_open ~= cfg then
                library.current_element_open.set_visible(false)
                library.current_element_open.open = false
            end
            library.current_element_open = cfg
        end
    end

    function cfg.set(value)
        local selected = {}
        local is_table = type(value) == "table"
        for _, option in next, options do
            local match = false
            if is_table then
                for _, val in next, value do
                    if option.text == tostring(val) then
                        match = true
                        break
                    end
                end
            elseif option.text == tostring(value) then
                match = true
            end
            option.selected = match
            if match then
                table.insert(selected, option.text)
            end
        end
        cfg.multi_items = selected
        element.text = table.concat(selected, ", ")
        flags[cfg.flag] = cfg.multi and selected or selected[1]
        cfg.callback(flags[cfg.flag])
    end

    function cfg:refresh_options(refreshed_list)
        table.clear(options)
        cfg.option_instances = options
        cfg.items = refreshed_list
        for _, v in next, refreshed_list do
            local option = { text = tostring(v), selected = false, owner = {} }
            option.owner.onDown = function()
                if cfg.multi then
                    local selected_index = table.find(cfg.multi_items, option.text)
                    if selected_index then
                        table.remove(cfg.multi_items, selected_index)
                    else
                        table.insert(cfg.multi_items, option.text)
                    end
                    cfg.set(cfg.multi_items)
                else
                    cfg.set(option.text)
                    cfg.set_visible(false)
                    cfg.open = false
                end
            end
            table.insert(options, option)
        end
    end

    function cfg:list(new_list)
        cfg:refresh_options(new_list)
        local current = flags[cfg.flag]
        if current then
            cfg.set(current)
        end
    end

    element.buttonOwner.onClick = function()
        cfg.open = not cfg.open
        cfg.set_visible(cfg.open)
    end

    if cfg.name then
        table.insert(self.holder.items, element)
    else
        table.insert((self.bottom_holder or self.holder).items, element)
    end

    cfg:refresh_options(cfg.items)
    cfg.set(cfg.default)
    library.config_flags[cfg.flag] = cfg.set
    return setmetatable(cfg, library)
end

function library:colorpicker(properties)
    local cfg = {
        name = properties.name or nil,
        flag = properties.flag or tostring(2 ^ 789),
        color = properties.color or properties.default or Color3.new(1, 1, 1),
        alpha = properties.alpha or 1,
        callback = properties.callback or function() end,
        right_holder = self.right_holder or nil,
        holder = self.holder or nil,
        open = false,
    }
    flags[cfg.flag] = {}

    local dragging_sat, dragging_hue, dragging_alpha = false, false, false
    local h, s, v = Util.toHSV(cfg.color)
    local a = cfg.alpha
    local menuOpen = false
    local inputText = ""

    local element = Element.new("colorpicker")
    element.iconOwner = {}
    element.anchor = { x = 0, y = 0 }
    element.pickerPos = { x = 0, y = 0 }
    element.menuPos = { x = 0, y = 0 }
    element.color = cfg.color

    local satOwner, hueOwner, alphaOwner = {}, {}, {}
    local inputBox = { text = "", clearOnFocus = false, owner = {} }

    function element:width()
        return 16
    end

    function element:drawRight(x, y)
        self.anchor.x, self.anchor.y = x, y
        local c = self.color
        region(x, y, 16, 10, self.iconOwner)
        fillRect(x, y, x + 16, y + 10, COL.c0)
        frame(x + 2, y + 2, 12, 6, packColor(c), pack(floor(c.R * 255 + 0.5) / 2, floor(c.G * 255 + 0.5) / 2, floor(c.B * 255 + 0.5) / 2, 255))
    end

    function element:height()
        return 12
    end

    function element:draw(x, y, w)
        namedRow(self, cfg.name, x, y, w)
        self:drawRight(x + 13 + (w - 26) + 15 - 16, y + 1)
    end

    local function updatePositions()
        element.pickerPos.x, element.pickerPos.y = element.anchor.x + 1, element.anchor.y + 17
        element.menuPos.x, element.menuPos.y = element.anchor.x + 20, element.anchor.y
    end

    function cfg.set_visible(bool)
        cfg.open = bool and true or false
        menuOpen = false
        if bool then
            if library.current_element_open and library.current_element_open ~= cfg then
                library.current_element_open.set_visible(false)
                library.current_element_open.open = false
            end
            library.current_element_open = cfg
        end
        updatePositions()
    end

    element.iconOwner.onClick = function()
        cfg.open = not cfg.open
        cfg.set_visible(cfg.open)
    end

    element.iconOwner.onRightClick = function()
        if cfg.open then
            cfg.open = false
            cfg.set_visible(false)
        end
        menuOpen = not menuOpen
        updatePositions()
    end

    function cfg.set(color, alpha)
        if color then
            h, s, v = Util.toHSV(color)
        end
        if alpha then
            a = alpha
        end
        local Color = hsv(h, s, v)
        element.color = Color
        inputText = math.floor(Color.R * 255) .. ", " .. math.floor(Color.G * 255) .. ", " .. math.floor(Color.B * 255) .. ", " .. library:round(a, 0.01)
        if Focus.box ~= inputBox then
            inputBox.text = inputText
        end
        cfg.color = Color
        cfg.alpha = a
        flags[cfg.flag] = {
            Color = Color,
            Transparency = a,
        }
        cfg.callback(Color, a)
    end

    function inputBox.setText(text)
        inputBox.text = text
    end

    function inputBox.onFocusLost()
        local r, g, b, alpha = library:convert_string_rgb(inputBox.text)
        if r and g and b and alpha then
            cfg.set(rgb(r, g, b), alpha)
        else
            inputBox.text = inputText
        end
    end

    inputBox.owner.onDown = function()
        focusBox(inputBox)
    end

    function cfg.update_color(mx, my)
        local p = element.pickerPos
        local px, py = p.x + 2, p.y + 2
        if dragging_sat then
            local sx, sy = px + 4 + 2, py + 4 + 2
            s = math.clamp((mx - sx) / 126, 0, 1)
            v = 1 - math.clamp((my - sy) / 88, 0, 1)
        elseif dragging_hue then
            h = math.clamp((mx - (px + 4)) / 130, 0, 1)
        elseif dragging_alpha then
            a = math.clamp((mx - (px + 4)) / 130, 0, 1)
        end
        cfg.set(nil, nil)
    end

    satOwner.onDragStart = function()
        dragging_sat = true
    end
    hueOwner.onDragStart = function()
        dragging_hue = true
    end
    alphaOwner.onDragStart = function()
        dragging_alpha = true
    end
    local function stopDrag()
        dragging_sat, dragging_hue, dragging_alpha = false, false, false
    end
    satOwner.onDragEnd, hueOwner.onDragEnd, alphaOwner.onDragEnd = stopDrag, stopDrag, stopDrag
    local function dragMove(mx, my)
        cfg.update_color(mx, my)
    end
    satOwner.onDragMove, hueOwner.onDragMove, alphaOwner.onDragMove = dragMove, dragMove, dragMove

    local menuOptions = {
        { text = "copy", owner = {} },
        { text = "paste", owner = {} },
    }

    menuOptions[1].owner.onClick = function()
        ColorClipboard.color, ColorClipboard.alpha = cfg.color, cfg.alpha
        menuOpen = false
    end

    menuOptions[2].owner.onClick = function()
        if ColorClipboard.color then
            cfg.set(ColorClipboard.color, ColorClipboard.alpha)
            menuOpen = false
        end
    end

    local function closeMenu()
        menuOpen = false
    end

    local function closePicker()
        if cfg.open then
            cfg.set_visible(false)
            cfg.open = false
        end
        if library.current_element_open == cfg then
            library.current_element_open = nil
        end
    end

    addSurface(2, function()
        if not menuOpen then
            return
        end
        local x, y, w = element.menuPos.x, element.menuPos.y, 73
        local hgt = popupHeight(#menuOptions, "color")
        registerPopup(x, y, x + w, y + hgt, element.iconOwner, "right", closeMenu)
        local oy = popupChrome(x, y, w, hgt, "color")
        for i, option in ipairs(menuOptions) do
            local enabled = i == 1 or ColorClipboard.color ~= nil
            oy = popupRow(x, oy, w, option.owner, option.text, optionColor(option.owner, false, enabled), enabled)
        end
    end)

    addSurface(9999, function()
        if not cfg.open then
            return
        end
        local x, y = element.pickerPos.x, element.pickerPos.y
        local Color = element.color
        registerPopup(x, y, x + 142, y + 146, element.iconOwner, "left", closePicker)
        popupChrome(x, y, 142, 146)
        local px, py = x + 2, y + 2
        region(px + 4, py + 4, 130, 92, satOwner)
        fillRect(px + 4, py + 4, px + 134, py + 96, COL.c8)
        local sx, sy = px + 6, py + 6
        frame(sx, sy, 126, 88, packColor(hsv(h, 1, 1)), COL.c56)
        drawImage("satWhite", sx, sy, 126, 88, 1)
        drawImage("satBlack", sx, sy, 126, 88, 1)
        local cxp = round(sx + clamp(126 * s, 0, 125))
        local cyp = round(sy + clamp(88 * (1 - v), 0, 87))
        fillRect(cxp - 4, cyp - 1, cxp + 5, cyp + 2, COL.c0)
        fillRect(cxp - 1, cyp - 4, cxp + 2, cyp + 5, COL.c0)
        fillRect(cxp - 3, cyp, cxp + 4, cyp + 1, COL.white)
        fillRect(cxp, cyp - 3, cxp + 1, cyp + 4, COL.white)
        region(px + 4, py + 98, 130, 10, hueOwner)
        fillRect(px + 4, py + 98, px + 134, py + 108, COL.c8)
        frame(px + 6, py + 100, 126, 6, COL.white, COL.c56)
        drawImage("hue", px + 6, py + 100, 126, 6, 1)
        local hx = px + 6 + 126 * h + (h < 1 and 0 or -4)
        frame(hx, py + 100, 1, 6, COL.marker, COL.c0)
        region(px + 4, py + 110, 130, 10, alphaOwner)
        fillRect(px + 4, py + 110, px + 134, py + 120, COL.c8)
        frame(px + 6, py + 112, 126, 6, packColor(Color), COL.c56)
        drawImage("alphaChecker", px + 6, py + 112, 126, 6, 1)
        local ax = px + 6 + 126 * a + (a < 1 and 0 or -4)
        frame(ax, py + 112, 1, 6, COL.marker, COL.c0)
        fillRect(px + 4, py + 122, px + 4 + 112, py + 138, COL.c8)
        region(px + 6, py + 124, 108, 12, inputBox.owner)
        frame(px + 6, py + 124, 108, 12, COL.c38, COL.c56)
        drawFieldText(px + 6, py + 124, 108, 12, inputBox.text, "r, g, b, a", Focus.box == inputBox, true)
        fillRect(px + 118, py + 122, px + 134, py + 138, grey(35))
        frame(px + 120, py + 124, 12, 12, packColor(Color), COL.c0)
        drawImage("previewChecker", px + 120, py + 124, 12, 12, a)
    end)

    if cfg.name then
        table.insert(self.holder.items, element)
    else
        local holder = self.right_holder
        if holder then
            table.insert(holder.items, element)
        else
            element.drawRightOnly = true
            table.insert(self.holder.items, element)
        end
    end

    cfg.set(cfg.color, cfg.alpha)
    library.config_flags[cfg.flag] = cfg.set
    return setmetatable(cfg, library)
end

function library:keybind(properties)
    local cfg = {
        flag = properties.flag or tostring(2 ^ math.random(1, 30) * 3),
        keybind_name = properties.keybind_name or nil,
        callback = properties.callback or function() end,
        open = false,
        binding = nil,
        name = properties.name or nil,
        key = properties.default or properties.key or nil,
        mode = properties.mode or "toggle",
        active = properties.default or false,
        display = properties.displayName or properties.display or properties.name or (self.bottom_element and self.bottom_element.name) or nil,
        hold_instances = {},
    }
    flags[cfg.flag] = {}

    local function normalize(value)
        if type(value) == "string" and value ~= "..." then
            value = library:convert_enum(value)
        end
        if value == nil or value == false or value == KEY_ESCAPE then
            return "..."
        end
        return value
    end

    local slots = {}
    local given = type(properties.keys) == "table" and #properties.keys > 0 and properties.keys or { cfg.key or "..." }
    for i = 1, #given do
        slots[i] = { key = normalize(given[i]), owner = {}, held = false, x = 0 }
    end
    local multi = #slots > 1

    local function bound(slot)
        return slot.key ~= nil and slot.key ~= "..."
    end

    local function unbound()
        for _, slot in ipairs(slots) do
            if bound(slot) then
                return false
            end
        end
        return true
    end

    local function anyHeld()
        for _, slot in ipairs(slots) do
            if slot.held and bound(slot) then
                return true
            end
        end
        return false
    end

    local function firstKey()
        for _, slot in ipairs(slots) do
            if bound(slot) then
                return slot.key
            end
        end
        return "..."
    end

    local function listText()
        local parts = {}
        for _, slot in ipairs(slots) do
            if bound(slot) then
                parts[#parts + 1] = listKeyName(slot.key)
            end
        end
        return #parts > 0 and table.concat(parts, ", ") or nil
    end

    local function publish()
        local value = { mode = cfg.mode, key = cfg.key, active = cfg.active }
        if multi then
            value.keys = {}
            for i, slot in ipairs(slots) do
                value.keys[i] = slot.key
            end
        end
        flags[cfg.flag] = value
    end

    cfg.key = firstKey()

    local key = library:new_keybind({
        text = cfg.display,
        key = cfg.key,
        mode = cfg.mode,
        listed = properties.show_in_list ~= false,
        parent = not cfg.name and self.right_holder and self.bottom_element or nil,
    })

    local element = Element.new("keybind")
    element.anchor = { x = 0, y = 0 }
    local captureSlot = nil

    local KEY_PAD = 3

    local function slotWidth(slot)
        if slot.inner then
            return inkWidth("[") + KEY_PAD + inkWidth(slot.inner) + KEY_PAD + inkWidth("]") + 1
        end
        return max(16, textWidth(slot.text or "..."))
    end

    function element:width()
        local total = 0
        for i, slot in ipairs(slots) do
            total = total + slotWidth(slot) + (i > 1 and 3 or 0)
        end
        return total
    end

    function element:drawRight(x, y)
        self.anchor.x, self.anchor.y = x, y
        for _, slot in ipairs(slots) do
            local w = slotWidth(slot)
            slot.x = x
            region(x, y, w, 12, slot.owner)
            if slot.inner then
                local ty = y + (12 - TEXT_H) * 0.5
                local openW, openLb = inkWidth("[")
                local innerW, innerLb = inkWidth(slot.inner)
                local _, closeLb = inkWidth("]")
                local ix = x + openW + KEY_PAD
                drawText(x - openLb, ty, "[", COL.text, true)
                drawText(ix - innerLb, ty, slot.inner, slot.unbound and COL.placeholder or COL.text, true)
                drawText(ix + innerW + KEY_PAD - closeLb, ty, "]", COL.text, true)
            else
                alignedText(x, y, w, 12, slot.text or "...", COL.text, 0.5, 0.5, true)
            end
            x = x + w + 3
        end
    end

    function element:height()
        return 12
    end

    function element:draw(x, y, w)
        namedRow(self, cfg.name, x, y, w)
        local width = self:width()
        self:drawRight(x + 13 + (w - 26) + 15 - width, y + 1)
    end

    local modeOptions = {}

    local function updateList()
        key.update({ text = cfg.display, key = cfg.key, mode = cfg.mode, keyText = multi and listText() or nil })
    end

    function cfg.set_display(text)
        cfg.display = text
        updateList()
    end

    function cfg.set_visible(bool)
        cfg.open = bool and true or false
        if bool then
            if library.current_element_open and library.current_element_open ~= cfg then
                library.current_element_open.set_visible(false)
                library.current_element_open.open = false
            end
            library.current_element_open = cfg
        end
    end

    function cfg.set_mode(mode)
        cfg.mode = mode
        if mode == "always" then
            cfg.set(true)
        elseif mode == "hold" then
            cfg.set(false)
        end
        publish()
    end

    local function showKey()
        cfg.key = firstKey()
        cfg.key_name = keyName(cfg.key)
        for _, slot in ipairs(slots) do
            if bound(slot) then
                slot.inner = string.lower(keyName(slot.key))
                slot.text, slot.unbound = "[" .. slot.inner .. "]", false
            else
                slot.text, slot.inner, slot.unbound = "[none]", "none", true
            end
        end
    end

    function cfg.set(input, index)
        if type(input) == "boolean" then
            local cached = input
            if cfg.mode == "always" or unbound() then
                cached = true
            end
            cfg.active = cached
            publish()
            key.set_active(cached and true or false)
            cfg.callback(cached)
        elseif isKeyItem(input) then
            if input == KEY_ESCAPE or input == KEY_BACKSPACE then
                input = "..."
            end
            local slot = slots[index or 1] or slots[1]
            slot.key = input or "..."
            slot.held = false
            showKey()
            if unbound() then
                cfg.active = true
            elseif cfg.mode == "hold" then
                cfg.active = anyHeld()
            end
            publish()
            updateList()
            cfg.callback(cfg.active or false)
        elseif input == "toggle" or input == "hold" or input == "always" then
            cfg.set_mode(input)
            if input == "always" then
                cfg.active = true
            end
            publish()
            cfg.callback(cfg.active or false)
        elseif type(input) == "table" then
            if multi and type(input.keys) == "table" then
                for i, slot in ipairs(slots) do
                    slot.key = normalize(input.keys[i])
                    slot.held = false
                end
            else
                local newKey = normalize(input.key)
                local present = false
                for _, slot in ipairs(slots) do
                    if slot.key == newKey then
                        present = true
                    end
                end
                if not multi or (newKey ~= "..." and not present) then
                    slots[1].key = newKey
                    slots[1].held = false
                end
            end
            cfg.mode = input.mode or "toggle"
            if input.active then
                cfg.active = input.active
            end
            if unbound() then
                cfg.active = true
            end
            showKey()
            publish()
            updateList()
        end
        if cfg.keybind_name then
            key.set_parts(cfg.keybind_name, multi and listText() or listKeyName(cfg.key))
            key.set_visible(cfg.active and true or false)
        end
        key.set_active(cfg.active and true or false)
    end

    for _, entry in ipairs({ { "press", "toggle" }, { "hold", "hold" } }) do
        local option = { text = entry[1], mode = entry[2], owner = {} }
        option.owner.onClick = function()
            cfg.set_mode(option.mode)
            cfg.set_visible(false)
            cfg.open = false
            updateList()
        end
        modeOptions[#modeOptions + 1] = option
    end

    local function closeModes()
        if cfg.open then
            cfg.set_visible(false)
            cfg.open = false
        end
        if library.current_element_open == cfg then
            library.current_element_open = nil
        end
    end

    addSurface(2, function()
        if not cfg.open then
            return
        end
        local opener = cfg.popupSlot or slots[1]
        local x, y, w = opener.x, element.anchor.y + 15, 57
        local hgt = popupHeight(#modeOptions, "mode")
        registerPopup(x, y, x + w, y + hgt, opener.owner, "right", closeModes)
        local oy = popupChrome(x, y, w, hgt, "mode")
        for _, option in ipairs(modeOptions) do
            oy = popupRow(x, oy, w, option.owner, option.text, optionColor(option.owner, cfg.mode == option.mode))
        end
    end)

    for i, slot in ipairs(slots) do
        slot.owner.onRightClick = function()
            cfg.popupSlot = slot
            cfg.open = not cfg.open
            cfg.set_visible(cfg.open)
        end
        slot.owner.onDown = function()
            captureSlot = i
        end
    end

    addUpdater(function()
        if captureSlot then
            local index = captureSlot
            captureSlot = nil
            showKey()
            local slot = slots[index]
            slot.text, slot.inner = "...", nil
            if cfg.binding then
                cfg.binding:Disconnect()
            end
            cfg.binding = library:connection(uis.InputBegan, function(input)
                local captured
                if input.UserInputType == UIT.Keyboard then
                    captured = input.KeyCode
                elseif input.UserInputType == UIT.MouseButton1 or input.UserInputType == UIT.MouseButton2 or input.UserInputType == UIT.MouseButton3 or input.UserInputType == UIT.MouseButton4 or input.UserInputType == UIT.MouseButton5 then
                    captured = input.UserInputType
                else
                    return
                end
                if cfg.binding then
                    cfg.binding:Disconnect()
                    cfg.binding = nil
                end
                cfg.set(captured, index)
                updateList()
            end)
        end
    end)

    local function pressedKey(input)
        return input.UserInputType == UIT.Keyboard and input.KeyCode or input.UserInputType
    end

    library:connection(uis.InputBegan, function(input, game_event)
        if game_event or cfg.binding then
            return
        end
        local selected_key = pressedKey(input)
        local matched = false
        for _, slot in ipairs(slots) do
            if bound(slot) and selected_key == slot.key then
                slot.held = true
                matched = true
            end
        end
        if matched then
            if cfg.mode == "toggle" then
                cfg.set(not cfg.active)
            elseif cfg.mode == "hold" then
                cfg.set(true)
            end
        end
    end)

    library:connection(uis.InputEnded, function(input)
        local selected_key = pressedKey(input)
        local matched = false
        for _, slot in ipairs(slots) do
            if bound(slot) and selected_key == slot.key then
                slot.held = false
                matched = true
            end
        end
        if matched and cfg.mode == "hold" and not anyHeld() then
            cfg.set(false)
        end
    end)

    if cfg.name then
        table.insert(self.holder.items, element)
    else
        local holder = self.right_holder
        if holder then
            table.insert(holder.items, element)
        else
            table.insert(self.holder.items, element)
        end
    end

    cfg.set({ mode = cfg.mode, active = cfg.active, key = cfg.key })
    updateList()
    library.config_flags[cfg.flag] = cfg.set
    return setmetatable(cfg, library)
end

function library:button(properties)
    local cfg = {
        callback = properties.callback or function() end,
        name = properties.text or properties.name or "Button",
        confirm = properties.confirm or false,
    }
    local element = Element.new("button")
    element.owner = {}
    local armedAt = nil
    element.owner.onClick = function()
        if cfg.confirm and not (armedAt and tick() - armedAt < 3) then
            armedAt = tick()
            return
        end
        armedAt = nil
        cfg.callback()
    end

    function element:height()
        return 16
    end

    function element:draw(x, y, w)
        local bx, bw = x + 13, w - 26
        fillRect(bx, y, bx + bw, y + 16, COL.c8)
        region(bx + 2, y + 2, bw - 4, 12, self.owner)
        frame(bx + 2, y + 2, bw - 4, 12, tintFor(self.owner, COL.c38), COL.c56)
        local label = cfg.name
        if armedAt then
            local left = 3 - (tick() - armedAt)
            if left > 0 then
                label = "confirm " .. math.ceil(left)
            else
                armedAt = nil
            end
        end
        alignedText(bx + 2, y + 2, bw - 4, 12, label, COL.text, 0.5, 0.5, true)
    end

    table.insert(self.holder.items, element)
    return setmetatable(cfg, library)
end

function library:textbox(properties)
    local cfg = {
        placeholder = properties.placeholder or properties.placeholdertext or properties.holder or properties.holdertext or "type here...",
        default = properties.default,
        clear_on_focus = properties.clearonfocus or false,
        flag = properties.flag or "...",
        callback = properties.callback or function() end,
    }
    local box = { text = "", clearOnFocus = cfg.clear_on_focus, owner = {} }

    function box.setText(text)
        text = tostring(text)
        if box.text == text then
            return
        end
        box.text = text
        flags[cfg.flag] = text
        local ok, err = pcall(cfg.callback, text)
        if not ok then
            reportError(err)
        end
    end

    box.owner.onDown = function()
        focusBox(box)
    end

    local element = Element.new("textbox")

    function element:height()
        return 16
    end

    function element:draw(x, y, w)
        local bx, bw = x + 13, w - 26
        fillRect(bx, y, bx + bw, y + 16, COL.c8)
        region(bx + 2, y + 2, bw - 4, 12, box.owner)
        frame(bx + 2, y + 2, bw - 4, 12, COL.c38, COL.c56)
        drawFieldText(bx + 2, y + 2, bw - 4, 12, box.text, cfg.placeholder, Focus.box == box, false)
    end

    function cfg.set(text)
        flags[cfg.flag] = text
        box.text = tostring(text)
        cfg.callback(text)
    end

    table.insert(self.holder.items, element)
    if cfg.default then
        cfg.set(cfg.default)
    end
    library.config_flags[cfg.flag] = cfg.set
    return setmetatable(cfg, library)
end

function library:panel(properties)
    if library.__panel == true then
        return
    end
    library.__panel = true
    local cfg = {
        name = properties.name or "Are you sure?",
        options = properties.options or { "Confirm", "Discard" },
        callback = properties.callback or function() end,
    }
    local surface
    local buttons = {}
    local blocker = {}
    for _, option in next, cfg.options do
        local button = { text = tostring(option), owner = {} }
        button.owner.onClick = function()
            removeSurface(surface)
            library.__panel = false
            cfg.callback(option)
        end
        buttons[#buttons + 1] = button
    end
    surface = addSurface(3, function()
        local vw, vh = Util.viewport()
        region(0, GUI_INSET, vw, vh - GUI_INSET, blocker)
        fillRect(0, GUI_INSET, vw, vh, grey(0, 153))
        local contentW = max(textWidth(cfg.name), 130) + 40
        local contentH = 5 + 6 + 11 + 4 + (#buttons * 16 + max(0, #buttons - 1) * 3) + 22
        local tabsW, tabsH = contentW, contentH
        local mainW, mainH = tabsW + 16, tabsH + 16
        local w, h = mainW + 8, mainH + 8
        local x, y = round(vw * 0.5 - w * 0.5), round(GUI_INSET + (vh - GUI_INSET) * 0.5 - h * 0.5)
        frame(x, y, w, h, COL.c56, COL.c8)
        strokedFrame(x + 4, y + 4, mainW, mainH, COL.c26, COL.c26, 2, COL.c57)
        local tx, ty = x + 12, y + 12
        strokedFrame(tx, ty, tabsW, tabsH, COL.c22, COL.c8, 2, COL.c57)
        alignedText(tx, ty + 5 + 6, tabsW, 0, cfg.name, COL.text, 0.5, 0, true)
        local by = ty + 5 + 6 + 11 + 4
        local bx = tx + (tabsW - 130) * 0.5
        for _, button in ipairs(buttons) do
            fillRect(bx, by, bx + 130, by + 16, COL.c8)
            region(bx + 2, by + 2, 126, 12, button.owner)
            frame(bx + 2, by + 2, 126, 12, tintFor(button.owner, COL.c38), COL.c56)
            alignedText(bx + 2, by + 2, 126, 12, button.text, COL.text, 0.5, 0.5, true)
            by = by + 19
        end
    end)
end

local Loop = { connection = nil }

local function onRender()
    local now = tick()
    pollInput(now)
    for i = #Updaters, 1, -1 do
        local fn = Updaters[i]
        if fn then
            local ok, err = pcall(fn)
            if not ok then
                reportError(err)
            end
        end
    end
    Render.beginFrame()
    Hit.n = 0
    Popups.n = 0
    local list = Surfaces.list
    local snapshot = {}
    for i = 1, #list do
        snapshot[i] = list[i]
    end
    for i = 1, #snapshot do
        local surface = snapshot[i]
        if not surface.removed then
            local ok, err = pcall(surface.draw)
            if not ok then
                reportError(err)
            end
            Render.alpha = 1
            Render.clip = nil
            table.clear(Render.clipStack)
        end
    end
    Render.endFrame()
    dispatchMouse()
end

Loop.connection = RunService.RenderStepped:Connect(onRender)

function library:unload()
    if Loop.connection then
        Loop.connection:Disconnect()
        Loop.connection = nil
    end
    for _, connection in next, library.connections do
        pcall(function()
            connection:Disconnect()
        end)
    end
    for _, o in ipairs(Render.objects) do
        pcall(function()
            o:Remove()
        end)
    end
    Render.objects = {}
    Render.pools = {}
    table.clear(Surfaces.list)
    table.clear(Updaters)
    if _G.InterceptionUI == library then
        _G.InterceptionUI = nil
    end
end

library.themes = themes
library.uis = uis
_G.InterceptionUI = library

print("UI By Pepsi")
print("Discord @ xtiwy_")
library:notification({ text = "Discord @ xtiwy_" })
library:notification({ text = "UI By Pepsi" })

return library
