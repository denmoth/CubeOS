-- Показывает шрифты CubeOS пикселями (нужен мод CC:Graphics). На компьютере: /repo/game/font_demo.lua
-- Первый экран: cube-6x9 (размер клетки как у родного терминала CC) со строками на шаге 9 пикселей, как у родного текста.
-- Любая клавиша переключает экран, на последнем закрывает демо.
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

local f6 = font.from_file(ROOT .. "/assets/fonts/cube-6x9.font")
-- личный шрифт Minecraft (см. tools/import_mc_font.py), если он собран на этой машине
local mc = fs.exists(ROOT .. "/assets/private/cube-mc-6x9.font") and font.from_file(ROOT .. "/assets/private/cube-mc-6x9.font") or nil
local f5 = font.from_file(ROOT .. "/assets/fonts/cube-5x7.font")
local f8 = font.from_file(ROOT .. "/assets/fonts/cube-8x16.font")

local function show(draw_fn)
  term.setGraphicsMode(1)
  local w, h = term.getSize(true)
  local buf = pixelbuf.new(w, h, 0)
  draw_fn(buf, w, h)
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
end

-- экран 0 (если шрифт собран): личный шрифт в стиле Minecraft
if mc then
  show(function(buf)
    local lines = {
      "cube-mc-6x9 (личный): шрифт Minecraft в клетке 6x9",
      "The quick brown fox jumps over the lazy dog 0123",
      "Привет, мир! Съешь ещё этих мягких булок, да выпей",
      "ПРИВЕТ, МИР! ЪЫЬЭЮЯ ёЁ йЙ жЖ шШ щЩ",
      "Українська: Є є, І і, Ї ї, Ґ ґ. Їжак із Харкова",
      "┌──────┬──────┐ ╔══════╦══════╗ █▓▒░ ← ↑ → ↓",
      "│ Файл │ Вид  │ ║ OK   ║ Нет  ║ α β γ δ π Ω ∞ ≠",
    }
    for i, text in ipairs(lines) do
      mc:draw(buf, 0, (i - 1) * 9, text, 1)
    end
  end)
end

-- экран 1: cube-6x9 на сетке родного терминала (клетка 6x9, строки на шаге 9)
show(function(buf)
  local lines = {
    "cube-6x9: размер клетки как у родного шрифта CC",
    "The quick brown fox jumps over the lazy dog 0123",
    "Привет, мир! Съешь ещё этих мягких булок, да выпей",
    "ПРИВЕТ, МИР! ЪЫЬЭЮЯ ёЁ йЙ жЖ шШ щЩ",
    "Українська: Є є, І і, Ї ї, Ґ ґ. Їжак із Харкова",
    "┌──────┬──────┐ ╔══════╦══════╗ █▓▒░ ← ↑ → ↓",
    "│ Файл │ Вид  │ ║ OK   ║ Нет  ║ α β γ δ π Ω ∞ ≠",
    "  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15",
  }
  for i, text in ipairs(lines) do
    f6:draw(buf, 0, (i - 1) * 9, text, 1)
  end
end)

-- экран 2: три размера рядом
show(function(buf)
  f6:draw(buf, 2, 2, "cube-6x9 : Привіт, Hello, мир! Ёж", 1)
  f5:draw(buf, 2, 14, "cube-5x7 : Привіт, Hello, мир! Ёж, компактный, больше текста на экране", 1)
  f8:draw(buf, 2, 26, "cube-8x16: Привіт, Hello, Ёж", 1)
  f5:draw(buf, 2, 46, "Один и тот же экран 51x19 родных клеток вмещает в 5x7 примерно 61 колонку и 24 строки", 1)
  f6:draw(buf, 2, 56, "А в 6x9 ровно 51 колонку и 19 строк, как у родного терминала", 1)
end)

term.setGraphicsMode(false)
term.clear()
term.setCursorPos(1, 1)
