AdjustSuiteAWS = AdjustSuiteAWS or {}
local AWS = AdjustSuiteAWS

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

    if vehicle.spec_workArea == nil then
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

function AWS.prerequisitesPresent(_specializations)
    return true
end

function AWS.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getRawSpeedLimit", AWS.getRawSpeedLimit)
end

function AWS.initSpecialization()
    Suite.registerOffsetSavegamePaths("AWS")
end

function AWS:onPreLoad(savegame)
    Suite.loadStoredOffsets(self, "AWS", savegame)
    Suite.resolveConfiguration(self, "AWS", self.isServer)
end

function AWS:saveToXMLFile(xmlFile, key, _usedModNames)
    Suite.saveStoredOffsets(self, "AWS", xmlFile, key)
end

function AWS.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onPreLoad", AWS)
    SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", AWS)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", AWS)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", AWS)
end

function AWS:onLoad(_savegame)
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

function AWS:getRawSpeedLimit(superFunc)
    local limit = superFunc(self)
    if not isValidTool(self) or not getIsLoweredForWork(self) then
        return limit
    end

    local factor = getSpec(self).currentFactor or getFactorFromOffset(getSelectedOffset(self))
    limit = tonumber(limit)
    if math.abs(factor - 1) > 0.0001 and limit ~= nil and limit > 0.5 and limit < math.huge then
        return math.max(limit * factor, SETTINGS.minAbsoluteSpeed)
    end

    return limit
end

function AWS:onDraw(_isActiveForInput, isActiveForInputIgnoreSelection, _isSelected)
    if not Suite.canShowHelpText(self, isActiveForInputIgnoreSelection) then
        return
    end

    local adjustedSpeed = getAdjustedSpeed(self)
    if adjustedSpeed ~= nil then
        local displaySpeed, displayUnit = Suite.getSpeedDisplay(adjustedSpeed)
        local offset = getSpec(self).currentOffset or getSelectedOffset(self)
        Suite.addHelpText(
            string.format(
                "AWS: %s [%s] - %s %s",
                Suite.getOffsetText(offset),
                Suite.getStatusText(offset),
                tostring(displaySpeed),
                displayUnit
            )
        )
    end
end
