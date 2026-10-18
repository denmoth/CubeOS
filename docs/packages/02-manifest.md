# Манифест пакета `package.json5`

Лежит в корне исходников пакета. При сборке проверяется, дополняется (размеры, хэши, список файлов, версия сборщика) и кладётся
в `.cpk` без сжатия. Расширяет манифест из [03-file-formats.md](../03-file-formats.md); поля оттуда (`caps`, `platform`, `cubeos`)
остаются.

```json5
{
  format: 1,
  id: "denmoth.snake",            // автор.имя; системные пакеты: cubeos.<имя>
  name: "Snake",                  // показываемое имя (можно ключ перевода)
  version: "1.2.0",               // SemVer
  description: "Classic snake",
  author: "Denmoth", license: "MIT", homepage: "https://github.com/...",
  kind: "app",                    // app | lib | service | driver | theme | font | lang | data | de | meta | tool
  lang: "lua",                    // lua | cubic: на чём исходники; влияет только на сборку
  category: "games",              // для магазина: system, desktop, apps, games, dev, network, automation, media, assets
  priority: "optional",           // essential | recommended | optional: что можно вынести на второй компьютер

  cubeos: { min: "0.5.0", max: null },
  depends: { "cubeos.cdk": "^1.0" },
  want: { "cubeos.audiod": "^1.0" },     // поставить, если есть место; без него работает
  provides: [],                          // виртуальные имена: несколько тем дают "theme"
  conflicts: [],

  files: ["src/**", "assets/**"],        // что входит в пакет (по умолчанию всё, кроме build/ и .git)
  modules: { "snake": "src/init.lua" },  // имя модуля для import -> файл

  permissions: { need: ["gfx"], want: ["net.http"] },

  // что пакет даёт системе: stew включает при установке и убирает при удалении сам
  contributes: {
    apps: [{ id: "snake", name: "Snake", entry: "snake", icon: "assets/icon.cimg", category: "games" }],
    services: [],                        // { name, module, autostart }
    associations: [{ ext: ".snk", app: "snake" }],
    desktop_icons: [],
    autostart: [],
    settings: [],                        // страницы или значения по умолчанию в Настройках
    themes: [], fonts: [], wallpapers: [], langs: [], sounds: [], music: [],
  },

  // опции установки: одно описание, окно на рабочем столе и вопросы в терминале (04-installers.md)
  options: [
    { id: "packs", type: "multi", label: "Music packs", choices: ["retro", "calm"], default: ["retro"] },
    { id: "autostart", type: "bool", label: "Start with the desktop", default: false },
  ],

  setup: "setup.lua",                    // необязательный скрипт установщика (04-installers.md)
  storage: "auto",                       // подсказка: auto | packed | unpacked (пользователь может переопределить)
}
```

## Правила

- `id` уникален в источнике. Системные пакеты начинаются с `cubeos.`, пользователям это имя занимать нельзя (Cobble проверяет).
- Пакет `kind: "meta"` не содержит файлов, только зависимости (наборы `cubeos-minimal`, `cubeos-desktop`, `cubeos-full`).
- `lang` нужен только сборщику. Установленной системе всё равно: в пакете в любом случае Lua.
- Всё, что можно описать в `contributes`, описывается там, а не в скрипте установщика: тогда удаление чистое без кода автора.
- После сборки в манифест `.cpk` добавляются: `installed_size`, `files` с размерами и хэшами, `built_by` (версия stew/Cubic),
  `source` (откуда собран: адрес и коммит). Эти поля автор не пишет.
- Разрешения: имена из [12-permissions-capabilities.md](../12-permissions-capabilities.md). Новых не придумывать без записи туда.

## Приложение на Lua

Точка входа одинакова для Lua и Cubic: модуль возвращает таблицу с `main(sys, ctx)` (как `export def main` в Cubic).

```lua
-- src/init.lua
local cdk = import("cdk")       -- системные модули через import, как в Cubic

local M = {}
function M.main(sys, ctx)
  local ui = cdk.open(sys, ctx, { title = "Snake", w = 120, h = 90 })
  ui:set_root(cdk.label("Hello"))
  ui:run()
end
return M
```

Модуль на Lua загружается с окружением, где поверх `_G` есть `import(имя)`: `import("cdk")` ищет системный модуль,
`import("./view")` файл рядом. Модуль, скомпилированный из Cubic, получает то же самое через `...` (`local __rt, __import = ...`).
Глобальные переменные модуля на Lua пишутся в его окружение, а не в общий `_G`.

Обычные программы CraftOS (без API CubeOS, например из PineStore) это не приложения CubeOS: они запускаются через `compat` в окне
терминала (05-sources.md).
