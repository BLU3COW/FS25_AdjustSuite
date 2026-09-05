AdjustSuiteADS = AdjustSuiteADS or {}
local ADS = AdjustSuiteADS

local Suite = AdjustSuite
local getSpec, getSelectedOffset, hasSelectedConfiguration = Suite.createModuleAccessors("ADS")

local MAX_OVERDRIVE_SPEED_STEP = 1.25
local MAX_FIXED_GEARS = 31

local function addOverdriveGears(gears, factor, direction)
    if factor <= 1 or #gears == 0 or #gears >= MAX_FIXED_GEARS then
        return 0
    end

    local topGear = gears[#gears]
    local topRatio = type(topGear) == "table" and math.abs(tonumber(topGear.ratio) or 0) or 0
    if topRatio <= 0 then
        return 0
    end

    local count = math.max(math.ceil(math.log(factor) / math.log(MAX_OVERDRIVE_SPEED_STEP)), 1)
    count = math.min(count, MAX_FIXED_GEARS - #gears)

    local speedStep = factor ^ (1 / count)
    for index = 1, count do
        local gearIndex = #gears + 1
        local gearName = tostring(gearIndex * direction)
        local reverseName = tostring(gearIndex * direction * -1)
        gears[gearIndex] = {
            ratio = topRatio / (speedStep ^ index),
            default = false,
            name = gearName,
            reverseName = reverseName,
            dashboardName = gearName,
            dashboardReverseName = reverseName
        }
    end

    return count
end

local function adjustFixedGears(gears, factor, direction, adjustedTables)
    if type(gears) ~= "table" or adjustedTables[gears] == true then
        return
    end

    adjustedTables[gears] = true
    if factor < 1 then
        for _, gear in ipairs(gears) do
            if type(gear.ratio) == "number" then
                gear.ratio = gear.ratio / factor
            end
        end
    elseif factor > 1 then
        addOverdriveGears(gears, factor, direction)
    end
end

local function scaleRatio(value, factor)
    return type(value) == "number" and value / factor or value
end

local function updateCruiseControl(vehicle, factor)
    local drivableSpec = vehicle.spec_drivable
    local cruiseControl = drivableSpec ~= nil and drivableSpec.cruiseControl or nil
    if cruiseControl == nil then
        return
    end

    local previousMaxSpeed = tonumber(cruiseControl.maxSpeed) or 0
    local previousMaxReverseSpeed = tonumber(cruiseControl.maxSpeedReverse) or 0
    local minSpeed = tonumber(cruiseControl.minSpeed) or 1
    local maxSpeed = math.max(previousMaxSpeed * factor, minSpeed)
    local maxReverseSpeed = math.max(previousMaxReverseSpeed * factor, minSpeed)

    cruiseControl.maxSpeed = maxSpeed
    cruiseControl.maxSpeedReverse = maxReverseSpeed

    if tonumber(cruiseControl.speed) == nil or cruiseControl.speed >= previousMaxSpeed - 0.01 then
        cruiseControl.speed = maxSpeed
    else
        cruiseControl.speed = math.min(cruiseControl.speed, maxSpeed)
    end

    if tonumber(cruiseControl.speedReverse) == nil
        or cruiseControl.speedReverse >= previousMaxReverseSpeed - 0.01 then
        cruiseControl.speedReverse = maxReverseSpeed
    else
        cruiseControl.speedReverse = math.min(cruiseControl.speedReverse, maxReverseSpeed)
    end

    cruiseControl.speedSent = cruiseControl.speed
    cruiseControl.speedReverseSent = cruiseControl.speedReverse
end

local function applyDrivingSpeed(vehicle)
    if not hasSelectedConfiguration(vehicle) then
        return false
    end

    local motor = vehicle.spec_motorized ~= nil and vehicle.spec_motorized.motor or nil
    if motor == nil
        or motor.getMaximumForwardSpeed == nil
        or motor.getMaximumBackwardSpeed == nil then
        return false
    end

    local baseForwardSpeed = tonumber(motor.maxForwardSpeedOrigin) or tonumber(motor.maxForwardSpeed)
    local baseBackwardSpeed = tonumber(motor.maxBackwardSpeedOrigin) or tonumber(motor.maxBackwardSpeed)
    if baseForwardSpeed == nil or baseForwardSpeed <= 0
        or baseBackwardSpeed == nil or baseBackwardSpeed <= 0 then
        return false
    end

    local spec = getSpec(vehicle)
    local offset = getSelectedOffset(vehicle)
    local factor = Suite.getFactorFromOffset(offset)
    local adjustedTables = {}

    adjustFixedGears(motor.forwardGears, factor, 1, adjustedTables)
    adjustFixedGears(motor.backwardGears, factor, -1, adjustedTables)

    motor.minForwardGearRatioOrigin = scaleRatio(motor.minForwardGearRatioOrigin, factor)
    motor.minBackwardGearRatioOrigin = scaleRatio(motor.minBackwardGearRatioOrigin, factor)

    motor.maxForwardSpeedOrigin = baseForwardSpeed * factor
    motor.maxBackwardSpeedOrigin = baseBackwardSpeed * factor

    if type(motor.maxClutchSpeedDifference) == "number" then
        motor.maxClutchSpeedDifference = motor.maxClutchSpeedDifference * factor
    end

    if motor.setTransmissionDirection ~= nil then
        local direction = tonumber(motor.transmissionDirection) or 1
        motor:setTransmissionDirection(direction < 0 and -1 or 1)
    else
        motor.maxForwardSpeed = motor.maxForwardSpeedOrigin
        motor.maxBackwardSpeed = motor.maxBackwardSpeedOrigin
        motor.minForwardGearRatio = motor.minForwardGearRatioOrigin
        motor.maxForwardGearRatio = motor.maxForwardGearRatioOrigin
        motor.minBackwardGearRatio = motor.minBackwardGearRatioOrigin
        motor.maxBackwardGearRatio = motor.maxBackwardGearRatioOrigin
    end

    updateCruiseControl(vehicle, factor)

    spec.currentOffset = offset
    spec.currentFactor = factor
    spec.baseForwardSpeed = baseForwardSpeed
    spec.currentForwardSpeed = motor.maxForwardSpeedOrigin
    return true
end

local function getDisplaySpeed(speed)
    local displaySpeed = speed * 3.6
    local displayUnit = g_i18n:getText("CONFIG_AS_KMH")

    if g_gameSettings.useMiles == true then
        displaySpeed = displaySpeed / 1.609344
        displayUnit = g_i18n:getText("CONFIG_AS_MPH")
    end

    displaySpeed = math.floor(displaySpeed * 10 + 0.5) / 10
    return displaySpeed, displayUnit
end

function ADS.prerequisitesPresent(specializations)
    return Motorized ~= nil
        and Drivable ~= nil
        and Wheels ~= nil
        and SpecializationUtil.hasSpecialization(Motorized, specializations)
        and SpecializationUtil.hasSpecialization(Drivable, specializations)
        and SpecializationUtil.hasSpecialization(Wheels, specializations)
end

function ADS.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ADS)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", ADS)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", ADS)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", ADS)
end

function ADS:onLoad(savegame)
    if hasSelectedConfiguration(self) then
        getSpec(self).pendingApply = true
    end
end

function ADS:onPostLoad(savegame)
    local spec = getSpec(self)
    if spec.pendingApply == true and applyDrivingSpeed(self) then
        spec.pendingApply = false
    end
end

function ADS:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = getSpec(self)
    if spec.pendingApply == true and applyDrivingSpeed(self) then
        spec.pendingApply = false
    end
end

function ADS:onDraw(isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = getSpec(self)
    if not Suite.canShowHelpText(self, isActiveForInputIgnoreSelection)
        or spec.currentForwardSpeed == nil then
        return
    end

    local displaySpeed, displayUnit = getDisplaySpeed(spec.currentForwardSpeed)
    Suite.addHelpText(string.format(
        "ADS: %s [%s] - %s %s",
        Suite.getOffsetText(spec.currentOffset or 0),
        Suite.getStatusText(spec.currentOffset or 0),
        tostring(displaySpeed),
        displayUnit
    ))
end
