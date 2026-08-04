AdjustSuite = AdjustSuite or {}

local Suite = AdjustSuite
local MODULE_SETTING_KEYS = {"module", "real", "unreal", "extreme"}

Suite.moduleIds = Suite.moduleIds or {"AFV", "AMP", "AWS", "AWW", "APW", "ADS", "ABP", "ADR"}
Suite.range = Suite.range or {
    minFactor = 0.20,
    realOffset = 20,
    unrealOffset = 200,
    minAbsoluteSpeed = 1,
    defaultIndex = 8,
    pricePerPercent = 0.004
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
Suite.pricePercent = math.max(tonumber(Suite.pricePercent) or 100, 0)

local SETTINGS_ROOT = "adjustSuiteSettings"
local SETTINGS_HELP_MENU_KEY = SETTINGS_ROOT .. ".settings.helpmenu"
local SETTINGS_PRICE_KEY = SETTINGS_ROOT .. ".settings.price"
local SETTINGS_MODULES_KEY = SETTINGS_ROOT .. ".modules"
local DEFAULT_MODULE_SETTINGS = {
    module = true,
    real = true,
    unreal = false,
    extreme = false
}

function Suite.getModuleIdFromConfigurationName(configurationName)
    return string.match(tostring(configurationName or ""), "^(%u+)$")
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

    return getSpec, getSelectedOffset, hasSelectedConfiguration
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
    return string.format("%s: %s [%s]", moduleId, Suite.getOffsetText(offset), Suite.getStatusText(offset))
end

function Suite.getStoreItemPrice(storeItem, xmlFile)
    local price = 0

    if storeItem ~= nil then
        price = tonumber(storeItem.price) or tonumber(storeItem.rawPrice) or tonumber(storeItem.basePrice) or 0
    end

    if price <= 0 and xmlFile ~= nil then
        price = tonumber(xmlFile:getValue("vehicle.storeData.price", 0)) or 0
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
    Suite.pricePercent = math.max(tonumber(value) or 100, 0)
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
    local showHelpMenu = true
    local pricePercent = 100
    if settingsFileExists then
        showHelpMenu = getBoolOrDefault(getXMLBool(xmlFile, SETTINGS_HELP_MENU_KEY .. "#show"), true)
        pricePercent = math.max(tonumber(getXMLFloat(xmlFile, SETTINGS_PRICE_KEY .. "#percent")) or 100, 0)
    end
    Suite.showHelpMenu = showHelpMenu
    applyPricePercent(pricePercent, false)

    for _, moduleId in ipairs(Suite.moduleIds) do
        local settings = getDefaultModuleSettings()
        local key = SETTINGS_MODULES_KEY .. "." .. moduleId

        if settingsFileExists then
            for _, settingKey in ipairs(MODULE_SETTING_KEYS) do
                settings[settingKey] = getBoolOrDefault(getXMLBool(xmlFile, key .. "#" .. settingKey), settings[settingKey])
            end
        end

        settingsByModule[moduleId] = settings
        applyModuleSettings(moduleId, settings)
    end

    if xmlFile ~= nil and xmlFile ~= 0 then
        delete(xmlFile)
    end

    writeSettingsXml(filename, settingsByModule, showHelpMenu, pricePercent)
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
    self.pricePercent = math.max(tonumber(pricePercent) or 100, 0)

    for _, moduleId in ipairs(Suite.moduleIds) do
        self.settingsByModule[moduleId] = copyModuleSettings(settingsByModule[moduleId])
    end

    return self
end

function AdjustSuiteSettingsEvent:readStream(streamId, connection)
    self.settingsByModule = {}
    self.showHelpMenu = streamReadBool(streamId)
    self.pricePercent = math.max(streamReadFloat32(streamId), 0)

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

FSBaseMission.onConnectionFinishedLoading = Utils.appendedFunction(FSBaseMission.onConnectionFinishedLoading, sendSelectionSettings)
Suite.loadSelectionSettings()
