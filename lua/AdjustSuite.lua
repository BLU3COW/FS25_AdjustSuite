AdjustSuite = AdjustSuite or {}

local Suite = AdjustSuite
local MODULE_SETTING_KEYS = {"module", "real", "unreal", "extreme"}

Suite.vehicleModuleIds = {"AFV", "AFC", "APC", "ABW", "AMP", "AWS", "AWW", "APW", "ADS", "ABP", "ADR"}
Suite.placeableModuleIds = {"AFVP", "ADRP", "ACRP", "ACAP", "AIPP"}
Suite.moduleIds = {}
for _, moduleId in ipairs(Suite.vehicleModuleIds) do
    table.insert(Suite.moduleIds, moduleId)
end
for _, moduleId in ipairs(Suite.placeableModuleIds) do
    table.insert(Suite.moduleIds, moduleId)
end
Suite.moduleLabels = {
    AFVP = "AFV-P",
    ADRP = "ADR-P",
    ACRP = "ACR-P",
    ACAP = "ACA-P",
    AIPP = "AIP-P"
}
Suite.ignoredFillTypeNames = Suite.ignoredFillTypeNames or {
    DIESEL = true,
    DEF = true,
    AIR = true,
    ELECTRICCHARGE = true,
    ELECTRICITY = true,
    METHANE = true,
    FUEL = true,
    BALE = true,
    ROUNDBALE = true,
    SQUAREBALE = true
}

function Suite.fillTypeIsAir(fillTypeIndex)
    if FillType ~= nil and FillType.AIR ~= nil and fillTypeIndex == FillType.AIR then
        return true
    end

    if fillTypeIndex ~= nil
        and g_fillTypeManager ~= nil
        and g_fillTypeManager.getFillTypeNameByIndex ~= nil then
        local ok, name = pcall(g_fillTypeManager.getFillTypeNameByIndex, g_fillTypeManager, fillTypeIndex)
        if ok and string.upper(tostring(name or "")) == "AIR" then
            return true
        end
    end

    return false
end

function Suite.getOperatingConsumerFillUnitIndices(vehicle)
    local motorizedSpec = vehicle ~= nil and vehicle.spec_motorized or nil
    if motorizedSpec == nil then
        return nil
    end

    local cachedIndices = motorizedSpec.adjustSuiteOperatingConsumerFillUnitIndices
    if cachedIndices ~= nil then
        return cachedIndices ~= false and cachedIndices or nil
    end

    local consumers = motorizedSpec.consumers
    if consumers == nil then
        return nil
    end

    local indices = {}
    for _, consumer in pairs(consumers) do
        local fillUnitIndex = consumer ~= nil and tonumber(consumer.fillUnitIndex) or nil
        if fillUnitIndex ~= nil
            and fillUnitIndex > 0
            and not Suite.fillTypeIsAir(consumer.fillType) then
            indices[math.floor(fillUnitIndex + 0.5)] = true
        end
    end

    motorizedSpec.adjustSuiteOperatingConsumerFillUnitIndices = next(indices) ~= nil and indices or false
    return next(indices) ~= nil and indices or nil
end

function Suite.fillUnitIsOperatingConsumer(vehicle, fillUnitIndex)
    local indices = Suite.getOperatingConsumerFillUnitIndices(vehicle)
    return indices ~= nil and indices[fillUnitIndex] == true
end
Suite.range = Suite.range or {
    minFactor = 0.20,
    realOffset = 20,
    unrealOffset = 200,
    minAbsoluteSpeed = 1,
    defaultIndex = 8,
    pricePerPercent = 0.0025
}
Suite.configurationOffsets = Suite.configurationOffsets or {
    -80, -60, -40, -20, -15, -10, -5,
    0,
    5, 10, 15, 20,
    40, 60, 80, 100, 120, 140, 160, 180, 200,
    300, 400, 500, 600, 700, 800
}
Suite.selectionSettings = Suite.selectionSettings or {}
Suite.showHelpMenu = Suite.showHelpMenu ~= false

local function normalizePricePercent(value)
    value = tonumber(value)
    if value == nil or value ~= value then
        return 100
    end
    return math.max(value, 0)
end

Suite.pricePercent = normalizePricePercent(Suite.pricePercent)

local SETTINGS_ROOT = "adjustSuiteSettings"
local SETTINGS_HELP_MENU_KEY = SETTINGS_ROOT .. ".settings.helpmenu"
local SETTINGS_PRICE_KEY = SETTINGS_ROOT .. ".settings.price"
local SETTINGS_MODULES_KEY = SETTINGS_ROOT .. ".modules"
local DEFAULT_MODULE_SETTINGS = {
    module = true,
    real = true,
    unreal = true,
    extreme = false
}

function Suite.getModuleIdFromConfigurationName(configurationName)
    return string.match(tostring(configurationName or ""), "^(%u+)$")
end

function Suite.getModuleLabel(moduleId)
    return Suite.moduleLabels[moduleId] or moduleId
end

function Suite.getModuleIdFromDisplayText(text)
    local label = string.match(tostring(text or ""), "^([%u%-]+):")
    return label ~= nil and string.gsub(label, "%-", "") or nil
end

local BALLAST_TOKENS = {"weight", "ballast", "gewicht", "counterweight"}

function Suite.textLooksLikeBallast(value)
    value = string.lower(tostring(value or ""))
    for _, token in ipairs(BALLAST_TOKENS) do
        if string.find(value, token, 1, true) ~= nil then
            return true
        end
    end
    return false
end

function Suite.xmlIsStandaloneWeight(xmlFile)
    if xmlFile == nil then
        return false
    end

    local category = string.lower(tostring(xmlFile:getValue("vehicle.storeData.category", "")))
    if category == "weight" or category == "weights" then
        return true
    end

    return Suite.textLooksLikeBallast(xmlFile:getValue("vehicle.base.typeDesc", ""))
        and xmlFile:hasProperty("vehicle.attachable")
        and not xmlFile:hasProperty("vehicle.motorized")
end

local function getPositiveConfigurationParameter(xmlFile, configurationKey)
    local value = tostring(xmlFile:getValue(configurationKey .. "#params", ""))
    for number in string.gmatch(value, "[%+%-]?[%d%.]+") do
        number = tonumber(number)
        if number ~= nil and number > 0 then
            return number
        end
    end
    return nil
end

local function configurationDisablesBallast(xmlFile, configurationKey)
    local name = tostring(xmlFile:getValue(configurationKey .. "#name", ""))
    local normalizedName = string.gsub(string.lower(name), "[^%w]", "")
    return string.find(normalizedName, "configurationvalueno", 1, true) ~= nil
        or normalizedName == "no"
        or normalizedName == "nein"
        or normalizedName == "non"
        or normalizedName == "nee"
        or normalizedName == "nie"
end

local function getBallastDescriptor(xmlFile, configurationKey, configurationsKey)
    return tostring(xmlFile:getValue(configurationKey .. "#name", ""))
        .. " " .. tostring(xmlFile:getValue(configurationKey .. "#params", ""))
        .. " " .. tostring(configurationsKey ~= nil
            and xmlFile:getValue(configurationsKey .. "#title", "")
            or "")
end

local function hasBallastConfigurationKey(xmlFile, configurationKey)
    return xmlFile ~= nil
        and type(configurationKey) == "string"
        and configurationKey ~= ""
        and xmlFile:hasProperty(configurationKey)
end

function Suite.getBallastObjectChanges(xmlFile, configurationKey, configurationsKey, configurationBaseKey)
    if not hasBallastConfigurationKey(xmlFile, configurationKey) then
        return {}
    end

    if configurationDisablesBallast(xmlFile, configurationKey) then
        return {}
    end

    if not Suite.textLooksLikeBallast(getBallastDescriptor(xmlFile, configurationKey, configurationsKey)) then
        return {}
    end

    local entries = {}
    local parameterMass = getPositiveConfigurationParameter(xmlFile, configurationKey)
    for _, objectChangeKey in xmlFile:iterator(configurationKey .. ".objectChange") do
        local activeMass = tonumber(xmlFile:getValue(objectChangeKey .. "#massActive"))
        local inactiveMass = tonumber(xmlFile:getValue(objectChangeKey .. "#massInactive"))
        if activeMass ~= nil and activeMass > 0 then
            if inactiveMass == nil then
                table.insert(entries, {
                    objectChangeKey = objectChangeKey,
                    mass = parameterMass or 1,
                    effectiveMass = activeMass,
                    deriveFromBase = parameterMass == nil
                })
            elseif activeMass > inactiveMass then
                table.insert(entries, {
                    objectChangeKey = objectChangeKey,
                    mass = activeMass - inactiveMass,
                    effectiveMass = activeMass
                })
            end
        end
    end
    if #entries > 0 or configurationBaseKey == nil then
        return entries
    end

    local index = 0
    while true do
        local siblingKey = string.format(configurationBaseKey .. "(%d)", index)
        if not xmlFile:hasProperty(siblingKey) then
            break
        end
        if siblingKey ~= configurationKey then
            for _, objectChangeKey in xmlFile:iterator(siblingKey .. ".objectChange") do
                local activeMass = tonumber(xmlFile:getValue(objectChangeKey .. "#massActive"))
                local inactiveMass = tonumber(xmlFile:getValue(objectChangeKey .. "#massInactive"))
                if activeMass ~= nil and inactiveMass ~= nil and inactiveMass > activeMass then
                    table.insert(entries, {
                        objectChangeKey = objectChangeKey,
                        mass = inactiveMass - activeMass,
                        effectiveMass = inactiveMass
                    })
                end
            end
            if #entries > 0 then
                break
            end
        end
        index = index + 1
    end
    return entries
end

function Suite.getBallastConfigurationMass(xmlFile, configurationKey, configurationsKey, configurationBaseKey)
    if not hasBallastConfigurationKey(xmlFile, configurationKey) then
        return 0
    end

    if configurationDisablesBallast(xmlFile, configurationKey)
        or not Suite.textLooksLikeBallast(getBallastDescriptor(xmlFile, configurationKey, configurationsKey)) then
        return 0
    end

    local mass = 0
    for _, componentKey in xmlFile:iterator(configurationKey .. ".component") do
        mass = mass + math.max(tonumber(xmlFile:getValue(componentKey .. "#additionalMass", 0)) or 0, 0)
    end
    if mass > 0 then
        return mass
    end

    for _, entry in ipairs(Suite.getBallastObjectChanges(
        xmlFile,
        configurationKey,
        configurationsKey,
        configurationBaseKey
    )) do
        mass = mass + entry.mass
    end
    return mass
end

function Suite.getIsModuleEnabled(moduleId)
    local settings = Suite.selectionSettings[moduleId]
    return settings == nil or settings.module ~= false
end

function Suite.getShowHelpMenu()
    return Suite.showHelpMenu ~= false
end

function Suite.getPricePercent()
    return Suite.pricePercent
end

function Suite.canShowHelpText(vehicle, isActiveForInputIgnoreSelection)
    return vehicle ~= nil
        and vehicle.isClient == true
        and isActiveForInputIgnoreSelection == true
        and Suite.getShowHelpMenu()
        and g_currentMission ~= nil
        and g_currentMission.addExtraPrintText ~= nil
end

function Suite.addHelpText(text)
    local moduleId = Suite.getModuleIdFromDisplayText(text)
    if moduleId ~= nil and not Suite.getIsModuleEnabled(moduleId) then
        return
    end

    if text ~= nil and g_currentMission ~= nil and g_currentMission.addExtraPrintText ~= nil then
        g_currentMission:addExtraPrintText(text)
    end
end

function Suite.resolveNode(value)
    if type(value) == "table" then
        return value.node or value.index or value.nodeId
    end
    return value
end

function Suite.getNodePosition(node, referenceNode)
    if type(node) ~= "number" or node == 0
        or type(referenceNode) ~= "number" or referenceNode == 0
        or localToLocal == nil then
        return nil
    end

    local ok, x, y, z = pcall(localToLocal, node, referenceNode, 0, 0, 0)
    if ok and type(x) == "number" and type(y) == "number" and type(z) == "number" then
        return x, y, z
    end
    return nil
end

function Suite.setNodePosition(node, referenceNode, x, y, z)
    if type(node) ~= "number" or node == 0
        or type(referenceNode) ~= "number" or referenceNode == 0
        or getParent == nil or localToLocal == nil or setTranslation == nil then
        return false
    end

    local okParent, parent = pcall(getParent, node)
    if not okParent or type(parent) ~= "number" or parent == 0 then
        return false
    end

    local okPosition, px, py, pz = pcall(localToLocal, referenceNode, parent, x, y, z)
    if not okPosition or type(px) ~= "number" or type(py) ~= "number" or type(pz) ~= "number" then
        return false
    end
    return pcall(setTranslation, node, px, py, pz)
end

function Suite.getIsLoweredForWork(vehicle)
    if vehicle == nil then
        return false
    end

    if vehicle.spec_turnOnVehicle ~= nil and vehicle.doCheckSpeedLimit ~= nil then
        local ok, isWorking = pcall(vehicle.doCheckSpeedLimit, vehicle)
        if ok and isWorking ~= nil then
            return isWorking == true
        end
    end

    local specLowerable = vehicle.spec_lowerable
    local hasLoweringState = specLowerable ~= nil
        or vehicle.spec_foldable ~= nil
        or vehicle.spec_pickup ~= nil
    if hasLoweringState and vehicle.getIsLowered ~= nil then
        local ok, lowered = pcall(vehicle.getIsLowered, vehicle)
        if ok and lowered ~= nil then
            return lowered == true
        end
    end

    if specLowerable ~= nil then
        if specLowerable.isLowered ~= nil then
            return specLowerable.isLowered == true
        end
        if specLowerable.lowered ~= nil then
            return specLowerable.lowered == true
        end
        return false
    end

    return true
end

function Suite.roundToStep(value)
    value = tonumber(value) or 0
    local nearestOffset = 0
    local nearestDistance = math.huge

    for _, offset in ipairs(Suite.configurationOffsets) do
        local distance = math.abs(value - offset)
        if distance < nearestDistance then
            nearestOffset = offset
            nearestDistance = distance
        end
    end

    return nearestOffset
end

function Suite.clampOffset(offset)
    return Suite.roundToStep(offset)
end

function Suite.getFactorFromOffset(offset)
    return math.max(1 + (Suite.clampOffset(offset) / 100), Suite.range.minFactor)
end

function Suite.getDefaultIndex()
    return Suite.range.defaultIndex
end

function Suite.getOffsetFromConfigId(configId)
    local defaultIndex = Suite.getDefaultIndex()
    configId = math.floor(tonumber(configId) or defaultIndex)

    if configId < 1 or configId > #Suite.configurationOffsets then
        configId = defaultIndex
    end

    return Suite.configurationOffsets[configId]
end

function Suite.getSelectedOffset(vehicle, configurationName)
    local moduleId = Suite.getModuleIdFromConfigurationName(configurationName)
    if moduleId ~= nil and not Suite.getIsModuleEnabled(moduleId) then
        return 0
    end

    if vehicle ~= nil and vehicle.configurations ~= nil and vehicle.configurations[configurationName] ~= nil then
        return Suite.getOffsetFromConfigId(vehicle.configurations[configurationName])
    end

    return 0
end

local function getBasePerMonthValue(production, baseField, monthField, hourField, minuteField)
    local baseValue = tonumber(production[baseField])
    if baseValue == nil then
        local monthValue = tonumber(production[monthField])
        local hourValue = tonumber(production[hourField])
        local minuteValue = tonumber(production[minuteField])
        if monthValue ~= nil then
            baseValue = monthValue
        elseif hourValue ~= nil then
            baseValue = hourValue * 24
        elseif minuteValue ~= nil then
            baseValue = minuteValue * 1440
        end
        production[baseField] = baseValue
    end
    return baseValue
end

local function applyPerMonthValue(production, baseField, monthField, hourField, minuteField, factor, minimum)
    local baseValue = getBasePerMonthValue(production, baseField, monthField, hourField, minuteField)
    if baseValue == nil then
        return
    end

    local value = baseValue * factor
    if minimum ~= nil then
        value = math.max(value, minimum)
    end
    production[monthField] = value
    production[hourField] = value / 24
    production[minuteField] = value / 1440
end

local function applyCycleAmounts(entries, factor)
    for _, entry in ipairs(entries or {}) do
        local baseAmount = tonumber(entry.adjustSuiteACAPBaseAmount)
        if baseAmount == nil then
            baseAmount = tonumber(entry.amount)
            entry.adjustSuiteACAPBaseAmount = baseAmount
        end
        if baseAmount ~= nil then
            entry.amount = math.max(baseAmount * factor, 0)
        end
    end
end

function Suite.applyProductionAdjustments(productionPoint)
    if productionPoint == nil then
        return
    end

    local placeable = productionPoint.owningPlaceable
    local rateFactor = Suite.getFactorFromOffset(Suite.getSelectedOffset(placeable, "ACRP"))
    local amountFactor = Suite.getFactorFromOffset(Suite.getSelectedOffset(placeable, "ACAP"))

    for _, production in ipairs(productionPoint.productions or {}) do
        applyPerMonthValue(
            production,
            "adjustSuiteACRPBaseCyclesPerMonth",
            "cyclesPerMonth",
            "cyclesPerHour",
            "cyclesPerMinute",
            rateFactor,
            0.000001
        )
        applyCycleAmounts(production.inputs, amountFactor)
        applyCycleAmounts(production.outputs, amountFactor)
        applyPerMonthValue(
            production,
            "adjustSuiteBaseCostsPerActiveMonth",
            "costsPerActiveMonth",
            "costsPerActiveHour",
            "costsPerActiveMinute",
            rateFactor * amountFactor,
            0
        )
    end

end

function Suite.createModuleAccessors(configurationName)
    local specName = "spec_" .. configurationName

    local function getSpec(vehicle)
        vehicle[specName] = vehicle[specName] or {}
        return vehicle[specName]
    end

    local function getSelectedOffset(vehicle)
        return Suite.getSelectedOffset(vehicle, configurationName)
    end

    local function hasSelectedConfiguration(vehicle)
        return vehicle ~= nil
            and vehicle.configurations ~= nil
            and vehicle.configurations[configurationName] ~= nil
    end

    local function getFactor(vehicle)
        local spec = getSpec(vehicle)
        if spec.currentFactor == nil then
            spec.currentOffset = getSelectedOffset(vehicle)
            spec.currentFactor = Suite.getFactorFromOffset(spec.currentOffset)
        end
        return spec.currentFactor
    end

    return getSpec, getSelectedOffset, hasSelectedConfiguration, getFactor
end

function Suite.getStatusTier(offset)
    local absOffset = math.abs(Suite.clampOffset(offset))

    if absOffset == 0 then
        return "BASE"
    elseif absOffset <= Suite.range.realOffset then
        return "REAL"
    elseif absOffset <= Suite.range.unrealOffset then
        return "UNREAL"
    end

    return "EXTREME"
end

function Suite.getStatusText(offset)
    return g_i18n:getText(string.format("CONFIG_AS_%s", Suite.getStatusTier(offset)))
end

function Suite.getOffsetText(offset)
    return offset == 0
        and g_i18n:getText("CONFIG_AS_STANDARD")
        or string.format("%+d %%", offset)
end

function Suite.buildConfigurationName(moduleId, offset)
    return string.format("%s: %s [%s]", Suite.getModuleLabel(moduleId), Suite.getOffsetText(offset), Suite.getStatusText(offset))
end

function Suite.getStoreItemPrice(storeItem, xmlFile)
    local price = 0

    if storeItem ~= nil then
        price = tonumber(storeItem.price) or tonumber(storeItem.rawPrice) or tonumber(storeItem.basePrice) or 0
    end

    if price <= 0 and xmlFile ~= nil then
        local rootName = xmlFile:getRootName()
        if rootName == "vehicle" or rootName == "placeable" then
            price = tonumber(xmlFile:getValue(rootName .. ".storeData.price")) or 0
        end
    end

    return math.max(price, 0)
end

function Suite.getPriceScale(offset)
    offset = Suite.clampOffset(offset)
    return math.max(0, 1 + (offset * Suite.range.pricePerPercent))
end

function Suite.getConfigurationPrice(basePrice, offset)
    local price = math.max(tonumber(basePrice) or 0, 0)
    local priceFactor = Suite.getPricePercent() / 100
    return math.floor((price * (Suite.getPriceScale(offset) - 1) * priceFactor) + 0.5)
end

local function getSettingsFilename()
    if getUserProfileAppPath == nil then
        return nil
    end

    local settingsDirectory = getUserProfileAppPath() .. "modSettings"
    if createFolder ~= nil then
        createFolder(settingsDirectory)
    end

    return settingsDirectory .. "/FS25_AdjustSuite.xml"
end

local function getBoolOrDefault(value, defaultValue)
    if value == nil then
        return defaultValue
    end

    return value == true
end

local function getDefaultModuleSettings()
    local settings = {}
    for _, key in ipairs(MODULE_SETTING_KEYS) do
        settings[key] = DEFAULT_MODULE_SETTINGS[key]
    end
    return settings
end

local function copyModuleSettings(source)
    local settings = getDefaultModuleSettings()
    for _, key in ipairs(MODULE_SETTING_KEYS) do
        if source ~= nil and source[key] ~= nil then
            settings[key] = source[key] == true
        end
    end
    return settings
end

function Suite.getIsOffsetAllowed(moduleId, offset)
    if not Suite.getIsModuleEnabled(moduleId) then
        return Suite.clampOffset(offset) == 0
    end

    local settings = Suite.selectionSettings[moduleId] or getDefaultModuleSettings()
    local tier = Suite.getStatusTier(offset)

    if tier == "BASE" then
        return true
    elseif tier == "REAL" then
        return settings.real == true
    elseif tier == "UNREAL" then
        return settings.unreal == true
    end

    return settings.extreme == true
end

local function applyModuleSettings(moduleId, values)
    local settings = copyModuleSettings(values)
    Suite.selectionSettings[moduleId] = settings

    if Suite.refreshStoreConfigurations ~= nil then
        local ok, message = pcall(Suite.refreshStoreConfigurations, moduleId)
        if not ok then
            print(string.format("Warning: %s - could not refresh store configurations: %s", moduleId, tostring(message)))
        end
    end
end

local function applyPricePercent(value, refreshStore)
    Suite.pricePercent = normalizePricePercent(value)
    if refreshStore and Suite.refreshStoreConfigurations ~= nil then
        for _, moduleId in ipairs(Suite.moduleIds) do
            Suite.refreshStoreConfigurations(moduleId)
        end
    end
end

local function boolToString(value)
    return value == true and "true" or "false"
end

local function writeSettingsTemplate(filename, settingsByModule, showHelpMenu, pricePercent)
    if io == nil or io.open == nil then
        return false
    end

    local file = io.open(filename, "w")
    if file == nil then
        return false
    end

    pricePercent = normalizePricePercent(pricePercent)

    file:write('<?xml version="1.0" encoding="utf-8" standalone="no"?>\n')
    file:write("<adjustSuiteSettings>\n")
    file:write("    <settings>\n")
    file:write(string.format("        <helpmenu show=\"%s\"/>\n", boolToString(showHelpMenu ~= false)))
    file:write(string.format("        <price percent=\"%s\"/>\n", tostring(pricePercent)))
    file:write("    </settings>\n")
    file:write("    <modules>\n")

    for _, moduleId in ipairs(Suite.moduleIds) do
        local settings = settingsByModule[moduleId] or getDefaultModuleSettings()
        file:write(string.format(
            "        <%s module=\"%s\" real=\"%s\" unreal=\"%s\" extreme=\"%s\"/>\n",
            moduleId,
            boolToString(settings.module ~= false),
            boolToString(settings.real == true),
            boolToString(settings.unreal == true),
            boolToString(settings.extreme == true)
        ))
    end

    file:write("    </modules>\n")
    file:write("</adjustSuiteSettings>\n")
    file:close()
    return true
end

local function writeSettingsXml(filename, settingsByModule, showHelpMenu, pricePercent)
    pricePercent = normalizePricePercent(pricePercent)
    if writeSettingsTemplate(filename, settingsByModule, showHelpMenu, pricePercent) then
        return
    end

    local xmlFile = createXMLFile("AdjustSuiteSelectionSettingsWrite", filename, SETTINGS_ROOT)
    if xmlFile == nil or xmlFile == 0 then
        print("Warning: AdjustSuite - could not save selection settings")
        return
    end

    setXMLBool(xmlFile, SETTINGS_HELP_MENU_KEY .. "#show", showHelpMenu ~= false)
    setXMLFloat(xmlFile, SETTINGS_PRICE_KEY .. "#percent", pricePercent)

    for _, moduleId in ipairs(Suite.moduleIds) do
        local settings = settingsByModule[moduleId] or getDefaultModuleSettings()
        local key = SETTINGS_MODULES_KEY .. "." .. moduleId
        for _, settingKey in ipairs(MODULE_SETTING_KEYS) do
            setXMLBool(xmlFile, key .. "#" .. settingKey, settings[settingKey] == true)
        end
    end

    saveXMLFile(xmlFile)
    delete(xmlFile)
end

function Suite.loadSelectionSettings()
    local filename = getSettingsFilename()
    if filename == nil then
        return
    end

    local settingsFileExists = fileExists(filename)
    local xmlFile = settingsFileExists and loadXMLFile("AdjustSuiteSelectionSettings", filename) or nil

    if settingsFileExists and (xmlFile == nil or xmlFile == 0) then
        print("Warning: AdjustSuite - could not load or create selection settings")
        return
    end

    local settingsByModule = {}
    local settingsFileChanged = false
    local showHelpMenu = true
    local pricePercent = 100
    if settingsFileExists then
        local configuredShowHelpMenu = getXMLBool(xmlFile, SETTINGS_HELP_MENU_KEY .. "#show")
        if configuredShowHelpMenu == nil then
            setXMLBool(xmlFile, SETTINGS_HELP_MENU_KEY .. "#show", showHelpMenu)
            settingsFileChanged = true
        else
            showHelpMenu = configuredShowHelpMenu == true
        end

        local configuredPricePercent = getXMLFloat(xmlFile, SETTINGS_PRICE_KEY .. "#percent")
        if configuredPricePercent == nil then
            setXMLFloat(xmlFile, SETTINGS_PRICE_KEY .. "#percent", pricePercent)
            settingsFileChanged = true
        else
            pricePercent = normalizePricePercent(configuredPricePercent)
        end
    end
    Suite.showHelpMenu = showHelpMenu
    applyPricePercent(pricePercent, false)

    for _, moduleId in ipairs(Suite.moduleIds) do
        local settings = getDefaultModuleSettings()
        local key = SETTINGS_MODULES_KEY .. "." .. moduleId

        if settingsFileExists then
            for _, settingKey in ipairs(MODULE_SETTING_KEYS) do
                local configuredValue = getXMLBool(xmlFile, key .. "#" .. settingKey)
                if configuredValue == nil then
                    setXMLBool(xmlFile, key .. "#" .. settingKey, settings[settingKey])
                    settingsFileChanged = true
                else
                    settings[settingKey] = configuredValue == true
                end
            end
        end

        settingsByModule[moduleId] = settings
        applyModuleSettings(moduleId, settings)
    end

    if xmlFile ~= nil and xmlFile ~= 0 then
        if settingsFileChanged then
            saveXMLFile(xmlFile)
        end
        delete(xmlFile)
    end

    if not settingsFileExists then
        writeSettingsXml(filename, settingsByModule, showHelpMenu, pricePercent)
    end
end

AdjustSuiteSettingsEvent = {}
local AdjustSuiteSettingsEvent_mt = Class(AdjustSuiteSettingsEvent, Event)
InitEventClass(AdjustSuiteSettingsEvent, "AdjustSuiteSettingsEvent")

function AdjustSuiteSettingsEvent.emptyNew()
    return Event.new(AdjustSuiteSettingsEvent_mt)
end

function AdjustSuiteSettingsEvent.new(settingsByModule, showHelpMenu, pricePercent)
    local self = AdjustSuiteSettingsEvent.emptyNew()
    self.settingsByModule = {}
    self.showHelpMenu = showHelpMenu ~= false
    self.pricePercent = normalizePricePercent(pricePercent)

    for _, moduleId in ipairs(Suite.moduleIds) do
        self.settingsByModule[moduleId] = copyModuleSettings(settingsByModule[moduleId])
    end

    return self
end

function AdjustSuiteSettingsEvent:readStream(streamId, connection)
    self.settingsByModule = {}
    self.showHelpMenu = streamReadBool(streamId)
    self.pricePercent = normalizePricePercent(streamReadFloat32(streamId))

    for _, moduleId in ipairs(Suite.moduleIds) do
        local settings = {}
        for _, key in ipairs(MODULE_SETTING_KEYS) do
            settings[key] = streamReadBool(streamId)
        end
        self.settingsByModule[moduleId] = settings
    end

    self:run(connection)
end

function AdjustSuiteSettingsEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.showHelpMenu ~= false)
    streamWriteFloat32(streamId, self.pricePercent)

    for _, moduleId in ipairs(Suite.moduleIds) do
        local settings = self.settingsByModule[moduleId]
        for _, key in ipairs(MODULE_SETTING_KEYS) do
            streamWriteBool(streamId, settings[key] == true)
        end
    end
end

function AdjustSuiteSettingsEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        Suite.showHelpMenu = self.showHelpMenu ~= false
        applyPricePercent(self.pricePercent, false)
        for _, moduleId in ipairs(Suite.moduleIds) do
            applyModuleSettings(moduleId, self.settingsByModule[moduleId])
        end
    end
end

local function sendSelectionSettings(baseMission, connection, x, y, z, viewDistanceCoeff)
    if g_server ~= nil and connection ~= nil then
        connection:sendEvent(AdjustSuiteSettingsEvent.new(Suite.selectionSettings, Suite.showHelpMenu, Suite.pricePercent))
    end
end

FSBaseMission.onConnectionFinishedLoading = Utils.prependedFunction(FSBaseMission.onConnectionFinishedLoading, sendSelectionSettings)
Suite.loadSelectionSettings()
