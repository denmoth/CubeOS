# Advanced Peripherals 0.7 for CC: Tweaked (types from docs.advanced-peripherals.de/0.7).
# Classes are `open`: methods that are not listed are `any`, so newer versions do not break strict code.
# Methods that return `true | nil, message` are typed `any`.

type ItemQuery = {name: str?, count: num?, nbt: str?, fingerprint: str?}
type FluidQuery = {name: str?, count: num?, nbt: str?, fingerprint: str?}
type Pos = {x: num, y: num, z: num}

open class ChatBox:
    sendMessage: fn(message: str, prefix: str?, brackets: str?, bracketColor: str?, range: num?, utf8Support: bool?) -> any
    sendMessageToPlayer: fn(message: str, username: str, prefix: str?, brackets: str?, bracketColor: str?, range: num?, utf8Support: bool?) -> any
    sendToastToPlayer: fn(message: str, title: str, username: str, prefix: str?, brackets: str?, bracketColor: str?, range: num?, utf8Support: bool?) -> any
    sendFormattedMessage: fn(json: str, prefix: str?, brackets: str?, bracketColor: str?, range: num?, utf8Support: bool?) -> any
    sendFormattedMessageToPlayer: fn(json: str, username: str, prefix: str?, brackets: str?, bracketColor: str?, range: num?, utf8Support: bool?) -> any
    sendFormattedToastToPlayer: fn(messageJson: str, titleJson: str, username: str, prefix: str?, brackets: str?, bracketColor: str?, range: num?, utf8Support: bool?) -> any

open class PlayerDetector:
    getPlayerPos: fn(username: str) -> any
    getPlayer: fn(username: str) -> any
    getOnlinePlayers: fn() -> list[str]
    getPlayersInRange: fn(range: num) -> list[str]
    getPlayersInCoords: fn(posOne: Pos, posTwo: Pos) -> list[str]
    getPlayersInCubic: fn(w: num, h: num, d: num) -> list[str]
    isPlayerInRange: fn(range: num, username: str) -> bool
    isPlayerInCoords: fn(posOne: Pos, posTwo: Pos, username: str) -> bool
    isPlayerInCubic: fn(w: num, h: num, d: num, username: str) -> bool
    isPlayersInRange: fn(range: num) -> bool
    isPlayersInCoords: fn(posOne: Pos, posTwo: Pos) -> bool
    isPlayersInCubic: fn(w: num, h: num, d: num) -> bool

open class EnvironmentDetector:
    getBiome: fn() -> str
    getBlockLightLevel: fn() -> num
    getDayLightLevel: fn() -> num
    getSkyLightLevel: fn() -> num
    getDimension: fn() -> str
    getDimensionPaN: fn() -> str
    getDimensionProvider: fn() -> str
    getMoonId: fn() -> num
    getMoonName: fn() -> str
    getTime: fn() -> num
    getRadiation: fn() -> any
    getRadiationRaw: fn() -> num
    isDimension: fn(dimension: str) -> bool
    isMoon: fn(moonPhaseId: num) -> bool
    isRaining: fn() -> bool
    isSunny: fn() -> bool
    isThunder: fn() -> bool
    isSlimeChunk: fn() -> bool
    listDimensions: fn() -> list[str]
    scanEntities: fn(range: num) -> any

open class InventoryManager:
    addItemToPlayer: fn(direction: str, item: ItemQuery?) -> num
    removeItemFromPlayer: fn(direction: str, item: ItemQuery?) -> num
    getArmor: fn() -> any
    getItems: fn() -> any
    getOwner: fn() -> str?
    isPlayerEquipped: fn() -> bool
    isWearing: fn(slot: num) -> bool
    getItemInHand: fn() -> any
    getItemInOffHand: fn() -> any
    getFreeSlot: fn() -> num
    isSpaceAvailable: fn() -> bool
    getEmptySpace: fn() -> num

open class GeoScanner:
    getMaxFuelLevel: fn() -> num
    cost: fn(radius: num) -> num
    scan: fn(radius: num) -> any
    chunkAnalyze: fn() -> any

open class MeBridge:
    craftItem: fn(item: ItemQuery, craftingCpu: str?) -> any
    craftFluid: fn(fluid: FluidQuery, craftingCpu: str?) -> any
    getItem: fn(item: ItemQuery) -> any
    importItem: fn(item: ItemQuery, direction: str) -> any
    exportItem: fn(item: ItemQuery, direction: str) -> any
    importItemFromPeripheral: fn(item: ItemQuery, container: str) -> any
    exportItemToPeripheral: fn(item: ItemQuery, container: str) -> any
    getEnergyStorage: fn() -> any
    getMaxEnergyStorage: fn() -> any
    getEnergyUsage: fn() -> any
    getCraftingCPUs: fn() -> any
    isItemCrafting: fn(item: ItemQuery, craftingCpu: str?) -> any
    isItemCraftable: fn(item: ItemQuery) -> any
    listCraftableItems: fn() -> any
    listCraftableFluid: fn() -> any
    listItems: fn() -> any
    listFluid: fn() -> any
    listGas: fn() -> any
    listCells: fn() -> any
    getTotalItemStorage: fn() -> any
    getTotalFluidStorage: fn() -> any
    getUsedItemStorage: fn() -> any
    getUsedFluidStorage: fn() -> any
    getAvailableItemStorage: fn() -> any
    getAvailableFluidStorage: fn() -> any

open class RsBridge:
    craftItem: fn(item: ItemQuery) -> bool
    craftFluid: fn(fluid: FluidQuery, amount: num) -> bool
    getItem: fn(item: ItemQuery) -> any
    importItem: fn(item: ItemQuery, direction: str) -> num
    exportItem: fn(item: ItemQuery, direction: str) -> num
    importItemFromPeripheral: fn(item: ItemQuery, container: str) -> num
    exportItemToPeripheral: fn(item: ItemQuery, container: str) -> num
    getMaxItemDiskStorage: fn() -> num
    getMaxFluidDiskStorage: fn() -> num
    getMaxItemExternalStorage: fn() -> num
    getMaxFluidExternalStorage: fn() -> num
    getEnergyStorage: fn() -> num
    getMaxEnergyStorage: fn() -> num
    getEnergyUsage: fn() -> num
    getPattern: fn(item: ItemQuery) -> any
    isItemCrafting: fn(item: ItemQuery) -> bool
    isItemCraftable: fn(item: ItemQuery) -> bool
    listCraftableItems: fn() -> any
    listCraftableFluids: fn() -> any
    listItems: fn() -> any
    listFluids: fn() -> any

open class RedstoneIntegrator:
    getInput: fn(side: str) -> bool
    getOutput: fn(side: str) -> bool
    getAnalogInput: fn(side: str) -> num
    getAnalogOutput: fn(side: str) -> num
    setOutput: fn(side: str, powered: bool)
    setAnalogOutput: fn(side: str, power: num)

open class BlockReader:
    getBlockName: fn() -> str
    getBlockData: fn() -> any
    getBlockStates: fn() -> any
    isTileEntity: fn() -> any

open class EnergyDetector:
    getTransferRate: fn() -> num
    getTransferRateLimit: fn() -> num
    setTransferRateLimit: fn(limit: num)

namespace peripheral_types:
    chatBox: ChatBox
    playerDetector: PlayerDetector
    environmentDetector: EnvironmentDetector
    inventoryManager: InventoryManager
    geoScanner: GeoScanner
    meBridge: MeBridge
    rsBridge: RsBridge
    redstoneIntegrator: RedstoneIntegrator
    blockReader: BlockReader
    energyDetector: EnergyDetector
