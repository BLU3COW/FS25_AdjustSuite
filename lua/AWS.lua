AWS = AWS or {}

local Suite = AdjustSuite
local SETTINGS = Suite.range
local getFactorFromOffset = Suite.getFactorFromOffset
local getIsLoweredForWork = Suite.getIsLoweredForWork
local getSpec, getSelectedOffset, hasSelectedConfiguration = Suite.createModuleAccessors("AWS")

local function getStoreItem(vehicle)
    if vehicle == nil or vehicle.configFileName == nil or g_storeManager == nil then
        return nil
    end
    return g_storeManager:getItemByXMLFilename(vehicle.configFileName)
end

local function getDefaultSpeed(vehicle)
    local spec = getSpec(vehicle)
    if spec.defaultSpeedLimit ~= nil then
        return spec.defaultSpeedLimit
    end

    local storeItem = getStoreItem(vehicle)
    local speed = 0

    if storeItem ~= nil and storeItem.AWSStandardSpeedLimit ~= nil then
        speed = Utils.getNoNil(tonumber(storeItem.AWSStandardSpeedLimit), 0)
    elseif vehicle ~= nil and vehicle.speedLimit ~= nil then
        speed = Utils.getNoNil(tonumber(vehicle.speedLimit), 0)
    end

    spec.defaultSpeedLimit = speed
    return speed
end

local function isValidTool(vehicle)
    if vehicle == nil then
        return false
    end

    if not hasSelectedConfiguration(vehicle) then
        return false
    end

    local isMotorVehicle = vehicle.spec_motorized ~= nil or vehicle.spec_enterable ~= nil
    local isSelfPropelledWorkMachine = isMotorVehicle
        and vehicle.spec_workArea ~= nil
    if isMotorVehicle and not isSelfPropelledWorkMachine then
        return false
    end

    return getDefaultSpeed(vehicle) > 0.5
end

local function normalizeSpeed(vehicle, speed)
    local value = math.floor(Utils.getNoNil(tonumber(speed), getDefaultSpeed(vehicle)) + 0.5)
    return math.max(value, SETTINGS.minAbsoluteSpeed)
end
local function getAdjustedSpeed(vehicle)
    if not isValidTool(vehicle) or not getIsLoweredForWork(vehicle) then
        return nil
    end

    local speed = tonumber(getSpec(vehicle).currentSpeedLimit)
    if speed == nil or speed <= 0.5 then
        return nil
    end

    return normalizeSpeed(vehicle, speed)
end

function AWS.prerequisitesPresent(specializations)
    return true
end

function AWS.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getSpeedLimit", AWS.getSpeedLimit)
end

function AWS.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", AWS)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", AWS)
end

function AWS:onLoad(savegame)
    if not isValidTool(self) then
        return
    end

    local defaultSpeed = getDefaultSpeed(self)
    local offset = getSelectedOffset(self)
    local spec = getSpec(self)

    spec.currentOffset = offset
    spec.currentFactor = getFactorFromOffset(offset)
    spec.currentSpeedLimit = normalizeSpeed(self, defaultSpeed * spec.currentFactor)
end

function AWS:getSpeedLimit(superFunc, onlyIfWorking)
    local limit, doCheckSpeedLimit = superFunc(self, onlyIfWorking)
    if not isValidTool(self) or not getIsLoweredForWork(self) then
        return limit, doCheckSpeedLimit
    end

    local factor = getSpec(self).currentFactor or getFactorFromOffset(getSelectedOffset(self))
    limit = tonumber(limit)
    if math.abs(factor - 1) > 0.0001 and limit ~= nil and limit > 0.5 and limit < math.huge then
        return math.max(limit * factor, SETTINGS.minAbsoluteSpeed), doCheckSpeedLimit
    end

    return limit, doCheckSpeedLimit
end

function AWS:onDraw(isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if not Suite.canShowHelpText(self, isActiveForInputIgnoreSelection) then
        return
    end

    local adjustedSpeed = getAdjustedSpeed(self)
    if adjustedSpeed ~= nil then
        local displaySpeed = math.floor(adjustedSpeed + 0.5)
        local displayUnit = g_i18n:getText("CONFIG_AS_KMH")
        if g_gameSettings.useMiles == true then
            displaySpeed = math.floor((adjustedSpeed / 1.609344) * 10 + 0.5) / 10
            displayUnit = g_i18n:getText("CONFIG_AS_MPH")
        end
        local offset = getSpec(self).currentOffset or getSelectedOffset(self)
        Suite.addHelpText(string.format("AWS: %s [%s] - %s %s", Suite.getOffsetText(offset), Suite.getStatusText(offset), tostring(displaySpeed), displayUnit))
    end
end
