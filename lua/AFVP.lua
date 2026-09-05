AdjustSuiteAFVP = AdjustSuiteAFVP or {}
local AFVP = AdjustSuiteAFVP

local Suite = AdjustSuite
local STORAGE_PATHS = {
    {path = "placeable.silo.storages.storage", isList = true},
    {path = "placeable.siloExtension.storage"},
    {path = "placeable.husbandry.storage"},
    {path = "placeable.factory.storage"},
    {path = "placeable.constructible.storage"}
}
local PRODUCTION_PATH = "placeable.productionPoint"
local PRODUCTION_CONFIGURATIONS_PATH = PRODUCTION_PATH
    .. ".productionPointConfigurations.productionPointConfiguration"
local HUSBANDRY_FOOD_CAPACITY_PATH = "placeable.husbandry.food#capacity"
local HUSBANDRY_FOOD_PLANE_CAPACITY_PATH = "placeable.husbandry.food.dynamicFoodPlane#capacity"
local MANURE_HEAP_CAPACITY_PATH = "placeable.manureHeap#capacity"

AFVP.visualFillVolumes = AFVP.visualFillVolumes or setmetatable({}, {__mode = "v"})
AFVP.baseFillPlaneAdd = AFVP.baseFillPlaneAdd or fillPlaneAdd
if AFVP.fillPlaneHookInstalled ~= true and AFVP.baseFillPlaneAdd ~= nil then
    AFVP.fillPlaneHookInstalled = true
    fillPlaneAdd = function(fillPlaneId, delta, ...)
        local fillVolume = AFVP.visualFillVolumes[fillPlaneId]
        if fillVolume ~= nil and fillVolume.volume == fillPlaneId then
            delta = delta / (tonumber(fillVolume.adjustSuiteAFVPVisualFactor) or 1)
        end
        return AFVP.baseFillPlaneAdd(fillPlaneId, delta, ...)
    end
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
    if fillVolume.volume == nil or fillVolume.volume == 0
        or fillVolume.baseNode == nil or fillVolume.baseNode == 0
        or createFillPlaneShape == nil then
        return
    end

    local visualCapacity = capacity / factor
    local newVolume = createFillPlaneShape(
        fillVolume.baseNode,
        "fillPlane",
        visualCapacity,
        fillVolume.maxDelta,
        fillVolume.maxSurfaceAngle,
        fillVolume.maxPhysicalSurfaceAngle,
        fillVolume.maxSurfaceDistanceError,
        fillVolume.maxSubDivEdgeLength,
        fillVolume.syncMaxSubDivEdgeLength,
        fillVolume.allSidePlanes,
        fillVolume.retessellateTop
    )
    if newVolume == nil or newVolume == 0 then
        return
    end

    AFVP.visualFillVolumes[fillVolume.volume] = nil
    delete(fillVolume.volume)
    fillVolume.volume = newVolume
    link(fillVolume.baseNode, newVolume)

    local material = g_materialManager ~= nil and g_materialManager:getBaseMaterialByName("fillPlane") or nil
    if material ~= nil then
        setMaterial(newVolume, material, 0)
        if g_fillTypeManager ~= nil and g_terrainNode ~= nil then
            g_fillTypeManager:assignFillTypeTextureArraysFromTerrain(newVolume, g_terrainNode, true, true, true)
        end
    end

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
            AFVP.baseFillPlaneAdd(
                newVolume,
                visualFillLevel / steps,
                x,
                y,
                z,
                d1x,
                d1y,
                d1z,
                d2x,
                d2y,
                d2z
            )
        end
    end

    fillVolume.fillLevel = fillLevel
    fillVolume.lastFillType = fillTypeIndex
    fillVolume.adjustSuiteAFVPVisualFactor = factor
    AFVP.visualFillVolumes[newVolume] = fillVolume
    setVisibility(newVolume, fillLevel > 0)
end

local function storageIsUsable(xmlFile, key)
    local handle = xmlFile.handle
    local fillTypes = handle ~= nil and getXMLString(handle, key .. "#fillTypes") or nil
    local fillTypeCategories = handle ~= nil and getXMLString(handle, key .. "#fillTypeCategories") or nil
    return xmlFile:hasProperty(key)
        and (fillTypes ~= nil
            or fillTypeCategories ~= nil
            or xmlFile:hasProperty(key .. ".capacity(0)"))
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
        and (getXMLString(handle, key .. "#fillTypes") ~= nil
            or getXMLString(handle, key .. "#fillTypeCategories") ~= nil)
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

function AFVP.getStoreContext(xmlFile, configurations, defaultConfigurationIds, customEnvironment, storeItem)
    local hasCapacity = capacityIsUsable(xmlFile, HUSBANDRY_FOOD_CAPACITY_PATH)
        or capacityIsUsable(xmlFile, MANURE_HEAP_CAPACITY_PATH)
    visitStoreStorageKeys(xmlFile, function(key)
        hasCapacity = hasCapacity or storageIsUsable(xmlFile, key)
    end)
    if not hasCapacity then
        return nil
    end

    return {basePrice = Suite.getStoreItemPrice(storeItem, xmlFile)}
end

function AFVP.applyToPlaceableXML(placeable, offset)
    local factor = Suite.getFactorFromOffset(offset)
    placeable.adjustSuiteAFVPFactor = factor
    if factor == 1 then
        return
    end

    local seen = {}
    visitStorageKeys(placeable.xmlFile, function(key)
        seen[key] = true
        scaleStorage(placeable.xmlFile, key, factor)
    end)

    local productionStorageKey = getSelectedProductionStorageKey(placeable)
    if not seen[productionStorageKey] then
        scaleStorage(placeable.xmlFile, productionStorageKey, factor)
    end

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

function AFVP.onFeedingRobotLoaded(placeable, robot, args)
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
end

if PlaceableHusbandryFeedingRobot ~= nil
    and PlaceableHusbandryFeedingRobot.onFeedingRobotLoaded ~= nil
    and AFVP.feedingRobotHookInstalled ~= true then
    AFVP.feedingRobotHookInstalled = true
    PlaceableHusbandryFeedingRobot.onFeedingRobotLoaded = Utils.appendedFunction(
        PlaceableHusbandryFeedingRobot.onFeedingRobotLoaded,
        AFVP.onFeedingRobotLoaded
    )
end

if FeedingRobot ~= nil and FeedingRobot.delete ~= nil and AFVP.feedingRobotDeleteHookInstalled ~= true then
    AFVP.feedingRobotDeleteHookInstalled = true
    FeedingRobot.delete = Utils.prependedFunction(FeedingRobot.delete, AFVP.onFeedingRobotDelete)
end
