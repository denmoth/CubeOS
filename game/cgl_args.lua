-- Общий разбор аргументов для game/cgl_demo.lua и game/cgl_bench.lua.
--   [graphics|teletext]   вывод (по умолчанию сам)
--   monitor[=имя]         рисовать на мониторе (первом найденном или с таким именем, в том числе по проводному модему)
--   scale=число          масштаб текста монитора; по умолчанию подбирается так, чтобы было не меньше 51 клетки в ширину
--                         (как у терминала компьютера: 306x171 пикселей, а не сотни тысяч)
--   cols=число            другая минимальная ширина в клетках для автоподбора
-- Возвращает opts для cgl.open / demo.main, найденный монитор (или nil) и выбранный масштаб.
local SCALES = { 5, 4, 3, 2.5, 2, 1.5, 1, 0.5 }
return function(args)
  local opts = { backend = "auto" }
  local target, scale, cols = nil, nil, 51
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
    elseif a:sub(1, 5) == "cols=" then
      cols = tonumber(a:sub(6)) or cols
    end
  end
  if opts.monitor and not target then
    return nil, "monitor not found: " .. tostring(opts.monitor)
  end
  if target then
    if target.setTextScale then
      if scale then
        target.setTextScale(scale)
      else
        for _, sc in ipairs(SCALES) do
          target.setTextScale(sc)
          local w = target.getSize()
          if w >= cols then scale = sc; break end
        end
        scale = scale or 0.5
        target.setTextScale(scale)
      end
    end
    opts.term = target
  end
  return opts, target, scale
end
