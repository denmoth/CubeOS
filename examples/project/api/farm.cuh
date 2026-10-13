# API игры/библиотеки, которой нет в CC: описываем только то, что нужно
namespace farm:
    def move(direction: str) -> bool
    def harvest() -> bool
    def get_position() -> {x: num, y: num}
    def plant(crop: str, count: num?)
