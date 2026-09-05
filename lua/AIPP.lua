AdjustSuiteAIPP = AdjustSuiteAIPP or {}
local AIPP = AdjustSuiteAIPP

local Suite = AdjustSuite
local INCOME_PATH = "placeable.incomePerHour"
local INCOME_CONFIGURATIONS_PATH = INCOME_PATH
    .. ".incomePerHourConfigurations.incomePerHourConfiguration"
local SOLAR_CONFIGURATIONS_PATH = "placeable.solarPanels.solarPanelsConfigurations.solarPanelsConfiguration"

local function valueIsIncome(xmlFile, key)
    local value = tonumber(xmlFile:getValue(key))
    return value ~= nil and value > 0
end

local function getConfigurationId(key)
    local index = tonumber(string.match(key, "%((%d+)%)$"))
    return index ~= nil and index + 1 or nil
end

local function containsTrue(values)
    for _, value in pairs(values) do
        if value == true then
            return true
        end
    end
    return false
end

local function scaleValue(xmlFile, key, factor)
    local value = tonumber(xmlFile:getValue(key))
    if value ~= nil and value > 0 then
        xmlFile:setValue(key, value * factor)
    end
end

local function selectedAttributeKey(placeable, configurationName, configurationsPath, attribute)
    local configurationId = tonumber(placeable.configurations ~= nil and placeable.configurations[configurationName]) or 1
    return string.format("%s(%d)#%s", configurationsPath, configurationId - 1, attribute)
end

function AIPP.getStoreContext(xmlFile, configurations, defaultConfigurationIds, customEnvironment, storeItem)
    local hasFixedIncome = valueIsIncome(xmlFile, INCOME_PATH)
        or valueIsIncome(xmlFile, "placeable.windTurbine#incomePerHour")
    local incomeByConfiguration = {}
    local solarByConfiguration = {}

    xmlFile:iterate(INCOME_CONFIGURATIONS_PATH, function(_, key)
        local configurationId = getConfigurationId(key)
        if configurationId ~= nil then
            incomeByConfiguration[configurationId] = valueIsIncome(xmlFile, key .. "#incomePerHour")
        end
    end)
    xmlFile:iterate(SOLAR_CONFIGURATIONS_PATH, function(_, key)
        local configurationId = getConfigurationId(key)
        if configurationId ~= nil then
            solarByConfiguration[configurationId] = xmlFile:getValue(key .. "#isActive", false)
                and valueIsIncome(xmlFile, key .. "#incomePerHour")
        end
    end)

    local hasConfigurableIncome = containsTrue(incomeByConfiguration)
        or containsTrue(solarByConfiguration)
    if not hasFixedIncome and not hasConfigurableIncome then
        return nil
    end

    return {
        basePrice = Suite.getStoreItemPrice(storeItem, xmlFile),
        hasFixedIncome = hasFixedIncome,
        incomeByConfiguration = incomeByConfiguration,
        solarByConfiguration = solarByConfiguration
    }
end

function AIPP.rememberStoreContext(storeItem, context)
    storeItem.AIPPHasFixedIncome = context.hasFixedIncome == true
    storeItem.AIPPIncomeByConfiguration = context.incomeByConfiguration
    storeItem.AIPPSolarByConfiguration = context.solarByConfiguration
end

function AIPP.applyToPlaceableXML(placeable, offset)
    local factor = Suite.getFactorFromOffset(offset)
    if factor == 1 then
        return
    end

    local xmlFile = placeable.xmlFile
    scaleValue(xmlFile, INCOME_PATH, factor)
    scaleValue(xmlFile, "placeable.windTurbine#incomePerHour", factor)
    scaleValue(xmlFile, selectedAttributeKey(
        placeable,
        "incomePerHour",
        INCOME_CONFIGURATIONS_PATH,
        "incomePerHour"
    ), factor)
    scaleValue(xmlFile, selectedAttributeKey(
        placeable,
        "solarPanels",
        SOLAR_CONFIGURATIONS_PATH,
        "incomePerHour"
    ), factor)
end
