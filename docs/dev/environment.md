# Среда разработки

## Тестовый инстанс Minecraft

Prism Launcher (портативный): `D:\PrismLauncher\instances\CubeOS Dev`.

- Minecraft 1.21.1, NeoForge 21.1.256 (как в CubeLand ReCreated).
- 52 мода, статическая проверка зависимостей чистая (отсутствующих обязательных зависимостей нет, несовместимых пар нет).
- Запускать инстанс в игре пока не пробовали. После создания в Prism может потребоваться перезапуск лаунчера, чтобы он появился в списке.

### Состав

**Из CubeLand ReCreated (скопированы как есть):**
- CC: Tweaked 1.120.2, CC: Graphics 0.2.1, CC:HQ Speakers 1.0.7.
- Create 6.0.10, Create Aeronautics (bundled) 1.3.2, Sable 2.0.6, Azimuth, Struts, Simulated Coasters, Create Better FPS.
- Оптимизация и клиент: Sodium, Sodium Extra, Reese's Sodium Options, Lithium, FerriteCore, ModernFix, ImmediatelyFast, Entity Culling, Dynamic FPS, Ksyxis, Iris + Iris Flywheel Compat, JEI, Jade, AppleSkin, Mouse Tweaks, Xaero's Minimap/World Map, spark.
- Библиотеки: Architectury, Cloth Config, YACL, Fzzy Config, Forgified Fabric API, Kotlin for Forge.

**Добавлено с Modrinth (хэши sha512 проверены):**
- Advanced Peripherals, Tom's Peripherals, CC:C Bridge, CC: Sable, Create: Avionics, Simulated: ComputerCraft Compat.
- CC: Tweaked Unicode Support (важно для кириллицы), CC Audio Expand (PCM-аудио), Classic Peripherals, Cricket's Peripherals, CCX, CC: Modern, CC:Gamepad, Universal Keyboard Controller, NeoPeripherals, CCSecureBoot.

**Из инстанса "All of CC-Tweaked":**
- MothPaste 1.0.0 (мод автора, многострочная вставка в компьютер).

Исходные инстансы CubeLand и All of CC-Tweaked не изменялись.

## Эмулятор CraftOS-PC

Установлен портативно: `D:\lin\Projects\MC\CC-Projects\_tools\CraftOS-PC` (v2.8.3, SHA-256 архива проверен). Вне репозитория.

- Эмулирует **ComputerCraft 1.112.0** и **Lua 5.2** (в игре CC 1.120.2 на Cobalt, это Lua 5.1 с добавлениями). Эмулятор годится для автотестов компилятора, но итоговую проверку делаем в игре. Есть различия: в эмуляторе есть `debug` и `bit32`, в игре `debug` ограничен.
- Запуск без окна, данные компьютера в `data\computer\0`:

```bash
CraftOS-PC_console.exe --headless -d "<папка данных>" --script "<файл.lua>"
```

- Вывод `print` в `--headless` не попадает в stdout, надёжный способ получать результат: записывать его в файл внутри компьютера (`fs.open`) и читать с диска.
- Параметры: `--mount <путь>=<папка>` (подключить папку проекта), `--exec "<код>"`.

## Lua на ПК

Отдельного Lua на машине нет. Тесты компилятора идут через CraftOS-PC. При необходимости ускорить прогоны можно поставить LuaJIT/Lua 5.1.
