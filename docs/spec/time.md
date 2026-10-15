# Время: `clock`, служба `timed`, `date`, `timedatectl`

Код: `lib/clock.cub` (чистая логика), `lib/svc/timed.cub` (служба), `lib/svc/rpc.cub` (запросы к службам), `lib/svc/timeclient.cub` (часы для процесса ядра), команды в `lib/cush/builtins.cub`, манифест `sys/services/timed.conf`, настройки по умолчанию `sys/cfg/time.conf`. Тесты `lib_clock`, `lib_svc_timed`, `lib_cush_time`, `lib_sys_files`. Решения D206, D212.

## Настройки (`/cubeos/sys/cfg/time.conf`, JSON5)

| Ключ | Значение |
|---|---|
| `source` | `utc` (реальное время, `os.epoch("utc")`) или `ingame` (время суток и день Minecraft) |
| `tz` | смещение (`+03:00`, `-0530`, `UTC+3`) или имя зоны (`Europe/Kyiv`, без учёта регистра); `timedatectl list-timezones [фильтр]` |
| `dst` | `auto` (правила зоны), `off`, либо смещение (`+01:00`), которое действует всегда |
| `seconds` | показывать секунды в часах (панель, `fetch`, `date`) |
| `format` | `24h` или `12h` |
| `date_format` | `strftime`-строка (по умолчанию `%Y-%m-%d`) |
| `week_start` | `monday`, `sunday`, `saturday` |
| `locale` | `en`, `ru`, `uk` (названия дней и месяцев; месяцы в родительном падеже) |
| `drift_ms` | порог расхождения с монотонным временем для события `time_changed` (по умолчанию 2000) |
| `zones` | свои зоны: `{"My/Zone": {offset: "+02:00", dst: "eu"}}` (`dst`: `""`, `eu`, `us`, `au`) |

Неверное значение заменяется значением по умолчанию, проблемы возвращает `clock.normalize` (служба при `set_conf` отклоняет такие изменения целиком).

## Зоны и летнее время

Встроенная таблица (около 80 зон): смещения и правила перехода `eu` (последнее воскресенье марта и октября, 01:00 UTC), `us` (второе воскресенье марта и первое ноября, 02:00 по местному), `au` (южное полушарие: с первого воскресенья октября по первое воскресенье апреля). Без базы IANA; история изменений правил не учитывается. Свои зоны добавляются в `zones`.

## `clock` (API)

`clock.new(conf, src)`; `src` это источники `{utc_ms, ingame_hours, ingame_day}` (подставляются в тестах). Методы: `now()`, `parts(ms)` (`year, month, day, hour, min, sec, wday` с 1 = воскресенье, `yday`, `isdst`, `offset_min`; метод назван `parts`, потому что `local` это ключевое слово Lua), `format(fmt, ms)` (`Y y m d e H I M S p A a B b j u w Z z F T R D s %`), `time_text()`, `date_text()` (при `source: ingame`: «Day N» и игровое время суток), `ingame()`, `zone()`, `set_conf(partial)`, `check_drift(utc, mono)`. Вспомогательные: `from_text`, `patch_text` (правка `time.conf` с сохранением комментариев через `json5.patch`), `zone_names`, `parse_offset`, `normalize`.

## Служба `timed` и `svc.rpc`

Запрос это сообщение `{op, args, sender, id}`, ответ `{id, result}` или `{id, error}`. Клиент: `rpc.call(sys, "timed", op, args, timeout)` возвращает результат или `nil, текст ошибки` (службы нет, нет ответа, служба ответила ошибкой). Операции: `now`, `parts`, `format`, `time_text`, `date_text`, `zone`, `ingame`, `get_conf`, `set_conf` (проверяет, применяет, сохраняет в файл, рассылает `time_changed`), `subscribe`/`unsubscribe`, `alarm {at, tag}` (до 256), `cancel_alarm`. События подписчикам (`sys.send`): `minute {ms, text}`, `time_changed {reason: "settings"|"drift"}`; будильник `alarm {tag, at, id}` приходит поставившему и без подписки. Дрейф проверяется не реже раза в 5 секунд (сравнение прироста `os.epoch` с монотонными часами ядра). Права на `set_conf` пока не проверяются (придёт с `permd`, шаг 6).

`svc.timeclient.new(sys)` даёт `{time, save, refresh}`: часы с настройками службы (расчёты у себя) и сохранение через службу; их оболочка получает как `time` и `time_save`. Без службы оболочка (`cush.main`) читает и пишет `time.conf` сама.

## Команды

- `date [-u] [-s] [+ФОРМАТ]`: без формата дата, время и зона по настройкам (`Thu 15 Oct 2026 15:00 UTC+03:00`; при `source: ingame` игровой день и время); `-u` UTC, `-s` секунды.
- `timedatectl [status | set-timezone ЗОНА | set-source utc|ingame | set-seconds on|off | set-format 12h|24h | list-timezones [фильтр]]`.
- `fetch` показывает дату и время из тех же часов.
