-- Общий разбор аргументов для game/cgl_demo.lua и game/cgl_bench.lua.
--   [graphics|teletext]   вывод (по умолчанию сам)
--   monitor[=имя]         рисовать на мониторе (первом найденном или с таким именем, в том числе по проводному модему)
--   scale=число          масштаб текста монитора (0.5 это больше всего клеток). По умолчанию: 0.5 для телетекста,
--                         а для пиксельного режима самый мелкий масштаб, при котором кадр не больше 120 тысяч пикселей
-- Возвращает opts для cgl.open / demo.main, найденный монитор (или nil) и выбранный масштаб.
local SCALES_UP = { 0.5, 1, 1.5, 2, 2.5, 3, 4, 5 }
local PIXEL_BUDGET = 120000
return function(args)
  local opts = { backend = "auto" }
  local target, scale = nil, nil
  for _, a in ipairs(args) do
    if a == "graphics" or a == "teletext" then
      opts.backend = a
    elseif a == "monitor" then
      target = peripheral.find("monitor")
      opts.monitor = target and peripheral.getName(target)
    elseif a:sub(1, 8) == "monitor=" then
      opts.monitor = a:sub(9)
      target = peripheral.wrap(opts.monitor)
    elseif a:sub(1, 6) == "scale=" then
      scale = tonumber(a:sub(7))
    end
  end
  if opts.monitor and not target then
    return nil, "monitor not found: " .. tostring(opts.monitor)
  end
  if target then
    if target.setTextScale then
      if not scale then
        -- телетекст: 2x3 пикселя на клетку, самый мелкий текст даёт максимум разрешения, а скан кадра дешёвый.
        -- Пиксельный режим (CC: Graphics): пикселей 6x9 на клетку, их число растёт быстро, поэтому берём самый
        -- мелкий масштаб, при котором кадр не больше PIXEL_BUDGET пикселей.
        local graphics = target.setGraphicsMode ~= nil and opts.backend ~= "teletext"
        if not graphics then
          scale = 0.5
        else
          for _, sc in ipairs(SCALES_UP) do
            target.setTextScale(sc)
            local w, h = target.getSize()
            if w * 6 * h * 9 <= PIXEL_BUDGET then scale = sc; break end
          end
          scale = scale or 5
        end
      end
      target.setTextScale(scale)
    end
    opts.term = target
  end
  return opts, target, scale
end
