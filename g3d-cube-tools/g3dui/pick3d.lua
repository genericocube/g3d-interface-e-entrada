-- g3dui/pick3d.lua
-- Click / touch / hover on 3D models, plus world -> screen projection.
--
-- Works with g3d models (needs `model.verts` and `model.matrix`) and with the
-- g3d camera (`camera.viewMatrix` / `camera.projectionMatrix`, 4x4 row-major).
-- Unlike g3d's own `model:rayIntersection`, the full model matrix is used, so
-- rotated models are picked correctly.
--
-- Note: `model:compress()` throws `model.verts` away. Models that were
-- compressed cannot be picked unless you pass the vertex table in the options
-- (`pick3d.add(model, { verts = originalVerts })`).

local layout = require((...):match("^(.*)%.[^.]+$") .. ".layout")

local pick3d = {
    camera = nil,        -- set with ui.setup{ camera = g3d.camera } (auto-detects package.loaded.g3d)
    viewport = nil,      -- optional {x, y, w, h} in window pixels (default: whole window)
    enabled = true,
    hoverEnabled = true, -- raycast under the mouse every frame
    buttons = { [1] = true }, -- mouse buttons that can pick (touches always can)
    entries = {},
    hovered = nil,       -- current hovered entry
}

local EPS = 1e-9

local function call(fn, ...)
    if fn then return fn(...) end
end

----------------------------------------------------------------------------------------------------
-- camera and matrices
----------------------------------------------------------------------------------------------------

local function getCamera()
    if pick3d.camera then return pick3d.camera end
    -- auto-detect g3d wherever it was required from
    for _, m in pairs(package.loaded) do
        if type(m) == "table" and type(rawget(m, "_VERSION")) == "string"
           and m._VERSION:find("^g3d") and type(rawget(m, "camera")) == "table" then
            pick3d.camera = m.camera
            return m.camera
        end
    end
    return nil
end

local function getViewport()
    local v = pick3d.viewport
    if v then return v[1], v[2], v[3], v[4] end
    local w, h = love.graphics.getDimensions()
    return 0, 0, w, h
end

-- row-major flat 4x4 product a*b
local function mul4(a, b)
    local r = {}
    for i = 0, 3 do
        for j = 0, 3 do
            local s = 0
            for k = 0, 3 do
                s = s + a[i * 4 + k + 1] * b[k * 4 + j + 1]
            end
            r[i * 4 + j + 1] = s
        end
    end
    return r
end

-- general 4x4 inverse (Gauss-Jordan with partial pivoting), row-major flat
local function inv4(m)
    local a = {}
    for i = 0, 3 do
        a[i] = {}
        for j = 0, 3 do
            a[i][j] = m[i * 4 + j + 1]
            a[i][j + 4] = (i == j) and 1 or 0
        end
    end
    for col = 0, 3 do
        local pivot, best = col, math.abs(a[col][col])
        for r = col + 1, 3 do
            local v = math.abs(a[r][col])
            if v > best then pivot, best = r, v end
        end
        if best < 1e-14 then return nil end
        a[col], a[pivot] = a[pivot], a[col]
        local d = a[col][col]
        for j = 0, 7 do a[col][j] = a[col][j] / d end
        for r = 0, 3 do
            if r ~= col then
                local f = a[r][col]
                if f ~= 0 then
                    for j = 0, 7 do a[r][j] = a[r][j] - f * a[col][j] end
                end
            end
        end
    end
    local out = {}
    for i = 0, 3 do
        for j = 0, 3 do out[i * 4 + j + 1] = a[i][j + 4] end
    end
    return out
end

local function normalize(x, y, z)
    local l = math.sqrt(x * x + y * y + z * z)
    if l < EPS then return 0, 0, 0 end
    return x / l, y / l, z / l
end

----------------------------------------------------------------------------------------------------
-- screen <-> world
----------------------------------------------------------------------------------------------------

-- Ray through a window pixel.
-- returns ox, oy, oz, dx, dy, dz  (direction is normalized), or nil
function pick3d.ray(px, py)
    local cam = getCamera()
    if not cam or not cam.viewMatrix or not cam.projectionMatrix then return nil end

    local vx, vy, vw, vh = getViewport()
    local ndcX = ((px - vx) / vw) * 2 - 1
    local ndcY = 1 - ((py - vy) / vh) * 2

    local inv = inv4(mul4(cam.projectionMatrix, cam.viewMatrix))
    if not inv then return nil end

    local function unproject(z)
        local x = inv[1] * ndcX + inv[2] * ndcY + inv[3] * z + inv[4]
        local y = inv[5] * ndcX + inv[6] * ndcY + inv[7] * z + inv[8]
        local zz = inv[9] * ndcX + inv[10] * ndcY + inv[11] * z + inv[12]
        local w = inv[13] * ndcX + inv[14] * ndcY + inv[15] * z + inv[16]
        if math.abs(w) < EPS then return nil end
        return x / w, y / w, zz / w
    end

    local x0, y0, z0 = unproject(-1)
    local x1, y1, z1 = unproject(1)
    if not x0 or not x1 then return nil end

    local dx, dy, dz = normalize(x1 - x0, y1 - y0, z1 - z0)
    if dx == 0 and dy == 0 and dz == 0 then return nil end
    return x0, y0, z0, dx, dy, dz
end

-- World point -> window pixel. Returns px, py, depth (ndc z) or nil when the
-- point is behind the camera.
function pick3d.worldToWindow(x, y, z)
    local cam = getCamera()
    if not cam or not cam.viewMatrix or not cam.projectionMatrix then return nil end
    local v, p = cam.viewMatrix, cam.projectionMatrix

    local ex = v[1] * x + v[2] * y + v[3] * z + v[4]
    local ey = v[5] * x + v[6] * y + v[7] * z + v[8]
    local ez = v[9] * x + v[10] * y + v[11] * z + v[12]

    local cx = p[1] * ex + p[2] * ey + p[3] * ez + p[4]
    local cy = p[5] * ex + p[6] * ey + p[7] * ez + p[8]
    local cz = p[9] * ex + p[10] * ey + p[11] * ez + p[12]
    local cw = p[13] * ex + p[14] * ey + p[15] * ez + p[16]

    if cw <= EPS then return nil end

    local nx, ny, nz = cx / cw, cy / cw, cz / cw
    local vx, vy, vw, vh = getViewport()
    return vx + (nx * 0.5 + 0.5) * vw, vy + (1 - (ny * 0.5 + 0.5)) * vh, nz
end

-- World point -> virtual UI units (what widgets use). Returns x, y or nil.
function pick3d.worldToVirtual(x, y, z)
    local px, py = pick3d.worldToWindow(x, y, z)
    if not px then return nil end
    return layout.toVirtual(px, py)
end

----------------------------------------------------------------------------------------------------
-- ray vs model
----------------------------------------------------------------------------------------------------

local warned = {}

local function getVerts(entry)
    local verts = entry.verts or entry.object.verts
    if not verts and not warned[entry] then
        warned[entry] = true
        print("[g3dui] pick3d: object has no `verts` (compressed model?). Pass { verts = ... } to pick3d.add.")
    end
    return verts
end

local identity = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }

local function getMatrix(entry)
    return entry.matrix or entry.object.matrix or identity
end

-- local bounding sphere, cached per vertex table
local function getBounds(entry, verts)
    local b = entry._bounds
    if b and entry._boundsVerts == verts and entry._boundsCount == #verts then return b end

    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    for i = 1, #verts do
        local v = verts[i]
        local x, y, z = v[1], v[2], v[3]
        if x < minX then minX = x end
        if y < minY then minY = y end
        if z < minZ then minZ = z end
        if x > maxX then maxX = x end
        if y > maxY then maxY = y end
        if z > maxZ then maxZ = z end
    end
    local cx, cy, cz = (minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2
    local r2 = 0
    for i = 1, #verts do
        local v = verts[i]
        local dx, dy, dz = v[1] - cx, v[2] - cy, v[3] - cz
        local d = dx * dx + dy * dy + dz * dz
        if d > r2 then r2 = d end
    end
    b = { cx = cx, cy = cy, cz = cz, r = math.sqrt(r2) }
    entry._bounds, entry._boundsVerts, entry._boundsCount = b, verts, #verts
    return b
end

-- Closest hit of a world ray against one entry. Returns a hit table or nil.
local function rayEntry(entry, ox, oy, oz, dx, dy, dz)
    local verts = getVerts(entry)
    if not verts or #verts < 3 then return nil end
    local m = getMatrix(entry)

    -- 3x3 part (A) and translation (t) of the affine model matrix
    local a11, a12, a13, tx = m[1], m[2], m[3], m[4]
    local a21, a22, a23, ty = m[5], m[6], m[7], m[8]
    local a31, a32, a33, tz = m[9], m[10], m[11], m[12]

    -- cheap bounding sphere rejection
    local b = getBounds(entry, verts)
    local wcx = a11 * b.cx + a12 * b.cy + a13 * b.cz + tx
    local wcy = a21 * b.cx + a22 * b.cy + a23 * b.cz + ty
    local wcz = a31 * b.cx + a32 * b.cy + a33 * b.cz + tz
    local sx = math.sqrt(a11 * a11 + a21 * a21 + a31 * a31)
    local sy = math.sqrt(a12 * a12 + a22 * a22 + a32 * a32)
    local sz = math.sqrt(a13 * a13 + a23 * a23 + a33 * a33)
    local wr = b.r * math.max(sx, sy, sz)

    local ocx, ocy, ocz = ox - wcx, oy - wcy, oz - wcz
    local bb = ocx * dx + ocy * dy + ocz * dz
    local cc = ocx * ocx + ocy * ocy + ocz * ocz - wr * wr
    if cc > 0 and bb > 0 then return nil end
    if bb * bb - cc < 0 then return nil end

    -- inverse of A (adjugate / determinant)
    local c11 = a22 * a33 - a23 * a32
    local c12 = a13 * a32 - a12 * a33
    local c13 = a12 * a23 - a13 * a22
    local det = a11 * c11 + a21 * c12 + a31 * c13
    if math.abs(det) < EPS then return nil end
    local id = 1 / det
    local i11, i12, i13 = c11 * id, c12 * id, c13 * id
    local i21 = (a23 * a31 - a21 * a33) * id
    local i22 = (a11 * a33 - a13 * a31) * id
    local i23 = (a13 * a21 - a11 * a23) * id
    local i31 = (a21 * a32 - a22 * a31) * id
    local i32 = (a12 * a31 - a11 * a32) * id
    local i33 = (a11 * a22 - a12 * a21) * id

    -- ray in model space (the parameter t is the same in both spaces)
    local px, py, pz = ox - tx, oy - ty, oz - tz
    local lox = i11 * px + i12 * py + i13 * pz
    local loy = i21 * px + i22 * py + i23 * pz
    local loz = i31 * px + i32 * py + i33 * pz
    local ldx = i11 * dx + i12 * dy + i13 * dz
    local ldy = i21 * dx + i22 * dy + i23 * dz
    local ldz = i31 * dx + i32 * dy + i33 * dz

    local bestT, bestTri
    local bnx, bny, bnz
    for i = 1, #verts - 2, 3 do
        local v0, v1, v2 = verts[i], verts[i + 1], verts[i + 2]
        local x0, y0, z0 = v0[1], v0[2], v0[3]
        local e1x, e1y, e1z = v1[1] - x0, v1[2] - y0, v1[3] - z0
        local e2x, e2y, e2z = v2[1] - x0, v2[2] - y0, v2[3] - z0

        -- Moller-Trumbore (both faces)
        local hx = ldy * e2z - ldz * e2y
        local hy = ldz * e2x - ldx * e2z
        local hz = ldx * e2y - ldy * e2x
        local det3 = e1x * hx + e1y * hy + e1z * hz
        if det3 > EPS or det3 < -EPS then
            local f = 1 / det3
            local sx_, sy_, sz_ = lox - x0, loy - y0, loz - z0
            local u = f * (sx_ * hx + sy_ * hy + sz_ * hz)
            if u >= 0 and u <= 1 then
                local qx = sy_ * e1z - sz_ * e1y
                local qy = sz_ * e1x - sx_ * e1z
                local qz = sx_ * e1y - sy_ * e1x
                local v = f * (ldx * qx + ldy * qy + ldz * qz)
                if v >= 0 and u + v <= 1 then
                    local t = f * (e2x * qx + e2y * qy + e2z * qz)
                    if t > 0 and (not bestT or t < bestT) then
                        bestT, bestTri = t, i
                        bnx = e1y * e2z - e1z * e2y
                        bny = e1z * e2x - e1x * e2z
                        bnz = e1x * e2y - e1y * e2x
                    end
                end
            end
        end
    end

    if not bestT then return nil end

    -- model-space normal -> world space (inverse transpose), facing the viewer
    local wnx = i11 * bnx + i21 * bny + i31 * bnz
    local wny = i12 * bnx + i22 * bny + i32 * bnz
    local wnz = i13 * bnx + i23 * bny + i33 * bnz
    wnx, wny, wnz = normalize(wnx, wny, wnz)
    if wnx * dx + wny * dy + wnz * dz > 0 then
        wnx, wny, wnz = -wnx, -wny, -wnz
    end

    return {
        x = ox + dx * bestT, y = oy + dy * bestT, z = oz + dz * bestT,
        nx = wnx, ny = wny, nz = wnz,
        distance = bestT,
        triangle = (bestTri - 1) / 3 + 1,
        entry = entry,
        object = entry.object,
    }
end

----------------------------------------------------------------------------------------------------
-- registration
----------------------------------------------------------------------------------------------------

-- Make a model clickable.
--
-- pick3d.add(model, {
--     name = "crate",                   -- optional, for your own use
--     onPress      = function(model, hit, pointer) end,
--     onRelease    = function(model, hit, pointer) end,
--     onClick      = function(model, hit, pointer) end, -- pressed and released on it
--     onDrag       = function(model, hit, pointer) end, -- hit is nil off the model
--     onHoverStart = function(model, hit) end,
--     onHoverEnd   = function(model) end,
--     hover = true,                     -- false: never raycast it for hover
--     enabled = true,
--     verts = nil, matrix = nil,        -- override model.verts / model.matrix
-- })
function pick3d.add(object, opts)
    local entry = {}
    if opts then
        for k, v in pairs(opts) do entry[k] = v end
    end
    entry.object = object
    if entry.enabled == nil then entry.enabled = true end
    pick3d.entries[#pick3d.entries + 1] = entry
    return entry
end

-- accepts the model or the entry returned by add()
function pick3d.remove(objectOrEntry)
    for i = #pick3d.entries, 1, -1 do
        local e = pick3d.entries[i]
        if e == objectOrEntry or e.object == objectOrEntry then
            if pick3d.hovered == e then pick3d.hovered = nil end
            table.remove(pick3d.entries, i)
        end
    end
end

function pick3d.clear()
    pick3d.entries = {}
    pick3d.hovered = nil
end

function pick3d.getEntry(object)
    for _, e in ipairs(pick3d.entries) do
        if e.object == object then return e end
    end
end

function pick3d.isHovered(object)
    local h = pick3d.hovered
    return h ~= nil and h.object == object
end

----------------------------------------------------------------------------------------------------
-- queries
----------------------------------------------------------------------------------------------------

-- Closest pickable entry under a window pixel. Returns entry, hit (or nil).
-- `filter(entry)` may reject entries.
function pick3d.raycast(px, py, filter)
    if not pick3d.enabled then return nil end
    local ox, oy, oz, dx, dy, dz = pick3d.ray(px, py)
    if not ox then return nil end

    local bestEntry, bestHit
    for _, e in ipairs(pick3d.entries) do
        if e.enabled and (not filter or filter(e)) then
            local hit = rayEntry(e, ox, oy, oz, dx, dy, dz)
            if hit and (not bestHit or hit.distance < bestHit.distance) then
                bestEntry, bestHit = e, hit
            end
        end
    end
    return bestEntry, bestHit
end

-- true when something pickable is under the pixel
function pick3d.testPoint(px, py)
    if #pick3d.entries == 0 then return false end
    return pick3d.raycast(px, py) ~= nil
end

----------------------------------------------------------------------------------------------------
-- pointer handling (called by g3dui when the UI did not consume the pointer)
----------------------------------------------------------------------------------------------------

local function allowed(p)
    return p.source ~= "mouse" or pick3d.buttons[p.button] == true
end

function pick3d.pressed(p)
    if not pick3d.enabled or not allowed(p) then return false end
    local entry, hit = pick3d.raycast(p.px, p.py)
    if not entry then return false end
    p.pick = { entry = entry, hit = hit }
    call(entry.onPress, entry.object, hit, p)
    return true
end

function pick3d.moved(p)
    local pk = p.pick
    if not pk then return end
    local entry = pk.entry
    local hit
    local ox, oy, oz, dx, dy, dz = pick3d.ray(p.px, p.py)
    if ox then hit = rayEntry(entry, ox, oy, oz, dx, dy, dz) end
    if hit then pk.hit = hit end
    call(entry.onDrag, entry.object, hit, p)
end

function pick3d.released(p)
    local pk = p.pick
    if not pk then return end
    p.pick = nil
    local entry = pk.entry
    local top, hit = pick3d.raycast(p.px, p.py)
    local onIt = (top == entry)
    call(entry.onRelease, entry.object, onIt and hit or nil, p)
    if onIt and entry.enabled then
        call(entry.onClick, entry.object, hit, p)
    end
end

-- Hover under the mouse. Pass nil px/py (or blocked = true) to clear it.
function pick3d.updateHover(px, py, blocked)
    local newEntry, hit
    if pick3d.enabled and pick3d.hoverEnabled and px and not blocked then
        newEntry, hit = pick3d.raycast(px, py, function(e) return e.hover ~= false end)
    end

    local old = pick3d.hovered
    if newEntry ~= old then
        pick3d.hovered = newEntry
        if old then
            old.hovered = false
            call(old.onHoverEnd, old.object)
        end
        if newEntry then
            newEntry.hovered = true
            call(newEntry.onHoverStart, newEntry.object, hit)
        end
    end
    return newEntry, hit
end

return pick3d
