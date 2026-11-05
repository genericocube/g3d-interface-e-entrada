# g3d-interface-e-entrada (g3dui)

**English** · [Português](#português)

UI, unified input and 3D picking for [g3d](https://github.com/groverburger/g3d) (LÖVE). Pure Lua, no dependencies, works on **desktop and mobile**.

- **Widgets:** button, joystick (fixed or floating), touchpad (camera look), slider, toggle, label, bar, image, panel (with automatic vertical/horizontal stacking).
- **Fully customizable:** every widget accepts your own `draw` function; colors, fonts and whole widget types can be themed. No fixed style.
- **Unified input:** keyboard, mouse, touch (multitouch), gamepad and on-screen controls feed the same named *actions* and *axes*.
- **Click 3D objects:** hover, press, release, click and drag on g3d models (mouse and touch), plus world → screen projection for labels that follow objects.
- **Layout:** anchors, percent sizes, automatic scaling for any resolution, phone safe-area, layers (HUD / menu / pause...).

Try the demo: install [LÖVE](https://love2d.org) and run `love .` in this folder (a copy of g3d is included).

## Install

Copy the `g3dui/` folder into your project (next to `g3d/`):

```
your-game/
├── g3d/
├── g3dui/
└── main.lua
```

## Quick start

```lua
local g3d = require("g3d")
local ui  = require("g3dui")

function love.load()
    ui.setup{ camera = g3d.camera }   -- camera is only needed for 3D picking
    ui.hook()                         -- the UI receives love events first

    -- actions & axes: same name for keyboard, gamepad and on-screen controls
    ui.bindAxis("move", { left = "key:a", right = "key:d", up = "key:w", down = "key:s", pad = "left" })
    ui.bind("jump", "key:space", "pad:a")

    -- on-screen controls
    ui.joystick{ name = "move", anchor = "bottom-left",  x = 40, y = 40, radius = 90 }
    ui.button{ text = "Jump", action = "jump", anchor = "bottom-right", x = 40, y = 40, w = 120, h = 120 }
end

function love.update(dt)
    ui.update(dt)                     -- first line of love.update
    local mx, my = ui.axis("move")    -- -1..1, y grows DOWN (forward = -my)
    if ui.pressed("jump") then --[[ jump! ]] end
end

function love.draw()
    -- draw your 3D world here
    ui.draw()                         -- always last
end
```

> Call `ui.hook()` inside `love.load`. It wraps `love.handlers`, so you keep writing `love.mousepressed`, `love.keypressed`... normally. Events consumed by the UI (a click on a button or on a clickable 3D model) are **not** forwarded to your callbacks. Prefer manual wiring? Skip `ui.hook()` and call `if ui.mousepressed(x, y, button, istouch) then return end` (same for `mousereleased`, `mousemoved`, `touchpressed`, `touchmoved`, `touchreleased`, `keypressed`, `keyreleased`, `gamepadpressed`, `gamepadreleased`, `gamepadaxis`, `wheelmoved`, `focus`) and `ui.resize(w, h)`.

## Widgets

Every option you pass becomes a field you can change later (`btn.text = "New"`). Callbacks always receive the widget first.

| Constructor | Main options | Callbacks |
|---|---|---|
| `ui.button` | `text`, `action`, `image`, `imagePressed` | `onPress(w,p)`, `onRelease(w,p)`, `onClick(w,p)`, `onDrag(w,p)` |
| `ui.toggle` | `text`, `value` | `onChange(w, value)` |
| `ui.slider` | `min`, `max`, `step`, `value`, `vertical` | `onChange(w, value)` |
| `ui.joystick` | `name`/`axis`, `radius`, `knobRadius`, `deadzone`, `floating`, `showIdle` | `onChange(w, x, y)`, `onPress`, `onRelease` |
| `ui.touchpad` | `delta` (name for `ui.delta`), `tapSlop`, `pickTaps`, `showArea` | `onDrag(w, dx, dy, p)`, `onTap(w, p)` |
| `ui.label` | `text` (string or function), `align`, `w` (wraps), `font`, `shadow` | – |
| `ui.bar` | `value` (number or function), `min`, `max`, `text`, `vertical` | – |
| `ui.image` | `image`, `quad` | – |
| `ui.panel` | `title`, `stack`, `spacing`, `padding`, `itemAlign`, `children` | – |
| `ui.widget` | invisible hotspot (button behavior, no look) | same as button |

Common options: `anchor`, `x`, `y`, `w`, `h`, `layer`, `visible`, `enabled`, `alpha`, `z`, `style`, `draw`, `hitPadding`, `onUpdate(w, dt)`, `onHoverStart(w)`, `onHoverEnd(w)`.
Methods: `w:show()`, `w:hide()`, `w:setEnabled(b)`, `w:setText(t)`, `w:setValue(v, silent)`, `w:getRect()`, `w:getCenter()`, `w:add(child)`, `w:destroy()`.

### Layout

```lua
ui.setup{ refWidth = 1280, refHeight = 720, scaleMode = "fit" }  -- "fit" | "height" | "width" | "none" | number
ui.button{ anchor = "bottom-right", x = 20, y = 20 }  -- 20 units away from the bottom-right corner
ui.panel{ anchor = "center", w = "50%", h = 300 }     -- percent of the parent
```

Anchors: `top-left top top-right left center right bottom-left bottom bottom-right`. For right/bottom anchors `x`/`y` are margins towards the inside; on a centered axis they are offsets from the center. Coordinates are in virtual units and are relative to the phone safe area (the whole window on desktop).

Stacking menus automatically:

```lua
ui.panel{ anchor = "center", title = "Pause", stack = "vertical", spacing = 10, children = {
    ui.button{ text = "Resume", w = 240, onClick = function() ui.hideLayer("menu") end },
    ui.toggle{ text = "Sound", value = true, onChange = function(_, on) end },
}, layer = "menu" }
```

### Layers

```lua
ui.layer("hud",  { order = 0 })
ui.layer("menu", { order = 20, visible = false })
ui.toggleLayer("menu")      -- also: ui.showLayer / ui.hideLayer / ui.isLayerVisible
```

Widgets in hidden layers are not drawn and cannot be touched. Higher `order` is drawn (and clicked) first.

### Custom look

```lua
-- 1) one widget: your own draw function (virtual units, already scaled)
ui.button{ text = "Fire", draw = function(w)
    local cx, cy = w:getCenter()
    love.graphics.setColor(w.pressed and {1, .3, .1} or {1, .6, .1})
    love.graphics.circle("fill", cx, cy, w._w / 2)
    love.graphics.setColor(1, 1, 1)
    ui.theme.print(w, w:getText(), w._x, cy - 10, w._w, "center")
    -- w:drawDefault() draws the default look if you want to add on top of it
end }

-- 2) one widget: colors
ui.button{ text = "Red", style = { bg = {.6, .1, .1, 1}, bgPressed = {.9, .2, .2, 1}, cornerRadius = 0 } }

-- 3) everything: theme
ui.setTheme("light")
ui.setTheme{ colors = { accent = {1, .4, .2, 1} }, cornerRadius = 14,
             draw = { button = function(w) --[[ replaces every default button ]] end } }

-- fonts (sharp at any resolution)
local big = ui.newFont(32, "myfont.ttf")      -- path is optional
ui.label{ text = "Score", font = big }
```

Style keys: `text textDim bg bgHover bgPressed bgDisabled border accent track shadow fill tint cornerRadius`.
Widget state for your draw function: `w.pressed`, `w.hovered`, `w.active` (joystick), `w.value`, `w.knobX/knobY`, `w.axisX/axisY`, `w:isEnabled()`, `w._alpha`.

## Input

Sources are strings: `"key:space"`, `"scan:w"` (scancode), `"mouse:1"`, `"pad:a"`, `"pad:triggerleft"`, `"wheel:up"` (`down`/`left`/`right`). On-screen widgets feed the same system.

```lua
ui.bind("jump", "key:space", "pad:a")        -- action: ui.down / ui.pressed / ui.released("jump")
ui.bindAxis("move", { left = {"key:a", "key:left"}, right = "key:d", up = "key:w", down = "key:s", pad = "left" })
local x, y = ui.axis("move")                 -- keyboard + gamepad stick + on-screen joystick named "move"
local dx, dy = ui.delta("look")              -- drag distance this frame (touchpad with delta = "look")
```

`pressed` / `released` are true for one frame (read them after `ui.update`). Multitouch works: joystick, buttons and touchpad can be used at the same time.

## Clicking 3D objects

```lua
local crate = g3d.newModel("crate.obj", "crate.png", {5, 0, 1})

ui.clickable(crate, {
    onHoverStart = function(model, hit) end,
    onHoverEnd   = function(model) end,
    onPress      = function(model, hit, pointer) end,
    onRelease    = function(model, hit, pointer) end,
    onClick      = function(model, hit, pointer) print(hit.x, hit.y, hit.z, hit.distance) end,
    onDrag       = function(model, hit, pointer) end,   -- hit is nil when the pointer left the model
    consume      = true,                                 -- false: the click also reaches your own callbacks
})
```

- `hit` has `x y z` (world point), `nx ny nz` (normal), `distance`, `triangle`.
- The full model matrix is used, so rotated and scaled models are picked correctly. Mouse and touch both work (`pointer.source` is `"mouse"` or `"touch"`).
- The camera is auto-detected; pass `ui.setup{ camera = ... }` to be explicit. If you render to a sub-area of the window use `ui.setup{ viewport = {x, y, w, h} }` (window pixels).
- Remove with `ui.pick3d.remove(model)`. A model that was `:compress()`ed has no `verts`; pass `verts = originalVerts` in the options.
- Is the pointer over the UI? `ui.isOverUI(x, y)` (window pixels).
- **Text that follows a 3D point:** `local vx, vy = ui.pick3d.worldToVirtual(x, y, z)` (nil when behind the camera); see the demo.
- A full-screen touchpad forwards short taps to 3D picking automatically, so one finger can look around *and* tap objects.

## Notes

- Touch positions are used as LÖVE reports them (pixels). Mouse events emulated from touches are ignored by the UI.
- `ui.debug = true` outlines every widget.
- Not included yet: text input, scroll lists, gamepad menu navigation.

## License

MIT. `g3d/` is © groverburger (MIT, included only so the demo runs out of the box).

---

# Português

UI, entrada unificada e clique em objetos 3D para o [g3d](https://github.com/groverburger/g3d) (LÖVE). Lua puro, sem dependências, funciona em **PC e celular**.

- **Widgets:** botão, joystick (fixo ou flutuante), touchpad (olhar com a câmera), slider, toggle, texto, barra, imagem, painel (com empilhamento automático).
- **Totalmente personalizável:** todo widget aceita sua própria função `draw`; cores, fontes e tipos inteiros de widget podem ser trocados por tema. Não existe estilo fixo.
- **Entrada unificada:** teclado, mouse, toque (multitouch), gamepad e controles na tela alimentam as mesmas *ações* e *eixos* nomeados.
- **Clique em objetos 3D:** hover, pressionar, soltar, clicar e arrastar em modelos do g3d (mouse e toque), além de projeção mundo → tela para textos que seguem objetos.
- **Layout:** âncoras, tamanhos em %, escala automática para qualquer resolução, área segura de celular (notch) e camadas (HUD / menu / pausa...).

Para testar a demo: instale o [LÖVE](https://love2d.org) e rode `love .` nesta pasta (uma cópia do g3d já está incluída).

## Instalação

Copie a pasta `g3dui/` para o seu projeto (junto da pasta `g3d/`):

```
seu-jogo/
├── g3d/
├── g3dui/
└── main.lua
```

## Começo rápido

```lua
local g3d = require("g3d")
local ui  = require("g3dui")

function love.load()
    ui.setup{ camera = g3d.camera }   -- a câmera só é necessária para clicar em 3D
    ui.hook()                         -- a UI recebe os eventos do love primeiro

    -- ações e eixos: o mesmo nome vale para teclado, gamepad e controles na tela
    ui.bindAxis("move", { left = "key:a", right = "key:d", up = "key:w", down = "key:s", pad = "left" })
    ui.bind("jump", "key:space", "pad:a")

    -- controles na tela
    ui.joystick{ name = "move", anchor = "bottom-left",  x = 40, y = 40, radius = 90 }
    ui.button{ text = "Pular", action = "jump", anchor = "bottom-right", x = 40, y = 40, w = 120, h = 120 }
end

function love.update(dt)
    ui.update(dt)                     -- primeira linha do love.update
    local mx, my = ui.axis("move")    -- -1..1, y cresce para BAIXO (frente = -my)
    if ui.pressed("jump") then --[[ pular! ]] end
end

function love.draw()
    -- desenhe seu mundo 3D aqui
    ui.draw()                         -- sempre por último
end
```

> Chame `ui.hook()` dentro do `love.load`. Ele envolve o `love.handlers`, então você continua escrevendo `love.mousepressed`, `love.keypressed`... normalmente. Eventos consumidos pela UI (clique num botão ou num modelo 3D clicável) **não** chegam nos seus callbacks. Prefere ligar na mão? Não use `ui.hook()` e chame `if ui.mousepressed(x, y, button, istouch) then return end` (idem para `mousereleased`, `mousemoved`, `touchpressed`, `touchmoved`, `touchreleased`, `keypressed`, `keyreleased`, `gamepadpressed`, `gamepadreleased`, `gamepadaxis`, `wheelmoved`, `focus`) e `ui.resize(w, h)`.

## Widgets

Toda opção passada vira um campo que você pode mudar depois (`btn.text = "Novo"`). Os callbacks sempre recebem o widget primeiro.

| Construtor | Opções principais | Callbacks |
|---|---|---|
| `ui.button` | `text`, `action`, `image`, `imagePressed` | `onPress(w,p)`, `onRelease(w,p)`, `onClick(w,p)`, `onDrag(w,p)` |
| `ui.toggle` | `text`, `value` | `onChange(w, value)` |
| `ui.slider` | `min`, `max`, `step`, `value`, `vertical` | `onChange(w, value)` |
| `ui.joystick` | `name`/`axis`, `radius`, `knobRadius`, `deadzone`, `floating`, `showIdle` | `onChange(w, x, y)`, `onPress`, `onRelease` |
| `ui.touchpad` | `delta` (nome para `ui.delta`), `tapSlop`, `pickTaps`, `showArea` | `onDrag(w, dx, dy, p)`, `onTap(w, p)` |
| `ui.label` | `text` (texto ou função), `align`, `w` (quebra linha), `font`, `shadow` | – |
| `ui.bar` | `value` (número ou função), `min`, `max`, `text`, `vertical` | – |
| `ui.image` | `image`, `quad` | – |
| `ui.panel` | `title`, `stack`, `spacing`, `padding`, `itemAlign`, `children` | – |
| `ui.widget` | área clicável invisível (comporta-se como botão, sem visual) | igual ao botão |

Opções comuns: `anchor`, `x`, `y`, `w`, `h`, `layer`, `visible`, `enabled`, `alpha`, `z`, `style`, `draw`, `hitPadding`, `onUpdate(w, dt)`, `onHoverStart(w)`, `onHoverEnd(w)`.
Métodos: `w:show()`, `w:hide()`, `w:setEnabled(b)`, `w:setText(t)`, `w:setValue(v, silent)`, `w:getRect()`, `w:getCenter()`, `w:add(filho)`, `w:destroy()`.

### Layout

```lua
ui.setup{ refWidth = 1280, refHeight = 720, scaleMode = "fit" }  -- "fit" | "height" | "width" | "none" | número
ui.button{ anchor = "bottom-right", x = 20, y = 20 }  -- 20 unidades do canto inferior direito
ui.panel{ anchor = "center", w = "50%", h = 300 }     -- porcentagem do pai
```

Âncoras: `top-left top top-right left center right bottom-left bottom bottom-right`. Em âncoras da direita/baixo, `x`/`y` são margens para dentro; no eixo centralizado são deslocamentos a partir do centro. As coordenadas são em unidades virtuais e relativas à área segura do celular (a janela inteira no PC).

Menus empilhados automaticamente:

```lua
ui.panel{ anchor = "center", title = "Pausa", stack = "vertical", spacing = 10, children = {
    ui.button{ text = "Continuar", w = 240, onClick = function() ui.hideLayer("menu") end },
    ui.toggle{ text = "Som", value = true, onChange = function(_, ligado) end },
}, layer = "menu" }
```

### Camadas

```lua
ui.layer("hud",  { order = 0 })
ui.layer("menu", { order = 20, visible = false })
ui.toggleLayer("menu")      -- também: ui.showLayer / ui.hideLayer / ui.isLayerVisible
```

Widgets em camadas escondidas não são desenhados nem recebem toque. `order` maior é desenhado (e clicado) primeiro.

### Visual personalizado

```lua
-- 1) um widget: sua própria função draw (unidades virtuais, já escalado)
ui.button{ text = "Atirar", draw = function(w)
    local cx, cy = w:getCenter()
    love.graphics.setColor(w.pressed and {1, .3, .1} or {1, .6, .1})
    love.graphics.circle("fill", cx, cy, w._w / 2)
    love.graphics.setColor(1, 1, 1)
    ui.theme.print(w, w:getText(), w._x, cy - 10, w._w, "center")
    -- w:drawDefault() desenha o visual padrão, se quiser desenhar por cima dele
end }

-- 2) um widget: cores
ui.button{ text = "Vermelho", style = { bg = {.6, .1, .1, 1}, bgPressed = {.9, .2, .2, 1}, cornerRadius = 0 } }

-- 3) tudo: tema
ui.setTheme("light")
ui.setTheme{ colors = { accent = {1, .4, .2, 1} }, cornerRadius = 14,
             draw = { button = function(w) --[[ substitui todos os botões padrão ]] end } }

-- fontes (nítidas em qualquer resolução)
local grande = ui.newFont(32, "minhafonte.ttf")   -- o caminho é opcional
ui.label{ text = "Pontos", font = grande }
```

Chaves de estilo: `text textDim bg bgHover bgPressed bgDisabled border accent track shadow fill tint cornerRadius`.
Estado do widget para sua função draw: `w.pressed`, `w.hovered`, `w.active` (joystick), `w.value`, `w.knobX/knobY`, `w.axisX/axisY`, `w:isEnabled()`, `w._alpha`.

## Entrada

As fontes são strings: `"key:space"`, `"scan:w"` (scancode), `"mouse:1"`, `"pad:a"`, `"pad:triggerleft"`, `"wheel:up"` (`down`/`left`/`right`). Os widgets na tela alimentam o mesmo sistema.

```lua
ui.bind("jump", "key:space", "pad:a")        -- ação: ui.down / ui.pressed / ui.released("jump")
ui.bindAxis("move", { left = {"key:a", "key:left"}, right = "key:d", up = "key:w", down = "key:s", pad = "left" })
local x, y = ui.axis("move")                 -- teclado + analógico + joystick na tela chamado "move"
local dx, dy = ui.delta("look")              -- arrasto neste frame (touchpad com delta = "look")
```

`pressed` / `released` valem por um frame (leia depois do `ui.update`). Multitouch funciona: joystick, botões e touchpad podem ser usados ao mesmo tempo.

## Clicar em objetos 3D

```lua
local caixa = g3d.newModel("caixa.obj", "caixa.png", {5, 0, 1})

ui.clickable(caixa, {
    onHoverStart = function(model, hit) end,
    onHoverEnd   = function(model) end,
    onPress      = function(model, hit, pointer) end,
    onRelease    = function(model, hit, pointer) end,
    onClick      = function(model, hit, pointer) print(hit.x, hit.y, hit.z, hit.distance) end,
    onDrag       = function(model, hit, pointer) end,   -- hit é nil quando o ponteiro saiu do modelo
    consume      = true,                                 -- false: o clique também chega nos seus callbacks
})
```

- `hit` tem `x y z` (ponto no mundo), `nx ny nz` (normal), `distance`, `triangle`.
- A matriz completa do modelo é usada, então modelos rotacionados e escalados funcionam. Mouse e toque funcionam (`pointer.source` é `"mouse"` ou `"touch"`).
- A câmera é detectada automaticamente; passe `ui.setup{ camera = ... }` para ser explícito. Se você desenha numa parte da janela, use `ui.setup{ viewport = {x, y, w, h} }` (pixels da janela).
- Remova com `ui.pick3d.remove(model)`. Um modelo com `:compress()` não tem `verts`; passe `verts = vertsOriginais` nas opções.
- O ponteiro está sobre a UI? `ui.isOverUI(x, y)` (pixels da janela).
- **Texto que segue um ponto 3D:** `local vx, vy = ui.pick3d.worldToVirtual(x, y, z)` (nil quando está atrás da câmera); veja a demo.
- Um touchpad em tela cheia repassa toques curtos para o clique em 3D automaticamente, então um dedo pode olhar em volta *e* tocar nos objetos.

## Observações

- As posições de toque são usadas como o LÖVE informa (pixels). Eventos de mouse emulados a partir de toque são ignorados pela UI.
- `ui.debug = true` desenha o contorno de todos os widgets.
- Ainda não incluído: campo de texto, listas com rolagem, navegação de menu por gamepad.

## Licença

MIT. `g3d/` é © groverburger (MIT, incluído só para a demo rodar sem instalar nada).
