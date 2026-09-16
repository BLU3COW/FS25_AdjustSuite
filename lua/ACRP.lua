AdjustSuiteACRP = AdjustSuiteACRP or {}
local ACRP = AdjustSuiteACRP

local Suite = AdjustSuite
local PRODUCTION_PATH = "placeable.productionPoint"
local PRODUCTION_CONFIGURATIONS_PATH = PRODUCTION_PATH .. ".productionPointConfigurations.productionPointConfiguration"

local function productionPointHasCycles(xmlFile, key)
    local hasCycles = false
    xmlFile:iterate(key .. ".productions.production", function()
        hasCycles = true
    end)
    return hasCycles
end

function ACRP.getStoreContext(xmlFile, _configurations, _defaultConfigurationIds, _customEnvironment, storeItem)
    local hasCycles = productionPointHasCycles(xmlFile, PRODUCTION_PATH)
    xmlFile:iterate(PRODUCTION_CONFIGURATIONS_PATH, function(_, key)
        hasCycles = hasCycles or productionPointHasCycles(xmlFile, key .. ".productionPoint")
    end)
    if not hasCycles then
        return nil
    end

    return { basePrice = Suite.getStoreItemPrice(storeItem, xmlFile) }
end
