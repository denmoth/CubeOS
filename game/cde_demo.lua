-- Демонстрация рабочего стола CDE (шаг 1) в настоящем CC с CC: Graphics. На компьютере: /repo/game/cde_demo.lua [theme=tokyo-night|dark|light]
-- Три окна-процесса ядра: Cube (пиксели), Notes (текст, можно печатать), Clock. Мышь: тянуть заголовок, края и углы, двойной
-- клик по заголовку, кнопки _ □ ×. Клавиши: Alt+←/→ окна, Alt+↑ развернуть, Alt+↓ вернуть или свернуть, Alt+Shift+←/→ половинки,
-- Ctrl+T закрыть окно (удержание: принудительно), Alt+D рабочий стол, Alt+Enter новое окно заметок, Ctrl+Alt+T тема,
-- Ctrl+Alt+K витрина cdk, F11 полный экран. Выход: Ctrl+Alt+Q.
local ROOT = "/repo"
if not term.setGraphicsMode then
  printError("CDE needs CC: Graphics (term.setGraphicsMode)")
  return
end
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
print("Loading CDE...")
preload({
  "unicode", "font", "pixelbuf", "compress", "cgl.color", "cgl.surface", "cgl.quant", "cgl.graphics", "cgl.teletext", "cgl.mirror",
  "cgl.anim", "cgl", "cgl.g3d", "ui.cells", "cfs.rules", "kernel.sys", "kernel", "kernel.cc",
  "cde.theme", "cde.window", "cde.wallpaper", "cde.icons", "cde.panel", "cde.compositor", "cde.wm", "cde.app", "cde",
  "input.layout", "cdk.style", "cdk.icons", "cdk.widget", "cdk.controls", "cdk.input", "cdk.ui", "cdk", "cdk.gallery",
})
local demo = loader.import("cde_demo")

local opts = { assets = ROOT .. "/assets" }
for _, a in ipairs({ ... }) do
  if a:sub(1, 6) == "theme=" then opts.theme = a:sub(7) end
end

local ok, err = pcall(demo.main, opts)
term.setGraphicsMode(false)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
for i = 0, 15 do term.setPaletteColor(2 ^ i, term.nativePaletteColor(2 ^ i)) end
if not ok then printError("cde demo: " .. tostring(err)) end
