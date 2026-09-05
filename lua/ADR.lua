AdjustSuiteADR = AdjustSuiteADR or {}
local ADR = AdjustSuiteADR

local Suite = AdjustSuite
local getSpec, _, hasSelectedConfiguration, getFactor = Suite.createModuleAccessors("ADR")
local WIDTH_CONFIGURATION_NAMES = {"AWW", "APW"}

local function getIsBufferCombine(vehicle)
    local combineSpec = vehicle ~= nil and vehicle.spec_combine or nil
    if combineSpec == nil then
        return false
    end

    if combineSpec.isBufferCombine == true then
        return true
    end

    local capacity = vehicle.getFillUnitCapacity ~= nil
        and vehicle:getFillUnitCapacity(combineSpec.fillUnitIndex)
        or nil
    return capacity == math.huge
end

local function getBufferFlowFactor(vehicle)
    local combineSpec = vehicle ~= nil and vehicle.spec_combine or nil
    if combineSpec == nil or not getIsBufferCombine(vehicle) then
        return 1
    end

    local widthFactor, speedFactor = 1, 1
    local function includeTool(tool)
        local configurations = tool ~= nil and tool.configurations or nil
        if configurations ~= nil then
            for _, moduleId in ipairs(WIDTH_CONFIGURATION_NAMES) do
                if configurations[moduleId] ~= nil then
                    widthFactor = math.max(
                        widthFactor,
                        Suite.getFactorFromOffset(Suite.getSelectedOffset(tool, moduleId))
                    )
                end
            end
            if configurations.AWS ~= nil then
                speedFactor = math.max(
                    speedFactor,
                    Suite.getFactorFromOffset(Suite.getSelectedOffset(tool, "AWS"))
                )
            end
        end
    end

    includeTool(vehicle)
    for cutter in pairs(combineSpec.attachedCutters or {}) do
        includeTool(cutter)
    end

    return widthFactor * speedFactor
end

local function applyBufferEmptySpeeds(vehicle)
    if not getIsBufferCombine(vehicle) then
        return false
    end

    local dischargeable = vehicle.spec_dischargeable
    if dischargeable == nil or dischargeable.dischargeNodes == nil then
        return false
    end

    local combineSpec = vehicle.spec_combine
    local factor = getBufferFlowFactor(vehicle)
    local applied = false
    for _, dischargeNode in ipairs(dischargeable.dischargeNodes) do
        if tonumber(dischargeNode.fillUnitIndex) == tonumber(combineSpec.fillUnitIndex) then
            local baseEmptySpeed = tonumber(dischargeNode.ADRBufferBaseEmptySpeed)
            if baseEmptySpeed == nil then
                baseEmptySpeed = tonumber(dischargeNode.emptySpeed)
                dischargeNode.ADRBufferBaseEmptySpeed = baseEmptySpeed
            end

            if baseEmptySpeed ~= nil and baseEmptySpeed > 0 then
                dischargeNode.emptySpeed = baseEmptySpeed * factor
                applied = true
            end
        end
    end

    return applied
end

local function isBufferDischargeNode(vehicle, dischargeNode)
    local combineSpec = vehicle ~= nil and vehicle.spec_combine or nil
    return combineSpec ~= nil
        and getIsBufferCombine(vehicle)
        and tonumber(dischargeNode ~= nil and dischargeNode.fillUnitIndex) == tonumber(combineSpec.fillUnitIndex)
        and (tonumber(dischargeNode ~= nil and dischargeNode.emptySpeed) or 0) > 0
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
    if getIsBufferCombine(vehicle) then
        return nil
    end

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
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", ADR)
    SpecializationUtil.registerEventListener(vehicleType, "onPostAttachImplement", ADR)
    SpecializationUtil.registerEventListener(vehicleType, "onPostDetachImplement", ADR)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", ADR)
end

function ADR:onLoad(savegame)
    if hasSelectedConfiguration(self) then
        getFactor(self)
    end
end

function ADR:onPostLoad(savegame)
    applyBufferEmptySpeeds(self)
end

function ADR:onPostAttachImplement(attachable, inputJointDescIndex, jointDescIndex)
    applyBufferEmptySpeeds(self)
end

function ADR:onPostDetachImplement(implement)
    applyBufferEmptySpeeds(self)
end

function ADR:getDischargeNodeEmptyFactor(superFunc, dischargeNode)
    local emptyFactor = tonumber(superFunc(self, dischargeNode)) or 1
    if isBufferDischargeNode(self, dischargeNode) then
        return emptyFactor
    end

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
