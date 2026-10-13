# CubeOS 2.0

Операционная система для **CC: Tweaked** (Minecraft), работающая поверх CraftOS.

> "2.0" это название системы, как у Windows 7 или XP. Версии выпусков считаются отдельно по SemVer (`MAJOR.MINOR.PATCH`, плюс `-alpha`, `-beta`, `-rc.N`).

**Статус: планирование.** Кода пока нет, только документация.

## Что это

- Своя ОС-надстройка: ядро, VFS с симлинками, оконный и текстовый режимы.
- Свой язык **Cubic** (`.cub`): питоноподобный синтаксис с отступами, компилируется в Lua.
- Пакеты `.cpk`, установщики `.stp`, онлайн-магазин на GitHub, облачные хранилища.
- Работает с аддонами (CC: Graphics, High Quality Speaker, ...) и без них.
- Встроенные игры: шахматы, Wordle, змейка, тетрис, понг, морской бой.

## Документация

| Файл | Тема |
|---|---|
| [docs/00-overview.md](docs/00-overview.md) | Цели, принципы, версионность, глоссарий |
| [docs/01-architecture.md](docs/01-architecture.md) | Слои, загрузка, ядро, HAL, песочница |
| [docs/02-filesystem.md](docs/02-filesystem.md) | VFS, симлинки, шорткаты `$`, структура каталогов |
| [docs/03-file-formats.md](docs/03-file-formats.md) | Расширения, JSON5, `.cpk`, `.stp` |
| [docs/spec/language-cubic.md](docs/spec/language-cubic.md) | Замысел языка Cubic |
| [docs/spec/grammar.md](docs/spec/grammar.md) | Грамматика и семантика Cubic 0.3.0 (реализовано) |
| [docs/spec/types.md](docs/spec/types.md) | Типы, режим strict, заголовки `.cuh` |
| [docs/spec/stdlib.md](docs/spec/stdlib.md) | Стандартные и базовые библиотеки (`lib/`), загрузчик модулей |
| [docs/spec/toolchain.md](docs/spec/toolchain.md) | Компилятор, флаги, модули, минификация |
| [docs/04-ui-graphics-fonts.md](docs/04-ui-graphics-fonts.md) | Режимы UI, графика, шрифты, темы, i18n |
| [docs/05-packages-store-cloud.md](docs/05-packages-store-cloud.md) | Пакеты, магазин, облако, Pastebin/Gist/rednet |
| [docs/06-system-services.md](docs/06-system-services.md) | Буфер обмена, undo/redo, корзина, разрешения |
| [docs/07-apps-games.md](docs/07-apps-games.md) | Встроенные приложения и игры |
| [docs/08-decisions-log.md](docs/08-decisions-log.md) | Журнал принятых решений |
| [docs/09-open-questions.md](docs/09-open-questions.md) | Нерешённые вопросы |
| [docs/10-roadmap.md](docs/10-roadmap.md) | Этапы разработки |
| [docs/11-platform.md](docs/11-platform.md) | Дистрибутивы, DE, версии ОС, режим совместимости |
| [docs/12-permissions-capabilities.md](docs/12-permissions-capabilities.md) | Права, безопасность, возможности (caps) |
| [docs/dev/git-workflow.md](docs/dev/git-workflow.md) | Ветки, коммиты, релизы |
| [docs/dev/environment.md](docs/dev/environment.md) | Тестовый инстанс Minecraft, эмулятор CraftOS-PC |

Документы помечают непроверенные факты как **(проверить)**.

## Лицензия

MIT, см. [LICENSE](LICENSE).
