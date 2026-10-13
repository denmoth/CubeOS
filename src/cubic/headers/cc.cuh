# CC: Tweaked API for Cubic strict mode (types of functions, peripherals and handles).
# Functions that return several values are typed `any`. Namespaces are open: members that are not listed are `any`.

# ------------------------------------------------------------------ handles

class FileHandle:
    readAll: fn() -> str?
    readLine: fn(withTrailing: bool?) -> str?
    read: fn(count: num?) -> any
    write: fn(text: any)
    writeLine: fn(text: any)
    flush: fn()
    seek: fn(whence: str?, offset: num?) -> any
    close: fn()

class HttpResponse:
    readAll: fn() -> str?
    readLine: fn(withTrailing: bool?) -> str?
    read: fn(count: num?) -> any
    getResponseCode: fn() -> any
    getResponseHeaders: fn() -> any
    seek: fn(whence: str?, offset: num?) -> any
    close: fn()

class Websocket:
    send: fn(message: any, binary: bool?)
    receive: fn(timeout: num?) -> any
    close: fn()

# ------------------------------------------------------------------ terminals and peripherals

class Terminal:
    write: fn(text: any)
    scroll: fn(y: num)
    getCursorPos: fn() -> any
    setCursorPos: fn(x: num, y: num)
    getCursorBlink: fn() -> bool
    setCursorBlink: fn(blink: bool)
    getSize: fn() -> any
    clear: fn()
    clearLine: fn()
    setTextColor: fn(color: num)
    setTextColour: fn(color: num)
    getTextColor: fn() -> num
    getTextColour: fn() -> num
    setBackgroundColor: fn(color: num)
    setBackgroundColour: fn(color: num)
    getBackgroundColor: fn() -> num
    getBackgroundColour: fn() -> num
    isColor: fn() -> bool
    isColour: fn() -> bool
    blit: fn(text: str, textColors: str, backgroundColors: str)
    setPaletteColor: fn(index: num, r: num, g: num?, b: num?)
    setPaletteColour: fn(index: num, r: num, g: num?, b: num?)
    getPaletteColor: fn(index: num) -> any
    getPaletteColour: fn(index: num) -> any

class Monitor(Terminal):
    getTextScale: fn() -> num
    setTextScale: fn(scale: num)

class Speaker:
    playNote: fn(instrument: str, volume: num?, pitch: num?) -> bool
    playSound: fn(name: str, volume: num?, pitch: num?) -> bool
    playAudio: fn(audio: list[num], volume: num?) -> bool
    stop: fn()

class Modem:
    open: fn(channel: num)
    isOpen: fn(channel: num) -> bool
    close: fn(channel: num)
    closeAll: fn()
    transmit: fn(channel: num, replyChannel: num, payload: any)
    isWireless: fn() -> bool
    getNamesRemote: fn() -> list[str]
    isPresentRemote: fn(name: str) -> bool
    getTypeRemote: fn(name: str) -> any
    hasTypeRemote: fn(name: str, type: str) -> bool?
    getMethodsRemote: fn(name: str) -> list[str]?
    callRemote: fn(name: str, method: str, *args: any) -> any
    getNameLocal: fn() -> str?

class Drive:
    isDiskPresent: fn() -> bool
    getDiskLabel: fn() -> str?
    setDiskLabel: fn(label: str?)
    hasData: fn() -> bool
    getMountPath: fn() -> str?
    hasAudio: fn() -> bool
    getAudioTitle: fn() -> any
    playAudio: fn()
    stopAudio: fn()
    ejectDisk: fn()
    getDiskID: fn() -> num?

class Printer:
    write: fn(text: any)
    getCursorPos: fn() -> any
    setCursorPos: fn(x: num, y: num)
    getPageSize: fn() -> any
    newPage: fn() -> bool
    endPage: fn() -> bool
    setPageTitle: fn(title: str?)
    getInkLevel: fn() -> num
    getPaperLevel: fn() -> num

class ComputerPeripheral:
    turnOn: fn()
    shutdown: fn()
    reboot: fn()
    getID: fn() -> num
    getLabel: fn() -> str?
    isOn: fn() -> bool

class CommandBlock:
    getCommand: fn() -> str
    setCommand: fn(command: str)
    runCommand: fn() -> any

class Inventory:
    size: fn() -> num
    list: fn() -> any
    getItemDetail: fn(slot: num) -> any
    getItemLimit: fn(slot: num) -> num
    pushItems: fn(toName: str, fromSlot: num, limit: num?, toSlot: num?) -> num
    pullItems: fn(fromName: str, fromSlot: num, limit: num?, toSlot: num?) -> num

class FluidStorage:
    tanks: fn() -> any
    pushFluid: fn(toName: str, limit: num?, fluidName: str?) -> num
    pullFluid: fn(fromName: str, limit: num?, fluidName: str?) -> num

class EnergyStorage:
    getEnergy: fn() -> num
    getEnergyCapacity: fn() -> num

class RedstoneRelay:
    getSides: fn() -> list[str]
    getInput: fn(side: str) -> bool
    setOutput: fn(side: str, on: bool)
    getOutput: fn(side: str) -> bool
    getAnalogInput: fn(side: str) -> num
    setAnalogOutput: fn(side: str, value: num)
    getAnalogOutput: fn(side: str) -> num

# peripheral.find("monitor") returns Monitor? (type by the literal name)
namespace peripheral_types:
    monitor: Monitor
    speaker: Speaker
    modem: Modem
    drive: Drive
    printer: Printer
    computer: ComputerPeripheral
    command: CommandBlock
    inventory: Inventory
    fluid_storage: FluidStorage
    energy_storage: EnergyStorage
    redstone_relay: RedstoneRelay

# ------------------------------------------------------------------ APIs

open namespace term:
    def write(text: any)
    def blit(text: str, fg: str, bg: str)
    def clear()
    def clearLine()
    def getCursorPos() -> any
    def setCursorPos(x: num, y: num)
    def setCursorBlink(blink: bool)
    def getCursorBlink() -> bool
    def getSize() -> any
    def scroll(n: num)
    def isColor() -> bool
    def isColour() -> bool
    def setTextColor(color: num)
    def setTextColour(color: num)
    def setBackgroundColor(color: num)
    def setBackgroundColour(color: num)
    def getTextColor() -> num
    def getTextColour() -> num
    def getBackgroundColor() -> num
    def getBackgroundColour() -> num
    def setPaletteColor(index: num, r: num, g: num?, b: num?)
    def setPaletteColour(index: num, r: num, g: num?, b: num?)
    def getPaletteColor(index: num) -> any
    def getPaletteColour(index: num) -> any
    def nativePaletteColor(index: num) -> any
    def redirect(target: Terminal) -> Terminal
    def current() -> Terminal
    def native() -> Terminal

open namespace fs:
    def list(path: str) -> list[str]
    def exists(path: str) -> bool
    def isDir(path: str) -> bool
    def isReadOnly(path: str) -> bool
    def getName(path: str) -> str
    def getDir(path: str) -> str
    def getSize(path: str) -> num
    def getDrive(path: str) -> str?
    def getFreeSpace(path: str) -> num
    def getCapacity(path: str) -> num?
    def attributes(path: str) -> any
    def makeDir(path: str)
    def move(source: str, dest: str)
    def copy(source: str, dest: str)
    def delete(path: str)
    def combine(path: str, *rest: str) -> str
    def open(path: str, mode: str) -> FileHandle?
    def find(wildcard: str) -> list[str]
    def isDriveRoot(path: str) -> bool
    def complete(partial: str, path: str, include_files: bool?, include_slashes: bool?) -> list[str]

open namespace peripheral:
    def getNames() -> list[str]
    def isPresent(name: str) -> bool
    def getType(name: any) -> any
    def hasType(name: any, type: str) -> bool?
    def getMethods(name: str) -> list[str]?
    def getName(peripheral: any) -> str
    def call(name: str, method: str, *args: any) -> any
    def wrap(name: str) -> any
    def find(type: str, filter: any?) -> any

open namespace rednet:
    CHANNEL_BROADCAST: num
    CHANNEL_REPEAT: num
    MAX_ID_CHANNELS: num
    def open(side: str)
    def close(side: str?)
    def isOpen(side: str?) -> bool
    def send(id: num, message: any, protocol: str?) -> bool
    def broadcast(message: any, protocol: str?)
    def receive(protocol: any?, timeout: num?) -> any
    def host(protocol: str, hostname: str)
    def unhost(protocol: str)
    def lookup(protocol: str, hostname: str?) -> any
    def run()

open namespace redstone:
    def getSides() -> list[str]
    def getInput(side: str) -> bool
    def setOutput(side: str, on: bool)
    def getOutput(side: str) -> bool
    def getAnalogInput(side: str) -> num
    def setAnalogOutput(side: str, value: num)
    def getAnalogOutput(side: str) -> num
    def getBundledInput(side: str) -> num
    def getBundledOutput(side: str) -> num
    def setBundledOutput(side: str, colors: num)
    def testBundledInput(side: str, mask: num) -> bool

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
    def combine(*colors: num) -> num
    def subtract(colors: num, *remove: num) -> num
    def test(colors: num, color: num) -> bool
    def packRGB(r: num, g: num, b: num) -> num
    def unpackRGB(rgb: num) -> any
    def rgb8(r: any, g: num?, b: num?) -> any
    def toBlit(color: num) -> str
    def fromBlit(hex: str) -> num?

open namespace colours:
    white: num
    orange: num
    magenta: num
    lightBlue: num
    yellow: num
    lime: num
    pink: num
    grey: num
    lightGrey: num
    cyan: num
    purple: num
    blue: num
    brown: num
    green: num
    red: num
    black: num
    def combine(*colors: num) -> num
    def subtract(colors: num, *remove: num) -> num
    def test(colors: num, color: num) -> bool
    def packRGB(r: num, g: num, b: num) -> num
    def unpackRGB(rgb: num) -> any
    def toBlit(color: num) -> str
    def fromBlit(hex: str) -> num?

open namespace keys:
    def getName(code: num) -> str?

open namespace textutils:
    empty_json_array: any
    json_null: any
    def serialize(value: any, options: any?) -> str
    def serialise(value: any, options: any?) -> str
    def unserialize(text: str) -> any
    def unserialise(text: str) -> any
    def serializeJSON(value: any, options: any?) -> str
    def serialiseJSON(value: any, options: any?) -> str
    def unserializeJSON(text: str, options: any?) -> any
    def unserialiseJSON(text: str, options: any?) -> any
    def formatTime(time: num, twentyFour: bool?) -> str
    def slowPrint(text: str, rate: num?)
    def slowWrite(text: str, rate: num?)
    def tabulate(*args: any)
    def pagedTabulate(*args: any)
    def print(*args: any)
    def pagedPrint(text: str, free_lines: num?) -> num
    def urlEncode(str: str) -> str
    def complete(partial: str, env: any?) -> list[str]

open namespace shell:
    def run(*args: str) -> bool
    def execute(command: str, *args: str) -> bool
    def exit()
    def dir() -> str
    def setDir(dir: str)
    def path() -> str
    def setPath(path: str)
    def resolve(path: str) -> str
    def resolveProgram(name: str) -> str?
    def aliases() -> any
    def setAlias(alias: str, program: str)
    def clearAlias(alias: str)
    def programs(include_hidden: bool?) -> list[str]
    def getRunningProgram() -> str
    def openTab(*args: str) -> num
    def switchTab(id: num)
    def complete(prefix: str) -> list[str]
    def completeProgram(prefix: str) -> list[str]
    def setCompletionFunction(path: str, completion: any)

open namespace http:
    def get(url: any, headers: any?, binary: bool?) -> HttpResponse?
    def post(url: any, body: str?, headers: any?, binary: bool?) -> HttpResponse?
    def request(url: any, body: str?, headers: any?, binary: bool?)
    def checkURL(url: str) -> any
    def checkURLAsync(url: str) -> any
    def websocket(url: str, headers: any?) -> Websocket?
    def websocketAsync(url: str, headers: any?)

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
    def attackUp(side: str?) -> any
    def attackDown(side: str?) -> any
    def detect() -> bool
    def detectUp() -> bool
    def detectDown() -> bool
    def inspect() -> any
    def inspectUp() -> any
    def inspectDown() -> any
    def compare() -> bool
    def compareUp() -> bool
    def compareDown() -> bool
    def compareTo(slot: num) -> bool
    def transferTo(slot: num, count: num?) -> bool
    def craft(limit: num?) -> any
    def equipLeft() -> any
    def equipRight() -> any
    def getEquippedLeft() -> any
    def getEquippedRight() -> any

open namespace parallel:
    def waitForAny(*fns: any)
    def waitForAll(*fns: any)

open namespace settings:
    def define(name: str, options: any?)
    def undefine(name: str)
    def set(name: str, value: any)
    def get(name: str, default: any?) -> any
    def getDetails(name: str) -> any
    def unset(name: str)
    def clear()
    def getNames() -> list[str]
    def save(path: str?) -> bool
    def load(path: str?) -> bool

open namespace window:
    def create(parent: any, x: num, y: num, width: num, height: num, visible: bool?) -> Terminal

open namespace paintutils:
    def drawPixel(x: num, y: num, color: num?)
    def drawLine(x1: num, y1: num, x2: num, y2: num, color: num?)
    def drawBox(x1: num, y1: num, x2: num, y2: num, color: num?)
    def drawFilledBox(x1: num, y1: num, x2: num, y2: num, color: num?)
    def parseImage(text: str) -> any
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
    def hasAudio(side: str) -> bool
    def getAudioTitle(side: str) -> any
    def playAudio(side: str)
    def stopAudio(side: str?)
    def eject(side: str)
    def getID(side: str) -> num?

open namespace gps:
    CHANNEL_GPS: num
    def locate(timeout: num?, debug: bool?) -> any

open namespace help:
    def path() -> str
    def setPath(path: str)
    def lookup(topic: str) -> str?
    def topics() -> list[str]
    def completeTopic(prefix: str) -> list[str]

open namespace multishell:
    def getCurrent() -> num
    def getFocus() -> num
    def setFocus(n: num) -> bool
    def getTitle(n: num) -> str?
    def setTitle(n: num, title: str)
    def getCount() -> num
    def launch(env: any, path: str, *args: any) -> num

open namespace pocket:
    def equipBack() -> any
    def unequipBack() -> any

open namespace commands:
    def exec(command: str) -> any
    def execAsync(command: str) -> num
    def list(*filter: str) -> list[str]
    def getBlockPosition() -> any
    def getBlockInfo(x: num, y: num, z: num) -> any
    def getBlockInfos(minX: num, minY: num, minZ: num, maxX: num, maxY: num, maxZ: num) -> any
