-- g3dui/input.lua
-- Unified input: keyboard, mouse, gamepad and on-screen (virtual) controls all
-- feed the same named "actions" and "axes".
--
-- Source strings:
--   "key:space"    keyboard key (love KeyConstant)
--   "scan:w"       keyboard scancode (layout independent)
--   "mouse:1"      mouse button
--   "pad:a"        gamepad button (love GamepadButton)
--   "virtual:<id>" used internally by on-screen widgets
--
-- Axis convention: x grows to the right, y grows DOWN (like the screen and
-- like LÖVE's gamepad axes). "Up" is therefore y = -1.

local input = {}

input.deadzone = 0.15 -- radial deadzone applied to gamepad sticks

local actions = {}    -- name -> true
local axes = {}       -- name -> axis definition
local srcActions = {} -- source -> { action, ... }
local srcHeld = {}    -- source -> true (digital sources that are down)
local held = {}       -- action -> { [source] = true }
local padAxes = {}    -- love gamepad axis name -> value
local virtualAxes = {} -- axis name -> { [key] = {x, y} }

-- values are double buffered so that "pressed" survives until the next
-- ui.update() even though events arrive before the update
local pendPressed, pendReleased, pendDelta = {}, {}, {}
local curPressed, curReleased, curDelta = {}, {}, {}

local function toList(v)
    if v == nil then return {} end
    if type(v) == "string" then return { v } end
    return v
end

----------------------------------------------------------------------------------------------------
-- actions
----------------------------------------------------------------------------------------------------

local function press(action, src)
    local h = held[action]
    if not h then
        h = {}
        held[action] = h
    end
    local wasDown = next(h) ~= nil
    h[src] = true
    if not wasDown then pendPressed[action] = true end
end

local function release(action, src)
    local h = held[action]
    if not h or not h[src] then return end
    h[src] = nil
    if next(h) == nil then pendReleased[action] = true end
end

local function mapSource(src, action)
    local list = srcActions[src]
    if not list then
        list = {}
        srcActions[src] = list
    end
    for _, a in ipairs(list) do
        if a == action then return end
    end
    list[#list + 1] = action
    -- if the source is already down when it gets bound, count it as held
    if srcHeld[src] then press(action, src) end
end

-- input.bind("jump", "key:space", "pad:a")   or   input.bind("jump", {"key:space", "pad:a"})
function input.bind(action, ...)
    actions[action] = true
    local sources = { ... }
    if type(sources[1]) == "table" then sources = sources[1] end
    for _, src in ipairs(sources) do
        mapSource(src, action)
    end
end

-- removes every source bound to an action
function input.unbind(action)
    for src, list in pairs(srcActions) do
        for i = #list, 1, -1 do
            if list[i] == action then table.remove(list, i) end
        end
    end
    held[action] = nil
    actions[action] = nil
end

function input.down(action)
    local h = held[action]
    return h ~= nil and next(h) ~= nil
end

function input.pressed(action)
    return curPressed[action] == true
end

function input.released(action)
    return curReleased[action] == true
end

-- called by event handlers
function input.sourceDown(src)
    srcHeld[src] = true
    local list = srcActions[src]
    if list then
        for _, a in ipairs(list) do press(a, src) end
    end
end

function input.sourceUp(src)
    srcHeld[src] = nil
    local list = srcActions[src]
    if list then
        for _, a in ipairs(list) do release(a, src) end
    end
end

-- on-screen widgets hold actions through "virtual:<id>" sources
function input.virtualDown(action, key)
    actions[action] = true
    press(action, "virtual:" .. tostring(key))
end

function input.virtualUp(action, key)
    release(action, "virtual:" .. tostring(key))
end

----------------------------------------------------------------------------------------------------
-- axes
----------------------------------------------------------------------------------------------------

local padShortcuts = {
    left  = { x = "leftx",  y = "lefty" },
    right = { x = "rightx", y = "righty" },
}

-- input.bindAxis("move", {
--     left = {"key:a", "key:left"}, right = "key:d", up = "key:w", down = "key:s",
--     pad = "left",                       -- or { x = "leftx", y = "lefty" }
-- })
function input.bindAxis(name, def)
    local pad = def.pad
    if type(pad) == "string" then pad = padShortcuts[pad] end
    axes[name] = {
        left  = toList(def.left),
        right = toList(def.right),
        up    = toList(def.up),
        down  = toList(def.down),
        pad   = pad,
    }
end

local function anyHeld(list)
    for i = 1, #list do
        if srcHeld[list[i]] then return true end
    end
    return false
end

local function radialDeadzone(x, y, dz)
    local len = math.sqrt(x * x + y * y)
    if len <= dz then return 0, 0 end
    local scaled = (len - dz) / (1 - dz)
    if scaled > 1 then scaled = 1 end
    return x / len * scaled, y / len * scaled
end

-- returns x, y in the range -1..1 (length never exceeds 1)
function input.axis(name)
    local def = axes[name]
    local bestX, bestY, bestLen = 0, 0, 0

    local function consider(x, y)
        local len = x * x + y * y
        if len > bestLen then bestX, bestY, bestLen = x, y, len end
    end

    if def then
        local dx = (anyHeld(def.right) and 1 or 0) - (anyHeld(def.left) and 1 or 0)
        local dy = (anyHeld(def.down) and 1 or 0) - (anyHeld(def.up) and 1 or 0)
        if dx ~= 0 and dy ~= 0 then
            dx, dy = dx * 0.70710678, dy * 0.70710678
        end
        consider(dx, dy)

        if def.pad then
            local px, py = padAxes[def.pad.x] or 0, padAxes[def.pad.y] or 0
            px, py = radialDeadzone(px, py, input.deadzone)
            consider(px, py)
        end
    end

    local v = virtualAxes[name]
    if v then
        for _, a in pairs(v) do consider(a[1], a[2]) end
    end

    if bestLen > 1 then
        local len = math.sqrt(bestLen)
        bestX, bestY = bestX / len, bestY / len
    end
    return bestX, bestY
end

-- on-screen joystick support
function input.setVirtualAxis(name, key, x, y)
    if not axes[name] then
        axes[name] = { left = {}, right = {}, up = {}, down = {} }
    end
    local v = virtualAxes[name]
    if not v then
        v = {}
        virtualAxes[name] = v
    end
    if x ~= 0 or y ~= 0 then
        v[key] = { x, y }
    else
        v[key] = nil
    end
end

input.gamepadAxis = function(axis, value)
    padAxes[axis] = value
end

----------------------------------------------------------------------------------------------------
-- deltas (drag / look pads)
----------------------------------------------------------------------------------------------------

function input.addDelta(name, dx, dy)
    local d = pendDelta[name]
    if not d then
        d = { 0, 0 }
        pendDelta[name] = d
    end
    d[1] = d[1] + dx
    d[2] = d[2] + dy
end

-- movement accumulated during the last frame
function input.delta(name)
    local d = curDelta[name]
    if d then return d[1], d[2] end
    return 0, 0
end

----------------------------------------------------------------------------------------------------
-- frame handling
----------------------------------------------------------------------------------------------------

-- call once per frame, before the game reads pressed/released/delta
function input.update()
    curPressed, pendPressed = pendPressed, {}
    curReleased, pendReleased = pendReleased, {}
    curDelta, pendDelta = pendDelta, {}
end

-- forget everything that is held (window lost focus, scene change...)
function input.releaseAll()
    for action, h in pairs(held) do
        if next(h) ~= nil then
            for src in pairs(h) do
                h[src] = nil
            end
            pendReleased[action] = true
        end
    end
    srcHeld = {}
    padAxes = {}
    for _, v in pairs(virtualAxes) do
        for k in pairs(v) do v[k] = nil end
    end
end

return input
