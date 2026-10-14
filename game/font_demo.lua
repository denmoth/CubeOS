-- Показывает шрифты CubeOS пикселями (нужен мод CC:Graphics). На компьютере: /repo/game/font_demo.lua
-- Любая клавиша закрывает демо.
local ROOT = "/repo"
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")
local loader = cubic.new_loader({ roots = { ROOT .. "/lib" } })
local font = loader.import("font")
local pixelbuf = loader.import("pixelbuf")

if not term.setGraphicsMode then
  print("CC:Graphics is not installed: custom fonts need pixel graphics.")
  print("Without it CubeOS shows English text only (decision D135).")
  return
end

local small = font.from_file(ROOT .. "/assets/fonts/cube-5x8.font")
local large = font.from_file(ROOT .. "/assets/fonts/cube-8x16.font")

term.setGraphicsMode(1)
local w, h = term.getSize(true)
local buf = pixelbuf.new(w, h, 0)

local y = 2
local function put(f, text)
  f:draw(buf, 2, y, text, 1)
  y = y + f.height + 3
end

put(small, "cube-5x8: Hello, world! 0123456789 (){}[]<>")
put(small, "Привет, мир! Съешь ещё этих мягких булок, да выпей чаю")
put(small, "ПРИВЕТ, МИР! ЪЫЬЭЮЯ ёЁ")
put(small, "Українська: Є є, І і, Ї ї, Ґ ґ. Їжак із Харкова")
put(small, "┌──────┬──────┐  ╔══════╦══════╗  █▓▒░  ← ↑ → ↓ ✓ ✗")
put(small, "│ Файл │ Вид  │  ║ ОК   ║ Нет  ║")
put(large, "cube-8x16: Привіт, Hello")
put(large, "Ёж и Єнот: ґанок, їжак")

local rows = buf:rows()
local out = {}
for yy = 1, #rows do
  local row = {}
  for xx = 1, #rows[yy] do
    row[xx] = rows[yy][xx] == 1 and colors.white or colors.black
  end
  out[yy] = row
end
term.drawPixels(0, 0, out)
os.pullEvent("key")
term.setGraphicsMode(false)
term.clear()
term.setCursorPos(1, 1)
