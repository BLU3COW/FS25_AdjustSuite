ADR = ADR or {}

local Suite = AdjustSuite
local getSpec, getSelectedOffset, hasSelectedConfiguration = Suite.createModuleAccessors("ADR")

local function getFactor(vehicle)
    local spec = getSpec(vehicle)
    if spec.currentFactor == nil then
        spec.currentOffset = getSelectedOffset(vehicle)
        spec.currentFactor = Suite.getFactorFromOffset(spec.currentOffset)
    end

    return spec.currentFactor
end

local function dischargeNodeHasUsableFillUnit(vehicle, dischargeNode)
    local fillUnitIndex = tonumber(dischargeNode ~= nil and dischargeNode.fillUnitIndex)
    local fillUnits = vehicle.spec_fillUnit ~= nil and vehicle.spec_fillUnit.fillUnits or nil
    local fillUnit = fillUnits ~= nil and fillUnitIndex ~= nil and fillUnits[fillUnitIndex] or nil
    if fillUnit == nil then
        return true
    end

    local capacity = tonumber(fillUnit.capacity) or tonumber(fillUnit.defaultCapacity)
    return capacity == nil or (capacity > 0 and capacity < math.huge)
end

local function getAdjustedRates(vehicle)
    local dischargeable = vehicle.spec_dischargeable
    if dischargeable == nil or dischargeable.dischargeNodes == nil then
        return nil
    end

    local factor = getFactor(vehicle)
    local rates, seen = {}, {}
    for _, dischargeNode in ipairs(dischargeable.dischargeNodes) do
        local emptySpeed = tonumber(dischargeNode.emptySpeed)
        if emptySpeed ~= nil and emptySpeed > 0 and dischargeNodeHasUsableFillUnit(vehicle, dischargeNode) then
            local rate = math.max(math.floor(emptySpeed * 1000 * factor + 0.5), 1)
            if not seen[rate] then
                seen[rate] = true
                table.insert(rates, rate)
            end
        end
    end

    table.sort(rates)
    return #rates > 0 and rates or nil
end

local function formatRate(rate)
    local value = tostring(rate)
    if g_i18n ~= nil and g_i18n.formatNumber ~= nil then
        value = g_i18n:formatNumber(rate, 0, true)
    end
    return string.format("%s %s", value, g_i18n:getText("CONFIG_AS_LPS"))
end

function ADR.prerequisitesPresent(specializations)
    return Dischargeable ~= nil
        and SpecializationUtil.hasSpecialization(Dischargeable, specializations)
end

function ADR.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(
        vehicleType,
        "getDischargeNodeEmptyFactor",
        ADR.getDischargeNodeEmptyFactor
    )
end

function ADR.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ADR)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", ADR)
end

function ADR:onLoad(savegame)
    if hasSelectedConfiguration(self) then
        getFactor(self)
    end
end

function ADR:getDischargeNodeEmptyFactor(superFunc, dischargeNode)
    local emptyFactor = tonumber(superFunc(self, dischargeNode)) or 1
    if not hasSelectedConfiguration(self) or not dischargeNodeHasUsableFillUnit(self, dischargeNode) then
        return emptyFactor
    end

    return emptyFactor * getFactor(self)
end

function ADR:onDraw(isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if not Suite.canShowHelpText(self, isActiveForInputIgnoreSelection)
        or not hasSelectedConfiguration(self) then
        return
    end

    local rates = getAdjustedRates(self)
    if rates == nil then
        return
    end

    local values = {}
    for _, rate in ipairs(rates) do
        table.insert(values, formatRate(rate))
    end

    local spec = getSpec(self)
    Suite.addHelpText(string.format(
        "ADR: %s [%s] - %s",
        Suite.getOffsetText(spec.currentOffset or 0),
        Suite.getStatusText(spec.currentOffset or 0),
        table.concat(values, " - ")
    ))
end
