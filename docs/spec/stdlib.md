# Стандартные и базовые библиотеки

Статус: **реализовано** в `lib/` (написаны на Cubic, проверены тестами в CraftOS-PC). Загружаются через `import` (см. загрузчик модулей в [toolchain.md](toolchain.md)).

## Загрузчик модулей

`cubic.new_loader({roots = [...], aliases = {...}, fs = ...})` даёт функции `import` для модулей:
- `import std.str`: поиск `std/str.cub` или `std/str.lua` в `roots`;
- `import ./util`, `import ../shared/x`: относительно файла;
- `import /abs/path/x`: абсолютный путь;
- `import $apps/snake/core`: через алиас.

Порядок поиска файла: `путь`, `.cub`, `.lua`, `путь/init.cub`, `путь/init.lua`. Модули кешируются, циклический импорт даёт ошибку. В ОС вместо файловой системы CC этот же загрузчик получит VFS.

## std (lib/std)

| Модуль | Функции |
|---|---|
| `std.str` | `split`, `join`, `lines`, `strip`/`lstrip`/`rstrip`, `startswith`, `endswith`, `find`, `count`, `replace`, `ljust`/`rjust`/`center`, `capitalize`, `title`, `is_blank`, `is_digits`, `is_alpha`, `iequals` |
| `std.list` | `map`, `filter`, `reduce`, `sum`, `any_of`, `all_of`, `count_if`, `index_of`, `contains`, `reverse`, `concat`, `flatten`, `unique`, `zip`, `take`, `drop`, `chunk`, `first`, `last`, `remove_value`, `extend`, `numbers`, `sorted` (устойчивая), `min_of`, `max_of`, `group_by` |
| `std.dict` | `keys`, `values`, `sorted_keys`, `items`, `count`, `is_empty`, `has`, `get`, `merge`, `pick`, `omit`, `from_pairs`, `map_values`, `invert` |
| `std.path` | `normalize`, `join`, `dirname`, `basename`, `extension`, `stem`, `split`, `is_absolute`, `relative` |
| `std.time` | по реальному (UTC) времени: `days_from_civil`, `civil_from_days`, `day_index` (для слова дня), `weekday`, `to_date`, `from_date`, `format_date`, `is_leap_year`, `now_ms` |
| `std.fmt` | `bytes` ("1.5 KB"), `duration` ("1h 2m 5s"), `thousands`, `percent` |

## Базовые библиотеки

| Модуль | Назначение | Проверено по |
|---|---|---|
| `semver` | `parse`, `compare`, `satisfies`, `max_satisfying`, `sort`, `inc`, `format`. Диапазоны npm: `^`, `~`, `>=`, `x`, `*`, `\|\|`, `a - b`, предрелизы | спецификация SemVer, таблица из 40 случаев |
| `json5` | `parse`, `stringify`, `patch`, `remove`. `patch` меняет или добавляет одно значение, не трогая комментарии, отступы и стиль кавычек | 65 проверок |
| `crc32` | CRC-32, поддерживает продолжение (`crc32(часть2, crc32(часть1))`) | Python zlib |
| `sha256` | `hex`, `digest`, `hmac`, `pbkdf2` (пароли) | Python hashlib/hmac |
| `base85` | алфавит Z85 для передачи через Pastebin (+25%) | вектор из спецификации Z85 |
| `lzfast` | быстрое сжатие в духе LZ4 (метод 1) | круговые проверки |
| `deflate` | `inflate`/`deflate` по RFC 1951 (динамический и фиксированный Хаффман, ленивый LZ77) | вектора и проверка потока настоящим zlib (`tools/verify_deflate.py`) |
| `compress` | контейнер: байт метода + размер + данные; `compress(data, "auto")` выбирает самый маленький из методов 0/1/2 | круговые проверки |

### Остальные библиотеки

| Модуль | Назначение |
|---|---|
| `json` | строгий JSON: `parse`, `stringify`, `null`, `array`; поверх разборщика json5 с режимом strict |
| `base64` | `encode(data, url_safe, pad)`, `decode`; векторы RFC 4648 |
| `url` | `encode`, `decode`, `query_parse`, `query_build`, `parse` |
| `unicode` | UTF-8: `codepoints`, `chars`, `length`, `sub`, `reverse`, `lower`, `upper`, `capitalize`, `is_valid`, `width`; регистр для латиницы, кириллицы, греческого |
| `rand` | детерминированный генератор xorshift32: `new(seed)`, `u32`, `float`, `int`, `choice`, `shuffle`, `sample`; `seed_from_string` (FNV-1a) для слова дня и общих сидов |
| `collections` | `Stack`, `Queue`, `Set`, `Heap`, `LRU` |
| `textwrap` | `wrap`, `fill`, `indent`, `truncate`, `pad_left`, `pad_right`, `center` |
| `argparse` | разбор аргументов команд: флаги, короткие склеенные, числа, списки, позиционные, `usage`, `help_text` |
| `history` | undo/redo с лимитом и склейкой подряд идущих действий |
| `log` | журнал с уровнями, кольцевой буфер, приёмник в файл |
| `event` | шина событий с приоритетами, `once`, `off` |
| `vec` | `Vec2`, `Vec3`, `Rect`, `clamp`, `lerp` |

## Особенности

- Скорость измерена только в эмуляторе. Реальные цифры в игровом CC (Cobalt) нужно снять отдельно, это влияет на выбор метода сжатия по умолчанию и на число итераций PBKDF2.
- В `semver`/`json5` и других библиотеках есть правило Cubic, которое легко нарушить: присваивание имени, уже определённому на уровне модуля, меняет это имя. Компилятор предупреждает, если так затирается функция, класс или импорт.
- Байтовые строки: все библиотеки работают с байтами, не с Unicode-символами.
