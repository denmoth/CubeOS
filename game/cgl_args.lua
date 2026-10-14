-- Общий разбор аргументов для game/cgl_demo.lua и game/cgl_bench.lua.
--   [graphics|teletext]   вывод (по умолчанию сам)
--   monitor[=имя]         рисовать на мониторе (первом найденном или с таким именем, в том числе по проводному модему)
--   mirror=имя1,имя2      показывать то же самое ещё на этих мониторах (того же размера); основной задаётся monitor=
--   scale=число          масштаб текста монитора; по умолчанию 0.5 (больше всего клеток и пикселей, максимальное разрешение)
-- Возвращает opts для cgl.open / demo.main, найденный монитор (или nil) и выбранный масштаб.
return function(args)
  local opts = { backend = "auto" }
  local target, scale = nil, nil
  local mirror_names = {}
  for _, a in ipairs(args) do
    if a == "graphics" or a == "teletext" then
      opts.backend = a
    elseif a == "monitor" then
      target = peripheral.find("monitor")
      opts.monitor = target and peripheral.getName(target)
    elseif a:sub(1, 8) == "monitor=" then
      opts.monitor = a:sub(9)
      target = peripheral.wrap(opts.monitor)
    elseif a:sub(1, 7) == "mirror=" then
      for name in a:sub(8):gmatch("[^,]+") do mirror_names[#mirror_names + 1] = name end
    elseif a:sub(1, 6) == "scale=" then
      scale = tonumber(a:sub(7))
    end
  end
  if opts.monitor and not target then
    return nil, "monitor not found: " .. tostring(opts.monitor)
  end
  if target then
    if target.setTextScale then
      -- по умолчанию самый мелкий текст: на большом мониторе максимум клеток и пикселей (весь смысл большого монитора)
      scale = scale or 0.5
      target.setTextScale(scale)
    end
    opts.term = target
  end
  if #mirror_names > 0 then
    opts.mirror = {}
    for _, name in ipairs(mirror_names) do
      local m = peripheral.wrap(name)
      if not m then return nil, "monitor not found: " .. name end
      if m.setTextScale then m.setTextScale(scale or 0.5) end
      opts.mirror[#opts.mirror + 1] = m
    end
  end
  return opts, target, scale
end
