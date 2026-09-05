AdjustSuiteCourseplay = AdjustSuiteCourseplay or {}

local Compatibility = AdjustSuiteCourseplay
local Suite = AdjustSuite
local UPDATE_INTERVAL_MS = 250
local states = setmetatable({}, {__mode = "k"})

local function getState(rootVehicle)
    local state = states[rootVehicle]
    if state == nil then
        state = {}
        states[rootVehicle] = state
    end
    return state
end

local function getRootVehicle(object)
    if object == nil then
        return nil
    end

    if object.getRootVehicle ~= nil then
        local ok, rootVehicle = pcall(object.getRootVehicle, object)
        if ok and rootVehicle ~= nil then
            return rootVehicle
        end
    end

    return object
end

local function getVehicleTree(rootVehicle, source)
    local objects = {}
    local seen = {}

    local function add(object)
        if object ~= nil and not seen[object] then
            seen[object] = true
            table.insert(objects, object)
        end
    end

    add(rootVehicle)
    add(source)

    if rootVehicle ~= nil and rootVehicle.getChildVehicles ~= nil then
        local ok, childVehicles = pcall(rootVehicle.getChildVehicles, rootVehicle)
        if ok then
            for _, object in ipairs(childVehicles or {}) do
                add(object)
            end
        end
    end

    return objects
end

local function getPositiveAwwWidth(rootVehicle, source)
    local maxWidth

    for _, object in ipairs(getVehicleTree(rootVehicle, source)) do
        if Suite.getSelectedOffset(object, "AWW") > 0 then
            local spec = object.spec_AWW
            local width = spec ~= nil and tonumber(spec.currentWidth) or nil
            if width ~= nil and width > 0 then
                maxWidth = math.max(maxWidth or 0, width)
            end
        end
    end

    return maxWidth
end

local function getCourseplayDischargeTarget(vehicle)
    local getStrategy = vehicle ~= nil and vehicle.getCpDriveStrategy or nil
    if getStrategy == nil then
        return nil
    end

    local strategyOk, strategy = pcall(getStrategy, vehicle)
    if not strategyOk or strategy == nil then
        return nil
    end

    local pipeController = strategy.pipeController
    if pipeController ~= nil and pipeController.getDischargeObject ~= nil then
        local targetOk, target = pcall(pipeController.getDischargeObject, pipeController)
        if targetOk and target ~= nil and target ~= false then
            return target, strategy
        end
    end

    if pipeController ~= nil and pipeController.isFillableTrailerInRange ~= nil then
        local rangeOk, inRange, target = pcall(pipeController.isFillableTrailerInRange, pipeController)
        if rangeOk and inRange == true and target ~= nil then
            return target, strategy
        end
    end

    return nil, strategy
end

function Compatibility.ignoreDischargeTarget(vehicle, object, detectedVehicle, moveForwards, hitTerrain)
    local rootVehicle = getRootVehicle(vehicle)
    if moveForwards ~= true
        or hitTerrain == true
        or rootVehicle == nil
        or getPositiveAwwWidth(rootVehicle, vehicle) == nil
        or rootVehicle.spec_combine == nil
        or rootVehicle.getIsTurnedOn == nil
        or rootVehicle:getIsTurnedOn() ~= true
        or not Suite.getIsLoweredForWork(rootVehicle) then
        return false
    end

    local target = getCourseplayDischargeTarget(rootVehicle)
    local targetRoot = getRootVehicle(target)
    if targetRoot == nil then
        return false
    end

    return getRootVehicle(detectedVehicle) == targetRoot
        or getRootVehicle(object) == targetRoot
end

local function registerProximityFilter(rootVehicle)
    if rootVehicle.spec_combine == nil then
        return
    end

    local _, strategy = getCourseplayDischargeTarget(rootVehicle)
    local controller = strategy ~= nil and strategy.proximityController or nil
    if controller == nil or controller.registerIgnoreObjectCallback == nil then
        return
    end

    local state = getState(rootVehicle)
    if state.proximityController == controller then
        return
    end

    controller:registerIgnoreObjectCallback(rootVehicle, Compatibility.ignoreDischargeTarget)
    state.proximityController = controller
end

function Compatibility.update(source)
    if source == nil or g_Courseplay == nil then
        return
    end

    local rootVehicle = getRootVehicle(source)
    if rootVehicle == nil then
        return
    end

    local state = getState(rootVehicle)
    local now = g_currentMission ~= nil and tonumber(g_currentMission.time) or 0
    if state.nextUpdateTime ~= nil and now < state.nextUpdateTime then
        return
    end
    state.nextUpdateTime = now + UPDATE_INTERVAL_MS

    if getPositiveAwwWidth(rootVehicle, source) == nil then
        return
    end

    registerProximityFilter(rootVehicle)
end
