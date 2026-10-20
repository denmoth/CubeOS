# CubeOS

An operating system for CC: Tweaked computers in Minecraft. It runs on top of CraftOS.

This is version 0.1.0. It installs and boots, but it hasn't seen much use in real worlds yet, so expect rough edges.

## Install

On a clean computer with HTTP enabled:

```
wget run https://raw.githubusercontent.com/denmoth/cobble/main/install.lua
```

The packages come from [Cobble](https://github.com/denmoth/cobble). The text-only system takes about 500 KB of disk and
the desktop about 880 KB, so both fit on a default computer. If you want more than fits, a second computer connected by a
modem can hold some of the packages (run `pkghost.lua` from Cobble on it).

## What's in it

The kernel runs processes and system services (logging, time, input, fonts, sound, network, permissions) and has user
accounts with sudo. Files go through CFS, a virtual file system with mounts, access rules and a trash.

Cush is the shell. It has pipes, background jobs, tab completion, a text editor and built-in help in English, Russian and
Ukrainian. On a computer with CC: Graphics you also get CDE, a desktop with windows, a taskbar, a Start menu, themes and
wallpapers. It comes with a file manager (Axo), Settings, Notes, Pixel, Brush, Jukebox, Calc, Clock, a task manager
(Pulse) and the Store.

Most of the code is written in Cubic, a small Python-like language that compiles to Lua. Apps can also be plain Lua.

Packages are handled by `stew`. A package is a single compressed `.cpk` file, an install either finishes or is rolled
back, and besides Cobble it can install CraftOS programs from PineStore. The system itself is split into about a hundred
small packages, so you only keep what you use.

Design notes are in [docs/](docs/), written in Russian.

## License

MIT, see [LICENSE](LICENSE).
