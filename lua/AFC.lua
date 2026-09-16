local safeCall = pcall
AdjustSuiteAFC = AdjustSuiteAFC or {}
local AFC = AdjustSuiteAFC

local Suite = AdjustSuite
local getFillUnits = Suite.getFillUnits
local getFillTypeName = Suite.getFillTypeName
local getFillUnitXMLKey = Suite.getFillUnitXMLKey
local captureSavedFillLevels = Suite.captureSavedFillLevels
local clampOffset = Suite.clampOffset
local getFactorFromOffset = Suite.getFactorFromOffset
local getSpec, getSelectedOffset = Suite.createModuleAccessors("AFC")

local function getFillTypeTitle(fillTypeIndex)
    if fillTypeIndex ~= nil and g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeByIndex ~= nil then
        local ok, fillType = safeCall(g_fillTypeManager.getFillTypeByIndex, g_fillTypeManager, fillTypeIndex)
        if ok and fillType ~= nil and fillType.title ~= nil then
            return fillType.title
        end
    end

    return getFillTypeName(fillTypeIndex)
end

local fillTypeIsAir = Suite.fillTypeIsAir

local function resolveUnitText(value)
    value = tostring(value or "")
    if value == "" then
        return nil
    end

    local l10nKey = string.match(value, "^%$l10n_(.+)$")
    if l10nKey ~= nil and g_i18n ~= nil then
        return g_i18n:getText(l10nKey)
    end

    return value
end

local function getUnitText(vehicle, fillUnitIndex, fillUnit)
    local unitText = resolveUnitText(fillUnit.unitTextOverride or fillUnit.customUnitText or fillUnit.unitText)
    if unitText ~= nil then
        return unitText
    end

    local fillUnitKey = getFillUnitXMLKey(vehicle, fillUnitIndex)
    if fillUnitKey ~= nil then
        unitText = resolveUnitText(vehicle.xmlFile:getValue(fillUnitKey .. "#unitTextOverride"))
    end

    return unitText or g_i18n:getText("CONFIG_AS_L")
end

local function formatCapacity(capacity, unitText)
    capacity = tonumber(capacity)
    if capacity == nil or capacity <= 0 then
        return nil
    end

    local nearestInteger = math.floor(capacity + 0.5)
    local decimals = math.abs(capacity - nearestInteger) > 0.001 and 2 or 0
    local value = g_i18n ~= nil and g_i18n.formatNumber ~= nil and g_i18n:formatNumber(capacity, decimals, true)
        or string.format(decimals == 0 and "%.0f" or "%.2f", capacity)
    return string.format("%s %s", value, unitText)
end

local function clampFillLevel(vehicle, fillUnitIndex, fillUnit, capacity, fillType)
    local fillLevel = tonumber(fillUnit.fillLevel)
    if fillLevel == nil or fillLevel <= capacity then
        return
    end

    local applied = false
    if vehicle.addFillUnitFillLevel ~= nil and fillType ~= nil then
        local farmId = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or nil
        local toolType = ToolType ~= nil and ToolType.UNDEFINED or nil
        applied = safeCall(
            vehicle.addFillUnitFillLevel,
            vehicle,
            farmId,
            fillUnitIndex,
            capacity - fillLevel,
            fillType,
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

local function applyCapacity(vehicle, entry, capacity)
    local fillUnit = entry.fillUnit
    local applied = false
    if vehicle.setFillUnitCapacity ~= nil then
        applied = safeCall(vehicle.setFillUnitCapacity, vehicle, entry.index, capacity, true)
    end
    if not applied then
        fillUnit.capacity = capacity
    end

    if fillUnit.capacityToDisplay ~= nil then
        if vehicle.setFillUnitCapacityToDisplay ~= nil then
            safeCall(vehicle.setFillUnitCapacityToDisplay, vehicle, entry.index, capacity)
        else
            fillUnit.capacityToDisplay = capacity
        end
    end

    clampFillLevel(vehicle, entry.index, fillUnit, capacity, entry.fillType)
end

local function collectOperatingUnits(vehicle, force)
    local spec = getSpec(vehicle)
    if force == true then
        spec.unitsCollected = false
        spec.units = {}
    elseif spec.unitsCollected == true then
        return #spec.units > 0
    end

    spec.unitsCollected = true
    spec.units = {}

    local consumers = vehicle.spec_motorized ~= nil and vehicle.spec_motorized.consumers or nil
    local fillUnits = getFillUnits(vehicle)
    if consumers == nil or fillUnits == nil then
        return false
    end

    local unitsByIndex = {}
    for _, consumer in pairs(consumers) do
        local fillUnitIndex = consumer ~= nil and tonumber(consumer.fillUnitIndex) or nil
        local fillType = consumer ~= nil and consumer.fillType or nil
        if fillUnitIndex ~= nil and fillUnitIndex > 0 and not fillTypeIsAir(fillType) then
            fillUnitIndex = math.floor(fillUnitIndex + 0.5)
            local fillUnit = fillUnits[fillUnitIndex]
            local baseCapacity = Suite.getCapacityBase(fillUnit)
            if baseCapacity ~= nil and unitsByIndex[fillUnitIndex] == nil then
                local entry = {
                    index = fillUnitIndex,
                    fillUnit = fillUnit,
                    fillType = fillType,
                    fillTypeTitle = getFillTypeTitle(fillType),
                    baseCapacity = baseCapacity,
                    unitText = getUnitText(vehicle, fillUnitIndex, fillUnit),
                }
                unitsByIndex[fillUnitIndex] = entry
                table.insert(spec.units, entry)
            end
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
        local capacity = entry.adjustedCapacity or entry.fillUnit.capacity
        if savedLevel ~= nil and capacity ~= nil then
            local targetLevel = math.min(savedLevel, capacity)
            local currentLevel = tonumber(entry.fillUnit.fillLevel) or 0
            if targetLevel > currentLevel + 0.001 then
                local delta = targetLevel - currentLevel
                local applied = false
                if vehicle.addFillUnitFillLevel ~= nil and entry.fillType ~= nil then
                    local farmId = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or nil
                    local toolType = ToolType ~= nil and ToolType.UNDEFINED or nil
                    applied = safeCall(
                        vehicle.addFillUnitFillLevel,
                        vehicle,
                        farmId,
                        entry.index,
                        delta,
                        entry.fillType,
                        toolType,
                        nil
                    )
                end
                if not applied then
                    entry.fillUnit.fillLevel = targetLevel
                end
            end
        end
    end
end

local function applyOffset(vehicle)
    local spec = getSpec(vehicle)
    if not collectOperatingUnits(vehicle, false) then
        return false
    end

    local offset = clampOffset(Utils.getNoNil(tonumber(spec.currentOffset), getSelectedOffset(vehicle)))
    local factor = getFactorFromOffset(offset)
    spec.currentOffset = offset
    spec.currentFactor = factor

    for _, entry in ipairs(spec.units) do
        local fillUnit = entry.fillUnit

        if Suite.capacityLooksExternallyOverridden(vehicle, fillUnit, "AFC") then
            entry.adjustedCapacity = tonumber(fillUnit.capacity)
        else
            local targetCapacity = offset == 0 and entry.baseCapacity or math.max(entry.baseCapacity * factor, 0.001)
            local currentCapacity = tonumber(fillUnit.capacity)
            entry.adjustedCapacity = targetCapacity
            Suite.setCapacityOffset(vehicle, "AFC", offset)

            if currentCapacity == nil or math.abs(currentCapacity - targetCapacity) > 0.001 then
                applyCapacity(vehicle, entry, targetCapacity)
            end
        end
    end

    return true
end

function AFC.prerequisitesPresent(specializations)
    return Motorized ~= nil
        and FillUnit ~= nil
        and SpecializationUtil.hasSpecialization(Motorized, specializations)
        and SpecializationUtil.hasSpecialization(FillUnit, specializations)
end

function AFC.initSpecialization()
    Suite.registerOffsetSavegamePaths("AFC")
end

function AFC:onPreLoad(savegame)
    Suite.loadStoredOffsets(self, "AFC", savegame)
    Suite.resolveConfiguration(self, "AFC", self.isServer)
end

function AFC:saveToXMLFile(xmlFile, key, _usedModNames)
    Suite.saveStoredOffsets(self, "AFC", xmlFile, key)
end

function AFC.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onPreLoad", AFC)
    SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", AFC)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", AFC)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", AFC)
end

function AFC:onPostLoad(savegame)
    local spec = getSpec(self)
    captureSavedFillLevels(savegame, spec)
    collectOperatingUnits(self, true)
    applyOffset(self)
    restoreSavedFillLevels(self, spec)
end

function AFC:onDraw(_isActiveForInput, isActiveForInputIgnoreSelection, _isSelected)
    if not Suite.canShowHelpText(self, isActiveForInputIgnoreSelection) then
        return
    end

    local spec = getSpec(self)
    if spec.units == nil or #spec.units == 0 then
        return
    end

    local offset = Utils.getNoNil(tonumber(spec.currentOffset), getSelectedOffset(self))
    local helpText = string.format("AFC: %s [%s]", Suite.getOffsetText(offset), Suite.getStatusText(offset))
    for _, entry in ipairs(spec.units) do
        if string.upper(tostring(getFillTypeName(entry.fillType) or "")) ~= "DEF" then
            local capacityText = formatCapacity(entry.adjustedCapacity or entry.fillUnit.capacity, entry.unitText)
            if capacityText ~= nil then
                if entry.fillTypeTitle ~= nil and entry.fillTypeTitle ~= "" then
                    capacityText = string.format("%s: %s", entry.fillTypeTitle, capacityText)
                end
                helpText = string.format("%s - %s", helpText, capacityText)
            end
        end
    end

    Suite.addHelpText(helpText)
end
