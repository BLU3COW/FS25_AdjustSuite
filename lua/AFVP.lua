local safeCall = pcall
AdjustSuiteAFVP = AdjustSuiteAFVP or {}
local AFVP = AdjustSuiteAFVP

local Suite = AdjustSuite
Suite.moduleClasses["AFVP"] = AFVP
local STORAGE_PATHS = {
    { path = "placeable.silo.storages.storage", isList = true },
    { path = "placeable.siloExtension.storage" },
    { path = "placeable.husbandry.storage" },
    { path = "placeable.factory.storage" },
    { path = "placeable.constructible.storage" },
}
local PRODUCTION_PATH = "placeable.productionPoint"
local PRODUCTION_CONFIGURATIONS_PATH = PRODUCTION_PATH .. ".productionPointConfigurations.productionPointConfiguration"
local HUSBANDRY_FOOD_CAPACITY_PATH = "placeable.husbandry.food#capacity"
local HUSBANDRY_FOOD_PLANE_CAPACITY_PATH = "placeable.husbandry.food.dynamicFoodPlane#capacity"
local MANURE_HEAP_CAPACITY_PATH = "placeable.manureHeap#capacity"

AFVP.visualFillVolumes = AFVP.visualFillVolumes or setmetatable({}, { __mode = "v" })
AFVP.baseFillPlaneAdd = AFVP.baseFillPlaneAdd or fillPlaneAdd
AFVP.hookedFillPlaneAdd = AFVP.hookedFillPlaneAdd
    or function(fillPlaneId, delta, ...)
        local fillVolume = AFVP.visualFillVolumes[fillPlaneId]
        if fillVolume ~= nil and fillVolume.volume == fillPlaneId then
            delta = delta / (tonumber(fillVolume.adjustSuiteAFVPVisualFactor) or 1)
        end
        return AFVP.baseFillPlaneAdd(fillPlaneId, delta, ...)
    end

local function updateFillPlaneHook()
    if AFVP.baseFillPlaneAdd == nil then
        return
    end

    if next(AFVP.visualFillVolumes) ~= nil then
        if AFVP.fillPlaneHookInstalled ~= true then
            AFVP.fillPlaneHookInstalled = true
            fillPlaneAdd = AFVP.hookedFillPlaneAdd
        end
    elseif AFVP.fillPlaneHookInstalled == true and fillPlaneAdd == AFVP.hookedFillPlaneAdd then
        AFVP.fillPlaneHookInstalled = false
        fillPlaneAdd = AFVP.baseFillPlaneAdd
    end
end

AFVP.storages = AFVP.storages or setmetatable({}, { __mode = "k" })

function AFVP.rememberStorageCapacities(storage)
    if type(storage) ~= "table" then
        return
    end

    local capacity = tonumber(storage.capacity)
    if capacity == nil or capacity <= 0 then
        return
    end

    storage.adjustSuiteAFVPCapacity = capacity

    local applied = {}
    for fillType, value in pairs(storage.capacities or {}) do
        applied[fillType] = tonumber(value)
    end
    storage.adjustSuiteAFVPCapacities = applied

    AFVP.storages[storage] = true
end

local function reconcileCapacity(current, applied, respectExternal)
    if current == nil or applied == nil or math.abs(current - applied) <= 0.5 then
        return nil
    end

    return respectExternal and current or applied
end

local DEFAULT_MAX_PHYSICAL_SURFACE_ANGLE = 0.6108652381980153

function AFVP.rememberDynamicFillPlane(storage, xmlFile, key)
    if storage.dynamicFillPlane == nil or xmlFile == nil or type(key) ~= "string" then
        return
    end

    local planeKey = key .. ".dynamicFillPlane"
    local defaultFillTypeName = xmlFile:getValue(planeKey .. "#defaultFillType")
    local defaultFillTypeIndex = nil
    if defaultFillTypeName ~= nil and g_fillTypeManager ~= nil then
        defaultFillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(defaultFillTypeName)
    end

    storage.adjustSuiteDynamicFillPlane = {
        fixedCapacity = xmlFile:getValue(planeKey .. "#capacity"),
        defaultFillTypeIndex = defaultFillTypeIndex,
        maxDelta = xmlFile:getValue(planeKey .. "#maxDelta", 1),
        maxSurfaceAngle = xmlFile:getValue(planeKey .. "#maxAllowedHeapAngle", 35),
        maxPhysicalSurfaceAngle = DEFAULT_MAX_PHYSICAL_SURFACE_ANGLE,
        maxSurfaceDistanceError = xmlFile:getValue(planeKey .. "#maxSurfaceDistanceError", 0.05),
        maxSubDivEdgeLength = xmlFile:getValue(planeKey .. "#maxSubDivEdgeLength", 0.9),
        syncMaxSubDivEdgeLength = xmlFile:getValue(planeKey .. "#syncMaxSubDivEdgeLength", 1.35),
        allSidePlanes = xmlFile:getValue(planeKey .. "#allSidePlanes", true),
        retessellateTop = xmlFile:getValue(planeKey .. "#retessellateTop", false),
    }
end

local function getDynamicFillPlaneCapacity(storage, params)
    local capacity = tonumber(params.fixedCapacity)
    if capacity == nil and params.defaultFillTypeIndex ~= nil and storage.capacities ~= nil then
        capacity = tonumber(storage.capacities[params.defaultFillTypeIndex])
    end
    return capacity or tonumber(storage.capacity)
end

local function rebuildDynamicFillPlane(storage)
    local params = storage.adjustSuiteDynamicFillPlane
    if params == nil or storage.dynamicFillPlane == nil or storage.dynamicFillPlaneBaseNode == nil then
        return
    end

    local fillPlane =
        Suite.createFillPlane(storage.dynamicFillPlaneBaseNode, getDynamicFillPlaneCapacity(storage, params), params)
    if fillPlane == nil then
        return
    end

    delete(storage.dynamicFillPlane)
    storage.dynamicFillPlane = fillPlane

    local totalFillLevel = 0
    local fillType = nil
    for fillTypeIndex, fillLevel in pairs(storage.fillLevels or {}) do
        fillLevel = tonumber(fillLevel) or 0
        if fillLevel > 0 then
            totalFillLevel = totalFillLevel + fillLevel
            fillType = fillType or fillTypeIndex
        end
    end
    fillType = fillType or params.defaultFillTypeIndex

    if fillType ~= nil and g_fillTypeManager ~= nil then
        local textureArrayIndex = g_fillTypeManager:getTextureArrayIndexByFillTypeIndex(fillType)
        if textureArrayIndex ~= nil then
            setShaderParameter(fillPlane, "fillTypeId", textureArrayIndex - 1, 0, 0, 0, false)
        end
    end

    if totalFillLevel > 0 then
        local x, y, z = localToWorld(fillPlane, 0, 0, 0)
        local d1x, d1y, d1z = localDirectionToWorld(fillPlane, 1, 0, 0)
        local d2x, d2y, d2z = localDirectionToWorld(fillPlane, 0, 0, 1)
        local steps = math.min(math.max(math.floor(totalFillLevel / 400), 1), 50)
        for _ = 1, steps do
            fillPlaneAdd(fillPlane, totalFillLevel / steps, x, y, z, d1x, d1y, d1z, d2x, d2y, d2z)
        end
    end
end

local function refreshStorageVisuals(storage)
    if storage.updateFillPlanes ~= nil then
        storage:updateFillPlanes()
    end
    rebuildDynamicFillPlane(storage)
end

local function refreshHusbandryPlanes(changedStorages)
    local placeableSystem = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    for _, placeable in ipairs(placeableSystem ~= nil and placeableSystem.placeables or {}) do
        local husbandry = placeable.spec_husbandry
        if husbandry ~= nil and husbandry.storage ~= nil and changedStorages[husbandry.storage] then
            if placeable.updateStrawPlane ~= nil then
                placeable:updateStrawPlane()
            end
            if placeable.updateWaterPlane ~= nil then
                placeable:updateWaterPlane()
            end
        end
    end
end

local function resolveCapacity(current, applied, respectExternal)
    local resolved = reconcileCapacity(current, applied, respectExternal)
    return resolved, resolved ~= nil and current ~= nil and math.abs(resolved - current) > 0.5
end

function AFVP.verifyStorageCapacities()
    local respectExternal = Suite.respectExternalCapacityOverrides == true
    local changedStorages = {}
    local anyChanged = false

    for storage in pairs(AFVP.storages) do
        local resolved, changed =
            resolveCapacity(tonumber(storage.capacity), tonumber(storage.adjustSuiteAFVPCapacity), respectExternal)
        if resolved ~= nil then
            storage.capacity = resolved
            storage.adjustSuiteAFVPCapacity = resolved
        end

        local applied = storage.adjustSuiteAFVPCapacities
        local capacities = storage.capacities
        if applied ~= nil and capacities ~= nil then
            for fillType, value in pairs(applied) do
                local resolvedFillType, fillTypeChanged =
                    resolveCapacity(tonumber(capacities[fillType]), value, respectExternal)
                if resolvedFillType ~= nil then
                    capacities[fillType] = resolvedFillType
                    applied[fillType] = resolvedFillType
                    changed = changed or fillTypeChanged
                end
            end
        end

        if changed then
            changedStorages[storage] = true
            anyChanged = true
            refreshStorageVisuals(storage)
        end
    end

    if anyChanged then
        refreshHusbandryPlanes(changedStorages)
    end
end

if AFVP.storageHookInstalled ~= true and Storage ~= nil and Storage.load ~= nil then
    AFVP.storageHookInstalled = true
    Storage.load = Utils.overwrittenFunction(Storage.load, function(storage, superFunc, components, xmlFile, key, ...)
        local loaded = superFunc(storage, components, xmlFile, key, ...)
        if loaded ~= false then
            AFVP.rememberStorageCapacities(storage)
            AFVP.rememberDynamicFillPlane(storage, xmlFile, key)
        end
        return loaded
    end)
end

local function createSiloLinkTable()
    return setmetatable({}, { __mode = "k" })
end

AFVP.siloNetworkLinks = AFVP.siloNetworkLinks or createSiloLinkTable()

local function getStorageSystem()
    return g_currentMission ~= nil and g_currentMission.storageSystem or nil
end

local function getSiloNetworkStorages(placeable)
    local spec = placeable ~= nil and placeable.spec_silo or nil
    if spec == nil or spec.storagePerFarm == true or spec.storages == nil then
        return nil
    end
    return spec.storages
end

local function rememberSiloLink(storage, station, isLoading)
    local links = AFVP.siloNetworkLinks[storage]
    if links == nil then
        links = {}
        AFVP.siloNetworkLinks[storage] = links
    end
    links[station] = isLoading
end

local function collectKeys(entries)
    local list = {}
    for key in pairs(entries or {}) do
        table.insert(list, key)
    end
    return list
end

local function productionsUseNearbyStorages()
    return Suite.connectProductionStorage ~= false
end

local function siloNetworkIsEnabled()
    return Suite.siloNetworkEnabled == true
end

local function silosStayApart()
    return siloNetworkIsEnabled() and Suite.connectSiloNetwork ~= true
end

local function belongsToSilo(object)
    return type(object) == "table" and object.adjustSuiteSiloPlaceable ~= nil
end

local function withoutSiloStorages(storages)
    local filtered = {}
    for _, storage in ipairs(storages or {}) do
        if not belongsToSilo(storage) then
            table.insert(filtered, storage)
        end
    end
    return filtered
end

local function offerStorageToProductions(storageSystem, storage)
    if storage == nil or storage.isExtension ~= true or not productionsUseNearbyStorages() then
        return
    end

    local manager = g_currentMission ~= nil and g_currentMission.productionChainManager or nil
    for _, productionPoint in ipairs(manager ~= nil and manager.productionPoints or {}) do
        local farmId = productionPoint:getOwnerFarmId()
        local loadingStation = productionPoint.loadingStation
        local unloadingStation = productionPoint.unloadingStation

        if
            loadingStation ~= nil
            and loadingStation.sourceStorages[storage] == nil
            and storageSystem:getIsStationCompatible(loadingStation, storage, farmId)
            and storageSystem:addStorageToLoadingStation(storage, loadingStation)
        then
            rememberSiloLink(storage, loadingStation, true)
        end

        if
            unloadingStation ~= nil
            and unloadingStation.targetStorages[storage] == nil
            and storageSystem:getIsStationCompatible(unloadingStation, storage, farmId)
            and storageSystem:addStorageToUnloadingStation(storage, unloadingStation)
        then
            rememberSiloLink(storage, unloadingStation, false)
        end
    end
end

function AFVP.markSiloStorages(placeable)
    local spec = placeable ~= nil and placeable.spec_silo or nil
    if spec == nil then
        return
    end

    for _, storage in ipairs(spec.storages or {}) do
        storage.adjustSuiteSiloPlaceable = placeable
    end
    if spec.loadingStation ~= nil then
        spec.loadingStation.adjustSuiteSiloPlaceable = placeable
    end
    if spec.unloadingStation ~= nil then
        spec.unloadingStation.adjustSuiteSiloPlaceable = placeable
    end
end

function AFVP.connectSiloStorages(placeable)
    local storages = getSiloNetworkStorages(placeable)
    local storageSystem = getStorageSystem()
    if storages == nil or storageSystem == nil then
        return
    end

    local farmId = placeable:getOwnerFarmId()
    for _, storage in ipairs(storages) do
        if storage.isExtension == true then
            for _, station in ipairs(storageSystem:getExtendableLoadingStationsInRange(storage, farmId)) do
                if
                    station.sourceStorages ~= nil
                    and station.sourceStorages[storage] == nil
                    and storageSystem:addStorageToLoadingStation(storage, station)
                then
                    rememberSiloLink(storage, station, true)
                end
            end

            for _, station in ipairs(storageSystem:getExtendableUnloadingStationsInRange(storage, farmId)) do
                if
                    station.targetStorages ~= nil
                    and station.targetStorages[storage] == nil
                    and storageSystem:addStorageToUnloadingStation(storage, station)
                then
                    rememberSiloLink(storage, station, false)
                end
            end
        end
    end
end

function AFVP.connectSiloStoragesToProductions(placeable)
    local storages = getSiloNetworkStorages(placeable)
    local storageSystem = getStorageSystem()
    if storages == nil or storageSystem == nil then
        return
    end

    for _, storage in ipairs(storages) do
        offerStorageToProductions(storageSystem, storage)
    end
end

function AFVP.connectSiloExtensionStorage(placeable)
    local spec = placeable ~= nil and placeable.spec_siloExtension or nil
    local storageSystem = getStorageSystem()
    if spec == nil or spec.storage == nil or storageSystem == nil then
        return
    end

    offerStorageToProductions(storageSystem, spec.storage)
end

function AFVP.releaseSiloStorages(placeable)
    local spec = placeable ~= nil and placeable.spec_silo or nil
    local storageSystem = getStorageSystem()
    if spec == nil or spec.storages == nil or storageSystem == nil then
        return
    end

    for _, storage in ipairs(spec.storages) do
        storageSystem:removeStorageFromLoadingStations(storage, collectKeys(storage.loadingStations))
        storageSystem:removeStorageFromUnloadingStations(storage, collectKeys(storage.unloadingStations))
        AFVP.siloNetworkLinks[storage] = nil
    end

    local ownStations = {}
    if spec.loadingStation ~= nil then
        ownStations[spec.loadingStation] = true
    end
    if spec.unloadingStation ~= nil then
        ownStations[spec.unloadingStation] = true
    end
    for _, links in pairs(AFVP.siloNetworkLinks) do
        for station in pairs(ownStations) do
            links[station] = nil
        end
    end
end

function AFVP.separateSiloStorages(placeable)
    local spec = placeable ~= nil and placeable.spec_silo or nil
    local storageSystem = getStorageSystem()
    if spec == nil or storageSystem == nil then
        return
    end

    if spec.loadingStation ~= nil then
        for _, storage in ipairs(collectKeys(spec.loadingStation.sourceStorages)) do
            if belongsToSilo(storage) and storage.adjustSuiteSiloPlaceable ~= placeable then
                storageSystem:removeStorageFromLoadingStations(storage, { spec.loadingStation })
            end
        end
    end

    if spec.unloadingStation ~= nil then
        for _, storage in ipairs(collectKeys(spec.unloadingStation.targetStorages)) do
            if belongsToSilo(storage) and storage.adjustSuiteSiloPlaceable ~= placeable then
                storageSystem:removeStorageFromUnloadingStations(storage, { spec.unloadingStation })
            end
        end
    end
end

function AFVP.refreshSiloNetwork()
    local storageSystem = getStorageSystem()
    if storageSystem ~= nil then
        for storage, links in pairs(AFVP.siloNetworkLinks) do
            for station, isLoading in pairs(links) do
                if isLoading then
                    storageSystem:removeStorageFromLoadingStations(storage, { station })
                else
                    storageSystem:removeStorageFromUnloadingStations(storage, { station })
                end
            end
        end
    end
    AFVP.siloNetworkLinks = createSiloLinkTable()

    if storageSystem == nil or not siloNetworkIsEnabled() then
        return
    end

    local placeableSystem = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    for _, placeable in pairs(placeableSystem ~= nil and placeableSystem.placeables or {}) do
        if Suite.connectSiloNetwork == true then
            AFVP.connectSiloStorages(placeable)
        else
            AFVP.separateSiloStorages(placeable)
        end
    end
end

local function placeableRunsInSandbox(placeable)
    if placeable == nil or placeable.isSandboxPlaceable == nil then
        return false
    end

    local ok, isSandbox = safeCall(placeable.isSandboxPlaceable, placeable)
    return ok and isSandbox == true
end

local function stationBelongsToProduction(station)
    local productionPoint = type(station) == "table" and station.adjustSuiteProductionPoint or nil
    return productionPoint ~= nil and not placeableRunsInSandbox(productionPoint.owningPlaceable)
end

local function withoutProductionStations(stations)
    if productionsUseNearbyStorages() or stations == nil then
        return stations
    end

    local filtered = {}
    for _, station in ipairs(stations) do
        if not stationBelongsToProduction(station) then
            table.insert(filtered, station)
        end
    end
    return filtered
end

function AFVP.refreshProductionStorages()
    local storageSystem = getStorageSystem()
    local manager = g_currentMission ~= nil and g_currentMission.productionChainManager or nil
    if storageSystem == nil or manager == nil then
        return
    end

    for _, productionPoint in ipairs(manager.productionPoints or {}) do
        local farmId = productionPoint:getOwnerFarmId()
        local loadingStation = productionPoint.loadingStation
        local unloadingStation = productionPoint.unloadingStation

        if productionsUseNearbyStorages() or placeableRunsInSandbox(productionPoint.owningPlaceable) then
            if loadingStation ~= nil then
                for _, storage in ipairs(storageSystem:getStorageExtensionsInRange(loadingStation, farmId)) do
                    if loadingStation.sourceStorages[storage] == nil then
                        storageSystem:addStorageToLoadingStation(storage, loadingStation)
                    end
                end
            end
            if unloadingStation ~= nil then
                for _, storage in ipairs(storageSystem:getStorageExtensionsInRange(unloadingStation, farmId)) do
                    if unloadingStation.targetStorages[storage] == nil then
                        storageSystem:addStorageToUnloadingStation(storage, unloadingStation)
                    end
                end
            end
        else
            if loadingStation ~= nil then
                for _, storage in ipairs(collectKeys(loadingStation.sourceStorages)) do
                    if storage.isExtension == true and storage ~= productionPoint.storage then
                        storageSystem:removeStorageFromLoadingStations(storage, { loadingStation })
                    end
                end
            end
            if unloadingStation ~= nil then
                for _, storage in ipairs(collectKeys(unloadingStation.targetStorages)) do
                    if storage.isExtension == true and storage ~= productionPoint.storage then
                        storageSystem:removeStorageFromUnloadingStations(storage, { unloadingStation })
                    end
                end
            end
        end
    end
end

if AFVP.productionStationHookInstalled ~= true and ProductionPoint ~= nil and ProductionPoint.load ~= nil then
    AFVP.productionStationHookInstalled = true
    ProductionPoint.load = Utils.overwrittenFunction(ProductionPoint.load, function(productionPoint, superFunc, ...)
        local loaded = superFunc(productionPoint, ...)
        if productionPoint.loadingStation ~= nil then
            productionPoint.loadingStation.adjustSuiteProductionPoint = productionPoint
        end
        if productionPoint.unloadingStation ~= nil then
            productionPoint.unloadingStation.adjustSuiteProductionPoint = productionPoint
        end
        return loaded
    end)
end

if
    AFVP.productionStorageFilterInstalled ~= true
    and StorageSystem ~= nil
    and StorageSystem.getStorageExtensionsInRange ~= nil
    and StorageSystem.getExtendableLoadingStationsInRange ~= nil
    and StorageSystem.getExtendableUnloadingStationsInRange ~= nil
then
    AFVP.productionStorageFilterInstalled = true
    StorageSystem.getStorageExtensionsInRange = Utils.overwrittenFunction(
        StorageSystem.getStorageExtensionsInRange,
        function(storageSystem, superFunc, station, ...)
            if not productionsUseNearbyStorages() and stationBelongsToProduction(station) then
                return {}
            end

            local storages = superFunc(storageSystem, station, ...)
            if silosStayApart() and belongsToSilo(station) then
                return withoutSiloStorages(storages)
            end
            return storages
        end
    )
    StorageSystem.getExtendableLoadingStationsInRange = Utils.overwrittenFunction(
        StorageSystem.getExtendableLoadingStationsInRange,
        function(storageSystem, superFunc, ...)
            return withoutProductionStations(superFunc(storageSystem, ...))
        end
    )
    StorageSystem.getExtendableUnloadingStationsInRange = Utils.overwrittenFunction(
        StorageSystem.getExtendableUnloadingStationsInRange,
        function(storageSystem, superFunc, ...)
            return withoutProductionStations(superFunc(storageSystem, ...))
        end
    )
end

if
    AFVP.siloNetworkHooksInstalled ~= true
    and PlaceableSilo ~= nil
    and PlaceableSilo.onLoad ~= nil
    and PlaceableSilo.onFinalizePlacement ~= nil
    and PlaceableSilo.onDelete ~= nil
then
    AFVP.siloNetworkHooksInstalled = true
    PlaceableSilo.onLoad = Utils.appendedFunction(PlaceableSilo.onLoad, AFVP.markSiloStorages)
    PlaceableSilo.onFinalizePlacement = Utils.appendedFunction(PlaceableSilo.onFinalizePlacement, function(placeable)
        if siloNetworkIsEnabled() and Suite.connectSiloNetwork == true then
            AFVP.connectSiloStorages(placeable)
        end
        AFVP.connectSiloStoragesToProductions(placeable)
    end)
    PlaceableSilo.onDelete = Utils.prependedFunction(PlaceableSilo.onDelete, function(placeable)
        if siloNetworkIsEnabled() then
            AFVP.releaseSiloStorages(placeable)
        end
    end)
end

if
    AFVP.siloExtensionHookInstalled ~= true
    and PlaceableSiloExtension ~= nil
    and PlaceableSiloExtension.onFinalizePlacement ~= nil
then
    AFVP.siloExtensionHookInstalled = true
    PlaceableSiloExtension.onFinalizePlacement =
        Utils.appendedFunction(PlaceableSiloExtension.onFinalizePlacement, AFVP.connectSiloExtensionStorage)
end

if
    AFVP.siloNetworkSettingsHookInstalled ~= true
    and AdjustSuiteSettingsEvent ~= nil
    and AdjustSuiteSettingsEvent.run ~= nil
then
    AFVP.siloNetworkSettingsHookInstalled = true
    AdjustSuiteSettingsEvent.run = Utils.appendedFunction(AdjustSuiteSettingsEvent.run, function(_event, connection)
        if connection ~= nil and connection:getIsServer() then
            AFVP.refreshProductionStorages()
            AFVP.refreshSiloNetwork()
        end
    end)
end

local function capacityIsUsable(xmlFile, key)
    local value = tonumber(xmlFile:getValue(key))
    return value ~= nil and value > 0
end

local function scaleCapacity(xmlFile, key, factor)
    local value = tonumber(xmlFile:getValue(key))
    if value ~= nil and value > 0 then
        xmlFile:setValue(key, math.max(math.ceil(value * factor - 0.000001), 1))
    end
end

local function recreateFillVolume(fillVolume, capacity, fillLevel, fillTypeIndex, factor)
    factor = tonumber(factor) or 1
    if type(fillVolume) ~= "table" or capacity == nil or capacity <= 0 or factor <= 0 then
        return
    end

    fillVolume.capacity = capacity
    if fillVolume.volume == nil or fillVolume.volume == 0 then
        return
    end

    local visualCapacity = capacity / factor
    local newVolume = Suite.createFillPlane(fillVolume.baseNode, visualCapacity, fillVolume)
    if newVolume == nil then
        return
    end

    AFVP.visualFillVolumes[fillVolume.volume] = nil
    updateFillPlaneHook()
    delete(fillVolume.volume)
    fillVolume.volume = newVolume

    AFVP.baseFillPlaneAdd(newVolume, 1, 0, 1, 0, 11, 0, 0, 0, 0, 11)
    fillVolume.heightOffset = getFillPlaneHeightAtLocalPos(newVolume, 0, 0)
    AFVP.baseFillPlaneAdd(newVolume, -1, 0, 1, 0, 11, 0, 0, 0, 0, 11)

    for _, deformer in ipairs(fillVolume.deformers or {}) do
        deformer.polyline = findPolyline(newVolume, deformer.posX, deformer.posZ)
    end

    fillTypeIndex = tonumber(fillTypeIndex) or tonumber(fillVolume.lastFillType)
    if fillTypeIndex ~= nil and g_fillTypeManager ~= nil then
        local textureArrayIndex = g_fillTypeManager:getTextureArrayIndexByFillTypeIndex(fillTypeIndex)
        if textureArrayIndex ~= nil then
            setShaderParameter(newVolume, "fillTypeId", textureArrayIndex - 1, 0, 0, 0, false)
        end

        local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
        if fillType ~= nil and fillType.maxPhysicalSurfaceAngle ~= nil then
            fillVolume.maxPhysicalSurfaceAngle = fillType.maxPhysicalSurfaceAngle
            setFillPlaneMaxPhysicalSurfaceAngle(newVolume, fillVolume.maxPhysicalSurfaceAngle)
        end
    end

    fillLevel = math.min(tonumber(fillLevel) or tonumber(fillVolume.fillLevel) or 0, capacity)
    local visualFillLevel = math.min(fillLevel / factor, visualCapacity)
    if visualFillLevel > 0 then
        local isFlat = fillVolume.maxPhysicalSurfaceAngle == 0 or fillVolume.maxSurfaceAngle == 0
        local loadSize = isFlat and 10 or 0.1
        local x, y, z = localToWorld(newVolume, -loadSize * 0.5, 0, -loadSize * 0.5)
        local d1x, d1y, d1z = localDirectionToWorld(newVolume, loadSize, 0, 0)
        local d2x, d2y, d2z = localDirectionToWorld(newVolume, 0, 0, loadSize)
        local steps = math.min(math.max(math.floor(visualFillLevel / 400), 1), 50)
        for _ = 1, steps do
            AFVP.baseFillPlaneAdd(newVolume, visualFillLevel / steps, x, y, z, d1x, d1y, d1z, d2x, d2y, d2z)
        end
    end

    fillVolume.fillLevel = fillLevel
    fillVolume.lastFillType = fillTypeIndex
    fillVolume.adjustSuiteAFVPVisualFactor = factor
    AFVP.visualFillVolumes[newVolume] = fillVolume
    updateFillPlaneHook()
    setVisibility(newVolume, fillLevel > 0)
end

local function storageIsUsable(xmlFile, key)
    local handle = xmlFile.handle
    local fillTypes = handle ~= nil and getXMLString(handle, key .. "#fillTypes") or nil
    local fillTypeCategories = handle ~= nil and getXMLString(handle, key .. "#fillTypeCategories") or nil
    return xmlFile:hasProperty(key)
        and (fillTypes ~= nil or fillTypeCategories ~= nil or xmlFile:hasProperty(key .. ".capacity(0)"))
end

local function visitStorageKeys(xmlFile, callback)
    for _, storagePath in ipairs(STORAGE_PATHS) do
        if storagePath.isList then
            xmlFile:iterate(storagePath.path, function(_, key)
                callback(key)
            end)
        elseif xmlFile:hasProperty(storagePath.path) then
            callback(storagePath.path)
        end
    end
end

local function visitStoreStorageKeys(xmlFile, callback)
    visitStorageKeys(xmlFile, callback)
    callback(PRODUCTION_PATH .. ".storage")
    xmlFile:iterate(PRODUCTION_CONFIGURATIONS_PATH, function(_, key)
        callback(key .. ".productionPoint.storage")
    end)
end

local function getSelectedProductionStorageKey(placeable)
    local configurationId = tonumber(placeable.configurations ~= nil and placeable.configurations.productionPoint) or 1
    local key = string.format("%s(%d).productionPoint.storage", PRODUCTION_CONFIGURATIONS_PATH, configurationId - 1)
    if placeable.xmlFile:hasProperty(key) then
        return key
    end
    return PRODUCTION_PATH .. ".storage"
end

local function scaleStorage(xmlFile, key, factor)
    if not storageIsUsable(xmlFile, key) then
        return
    end

    local handle = xmlFile.handle
    local hasGenericFillTypes = handle ~= nil
        and (
            getXMLString(handle, key .. "#fillTypes") ~= nil
            or getXMLString(handle, key .. "#fillTypeCategories") ~= nil
        )
    local hasCustomCapacities = xmlFile:hasProperty(key .. ".capacity(0)")
    if xmlFile:hasProperty(key .. "#capacity") or (hasGenericFillTypes and not hasCustomCapacities) then
        local capacity = tonumber(xmlFile:getValue(key .. "#capacity", 100000)) or 100000
        xmlFile:setValue(key .. "#capacity", math.max(math.ceil(capacity * factor - 0.000001), 1))
    end

    xmlFile:iterate(key .. ".capacity", function(_, capacityKey)
        local value = tonumber(xmlFile:getValue(capacityKey .. "#capacity", 100000)) or 100000
        xmlFile:setValue(capacityKey .. "#capacity", math.max(math.ceil(value * factor - 0.000001), 1))
    end)
end

function AFVP.getStoreContext(xmlFile, _configurations, _defaultConfigurationIds, _customEnvironment, storeItem)
    local hasCapacity = capacityIsUsable(xmlFile, HUSBANDRY_FOOD_CAPACITY_PATH)
        or capacityIsUsable(xmlFile, MANURE_HEAP_CAPACITY_PATH)
    visitStoreStorageKeys(xmlFile, function(key)
        hasCapacity = hasCapacity or storageIsUsable(xmlFile, key)
    end)
    if not hasCapacity then
        return nil
    end

    return { basePrice = Suite.getStoreItemPrice(storeItem, xmlFile) }
end

function AFVP.applyToPlaceableXML(placeable, offset)
    local factor = Suite.getFactorFromOffset(offset)
    placeable.adjustSuiteAFVPFactor = factor
    if factor == 1 then
        return
    end

    visitStorageKeys(placeable.xmlFile, function(key)
        scaleStorage(placeable.xmlFile, key, factor)
    end)

    scaleStorage(placeable.xmlFile, getSelectedProductionStorageKey(placeable), factor)

    if capacityIsUsable(placeable.xmlFile, HUSBANDRY_FOOD_CAPACITY_PATH) then
        scaleCapacity(placeable.xmlFile, HUSBANDRY_FOOD_CAPACITY_PATH, factor)
        if placeable.xmlFile:hasProperty(HUSBANDRY_FOOD_PLANE_CAPACITY_PATH) then
            placeable.xmlFile:setValue(
                HUSBANDRY_FOOD_PLANE_CAPACITY_PATH,
                placeable.xmlFile:getValue(HUSBANDRY_FOOD_CAPACITY_PATH)
            )
        end
    end
    scaleCapacity(placeable.xmlFile, MANURE_HEAP_CAPACITY_PATH, factor)
end

function AFVP.onFeedingRobotLoaded(placeable, robot, _args)
    local factor = tonumber(placeable ~= nil and placeable.adjustSuiteAFVPFactor) or 1
    if robot == nil or factor == 1 or robot.adjustSuiteAFVPScaled == true then
        return
    end

    for _, unloadingSpot in ipairs(robot.unloadingSpots or {}) do
        local capacity = tonumber(unloadingSpot.capacity)
        if capacity ~= nil and capacity > 0 then
            unloadingSpot.capacity = math.max(math.ceil(capacity * factor - 0.000001), 1)
            recreateFillVolume(
                unloadingSpot.fillVolume,
                unloadingSpot.capacity,
                unloadingSpot.fillLevel,
                unloadingSpot.fillTypeIndex,
                factor
            )
        end
    end

    robot.adjustSuiteAFVPScaled = true
end

function AFVP.onFeedingRobotDelete(robot)
    for _, unloadingSpot in ipairs(robot.unloadingSpots or {}) do
        local fillVolume = unloadingSpot.fillVolume
        if type(fillVolume) == "table" and fillVolume.volume ~= nil then
            AFVP.visualFillVolumes[fillVolume.volume] = nil
        end
    end

    local fillPlane = robot.fillPlane
    if type(fillPlane) == "table" and fillPlane.volume ~= nil then
        AFVP.visualFillVolumes[fillPlane.volume] = nil
    end

    updateFillPlaneHook()
end

if
    PlaceableHusbandryFeedingRobot ~= nil
    and PlaceableHusbandryFeedingRobot.onFeedingRobotLoaded ~= nil
    and AFVP.feedingRobotHookInstalled ~= true
then
    AFVP.feedingRobotHookInstalled = true
    PlaceableHusbandryFeedingRobot.onFeedingRobotLoaded =
        Utils.appendedFunction(PlaceableHusbandryFeedingRobot.onFeedingRobotLoaded, AFVP.onFeedingRobotLoaded)
end

if FeedingRobot ~= nil and FeedingRobot.delete ~= nil and AFVP.feedingRobotDeleteHookInstalled ~= true then
    AFVP.feedingRobotDeleteHookInstalled = true
    FeedingRobot.delete = Utils.prependedFunction(FeedingRobot.delete, AFVP.onFeedingRobotDelete)
end
