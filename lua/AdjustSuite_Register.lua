local Suite = AdjustSuite
local MOD_DIRECTORY = g_currentModDirectory

for _, moduleId in ipairs(Suite.moduleIds) do
    local className = moduleId
    _G[className] = _G[className] or {}
end

AFV.ignoredFillTypeNames = AFV.ignoredFillTypeNames or {
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

local function hasSpecialization(specialization, specializations)
    return specialization ~= nil
        and specializations ~= nil
        and SpecializationUtil.hasSpecialization(specialization, specializations)
end

local function fillTypeTokenIsIgnored(token)
    token = string.upper(tostring(token or ""))
    token = string.gsub(token, "%s", "")
    return AFV.ignoredFillTypeNames[token] == true
end

local function tokenListAllowsUsableFillType(value)
    if value == nil or tostring(value) == "" then
        return true
    end

    local foundToken = false
    for token in string.gmatch(tostring(value), "[^%s,;|]+") do
        foundToken = true
        if not fillTypeTokenIsIgnored(token) then
            return true
        end
    end

    return not foundToken
end

local function xmlFillUnitIsUsable(xmlFile, fillUnitKey)
    local capacity = tonumber(xmlFile:getValue(fillUnitKey .. "#capacity", 0))
    if capacity == nil or capacity <= 0 or capacity >= math.huge then
        return false
    end

    local fillTypes = xmlFile:getValue(fillUnitKey .. "#fillTypes")
    local fillTypeCategories = xmlFile:getValue(fillUnitKey .. "#fillTypeCategories")
    return tokenListAllowsUsableFillType(fillTypes) and tokenListAllowsUsableFillType(fillTypeCategories)
end

local function xmlFillUnitIsTechnicalHidden(xmlFile, fillUnitKey)
    return xmlFile:getValue(fillUnitKey .. "#showInShop", true) == false
        and xmlFile:getValue(fillUnitKey .. "#showOnHud", true) == false
end

local function getFillUnitConfigurationContext(xmlFile, configurationId)
    configurationId = math.max(math.floor((tonumber(configurationId) or 1) + 0.5), 1)
    local configurationKey = string.format(
        "vehicle.fillUnit.fillUnitConfigurations.fillUnitConfiguration(%d)",
        configurationId - 1
    )

    if not xmlFile:hasProperty(configurationKey) then
        if configurationId ~= 1 then
            return nil
        end

        configurationKey = "vehicle.fillUnit.fillUnits"
        if not xmlFile:hasProperty(configurationKey) then
            return nil
        end
    end

    local fillUnitIndex = 0

    while true do
        local fillUnitKey = string.format("%s.fillUnits.fillUnit(%d)", configurationKey, fillUnitIndex)
        if configurationKey == "vehicle.fillUnit.fillUnits" then
            fillUnitKey = string.format("%s.fillUnit(%d)", configurationKey, fillUnitIndex)
        end

        if not xmlFile:hasProperty(fillUnitKey) then
            break
        end

        if xmlFillUnitIsUsable(xmlFile, fillUnitKey) and not xmlFillUnitIsTechnicalHidden(xmlFile, fillUnitKey) then
            return {hasUsable = true}
        end

        fillUnitIndex = fillUnitIndex + 1
    end

    return {hasUsable = false}
end

local function getFillUnitConfigurationContexts(xmlFile)
    if xmlFile == nil or not xmlFile:hasProperty("vehicle.fillUnit") then
        return nil, false
    end

    local contexts = {}
    local hasUsable = false
    local configurationId = 1

    while true do
        local context = getFillUnitConfigurationContext(xmlFile, configurationId)
        if context == nil then
            break
        end

        contexts[configurationId] = context
        hasUsable = hasUsable or context.hasUsable
        configurationId = configurationId + 1
    end

    return next(contexts) ~= nil and contexts or nil, hasUsable
end

local function getVehicleTypeConfigurationContexts(xmlFile, customEnvironment, requiredSpecialization)
    local configurationsKey = "vehicle.vehicleTypeConfigurations"
    if xmlFile == nil or not xmlFile:hasProperty(configurationsKey) then
        return nil, false
    end

    local contexts = {}
    local hasUsable = false
    local configurationIndex = 0
    while true do
        local key = string.format("%s.vehicleTypeConfiguration(%d)", configurationsKey, configurationIndex)
        if not xmlFile:hasProperty(key) then
            break
        end

        local vehicleTypeName = xmlFile:getValue(key .. "#vehicleType")
        local vehicleType = vehicleTypeName ~= nil
            and g_vehicleTypeManager:getTypeByName(vehicleTypeName, customEnvironment)
            or nil
        local isUsable = vehicleType ~= nil
            and hasSpecialization(requiredSpecialization, vehicleType.specializations)
        contexts[configurationIndex + 1] = {hasUsable = isUsable}
        hasUsable = hasUsable or isUsable
        configurationIndex = configurationIndex + 1
    end

    return next(contexts) ~= nil and contexts or nil, hasUsable
end

local function storeCategoryIsExcluded(categoryNames)
    for categoryName in string.gmatch(string.lower(tostring(categoryNames or "")), "[^%s,;|]+") do
        if categoryName == "bales"
            or categoryName == "bigbags"
            or categoryName == "bigbagpallets"
            or string.find(categoryName, "bale", 1, true) == 1
            or string.find(categoryName, "pallet", 1, true) ~= nil then
            return true
        end
    end

    return false
end

local function afvXmlIsExcluded(xmlFile)
    if xmlFile == nil then
        return true
    end

    local vehicleTypeName = string.lower(tostring(xmlFile:getValue("vehicle#type", "")))
    if vehicleTypeName == "pallet" or vehicleTypeName == "bigbag" or vehicleTypeName == "multipleitempurchase" then
        return true
    end

    if xmlFile:hasProperty("vehicle.baler")
        or xmlFile:hasProperty("vehicle.baleLoader")
        or xmlFile:hasProperty("vehicle.autoLoaderBales")
        or xmlFile:hasProperty("vehicle.baleWrapper")
        or xmlFile:hasProperty("vehicle.bigBag")
        or xmlFile:hasProperty("vehicle.multipleItemPurchase") then
        return true
    end

    return storeCategoryIsExcluded(xmlFile:getValue("vehicle.storeData.category"))
end

Suite.afvXmlIsExcluded = afvXmlIsExcluded

local function isCarFillableVehicleType(vehicleTypeName)
    vehicleTypeName = string.lower(tostring(vehicleTypeName or ""))
    return vehicleTypeName == "carfillable" or string.match(vehicleTypeName, "%.carfillable$") ~= nil
end

local function hasMotorPower(configurations, storeItem, xmlFile)
    local motorItems = configurations ~= nil and configurations["motor"] or nil

    if motorItems ~= nil then
        for _, motorItem in ipairs(motorItems) do
            local power = tonumber(motorItem.power)
            if power ~= nil and power > 0 then
                return true
            end
        end
    end

    local storePower = storeItem ~= nil and storeItem.specs ~= nil and tonumber(storeItem.specs.power) or nil
    if storePower ~= nil and storePower > 0 then
        return true
    end

    local xmlPower = xmlFile ~= nil and tonumber(xmlFile:getValue("vehicle.storeData.specs.power", 0)) or nil
    return xmlPower ~= nil and xmlPower > 0
end

local function hasWorkAreas(xmlFile)
    return xmlFile:hasProperty("vehicle.workAreas") or xmlFile:hasProperty("vehicle.workAreas.workArea(0)")
end

local function hasAlternativeWorkWidth(xmlFile)
    return xmlFile:hasProperty("vehicle.leveler.levelerNode(0)")
        or xmlFile:hasProperty("vehicle.bunkerSiloCompacter")
end

local function getStoreWorkingWidth(xmlFile, storeItem)
    local width = storeItem ~= nil and storeItem.specs ~= nil and tonumber(storeItem.specs.workingWidth) or nil
    if width == nil or width <= 0 then
        width = tonumber(xmlFile:getValue("vehicle.storeData.specs.workingWidth"))
    end
    if width == nil or width <= 0 then
        width = tonumber(xmlFile:getValue("vehicle.leveler.levelerNode(0)#width"))
    end
    return width ~= nil and width > 0 and width or nil
end

local pickupWorkAreaFunctions = {
    processBalerArea = true,
    processForageWagonArea = true
}

local function workAreaCollectionHasPickupFunction(xmlFile, collectionKey)
    local index = 0
    while true do
        local workAreaKey = string.format("%s.workArea(%d)", collectionKey, index)
        if not xmlFile:hasProperty(workAreaKey) then
            break
        end

        local functionName = xmlFile:getValue(workAreaKey .. "#functionName")
        if pickupWorkAreaFunctions[functionName] == true then
            return true
        end

        index = index + 1
    end

    return false
end

local function hasPickupWorkArea(xmlFile)
    if xmlFile == nil or not xmlFile:hasProperty("vehicle.pickup") then
        return false
    end

    if workAreaCollectionHasPickupFunction(xmlFile, "vehicle.workAreas") then
        return true
    end

    local configurationIndex = 0
    while true do
        local configurationKey = string.format(
            "vehicle.workAreas.workAreaConfigurations.workAreaConfiguration(%d)",
            configurationIndex
        )
        if not xmlFile:hasProperty(configurationKey) then
            break
        end

        if workAreaCollectionHasPickupFunction(xmlFile, configurationKey) then
            return true
        end

        configurationIndex = configurationIndex + 1
    end

    return false
end

local function hasDischargeNodes(xmlFile)
    if xmlFile == nil or not xmlFile:hasProperty("vehicle.dischargeable") then
        return false
    end

    if xmlFile:hasProperty("vehicle.dischargeable.dischargeNode(0)") then
        return true
    end

    local configurationIndex = 0
    while true do
        local configurationKey = string.format(
            "vehicle.dischargeable.dischargeableConfigurations.dischargeableConfiguration(%d)",
            configurationIndex
        )
        if not xmlFile:hasProperty(configurationKey) then
            return false
        end
        if xmlFile:hasProperty(configurationKey .. ".dischargeNode(0)") then
            return true
        end
        configurationIndex = configurationIndex + 1
    end
end

local function dischargeableKeyHasUsableNode(xmlFile, dischargeableKey)
    local nodeIndex = 0
    while true do
        local nodeKey = string.format("%s.dischargeNode(%d)", dischargeableKey, nodeIndex)
        if not xmlFile:hasProperty(nodeKey) then
            break
        end

        local emptySpeed = tonumber(xmlFile:getValue(nodeKey .. "#emptySpeed", 0))
        if emptySpeed ~= nil and emptySpeed > 0 then
            return true
        end

        nodeIndex = nodeIndex + 1
    end

    return false
end

local function getDischargeableConfigurationContext(xmlFile, configurationId)
    configurationId = math.max(math.floor((tonumber(configurationId) or 1) + 0.5), 1)
    local configurationKey = string.format(
        "vehicle.dischargeable.dischargeableConfigurations.dischargeableConfiguration(%d)",
        configurationId - 1
    )

    if not xmlFile:hasProperty(configurationKey) then
        if configurationId ~= 1 or not xmlFile:hasProperty("vehicle.dischargeable") then
            return nil
        end
        configurationKey = "vehicle.dischargeable"
    end

    return {hasUsable = dischargeableKeyHasUsableNode(xmlFile, configurationKey)}
end

local function getDischargeableConfigurationContexts(xmlFile)
    if xmlFile == nil or not xmlFile:hasProperty("vehicle.dischargeable") then
        return nil, false
    end

    local contexts = {}
    local hasUsable = false
    local configurationId = 1
    while true do
        local context = getDischargeableConfigurationContext(xmlFile, configurationId)
        if context == nil then
            break
        end

        contexts[configurationId] = context
        hasUsable = hasUsable or context.hasUsable
        configurationId = configurationId + 1
    end

    return next(contexts) ~= nil and contexts or nil, hasUsable
end

local function getBasePriceContext(storeItem, xmlFile)
    if storeItem == nil then
        return nil
    end
    return {basePrice = Suite.getStoreItemPrice(storeItem, xmlFile)}
end

local function isRoadVehicleType(vehicleTypeName, vehicleType)
    return not hasSpecialization(Locomotive, vehicleType.specializations)
        and hasSpecialization(Motorized, vehicleType.specializations)
        and hasSpecialization(Drivable, vehicleType.specializations)
        and hasSpecialization(Wheels, vehicleType.specializations)
end

local function getMotorizedStoreContext(xmlFile, configurations, defaultConfigurationIds, customEnvironment, storeItem)
    if not xmlFile:hasProperty("vehicle.motorized") then
        return nil
    end
    return getBasePriceContext(storeItem, xmlFile)
end

local function getRoadModuleDefinition()
    return {
        typeFilter = isRoadVehicleType,
        getStoreContext = getMotorizedStoreContext
    }
end

local definitions = {
    AFV = {
        typeFilter = function(vehicleTypeName, vehicleType)
            return hasSpecialization(FillUnit, vehicleType.specializations)
                or isCarFillableVehicleType(vehicleTypeName)
        end,
        getStoreContext = function(xmlFile, configurations, defaultConfigurationIds, customEnvironment, storeItem)
            local capacityByFillUnit, hasUsable = getFillUnitConfigurationContexts(xmlFile)
            local vehicleTypeContexts, hasUsableVehicleType = getVehicleTypeConfigurationContexts(
                xmlFile,
                customEnvironment,
                FillUnit
            )
            local hasUsableCombination = hasUsable and (vehicleTypeContexts == nil or hasUsableVehicleType)
            if storeItem == nil or afvXmlIsExcluded(xmlFile) or not hasUsableCombination then
                return nil
            end

            return {
                basePrice = Suite.getStoreItemPrice(storeItem, xmlFile),
                capacityByFillUnit = capacityByFillUnit,
                vehicleTypeContexts = vehicleTypeContexts,
                hasUsableConfiguration = hasUsableCombination,
                active = hasUsableCombination
            }
        end,
        rememberStoreContext = function(storeItem, context)
            storeItem.AFVCapacityByFillUnit = context.capacityByFillUnit
            storeItem.AFVVehicleTypeByConfiguration = context.vehicleTypeContexts
            storeItem.AFVHasUsableConfiguration = context.hasUsableConfiguration == true
        end,
        isSelectable = function(baseValue, offset, context)
            return offset == 0 or (context ~= nil and context.active == true)
        end
    },
    AMP = {
        typeFilter = function(vehicleTypeName, vehicleType)
            return not hasSpecialization(Locomotive, vehicleType.specializations)
                and hasSpecialization(Motorized, vehicleType.specializations)
        end,
        getStoreContext = function(xmlFile, configurations, defaultConfigurationIds, customEnvironment, storeItem)
            local isMotorVehicle = storeItem ~= nil
                and (xmlFile:hasProperty("vehicle.motorized") or xmlFile:hasProperty("vehicle.motorized.motorConfigurations"))
            if not isMotorVehicle then
                return nil
            end

            if not hasMotorPower(configurations, storeItem, xmlFile) then
                return nil
            end

            return getBasePriceContext(storeItem, xmlFile)
        end
    },
    AWS = {
        baseValueField = "AWSStandardSpeedLimit",
        typeFilter = function(vehicleTypeName, vehicleType)
            local isMotorized = hasSpecialization(Motorized, vehicleType.specializations)
            local isEnterable = hasSpecialization(Enterable, vehicleType.specializations)
            local isSelfPropelledWorkMachine = (isMotorized or isEnterable)
                and hasSpecialization(WorkArea, vehicleType.specializations)
            return not hasSpecialization(Locomotive, vehicleType.specializations)
                and (not isMotorized or isSelfPropelledWorkMachine)
                and (not isEnterable or isSelfPropelledWorkMachine)
                and vehicleTypeName ~= "trainTimberTrailer"
                and vehicleTypeName ~= "trainTrailer"
                and vehicleTypeName ~= "pallet"
                and vehicleTypeName ~= "horse"
        end,
        getStoreContext = function(xmlFile, configurations, defaultConfigurationIds, customEnvironment, storeItem)
            local isMotorVehicle = xmlFile:hasProperty("vehicle.motorized") or xmlFile:hasProperty("vehicle.enterable")
            local isSelfPropelledWorkMachine = isMotorVehicle and hasWorkAreas(xmlFile)
            local speedLimit = (not isMotorVehicle or isSelfPropelledWorkMachine)
                and tonumber(xmlFile:getValue("vehicle.base.speedLimit#value"))
                or nil
            if storeItem == nil or speedLimit == nil or speedLimit <= 0.5 then
                return nil
            end

            return {
                baseValue = speedLimit,
                basePrice = Suite.getStoreItemPrice(storeItem, xmlFile)
            }
        end,
        isSelectable = function(baseValue, offset)
            return tonumber(baseValue) ~= nil and baseValue > 0.5
        end
    },
    AWW = {
        baseValueField = "AWWStandardWorkingWidth",
        typeFilter = function(vehicleTypeName, vehicleType)
            return not hasSpecialization(Locomotive, vehicleType.specializations)
                and not hasSpecialization(Pickup, vehicleType.specializations)
                and (hasSpecialization(WorkArea, vehicleType.specializations)
                    or hasSpecialization(Leveler, vehicleType.specializations)
                    or hasSpecialization(BunkerSiloCompacter, vehicleType.specializations))
                and vehicleTypeName ~= "trainTimberTrailer"
                and vehicleTypeName ~= "trainTrailer"
                and vehicleTypeName ~= "pallet"
                and vehicleTypeName ~= "horse"
        end,
        getStoreContext = function(xmlFile, configurations, defaultConfigurationIds, customEnvironment, storeItem)
            local workingWidth = getStoreWorkingWidth(xmlFile, storeItem)
            local isEligible = storeItem ~= nil
                and not xmlFile:hasProperty("vehicle.pickup")
                and (hasWorkAreas(xmlFile) or (hasAlternativeWorkWidth(xmlFile) and workingWidth ~= nil))
            if not isEligible then
                return nil
            end

            return {
                baseValue = workingWidth,
                basePrice = Suite.getStoreItemPrice(storeItem, xmlFile)
            }
        end
    },
    APW = {
        typeFilter = function(vehicleTypeName, vehicleType)
            return not hasSpecialization(Locomotive, vehicleType.specializations)
                and hasSpecialization(Pickup, vehicleType.specializations)
                and hasSpecialization(WorkArea, vehicleType.specializations)
        end,
        getStoreContext = function(xmlFile, configurations, defaultConfigurationIds, customEnvironment, storeItem)
            if storeItem == nil or not hasPickupWorkArea(xmlFile) then
                return nil
            end

            return getBasePriceContext(storeItem, xmlFile)
        end
    },
    ADS = getRoadModuleDefinition(),
    ABP = getRoadModuleDefinition(),
    ADR = {
        typeFilter = function(vehicleTypeName, vehicleType)
            return hasSpecialization(Dischargeable, vehicleType.specializations)
        end,
        getStoreContext = function(xmlFile, configurations, defaultConfigurationIds, customEnvironment, storeItem)
            local dischargeByConfiguration, hasUsable = getDischargeableConfigurationContexts(xmlFile)
            local fillUnitByConfiguration = getFillUnitConfigurationContexts(xmlFile)
            if storeItem == nil or afvXmlIsExcluded(xmlFile) or not hasDischargeNodes(xmlFile) or not hasUsable then
                return nil
            end

            return {
                basePrice = Suite.getStoreItemPrice(storeItem, xmlFile),
                dischargeByConfiguration = dischargeByConfiguration,
                fillUnitByConfiguration = fillUnitByConfiguration,
                hasUsableConfiguration = hasUsable,
                active = hasUsable
            }
        end,
        rememberStoreContext = function(storeItem, context)
            storeItem.ADRDischargeByConfiguration = context.dischargeByConfiguration
            storeItem.ADRFillUnitByConfiguration = context.fillUnitByConfiguration
            storeItem.ADRHasUsableConfiguration = context.hasUsableConfiguration == true
        end,
        isSelectable = function(baseValue, offset, context)
            return offset == 0 or (context ~= nil and context.active == true)
        end
    }
}

for _, moduleId in ipairs(Suite.moduleIds) do
    local definition = definitions[moduleId]
    definition.id = moduleId
    definition.configName = moduleId
    definition.titleKey = string.format("CONFIG_%s_TITLE", moduleId)
    definition.specialization = _G[definition.configName]
    definition.specializationFile = string.format("lua/%s.lua", definition.configName)
end

Suite.storeItemsByModule = Suite.storeItemsByModule or {}

local function getVehicleType(xmlFile, customEnvironment)
    local vehicleTypeName = xmlFile:getValue(xmlFile:getRootName() .. "#type")
    if vehicleTypeName == nil then
        return nil
    end

    return g_vehicleTypeManager:getTypeByName(vehicleTypeName, customEnvironment)
end

local function xmlVehicleTypeHasModule(definition, xmlFile, customEnvironment)
    local vehicleTypeName = xmlFile:getValue(xmlFile:getRootName() .. "#type")
    if definition.id == "AFV" then
        return isCarFillableVehicleType(vehicleTypeName)
            or xmlFile:hasProperty("vehicle.fillUnit")
    end

    local vehicleType = getVehicleType(xmlFile, customEnvironment)
    return vehicleType ~= nil and hasSpecialization(definition.specialization, vehicleType.specializations)
end

local function updateConfigurationItems(definition, configItems, context)
    context = context or {}
    local baseValue = context.baseValue
    local basePrice = context.basePrice
    for index, offset in ipairs(Suite.configurationOffsets) do
        local item = configItems[index]
        if item ~= nil then
            item.name = Suite.buildConfigurationName(definition.id, offset)
            item.hasDefaultName = false
            item.isDefault = offset == 0
            item.isSelectable = Suite.getIsOffsetAllowed(definition.id, offset)
                and (definition.isSelectable == nil or definition.isSelectable(baseValue, offset, context))
            item.price = Suite.getConfigurationPrice(basePrice, offset)
        end
    end
end

local function createConfigurationItems(manager, definition, xmlFile, baseDir, customEnvironment, context)
    local configurationDesc = manager:getConfigurations()[definition.configName]
    if configurationDesc == nil then
        return nil
    end

    local items = {}
    for index in ipairs(Suite.configurationOffsets) do
        local configItem = configurationDesc.itemClass.new(definition.configName)
        configItem:setIndex(index)

        local configKey = string.format(configurationDesc.configurationKey .. "(%d)", index - 1)
        configItem:loadFromXML(xmlFile, configurationDesc.configurationsKey, configKey, baseDir, customEnvironment)
        items[index] = configItem
    end

    updateConfigurationItems(definition, items, context)
    return items
end

local function rememberStoreItem(definition, storeItem, context)
    if definition.baseValueField ~= nil then
        storeItem[definition.baseValueField] = context.baseValue
    end
    if definition.rememberStoreContext ~= nil then
        definition.rememberStoreContext(storeItem, context)
    end

    if storeItem.xmlFilename ~= nil then
        local filenames = Suite.storeItemsByModule[definition.id] or {}
        filenames[storeItem.xmlFilename] = true
        Suite.storeItemsByModule[definition.id] = filenames
    end
end

function Suite.refreshStoreConfigurations(moduleId)
    local definition = definitions[moduleId]
    local filenames = Suite.storeItemsByModule[moduleId]
    if definition == nil or filenames == nil or g_storeManager == nil then
        return
    end

    for xmlFilename in pairs(filenames) do
        local storeItem = g_storeManager:getItemByXMLFilename(xmlFilename)
        local configItems = storeItem ~= nil and storeItem.configurations ~= nil and storeItem.configurations[definition.configName] or nil
        if configItems ~= nil then
            local context = {
                baseValue = definition.baseValueField ~= nil and tonumber(storeItem[definition.baseValueField]) or nil,
                basePrice = Suite.getStoreItemPrice(storeItem, nil),
                active = true
            }

            if moduleId == "AFV" then
                context.active = storeItem.AFVHasUsableConfiguration == true
            elseif moduleId == "ADR" then
                context.active = storeItem.ADRHasUsableConfiguration == true
            end

            updateConfigurationItems(definition, configItems, context)
        end
    end
end

local SUITE_CONFIGURATION_NAMES = {}
for _, moduleId in ipairs(Suite.moduleIds) do
    SUITE_CONFIGURATION_NAMES[moduleId] = true
end

local function getConfigurationLayout(screen)
    local layout = screen ~= nil and screen.configurationLayout or nil
    if layout == nil and screen ~= nil and screen.getDescendantByName ~= nil then
        layout = screen:getDescendantByName("configurationLayout")
    end
    return layout
end

local function getConfigurationRow(element, layout)
    local row = element
    while row ~= nil and row.parent ~= nil and row.parent ~= layout do
        row = row.parent
    end
    return row ~= layout and row or nil
end

local function collectSuiteShopOptions(element, options)
    if element == nil then
        return
    end

    for _, value in ipairs(element.texts or {}) do
        local moduleId = string.match(tostring(value), "^(%u+):")
        if moduleId ~= nil and SUITE_CONFIGURATION_NAMES[moduleId] == true then
            options[moduleId] = element
            break
        end
    end

    for _, child in ipairs(element.elements or {}) do
        collectSuiteShopOptions(child, options)
    end
end

local function getConfigurationMatches(source, target, rejectMismatch, ignoredName)
    local matches = 0
    target = target or {}
    for name, index in pairs(source or {}) do
        if name ~= ignoredName and SUITE_CONFIGURATION_NAMES[name] ~= true and target[name] ~= nil then
            if tonumber(target[name]) == tonumber(index) then
                matches = matches + 1
            elseif rejectMismatch then
                return nil
            end
        end
    end
    return matches
end

local function getActiveConfigurationId(screen, storeItem, configurationName)
    local screenConfigurations = screen.configurations or {}
    local configurationId = tonumber(screenConfigurations[configurationName])
    local bestPreviewId, bestPreviewMatches = nil, -1
    local previewIds = {}
    local previewVehicles = {}

    local function addPreviewVehicle(vehicle)
        if vehicle ~= nil and vehicle.configurations ~= nil then
            table.insert(previewVehicles, vehicle)
        end
    end

    addPreviewVehicle(screen.vehicle)
    addPreviewVehicle(screen.previewVehicle)
    for _, vehicle in pairs(screen.previewVehicles or {}) do
        addPreviewVehicle(vehicle)
    end

    for _, vehicle in ipairs(previewVehicles) do
        local previewId = tonumber(vehicle.configurations[configurationName])
        if previewId ~= nil then
            previewIds[previewId] = true
            local matches = getConfigurationMatches(screenConfigurations, vehicle.configurations, false, configurationName)
            if matches > bestPreviewMatches then
                bestPreviewId, bestPreviewMatches = previewId, matches
            end
        end
    end

    local previewCount = 0
    for _ in pairs(previewIds) do
        previewCount = previewCount + 1
    end
    if bestPreviewId ~= nil and (bestPreviewMatches > 0 or previewCount == 1) then
        configurationId = bestPreviewId
    end

    local bestSetId, bestSetMatches = nil, -1
    for _, configurationSet in ipairs(storeItem.configurationSets or {}) do
        local setConfigurations = configurationSet.configurations or {}
        local setId = tonumber(setConfigurations[configurationName])
        local matches = setId ~= nil
            and getConfigurationMatches(setConfigurations, screenConfigurations, true, configurationName)
            or nil
        if matches ~= nil and matches > bestSetMatches then
            bestSetId, bestSetMatches = setId, matches
        end
    end
    if bestSetId ~= nil and bestSetMatches > 0 then
        configurationId = bestSetId
    end

    if configurationId == nil then
        configurationId = storeItem.defaultConfigurationIds ~= nil
            and tonumber(storeItem.defaultConfigurationIds[configurationName])
            or 1
    end
    return configurationId
end

local function getDynamicShopState(screen, moduleId)
    local storeItem = screen ~= nil and screen.storeItem or nil
    if storeItem == nil then
        return nil, nil
    end

    if moduleId == "AFV" then
        local fillUnitContexts = storeItem.AFVCapacityByFillUnit
        if fillUnitContexts == nil then
            return nil, nil
        end

        local fillUnitId = getActiveConfigurationId(screen, storeItem, "fillUnit")
        local fillUnitContext = fillUnitContexts[fillUnitId] or fillUnitContexts[1] or {hasUsable = false}
        local vehicleTypeContexts = storeItem.AFVVehicleTypeByConfiguration
        local vehicleTypeId = nil
        local vehicleTypeContext = nil
        if vehicleTypeContexts ~= nil then
            vehicleTypeId = getActiveConfigurationId(screen, storeItem, "vehicleType")
            vehicleTypeContext = vehicleTypeContexts[vehicleTypeId] or vehicleTypeContexts[1] or {hasUsable = false}
        end

        return fillUnitContext.hasUsable == true
            and (vehicleTypeContext == nil or vehicleTypeContext.hasUsable == true),
            string.format("%s:%s", tostring(fillUnitId), tostring(vehicleTypeId or 0))
    end

    if moduleId == "ADR" then
        local dischargeContexts = storeItem.ADRDischargeByConfiguration
        if dischargeContexts == nil then
            return nil, nil
        end

        local dischargeId = getActiveConfigurationId(screen, storeItem, "dischargeable")
        local dischargeContext = dischargeContexts[dischargeId] or dischargeContexts[1] or {hasUsable = false}
        local fillUnitContexts = storeItem.ADRFillUnitByConfiguration
        local fillUnitId = nil
        local fillUnitContext = nil
        if fillUnitContexts ~= nil then
            fillUnitId = getActiveConfigurationId(screen, storeItem, "fillUnit")
            fillUnitContext = fillUnitContexts[fillUnitId] or fillUnitContexts[1] or {hasUsable = false}
        end

        return dischargeContext.hasUsable == true
            and (fillUnitContext == nil or fillUnitContext.hasUsable == true),
            string.format("%s:%s", tostring(dischargeId), tostring(fillUnitId or 0))
    end

    return nil, nil
end

local function updateShopPrice(screen)
    local economyManager = g_currentMission ~= nil and g_currentMission.economyManager or nil
    if economyManager ~= nil then
        screen.totalPrice = economyManager:getBuyPrice(screen.storeItem, screen.configurations, screen.saleItem)
        screen.initialLeasingCosts = economyManager:getInitialLeasingPrice(screen.totalPrice)
    end
end

local function resetDynamicShopSelection(screen, moduleId, option)
    local configurationName = moduleId
    local defaultIndex = Suite.getDefaultIndex()
    screen.configurations[configurationName] = defaultIndex

    local items = screen.storeItem.configurations ~= nil and screen.storeItem.configurations[configurationName] or nil
    local defaultItem = items ~= nil and items[defaultIndex] or nil
    if defaultItem ~= nil and option.setState ~= nil then
        for state, text in ipairs(option.texts or {}) do
            if text == defaultItem.name then
                option:setState(state, false)
                break
            end
        end
    end
    updateShopPrice(screen)
end

local function refreshDynamicShopOption(screen, moduleId, option)
    local configurationName = moduleId
    local items = screen.storeItem.configurations ~= nil and screen.storeItem.configurations[configurationName] or nil
    local texts, configurationIds = {}, {}
    for index, item in ipairs(items or {}) do
        if item.isSelectable == true then
            table.insert(texts, item.name)
            table.insert(configurationIds, index)
        end
    end

    if #texts == 0 or option.setTexts == nil then
        return
    end

    option:setTexts(texts)
    option.configurationIds = configurationIds
    local selectedIndex = tonumber(screen.configurations[configurationName]) or Suite.getDefaultIndex()
    for state, index in ipairs(configurationIds) do
        if index == selectedIndex and option.setState ~= nil then
            option:setState(state, false)
            break
        end
    end
end

local function normalizeShopOption(option, row)
    if row == nil or row.visible == false then
        return
    end

    if row.disabled == true and row.setDisabled ~= nil then
        row:setDisabled(false)
    end
    if option.disabled == true and option.setDisabled ~= nil then
        option:setDisabled(false)
    end

    local canChangeState = #(option.texts or {}) > 1
    if option.canChangeState ~= canChangeState and option.setCanChangeState ~= nil then
        option:setCanChangeState(canChangeState)
    end
end

local function updateSuiteShopControls(screen, force)
    if screen == nil or screen.storeItem == nil then
        return
    end

    local layout = getConfigurationLayout(screen)
    if layout == nil then
        return
    end

    screen.configurations = screen.configurations or {}
    screen.AdjustSuiteDynamicStates = screen.AdjustSuiteDynamicStates or {}

    local options = {}
    collectSuiteShopOptions(layout, options)
    local layoutChanged = false

    for _, moduleId in ipairs({"AFV", "ADR"}) do
        local shouldShow, stateKey = getDynamicShopState(screen, moduleId)
        local option = options[moduleId]
        local row = getConfigurationRow(option, layout)
        if shouldShow ~= nil and option ~= nil and row ~= nil and row.setVisible ~= nil
            and (force or screen.AdjustSuiteDynamicStates[moduleId] ~= stateKey) then
            if shouldShow then
                refreshDynamicShopOption(screen, moduleId, option)
            else
                local selectedIndex = tonumber(screen.configurations[moduleId])
                    or Suite.getDefaultIndex()
                if selectedIndex ~= Suite.getDefaultIndex() then
                    resetDynamicShopSelection(screen, moduleId, option)
                end
            end

            local visibilityChanged = (row.visible == true) ~= shouldShow
            if force or visibilityChanged then
                row:setVisible(shouldShow)
                layoutChanged = true
            end
            screen.AdjustSuiteDynamicStates[moduleId] = stateKey
        end
    end

    if force or layoutChanged then
        for _, moduleId in ipairs(Suite.moduleIds) do
            local option = options[moduleId]
            if option ~= nil then
                normalizeShopOption(option, getConfigurationRow(option, layout))
            end
        end
    end

    if layoutChanged and layout.invalidateLayout ~= nil then
        layout:invalidateLayout()
    end
end

for _, moduleId in ipairs(Suite.moduleIds) do
    local definition = definitions[moduleId]
    if Suite.getIsModuleEnabled(moduleId)
        and g_specializationManager:getSpecializationByName(definition.configName) == nil then
        g_specializationManager:addSpecialization(definition.configName, definition.configName, Utils.getFilename(definition.specializationFile, MOD_DIRECTORY), nil)
    end
end

if Suite.shopHooksInstalled ~= true and ShopConfigScreen ~= nil then
    Suite.shopHooksInstalled = true
    if ShopConfigScreen.setStoreItem ~= nil then
        ShopConfigScreen.setStoreItem = Utils.appendedFunction(ShopConfigScreen.setStoreItem, function(screen)
            screen.AdjustSuiteDynamicStates = {}
            updateSuiteShopControls(screen, true)
        end)
    end
    if ShopConfigScreen.update ~= nil then
        ShopConfigScreen.update = Utils.appendedFunction(ShopConfigScreen.update, function(screen)
            updateSuiteShopControls(screen, false)
        end)
    end
end

function Suite.registerVehicleTypes(typeManager)
    if typeManager == nil or typeManager.typeName ~= "vehicle" then
        return
    end

    for vehicleTypeName, vehicleType in pairs(typeManager.types) do
        if vehicleType ~= nil then
            for _, moduleId in ipairs(Suite.moduleIds) do
                local definition = definitions[moduleId]
                if Suite.getIsModuleEnabled(moduleId)
                    and not hasSpecialization(definition.specialization, vehicleType.specializations)
                    and definition.typeFilter(vehicleTypeName, vehicleType) then
                    typeManager:addSpecialization(vehicleTypeName, definition.configName)
                end
            end
        end
    end
end

Suite.registerVehicleTypes(g_vehicleTypeManager)
if Suite.typeRegistrationInstalled ~= true then
    Suite.typeRegistrationInstalled = true
    TypeManager.finalizeTypes = Utils.prependedFunction(TypeManager.finalizeTypes, Suite.registerVehicleTypes)
end

local function addSuiteStoreConfigurations(manager, superFunc, xmlFile, key, baseDir, customEnvironment, isMod, storeItem)
    local configurations, defaultConfigurationIds = superFunc(manager, xmlFile, key, baseDir, customEnvironment, isMod, storeItem)
    if key ~= "vehicle" then
        return configurations, defaultConfigurationIds
    end

    for _, moduleId in ipairs(Suite.moduleIds) do
        local definition = definitions[moduleId]
        if Suite.getIsModuleEnabled(moduleId)
            and xmlVehicleTypeHasModule(definition, xmlFile, customEnvironment)
            and (configurations == nil or configurations[definition.configName] == nil) then
            local context = definition.getStoreContext(xmlFile, configurations, defaultConfigurationIds, customEnvironment, storeItem)
            if context ~= nil then
                local items = createConfigurationItems(manager, definition, xmlFile, baseDir, customEnvironment, context)
                if items ~= nil and #items > 0 then
                    configurations = configurations or {}
                    defaultConfigurationIds = defaultConfigurationIds or {}
                    configurations[definition.configName] = items
                    defaultConfigurationIds[definition.configName] = ConfigurationUtil.getDefaultConfigIdFromItems(items)
                    rememberStoreItem(definition, storeItem, context)
                else
                    print(string.format("Error: %s - could not create configuration items", definition.configName))
                end
            end
        end
    end

    return configurations, defaultConfigurationIds
end

for _, moduleId in ipairs(Suite.moduleIds) do
    local definition = definitions[moduleId]
    if Suite.getIsModuleEnabled(moduleId)
        and g_vehicleConfigurationManager.configurations[definition.configName] == nil then
        g_vehicleConfigurationManager:addConfigurationType(
            definition.configName,
            g_i18n:getText(definition.titleKey),
            definition.configName,
            VehicleConfigurationItem
        )
    end
end

ConfigurationUtil.getConfigurationsFromXML = Utils.overwrittenFunction(
    ConfigurationUtil.getConfigurationsFromXML,
    addSuiteStoreConfigurations
)

function Suite:update(dt)
    if self.useMiles ~= g_gameSettings.useMiles then
        self.useMiles = g_gameSettings.useMiles
        self.refreshStoreConfigurations("AWS")
    end
end

if Suite.modEventListenerInstalled ~= true then
    Suite.modEventListenerInstalled = true
    Suite.useMiles = g_gameSettings.useMiles
    addModEventListener(Suite)
end
