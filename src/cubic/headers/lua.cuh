# Lua standard library (subset) for Cubic strict mode.
# Functions that return several values are typed `any`.

def print(*args: any)
def type(v: any) -> str
def tostring(v: any) -> str
def tonumber(v: any, base: num?) -> num?
def pairs(t: any) -> any
def ipairs(t: any) -> any
def next(t: any, k: any?) -> any
def select(n: any, *args: any) -> any
def error(message: any, level: num?)
def assert(v: any, message: any?) -> any
def pcall(f: any, *args: any) -> any
def xpcall(f: any, handler: any, *args: any) -> any
def setmetatable(t: any, mt: any?) -> any
def getmetatable(t: any) -> any
def rawget(t: any, k: any) -> any
def rawset(t: any, k: any, v: any) -> any
def rawequal(a: any, b: any) -> bool
def unpack(t: any, i: num?, j: num?) -> any
def load(chunk: any, name: str?, mode: str?, env: any?) -> any
def loadstring(s: str, name: str?) -> any
def loadfile(path: str, mode: str?, env: any?) -> any
def dofile(path: str) -> any
def require(name: str) -> any
def collectgarbage(opt: str?, arg: any?) -> any
def sleep(seconds: num?)
def write(text: any)
def read(replace: str?, history: any?, complete: any?, default: str?) -> str
def printError(*args: any)
_G: any
_VERSION: str

open namespace math:
    pi: num
    huge: num
    def floor(x: num) -> num
    def ceil(x: num) -> num
    def abs(x: num) -> num
    def sqrt(x: num) -> num
    def sin(x: num) -> num
    def cos(x: num) -> num
    def tan(x: num) -> num
    def asin(x: num) -> num
    def acos(x: num) -> num
    def atan(x: num) -> num
    def atan2(y: num, x: num) -> num
    def exp(x: num) -> num
    def log(x: num, base: num?) -> num
    def pow(x: num, y: num) -> num
    def fmod(x: num, y: num) -> num
    def modf(x: num) -> any
    def max(x: num, *rest: num) -> num
    def min(x: num, *rest: num) -> num
    def random(m: num?, n: num?) -> num
    def randomseed(x: num)

open namespace string:
    def len(s: str) -> num
    def sub(s: str, i: num, j: num?) -> str
    def upper(s: str) -> str
    def lower(s: str) -> str
    def rep(s: str, n: num, sep: str?) -> str
    def reverse(s: str) -> str
    def byte(s: str, i: num?, j: num?) -> any
    def char(*codes: num) -> str
    def format(fmt: str, *args: any) -> str
    def find(s: str, pattern: str, init: num?, plain: bool?) -> any
    def match(s: str, pattern: str, init: num?) -> any
    def gmatch(s: str, pattern: str) -> any
    def gsub(s: str, pattern: str, repl: any, n: num?) -> any

open namespace table:
    def insert(t: any, a: any, b: any?)
    def remove(t: any, pos: num?) -> any
    def concat(t: any, sep: str?, i: num?, j: num?) -> str
    def sort(t: any, cmp: any?)
    def unpack(t: any, i: num?, j: num?) -> any

open namespace os:
    def time(t: any?) -> num
    def clock() -> num
    def date(fmt: str?, time: num?) -> any
    def epoch(locale: str?) -> num
    def startTimer(t: num) -> num
    def cancelTimer(id: num)
    def startAlarm(t: num) -> num
    def cancelAlarm(id: num)
    def pullEvent(filter: str?) -> any
    def pullEventRaw(filter: str?) -> any
    def queueEvent(name: str, *args: any)
    def sleep(t: num)
    def getComputerID() -> num
    def getComputerLabel() -> str?
    def setComputerLabel(label: str?)
    def shutdown()
    def reboot()
    def version() -> str
    def day(locale: str?) -> num

open namespace io:
    def open(path: str, mode: str?) -> any
    def read(fmt: any?) -> any
    def write(*args: any)

open namespace coroutine:
    def create(f: any) -> any
    def resume(co: any, *args: any) -> any
    def yield(*args: any) -> any
    def status(co: any) -> str
    def wrap(f: any) -> any
    def running() -> any
