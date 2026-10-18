# Системные пакеты CubeOS

Манифесты всей системы, разбитой на мелкие пакеты (docs/packages/07-system-split.md). Один пакет это один файл
`packages/system/<имя>.json5`, где `<имя>` это id без `cubeos.` (`cubeos.cfs` лежит в `cfs.json5`). Наборы: `minimal`, `desktop`, `full`,
`dev` (`kind: "meta"`, только зависимости; их id пишется через дефис: `cubeos.minimal`).

Системные пакеты собираются из самого репозитория, поэтому `files` это пути от корня репозитория (или шаблоны `*`, `**`), а не
пути внутри исходников пакета. Каждый файл из `lib/`, `sys/boot`, `sys/startup.lua`, `sys/services`, `sys/cfg`, `src/cubic`
и `assets/` (кроме `assets/private/`) входит ровно в один пакет. Поля `depends` выведены из настоящих строк `import`; `want` это
связи, которые код пока держит статическим `import`, но которые заменит база пакетов (лончер и загрузка рабочего стола).

## Проверка

```
python tools/pkg_graph.py            # отчёт в build/pkg-graph.txt, итог одной строкой
python tools/pkg_graph.py --table    # плюс таблица пакетов в markdown
```

Инструмент строит граф модулей (`import a.b`, службы из `sys/services/*.conf`, `import("...")` в `sys/boot/*.lua`), ищет циклы,
сверяет с манифестами: неразложенные и двойные файлы, недостающие `depends` (ошибка), лишние (предупреждение), essential только от
essential, recommended не от optional, наборы покрывают свои приоритеты, циклы между пакетами. Код выхода 1, если есть ошибки.
После любого добавления или переноса модуля прогоните его.

## Отличия от 07-system-split.md

Граф показал, что разбивку из 07 нельзя взять один в один. Что изменено и почему:

- `cubeos.cfs-base` (новый, `cfs/path`, `cfs/errors`): ядро CFS статически импортирует `trash`, `init` импортирует `legacy`, а те
  используют `path` и `errors` ядра. Без отдельной базы получался цикл `cfs <-> cfs-trash <-> cfs-legacy`.
- `cfs-trash` из R стал E: `cfs/core` его импортирует.
- `cubeos.term-chars` (новый, `term/chars`): `ui/out_pixel` и `compat/bios` берут `term.chars`, а `term/view` берёт `ui`; в одном
  пакете получался цикл `ui <-> term`.
- `cubeos.term-session` (новый: `term/app`, `term/session`, `cde/winout`): `cush/shell` использует `term/vterm`, а `term/session`
  использует `cush/shell` (цикл `term <-> cush`). `cde/winout` переехал сюда из `cde`: его импортирует `term/session`, а essential не может
  зависеть от рабочего стола.
- Cush разделён на `cush` (lex, hist, commands, help, builtins), `cush-shell` (shell), `cush-edit`, `cush-net`, `cush-tools`:
  `shell` импортирует все остальные, а `tools` импортируют `builtins`; в одном пакете с `shell` получался цикл. Из-за статических
  импортов все пять essential (раньше `-edit`, `-net`, `-tools` были R). Позже `shell` можно сделать ленивым и снова понизить их.
- `cubeos.audiod` из R стал E: `cush/tools2` берёт из него список инструментов. `cubeos.logo`, `cubeos.pixelbuf`, `cubeos.splash` тоже
  E: их статически требуют `font`, `cush/fetch` и `stage2` (заставка грузится безусловно).
- `cubeos.cgl` вобрал `quant` и `teletext` (их импортируют `graphics` и `cgl/init`), `cgl-image` остался только с `cimg`. `cgl` и
  `cgl-anim` стали E: текстовый `ui` (E) импортирует `cgl` и `cgl/anim`.
- `cubeos.cdk` вобрал `cdk/table` (импортируется из `cdk/init`, цикл). `cdk-gallery` из O стал R, потому что `cde/session`
  импортирует его.
- Рабочий стол CDE: `theme` вынесен в `cubeos.cde-theme` (его используют `wm`, `panel`, `cdk`; внутри `cde` был бы цикл),
  `tray` отделён от `panel` (`tray` импортирует `cdk`, а `cdk` через `cde/app` тянет `wm` и `panel`), `session` вынесен в
  `cubeos.cde-session` (вершина графа), `cde/apps` ушёл в `cde-startmenu`. `wallpaper_live` слит в `cde-wallpaper` (его импортирует
  `wallpaper`), `cde-fx` и `cde-widgets` из O стали R (импортируются `wm` и `session`).
- `app-kit` и `launcher` разделены: `launcher` импортирует все приложения, а они импортируют `kit` (цикл). Приложения `pixel`,
  `brush`, `jukebox`, `calc`, `clock` остаются O, а `launcher -> они` записаны как `want` (см. ниже).
- `cubeos.rpc` включает `svc/stub` (как в 07), `cubeos.cpk` теперь содержит `lib/cpk.cub` (уже написан в шаге 2a).
- `assets/fonts/CREDITS` лежит в `cubeos.font-cube-6x9`; `assets/sounds.txt` в `cubeos.audiod`; `sys/cfg/locale.conf` в `cubeos.i18n`.
- `cubeos.stew` берёт `lib/stew/*` (пока `stew pack`); `cubeos.stew-publish` и `cubeos.store` пока без кода (`files: []`), заданы только id, приоритет и зависимости.

## Мягкие связи (want) и что в коде потом поменять

- `app-launcher ~> brush, calc, clock, jukebox, pixel`: `CATALOG` в `launcher.cub` импортирует приложения. По плану 07 он читает
  установленные приложения из базы stew; тогда эти связи исчезнут.
- `boot ~> cde-session, cde-login`: `stage2.lua` импортирует `cde.session` и `cde.greeter` только если есть рабочий стол.
- Списки предзагрузки в `stage2.lua` (79 имён, включая модули R и O) тоже должны стать данными из базы пакетов.

## Таблица пакетов

Приоритет: E essential, R recommended, O optional. Размер это сумма размеров исходных файлов пакета в репозитории (`.cub`, `.lua`,
ресурсы), не размер `.cpk`.

| Пакет | Приоритет | Файлов | Размер, байт |
|---|---|---|---|
| `cubeos.audiod` | E | 4 | 30067 |
| `cubeos.auth` | E | 2 | 27615 |
| `cubeos.boot` | E | 4 | 29286 |
| `cubeos.cfs` | E | 11 | 80674 |
| `cubeos.cfs-base` | E | 2 | 7668 |
| `cubeos.cfs-legacy` | E | 1 | 5736 |
| `cubeos.cfs-trash` | E | 1 | 4690 |
| `cubeos.cgl` | E | 7 | 89824 |
| `cubeos.cgl-anim` | E | 2 | 23668 |
| `cubeos.collections` | E | 5 | 18030 |
| `cubeos.compat` | E | 4 | 32122 |
| `cubeos.compress` | E | 4 | 31101 |
| `cubeos.console` | E | 1 | 6875 |
| `cubeos.cpk` | E | 1 | 12799 |
| `cubeos.crashd` | E | 2 | 3468 |
| `cubeos.crypto` | E | 4 | 14365 |
| `cubeos.cubic-rt` | E | 1 | 16077 |
| `cubeos.cush` | E | 5 | 102430 |
| `cubeos.cush-edit` | E | 2 | 67877 |
| `cubeos.cush-net` | E | 2 | 14827 |
| `cubeos.cush-shell` | E | 1 | 45952 |
| `cubeos.cush-tools` | E | 2 | 43323 |
| `cubeos.devd` | E | 2 | 6554 |
| `cubeos.encoding` | E | 3 | 7219 |
| `cubeos.font` | E | 2 | 15919 |
| `cubeos.font-cube-6x9` | E | 2 | 9464 |
| `cubeos.greeter` | E | 1 | 12980 |
| `cubeos.hal` | E | 2 | 6892 |
| `cubeos.i18n` | E | 2 | 6341 |
| `cubeos.init` | E | 4 | 52690 |
| `cubeos.inputd` | E | 3 | 16497 |
| `cubeos.json` | E | 2 | 25891 |
| `cubeos.kernel` | E | 3 | 42721 |
| `cubeos.log` | E | 3 | 11029 |
| `cubeos.logd` | E | 3 | 19138 |
| `cubeos.logo` | E | 1 | 3382 |
| `cubeos.permd` | E | 2 | 5900 |
| `cubeos.pixelbuf` | E | 1 | 2774 |
| `cubeos.powerd` | E | 2 | 2139 |
| `cubeos.rescue` | E | 2 | 7861 |
| `cubeos.rpc` | E | 2 | 4970 |
| `cubeos.splash` | E | 1 | 27514 |
| `cubeos.std` | E | 6 | 17006 |
| `cubeos.stew` | E | 1 | 10464 |
| `cubeos.term` | E | 4 | 41222 |
| `cubeos.term-chars` | E | 1 | 7182 |
| `cubeos.term-session` | E | 3 | 30079 |
| `cubeos.text` | E | 3 | 13204 |
| `cubeos.time` | E | 2 | 49690 |
| `cubeos.timed` | E | 4 | 7871 |
| `cubeos.ui` | E | 15 | 163605 |
| `cubeos.version` | E | 2 | 9666 |
| `cubeos.app-kit` | R | 1 | 18879 |
| `cubeos.app-launcher` | R | 1 | 3794 |
| `cubeos.avatars` | R | 7 | 1857 |
| `cubeos.axo` | R | 5 | 115780 |
| `cubeos.branding` | R | 4 | 2000 |
| `cubeos.cde` | R | 5 | 89707 |
| `cubeos.cde-crashbox` | R | 1 | 1663 |
| `cubeos.cde-fx` | R | 1 | 10596 |
| `cubeos.cde-icons` | R | 1 | 9509 |
| `cubeos.cde-login` | R | 3 | 48674 |
| `cubeos.cde-panel` | R | 1 | 17135 |
| `cubeos.cde-session` | R | 1 | 23004 |
| `cubeos.cde-startmenu` | R | 2 | 9657 |
| `cubeos.cde-terminal` | R | 1 | 911 |
| `cubeos.cde-theme` | R | 1 | 11364 |
| `cubeos.cde-tray` | R | 1 | 15885 |
| `cubeos.cde-wallpaper` | R | 2 | 26991 |
| `cubeos.cde-widgets` | R | 1 | 8616 |
| `cubeos.cdk` | R | 10 | 114852 |
| `cubeos.cdk-gallery` | R | 1 | 4310 |
| `cubeos.cgl-image` | R | 1 | 4048 |
| `cubeos.clipboard` | R | 2 | 2003 |
| `cubeos.extender` | R | 4 | 45788 |
| `cubeos.fontd` | R | 3 | 3504 |
| `cubeos.netd` | R | 6 | 50627 |
| `cubeos.notes` | R | 2 | 37581 |
| `cubeos.notifyd` | R | 2 | 2806 |
| `cubeos.pulse` | R | 1 | 12690 |
| `cubeos.settings` | R | 1 | 22209 |
| `cubeos.store` | R | 0 | 0 |
| `cubeos.theme-dark` | R | 1 | 1279 |
| `cubeos.wallpaper-aurora` | R | 1 | 7086 |
| `cubeos.brush` | O | 1 | 26211 |
| `cubeos.calc` | O | 2 | 15497 |
| `cubeos.cgl-3d` | O | 1 | 9782 |
| `cubeos.clock` | O | 1 | 17508 |
| `cubeos.cubic` | O | 8 | 198843 |
| `cubeos.cubic-tools` | O | 5 | 84977 |
| `cubeos.font-cube-5x7` | O | 1 | 2772 |
| `cubeos.font-cube-8x16` | O | 1 | 2878 |
| `cubeos.font-cube-mono-6x9` | O | 1 | 3406 |
| `cubeos.jukebox` | O | 2 | 29621 |
| `cubeos.lang-ru` | O | 4 | 85688 |
| `cubeos.lang-uk` | O | 4 | 85017 |
| `cubeos.music-block-sunrise` | O | 1 | 6561 |
| `cubeos.music-neon-drive` | O | 1 | 22388 |
| `cubeos.music-nether-lullaby` | O | 1 | 6940 |
| `cubeos.music-pixel-parade` | O | 1 | 5666 |
| `cubeos.music-redstone-rave` | O | 1 | 10879 |
| `cubeos.pixel` | O | 1 | 12742 |
| `cubeos.stew-publish` | O | 0 | 0 |
| `cubeos.theme-light` | O | 1 | 1276 |
| `cubeos.theme-nord` | O | 1 | 1290 |
| `cubeos.theme-tokyo-night` | O | 1 | 1874 |
| `cubeos.ui-toys` | O | 1 | 22929 |
| `cubeos.wallpaper-creeper` | O | 1 | 3932 |
| `cubeos.wallpaper-night-city` | O | 1 | 1619 |
| `cubeos.wallpaper-sunset` | O | 1 | 1221 |
| `cubeos.wallpaper-sus` | O | 1 | 807 |
| `cubeos.desktop` | - | 0 | 0 |
| `cubeos.dev` | - | 0 | 0 |
| `cubeos.full` | - | 0 | 0 |
| `cubeos.minimal` | - | 0 | 0 |
