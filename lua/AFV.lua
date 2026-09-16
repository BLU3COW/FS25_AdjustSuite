local safeCall = pcall
AdjustSuiteAFV = AdjustSuiteAFV or {}
local AFV = AdjustSuiteAFV

local Suite = AdjustSuite
local clampOffset = Suite.clampOffset
local getFactorFromOffset = Suite.getFactorFromOffset
local getSpec, getSelectedOffset = Suite.createModuleAccessors("AFV")

AFV.ignoredFillTypeNames = Suite.ignoredFillTypeNames
local getFillUnits = Suite.getFillUnits
local fillTypeIsIgnored = Suite.fillTypeIsIgnored
local getFillUnitXMLKey = Suite.getFillUnitXMLKey
local fillUnitIsTechnicalHidden = Suite.fillUnitIsTechnicalHidden
local captureSavedFillLevels = Suite.captureSavedFillLevels

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

local function fillUnitHasUsableFillTypes(fillUnit)
    local foundUsable = false
    local foundOnlyIgnored = false

    local candidates = fillUnit.fillTypes
        or fillUnit.supportedFillTypes
        or fillUnit.supportedFillTypeIndices
        or fillUnit.fillTypeCategories

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

        applied = safeCall(
            vehicle.addFillUnitFillLevel,
            vehicle,
            farmId,
            fillUnitIndex,
            capacity - fillLevel,
            fillUnit.fillType,
            toolType,
            nil
        )
    end

    if not applied then
        fillUnit.fillLevel = capacity
    end

    if tonumber(fillUnit.fillLevelSent) ~= nil and fillUnit.fillLevelSent > capacity then
        fillUnit.fillLevelSent = capacity
    end

    if tonumber(fillUnit.fillLevelToDisplay) ~= nil and fillUnit.fillLevelToDisplay > capacity then
        if vehicle.setFillUnitFillLevelToDisplay ~= nil then
            safeCall(
                vehicle.setFillUnitFillLevelToDisplay,
                vehicle,
                fillUnitIndex,
                capacity,
                fillUnit.fillLevelToDisplayIsPersistent
            )
        else
            fillUnit.fillLevelToDisplay = capacity
        end
    end
end

local function applyFillUnitCapacity(vehicle, fillUnitIndex, fillUnit, capacity)
    local applied = false
    if vehicle.setFillUnitCapacity ~= nil then
        applied = safeCall(vehicle.setFillUnitCapacity, vehicle, fillUnitIndex, capacity, true)
    end

    if not applied then
        fillUnit.capacity = capacity
    end

    if fillUnit.capacityToDisplay ~= nil then
        if vehicle.setFillUnitCapacityToDisplay ~= nil then
            safeCall(vehicle.setFillUnitCapacityToDisplay, vehicle, fillUnitIndex, capacity)
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

    local operatingIndices = Suite.getOperatingConsumerFillUnitIndices(vehicle)
    for index, fillUnit in pairs(fillUnits) do
        local capacity = Suite.getCapacityBase(fillUnit)

        if
            capacity ~= nil
            and capacity > 0
            and capacity < math.huge
            and (operatingIndices == nil or operatingIndices[index] ~= true)
            and fillUnitHasUsableFillTypes(fillUnit)
            and not fillUnitIsTechnicalHidden(vehicle, index, fillUnit)
        then
            table.insert(spec.units, {
                index = index,
                fillUnit = fillUnit,
                baseCapacity = capacity,
                displayUnit = getFillUnitDisplayUnit(vehicle, index, capacity),
            })
        end
    end

    table.sort(spec.units, function(a, b)
        return a.index < b.index
    end)

    return #spec.units > 0
end

local function restoreSavedFillLevels(vehicle, spec)
    local savedLevels = spec.savedFillLevels
    spec.savedFillLevels = nil
    if savedLevels == nil then
        return
    end

    for _, entry in ipairs(spec.units) do
        local savedLevel = savedLevels[entry.index]
        local fillUnit = entry.fillUnit
        local capacity = entry.adjustedCapacity or fillUnit.capacity
        if savedLevel ~= nil and capacity ~= nil then
            local targetLevel = math.min(savedLevel, capacity)
            local currentLevel = tonumber(fillUnit.fillLevel) or 0
            if targetLevel > currentLevel + 0.001 then
                local delta = targetLevel - currentLevel
                local applied = false
                if vehicle.addFillUnitFillLevel ~= nil and fillUnit.fillType ~= nil then
                    local farmId = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or nil
                    local toolType = ToolType ~= nil and ToolType.UNDEFINED or nil
                    applied = safeCall(
                        vehicle.addFillUnitFillLevel,
                        vehicle,
                        farmId,
                        entry.index,
                        delta,
                        fillUnit.fillType,
                        toolType,
                        nil
                    )
                end
                if not applied then
                    fillUnit.fillLevel = targetLevel
                end
            end
        end
    end
end

local function applyOffset(vehicle)
    local spec = getSpec(vehicle)

    if not collectFillUnits(vehicle, false) then
        return false
    end

    local offset = clampOffset(Utils.getNoNil(tonumber(spec.currentOffset), getSelectedOffset(vehicle)))
    local factor = getFactorFromOffset(offset)
    spec.currentOffset = offset

    for _, entry in ipairs(spec.units) do
        local fillUnit = entry.fillUnit

        if Suite.capacityLooksExternallyOverridden(vehicle, fillUnit, "AFV") then
            entry.adjustedCapacity = tonumber(fillUnit.capacity)
        else
            local targetCapacity = offset == 0 and entry.baseCapacity or roundCapacityUp(entry.baseCapacity * factor)
            local currentCapacity = tonumber(fillUnit.capacity)
            entry.adjustedCapacity = targetCapacity
            Suite.setCapacityOffset(vehicle, "AFV", offset)

            if currentCapacity == nil or math.abs(currentCapacity - targetCapacity) > 0.001 then
                applyFillUnitCapacity(vehicle, entry.index, fillUnit, targetCapacity)
            end
        end
    end

    return true
end

function AFV.prepareFillVolumeOnLoad(vehicle, savegame)
    if vehicle == nil or vehicle.configurations == nil or vehicle.configurations.AFV == nil then
        return
    end

    collectFillUnits(vehicle, true)
    applyOffset(vehicle)
end

function AFV.prerequisitesPresent(specializations)
    return true
end

function AFV.initSpecialization()
    Suite.registerOffsetSavegamePaths("AFV")
end

function AFV:onPreLoad(savegame)
    Suite.loadStoredOffsets(self, "AFV", savegame)
    Suite.resolveConfiguration(self, "AFV", self.isServer)
end

function AFV:saveToXMLFile(xmlFile, key, usedModNames)
    Suite.saveStoredOffsets(self, "AFV", xmlFile, key)
end

function AFV.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onPreLoad", AFV)
    SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", AFV)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", AFV)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", AFV)
end

function AFV:onPostLoad(savegame)
    local spec = getSpec(self)
    captureSavedFillLevels(savegame, spec)
    collectFillUnits(self, true)
    applyOffset(self)
    restoreSavedFillLevels(self, spec)
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

if FillVolume ~= nil and FillVolume.onLoad ~= nil and AFV.fillVolumeOnLoadHookInstalled ~= true then
    AFV.fillVolumeOnLoadHookInstalled = true
    FillVolume.onLoad = Utils.prependedFunction(FillVolume.onLoad, AFV.prepareFillVolumeOnLoad)
end
