-- g3dui/theme.lua
-- Default look. Nothing here is mandatory:
--   * pass `draw = function(w) ... end` to any widget to draw it yourself
--   * replace a whole widget type:  ui.setTheme{ draw = { button = function(w) ... end } }
--   * tweak colors:                 ui.setTheme{ colors = { accent = {1, .4, .2, 1} } }
--   * tweak a single widget:        ui.button{ style = { bg = {...}, cornerRadius = 0 } }
--
-- Text is rasterized at the real screen size (font size * UI scale) so it stays
-- sharp at any resolution. Use `ui.newFont(size [, path])` for custom fonts.

local layout = require((...):match("^(.*)%.[^.]+$") .. ".layout")

local theme = {}

theme.presets = {
    dark = {
        text = { 1, 1, 1, 1 }, textDim = { 1, 1, 1, 0.55 },
        bg = { 0.12, 0.13, 0.18, 0.82 }, bgHover = { 0.19, 0.21, 0.29, 0.92 },
        bgPressed = { 0.28, 0.52, 0.92, 0.95 }, bgDisabled = { 0.12, 0.13, 0.18, 0.4 },
        border = { 1, 1, 1, 0.25 }, accent = { 0.3, 0.65, 1, 1 },
        track = { 1, 1, 1, 0.18 }, shadow = { 0, 0, 0, 0.65 },
    },
    light = {
        text = { 0.1, 0.1, 0.14, 1 }, textDim = { 0.1, 0.1, 0.14, 0.55 },
        bg = { 0.96, 0.96, 0.98, 0.9 }, bgHover = { 0.88, 0.92, 1, 0.95 },
        bgPressed = { 0.6, 0.78, 1, 0.98 }, bgDisabled = { 0.96, 0.96, 0.98, 0.45 },
        border = { 0, 0, 0, 0.3 }, accent = { 0.1, 0.45, 0.9, 1 },
        track = { 0, 0, 0, 0.15 }, shadow = { 1, 1, 1, 0.6 },
    },
}

theme.colors = {}
for k, v in pairs(theme.presets.dark) do theme.colors[k] = v end

theme.cornerRadius = 8
theme.lineWidth = 2
theme.fontSize = 18
theme.font = nil -- a ui.newFont(...) object or a love Font

----------------------------------------------------------------------------------------------------
-- fonts
----------------------------------------------------------------------------------------------------

local cache = {}

-- "scalable font": resolved to a real Font at the current UI scale
function theme.newFont(size, path)
    return { isScalable = true, size = size, path = path }
end

local function scaledFont(path, size)
    local px = math.max(1, math.floor(size * layout.scale + 0.5))
    local key = (path or "") .. ":" .. px
    local f = cache[key]
    if not f then
        f = path and love.graphics.newFont(path, px) or love.graphics.newFont(px)
        cache[key] = f
    end
    return f, px / size
end

-- returns font, divisor (font metrics / divisor = virtual units)
function theme.fontFor(w)
    local f = (w and w.font) or theme.font
    if f == nil then return scaledFont(nil, theme.fontSize) end
    if type(f) == "table" and f.isScalable then return scaledFont(f.path, f.size) end
    return f, 1
end

function theme.fontHeight(w)
    local font, fs = theme.fontFor(w)
    return font:getHeight() / fs
end

-- width, height of a text in virtual units (wraps when `width` is given)
function theme.measure(w, text, width)
    local font, fs = theme.fontFor(w)
    local lh = font:getHeight() * font:getLineHeight() / fs
    if width then
        local _, lines = font:getWrap(text, width * fs)
        return width, math.max(1, #lines) * lh
    end
    local _, n = text:gsub("\n", "")
    return font:getWidth(text) / fs, (n + 1) * lh
end

function theme.print(w, text, x, y, width, align)
    local font, fs = theme.fontFor(w)
    local s = layout.scale
    x, y = math.floor(x * s + 0.5) / s, math.floor(y * s + 0.5) / s -- pixel snap
    love.graphics.setFont(font)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(1 / fs)
    love.graphics.printf(text, 0, 0, width * fs, align or "left")
    love.graphics.pop()
end

----------------------------------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------------------------------

function theme.color(w, name)
    local s = w.style
    if s and s[name] then return s[name] end
    return theme.colors[name]
end

function theme.setColor(c, alpha)
    love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * (alpha or 1))
end

local function radiusOf(w)
    return (w.style and w.style.cornerRadius) or theme.cornerRadius
end

local function text(w, str, x, y, width, align)
    if w.shadow then
        theme.setColor(theme.color(w, "shadow"), w._alpha)
        theme.print(w, str, x + 1.5, y + 1.5, width, align)
    end
    theme.setColor(theme.color(w, "text"), w._alpha)
    theme.print(w, str, x, y, width, align)
end

----------------------------------------------------------------------------------------------------
-- default draw functions, one per widget type (each receives the widget)
----------------------------------------------------------------------------------------------------

local draw = {}
theme.draw = draw

function draw.widget(w) end -- a bare hotspot draws nothing

function draw.panel(w)
    local x, y, pw, ph = w:getRect()
    local r = radiusOf(w)
    theme.setColor(theme.color(w, "bg"), w._alpha)
    love.graphics.rectangle("fill", x, y, pw, ph, r, r)
    if w.border ~= false then
        love.graphics.setLineWidth(theme.lineWidth)
        theme.setColor(theme.color(w, "border"), w._alpha)
        love.graphics.rectangle("line", x, y, pw, ph, r, r)
    end
    if w.title then text(w, w.title, x, y + 8, pw, "center") end
end

function draw.label(w)
    local str = w:getText()
    if str == "" then return end
    local x, y, lw = w:getRect()
    text(w, str, x, y, lw, w.align or "left")
end

function draw.button(w)
    local x, y, bw, bh = w:getRect()
    local a, r = w._alpha, radiusOf(w)
    if w.image then
        local img = (w.pressed and w.imagePressed) or w.image
        local shade = (w.pressed and not w.imagePressed) and 0.7 or 1
        if not w:isEnabled() then shade = 0.45 end
        love.graphics.setColor(shade, shade, shade, a)
        love.graphics.draw(img, x, y, 0, bw / img:getWidth(), bh / img:getHeight())
    else
        local bg
        if not w:isEnabled() then bg = theme.color(w, "bgDisabled")
        elseif w.pressed then bg = theme.color(w, "bgPressed")
        elseif w.hovered then bg = theme.color(w, "bgHover")
        else bg = theme.color(w, "bg") end
        theme.setColor(bg, a)
        love.graphics.rectangle("fill", x, y, bw, bh, r, r)
        love.graphics.setLineWidth(theme.lineWidth)
        theme.setColor(theme.color(w, "border"), a)
        love.graphics.rectangle("line", x, y, bw, bh, r, r)
    end
    local str = w:getText()
    if str ~= "" then
        local _, th = theme.measure(w, str)
        text(w, str, x, y + (bh - th) / 2, bw, "center")
    end
end

function draw.toggle(w)
    local x, y, tw, th = w:getRect()
    local a, r = w._alpha, radiusOf(w) * 0.6
    theme.setColor(w.hovered and theme.color(w, "bgHover") or theme.color(w, "bg"), a)
    love.graphics.rectangle("fill", x, y, th, th, r, r)
    love.graphics.setLineWidth(theme.lineWidth)
    theme.setColor(theme.color(w, "border"), a)
    love.graphics.rectangle("line", x, y, th, th, r, r)
    if w.value then
        theme.setColor(theme.color(w, "accent"), a)
        local m = th * 0.25
        love.graphics.rectangle("fill", x + m, y + m, th - 2 * m, th - 2 * m, r * 0.5, r * 0.5)
    end
    local str = w:getText()
    if str ~= "" then
        local _, h = theme.measure(w, str)
        text(w, str, x + th + 10, y + (th - h) / 2, tw - th - 10, "left")
    end
end

function draw.slider(w)
    local x, y, sw, sh = w:getRect()
    local a, t, th = w._alpha, w:getNormalized(), 8
    local knob = (w.vertical and sw or sh) * 0.5 * (w.pressed and 1.1 or 1)
    if w.vertical then
        local cx, fh = x + sw / 2, sh * t
        theme.setColor(theme.color(w, "track"), a)
        love.graphics.rectangle("fill", cx - th / 2, y, th, sh, th / 2, th / 2)
        theme.setColor(theme.color(w, "accent"), a)
        love.graphics.rectangle("fill", cx - th / 2, y + sh - fh, th, fh, th / 2, th / 2)
        love.graphics.circle("fill", cx, y + sh - fh, knob)
    else
        local cy = y + sh / 2
        theme.setColor(theme.color(w, "track"), a)
        love.graphics.rectangle("fill", x, cy - th / 2, sw, th, th / 2, th / 2)
        theme.setColor(theme.color(w, "accent"), a)
        love.graphics.rectangle("fill", x, cy - th / 2, sw * t, th, th / 2, th / 2)
        love.graphics.circle("fill", x + sw * t, cy, knob)
    end
end

function draw.joystick(w)
    if w.floating and not w.active and w.showIdle == false then return end
    local cx, cy = w:getCenter()
    local a = w._alpha * ((not w.active and w.floating) and 0.35 or 1)
    theme.setColor(theme.color(w, "bg"), a)
    love.graphics.circle("fill", cx, cy, w.radius)
    love.graphics.setLineWidth(theme.lineWidth)
    theme.setColor(theme.color(w, "border"), a)
    love.graphics.circle("line", cx, cy, w.radius)
    local kx, ky = cx + w.knobX * w.radius, cy + w.knobY * w.radius
    theme.setColor(w.active and theme.color(w, "bgPressed") or theme.color(w, "accent"), a)
    love.graphics.circle("fill", kx, ky, w.knobRadius)
    theme.setColor(theme.color(w, "border"), a)
    love.graphics.circle("line", kx, ky, w.knobRadius)
end

function draw.touchpad(w)
    if not w.showArea then return end
    local x, y, pw, ph = w:getRect()
    theme.setColor(theme.color(w, "track"), w._alpha)
    love.graphics.rectangle("fill", x, y, pw, ph)
    love.graphics.setLineWidth(1)
    theme.setColor(theme.color(w, "border"), w._alpha)
    love.graphics.rectangle("line", x, y, pw, ph)
end

function draw.bar(w)
    local x, y, bw, bh = w:getRect()
    local a, t = w._alpha, w:getNormalized()
    local r = math.min(radiusOf(w), math.min(bw, bh) / 2)
    theme.setColor(theme.color(w, "track"), a)
    love.graphics.rectangle("fill", x, y, bw, bh, r, r)
    if t > 0 then
        theme.setColor((w.style and w.style.fill) or theme.color(w, "accent"), a)
        if w.vertical then
            love.graphics.rectangle("fill", x, y + bh * (1 - t), bw, bh * t, r, r)
        else
            love.graphics.rectangle("fill", x, y, bw * t, bh, r, r)
        end
    end
    love.graphics.setLineWidth(theme.lineWidth)
    theme.setColor(theme.color(w, "border"), a)
    love.graphics.rectangle("line", x, y, bw, bh, r, r)
    local str = w:getText()
    if str ~= "" then
        local _, th = theme.measure(w, str)
        text(w, str, x, y + (bh - th) / 2, bw, "center")
    end
end

function draw.image(w)
    if not w.image then return end
    local x, y, iw, ih = w:getRect()
    theme.setColor((w.style and w.style.tint) or { 1, 1, 1, 1 }, w._alpha)
    if w.quad then
        local _, _, qw, qh = w.quad:getViewport()
        love.graphics.draw(w.image, w.quad, x, y, 0, iw / qw, ih / qh)
    else
        love.graphics.draw(w.image, x, y, 0, iw / w.image:getWidth(), ih / w.image:getHeight())
    end
end

-- ui.setTheme("light")  or  ui.setTheme{ colors = {...}, draw = {...}, cornerRadius = 12, font = f }
function theme.set(t)
    if type(t) == "string" then
        local preset = theme.presets[t]
        if not preset then error("g3dui: unknown theme preset '" .. t .. "'", 2) end
        t = { colors = preset }
    end
    for k, v in pairs(t) do
        if k == "colors" then
            for name, c in pairs(v) do theme.colors[name] = c end
        elseif k == "draw" then
            for name, fn in pairs(v) do draw[name] = fn end
        elseif k ~= "presets" then
            theme[k] = v
        end
    end
end

return theme
