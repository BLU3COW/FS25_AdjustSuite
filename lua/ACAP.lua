AdjustSuiteACAP = AdjustSuiteACAP or {}
local ACAP = AdjustSuiteACAP

local Suite = AdjustSuite
Suite.moduleClasses["ACAP"] = ACAP
local PRODUCTION_PATH = "placeable.productionPoint"
local PRODUCTION_CONFIGURATIONS_PATH = PRODUCTION_PATH .. ".productionPointConfigurations.productionPointConfiguration"
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
        xmlFile:iterate(productionKey .. ".inputs.input", function()
            hasCycleAmounts = true
        end)
        xmlFile:iterate(productionKey .. ".outputs.output", function()
            hasCycleAmounts = true
        end)
    end)
    return hasCycleAmounts
end

function ACAP.getStoreContext(xmlFile, _configurations, _defaultConfigurationIds, _customEnvironment, storeItem)
    local hasCycleAmounts = productionPointHasCycleAmounts(xmlFile, PRODUCTION_PATH)
    xmlFile:iterate(PRODUCTION_CONFIGURATIONS_PATH, function(_, key)
        hasCycleAmounts = hasCycleAmounts or productionPointHasCycleAmounts(xmlFile, key .. ".productionPoint")
    end)
    local hasFeedingRobot = xmlFile:hasProperty(FEEDING_ROBOT_PATH)
        and xmlFile:getValue(FEEDING_ROBOT_PATH .. "#filename") ~= nil
    if not hasCycleAmounts and not hasFeedingRobot then
        return nil
    end

    return { basePrice = Suite.getStoreItemPrice(storeItem, xmlFile) }
end

local function getSelectedProductionKey(placeable)
    local configurationId = tonumber(placeable.configurations ~= nil and placeable.configurations.productionPoint) or 1
    local key = string.format("%s(%d).productionPoint", PRODUCTION_CONFIGURATIONS_PATH, configurationId - 1)
    if placeable.xmlFile:hasProperty(key) then
        return key
    end
    return PRODUCTION_PATH
end

local function scaleAmount(handle, attribute, factor)
    local value = getXMLFloat(handle, attribute)
    if value ~= nil and value > 0 then
        setXMLFloat(handle, attribute, value * factor)
    end
end

function ACAP.applyToPlaceableXML(placeable, offset)
    local xmlFile = placeable.xmlFile
    if not Suite.isSandboxPlaceableXML(xmlFile) then
        return
    end

    placeable.adjustSuiteACAPScaledInXML = true

    local factor = Suite.getFactorFromOffset(offset)
    if factor == 1 then
        return
    end

    local handle = xmlFile.handle
    if handle ~= nil then
        xmlFile:iterate(getSelectedProductionKey(placeable) .. ".productions.production", function(_, productionKey)
            xmlFile:iterate(productionKey .. ".inputs.input", function(_, inputKey)
                scaleAmount(handle, inputKey .. "#amount", factor)
                xmlFile:iterate(inputKey .. ".outputAmount", function(_, outputAmountKey)
                    scaleAmount(handle, outputAmountKey .. "#active", factor)
                end)
            end)
            xmlFile:iterate(productionKey .. ".outputs.output", function(_, outputKey)
                scaleAmount(handle, outputKey .. "#amount", factor)
            end)
        end)
    end

    Suite.scaleSandboxDistributions(xmlFile, factor)
end

function ACAP.onFeedingRobotLoaded(placeable, robot, _args)
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
    if capacity ~= nil and capacity > 0 and type(robot.fillPlane) == "table" and robot.fillPlane.setState ~= nil then
        robot.fillPlane:setState(math.clamp((tonumber(robot.fillLevel) or 0) / capacity, 0, 1))
    end

    robot.adjustSuiteACAPScaled = true
end

if
    PlaceableHusbandryFeedingRobot ~= nil
    and PlaceableHusbandryFeedingRobot.onFeedingRobotLoaded ~= nil
    and ACAP.feedingRobotHookInstalled ~= true
then
    ACAP.feedingRobotHookInstalled = true
    PlaceableHusbandryFeedingRobot.onFeedingRobotLoaded =
        Utils.appendedFunction(PlaceableHusbandryFeedingRobot.onFeedingRobotLoaded, ACAP.onFeedingRobotLoaded)
end
