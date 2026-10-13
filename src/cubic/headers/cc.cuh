# CC: Tweaked API (subset) for Cubic strict mode.

class FileHandle:
    readAll: fn() -> str?
    readLine: fn(withTrailing: bool?) -> str?
    read: fn(count: num?) -> any
    write: fn(text: any)
    writeLine: fn(text: any)
    flush: fn()
    seek: fn(whence: str?, offset: num?) -> any
    close: fn()

open namespace term:
    def write(text: any)
    def blit(text: str, fg: str, bg: str)
    def clear()
    def clearLine()
    def getCursorPos() -> any
    def setCursorPos(x: num, y: num)
    def setCursorBlink(blink: bool)
    def getSize() -> any
    def scroll(n: num)
    def isColor() -> bool
    def setTextColor(color: num)
    def setBackgroundColor(color: num)
    def getTextColor() -> num
    def getBackgroundColor() -> num
    def setPaletteColor(color: num, r: num, g: num?, b: num?)
    def getPaletteColor(color: num) -> any
    def redirect(target: any) -> any
    def current() -> any
    def native() -> any

open namespace fs:
    def list(path: str) -> list[str]
    def exists(path: str) -> bool
    def isDir(path: str) -> bool
    def isReadOnly(path: str) -> bool
    def getName(path: str) -> str
    def getDir(path: str) -> str
    def getSize(path: str) -> num
    def getFreeSpace(path: str) -> num
    def getCapacity(path: str) -> num?
    def makeDir(path: str)
    def move(source: str, dest: str)
    def copy(source: str, dest: str)
    def delete(path: str)
    def combine(path: str, *rest: str) -> str
    def open(path: str, mode: str) -> FileHandle?
    def find(wildcard: str) -> list[str]
    def complete(partial: str, path: str, include_files: bool?, include_slashes: bool?) -> list[str]

open namespace peripheral:
    def getNames() -> list[str]
    def isPresent(name: str) -> bool
    def getType(name: any) -> any
    def hasType(name: any, type: str) -> bool?
    def getMethods(name: str) -> list[str]?
    def call(name: str, method: str, *args: any) -> any
    def wrap(name: str) -> any
    def find(type: str, filter: any?) -> any

open namespace rednet:
    def open(side: str)
    def close(side: str?)
    def isOpen(side: str?) -> bool
    def send(id: num, message: any, protocol: str?) -> bool
    def broadcast(message: any, protocol: str?)
    def receive(protocol: any?, timeout: num?) -> any
    def host(protocol: str, hostname: str)
    def unhost(protocol: str)
    def lookup(protocol: str, hostname: str?) -> any

open namespace redstone:
    def getSides() -> list[str]
    def getInput(side: str) -> bool
    def setOutput(side: str, on: bool)
    def getOutput(side: str) -> bool
    def getAnalogInput(side: str) -> num
    def setAnalogOutput(side: str, value: num)
    def getAnalogOutput(side: str) -> num

open namespace colors:
    white: num
    orange: num
    magenta: num
    lightBlue: num
    yellow: num
    lime: num
    pink: num
    gray: num
    lightGray: num
    cyan: num
    purple: num
    blue: num
    brown: num
    green: num
    red: num
    black: num

open namespace keys:
    def getName(code: num) -> str?

open namespace textutils:
    def serialize(value: any, options: any?) -> str
    def unserialize(text: str) -> any
    def serializeJSON(value: any, options: any?) -> str
    def unserializeJSON(text: str, options: any?) -> any
    def formatTime(time: num, twentyFour: bool?) -> str
    def slowPrint(text: str, rate: num?)
    def tabulate(*args: any)
    def pagedPrint(text: str, free_lines: num?) -> num
    def urlEncode(str: str) -> str

open namespace shell:
    def run(*args: str) -> bool
    def execute(command: str, *args: str) -> bool
    def dir() -> str
    def setDir(dir: str)
    def resolve(path: str) -> str
    def getRunningProgram() -> str
    def openTab(*args: str) -> num

open namespace http:
    def get(url: any, headers: any?, binary: bool?) -> any
    def post(url: any, body: str?, headers: any?, binary: bool?) -> any
    def request(url: any, body: str?, headers: any?, binary: bool?)
    def checkURL(url: str) -> any

open namespace turtle:
    def forward() -> any
    def back() -> any
    def up() -> any
    def down() -> any
    def turnLeft() -> any
    def turnRight() -> any
    def dig(side: str?) -> any
    def digUp(side: str?) -> any
    def digDown(side: str?) -> any
    def place(text: str?) -> any
    def placeUp(text: str?) -> any
    def placeDown(text: str?) -> any
    def select(slot: num) -> bool
    def getSelectedSlot() -> num
    def getItemCount(slot: num?) -> num
    def getItemSpace(slot: num?) -> num
    def getItemDetail(slot: num?, detailed: bool?) -> any
    def getFuelLevel() -> any
    def getFuelLimit() -> any
    def refuel(count: num?) -> any
    def suck(count: num?) -> any
    def suckUp(count: num?) -> any
    def suckDown(count: num?) -> any
    def drop(count: num?) -> any
    def dropUp(count: num?) -> any
    def dropDown(count: num?) -> any
    def attack(side: str?) -> any
    def detect() -> bool
    def detectUp() -> bool
    def detectDown() -> bool
    def inspect() -> any
    def inspectUp() -> any
    def inspectDown() -> any
    def compare() -> bool
    def transferTo(slot: num, count: num?) -> bool
    def equipLeft() -> any
    def equipRight() -> any

open namespace parallel:
    def waitForAny(*fns: any)
    def waitForAll(*fns: any)

open namespace settings:
    def set(name: str, value: any)
    def get(name: str, default: any?) -> any
    def unset(name: str)
    def clear()
    def save(path: str?) -> bool
    def load(path: str?) -> bool

open namespace window:
    def create(parent: any, x: num, y: num, width: num, height: num, visible: bool?) -> any

open namespace paintutils:
    def drawPixel(x: num, y: num, color: num?)
    def drawLine(x1: num, y1: num, x2: num, y2: num, color: num?)
    def drawBox(x1: num, y1: num, x2: num, y2: num, color: num?)
    def drawFilledBox(x1: num, y1: num, x2: num, y2: num, color: num?)
    def loadImage(path: str) -> any
    def drawImage(image: any, x: num, y: num)

open namespace vector:
    def new(x: num?, y: num?, z: num?) -> any

open namespace disk:
    def isPresent(side: str) -> bool
    def getLabel(side: str) -> str?
    def setLabel(side: str, label: str?)
    def hasData(side: str) -> bool
    def getMountPath(side: str) -> str?
    def getID(side: str) -> num?

open namespace gps:
    def locate(timeout: num?, debug: bool?) -> any

open namespace multishell:
    def getCurrent() -> num
    def getCount() -> num
    def launch(env: any, path: str, *args: any) -> num
    def setTitle(n: num, title: str)

open namespace pocket:
    def equipBack() -> any
    def unequipBack() -> any

open namespace commands:
    def exec(command: str) -> any
