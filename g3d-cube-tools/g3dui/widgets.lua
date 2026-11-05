-- g3dui/widgets.lua
-- Widget classes (panel, label, button, toggle, slider, bar, image, joystick,
-- touchpad), layers, layout pass, drawing and hit testing.
--
-- Every option passed to a constructor becomes a field of the widget, so any
-- callback or setting can be changed later: `btn.text = "Other"`.

local base = (...):match("^(.*)%.[^.]+$")
local layout = require(base .. ".layout")
local theme = require(base .. ".theme")
local input = require(base .. ".input")

local widgets = {
    roots = {},
    sorted = {},
    layers = {},
    dirty = true,
    tapHandler = nil, -- set by init.lua: forwards touchpad taps to 3D picking
}

local classes = {}
local seq = 0

local function fire(w, name, ...)
    local f = w[name]
    if f then return f(w, ...) end
end

-- number, or "50%" of the parent size
local function resolve(v, parentSize, default)
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local pct = v:match("^(%-?[%d%.]+)%%$")
        if pct then return parentSize * tonumber(pct) / 100 end
    end
    return default
end

local function clamp(v, lo, hi)
    return v < lo and lo or (v > hi and hi or v)
end

----------------------------------------------------------------------------------------------------
-- layers
----------------------------------------------------------------------------------------------------

function widgets.getLayer(name)
    local l = widgets.layers[name]
    if not l then
        l = { name = name, order = 0, visible = true, alpha = 1 }
        widgets.layers[name] = l
    end
    return l
end

----------------------------------------------------------------------------------------------------
-- base class
----------------------------------------------------------------------------------------------------

local Widget = {}
Widget.__index = Widget
Widget.type = "widget"
Widget.defaultW, Widget.defaultH = 100, 40

local function newClass(name, parent)
    local c = setmetatable({}, { __index = parent or Widget })
    c.__index = c
    c.type = name
    classes[name] = c
    return c
end

function Widget:getRect() return self._x, self._y, self._w, self._h end
function Widget:getCenter() return self._x + self._w / 2, self._y + self._h / 2 end

function Widget:getText()
    local t = self.text
    if type(t) == "function" then t = t(self) end
    return t == nil and "" or tostring(t)
end

function Widget:setText(t) self.text = t end

function Widget:getValue()
    local v = self.value
    if type(v) == "function" then v = v(self) end
    return v
end

function Widget:getNormalized()
    local lo, hi = self.min or 0, self.max or 1
    local v = self:getValue() or lo
    if hi == lo then return 0 end
    return clamp((v - lo) / (hi - lo), 0, 1)
end

function Widget:isEnabled()
    local w = self
    while w do
        if w.enabled == false then return false end
        w = w.parent
    end
    return true
end

function Widget:setEnabled(b) self.enabled = b end

-- visible itself, in a visible layer and with every parent visible
function Widget:isVisible()
    local w = self
    while w do
        if not w.visible then return false end
        if not w.parent then
            return widgets.getLayer(w.layer).visible
        end
        w = w.parent
    end
    return false
end

function Widget:setVisible(b)
    self.visible = b and true or false
    widgets.dirty = true
end
function Widget:show() self:setVisible(true) end
function Widget:hide() self:setVisible(false) end

function Widget:contains(vx, vy)
    local pad = self.hitPadding or 0
    return vx >= self._x - pad and vx <= self._x + self._w + pad
       and vy >= self._y - pad and vy <= self._y + self._h + pad
end
Widget.hitTest = Widget.contains -- override for non-rectangular shapes

function Widget:measure(pw, ph)
    self._w = resolve(self.w, pw, self.defaultW)
    self._h = resolve(self.h, ph, self.defaultH)
end

function Widget:contentTop() return 0 end

function Widget:drawDefault()
    local fn = theme.draw[self.type]
    if fn then fn(self) end
end

function Widget:render()
    if self.draw then self.draw(self) else self:drawDefault() end
end

function Widget:add(child)
    if child.parent == self then return child end
    if child.parent then child.parent:remove(child) else widgets.unroot(child) end
    child.parent = self
    self.children[#self.children + 1] = child
    widgets.dirty = true
    return child
end

function Widget:remove(child)
    for i, c in ipairs(self.children) do
        if c == child then
            table.remove(self.children, i)
            child.parent = nil
            widgets.dirty = true
            return child
        end
    end
end

function Widget:bringToFront()
    local top = 0
    for _, w in ipairs(widgets.roots) do top = math.max(top, w.z or 0) end
    self.z = top + 1
end

function Widget:destroy()
    if self._destroyed then return end
    for i = #self.children, 1, -1 do self.children[i]:destroy() end
    self:_cancel(self._pointer)
    if self._pointer then self._pointer.widget = nil end
    if self.parent then self.parent:remove(self) else widgets.unroot(self) end
    self._destroyed = true
    widgets.dirty = true
end

-- pointer events (overridden by interactive classes)
function Widget:_press(p) end
function Widget:_move(p) end
function Widget:_release(p, cancelled) end
function Widget:_cancel(p) self:_release(p or {}, true) end

function widgets.unroot(w)
    for i, r in ipairs(widgets.roots) do
        if r == w then table.remove(widgets.roots, i) return end
    end
end

----------------------------------------------------------------------------------------------------
-- panel / label / image / bar (non interactive)
----------------------------------------------------------------------------------------------------

local Panel = newClass("panel")
Panel.block = true -- swallows pointers so clicks do not pass through to the 3D world

function Panel:contentTop()
    if self.title then return theme.fontHeight(self) + 16 end
    return 0
end

function Panel:measure(pw, ph)
    if self.stack then
        local pad, gap = self.padding or 12, self.spacing or 8
        local vertical = self.stack ~= "horizontal"
        local main, cross, n = 0, 0, 0
        for _, k in ipairs(self.children) do
            if k.visible then
                k:measure(pw, ph)
                n = n + 1
                main = main + (vertical and k._h or k._w)
                cross = math.max(cross, vertical and k._w or k._h)
            end
        end
        main = main + gap * math.max(n - 1, 0)
        local cw, ch = vertical and cross or main, vertical and main or cross
        self._w = resolve(self.w, pw, cw + pad * 2)
        self._h = resolve(self.h, ph, ch + pad * 2 + self:contentTop())
    else
        self._w = resolve(self.w, pw, pw)
        self._h = resolve(self.h, ph, ph)
    end
end

local Label = newClass("label")
function Label:measure(pw, ph)
    local str = self:getText()
    local w = resolve(self.w, pw, nil)
    local tw, th = theme.measure(self, str, w)
    self._w = w or tw
    self._h = resolve(self.h, ph, th)
end

local Image = newClass("image")
function Image:measure(pw, ph)
    local iw, ih = 32, 32
    if self.quad then
        local _, _, qw, qh = self.quad:getViewport()
        iw, ih = qw, qh
    elseif self.image then
        iw, ih = self.image:getDimensions()
    end
    self._w = resolve(self.w, pw, iw)
    self._h = resolve(self.h, ph, ih)
end

local Bar = newClass("bar")
function Bar:measure(pw, ph)
    local dw, dh = 200, 24
    if self.vertical then dw, dh = 24, 200 end
    self._w = resolve(self.w, pw, dw)
    self._h = resolve(self.h, ph, dh)
end

----------------------------------------------------------------------------------------------------
-- button ("widget" is the same thing without a default look)
----------------------------------------------------------------------------------------------------

local Button = newClass("button")
Button.interactive = true
Button.defaultW, Button.defaultH = 160, 56

function Button:_press(p)
    if not self:isEnabled() then return end
    self.pressed = true
    self._pointer = p
    if self.action then input.virtualDown(self.action, self.id) end
    fire(self, "onPress", p)
end

function Button:_move(p)
    if self.pressed then fire(self, "onDrag", p) end
end

function Button:_release(p, cancelled)
    if not self.pressed then return end
    self.pressed = false
    self._pointer = nil
    if self.action then input.virtualUp(self.action, self.id) end
    fire(self, "onRelease", p)
    if not cancelled and self:hitTest(p.x, p.y) then fire(self, "onClick", p) end
end

local Hotspot = newClass("widget", Button)

----------------------------------------------------------------------------------------------------
-- toggle
----------------------------------------------------------------------------------------------------

local Toggle = newClass("toggle", Button)
Toggle.defaultH = 32

function Toggle:measure(pw, ph)
    self._h = resolve(self.h, ph, 32)
    local w = resolve(self.w, pw, nil)
    if not w then
        local str = self:getText()
        w = self._h
        if str ~= "" then w = w + 10 + theme.measure(self, str) end
    end
    self._w = w
end

function Toggle:setValue(v, silent)
    v = v and true or false
    if v == self.value then return end
    self.value = v
    if not silent then fire(self, "onChange", v) end
end

function Toggle:_press(p)
    if not self:isEnabled() then return end
    self.pressed = true
    self._pointer = p
    fire(self, "onPress", p)
end

function Toggle:_release(p, cancelled)
    if not self.pressed then return end
    self.pressed = false
    self._pointer = nil
    fire(self, "onRelease", p)
    if not cancelled and self:hitTest(p.x, p.y) then
        self:setValue(not self.value)
        fire(self, "onClick", p)
    end
end

----------------------------------------------------------------------------------------------------
-- slider
----------------------------------------------------------------------------------------------------

local Slider = newClass("slider", Button)

function Slider:measure(pw, ph)
    local dw, dh = 240, 32
    if self.vertical then dw, dh = 32, 240 end
    self._w = resolve(self.w, pw, dw)
    self._h = resolve(self.h, ph, dh)
end

function Slider:setValue(v, silent)
    local lo, hi = self.min or 0, self.max or 1
    if self.step and self.step > 0 then
        v = lo + math.floor((v - lo) / self.step + 0.5) * self.step
    end
    v = clamp(v, lo, hi)
    if v == self.value then return end
    self.value = v
    if not silent then fire(self, "onChange", v) end
end

function Slider:_fromPointer(p)
    local x, y, w, h = self:getRect()
    local t
    if self.vertical then t = 1 - (p.y - y) / h else t = (p.x - x) / w end
    t = clamp(t, 0, 1)
    local lo, hi = self.min or 0, self.max or 1
    self:setValue(lo + t * (hi - lo))
end

function Slider:_press(p)
    if not self:isEnabled() then return end
    self.pressed = true
    self._pointer = p
    fire(self, "onPress", p)
    self:_fromPointer(p)
end

function Slider:_move(p)
    if self.pressed then self:_fromPointer(p) end
end

function Slider:_release(p, cancelled)
    if not self.pressed then return end
    self.pressed = false
    self._pointer = nil
    fire(self, "onRelease", p)
end

----------------------------------------------------------------------------------------------------
-- virtual joystick
----------------------------------------------------------------------------------------------------
-- Options: radius, knobRadius, axis (name for input.axis), deadzone, floating
-- (appears where the finger lands, inside the widget's rectangle), showIdle.
-- Output: w.axisX, w.axisY in -1..1 (y grows down). Callbacks:
-- onPress(w, p), onChange(w, x, y), onRelease(w, p)

local Joystick = newClass("joystick")
Joystick.interactive = true

function Joystick:measure(pw, ph)
    local r = self.radius
    if self.floating then
        self._w = resolve(self.w, pw, r * 4)
        self._h = resolve(self.h, ph, r * 4)
    else
        self._w, self._h = r * 2, r * 2
    end
end

function Joystick:getCenter()
    if self.floating and self.active then return self._cx, self._cy end
    return self._x + self._w / 2, self._y + self._h / 2
end

function Joystick:hitTest(vx, vy)
    if self.floating then return self:contains(vx, vy) end
    local cx, cy = self._x + self._w / 2, self._y + self._h / 2
    local r = self.radius * 1.25 + (self.hitPadding or 0)
    local dx, dy = vx - cx, vy - cy
    return dx * dx + dy * dy <= r * r
end

function Joystick:_apply(p)
    local cx, cy = self:getCenter()
    local dx, dy = (p.x - cx) / self.radius, (p.y - cy) / self.radius
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 1 then dx, dy, len = dx / len, dy / len, 1 end
    self.knobX, self.knobY = dx, dy

    local ox, oy = 0, 0
    local dz = self.deadzone
    if len > dz then
        local s = (len - dz) / (1 - dz) / len
        ox, oy = dx * s, dy * s
    end
    if ox ~= self.axisX or oy ~= self.axisY then
        self.axisX, self.axisY = ox, oy
        if self.axis then input.setVirtualAxis(self.axis, self.id, ox, oy) end
        fire(self, "onChange", ox, oy)
    end
end

function Joystick:_press(p)
    if not self:isEnabled() then return end
    self.active = true
    self._pointer = p
    if self.floating then
        local x, y, w, h = self:getRect()
        local r = self.radius
        self._cx = w > 2 * r and clamp(p.x, x + r, x + w - r) or x + w / 2
        self._cy = h > 2 * r and clamp(p.y, y + r, y + h - r) or y + h / 2
    end
    fire(self, "onPress", p)
    self:_apply(p)
end

function Joystick:_move(p)
    if self.active then self:_apply(p) end
end

function Joystick:_release(p, cancelled)
    if not self.active then return end
    self.active = false
    self._pointer = nil
    self.knobX, self.knobY = 0, 0
    if self.axisX ~= 0 or self.axisY ~= 0 then
        self.axisX, self.axisY = 0, 0
        fire(self, "onChange", 0, 0)
    end
    if self.axis then input.setVirtualAxis(self.axis, self.id, 0, 0) end
    fire(self, "onRelease", p)
end

function Joystick:getAxis() return self.axisX, self.axisY end

----------------------------------------------------------------------------------------------------
-- touchpad: drag area (camera look). Taps are forwarded to 3D picking.
----------------------------------------------------------------------------------------------------
-- Options: delta (name for input.delta), tapSlop, pickTaps, showArea.
-- Callbacks: onPress(w, p), onDrag(w, dx, dy, p), onTap(w, p), onRelease(w, p)

local Touchpad = newClass("touchpad")
Touchpad.interactive = true

function Touchpad:measure(pw, ph)
    self._w = resolve(self.w, pw, pw)
    self._h = resolve(self.h, ph, ph)
end

function Touchpad:_press(p)
    if not self:isEnabled() then return end
    self.pressed = true
    self._pointer = p
    self._moved = false
    fire(self, "onPress", p)
end

function Touchpad:_move(p)
    if not self.pressed then return end
    local slop = self.tapSlop or 12
    local ddx, ddy = p.x - p.sx, p.y - p.sy
    if ddx * ddx + ddy * ddy > slop * slop then self._moved = true end
    if self.delta then input.addDelta(self.delta, p.dx, p.dy) end
    fire(self, "onDrag", p.dx, p.dy, p)
end

function Touchpad:_release(p, cancelled)
    if not self.pressed then return end
    self.pressed = false
    self._pointer = nil
    fire(self, "onRelease", p)
    if not cancelled and not self._moved then
        fire(self, "onTap", p)
        if self.pickTaps ~= false and widgets.tapHandler then widgets.tapHandler(p) end
    end
end

----------------------------------------------------------------------------------------------------
-- creation
----------------------------------------------------------------------------------------------------

function widgets.create(kind, opts)
    local cls = classes[kind]
    local w = setmetatable({}, cls)
    local kids
    for k, v in pairs(opts or {}) do
        if k == "children" then kids = v else w[k] = v end
    end

    seq = seq + 1
    w._seq = seq
    w.id = w.id or w.name or (kind .. seq)
    w.anchor = w.anchor or "top-left"
    w.x, w.y = w.x or 0, w.y or 0
    if w.visible == nil then w.visible = true end
    w.alpha = w.alpha or 1
    w._alpha = 1
    w._x, w._y, w._w, w._h = 0, 0, 0, 0
    w.z = w.z or 0
    w.children = {}

    if kind == "joystick" then
        w.radius = w.radius or 70
        w.knobRadius = w.knobRadius or w.radius * 0.45
        w.deadzone = w.deadzone or 0.08
        w.axis = w.axis or w.name
        w.knobX, w.knobY, w.axisX, w.axisY = 0, 0, 0, 0
        w._cx, w._cy = 0, 0
    elseif kind == "slider" then
        w.min, w.max = w.min or 0, w.max or 1
        w.value = w.value or w.min
    elseif kind == "bar" then
        w.min, w.max = w.min or 0, w.max or 1
        w.value = w.value or w.min
    elseif kind == "toggle" then
        w.value = w.value and true or false
    end
    if (kind == "slider") and w.hitPadding == nil then w.hitPadding = 10 end

    if not w.parent then
        w.layer = w.layer or "default"
        widgets.getLayer(w.layer)
        widgets.roots[#widgets.roots + 1] = w
    else
        local parent = w.parent
        w.parent = nil
        parent:add(w)
    end

    if kids then
        for _, c in ipairs(kids) do w:add(c) end
    end
    widgets.dirty = true
    return w
end

----------------------------------------------------------------------------------------------------
-- layout, drawing, hit testing
----------------------------------------------------------------------------------------------------

local function layoutNode(w, px, py, pw, ph, placed)
    if not w.visible then return end
    if not placed then
        w:measure(pw, ph)
        layout.place(w, px, py, pw, ph)
    end
    local kids = w.children
    if #kids == 0 then return end

    if w.stack then
        local pad, gap = w.padding or 12, w.spacing or 8
        local top = w:contentTop()
        local ix, iy = w._x + pad, w._y + pad + top
        local iw, ih = w._w - pad * 2, w._h - pad * 2 - top
        local vertical = w.stack ~= "horizontal"
        local align = w.itemAlign or "center"
        local cursor = 0
        for _, k in ipairs(kids) do
            if k.visible then
                k:measure(iw, ih)
                local cross = vertical and iw or ih
                local size = vertical and k._w or k._h
                local off = 0
                if align == "center" then off = (cross - size) / 2
                elseif align == "end" then off = cross - size end
                if vertical then
                    k._x, k._y = ix + off + k.x, iy + cursor + k.y
                    cursor = cursor + k._h + gap
                else
                    k._x, k._y = ix + cursor + k.x, iy + off + k.y
                    cursor = cursor + k._w + gap
                end
                layoutNode(k, 0, 0, 0, 0, true)
            end
        end
    else
        for _, k in ipairs(kids) do
            layoutNode(k, w._x, w._y, w._w, w._h)
        end
    end
end

local function sortRoots(a, b)
    local la, lb = widgets.layers[a.layer].order, widgets.layers[b.layer].order
    if la ~= lb then return la < lb end
    if a.z ~= b.z then return a.z < b.z end
    return a._seq < b._seq
end

function widgets.layoutAll()
    local s = widgets.sorted
    for i = #s, 1, -1 do s[i] = nil end
    for i, w in ipairs(widgets.roots) do s[i] = w end
    table.sort(s, sortRoots)
    local px, py, pw, ph = layout.safeX, layout.safeY, layout.safeW, layout.safeH
    for _, w in ipairs(s) do layoutNode(w, px, py, pw, ph) end
    widgets.dirty = false
end

local function updateNode(w, dt)
    if not w.visible then return end
    if w.onUpdate then w.onUpdate(w, dt) end
    for _, k in ipairs(w.children) do updateNode(k, dt) end
end

function widgets.update(dt)
    for _, w in ipairs(widgets.sorted) do
        if widgets.layers[w.layer].visible then updateNode(w, dt) end
    end
end

local function drawNode(w, alpha, debug)
    if not w.visible then return end
    w._alpha = alpha * w.alpha
    w:render()
    if debug then
        love.graphics.setColor(1, 0.2, 0.8, 0.8)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", w._x, w._y, w._w, w._h)
    end
    for _, k in ipairs(w.children) do drawNode(k, w._alpha, debug) end
end

function widgets.draw(debug)
    for _, w in ipairs(widgets.sorted) do
        local l = widgets.layers[w.layer]
        if l.visible then drawNode(w, l.alpha, debug) end
    end
end

local function hitNode(w, vx, vy)
    if not w.visible then return nil end
    for i = #w.children, 1, -1 do
        local r = hitNode(w.children[i], vx, vy)
        if r then return r end
    end
    if (w.interactive or w.block) and w:hitTest(vx, vy) then return w end
end

-- topmost interactive/blocking widget at a virtual position
function widgets.hitTest(vx, vy)
    local s = widgets.sorted
    for i = #s, 1, -1 do
        local w = s[i]
        if widgets.layers[w.layer].visible then
            local r = hitNode(w, vx, vy)
            if r then return r end
        end
    end
end

function widgets.destroyAll()
    for i = #widgets.roots, 1, -1 do widgets.roots[i]:destroy() end
end

return widgets
