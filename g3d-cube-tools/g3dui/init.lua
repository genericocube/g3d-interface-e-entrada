-- g3dui: UI + unified input + 3D picking for LÖVE / g3d
-- MIT license. See README.md.
--
--   local ui = require "g3d-cube-tools.g3dui"
--   ui.setup{ camera = g3d.camera }      -- optional
--   ui.hook()                            -- call inside love.load
--   function love.update(dt) ui.update(dt) end
--   function love.draw() --[[ 3D ]] ui.draw() end

local PATH = ...

local layout  = require(PATH .. ".layout")
local input   = require(PATH .. ".input")
local theme   = require(PATH .. ".theme")
local widgets = require(PATH .. ".widgets")
local pick3d  = require(PATH .. ".pick3d")

local ui = {
    _VERSION = "g3dui 1.0.0",
    layout = layout,
    input = input,
    theme = theme,
    pick3d = pick3d,
    debug = false, -- draw widget rectangles
}

local pointers = {}      -- id -> pointer
local lastSource = (love.system and (love.system.getOS() == "Android" or love.system.getOS() == "iOS")) and "touch" or "mouse"
local touchCount = 0
local primaryTouchConsumed = false
local hovered = nil
local lastW, lastH = 0, 0

----------------------------------------------------------------------------------------------------
-- setup
----------------------------------------------------------------------------------------------------

-- ui.setup{
--   refWidth = 1280, refHeight = 720,   -- design resolution
--   scaleMode = "fit",                  -- "fit" | "height" | "width" | "none" | number
--   safeArea = true,                    -- respect phone notches
--   camera = g3d.camera,                -- needed for 3D picking (auto-detected when possible)
--   viewport = {x, y, w, h},            -- window pixels where the 3D view is drawn (default: whole window)
--   theme = "dark" | "light" | table,
-- }
function ui.setup(opts)
    opts = opts or {}
    layout.setup(opts)
    if opts.camera then pick3d.camera = opts.camera end
    if opts.viewport then pick3d.viewport = opts.viewport end
    if opts.theme then theme.set(opts.theme) end
    layout.refresh()
    widgets.dirty = true
end

function ui.resize(w, h)
    layout.refresh(w, h)
    lastW, lastH = layout.winWidth, layout.winHeight
    widgets.dirty = true
end

ui.setTheme = theme.set
ui.newFont = theme.newFont

----------------------------------------------------------------------------------------------------
-- widget constructors
----------------------------------------------------------------------------------------------------

for _, kind in ipairs { "panel", "label", "button", "toggle", "slider", "bar", "image", "joystick", "touchpad", "widget" } do
    ui[kind] = function(opts) return widgets.create(kind, opts) end
end

function ui.destroyAll() widgets.destroyAll() end

----------------------------------------------------------------------------------------------------
-- layers
----------------------------------------------------------------------------------------------------

-- ui.layer("menu", { order = 10, visible = false, alpha = 1 })
function ui.layer(name, opts)
    local l = widgets.getLayer(name)
    if opts then
        if opts.order ~= nil then l.order = opts.order end
        if opts.visible ~= nil then l.visible = opts.visible end
        if opts.alpha ~= nil then l.alpha = opts.alpha end
    end
    widgets.dirty = true
    return l
end
function ui.showLayer(name) ui.layer(name, { visible = true }) end
function ui.hideLayer(name) ui.layer(name, { visible = false }) end
function ui.toggleLayer(name)
    local l = widgets.getLayer(name)
    ui.layer(name, { visible = not l.visible })
end
function ui.isLayerVisible(name) return widgets.getLayer(name).visible end

----------------------------------------------------------------------------------------------------
-- input shortcuts
----------------------------------------------------------------------------------------------------

ui.bind = input.bind
ui.unbind = input.unbind
ui.bindAxis = input.bindAxis
ui.down = input.down
ui.pressed = input.pressed
ui.released = input.released
ui.axis = input.axis
ui.delta = input.delta

-- 3D picking shortcut: ui.clickable(model, { onClick = function(model, hit) end, ... })
ui.clickable = pick3d.add

----------------------------------------------------------------------------------------------------
-- pointers (mouse + every touch)
----------------------------------------------------------------------------------------------------

local function newPointer(id, source, px, py, button)
    local vx, vy = layout.toVirtual(px, py)
    return {
        id = id, source = source, button = button,
        px = px, py = py, x = vx, y = vy, dx = 0, dy = 0, sx = vx, sy = vy,
    }
end

-- Returns true when the UI or a 3D object consumed the press.
function ui.pointerPressed(id, source, px, py, button)
    if widgets.dirty then widgets.layoutAll() end
    if source == "mouse" and button ~= 1 and not (pick3d.buttons[button]) then return false end
    local p = newPointer(id, source, px, py, button)

    local w = (source ~= "mouse" or button == 1) and widgets.hitTest(p.x, p.y) or nil
    if w then
        p.widget, p.consumed = w, true
        pointers[id] = p
        w:_press(p)
        return true
    end
    if pick3d.pressed(p) then
        p.consumed = p.pick.entry.consume ~= false
        pointers[id] = p
        return p.consumed
    end
    return false
end

function ui.pointerMoved(id, px, py)
    local p = pointers[id]
    if not p then return false end
    local nx, ny = layout.toVirtual(px, py)
    p.dx, p.dy = nx - p.x, ny - p.y
    p.x, p.y, p.px, p.py = nx, ny, px, py
    if p.widget then p.widget:_move(p) elseif p.pick then pick3d.moved(p) end
    return p.consumed == true
end

function ui.pointerReleased(id, px, py)
    local p = pointers[id]
    if not p then return false end
    pointers[id] = nil
    p.x, p.y = layout.toVirtual(px, py)
    p.px, p.py = px, py
    if p.widget then p.widget:_release(p, false) elseif p.pick then pick3d.released(p) end
    return p.consumed == true
end

-- window pixels. True when a widget (or blocking panel) is under the position.
function ui.isOverUI(px, py)
    if widgets.dirty then widgets.layoutAll() end
    local vx, vy = layout.toVirtual(px, py)
    return widgets.hitTest(vx, vy) ~= nil
end

local function cancelAll()
    for id, p in pairs(pointers) do
        if p.widget then p.widget:_cancel(p) p.widget = nil end
        if p.pick then p.pick = nil end
    end
end

----------------------------------------------------------------------------------------------------
-- love event entry points. Each returns true when the event was consumed and
-- your game should ignore it. (ui.hook() wires these up for you.)
----------------------------------------------------------------------------------------------------

function ui.mousepressed(x, y, button, istouch)
    if istouch then return primaryTouchConsumed end
    lastSource = "mouse"
    local consumed = ui.pointerPressed("mouse", "mouse", x, y, button)
    if not consumed then input.sourceDown("mouse:" .. button) end
    return consumed
end

function ui.mousereleased(x, y, button, istouch)
    if istouch then return primaryTouchConsumed end
    input.sourceUp("mouse:" .. button)
    if button ~= 1 then return false end
    return ui.pointerReleased("mouse", x, y)
end

function ui.mousemoved(x, y, dx, dy, istouch)
    if istouch then return primaryTouchConsumed end
    lastSource = "mouse"
    return ui.pointerMoved("mouse", x, y)
end

function ui.touchpressed(id, x, y)
    lastSource = "touch"
    local first = touchCount == 0
    touchCount = touchCount + 1
    local consumed = ui.pointerPressed(id, "touch", x, y, 1)
    if first then primaryTouchConsumed = consumed end
    return consumed
end

function ui.touchmoved(id, x, y)
    return ui.pointerMoved(id, x, y)
end

function ui.touchreleased(id, x, y)
    touchCount = math.max(0, touchCount - 1)
    return ui.pointerReleased(id, x, y)
end

function ui.keypressed(key, scancode, isrepeat)
    if isrepeat then return end
    input.sourceDown("key:" .. key)
    if scancode then input.sourceDown("scan:" .. scancode) end
end

function ui.keyreleased(key, scancode)
    input.sourceUp("key:" .. key)
    if scancode then input.sourceUp("scan:" .. scancode) end
end

function ui.gamepadpressed(_, button) input.sourceDown("pad:" .. button) end
function ui.gamepadreleased(_, button) input.sourceUp("pad:" .. button) end

function ui.gamepadaxis(_, axis, value)
    input.gamepadAxis(axis, value)
    if axis == "triggerleft" or axis == "triggerright" then
        if value > 0.5 then input.sourceDown("pad:" .. axis) else input.sourceUp("pad:" .. axis) end
    end
end

-- mouse wheel becomes one-frame presses: "wheel:up", "wheel:down", "wheel:left", "wheel:right"
function ui.wheelmoved(x, y)
    local name = (y > 0 and "up") or (y < 0 and "down") or (x > 0 and "right") or (x < 0 and "left")
    if name then
        input.sourceDown("wheel:" .. name)
        input.sourceUp("wheel:" .. name)
    end
end

function ui.focus(focused)
    if not focused then
        cancelAll()
        input.releaseAll()
    end
end

----------------------------------------------------------------------------------------------------
-- hook: wraps love.handlers so you can keep defining love.mousepressed etc.
-- yourself, in any order. Events consumed by the UI never reach your callbacks.
----------------------------------------------------------------------------------------------------

local hooked = false

function ui.hook()
    if hooked then return end
    local handlers = love.handlers
    if not handlers then
        error("g3dui: love.handlers not found; call the ui.mousepressed/... functions manually", 2)
    end
    hooked = true

    local function wrap(name, fn, canConsume)
        local orig = rawget(handlers, name)
        handlers[name] = function(...)
            local consumed = fn(...)
            if canConsume and consumed then return end
            if orig then return orig(...) end
        end
    end

    wrap("mousepressed", ui.mousepressed, true)
    wrap("mousereleased", ui.mousereleased, true)
    wrap("mousemoved", ui.mousemoved, true)
    wrap("touchpressed", ui.touchpressed, true)
    wrap("touchmoved", ui.touchmoved, true)
    wrap("touchreleased", ui.touchreleased, true)
    wrap("keypressed", ui.keypressed)
    wrap("keyreleased", ui.keyreleased)
    wrap("gamepadpressed", ui.gamepadpressed)
    wrap("gamepadreleased", ui.gamepadreleased)
    wrap("gamepadaxis", ui.gamepadaxis)
    wrap("wheelmoved", ui.wheelmoved)
    wrap("focus", ui.focus)
    wrap("resize", ui.resize)
end

----------------------------------------------------------------------------------------------------
-- update / draw
----------------------------------------------------------------------------------------------------

local function setHovered(w)
    if w == hovered then return end
    if hovered then
        hovered.hovered = false
        if hovered.onHoverEnd then hovered:onHoverEnd() end
    end
    hovered = w
    if w then
        w.hovered = true
        if w.onHoverStart then w:onHoverStart() end
    end
end

function ui.update(dt)
    local ww, wh = love.graphics.getDimensions()
    if ww ~= lastW or wh ~= lastH then ui.resize(ww, wh) end

    input.update()

    -- release pointers whose widget was hidden / destroyed meanwhile
    for _, p in pairs(pointers) do
        if p.widget and (p.widget._destroyed or not p.widget:isVisible()) then
            p.widget:_cancel(p)
            p.widget = nil
        end
    end

    -- mouse hover (widgets and 3D objects)
    local relative = love.mouse.getRelativeMode and love.mouse.getRelativeMode()
    if lastSource == "mouse" and not relative then
        if not pointers.mouse then
            local px, py = love.mouse.getPosition()
            local vx, vy = layout.toVirtual(px, py)
            local w = widgets.hitTest(vx, vy)
            setHovered(w)
            pick3d.updateHover(px, py, w ~= nil)
        end
    else
        setHovered(nil)
        pick3d.updateHover(nil)
    end

    widgets.update(dt)
    widgets.layoutAll() -- every frame: texts and sizes can change
end

function ui.draw()
    if widgets.dirty then widgets.layoutAll() end
    local depthMode, depthWrite = love.graphics.getDepthMode()
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setShader()
    love.graphics.setDepthMode("always", false)
    love.graphics.setBlendMode("alpha")
    love.graphics.setColorMask(true, true, true, true)
    love.graphics.scale(layout.scale)
    widgets.draw(ui.debug)
    love.graphics.pop()
    love.graphics.setDepthMode(depthMode, depthWrite)
end

widgets.tapHandler = function(p)
    if pick3d.pressed(p) then pick3d.released(p) end
end

-- initial state (the window already exists when main.lua is loaded)
layout.refresh()
lastW, lastH = layout.winWidth, layout.winHeight

return ui
