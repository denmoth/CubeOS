# API `stew` (шаг 4)

Один API для терминала (`stew ...` в cush), магазина, установщика системы и двойного клика по `.cpk`. Код в `lib/stew/`.
Работает и без CubeOS (на чистом CraftOS в установщике), поэтому файлы трогает через CraftOS-подобный `fs`, а не через CFS.

## Раскладка на диске (относительно `root`, по умолчанию `/`)

| Путь | Что |
|---|---|
| `/cubeos/pkg/<id>.cpk` | пакет, хранимый сжатым |
| `/cubeos/pkg/<id>/` | пакет, хранимый распакованным (файлы как в архиве) |
| `/cubeos/share/assets/...` | ресурсы системных пакетов (`assets/**` из пакетов `cubeos.*`), всегда файлами |
| `/cubeos/sys/boot/`, `/startup.lua` | загрузка (`sys/boot/*`, `sys/startup.lua` из пакетов `cubeos.*`) |
| `/cubeos/sys/services/`, `/cubeos/sys/cfg/` | манифесты служб (заменяются) и настройки (только если их ещё нет) |
| `/cubeos/var/stew/installed.json5` | база установленных |
| `/cubeos/var/stew/boot.idx` | индекс модулей для загрузчика (таблица Lua, `sys/boot/pkgload.lua`) |
| `/cubeos/var/stew/sources.json5` | источники |
| `/cubeos/var/stew/cache/<источник>.json5` | кэш каталога |
| `/cubeos/var/stew/staging/<txn>/` | скачанное до фиксации |
| `/cubeos/var/stew/trash/<txn>/` | заменённое и удалённое до конца транзакции (откат) |
| `/cubeos/var/stew/journal.json5` | журнал незавершённой транзакции |

Код (`lib/**`, `src/cubic/rt.lua`) всегда остаётся внутри пакета (сжатого или распакованного). Пакеты, без которых не
прочитать сжатый пакет (`cubeos.boot`, `cubeos.cubic-rt`, `cubeos.cpk` и их зависимости), всегда распакованы.

## Создание

```
import stew
s = stew.new({fs: fs, root: "/", http: nil, cubic: nil, log: fn, yield: fn})
```

- `http`: функция `http(url, binary) -> body | nil, err` (по умолчанию CC `http.get`); тесты подставляют свою.
- `cubic`: компилятор, если стоит `cubeos.cubic` (нужен только для `pack` пакетов с `.cub`).
- `yield`: отдать управление между тяжёлыми шагами (по умолчанию `os.queueEvent` + `os.pullEvent`).

## Чтение

| Вызов | Результат |
|---|---|
| `s:installed()` | `{id: rec}`; `rec = {id, version, source, storage, priority, kind, depends, want, modules, contributes, options, files, auto, pinned, size}` |
| `s:sources()` | список источников `[{name, kind, url, trust}]` |
| `s:refresh(name=nil, on_progress=nil)` | обновить кэш каталогов: `{ok: [имена], failed: [{name, error}]}` |
| `s:catalog()` | все пакеты из кэша всех источников: `[{id, name, description, kind, category, priority, source, trust, latest, versions, installed, update}]` |
| `s:search(text, filter=nil)` | то же с поиском по id, имени, описанию; `filter = {source, category, kind}` |
| `s:info(id)` | запись каталога + установленное + манифест, если пакет стоит |

## План и изменения

```
p = s:plan({install: ["denmoth.snake"], remove: [], update: [], storage: "auto", options: {"denmoth.snake": {...}}})
```

`p = {ok, steps: [{op: "install"|"update"|"remove", id, version, from, size, installed_size, source, trust, auto}],
download, installed_delta, peak, free, reserve, fits, missing: [...], conflicts: [...], warnings: [...], new_permissions: {id: [...]},
runs_setup: [ids]}` (смысл полей как в spec/package-manager.md, «Запрос сколько места нужно»).

```
r = s:apply(p, {on_progress: fn(stage, id, i, n), ask: fn(question) -> answer})
```

Транзакция целиком: скачать в staging, проверить sha256 и размер, установщики `ask`, журнал, разложить файлы, `contributes`,
`install`/`upgrade` установщиков, база, `boot.idx`, удалить журнал и корзину. Любая ошибка: откат, `r = {ok: false, error}`.
Стадии прогресса: `download`, `verify`, `ask`, `place`, `setup`, `commit`, `rollback`.

Короткие обёртки: `s:install(ids, opts)`, `s:remove(ids, opts)`, `s:update(ids=nil, opts)` (plan + apply),
`s:install_file(path, opts)` (локальный `.cpk`, источник `adhoc` или `path`), `s:recover()` (вызывается при загрузке: откатить
незавершённую транзакцию по журналу).

## Обслуживание

`s:verify(id=nil)` (CRC файлов из `listing` манифеста), `s:pin(id, on)`, `s:set_storage(id, "packed"|"unpacked")`,
`s:rollback(id)` (если старая версия ещё в корзине), `s:clean()` (кэш, корзина, ненужные авто-зависимости),
`s:source_add(src)`, `s:source_remove(name)`, `s:options(id)`, `s:reconfigure(id, values)`.

## Адаптеры источников

`stew.source.<kind>` (05-sources.md):

- `refresh(src, ctx) -> {packages: {id: запись как в index.json5}}`
- `fetch(src, id, version, rec, dest, ctx) -> путь к .cpk` (пишет `.cpk` в `dest`)
- необязательно `search(src, text, ctx)`, `publish(...)`

`ctx = {fs, http, tmp, pack (модуль stew.pack), cubic, log, yield}`. Виды в первой версии: `path`, `http`, `cobble`,
`pinestore`; `pastebin` и `rednet` позже.
