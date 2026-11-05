-- g3d-interface-e-entrada demo
--
-- Shows: keyboard, mouse (hover / click / right-drag), touch (multitouch),
-- on-screen joystick, virtual buttons, gamepad, unified actions and axes,
-- layers, custom drawing, themes, sliders / toggles and clicking 3D objects.
--
-- Run with:  love .

local g3d = require("g3d")
local ui = require "g3d-cube-tools.g3dui"

local isMobile = (love.system.getOS() == "Android" or love.system.getOS() == "iOS")

----------------------------------------------------------------------------------------------------
-- tiny 3D helpers (no assets needed)
----------------------------------------------------------------------------------------------------

local whiteTexture

local function box(hx, hy, hz, c)
    local verts = {}
    local function face(shade, a, b, cc, d)
        local function v(p)
            return { p[1] * hx, p[2] * hy, p[3] * hz, 0, 0, 0, 0, 0, c[1] * shade, c[2] * shade, c[3] * shade, 1 }
        end
        verts[#verts + 1], verts[#verts + 2], verts[#verts + 3] = v(a), v(b), v(cc)
        verts[#verts + 1], verts[#verts + 2], verts[#verts + 3] = v(a), v(cc), v(d)
    end
    face(1.00, { -1, -1, 1 }, { 1, -1, 1 }, { 1, 1, 1 }, { -1, 1, 1 })
    face(0.50, { -1, -1, -1 }, { -1, 1, -1 }, { 1, 1, -1 }, { 1, -1, -1 })
    face(0.80, { -1, -1, -1 }, { 1, -1, -1 }, { 1, -1, 1 }, { -1, -1, 1 })
    face(0.80, { -1, 1, -1 }, { -1, 1, 1 }, { 1, 1, 1 }, { 1, 1, -1 })
    face(0.65, { -1, -1, -1 }, { -1, -1, 1 }, { -1, 1, 1 }, { -1, 1, -1 })
    face(0.65, { 1, -1, -1 }, { 1, 1, -1 }, { 1, 1, 1 }, { 1, -1, 1 })
    return verts
end

----------------------------------------------------------------------------------------------------
-- game state
----------------------------------------------------------------------------------------------------

local ground, player, cubes = nil, nil, {}
local px, py, pz, vz = 0, 0, 0, 0
local yaw, pitch, dist = -math.pi / 2, 0.55, 13
local sensitivity = 1
local hp = 100
local lastEvent = "click a cube!"

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function addCube(name, x, y, color, damage)
    local cube = { name = name, color = color, hover = false, clicks = 0 }
    cube.model = g3d.newModel(box(1, 1, 1, color), whiteTexture, { x, y, 1 })

    -- make the model clickable (mouse, touch and touchpad taps all work)
    ui.clickable(cube.model, {
        onHoverStart = function() cube.hover = true end,
        onHoverEnd = function() cube.hover = false end,
        onClick = function(_, hit, pointer)
            cube.clicks = cube.clicks + 1
            lastEvent = ("%s cube clicked via %s  (hit %.1f, %.1f, %.1f)"):format(
                name, pointer.source, hit.x, hit.y, hit.z)
            if damage then
                hp = hp - damage
                if hp <= 0 then hp = 100 end
            end
        end,
    })
    cubes[#cubes + 1] = cube
end

local function resetGame()
    px, py, pz, vz = 0, 0, 0, 0
    yaw, pitch = -math.pi / 2, 0.55
    hp = 100
    lastEvent = "game reset"
end

----------------------------------------------------------------------------------------------------
-- UI
----------------------------------------------------------------------------------------------------

local function buildUI()
    -- layers: "touch" sits UNDER the HUD so HUD buttons always win
    ui.layer("touch", { order = -5, visible = isMobile })
    ui.layer("hud", { order = 0 })
    ui.layer("menu", { order = 20, visible = false })

    ------------------------------------------------------------------ touch controls
    -- joystick: `name` is the axis name, read with ui.axis("move")
    ui.joystick{ layer = "touch", name = "move", anchor = "bottom-left", x = 40, y = 40, radius = 90 }

    -- drag area for the camera (right part of the screen), feeds ui.delta("look")
    ui.touchpad{ layer = "touch", name = "lookpad", delta = "look", anchor = "right", w = "55%", h = "100%", z = -1 }

    -- fully custom look: pass your own `draw` function (it draws in virtual units)
    ui.button{
        layer = "touch", anchor = "bottom-right", x = 60, y = 60, w = 120, h = 120,
        text = "Jump", action = "jump", -- holds the "jump" action while pressed
        draw = function(w)
            local cx, cy = w:getCenter()
            local t = w.pressed and 0.55 or 1
            love.graphics.setColor(1, 0.55 * t, 0.15 * t, 0.55 * w._alpha)
            love.graphics.circle("fill", cx, cy, w._w / 2)
            love.graphics.setColor(1, 1, 1, w._alpha)
            love.graphics.setLineWidth(3)
            love.graphics.circle("line", cx, cy, w._w / 2)
            ui.theme.print(w, w:getText(), w._x, cy - 11, w._w, "center")
        end,
    }

    ------------------------------------------------------------------ HUD
    ui.label{
        layer = "hud", anchor = "top-left", x = 16, y = 16, shadow = true,
        text = function()
            local mx, my = ui.axis("move")
            local lx, ly = ui.delta("look")
            return ("FPS: %d\nmove axis: %.2f, %.2f\nlook delta: %.1f, %.1f\njump: %s    orbit (right mouse): %s\n%s")
                :format(love.timer.getFPS(), mx, my, lx, ly,
                    ui.down("jump") and "DOWN" or "-", ui.down("orbit") and "DOWN" or "-", lastEvent)
        end,
    }

    ui.bar{
        layer = "hud", anchor = "top", y = 16, w = 320, h = 26, max = 100,
        value = function() return hp end,
        text = function() return ("HP %d / 100  (red cube hurts)"):format(hp) end,
        style = { fill = { 0.85, 0.2, 0.25, 1 } },
    }

    ui.button{
        layer = "hud", anchor = "top-right", x = 16, y = 16, w = 110, h = 44, text = "Menu",
        onClick = function() ui.toggleLayer("menu") end,
    }

    ui.label{
        layer = "hud", anchor = "bottom", y = 10, w = "90%", align = "center", shadow = true,
        text = "WASD / arrows / left stick / joystick: move   |   Space / A / Jump: jump   |   " ..
               "right-drag / touch-drag / right stick: look   |   Esc / Start: menu",
    }

    -- text that follows a 3D point (world -> screen projection)
    ui.label{
        layer = "hud", w = 120, align = "center", shadow = true, text = "Player",
        onUpdate = function(w)
            local vx, vy = ui.pick3d.worldToVirtual(px, py, pz + 2.4)
            w.visible = vx ~= nil
            if vx then
                w.x = vx - ui.layout.safeX - w.w / 2
                w.y = vy - ui.layout.safeY - 10
            end
        end,
    }

    ------------------------------------------------------------------ menu
    ui.panel{ layer = "menu", w = "100%", h = "100%", border = false, style = { bg = { 0, 0, 0, 0.55 } } }

    ui.panel{
        layer = "menu", anchor = "center", title = "Paused", stack = "vertical", spacing = 10, padding = 16,
        children = {
            ui.toggle{ text = "Touch controls", value = isMobile,
                onChange = function(_, v) ui.layer("touch", { visible = v }) end },
            ui.toggle{ text = "Light theme", value = false,
                onChange = function(_, v) ui.setTheme(v and "light" or "dark") end },
            ui.label{ text = "Look sensitivity" },
            ui.slider{ w = 260, min = 0.3, max = 2.5, value = 1, onChange = function(_, v) sensitivity = v end },
            ui.label{ text = "Field of view" },
            ui.slider{ w = 260, min = 50, max = 110, step = 1, value = 90, onChange = function(_, v)
                g3d.camera.fov = math.rad(v)
                g3d.camera.updateProjectionMatrix()
            end },
            ui.button{ text = "Resume", w = 260, onClick = function() ui.hideLayer("menu") end },
            ui.button{ text = "Reset", w = 260, onClick = function() resetGame() ui.hideLayer("menu") end },
            ui.button{ text = "Quit", w = 260, onClick = function() love.event.quit() end },
        },
    }
end

----------------------------------------------------------------------------------------------------
-- LÖVE callbacks
----------------------------------------------------------------------------------------------------

function love.load()
    love.graphics.setBackgroundColor(0.55, 0.75, 0.95)

    local data = love.image.newImageData(1, 1)
    data:setPixel(0, 0, 1, 1, 1, 1)
    whiteTexture = love.graphics.newImage(data)

    -- 1) setup + hook: the UI gets the events first; consumed events never reach your callbacks
    ui.setup{ camera = g3d.camera, theme = "dark" }
    ui.hook()

    -- 2) named actions / axes: the same name works with keyboard, gamepad and on-screen controls
    ui.bindAxis("move", {
        left = { "key:a", "key:left" }, right = { "key:d", "key:right" },
        up = { "key:w", "key:up" }, down = { "key:s", "key:down" },
        pad = "left", -- gamepad left stick
    })
    ui.bindAxis("look", { pad = "right" })
    ui.bind("jump", "key:space", "pad:a")
    ui.bind("orbit", "mouse:2")
    ui.bind("menu", "key:escape", "pad:start")

    -- 3) world
    ground = g3d.newModel(box(22, 22, 0.1, { 0.45, 0.62, 0.4 }), whiteTexture, { 0, 0, -0.1 })
    player = g3d.newModel(box(0.6, 0.6, 0.6, { 0.25, 0.45, 0.95 }), whiteTexture)
    addCube("red", 5, 4, { 0.9, 0.25, 0.25 }, 15)
    addCube("green", -5, 6, { 0.3, 0.8, 0.35 })
    addCube("yellow", 8, -4, { 0.95, 0.8, 0.25 })
    addCube("purple", -7, -5, { 0.65, 0.4, 0.85 })

    buildUI()
end

function love.update(dt)
    ui.update(dt) -- first: refreshes input state ("pressed" / "released" / deltas)

    if ui.pressed("menu") then ui.toggleLayer("menu") end
    if ui.isLayerVisible("menu") then return end

    -- camera look: touchpad drag, gamepad stick (right-drag is in love.mousemoved)
    local dx, dy = ui.delta("look")
    local lx, ly = ui.axis("look")
    yaw = yaw - (dx * 0.006 + lx * dt * 2.5) * sensitivity
    pitch = clamp(pitch + (dy * 0.006 + ly * dt * 2) * sensitivity, 0.1, 1.45)

    -- movement relative to the camera
    local ax, ay = ui.axis("move") -- y grows down: "forward" is -ay
    local fx, fy = -math.cos(yaw), -math.sin(yaw)
    local rx, ry = fy, -fx
    px = clamp(px + (fx * -ay + rx * ax) * 8 * dt, -20, 20)
    py = clamp(py + (fy * -ay + ry * ax) * 8 * dt, -20, 20)

    if ui.pressed("jump") and pz <= 0 then vz = 9 end
    vz = vz - 25 * dt
    pz = math.max(0, pz + vz * dt)
    if pz == 0 then vz = 0 end
    player:setTranslation(px, py, pz + 0.6)

    local cp = math.cos(pitch)
    g3d.camera.lookAt(
        px + math.cos(yaw) * cp * dist, py + math.sin(yaw) * cp * dist, pz + 1 + math.sin(pitch) * dist,
        px, py, pz + 1)
end

function love.draw()
    ground:draw()
    player:draw()
    for _, c in ipairs(cubes) do
        if c.hover then love.graphics.setColor(1.35, 1.35, 1.35) else love.graphics.setColor(1, 1, 1) end
        c.model:draw()
    end
    love.graphics.setColor(1, 1, 1)

    ui.draw() -- always last
end

-- Events the UI did not consume arrive here as usual.
function love.mousemoved(x, y, dx, dy)
    if ui.down("orbit") then
        yaw = yaw - dx * 0.008 * sensitivity
        pitch = clamp(pitch + dy * 0.008 * sensitivity, 0.1, 1.45)
    end
end

function love.keypressed(key)
    lastEvent = "key pressed: " .. key
end

function love.resize(w, h)
    g3d.camera.resize(w, h)
end
