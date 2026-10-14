-- Терминал CubeOS: оболочка csh на весь экран (пайпы, фоновые задачи, подсветка, история, fetch; классические программы CC работают как есть),
-- с русским и украинским вводом, прокруткой колесом мыши и выделением.
-- На компьютере: /repo/game/terminal.lua [pixel|text] [monitor[=имя]] [программа аргументы...]
--   pixel: свой шрифт, кириллица и любые символы (нужен CC: Graphics); text: обычный терминал (кириллица латиницей).
-- Ctrl+Shift или Alt+Shift переключает раскладку (EN, RU, UK). Ctrl+C или Ctrl+T прерывает программу. Выход: команда exit.
-- Если указать программу, она запускается вместо csh (например rom/programs/shell.lua).
local ROOT = "/repo"
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")
local loader = cubic.new_loader({ roots = { ROOT .. "/lib" } })

-- компиляция модулей Cubic в CC идёт долго; между модулями отдаём управление
local function preload(names)
  for _, name in ipairs(names) do
    loader.import(name)
    os.queueEvent("preload")
    os.pullEvent("preload")
  end
end
preload({
  "version", "unicode", "font", "pixelbuf", "compress", "cgl.color", "cgl.surface", "cgl.quant", "cgl.graphics", "cgl.teletext",
  "cgl.mirror", "cgl.anim", "cgl", "ui.cells", "ui.theme", "ui.border", "ui.keymap", "ui.text", "ui.charmap", "ui.widget",
  "ui.controls", "ui.lists", "ui.dialogs", "ui.runtime", "ui.out_text", "ui.out_pixel", "ui.shell", "ui.toys", "ui",
  "input.layout", "term.chars", "term.palette", "term.vterm", "term.view", "compat.vararg", "compat.bios", "compat.env", "compat.proc",
  "csh.lex", "csh.hist", "csh.editor", "csh.builtins", "csh.fetch", "csh.shell",
})
local ui = loader.import("ui")
local vterm = loader.import("term.vterm")
local view_mod = loader.import("term.view")
local env_mod = loader.import("compat.env")
local proc_mod = loader.import("compat.proc")
local palette = loader.import("term.palette")
local csh = loader.import("csh.shell")

local opts, target = dofile(ROOT .. "/game/cgl_args.lua")({ ... })
if not opts then
  printError(target)
  return
end
local backend = "auto"
local rest = {}
for _, a in ipairs({ ... }) do
  if a == "pixel" or a == "text" then backend = a
  elseif not (a == "graphics" or a == "teletext" or a:match("^monitor") or a:match("^mirror=") or a:match("^scale=")
    or a:match("^fps=") or a:match("^view=")) then rest[#rest + 1] = a end
end
if backend == "auto" and opts.backend == "teletext" then backend = "text" end

local out = ui.open_out({ term = target, backend = backend, mirror = opts.mirror })
local u = ui.runtime.new(out, { theme = ui.theme.get("cubeos") })
local cols, rows = out:size()
local vt = vterm.new(cols, rows, { palette = palette.get("cubeos"), history = 2000 })
local view = view_mod.new(vt, { width = "fill", height = "fill" })
local env = env_mod.new({ vterm = vt })
env.csh_opts = { history_path = "/.csh_history",
  info = { display = out.kind == "pixel" and "pixel mode" or "text mode", font = out.kind == "pixel" and "Monocraft 6x9" or nil } }
local program = table.remove(rest, 1)
local popts = { name = "terminal", on_exit = function() u.quit = true end, on_shutdown = function() u.quit = true end }
if not program then popts.main = csh.main end
local proc = proc_mod.new(env, program or "csh", rest, popts)
view:on("event", function(_, name, a, b, c) proc:feed(name, a, b, c) end)
u:set_root(view)
u:focus_widget(view)
proc:start()

-- события не от ввода (таймеры, rednet, диски) идут программе напрямую, ввод через интерфейс (раскладка, мышь)
local INPUT = { key = true, key_up = true, char = true, paste = true, mouse_click = true, mouse_drag = true, mouse_up = true,
  mouse_scroll = true, monitor_touch = true, term_resize = true, monitor_resize = true }
local function pull()
  local ev, a, b, c, d, e = os.pullEventRaw()
  if ev == "terminate" then
    proc:feed("terminate")
    return "none"
  end
  if not INPUT[ev] then
    if ev == "timer" then
      if proc:owns_timer(a) then proc:feed(ev, a, b, c, d, e) end
    elseif ev == "alarm" then
      if proc:owns_alarm(a) then proc:feed(ev, a, b, c, d, e) end
    else
      proc:feed(ev, a, b, c, d, e)
    end
  end
  return ev, a, b, c
end
ui.runtime.run(u, { pull = pull })
out:close()
if out.screen and out.screen.close then pcall(out.screen.close, out.screen) end
