AdjustSuiteADRP = AdjustSuiteADRP or {}
local ADRP = AdjustSuiteADRP

local Suite = AdjustSuite
local LOAD_TRIGGER_PATHS = {
    "placeable.silo.loadingStation.loadTrigger",
    "placeable.buyingStation.loadTrigger",
    "placeable.husbandry.loadingStation.loadTrigger",
    "placeable.manureHeap.loadingStation.loadTrigger"
}
local PRODUCTION_PATH = "placeable.productionPoint"
local PRODUCTION_CONFIGURATIONS_PATH = PRODUCTION_PATH
    .. ".productionPointConfigurations.productionPointConfiguration"

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
    local productionKey = string.format(
        "%s(%d).productionPoint",
        PRODUCTION_CONFIGURATIONS_PATH,
        configurationId - 1
    )
    if not placeable.xmlFile:hasProperty(productionKey) then
        productionKey = PRODUCTION_PATH
    end
    visitLoadTriggerPath(placeable.xmlFile, productionKey .. ".loadingStation.loadTrigger", callback)
end

function ADRP.getStoreContext(xmlFile, configurations, defaultConfigurationIds, customEnvironment, storeItem)
    local hasTrigger = false
    visitStoreLoadTriggers(xmlFile, function()
        hasTrigger = true
    end)
    if not hasTrigger then
        return nil
    end

    return {basePrice = Suite.getStoreItemPrice(storeItem, xmlFile)}
end

function ADRP.applyToPlaceableXML(placeable, offset)
    local factor = Suite.getFactorFromOffset(offset)
    if factor == 1 then
        return
    end

    visitSelectedLoadTriggers(placeable, function(key)
        local value = tonumber(placeable.xmlFile:getValue(key .. "#fillLitersPerSecond", 1000)) or 1000
        placeable.xmlFile:setValue(
            key .. "#fillLitersPerSecond",
            math.max(math.floor(value * factor + 0.5), 1)
        )
    end)
end
