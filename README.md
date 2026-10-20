# CubeOS 2.0

An operating system for **CC: Tweaked** computers in Minecraft, running on top of CraftOS.

> "2.0" is the name of the system, like Windows 7 or XP. Releases are versioned separately with SemVer.

**Status: alpha (0.5.0).** It installs from the internet and runs; it has not been checked much in real game worlds yet.

## Install

On a clean ComputerCraft computer with HTTP enabled:

```
wget run https://raw.githubusercontent.com/denmoth/cobble/main/install.lua
```

Packages come from [Cobble](https://github.com/denmoth/cobble), the official catalog. The minimal text system takes about
500 KB, the desktop about 880 KB, so both fit the default 1 MB of a computer. A second computer can hold packages that do
not fit (`pkghost.lua` in Cobble).

## What is inside

- A kernel with processes, services (log, time, input, fonts, sound, network, permissions...), users and sudo.
- CFS: a virtual file system with mounts, rules, a trash, extenders (more storage from a floppy or another computer).
- **Cush**, a shell with pipes, jobs, completion, help in English, Russian and Ukrainian, a text editor.
- **CDE**, a desktop for CC: Graphics: windows, a taskbar, the Start menu, themes, wallpapers, widgets, a login screen.
- Apps: Axo (files), Settings, Pulse (tasks), Notes, Pixel, Brush, Jukebox, Calc, Clock, Store.
- **Cubic** (`.cub`), its own language: Python-like syntax with indents, compiled to Lua. Apps may also be plain Lua.
- **stew**, the package manager: `.cpk` packages (compressed, loaded lazily), whole-or-nothing installs with rollback,
  sources Cobble, PineStore, http and folders, publishing from inside the game.
- CubeNet: pairing, shared folders and remote folders between computers over modems.

The system itself is split into about a hundred small packages (`packages/system/`).

## Development

- `bash tools/test.sh [filter]` runs the tests in CraftOS-PC (headless).
- `bash tools/build_packages.sh` builds every system package into `build/packages/`.
- `bash tools/e2e_stew.sh <set> <storage>` installs a set on a clean emulated computer and boots the installed loader.
- `game/install_dev.lua` installs the boot chain from a copy of this repository inside the game.

The design documents are in [docs/](docs/) (written in Russian); the package system is described in
[docs/packages/](docs/packages/README.md).

## License

MIT, see [LICENSE](LICENSE).
