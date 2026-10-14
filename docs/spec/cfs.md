# CFS: Cube File System

Код: `lib/cfs/` (написан на Cubic, тесты `tests/cases/lib_cfs_*.cub`). Решения: D115–D128 в [08-decisions-log.md](../08-decisions-log.md). Структура дерева: [02-filesystem.md](../02-filesystem.md).

## Быстрый старт

```cubic
import cfs

fsys = cfs.new()
fsys:mount("/", cfs.host("/cubeos-data"))      # настоящий диск
fsys:mount("/cubeos/tmp", cfs.tmp(65536))      # tmp в памяти, лимит 64 КБ
cfs.install_defaults(fsys)                     # стандартные права и очистка tmp

v = cfs.view(fsys, cfs.subject("ivan"), {aliases: cfs.default_aliases("ivan", "chess")})
v:write("$appdata/save.json", "{}")
for e in v:list("$home/documents"):
    print(e.name, e.type, e.size)
for path in v:glob("$projects/**/*.cub"):
    print(path)
with v:open("$docs/note.txt", "w") as f:
    f:write_line("привет")
```

## Слои

| Модуль | Назначение |
|---|---|
| `cfs.core` | ядро: точки монтирования, ссылки `.sym`, права, важные файлы, корзина, блокировки, события, tmp |
| `cfs.view` | вид процесса: субъект, `$алиасы`, виртуальный корень, `glob`, `walk` |
| `cfs.memory`, `cfs.host` | провайдеры: память и настоящий диск CC (`fs`) |
| `cfs.rules` | правила доступа по путям |
| `cfs.legacy` | замещённый `fs` для старых программ |
| `cfs.defaults` | стандартные права `/cubeos` и очистка tmp |
| `cfs.path`, `cfs.errors`, `cfs.handle`, `cfs.trash` | пути и имена, ошибки с кодами, дескрипторы, корзина |

Ядро принимает субъекта первым аргументом (`nil` это система, ей всё разрешено) и настоящие пути. Программы пользуются видом (`cfs.view`).

## Пути и имена

- Разделитель `/`, `..` и `.` сворачиваются, выше корня не выйти.
- `$алиас` целым сегментом: `$home/a.txt`. Алиасы могут ссылаться на другие, циклы дают `ELOOP`. Стандартные: `$sys $var $shared $apps $user $home $userapps $docs $pictures $videos $projects $desktop $cfg $cache $trash $tmp $mnt`, для приложения `$appdata` и `$shareddata`.
- Имя: UTF-8 (кириллица можно), нельзя управляющие символы и `\ : * ? " < > |`, пробел и точку в конце, больше 64 байт, `.`/`..`, оканчивающиеся на `.sym` (зарезервировано под ссылки), совпадающие с существующим только регистром.
- Скрытые: начинаются с `.`. Важные: начинаются с `!`.

## Права

Правила `{path, allow: {субъект: "rwxl"}}`: `r` чтение, `w` запись, `x` выполнение, `l` список. Побеждает самое конкретное совпавшее правило целиком; пути без правил закрыты; `system` не ограничена; `$user` в шаблоне это имя пользователя; субъект правила имя, роль, группа или `*`. Явных запретов нет.

Субъект: `cfs.subject(имя, роли, группы)`, роли `user`, `admin`, `system`.

## Важные файлы (`!`)

Создание, изменение, удаление, перенос и ссылки на путь с `!` в любой части: только `admin` и после подтверждения (`confirm(операция, путь, субъект) -> bool`, обработчик задаёт ядро). Без обработчика или при отказе `ECONFIRM`. Обычному пользователю `EACCES`. `system` без вопросов. Чтение по обычным правилам.

## Ссылки

`v:link(цель, путь)` создаёт файл `путь.sym` (первая строка цель). В списках видна как `путь` с типом `link`. Поиск `foo` при промахе проверяет `foo.sym` (глубина 16, `ELOOP`). `remove` на ссылке удаляет ссылку. В ограниченном виде ссылки не выводят за привязки.

## Операции вида (`cfs.view`)

| Метод | Описание |
|---|---|
| `read(p)`, `write(p, data)`, `append(p, data)`, `open(p, "r"/"w"/"a")` | файлы; запись атомарная (временный файл рядом, потом замена) |
| `list(p, {hidden})`, `stat(p)`, `lstat(p)`, `exists(p)`, `is_file`, `is_dir`, `readlink` | сведения |
| `mkdir(p, {parents})`, `remove(p, {recursive, permanent})`, `copy`, `move` (`overwrite`, внутрь каталога) | изменения, между дисками копирование и удаление |
| `link(цель, путь)` | ссылка |
| `glob(шаблон, {type, hidden})`, `walk(p)` | поиск: `*`, `?`, `**` |
| `lock(p, "shared"/"exclusive")`, `unlock` | рекомендательные блокировки |
| `watch(префикс, fn)`, `unwatch(id)` | события `create`, `modify`, `delete`, `move` |
| `space(p)`, `rights(p)`, `chdir(p)` | место (`warn` при 90%), права, рабочий каталог |
| `trash_items`, `trash_restore`, `trash_purge`, `trash_empty` | корзина |

Ошибки: объекты `CfsError` с полем `code`: `ENOENT EEXIST ENOTDIR EISDIR EACCES EINVAL ENAME ENOSPC ELOOP ENOTEMPTY EROFS ECONFIRM EBUSY EIO`.

```cubic
try:
    v:read("$home/missing.txt")
except Error as e:
    if e.code == "ENOENT": ...
```

## Виртуальный корень

`binds: [{path: "/data", to: "$appdata", mode: "rw"}, {path: "/docs", to: "$docs", mode: "ro"}]`: приложение видит только `/data` и `/docs`, настоящие пути и выход за привязки (`..`, ссылки) недоступны, ошибки показывают виртуальные пути.

## Корзина

Настройка: `fsys:set_trash(пользователь, путь, max_bytes, enabled)`; по умолчанию `/cubeos/users/<имя>/trash`, 128 КБ. Корзина может лежать на другом диске. Не уходит в корзину: `permanent`, пути из `no_trash` (в стандартных настройках `tmp`, `sys`, `var`, `proc`, `run`), сама корзина. Переполнение вытесняет самое старое; элемент больше лимита не помещается (`ENOSPC`).

## tmp, место, события

- `cfs.tmp(лимит)` провайдер в памяти. Очистка: `fsys:clean(субъект, путь, {older_than, all})`, по расписанию `fsys:schedule_clean(путь, интервал, возраст)` и вызов `fsys:tick()` из ядра.
- `fsys:space(путь)` даёт `free`, `capacity`, `used`, `warn`. У точки монтирования есть резерв (`reserve`): обычные субъекты не могут занять его, `system` может.
- События: `watch` и, при `emit_events`, очередь `cfs_change`.

## Замещённый fs

`cfs.legacy_fs(вид)` возвращает таблицу с `list exists isDir isReadOnly getSize getFreeSpace getCapacity makeDir delete move copy open find combine getName getDir attributes getDrive`. Дескрипторы в стиле CC (`h.readLine()`, `h.write(x)`, `h.close()`); ошибки строками `"/путь: причина"`; `delete` окончательное.

## Провайдеры

Интерфейс (пути внутри провайдера абсолютные): `stat`, `list`, `read`, `write`, `mkdir`, `remove`, `move`, `copy` (необязательно), `free_space`, `capacity`, `is_readonly`. Остальные (сетевой том, `.cpk`, облако) добавляются так же; для `.cpk` файлы внутри сжимаются по отдельности, оглавление в начале (D126).

## Известные ограничения

- Нет квот по пользователям и приложениям (только резерв и предупреждение).
- Дескрипторы буферизуют файл целиком (диск маленький); потоковое чтение для больших файлов позже.
- Имена файлов с кириллицей зависят от хоста: проверяется скриптом `game/names.lua` (эмулятор может искажать такие имена).
