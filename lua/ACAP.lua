AdjustSuiteACAP = AdjustSuiteACAP or {}
local ACAP = AdjustSuiteACAP

local Suite = AdjustSuite
Suite.moduleClasses["ACAP"] = ACAP
local PRODUCTION_PATH = "placeable.productionPoint"
local PRODUCTION_CONFIGURATIONS_PATH = PRODUCTION_PATH .. ".productionPointConfigurations.productionPointConfiguration"

local function productionPointHasCycleAmounts(xmlFile, key)
    local hasCycleAmounts = false
    xmlFile:iterate(key .. ".productions.production", function(_, productionKey)
        xmlFile:iterate(productionKey .. ".inputs.input", function()
            hasCycleAmounts = true
        end)
        xmlFile:iterate(productionKey .. ".outputs.output", function()
            hasCycleAmounts = true
        end)
    end)
    return hasCycleAmounts
end

function ACAP.getStoreContext(xmlFile, _configurations, _defaultConfigurationIds, _customEnvironment, storeItem)
    local hasCycleAmounts = productionPointHasCycleAmounts(xmlFile, PRODUCTION_PATH)
    xmlFile:iterate(PRODUCTION_CONFIGURATIONS_PATH, function(_, key)
        hasCycleAmounts = hasCycleAmounts or productionPointHasCycleAmounts(xmlFile, key .. ".productionPoint")
    end)
    if not hasCycleAmounts then
        return nil
    end

    return { basePrice = Suite.getStoreItemPrice(storeItem, xmlFile) }
end

local function getSelectedProductionKey(placeable)
    local configurationId = tonumber(placeable.configurations ~= nil and placeable.configurations.productionPoint) or 1
    local key = string.format("%s(%d).productionPoint", PRODUCTION_CONFIGURATIONS_PATH, configurationId - 1)
    if placeable.xmlFile:hasProperty(key) then
        return key
    end
    return PRODUCTION_PATH
end

local function scaleAmount(handle, attribute, factor)
    local value = getXMLFloat(handle, attribute)
    if value ~= nil and value > 0 then
        setXMLFloat(handle, attribute, value * factor)
    end
end

function ACAP.applyToPlaceableXML(placeable, offset)
    local xmlFile = placeable.xmlFile
    if not Suite.isSandboxPlaceableXML(xmlFile) then
        return
    end

    placeable.adjustSuiteACAPScaledInXML = true

    local factor = Suite.getFactorFromOffset(offset)
    if factor == 1 then
        return
    end

    local handle = xmlFile.handle
    if handle ~= nil then
        xmlFile:iterate(getSelectedProductionKey(placeable) .. ".productions.production", function(_, productionKey)
            xmlFile:iterate(productionKey .. ".inputs.input", function(_, inputKey)
                scaleAmount(handle, inputKey .. "#amount", factor)
                xmlFile:iterate(inputKey .. ".outputAmount", function(_, outputAmountKey)
                    scaleAmount(handle, outputAmountKey .. "#active", factor)
                end)
            end)
            xmlFile:iterate(productionKey .. ".outputs.output", function(_, outputKey)
                scaleAmount(handle, outputKey .. "#amount", factor)
            end)
        end)
    end

    Suite.scaleSandboxDistributions(xmlFile, factor)
end
