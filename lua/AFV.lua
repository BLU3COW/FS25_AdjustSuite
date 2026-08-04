AFV = AFV or {}

local Suite = AdjustSuite
local clampOffset = Suite.clampOffset
local getFactorFromOffset = Suite.getFactorFromOffset
local getSpec, getSelectedOffset = Suite.createModuleAccessors("AFV")

local IGNORED_FILLTYPE_NAMES = AFV.ignoredFillTypeNames

local function roundCapacityUp(capacity)
    return math.max(math.ceil((tonumber(capacity) or 0) - 0.000001), 1)
end

local function formatCapacity(capacity, displayUnit)
    capacity = tonumber(capacity)
    if capacity == nil or capacity <= 0 then
        return nil
    end

    if displayUnit == "L" then
        local value = nil
        if g_i18n ~= nil and g_i18n.formatNumber ~= nil then
            value = g_i18n:formatNumber(capacity, 0, true)
        else
            value = string.format("%.0f", capacity)
        end

        return string.format("%s %s", value, g_i18n:getText("CONFIG_AS_L"))
    end

    local cubicMetres = capacity / 1000
    local value = nil
    if g_i18n ~= nil and g_i18n.formatNumber ~= nil then
        value = g_i18n:formatNumber(cubicMetres, 2, true)
    else
        value = string.format("%.2f", cubicMetres)
    end

    return string.format("%s %s", value, g_i18n:getText("CONFIG_AS_M3"))
end

local function getFillUnits(vehicle)
    if vehicle == nil then
        return nil
    end

    if vehicle.spec_fillUnit ~= nil and vehicle.spec_fillUnit.fillUnits ~= nil then
        return vehicle.spec_fillUnit.fillUnits
    end

    if vehicle.fillUnits ~= nil then
        return vehicle.fillUnits
    end

    return nil
end

local function vehicleIsExcluded(vehicle)
    if vehicle == nil then
        return true
    end

    if vehicle.xmlFile ~= nil and Suite.afvXmlIsExcluded ~= nil then
        return Suite.afvXmlIsExcluded(vehicle.xmlFile)
    end

    return vehicle.spec_baler ~= nil
        or vehicle.spec_baleLoader ~= nil
        or vehicle.spec_autoLoaderBales ~= nil
        or vehicle.spec_baleWrapper ~= nil
        or vehicle.spec_pallet ~= nil
        or vehicle.spec_bigBag ~= nil
        or vehicle.spec_multipleItemPurchase ~= nil
end

local function getFillTypeName(fillTypeIndex)
    if fillTypeIndex == nil then
        return nil
    end

    if g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeNameByIndex ~= nil then
        local ok, name = pcall(g_fillTypeManager.getFillTypeNameByIndex, g_fillTypeManager, fillTypeIndex)
        if ok then
            return name
        end
    end

    if FillType ~= nil then
        for name, index in pairs(FillType) do
            if index == fillTypeIndex then
                return name
            end
        end
    end

    return nil
end

local function fillTypeIsIgnored(fillTypeIndex)
    local name = getFillTypeName(fillTypeIndex)
    if name == nil then
        return false
    end

    return IGNORED_FILLTYPE_NAMES[string.upper(tostring(name))] == true
end

local function fillUnitHasUsableFillTypes(fillUnit)
    local foundUsable = false
    local foundOnlyIgnored = false

    local candidates = fillUnit.fillTypes or fillUnit.supportedFillTypes or fillUnit.supportedFillTypeIndices or fillUnit.fillTypeCategories

    if type(candidates) == "table" then
        for key, value in pairs(candidates) do
            local fillTypeIndex = nil

            if type(key) == "number" and (value == true or value == 1) then
                fillTypeIndex = key
            elseif type(value) == "number" then
                fillTypeIndex = value
            elseif type(value) == "table" and value.index ~= nil then
                fillTypeIndex = value.index
            end

            if fillTypeIndex ~= nil then
                if fillTypeIsIgnored(fillTypeIndex) then
                    foundOnlyIgnored = true
                else
                    foundUsable = true
                end
            end
        end
    end

    if foundUsable then
        return true
    end

    if foundOnlyIgnored then
        return false
    end

    return true
end

local function getBaseCapacity(fillUnit)
    if fillUnit == nil then
        return nil
    end

    local baseCapacity = tonumber(fillUnit.AFVBaseCapacity) or tonumber(fillUnit.defaultCapacity) or tonumber(fillUnit.capacity)
    if baseCapacity ~= nil and baseCapacity > 0 and baseCapacity < math.huge then
        fillUnit.AFVBaseCapacity = baseCapacity
        return baseCapacity
    end

    return nil
end

local function getFillUnitXMLKey(vehicle, fillUnitIndex)
    if vehicle == nil or vehicle.xmlFile == nil or tonumber(fillUnitIndex) == nil then
        return nil
    end

    local configurationId = vehicle.configurations ~= nil and tonumber(vehicle.configurations.fillUnit) or 1
    configurationId = math.max(math.floor((configurationId or 1) + 0.5), 1)
    local configurationKey = string.format(
        "vehicle.fillUnit.fillUnitConfigurations.fillUnitConfiguration(%d)",
        configurationId - 1
    )
    local fillUnitKey = string.format("%s.fillUnits.fillUnit(%d)", configurationKey, fillUnitIndex - 1)

    if not vehicle.xmlFile:hasProperty(fillUnitKey) and configurationId == 1 then
        fillUnitKey = string.format("vehicle.fillUnit.fillUnits.fillUnit(%d)", fillUnitIndex - 1)
    end

    return vehicle.xmlFile:hasProperty(fillUnitKey) and fillUnitKey or nil
end

local function fillUnitIsTechnicalHidden(vehicle, fillUnitIndex, fillUnit)
    if fillUnit == nil or fillUnit.showOnHud ~= false then
        return false
    end

    local fillUnitKey = getFillUnitXMLKey(vehicle, fillUnitIndex)
    return fillUnitKey ~= nil and vehicle.xmlFile:getValue(fillUnitKey .. "#showInShop", true) == false
end

local function getFillUnitDisplayUnit(vehicle, fillUnitIndex, capacity)
    local fillUnitKey = getFillUnitXMLKey(vehicle, fillUnitIndex)
    if fillUnitKey ~= nil then
        local categories = string.upper(tostring(vehicle.xmlFile:getValue(fillUnitKey .. "#fillTypeCategories", "")))
        if string.find(categories, "BULK", 1, true) ~= nil then
            return "M3"
        end
    end

    return capacity >= 10000 and "M3" or "L"
end

local function clampFillLevel(vehicle, fillUnitIndex, fillUnit, capacity)
    local fillLevel = tonumber(fillUnit.fillLevel)
    if fillLevel == nil or fillLevel <= capacity then
        return
    end

    local applied = false
    if vehicle.addFillUnitFillLevel ~= nil and fillUnit.fillType ~= nil then
        local farmId = nil
        if vehicle.getOwnerFarmId ~= nil then
            farmId = vehicle:getOwnerFarmId()
        end

        local toolType = nil
        if ToolType ~= nil then
            toolType = ToolType.UNDEFINED
        end

        applied = pcall(vehicle.addFillUnitFillLevel, vehicle, farmId, fillUnitIndex, capacity - fillLevel, fillUnit.fillType, toolType, nil)
    end

    if not applied then
        fillUnit.fillLevel = capacity
    end

    if tonumber(fillUnit.fillLevelSent) ~= nil and fillUnit.fillLevelSent > capacity then
        fillUnit.fillLevelSent = capacity
    end

    if tonumber(fillUnit.fillLevelToDisplay) ~= nil and fillUnit.fillLevelToDisplay > capacity then
        if vehicle.setFillUnitFillLevelToDisplay ~= nil then
            pcall(vehicle.setFillUnitFillLevelToDisplay, vehicle, fillUnitIndex, capacity, fillUnit.fillLevelToDisplayIsPersistent)
        else
            fillUnit.fillLevelToDisplay = capacity
        end
    end
end

local function applyFillUnitCapacity(vehicle, fillUnitIndex, fillUnit, capacity)
    fillUnit.defaultCapacity = capacity

    local applied = false
    if vehicle.setFillUnitCapacity ~= nil then
        applied = pcall(vehicle.setFillUnitCapacity, vehicle, fillUnitIndex, capacity, true)
    end

    if not applied then
        fillUnit.capacity = capacity
    end

    if fillUnit.capacityToDisplay ~= nil then
        if vehicle.setFillUnitCapacityToDisplay ~= nil then
            pcall(vehicle.setFillUnitCapacityToDisplay, vehicle, fillUnitIndex, capacity)
        else
            fillUnit.capacityToDisplay = capacity
        end
    end

    clampFillLevel(vehicle, fillUnitIndex, fillUnit, capacity)
end

local function collectFillUnits(vehicle, force)
    local spec = getSpec(vehicle)

    if force == true then
        spec.unitsCollected = false
        spec.units = {}
    elseif spec.unitsCollected == true then
        return #spec.units > 0
    end

    spec.unitsCollected = true
    spec.units = {}

    if vehicleIsExcluded(vehicle) then
        return false
    end

    local fillUnits = getFillUnits(vehicle)
    if fillUnits == nil then
        return false
    end

    for index, fillUnit in pairs(fillUnits) do
        local capacity = getBaseCapacity(fillUnit)

        if capacity ~= nil
            and capacity > 0
            and capacity < math.huge
            and fillUnitHasUsableFillTypes(fillUnit)
            and not fillUnitIsTechnicalHidden(vehicle, index, fillUnit) then
            table.insert(spec.units, {
                index = index,
                fillUnit = fillUnit,
                baseCapacity = capacity,
                displayUnit = getFillUnitDisplayUnit(vehicle, index, capacity)
            })
        end
    end

    table.sort(spec.units, function(a, b)
        return a.index < b.index
    end)

    return #spec.units > 0
end

local function applyOffset(vehicle)
    local spec = getSpec(vehicle)

    if not collectFillUnits(vehicle, false) then
        return false
    end

    local offset = Utils.getNoNil(tonumber(spec.currentOffset), getSelectedOffset(vehicle))
    local factor = getFactorFromOffset(offset)

    spec.currentOffset = clampOffset(offset)

    for _, entry in ipairs(spec.units) do
        local fillUnit = entry.fillUnit
        local newCapacity = roundCapacityUp(entry.baseCapacity * factor)

        entry.adjustedCapacity = newCapacity
        applyFillUnitCapacity(vehicle, entry.index, fillUnit, newCapacity)
    end

    return true
end

function AFV.prepareFillVolumeOnLoad(vehicle, savegame)
    if vehicle == nil
        or vehicle.configurations == nil
        or vehicle.configurations.AFV == nil then
        return
    end

    collectFillUnits(vehicle, true)
    applyOffset(vehicle)
end

function AFV.prerequisitesPresent(specializations)
    return true
end

function AFV.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", AFV)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", AFV)
end

function AFV:onPostLoad(savegame)
    collectFillUnits(self, true)
    applyOffset(self)
end

function AFV:onDraw(isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if not Suite.canShowHelpText(self, isActiveForInputIgnoreSelection) then
        return
    end

    local spec = getSpec(self)
    if spec.units == nil or #spec.units == 0 then
        return
    end

    local offset = Utils.getNoNil(tonumber(spec.currentOffset), getSelectedOffset(self))
    local helpText = string.format("AFV: %s [%s]", Suite.getOffsetText(offset), Suite.getStatusText(offset))

    for _, entry in ipairs(spec.units or {}) do
        local capacityText = formatCapacity(entry.adjustedCapacity or entry.fillUnit.capacity, entry.displayUnit)
        if capacityText ~= nil then
            helpText = string.format("%s - %s", helpText, capacityText)
        end
    end

    Suite.addHelpText(helpText)
end

if FillVolume ~= nil
    and FillVolume.onLoad ~= nil
    and AFV.fillVolumeOnLoadHookInstalled ~= true then
    AFV.fillVolumeOnLoadHookInstalled = true
    FillVolume.onLoad = Utils.prependedFunction(FillVolume.onLoad, AFV.prepareFillVolumeOnLoad)
end
