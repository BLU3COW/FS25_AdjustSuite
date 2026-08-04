APW = APW or {}

local Suite = AdjustSuite

local pickupWorkAreaFunctions = {
    processBalerArea = true,
    processForageWagonArea = true
}
local getSpec, getSelectedOffset = Suite.createModuleAccessors("APW")

local getNode = Suite.resolveNode
local getNodePosition = Suite.getNodePosition
local setNodePosition = Suite.setNodePosition

local function getAreaNodes(workArea)
    if workArea == nil then
        return nil, nil, nil
    end

    local startNode = getNode(workArea.start or workArea.startNode or workArea.startNodeId or workArea.startNodeIndex)
    local widthNode = getNode(workArea.width or workArea.widthNode or workArea.widthNodeId or workArea.widthNodeIndex)
    local heightNode = getNode(workArea.height or workArea.heightNode or workArea.heightNodeId or workArea.heightNodeIndex)
    if startNode ~= nil and widthNode ~= nil and startNode ~= 0 and widthNode ~= 0 then
        return startNode, widthNode, heightNode
    end

    return nil, nil, nil
end

local function isPickupWorkArea(workArea)
    return workArea ~= nil and pickupWorkAreaFunctions[workArea.functionName] == true
end

local function collectPickupAreas(vehicle)
    local workAreas = vehicle.spec_workArea ~= nil and vehicle.spec_workArea.workAreas or nil
    local areas = {}
    local nodes = {}
    local uniqueNodes = {}

    for index, workArea in ipairs(workAreas or {}) do
        if isPickupWorkArea(workArea) then
            local startNode, widthNode, heightNode = getAreaNodes(workArea)
            if startNode ~= nil then
                table.insert(areas, {
                    index = workArea.index or index,
                    startNode = startNode,
                    widthNode = widthNode,
                    heightNode = heightNode
                })

                for _, node in ipairs({startNode, widthNode, heightNode}) do
                    if uniqueNodes[node] ~= true then
                        uniqueNodes[node] = true
                        table.insert(nodes, node)
                    end
                end
            end
        end
    end

    return areas, nodes
end

local function applyPickupWidth(vehicle)
    local spec = getSpec(vehicle)
    local referenceNode = vehicle.components ~= nil
        and vehicle.components[1] ~= nil
        and vehicle.components[1].node
        or vehicle.rootNode
    if type(referenceNode) ~= "number" or referenceNode == 0 then
        return false
    end

    local areas, nodes = collectPickupAreas(vehicle)
    if #areas == 0 or #nodes == 0 then
        return false
    end

    local startX, startY, startZ = getNodePosition(areas[1].startNode, referenceNode)
    local widthX, widthY, widthZ = getNodePosition(areas[1].widthNode, referenceNode)
    if startX == nil or widthX == nil then
        return false
    end

    local axisX = widthX - startX
    local axisY = widthY - startY
    local axisZ = widthZ - startZ
    local axisLength = math.sqrt(axisX * axisX + axisY * axisY + axisZ * axisZ)
    if axisLength <= 0.01 then
        return false
    end

    axisX = axisX / axisLength
    axisY = axisY / axisLength
    axisZ = axisZ / axisLength

    local positions = {}
    local minProjection = math.huge
    local maxProjection = -math.huge
    for _, node in ipairs(nodes) do
        local x, y, z = getNodePosition(node, referenceNode)
        if x == nil then
            return false
        end

        local projection = x * axisX + y * axisY + z * axisZ
        positions[node] = {x = x, y = y, z = z, projection = projection}
        minProjection = math.min(minProjection, projection)
        maxProjection = math.max(maxProjection, projection)
    end

    local baseWidth = maxProjection - minProjection
    if baseWidth <= 0.01 then
        return false
    end

    local offset = getSelectedOffset(vehicle)
    local factor = Suite.getFactorFromOffset(offset)
    local centerProjection = (minProjection + maxProjection) * 0.5

    for node, position in pairs(positions) do
        local targetProjection = centerProjection + (position.projection - centerProjection) * factor
        local delta = targetProjection - position.projection
        if not setNodePosition(
            node,
            referenceNode,
            position.x + axisX * delta,
            position.y + axisY * delta,
            position.z + axisZ * delta
        ) then
            return false
        end
    end

    if vehicle.updateWorkAreaWidth ~= nil then
        for _, area in ipairs(areas) do
            vehicle:updateWorkAreaWidth(area.index)
        end
    end

    spec.baseWidth = baseWidth
    spec.currentWidth = baseWidth * factor
    spec.currentOffset = offset
    return true
end

function APW.prerequisitesPresent(specializations)
    return Pickup ~= nil
        and WorkArea ~= nil
        and SpecializationUtil.hasSpecialization(Pickup, specializations)
        and SpecializationUtil.hasSpecialization(WorkArea, specializations)
end

function APW.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", APW)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", APW)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", APW)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", APW)
end

function APW:onLoad(savegame)
    if self.configurations == nil or self.configurations.APW == nil then
        return
    end

    getSpec(self).pendingApply = true
end

function APW:onPostLoad(savegame)
    local spec = getSpec(self)
    if spec.pendingApply == true and applyPickupWidth(self) then
        spec.pendingApply = false
    end
end

function APW:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = getSpec(self)
    if spec.pendingApply == true and applyPickupWidth(self) then
        spec.pendingApply = false
    end
end

function APW:onDraw(isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = getSpec(self)
    if not Suite.canShowHelpText(self, isActiveForInputIgnoreSelection)
        or spec.currentWidth == nil
        or not Suite.getIsLoweredForWork(self)
        then
        return
    end

    Suite.addHelpText(string.format(
        "APW: %s [%s] - %.2f %s",
        Suite.getOffsetText(spec.currentOffset or 0),
        Suite.getStatusText(spec.currentOffset or 0),
        spec.currentWidth,
        g_i18n:getText("CONFIG_AS_M")
    ))
end
