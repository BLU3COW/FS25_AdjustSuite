local safeCall = pcall
AdjustSuiteADRP = AdjustSuiteADRP or {}
local ADRP = AdjustSuiteADRP

local Suite = AdjustSuite
Suite.moduleClasses["ADRP"] = ADRP
ADRP.placeableXMLFiles = ADRP.placeableXMLFiles or setmetatable({}, { __mode = "k" })
local LOAD_TRIGGER_PATHS = {
    "placeable.silo.loadingStation.loadTrigger",
    "placeable.buyingStation.loadTrigger",
    "placeable.husbandry.loadingStation.loadTrigger",
    "placeable.manureHeap.loadingStation.loadTrigger",
    "placeable.VariableBunker.outputStation.loadTrigger",
}
local PRODUCTION_PATH = "placeable.productionPoint"
local PRODUCTION_CONFIGURATIONS_PATH = PRODUCTION_PATH .. ".productionPointConfigurations.productionPointConfiguration"

local function visitLoadTriggerPath(xmlFile, path, callback)
    local found = false
    xmlFile:iterate(path, function(_, key)
        found = true
        callback(key)
    end)
    if not found and xmlFile:hasProperty(path) then
        callback(path)
    end
end

local function visitStoreLoadTriggers(xmlFile, callback)
    for _, path in ipairs(LOAD_TRIGGER_PATHS) do
        visitLoadTriggerPath(xmlFile, path, callback)
    end

    visitLoadTriggerPath(xmlFile, PRODUCTION_PATH .. ".loadingStation.loadTrigger", callback)
    xmlFile:iterate(PRODUCTION_CONFIGURATIONS_PATH, function(_, key)
        visitLoadTriggerPath(xmlFile, key .. ".productionPoint.loadingStation.loadTrigger", callback)
    end)
end

local function visitSelectedLoadTriggers(placeable, callback)
    for _, path in ipairs(LOAD_TRIGGER_PATHS) do
        visitLoadTriggerPath(placeable.xmlFile, path, callback)
    end

    local configurationId = tonumber(placeable.configurations ~= nil and placeable.configurations.productionPoint) or 1
    local productionKey = string.format("%s(%d).productionPoint", PRODUCTION_CONFIGURATIONS_PATH, configurationId - 1)
    if not placeable.xmlFile:hasProperty(productionKey) then
        productionKey = PRODUCTION_PATH
    end
    visitLoadTriggerPath(placeable.xmlFile, productionKey .. ".loadingStation.loadTrigger", callback)
end

function ADRP.getStoreContext(xmlFile, _configurations, _defaultConfigurationIds, _customEnvironment, storeItem)
    local hasTrigger = false
    visitStoreLoadTriggers(xmlFile, function()
        hasTrigger = true
    end)
    if not hasTrigger then
        return nil
    end

    return { basePrice = Suite.getStoreItemPrice(storeItem, xmlFile) }
end

function ADRP.applyToPlaceableXML(placeable, offset)
    if type(placeable.xmlFile) == "table" then
        ADRP.placeableXMLFiles[placeable.xmlFile] = true
    end

    local factor = Suite.getFactorFromOffset(offset)
    if factor == 1 then
        return
    end

    visitSelectedLoadTriggers(placeable, function(key)
        local value = tonumber(placeable.xmlFile:getValue(key .. "#fillLitersPerSecond", 1000)) or 1000
        placeable.xmlFile:setValue(key .. "#fillLitersPerSecond", math.max(math.ceil(value * factor - 0.000001), 1))
    end)
end

function ADRP.getEffectiveFillLitersPerMS(loadTrigger)
    local current = tonumber(loadTrigger ~= nil and loadTrigger.fillLitersPerMS)
    if current == nil or Suite.respectExternalCapacityOverrides == true then
        return current
    end

    local base = tonumber(loadTrigger.adjustSuiteADRPFillLitersPerMS)
    if base ~= nil and base > 0 then
        return base
    end

    return current
end

function ADRP.loadLoadTrigger(loadTrigger, superFunc, components, xmlFile, ...)
    local loaded = superFunc(loadTrigger, components, xmlFile, ...)
    if loaded ~= false and type(xmlFile) == "table" and ADRP.placeableXMLFiles[xmlFile] == true then
        loadTrigger.adjustSuiteADRPFillLitersPerMS = tonumber(loadTrigger.fillLitersPerMS)
    end
    return loaded
end

function ADRP.updateLoadTrigger(loadTrigger, superFunc, ...)
    local current = loadTrigger.fillLitersPerMS
    local effective = ADRP.getEffectiveFillLitersPerMS(loadTrigger)
    if effective == nil or effective == current then
        return superFunc(loadTrigger, ...)
    end

    loadTrigger.fillLitersPerMS = effective
    local ok, result = safeCall(superFunc, loadTrigger, ...)
    loadTrigger.fillLitersPerMS = current
    if not ok then
        error(result, 0)
    end
    return result
end

function ADRP.installLoadTriggerHooks(loadTriggerClass)
    if loadTriggerClass == nil or loadTriggerClass.load == nil or loadTriggerClass.update == nil then
        return false
    end

    loadTriggerClass.load = Utils.overwrittenFunction(loadTriggerClass.load, ADRP.loadLoadTrigger)
    loadTriggerClass.update = Utils.overwrittenFunction(loadTriggerClass.update, ADRP.updateLoadTrigger)
    return true
end

if ADRP.loadTriggerHooksInstalled ~= true then
    ADRP.loadTriggerHooksInstalled = ADRP.installLoadTriggerHooks(LoadTrigger)
end
