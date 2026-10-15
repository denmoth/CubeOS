# Службы системы

Код: `lib/svc/*.cub`, манифесты `sys/services/*.conf`, настройки по умолчанию `sys/cfg/*.conf`, библиотеки `lib/crash.cub`, `lib/sysfs.cub`, `lib/cfs/virtual.cub`. Тесты `lib_svc_*`, `lib_boot_system`, `lib_crash`, `lib_cfs_virtual`, `lib_cush_logs`, `lib_sys_files`. Решения D207, D211–D213. Общая часть про загрузку и менеджер служб: [boot.md](boot.md), про время: [time.md](time.md).

## Как устроена служба

- **Манифест** (`/cubeos/sys/services/<имя>.conf`, JSON5): `name`, `module` (модуль с `main(sys, args)`), `requires`, `after`, `restart`, `max_restarts`, `restart_delay`, `ready` (`register` или `immediate`), `timeout`, `enabled`, `safe`, **`args`** (словарь для `main`). Тест `lib_sys_files` проверяет все поставляемые манифесты (разбор, имя по файлу, существующий модуль).
- **Аргументы `main(sys, args)`**: словарь `args` из манифеста плюс `args.system`: контекст загрузки (`fsys`, `kernel`, `services`, `sessions`, `auth`, `state`, `mode`, `power(action, sys)`...). Службе выдаётся вид CFS системы (`sys.view()`). Изоляции памяти нет (песочница шаг 6), поэтому служба видит всё.
- **Запросы** (`svc.rpc`): сообщение `{op, args, sender, id}` через `sys.send`, ответ `{id, result}` или `{id, error}`. Клиент `rpc.call(sys, имя, op, args, таймаут)` возвращает результат либо `nil, текст ошибки`. Служба: `rpc.serve(sys, {op: (args, sender) => ...}, {tick, timeout, on_message})`. События службы это обычные сообщения без `id` (`{event: ...}`); пока `call` ждёт ответ, они откладываются (до 100 на процесс), и читать их нужно через `rpc.next_event(sys, таймаут)`, а не `sys.receive`.
- **События CC для служб.** Ядро запоминает, по каким именам процесс ждал события (`wait_event(список)`), и копит такие события в его очереди, пока он занят: так служба не теряет `disk` или `process_exit`, если два события пришли подряд. Обработчик события работает в процессе-помощнике (`devd-events`, `crashd-events`), который шлёт службе сообщения.
- **Журнал из любого процесса:** `sys.log(уровень, текст)`. Через `logd`, если он запущен (источник это имя процесса), иначе в журнал ядра (`klog`).
- **Права.** Пока запросы принимает любой процесс; проверку по правам добавит `permd` (шаг 6).

## Службы

| Служба | Модуль | Что делает |
|---|---|---|
| `logd` | `svc.logd` | журнал: уровни `debug info warn error crit`, файлы `/cubeos/var/log/<источник>.log` и `system.log`, ротация по размеру (`max_size` 65536, `keep` 4 архива `.1`...) и по загрузкам (`rotate_boots`), чтение запросами и командой `logs`; строки журнала ядра до запуска записываются при старте, дальше приходят через общий буфер (`kernel.log_fn`, `kernel: true` в `log.conf`) |
| `timed` | `svc.timed` | время, см. [time.md](time.md) |
| `devd` | `svc.devd` | периферия и диски (ниже) |
| `powerd` | `svc.powerd` | `shutdown`, `reboot`, `status`: запускает штатное завершение (`Boot:power`) в отдельном процессе `power`, который переживает остановку служб |
| `crashd` | `svc.crashd` | отчёты о сбоях процессов (ниже) |
| `permd` | `svc.permd` | **заглушка**: `check {pid, cap}` разрешает системе и администраторам, остальным отказывает и пишет отказ в журнал |
| `notifyd` | `svc.notifyd` | уведомления: `post`, `list {unread}`, `read`, `dismiss`, `clear`, `subscribe` (события `notification`); до 100 штук |
| `clipboard` | `svc.clipboard` | буфер обмена в памяти: `set {text, source}`, `get`, `history {n}`, `clear`; до 50 записей, запись до 64 КБ |
| `fontd`, `audiod`, `netd` | `svc.stub` | **заглушки** (`ping`, `status`), нужны зависимостям и проверкам готовности до шагов 4, 7, 8 |

Порядок запуска: `logd` первым (остальные `after: ["logd"]`), дальше по имени. Службы без `safe: false` работают и в безопасном режиме; `clipboard`, `fontd`, `audiod`, `netd` в нём не запускаются.

## Журнал (`logd`)

Строка: `2026-10-15T12:00:00Z info timed сообщение` (время UTC, один пробел между полями, переводы строк в тексте заменяются пробелами, источник очищается до `[%w_-.]`). Настройки `/cubeos/sys/cfg/log.conf`: `level`, `max_size`, `keep`, `rotate_boots`, `kernel`. Запросы: `log`, `read {source, level, n}`, `list`, `rotate`, `set_level`. Команда `logs [-f] [-n N] [-l уровень] [служба]` читает файлы напрямую (цвет по уровню, `-f` следит, Ctrl+C выходит). **Секреты в журнал не пишутся** (D196): за это отвечает тот, кто вызывает `sys.log`. Журнал загрузки до `logd` хранится в `kernel.log_lines` (последние 200 строк).

## Устройства (`devd`)

Следит за `peripheral` и `peripheral_detach`, монтирует диски по `disk` и `disk_eject`, строит `/cubeos/hardware`. Стандартный дисковод (`drive`) монтируется в `/cubeos/drives/floppy/<метка или disk-<id>>`, другое хранилище с `getMountPath` в `/cubeos/drives/<метка или id>` (привязка к диску, не к стороне дисковода; одинаковые метки получают суффикс ID). Диск без данных (звуковой) не монтируется. Код с носителей сам не запускается (только по запросу с показом источника и прав, шаг 6). Запросы: `list`, `drives`, `has {type}`, `mount {name}`, `unmount {name}`. Уведомления о монтировании пока только в журнал (`notifyd` подключится позже).

## Сбои (`crash`, `crashd`)

Отчёт `/cubeos/var/crash/<ГГГГММДД-ччммсс>-<имя>.json`: `version`, `time`, `time_text`, `kind` (`process`, `boot`, `kernel`), `code` (`E-` и CRC32 первой строки ошибки без чисел, поэтому одна ошибка даёт один код), `error`, `process`, `log` (последние 20 строк журнала ядра). `crashd` пишет отчёт для каждого процесса, завершившегося как `crashed`, и хранит не больше 20 (`keep`). Запросы: `report`, `list`, `read`, `clear`.

**Сбой самой загрузки** (исключение в `stage2`): тот же формат через библиотеку `crash` (до запуска служб), экран ошибки с кодом причины, путём к отчёту и отсчётом (`crash_delay`, 10 с), клавиша открывает восстановление. По истечении времени: перезагрузка, если загрузка уже началась (неудачные загрузки считает `boot.state`: после одной безопасный режим, после двух восстановление), иначе восстановление (счёт вести нечем, перезагрузка зациклилась бы).

## Выключение и грязное выключение

`powerd` или вход (`Boot:power`) закрывают сессии, просят службы завершиться (до 3 с, затем принудительно), помечают загрузку законченной (`boot.state: clean`), вызывают `os.shutdown` или `os.reboot`. Если прошлая загрузка так и не закончилась, `system.unclean = true`: в журнал ядра пишется «unclean shutdown», экран входа показывает «The system was not shut down properly last time.», `/cubeos/run/boot.state` содержит `unclean: true`. Ctrl+S и Ctrl+R (удержание) выключают CC на уровне игры, мы их не перехватываем.

## Виртуальные каталоги (`cfs.virtual`, `sysfs`)

Провайдер только для чтения: дерево таблиц и строк строится заново при каждом обращении, любое изменение даёт `EROFS`.

- **`/cubeos/proc`**: `<pid>/{status,cmdline,user,started,focus}`, `ps`, `uptime`, `version`, `meminfo`.
- **`/cubeos/run`**: `services/<имя>` (`running`, `failed`, `blocked`, `stopped`...), `session/<id>`, `boot.state` (режим, причина, число неудач, `unclean`).
- **`/cubeos/hardware`** (монтирует `devd`): `peripherals/<имя>/{type,methods}`, `displays`, `speakers`, `modems`, `drives`.

Права по умолчанию (`cfs.defaults`): все читают `/cubeos/proc`, `/run`, `/hardware`; `/cubeos/drives` читают все, пишут администраторы.

## Что дальше

Подключение к сессии (`cush` как оболочка сессии получает `time`, `time_save`, `power` через `svc.timeclient` и `rpc.call`), HAL (`gfx.caps()`, `audio.caps()`, `periph.has()` на запросах `devd`), уведомления о монтировании в `notifyd`, права в `permd`, атомарная запись для `logd` и конфигов (пункт 7 плана).
