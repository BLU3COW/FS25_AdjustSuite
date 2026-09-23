AdjustSuiteACRP = AdjustSuiteACRP or {}
local ACRP = AdjustSuiteACRP

local Suite = AdjustSuite
Suite.moduleClasses["ACRP"] = ACRP
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

function ACRP.applyToPlaceableXML(placeable, offset)
    local factor = Suite.getFactorFromOffset(offset)
    if factor == 1 then
        return
    end

    Suite.scaleSandboxDistributions(placeable.xmlFile, factor)
end
