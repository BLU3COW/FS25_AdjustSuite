AdjustSuiteACRP = AdjustSuiteACRP or {}
local ACRP = AdjustSuiteACRP

local Suite = AdjustSuite
local PRODUCTION_PATH = "placeable.productionPoint"
local PRODUCTION_CONFIGURATIONS_PATH = PRODUCTION_PATH
    .. ".productionPointConfigurations.productionPointConfiguration"
local CYCLE_ATTRIBUTES = {"cyclesPerMonth", "cyclesPerHour", "cyclesPerMinute"}

local function productionPointHasCycles(xmlFile, key)
    local hasCycles = false
    xmlFile:iterate(key .. ".productions.production", function(_, productionKey)
        for _, attribute in ipairs(CYCLE_ATTRIBUTES) do
            hasCycles = hasCycles or xmlFile:hasProperty(productionKey .. "#" .. attribute)
        end
    end)
    return hasCycles
end

function ACRP.getStoreContext(xmlFile, configurations, defaultConfigurationIds, customEnvironment, storeItem)
    local hasCycles = productionPointHasCycles(xmlFile, PRODUCTION_PATH)
    xmlFile:iterate(PRODUCTION_CONFIGURATIONS_PATH, function(_, key)
        hasCycles = hasCycles or productionPointHasCycles(xmlFile, key .. ".productionPoint")
    end)
    if not hasCycles then
        return nil
    end

    return {basePrice = Suite.getStoreItemPrice(storeItem, xmlFile)}
end

function ACRP.applyToProductionPoint(productionPoint)
    Suite.applyProductionAdjustments(productionPoint)
end

function ACRP.refreshProductionPoints()
    local manager = g_currentMission ~= nil and g_currentMission.productionChainManager or nil
    for _, productionPoint in ipairs(manager ~= nil and manager.productionPoints or {}) do
        ACRP.applyToProductionPoint(productionPoint)
    end
end

if ProductionPoint ~= nil and ProductionPoint.register ~= nil and ACRP.hookInstalled ~= true then
    ACRP.hookInstalled = true
    ProductionPoint.register = Utils.appendedFunction(
        ProductionPoint.register,
        ACRP.applyToProductionPoint
    )
end

if AdjustSuiteSettingsEvent ~= nil
    and AdjustSuiteSettingsEvent.run ~= nil
    and ACRP.settingsHookInstalled ~= true then
    ACRP.settingsHookInstalled = true
    AdjustSuiteSettingsEvent.run = Utils.appendedFunction(
        AdjustSuiteSettingsEvent.run,
        ACRP.refreshProductionPoints
    )
end
