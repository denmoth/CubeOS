local w, h = term.getSize()
local snake = { { x = 10, y = 5 }, { x = 9, y = 5 }, { x = 8, y = 5 } }
local dir = { x = 1, y = 0 }
local food = { x = 20, y = 8 }
local score, alive = 0, true
math.randomseed(os.epoch("utc"))

local function placeFood()
  food = { x = math.random(1, w), y = math.random(2, h) }
end

local function draw()
  term.clear()
  for _, seg in ipairs(snake) do
    term.setCursorPos(seg.x, seg.y)
    term.write("O")
  end
  term.setCursorPos(food.x, food.y)
  term.write("*")
  term.setCursorPos(1, 1)
  term.write("Score: " .. score)
end

local function step()
  local head = { x = snake[1].x + dir.x, y = snake[1].y + dir.y }
  if head.x < 1 or head.x > w or head.y < 2 or head.y > h then
    alive = false
    return
  end
  for _, seg in ipairs(snake) do
    if seg.x == head.x and seg.y == head.y then
      alive = false
      return
    end
  end
  table.insert(snake, 1, head)
  if head.x == food.x and head.y == food.y then
    score = score + 1
    placeFood()
  else
    table.remove(snake)
  end
end

local timer = os.startTimer(0.15)
while alive do
  local event, p1 = os.pullEvent()
  if event == "key" then
    if (p1 == keys.up or p1 == keys.w) and dir.y == 0 then dir = { x = 0, y = -1 }
    elseif (p1 == keys.down or p1 == keys.s) and dir.y == 0 then dir = { x = 0, y = 1 }
    elseif (p1 == keys.left or p1 == keys.a) and dir.x == 0 then dir = { x = -1, y = 0 }
    elseif (p1 == keys.right or p1 == keys.d) and dir.x == 0 then dir = { x = 1, y = 0 }
    end
  elseif event == "timer" and p1 == timer then
    step()
    draw()
    timer = os.startTimer(0.15)
  end
end

term.setCursorPos(1, h)
print("Game over! Score: " .. score)
