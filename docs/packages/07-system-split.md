# Система, разбитая на мелкие пакеты

Решение владельца: **целиком вся система, тонна мелких пакетов.** Ниже черновая разметка по текущему `lib`, `sys`, `assets`, `src`.
Окончательные границы и зависимости шаг 2b выводит из настоящего графа импортов (`tools/pkg_graph.lua`, новый): если два модуля
всегда импортируют друг друга, они идут в один пакет; если модуль тянет половину системы, его зависимости честно пишутся в
манифест. Разметку можно уточнять, но не укрупнять обратно в 5-6 пакетов.

Мелкие пакеты не тратят место зря: каждый это один файл `.cpk` (01-cpk-format.md), а распакованные системные пакеты при способе
«авто» объединяются по месту на диске только если это выгодно (решается замером).

Обозначения приоритета: **E** essential (без него не загрузится), **R** recommended (входит в рабочий стол), **O** optional
(можно вынести на второй компьютер или не ставить).

## Загрузка и ядро

| Пакет | Что внутри | Пр. |
|---|---|---|
| `cubeos.boot` | `sys/boot/stage1.lua`, `stage2.lua`, `runtime.lua`, `sys/startup.lua` | E |
| `cubeos.rescue` | `sys/boot/rescue.lua`, `diskboot.lua` | E |
| `cubeos.cubic-rt` | `src/cubic/rt.lua` (рантайм для всего кода Cubic) | E |
| `cubeos.kernel` | `lib/kernel/*` | E |
| `cubeos.compat` | `lib/compat/*` (bios, env, proc, vararg): программы CraftOS | E |
| `cubeos.hal` | `hal`, `sysfs` | E |

## Базовые библиотеки

| Пакет | Что внутри | Пр. |
|---|---|---|
| `cubeos.std` | `lib/std/*` | E |
| `cubeos.collections` | `collections`, `box`, `vec`, `event`, `history` | E |
| `cubeos.text` | `textwrap`, `unicode`, `argparse` | E |
| `cubeos.json` | `json`, `json5` | E |
| `cubeos.compress` | `deflate`, `lzfast`, `compress`, `crc32` (распаковщик: всегда распакован) | E |
| `cubeos.encoding` | `base64`, `base85`, `url` | E |
| `cubeos.crypto` | `sha256`, `chacha20`, `x25519`, `rand` | E |
| `cubeos.version` | `semver`, `version` | E |
| `cubeos.log` | `log`, `chainlog`, `crash` | E |
| `cubeos.i18n` | `i18n` | E |
| `cubeos.time` | `clock`, `tzdata` | E |
| `cubeos.font` | `font`, `fonts` (код; сами шрифты отдельно) | E |
| `cubeos.pixelbuf` | `pixelbuf` | R |
| `cubeos.logo` | `logo` | R |

## Файловая система

| Пакет | Что внутри | Пр. |
|---|---|---|
| `cubeos.cfs` | `core`, `path`, `handle`, `errors`, `init`, `view`, `virtual`, `memory`, `host`, `rules`, `defaults`, `atomic`, `journal` | E |
| `cubeos.cfs-legacy` | `cfs/legacy` | E |
| `cubeos.cfs-trash` | `cfs/trash` | R |
| `cubeos.cpk` | читатель и монтирование `.cpk` (новый, шаг 2a/3) | E |
| `cubeos.extender` | `cfs/extend`, `cfs/extlabel`, `svc/extd`, `sys/services/extd.conf` | R |

## Службы (каждая отдельно, со своим `sys/services/*.conf` и `sys/cfg/*.conf`)

| Пакет | Что внутри | Пр. |
|---|---|---|
| `cubeos.rpc` | `svc/rpc`, `svc/stub` | E |
| `cubeos.logd` | `svc/logd`, `log.conf` | E |
| `cubeos.timed` | `svc/timed`, `svc/timeclient`, `time.conf` | E |
| `cubeos.devd` | `svc/devd` | E |
| `cubeos.inputd` | `svc/inputd`, `lib/input/*` | E |
| `cubeos.permd` | `svc/permd` | E |
| `cubeos.powerd` | `svc/powerd` | E |
| `cubeos.crashd` | `svc/crashd` | E |
| `cubeos.fontd` | `svc/fontd`, `fonts.conf` | R |
| `cubeos.audiod` | `svc/audiod`, `audio.conf`, `assets/sounds.txt` | R |
| `cubeos.clipboard` | `svc/clipboard` | R |
| `cubeos.notifyd` | `svc/notifyd` | R |
| `cubeos.netd` | `svc/netd`, `lib/net/*`, `net.conf` | R |

## Загрузочный интерфейс и вход

| Пакет | Что внутри | Пр. |
|---|---|---|
| `cubeos.init` | `boot/init`, `boot/services`, `boot/state`, `boot/session` | E |
| `cubeos.console` | `boot/console` | E |
| `cubeos.auth` | `boot/auth`, `boot/diskkey` | E |
| `cubeos.splash` | `boot/splash` | R |
| `cubeos.greeter` | `boot/greeter` (текстовый вход) | E |

## Текстовый режим

| Пакет | Что внутри | Пр. |
|---|---|---|
| `cubeos.term` | `lib/term/*` | E |
| `cubeos.ui` | `lib/ui/*` кроме `toys` | E |
| `cubeos.ui-toys` | `ui/toys` | O |
| `cubeos.cush` | `cush/shell`, `lex`, `builtins`, `commands`, `hist`, `help` | E |
| `cubeos.cush-edit` | `cush/editor`, `cush/textedit` | R |
| `cubeos.cush-net` | `cush/fetch`, `cush/nettools` | R |
| `cubeos.cush-tools` | `cush/tools`, `cush/tools2` | R |

## Графика и виджеты

| Пакет | Что внутри | Пр. |
|---|---|---|
| `cubeos.cgl` | `cgl/init`, `graphics`, `surface`, `color`, `mirror` | R |
| `cubeos.cgl-image` | `cgl/cimg`, `cgl/quant` | R |
| `cubeos.cgl-anim` | `cgl/anim`, `cgl/fx` | R |
| `cubeos.cgl-teletext` | `cgl/teletext` | R |
| `cubeos.cgl-3d` | `cgl/g3d` | O |
| `cubeos.cdk` | `cdk/init`, `ui`, `widget`, `style`, `controls`, `input`, `lists`, `popup`, `icons` | R |
| `cubeos.cdk-table` | `cdk/table` | R |
| `cubeos.cdk-gallery` | `cdk/gallery` | O |

## Рабочий стол CDE

| Пакет | Что внутри | Пр. |
|---|---|---|
| `cubeos.cde` | `wm`, `window`, `winout`, `compositor`, `app`, `apps`, `theme`, `init`, `session` | R |
| `cubeos.cde-icons` | `cde/icons` | R |
| `cubeos.cde-panel` | `panel`, `tray` | R |
| `cubeos.cde-startmenu` | `startmenu` | R |
| `cubeos.cde-login` | `login`, `lock`, `greeter` | R |
| `cubeos.cde-wallpaper` | `wallpaper` | R |
| `cubeos.cde-wallpaper-live` | `wallpaper_live` | O |
| `cubeos.cde-widgets` | `widgets` | O |
| `cubeos.cde-fx` | `cde/fx` | O |
| `cubeos.cde-terminal` | `cde/terminal` | R |
| `cubeos.cde-crashbox` | `crashbox` | R |

## Приложения

| Пакет | Что внутри | Пр. |
|---|---|---|
| `cubeos.app-kit` | `apps/kit`, `apps/launcher` (общие куски; launcher читает установленные приложения из базы stew, а не из списка в коде) | R |
| `cubeos.axo` | `apps/axo/*` | R |
| `cubeos.settings` | `apps/settings/*` | R |
| `cubeos.pulse` | `apps/pulse/*` | R |
| `cubeos.notes` | `apps/notes/*` | R |
| `cubeos.calc` | `apps/calc/*` | O |
| `cubeos.clock` | `apps/clock/*` | O |
| `cubeos.pixel` | `apps/pixel/*` | O |
| `cubeos.brush` | `apps/brush/*` | O |
| `cubeos.jukebox` | `apps/jukebox/*` (без треков) | O |
| `cubeos.store` | магазин (новый, шаг 7; имя в 08-setup-and-store.md) | R |

## Ресурсы (каждый отдельным пакетом)

| Пакет | Что внутри | Пр. |
|---|---|---|
| `cubeos.font-cube-6x9` | шрифт по умолчанию | E |
| `cubeos.font-cube-5x7`, `-8x16`, `-mono-6x9` | остальные шрифты | O |
| `cubeos.theme-dark` | тема по умолчанию | R |
| `cubeos.theme-light`, `-nord`, `-tokyo-night` | темы | O |
| `cubeos.wallpaper-aurora` | обои по умолчанию | R |
| `cubeos.wallpaper-creeper`, `-night-city`, `-sunset`, `-sus` | обои | O |
| `cubeos.avatars` | `assets/avatars/*` | R |
| `cubeos.music-<трек>` | каждый трек `assets/music/*.csc` | O |
| `cubeos.lang-ru`, `cubeos.lang-uk` | переводы | O (свой язык ставится как R) |
| `cubeos.branding` | `assets/images/*`, `assets/icons/*` | R |

`assets/private/` в пакеты не идёт (шрифт под вопросом лицензии). Личные обои владельца тоже никогда.

## Разработка

| Пакет | Что внутри | Пр. |
|---|---|---|
| `cubeos.cubic` | `src/cubic/*` кроме `rt.lua` и `tooling.lua` (компилятор) | O |
| `cubeos.cubic-tools` | `src/cubic/tooling.lua`, `headers/` (подсказки, проверка типов) | O |
| `cubeos.stew` | менеджер пакетов: ядро, адаптеры источников, `stew pack` | E |
| `cubeos.stew-publish` | `stew login/publish` (клиент Worker) | O |

## Наборы (`kind: "meta"`)

| Набор | Состав |
|---|---|
| `cubeos.minimal` | все **E**: загрузка, текстовый режим, cush, stew |
| `cubeos.desktop` | minimal + все **R** |
| `cubeos.full` | desktop + все **O** |
| `cubeos.dev` | `cubeos.cubic`, `cubeos.cubic-tools`, `cubeos.stew-publish` |

## Что меняется в коде из-за разбивки

- `sys/boot/stage2.lua`: список предзагрузки берётся из базы установленных пакетов, а не из списка в коде.
- `lib/apps/launcher.cub` (`CATALOG`) и регистрация приложений: из `contributes.apps` установленных пакетов.
- Темы, шрифты, обои, языки, музыка: ищутся по `contributes`, а не по фиксированным папкам `assets/`.
- Службы: включаются по `contributes.services`.

## Потом (записано, сейчас не делаем)

Новые пакеты, которые обсуждали; делать только после основы и проверки в игре:

- Система: обновление ОС через stew, пользователи, периферия (мониторы, динамики, модемы, принтеры), сетевой центр, GPS, поиск Just,
  док, скриншоты, рабочий стол со значками в стиле KDE, переделка меню «Пуск», скины тем (D256).
- Сеть: мессенджер, почта, файловый сервер, браузер CubeOS-сайтов, свой веб-сервер.
- Автоматизация: панель редстоуна с расписаниями, менеджер сундуков, мониторинг энергии.
- Разработка: REPL, отладчик, профайлер, просмотр логов.
- Утилиты: архиватор (`.cpk`, `.cbx`, zip), анализ занятого места, экранная клавиатура, мини-плеер.
- Игры: змейка, тетрис, сапёр, 2048, пасьянс, сетевые крестики-нолики и морской бой.
- Наборы тем, иконок, шрифтов, обоев, музыки, языков.
