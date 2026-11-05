-- g3dui/layout.lua
-- Virtual resolution, automatic scaling and anchor-based placement.
--
-- All widget coordinates live in "virtual units". The virtual space is the
-- window size divided by `layout.scale`, so a UI designed for 1280x720 looks
-- the same on a phone and on a desktop monitor.

local layout = {
    refWidth  = 1280,
    refHeight = 720,
    scaleMode = "fit", -- "fit" | "height" | "width" | "none" | <number>

    scale  = 1,        -- virtual unit -> window pixel
    width  = 1280,     -- virtual width  (window width  / scale)
    height = 720,      -- virtual height (window height / scale)

    winWidth  = 1280,
    winHeight = 720,

    -- notch / rounded corners (phones): anchored widgets stay inside this rectangle
    useSafeArea = true,
    safeX = 0, safeY = 0, safeW = 1280, safeH = 720, -- virtual units
}

-- anchor name -> {fractionX, fractionY}
layout.anchors = {
    ["top-left"]     = {0,   0},
    ["top"]          = {0.5, 0},
    ["top-right"]    = {1,   0},
    ["left"]         = {0,   0.5},
    ["center"]       = {0.5, 0.5},
    ["right"]        = {1,   0.5},
    ["bottom-left"]  = {0,   1},
    ["bottom"]       = {0.5, 1},
    ["bottom-right"] = {1,   1},
}

function layout.setup(opts)
    if opts.refWidth  then layout.refWidth  = opts.refWidth  end
    if opts.refHeight then layout.refHeight = opts.refHeight end
    if opts.scaleMode ~= nil then layout.scaleMode = opts.scaleMode end
    if opts.safeArea ~= nil then layout.useSafeArea = opts.safeArea end
end

-- recompute scale and virtual size from the window size (in pixels)
function layout.refresh(winW, winH)
    if not winW then
        winW, winH = love.graphics.getDimensions()
    end
    winW, winH = math.max(winW, 1), math.max(winH, 1)

    local mode = layout.scaleMode
    local s
    if type(mode) == "number" then
        s = mode
    elseif mode == "fit" then
        s = math.min(winW / layout.refWidth, winH / layout.refHeight)
    elseif mode == "height" then
        s = winH / layout.refHeight
    elseif mode == "width" then
        s = winW / layout.refWidth
    else
        s = 1
    end

    layout.scale = s
    layout.width = winW / s
    layout.height = winH / s
    layout.winWidth, layout.winHeight = winW, winH

    -- safe area (LÖVE 11.3+ on mobile); falls back to the whole window
    local sx, sy, sw, sh = 0, 0, winW, winH
    if layout.useSafeArea and love.window and love.window.getSafeArea then
        local ok, ax, ay, aw, ah = pcall(love.window.getSafeArea)
        if ok and aw and aw > 0 and ah and ah > 0 then
            sx, sy, sw, sh = ax, ay, aw, ah
        end
    end
    layout.safeX, layout.safeY = sx / s, sy / s
    layout.safeW, layout.safeH = sw / s, sh / s
end

function layout.toVirtual(px, py)
    return px / layout.scale, py / layout.scale
end

function layout.toWindow(vx, vy)
    return vx * layout.scale, vy * layout.scale
end

-- Position a widget inside its parent rectangle.
--
-- The widget's own pivot equals its anchor, so a "bottom-right" widget has its
-- bottom-right corner on the parent's bottom-right corner.
-- `w.x` / `w.y` are margins measured from the anchored edge towards the
-- inside (right/bottom anchors flip the sign). On a centered axis the offset is
-- measured from the center (right/down is positive).
function layout.place(w, px, py, pw, ph)
    local a = layout.anchors[w.anchor]
    if not a then
        error("g3dui: unknown anchor '" .. tostring(w.anchor) .. "'", 3)
    end
    local ax, ay = a[1], a[2]
    local ox = w.x or 0
    local oy = w.y or 0
    if ax == 1 then ox = -ox end
    if ay == 1 then oy = -oy end
    w._x = px + ax * pw + ox - ax * w._w
    w._y = py + ay * ph + oy - ay * w._h
end

return layout
