-- Демонстрация библиотеки интерфейса CubeOS в настоящем CC. На компьютере: /repo/game/ui_demo.lua [pixel|text] [monitor[=имя]]
--   [theme=cubeos|dark|light|retro|hacker|amber|contrast] [keys=arrows|wasd|vim] [scale=число] [mirror=имя1,имя2]
-- pixel: свой шрифт и любые символы (нужен CC: Graphics); text: обычный терминал (рамки заменяются на + - |, русские буквы на латинские).
-- Alt+←→ листает программы, Alt+W закрывает, F9 открывает список программ, Esc закрывает диалоги. Выход: Ctrl+T.
local ROOT = "/repo"
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")
local loader = cubic.new_loader({ roots = { ROOT .. "/lib", ROOT .. "/examples" } })

-- компиляция модулей Cubic в CC идёт долго; между модулями отдаём управление, чтобы не сработал «Too long without yielding»
local function preload(names)
  for _, name in ipairs(names) do
    loader.import(name)
    os.queueEvent("preload")
    os.pullEvent("preload")
  end
end
preload({
  "unicode", "font", "pixelbuf", "compress", "cgl.color", "cgl.surface", "cgl.quant", "cgl.graphics", "cgl.teletext", "cgl.mirror",
  "cgl.anim", "cgl", "ui.cells", "ui.theme", "ui.border", "ui.keymap", "ui.text", "ui.charmap", "ui.widget", "ui.controls",
  "ui.lists", "ui.dialogs", "ui.runtime", "ui.out_text", "ui.out_pixel", "ui.shell", "ui.toys", "ui",
})
local demo = loader.import("ui_demo")

local opts, target, scale = dofile(ROOT .. "/game/cgl_args.lua")({ ... })
if not opts then
  printError(target)
  return
end
local ui_opts = { term = target, theme = "cubeos", keys = "arrows", backend = "auto", mirror = opts.mirror }
for _, a in ipairs({ ... }) do
  if a == "pixel" or a == "text" then ui_opts.backend = a
  elseif a:sub(1, 6) == "theme=" then ui_opts.theme = a:sub(7)
  elseif a:sub(1, 5) == "keys=" then ui_opts.keys = a:sub(6) end
end
if ui_opts.backend == "auto" and opts.backend == "teletext" then ui_opts.backend = "text" end

local ok, err = pcall(demo.main, ui_opts)
local out = target or term
out.setBackgroundColor(colors.black)
out.setTextColor(colors.white)
if out.setGraphicsMode then out.setGraphicsMode(false) end
out.clear()
out.setCursorPos(1, 1)
if not ok then printError("ui demo: " .. tostring(err)) end
