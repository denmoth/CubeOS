-- Вспомогательные функции с переменным числом аргументов для compat.bios (в Cubic нет `...`, а nil внутри аргументов важны).
local M = {}

-- упаковка аргументов с их числом
function M.pack(...)
  return { n = select("#", ...), ... }
end

-- os.pullEventRaw: просто отдаёт управление хозяину и получает событие
function M.pull_event_raw(filter)
  return coroutine.yield(filter)
end

-- os.pullEvent: то же, но «terminate» это ошибка "Terminated"
function M.pull_event(filter)
  local ev = M.pack(coroutine.yield(filter))
  if ev[1] == "terminate" then error("Terminated", 0) end
  return table.unpack(ev, 1, ev.n)
end

-- функция с аргументами (env, список аргументов, их число) -> обычная функция с `...`
function M.variadic(env, fn)
  return function(...)
    return fn(env, M.pack(...), select("#", ...))
  end
end

-- os.run(окружение, путь, ...): fn(env, окружение, путь, упакованные аргументы)
function M.runner(env, fn)
  return function(run_env, path, ...)
    return fn(env, run_env, path, M.pack(...))
  end
end

-- вызвать функцию с упакованными аргументами
function M.call(fn, args)
  return fn(table.unpack(args, 1, args.n))
end

-- результаты вызова в таблицу с n
function M.call_packed(fn, ...)
  return M.pack(pcall(fn, ...))
end

-- ждать событие у хозяина и вернуть его упакованным (фильтр не нужен, оболочка сама раздаёт события задачам)
function M.pull_packed(filter)
  return M.pack(coroutine.yield(filter))
end

-- возобновить корутину событием ev (упакованным; nil при первом запуске): ok, первое значение (фильтр), остальное отбрасывается
function M.resume(co, ev)
  if ev == nil then return coroutine.resume(co) end
  return coroutine.resume(co, table.unpack(ev, 1, ev.n))
end

return M
