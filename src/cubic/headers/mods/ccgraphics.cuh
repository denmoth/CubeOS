# CC: Graphics 0.2 (CraftOS-PC compatible pixel mode for CC: Tweaked terminals).
# Checked against the mod's own Lua files and Java code (term.lua, window.lua, TermMethodsMixin).
#
# Modes:  false / 0  text mode (the default, characters only)
#         1 (true)    pixel mode with the 16 standard colors; color arguments are color constants
#                     (colors.red, or bit32.lshift(1, n)), the same values paintutils uses
#         2           pixel mode with a 256-color palette; color arguments are palette indexes 0..255
#                     (set them with term.setPaletteColor(index, r, g, b))
# Pixel coordinates start at 0,0 (text coordinates start at 1,1). term.getSize(true) returns the size in
# pixels, term.getSize() the size in characters. In pixel mode mouse events carry pixel coordinates.
# term.setFrozen(true) stops the screen from updating until term.setFrozen(false): use it to avoid flicker.

type PixelRows = list[list[num]] | list[str]

# the same methods exist on monitors and windows
class Terminal:
    setGraphicsMode: fn(mode: bool | num)
    getGraphicsMode: fn() -> bool | num
    setPixel: fn(x: num, y: num, color: num)
    getPixel: fn(x: num, y: num) -> num
    drawPixels: fn(x: num, y: num, pixels: PixelRows | num, width: num?, height: num?)
    getPixels: fn(x: num, y: num, width: num, height: num, asString: bool?) -> PixelRows
    setFrozen: fn(frozen: bool)
    getFrozen: fn() -> bool
    getSize: fn(pixels: bool | num?) -> any

open namespace term:
    def setGraphicsMode(mode: bool | num)
    def getGraphicsMode() -> bool | num
    def setPixel(x: num, y: num, color: num)
    def getPixel(x: num, y: num) -> num
    def drawPixels(x: num, y: num, pixels: PixelRows | num, width: num?, height: num?)
    def getPixels(x: num, y: num, width: num, height: num, asString: bool?) -> PixelRows
    def setFrozen(frozen: bool)
    def getFrozen() -> bool
    def getSize(pixels: bool | num?) -> any
