AdjustSuiteACAP = AdjustSuiteACAP or {}
local ACAP = AdjustSuiteACAP

local Suite = AdjustSuite
local PRODUCTION_PATH = "placeable.productionPoint"
local PRODUCTION_CONFIGURATIONS_PATH = PRODUCTION_PATH
    .. ".productionPointConfigurations.productionPointConfiguration"
local FEEDING_ROBOT_PATH = "placeable.husbandry.feedingRobot"

local function scaleRuntimeValue(object, key, factor)
    if type(object) ~= "table" then
        return false
    end

    local value = tonumber(object[key])
    if value == nil or value <= 0 then
        return false
    end

    object[key] = math.max(math.ceil(value * factor - 0.000001), 1)
    return true
end

local function productionPointHasCycleAmounts(xmlFile, key)
    local hasCycleAmounts = false
    xmlFile:iterate(key .. ".productions.production", function(_, productionKey)
        local hasInput = false
        local hasOutput = false
        xmlFile:iterate(productionKey .. ".inputs.input", function()
            hasInput = true
        end)
        xmlFile:iterate(productionKey .. ".outputs.output", function()
            hasOutput = true
        end)
        hasCycleAmounts = hasCycleAmounts or hasInput and hasOutput
    end)
    return hasCycleAmounts
end

function ACAP.getStoreContext(xmlFile, configurations, defaultConfigurationIds, customEnvironment, storeItem)
    local hasCycleAmounts = productionPointHasCycleAmounts(xmlFile, PRODUCTION_PATH)
    xmlFile:iterate(PRODUCTION_CONFIGURATIONS_PATH, function(_, key)
        hasCycleAmounts = hasCycleAmounts
            or productionPointHasCycleAmounts(xmlFile, key .. ".productionPoint")
    end)
    local hasFeedingRobot = xmlFile:hasProperty(FEEDING_ROBOT_PATH)
        and xmlFile:getValue(FEEDING_ROBOT_PATH .. "#filename") ~= nil
    if not hasCycleAmounts and not hasFeedingRobot then
        return nil
    end

    return {basePrice = Suite.getStoreItemPrice(storeItem, xmlFile)}
end

function ACAP.onFeedingRobotLoaded(placeable, robot, args)
    local factor = Suite.getFactorFromOffset(Suite.getSelectedOffset(placeable, "ACAP"))
    if robot == nil or factor == 1 or robot.adjustSuiteACAPScaled == true then
        return
    end

    scaleRuntimeValue(robot.fillPlane, "capacity", factor)
    scaleRuntimeValue(robot.fillPlane, "maxCapacity", factor)
    scaleRuntimeValue(robot, "fillPlaneCapacity", factor)

    local stateMachine = robot.stateMachine
    for _, state in pairs(stateMachine ~= nil and stateMachine.states or {}) do
        scaleRuntimeValue(state, "deltaFillLevel", factor)
    end

    local capacity = tonumber(robot.fillPlaneCapacity)
        or tonumber(type(robot.fillPlane) == "table" and robot.fillPlane.capacity)
        or tonumber(type(robot.fillPlane) == "table" and robot.fillPlane.maxCapacity)
    if capacity ~= nil and capacity > 0
        and type(robot.fillPlane) == "table"
        and robot.fillPlane.setState ~= nil then
        robot.fillPlane:setState(math.clamp((tonumber(robot.fillLevel) or 0) / capacity, 0, 1))
    end

    robot.adjustSuiteACAPScaled = true
end

if PlaceableHusbandryFeedingRobot ~= nil
    and PlaceableHusbandryFeedingRobot.onFeedingRobotLoaded ~= nil
    and ACAP.feedingRobotHookInstalled ~= true then
    ACAP.feedingRobotHookInstalled = true
    PlaceableHusbandryFeedingRobot.onFeedingRobotLoaded = Utils.appendedFunction(
        PlaceableHusbandryFeedingRobot.onFeedingRobotLoaded,
        ACAP.onFeedingRobotLoaded
    )
end
