AdjustSuiteAWW = AdjustSuiteAWW or {}
local AWW = AdjustSuiteAWW

local Suite = AdjustSuite
local clampOffset = Suite.clampOffset
local getFactorFromOffset = Suite.getFactorFromOffset
local getIsLoweredForWork = Suite.getIsLoweredForWork
local SAVEGAME_PATH = ".FS25_AdjustSuite.AWW#useWindrowDropAreas"
local getSpec, getSelectedOffset = Suite.createModuleAccessors("AWW")

local function round2(value)
    value = tonumber(value) or 0
    return math.floor(value * 100 + 0.5) / 100
end

local function distance3(x1, y1, z1, x2, y2, z2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dz = z2 - z1
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local resolveNode = Suite.resolveNode
local getNodePositionInReference = Suite.getNodePosition
local setNodePositionFromReference = Suite.setNodePosition

local function getConfiguredWorkingWidth(vehicle)
    local spec = getSpec(vehicle)
    if spec.configuredBaseWidth ~= nil then
        return spec.configuredBaseWidth
    end

    local storeItem = vehicle.configFileName ~= nil
        and g_storeManager ~= nil
        and g_storeManager:getItemByXMLFilename(vehicle.configFileName)
        or nil
    local width = storeItem ~= nil and tonumber(storeItem.AWWStandardWorkingWidth) or nil
    if (width == nil or width <= 0) and vehicle.xmlFile ~= nil then
        width = tonumber(vehicle.xmlFile:getValue("vehicle.storeData.specs.workingWidth"))
    end

    spec.configuredBaseWidth = width ~= nil and width > 0 and width or 0
    return spec.configuredBaseWidth
end

local function getAreaNodes(workArea)
    if workArea == nil then
        return nil, nil, nil
    end

    local startNode = resolveNode(workArea.start or workArea.startNode or workArea.startNodeId or workArea.startNodeIndex)
    local widthNode = resolveNode(workArea.width or workArea.widthNode or workArea.widthNodeId or workArea.widthNodeIndex)
    local heightNode = resolveNode(workArea.height or workArea.heightNode or workArea.heightNodeId or workArea.heightNodeIndex)

    if startNode ~= nil and widthNode ~= nil and startNode ~= 0 and widthNode ~= 0 then
        return startNode, widthNode, heightNode
    end

    return nil, nil, nil
end

local function getWorkAreas(vehicle)
    if vehicle.spec_workArea ~= nil and vehicle.spec_workArea.workAreas ~= nil then
        return vehicle.spec_workArea.workAreas
    end

    if vehicle.workAreas ~= nil then
        return vehicle.workAreas
    end

    return nil
end

local function getAreaIsAuxiliary(workArea)
    return workArea ~= nil
        and WorkAreaType ~= nil
        and WorkAreaType.AUXILIARY ~= nil
        and workArea.type == WorkAreaType.AUXILIARY
end

local function createAreaEntry(workArea, index)
    local startNode, widthNode, heightNode = getAreaNodes(workArea)
    if startNode == nil or widthNode == nil then
        return nil
    end

    return {
        workArea = workArea,
        workAreaIndex = workArea.index or index,
        startNode = startNode,
        widthNode = widthNode,
        heightNode = heightNode
    }
end

local function restoreSyntheticAreaSet(areaSet)
    if areaSet == nil then
        return
    end

    for _, mapping in ipairs(areaSet.mappings or {}) do
        mapping.workArea.start = mapping.startNode
        mapping.workArea.width = mapping.widthNode
        mapping.workArea.height = mapping.heightNode
    end

    areaSet.active = false
    areaSet.members = {}
    areaSet.mappings = {}
end

local function restoreSyntheticAreaSets(spec)
    restoreSyntheticAreaSet(spec.syntheticPlowArea)
    restoreSyntheticAreaSet(spec.syntheticPlowPackerArea)
    restoreSyntheticAreaSet(spec.syntheticTedderDropArea)
end

local function getAxisFromNodes(startNode, widthNode, referenceNode)
    local sx, sy, sz = getNodePositionInReference(startNode, referenceNode)
    local wx, wy, wz = getNodePositionInReference(widthNode, referenceNode)
    if sx == nil or wx == nil then
        return nil
    end

    local dx = wx - sx
    local dy = wy - sy
    local dz = wz - sz
    local length = distance3(0, 0, 0, dx, dy, dz)
    if length <= 0.01 then
        return nil
    end

    return dx / length, dy / length, dz / length, length
end

local function getPlowWidthAreas(vehicle, areas)
    if vehicle.spec_plow == nil or WorkAreaType == nil or WorkAreaType.PLOW == nil then
        return areas, false
    end

    local plowAreas = {}
    for _, area in ipairs(areas) do
        if area.workArea.type == WorkAreaType.PLOW then
            table.insert(plowAreas, area)
        end
    end

    if #plowAreas == 0 then
        return areas, false
    end

    return plowAreas, true
end

local function getWidthAxis(vehicle, areas, referenceNode, usePlowAxis)
    if usePlowAxis or vehicle.spec_windrower ~= nil then
        return 1, 0, 0
    end

    if vehicle.getAIMarkers ~= nil then
        local ok, leftMarker, rightMarker = pcall(vehicle.getAIMarkers, vehicle)
        if ok then
            local ax, ay, az = getAxisFromNodes(leftMarker, rightMarker, referenceNode)
            if ax ~= nil then
                return ax, ay, az
            end
        end
    end

    local bestX, bestY, bestZ = nil, nil, nil
    local bestLength = 0
    for _, area in ipairs(areas) do
        local ax, ay, az, length = getAxisFromNodes(area.startNode, area.widthNode, referenceNode)
        if ax ~= nil and length > bestLength then
            bestX, bestY, bestZ = ax, ay, az
            bestLength = length
        end
    end

    return bestX, bestY, bestZ
end

local function getProjection(x, y, z, axisX, axisY, axisZ)
    return x * axisX + y * axisY + z * axisZ
end

local function getAreaProjectionBounds(areas, referenceNode, axisX, axisY, axisZ)
    local minProjection = math.huge
    local maxProjection = -math.huge

    for _, area in ipairs(areas) do
        for _, node in ipairs({area.startNode, area.widthNode, area.heightNode}) do
            local x, y, z = getNodePositionInReference(node, referenceNode)
            if x ~= nil then
                local projection = getProjection(x, y, z, axisX, axisY, axisZ)
                minProjection = math.min(minProjection, projection)
                maxProjection = math.max(maxProjection, projection)
            end
        end
    end

    if minProjection == math.huge or maxProjection == -math.huge then
        return nil, nil
    end

    return minProjection, maxProjection
end

local function collectWorkAreas(vehicle)
    local spec = getSpec(vehicle)
    restoreSyntheticAreaSets(spec)
    spec.areas = {}
    spec.dropAreas = {}

    local workAreas = getWorkAreas(vehicle)
    local referenceNode = vehicle.rootNode
    if workAreas == nil or referenceNode == nil or referenceNode == 0 then
        return false
    end

    for index, workArea in pairs(workAreas) do
        local area = createAreaEntry(workArea, index)
        if area ~= nil then
            if getAreaIsAuxiliary(workArea) then
                if vehicle.spec_mower ~= nil
                    or vehicle.spec_tedder ~= nil
                    or vehicle.spec_windrower ~= nil then
                    table.insert(spec.dropAreas, area)
                end
            else
                table.insert(spec.areas, area)
            end
        end
    end

    if #spec.areas == 0 then
        return false
    end

    local widthAreas, usePlowAxis = getPlowWidthAreas(vehicle, spec.areas)
    local axisX, axisY, axisZ = getWidthAxis(vehicle, widthAreas, referenceNode, usePlowAxis)
    if axisX == nil then
        return false
    end

    local minProjection, maxProjection = getAreaProjectionBounds(widthAreas, referenceNode, axisX, axisY, axisZ)
    if minProjection == nil or maxProjection - minProjection <= 0.01 then
        return false
    end

    spec.referenceNode = referenceNode
    spec.widthAxisX = axisX
    spec.widthAxisY = axisY
    spec.widthAxisZ = axisZ
    spec.widthCenterProjection = (minProjection + maxProjection) * 0.5
    spec.measuredBaseWidth = round2(maxProjection - minProjection)
    spec.baseWidth = spec.measuredBaseWidth
    spec.usePlowWidthAxis = usePlowAxis
    spec.plowAreas = usePlowAxis and widthAreas or nil
    spec.plowPackerAreas = nil
    if usePlowAxis
        and vehicle.spec_plowPacker ~= nil
        and vehicle.spec_plowPacker.packerAvailable == true
        and WorkAreaType.CULTIVATOR ~= nil then
        spec.plowPackerAreas = {}
        for _, area in ipairs(spec.areas) do
            if area.workArea.type == WorkAreaType.CULTIVATOR then
                table.insert(spec.plowPackerAreas, area)
            end
        end
    end

    return true
end

local function updateChangedWorkAreas(vehicle, areas)
    if vehicle.updateWorkAreaWidth == nil then
        return
    end

    local updated = {}
    for _, area in ipairs(areas) do
        local workAreaIndex = area.workAreaIndex
        if workAreaIndex ~= nil and updated[workAreaIndex] ~= true then
            pcall(vehicle.updateWorkAreaWidth, vehicle, workAreaIndex)
            updated[workAreaIndex] = true
        end
    end
end

local function scaleNodeAlongWidthAxis(spec, node, factor, appliedNodes, centerProjection)
    if node == nil or node == 0 or appliedNodes[node] == true then
        return false
    end

    local x, y, z = getNodePositionInReference(node, spec.referenceNode)
    if x == nil then
        return false
    end

    local projection = getProjection(x, y, z, spec.widthAxisX, spec.widthAxisY, spec.widthAxisZ)
    centerProjection = centerProjection or spec.widthCenterProjection
    local targetProjection = centerProjection + (projection - centerProjection) * factor
    local projectionDelta = targetProjection - projection

    local nx = x + spec.widthAxisX * projectionDelta
    local ny = y + spec.widthAxisY * projectionDelta
    local nz = z + spec.widthAxisZ * projectionDelta

    if setNodePositionFromReference(node, spec.referenceNode, nx, ny, nz) then
        appliedNodes[node] = true
        return true
    end

    return false
end

local function scaleAreaNodes(spec, areas, factor, appliedNodes, centerProjection)
    for _, area in ipairs(areas) do
        scaleNodeAlongWidthAxis(spec, area.startNode, factor, appliedNodes, centerProjection)
        scaleNodeAlongWidthAxis(spec, area.widthNode, factor, appliedNodes, centerProjection)
        scaleNodeAlongWidthAxis(spec, area.heightNode, factor, appliedNodes, centerProjection)
    end
end

local function scaleWindrowerAreasAroundCenterGap(spec, areas, factor, appliedNodes)
    local windrowerAreas = {}
    local otherAreas = {}
    local leftInner = -math.huge
    local rightInner = math.huge
    local outerMin = math.huge
    local outerMax = -math.huge

    for _, area in ipairs(areas) do
        if WorkAreaType ~= nil
            and WorkAreaType.WINDROWER ~= nil
            and area.workArea.type == WorkAreaType.WINDROWER then
            local areaMin, areaMax = getAreaProjectionBounds(
                {area},
                spec.referenceNode,
                spec.widthAxisX,
                spec.widthAxisY,
                spec.widthAxisZ
            )
            if areaMin == nil or areaMin <= spec.widthCenterProjection and areaMax >= spec.widthCenterProjection then
                return false
            end

            outerMin = math.min(outerMin, areaMin)
            outerMax = math.max(outerMax, areaMax)
            if areaMax < spec.widthCenterProjection then
                leftInner = math.max(leftInner, areaMax)
            elseif areaMin > spec.widthCenterProjection then
                rightInner = math.min(rightInner, areaMin)
            end
            table.insert(windrowerAreas, area)
        else
            table.insert(otherAreas, area)
        end
    end

    local centerGap = rightInner - leftInner
    local outerWidth = outerMax - outerMin
    local activeWidth = outerWidth - centerGap
    local targetActiveWidth = outerWidth * factor - centerGap
    if #windrowerAreas < 2
        or leftInner == -math.huge
        or rightInner == math.huge
        or centerGap <= 0
        or activeWidth <= 0.01
        or targetActiveWidth <= 0.01 then
        return false
    end

    local sideFactor = targetActiveWidth / activeWidth
    for _, area in ipairs(windrowerAreas) do
        for _, node in ipairs({area.startNode, area.widthNode, area.heightNode}) do
            if node ~= nil and node ~= 0 and appliedNodes[node] ~= true then
                local x, y, z = getNodePositionInReference(node, spec.referenceNode)
                if x ~= nil then
                    local projection = getProjection(
                        x,
                        y,
                        z,
                        spec.widthAxisX,
                        spec.widthAxisY,
                        spec.widthAxisZ
                    )
                    local targetProjection = projection
                    if projection <= leftInner then
                        targetProjection = leftInner + (projection - leftInner) * sideFactor
                    elseif projection >= rightInner then
                        targetProjection = rightInner + (projection - rightInner) * sideFactor
                    end

                    local projectionDelta = targetProjection - projection
                    if setNodePositionFromReference(
                        node,
                        spec.referenceNode,
                        x + spec.widthAxisX * projectionDelta,
                        y + spec.widthAxisY * projectionDelta,
                        z + spec.widthAxisZ * projectionDelta
                    ) then
                        appliedNodes[node] = true
                    end
                end
            end
        end
    end

    scaleAreaNodes(spec, otherAreas, factor, appliedNodes)
    return true
end

local function getSyntheticAreaGeometry(spec, areas)
    local minZ = math.huge
    local maxZ = -math.huge
    local startZTotal = 0
    local heightZTotal = 0
    local count = 0

    for _, area in ipairs(areas) do
        local sx, sy, sz = getNodePositionInReference(area.startNode, spec.referenceNode)
        local wx, _, wz = getNodePositionInReference(area.widthNode, spec.referenceNode)
        local hx, _, hz = getNodePositionInReference(area.heightNode, spec.referenceNode)
        if sx ~= nil and wx ~= nil and hx ~= nil then
            minZ = math.min(minZ, sz, wz, hz)
            maxZ = math.max(maxZ, sz, wz, hz)
            startZTotal = startZTotal + (sz + wz) * 0.5
            heightZTotal = heightZTotal + hz
            count = count + 1
        end
    end

    if count == 0 or maxZ - minZ <= 0.01 then
        return nil
    end

    local firstArea = areas[1]
    local sx, sy = getNodePositionInReference(firstArea.startNode, spec.referenceNode)
    local wx = getNodePositionInReference(firstArea.widthNode, spec.referenceNode)
    if sx == nil or wx == nil then
        return nil
    end

    local direction = wx < sx and -1 or 1
    local halfWidth = spec.currentWidth * 0.5
    local startZ, heightZ = maxZ, minZ
    if startZTotal < heightZTotal then
        startZ, heightZ = minZ, maxZ
    end

    return {
        startX = spec.widthCenterProjection - direction * halfWidth,
        widthX = spec.widthCenterProjection + direction * halfWidth,
        y = sy,
        startZ = startZ,
        heightZ = heightZ
    }
end

local function ensureSyntheticAreaNodes(spec, fieldName, nodeName)
    local areaSet = spec[fieldName]
    if areaSet == nil then
        if createTransformGroup == nil or link == nil then
            return nil
        end

        local parentNode = createTransformGroup("AWW_" .. nodeName)
        local startNode = createTransformGroup("AWW_" .. nodeName .. "Start")
        local widthNode = createTransformGroup("AWW_" .. nodeName .. "Width")
        local heightNode = createTransformGroup("AWW_" .. nodeName .. "Height")
        if parentNode == nil or parentNode == 0
            or startNode == nil or startNode == 0
            or widthNode == nil or widthNode == 0
            or heightNode == nil or heightNode == 0 then
            return nil
        end

        link(spec.referenceNode, parentNode)
        link(parentNode, startNode)
        link(parentNode, widthNode)
        link(parentNode, heightNode)
        areaSet = {
            parentNode = parentNode,
            startNode = startNode,
            widthNode = widthNode,
            heightNode = heightNode
        }
        spec[fieldName] = areaSet
    end

    return areaSet
end

local function configureSyntheticAreaSet(spec, areas, fieldName, nodeName)
    if areas == nil or #areas == 0 then
        return false
    end

    local geometry = getSyntheticAreaGeometry(spec, areas)
    local areaSet = geometry ~= nil and ensureSyntheticAreaNodes(spec, fieldName, nodeName) or nil
    if areaSet == nil then
        return false
    end

    if not setNodePositionFromReference(areaSet.startNode, spec.referenceNode, geometry.startX, geometry.y, geometry.startZ)
        or not setNodePositionFromReference(areaSet.widthNode, spec.referenceNode, geometry.widthX, geometry.y, geometry.startZ)
        or not setNodePositionFromReference(areaSet.heightNode, spec.referenceNode, geometry.startX, geometry.y, geometry.heightZ) then
        return false
    end

    areaSet.active = true
    areaSet.processed = false
    areaSet.members = {}
    areaSet.mappings = {}
    for _, area in ipairs(areas) do
        local workArea = area.workArea
        table.insert(areaSet.mappings, {
            workArea = workArea,
            startNode = workArea.start,
            widthNode = workArea.width,
            heightNode = workArea.height
        })
        areaSet.members[workArea] = true
        workArea.start = areaSet.startNode
        workArea.width = areaSet.widthNode
        workArea.height = areaSet.heightNode
        area.startNode = areaSet.startNode
        area.widthNode = areaSet.widthNode
        area.heightNode = areaSet.heightNode
    end

    return true
end

local function updateSyntheticAreaSetGeometry(spec, areaSet)
    if areaSet == nil or areaSet.active ~= true then
        return
    end

    local originalAreas = {}
    for _, mapping in ipairs(areaSet.mappings or {}) do
        table.insert(originalAreas, {
            startNode = mapping.startNode,
            widthNode = mapping.widthNode,
            heightNode = mapping.heightNode
        })
    end

    local geometry = getSyntheticAreaGeometry(spec, originalAreas)
    if geometry == nil then
        return
    end

    setNodePositionFromReference(areaSet.startNode, spec.referenceNode, geometry.startX, geometry.y, geometry.startZ)
    setNodePositionFromReference(areaSet.widthNode, spec.referenceNode, geometry.widthX, geometry.y, geometry.startZ)
    setNodePositionFromReference(areaSet.heightNode, spec.referenceNode, geometry.startX, geometry.y, geometry.heightZ)
end

local function copySyntheticAreaSetGeometry(spec, sourceAreaSet, targetAreaSet)
    if sourceAreaSet == nil or sourceAreaSet.active ~= true
        or targetAreaSet == nil or targetAreaSet.active ~= true then
        return false
    end

    for _, nodePair in ipairs({
        {sourceAreaSet.startNode, targetAreaSet.startNode},
        {sourceAreaSet.widthNode, targetAreaSet.widthNode},
        {sourceAreaSet.heightNode, targetAreaSet.heightNode}
    }) do
        local x, y, z = getNodePositionInReference(nodePair[1], spec.referenceNode)
        if x == nil or not setNodePositionFromReference(nodePair[2], spec.referenceNode, x, y, z) then
            return false
        end
    end

    return true
end

local function setPlowAreaWidths(spec, appliedNodes)
    if #(spec.plowAreas or {}) > 1
        and configureSyntheticAreaSet(spec, spec.plowAreas, "syntheticPlowArea", "PlowArea") then
        return
    end

    local targets = {}
    local halfWidth = spec.currentWidth * 0.5

    for _, area in ipairs(spec.plowAreas or {}) do
        local sx, sy, sz = getNodePositionInReference(area.startNode, spec.referenceNode)
        local wx, wy, wz = getNodePositionInReference(area.widthNode, spec.referenceNode)
        local hx, hy, hz = getNodePositionInReference(area.heightNode, spec.referenceNode)
        if sx ~= nil and wx ~= nil and hx ~= nil then
            local startProjection = getProjection(sx, sy, sz, spec.widthAxisX, spec.widthAxisY, spec.widthAxisZ)
            local widthProjection = getProjection(wx, wy, wz, spec.widthAxisX, spec.widthAxisY, spec.widthAxisZ)
            local direction = widthProjection < startProjection and -1 or 1
            local targetStartProjection = spec.widthCenterProjection - direction * halfWidth
            local targetWidthProjection = spec.widthCenterProjection + direction * halfWidth
            local startDelta = targetStartProjection - startProjection
            local widthDelta = targetWidthProjection - widthProjection

            table.insert(targets, {
                node = area.startNode,
                x = sx + spec.widthAxisX * startDelta,
                y = sy + spec.widthAxisY * startDelta,
                z = sz + spec.widthAxisZ * startDelta
            })
            table.insert(targets, {
                node = area.widthNode,
                x = wx + spec.widthAxisX * widthDelta,
                y = wy + spec.widthAxisY * widthDelta,
                z = wz + spec.widthAxisZ * widthDelta
            })
            table.insert(targets, {
                node = area.heightNode,
                x = hx + spec.widthAxisX * startDelta,
                y = hy + spec.widthAxisY * startDelta,
                z = hz + spec.widthAxisZ * startDelta
            })
        end
    end

    for _, target in ipairs(targets) do
        if appliedNodes[target.node] ~= true
            and setNodePositionFromReference(target.node, spec.referenceNode, target.x, target.y, target.z) then
            appliedNodes[target.node] = true
        end
    end
end

local function captureDropModeAreas(spec)
    local modeAreas = {}

    for _, dropArea in ipairs(spec.dropAreas) do
        local nodes = {}
        local minProjection = math.huge
        local maxProjection = -math.huge

        for _, node in ipairs({dropArea.startNode, dropArea.widthNode, dropArea.heightNode}) do
            local x, y, z = getNodePositionInReference(node, spec.referenceNode)
            if x ~= nil then
                local projection = getProjection(x, y, z, spec.widthAxisX, spec.widthAxisY, spec.widthAxisZ)
                table.insert(nodes, {node = node, x = x, y = y, z = z, projection = projection})
                minProjection = math.min(minProjection, projection)
                maxProjection = math.max(maxProjection, projection)
            end
        end

        if #nodes >= 2 and maxProjection - minProjection > 0.01 then
            local sourceAreas = {}
            for _, area in ipairs(spec.areas) do
                if area.workArea ~= nil and area.workArea.dropAreaIndex == dropArea.workAreaIndex then
                    table.insert(sourceAreas, area)
                end
            end

            table.insert(modeAreas, {
                nodes = nodes,
                minProjection = minProjection,
                maxProjection = maxProjection,
                sourceAreas = sourceAreas
            })
        end
    end

    return modeAreas
end

local function setDropModeNodePositions(spec, useWindrowDropAreas)
    local changedNodes = 0

    for _, modeArea in ipairs(spec.dropModeAreas or {}) do
        local targetMin = nil
        local targetMax = nil
        if not useWindrowDropAreas then
            targetMin, targetMax = getAreaProjectionBounds(modeArea.sourceAreas, spec.referenceNode, spec.widthAxisX, spec.widthAxisY, spec.widthAxisZ)
            if targetMin == nil then
                targetMin = spec.widthCenterProjection - (spec.currentWidth * 0.5)
                targetMax = spec.widthCenterProjection + (spec.currentWidth * 0.5)
            end
        end

        for _, entry in ipairs(modeArea.nodes) do
            local targetProjection
            if useWindrowDropAreas then
                local modeCenter = (modeArea.minProjection + modeArea.maxProjection) * 0.5
                targetProjection = spec.dropCenterProjection + (entry.projection - modeCenter) * spec.currentFactor
            else
                local ratio = (entry.projection - modeArea.minProjection) / (modeArea.maxProjection - modeArea.minProjection)
                targetProjection = targetMin + ((targetMax - targetMin) * ratio)
            end

            local projectionDelta = targetProjection - entry.projection
            local x = entry.x + spec.widthAxisX * projectionDelta
            local y = entry.y + spec.widthAxisY * projectionDelta
            local z = entry.z + spec.widthAxisZ * projectionDelta
            if setNodePositionFromReference(entry.node, spec.referenceNode, x, y, z) then
                changedNodes = changedNodes + 1
            end
        end
    end

    return changedNodes
end

local function hasNativeMowerModes(vehicle)
    local workModeSpec = vehicle.spec_workMode
    if workModeSpec ~= nil then
        if (tonumber(workModeSpec.stateMax) or 0) > 0 then
            return true
        end

        if type(workModeSpec.workModes) == "table" and #workModeSpec.workModes > 0 then
            return true
        end
    end

    return vehicle.xmlFile ~= nil
        and vehicle.xmlFile.hasProperty ~= nil
        and vehicle.xmlFile:hasProperty("vehicle.workModes")
end

local function synchronizeNativeMowerModeAreas(vehicle, state)
    local workModeSpec = vehicle.spec_workMode
    local workAreaSpec = vehicle.spec_workArea
    if workModeSpec == nil or workAreaSpec == nil or workAreaSpec.workAreas == nil then
        return false
    end

    state = tonumber(state) or tonumber(workModeSpec.state)
    local workMode = state ~= nil and workModeSpec.workModes ~= nil and workModeSpec.workModes[state] or nil
    if workMode == nil or workMode.workAreas == nil then
        return false
    end

    local changed = false
    for _, workAreaMapping in pairs(workMode.workAreas) do
        local workArea = workAreaSpec.workAreas[workAreaMapping.workAreaIndex]
        if workArea ~= nil and workAreaMapping.dropAreaIndex ~= nil then
            workArea.dropWindrowWorkAreaIndex = workAreaMapping.dropAreaIndex
            workArea.dropAreaIndex = workAreaMapping.dropAreaIndex
            changed = true
        end
    end

    return changed
end

local function getNativeMowerDropArea(vehicle, workArea)
    local workModeSpec = vehicle.spec_workMode
    local workAreaSpec = vehicle.spec_workArea
    if workModeSpec == nil or workAreaSpec == nil or workArea == nil then
        return nil
    end

    local state = tonumber(workModeSpec.state)
    local workMode = state ~= nil and workModeSpec.workModes ~= nil and workModeSpec.workModes[state] or nil
    if workMode == nil or workMode.workAreas == nil then
        return nil
    end

    local workAreaIndex = workArea.index
    for _, workAreaMapping in pairs(workMode.workAreas) do
        if workAreaMapping.workAreaIndex == workAreaIndex then
            return workAreaSpec.workAreas[workAreaMapping.dropAreaIndex]
        end
    end

    return nil
end

local function getAreaByWorkAreaIndex(areas, workAreaIndex)
    for _, area in ipairs(areas or {}) do
        if area.workAreaIndex == workAreaIndex then
            return area
        end
    end

    return nil
end

local function restoreWindrowerDropAreaMappings(spec)
    for workArea, dropAreaIndex in pairs(spec.nativeWindrowerDropAreaIndices or {}) do
        workArea.dropWindrowWorkAreaIndex = dropAreaIndex
    end
    spec.singleWindrowDropAreaConfigured = false
    spec.sharedWindrowDropAreaConfigured = false
end

local function getAreaCenterProjection(spec, area)
    local minProjection, maxProjection = getAreaProjectionBounds(
        {area},
        spec.referenceNode,
        spec.widthAxisX,
        spec.widthAxisY,
        spec.widthAxisZ
    )
    return minProjection ~= nil and (minProjection + maxProjection) * 0.5 or nil
end

local function configureSingleWindrowDropArea(vehicle, spec)
    if vehicle.spec_windrower == nil or spec.isBase or hasNativeMowerModes(vehicle) then
        restoreWindrowerDropAreaMappings(spec)
        return
    end

    spec.nativeWindrowerDropAreaIndices = spec.nativeWindrowerDropAreaIndices or {}
    local dropAreaUsageCounts = {}
    local dropAreaCenters = {}
    local windrowerAreaCount = 0
    local totalFlowOffset = 0
    local flowAreaCount = 0

    for _, area in ipairs(spec.areas) do
        local workArea = area.workArea
        if WorkAreaType ~= nil
            and WorkAreaType.WINDROWER ~= nil
            and workArea.type == WorkAreaType.WINDROWER then
            local dropAreaIndex = spec.nativeWindrowerDropAreaIndices[workArea]
            if dropAreaIndex == nil then
                dropAreaIndex = tonumber(workArea.dropWindrowWorkAreaIndex)
                spec.nativeWindrowerDropAreaIndices[workArea] = dropAreaIndex
            end

            local dropArea = getAreaByWorkAreaIndex(spec.dropAreas, dropAreaIndex)
            if dropAreaIndex == nil
                or dropArea == nil then
                restoreWindrowerDropAreaMappings(spec)
                return
            end

            dropAreaUsageCounts[dropAreaIndex] = (dropAreaUsageCounts[dropAreaIndex] or 0) + 1
            windrowerAreaCount = windrowerAreaCount + 1

            local sourceCenter = getAreaCenterProjection(spec, area)
            local dropCenter = getAreaCenterProjection(spec, dropArea)
            if sourceCenter ~= nil and dropCenter ~= nil then
                dropAreaCenters[dropAreaIndex] = dropCenter
                totalFlowOffset = totalFlowOffset + dropCenter - sourceCenter
                flowAreaCount = flowAreaCount + 1
            end
        end
    end

    if windrowerAreaCount < 2 then
        restoreWindrowerDropAreaMappings(spec)
        return
    end

    local sharedDropAreaIndex = nil
    local sharedDropAreaCount = 0
    for dropAreaIndex, usageCount in pairs(dropAreaUsageCounts) do
        if usageCount > 1 then
            sharedDropAreaIndex = dropAreaIndex
            sharedDropAreaCount = sharedDropAreaCount + 1
        end
    end

    if sharedDropAreaCount == 1 then
        for workArea in pairs(spec.nativeWindrowerDropAreaIndices) do
            workArea.dropWindrowWorkAreaIndex = sharedDropAreaIndex
        end
        spec.singleWindrowDropAreaConfigured = true
        spec.sharedWindrowDropAreaConfigured = true
        return
    elseif sharedDropAreaCount > 1 then
        restoreWindrowerDropAreaMappings(spec)
        return
    end

    local flowOffset = flowAreaCount > 0 and totalFlowOffset / flowAreaCount or 0
    local flowDirection = math.abs(flowOffset) > 0.05 and (flowOffset < 0 and -1 or 1) or 0
    local targetDropAreaIndex = nil
    local targetScore = -math.huge
    for dropAreaIndex in pairs(dropAreaUsageCounts) do
        local dropCenter = dropAreaCenters[dropAreaIndex]
        if dropCenter ~= nil then
            local score = flowDirection == 0
                and -math.abs(dropCenter - spec.widthCenterProjection)
                or dropCenter * flowDirection
            if score > targetScore
                or (score == targetScore and (targetDropAreaIndex == nil or dropAreaIndex < targetDropAreaIndex)) then
                targetDropAreaIndex = dropAreaIndex
                targetScore = score
            end
        end
    end

    if targetDropAreaIndex == nil then
        restoreWindrowerDropAreaMappings(spec)
        return
    end

    for workArea in pairs(spec.nativeWindrowerDropAreaIndices) do
        workArea.dropWindrowWorkAreaIndex = targetDropAreaIndex
    end
    spec.singleWindrowDropAreaConfigured = true

end

local function getIntermediateWindrowDropAreas(spec)
    local usageCounts = {}
    local hasSharedDropArea = false
    for _, dropAreaIndex in pairs(spec.nativeWindrowerDropAreaIndices or {}) do
        usageCounts[dropAreaIndex] = (usageCounts[dropAreaIndex] or 0) + 1
        hasSharedDropArea = hasSharedDropArea or usageCounts[dropAreaIndex] > 1
    end

    if not hasSharedDropArea then
        return {}
    end

    local intermediateAreas = {}
    for _, area in ipairs(spec.dropAreas or {}) do
        if usageCounts[area.workAreaIndex] == 1 then
            table.insert(intermediateAreas, area)
        end
    end
    return intermediateAreas
end

local function restoreTedderDropAreaMappings(spec)
    for workArea, dropAreaIndex in pairs(spec.nativeTedderDropAreaIndices or {}) do
        workArea.dropWindrowWorkAreaIndex = dropAreaIndex
    end
    spec.sharedTedderDropAreaConfigured = false
end

local function configureSharedTedderDropArea(vehicle, spec)
    restoreTedderDropAreaMappings(spec)
    if vehicle.spec_tedder == nil or spec.isBase or #spec.dropAreas == 0 then
        return false
    end

    spec.nativeTedderDropAreaIndices = spec.nativeTedderDropAreaIndices or {}
    local targetDropArea = nil
    local targetDropAreaIndex = nil
    local tedderAreaCount = 0

    for _, area in ipairs(spec.areas) do
        local workArea = area.workArea
        if WorkAreaType ~= nil
            and WorkAreaType.TEDDER ~= nil
            and workArea.type == WorkAreaType.TEDDER then
            local dropAreaIndex = spec.nativeTedderDropAreaIndices[workArea]
            if dropAreaIndex == nil then
                dropAreaIndex = tonumber(workArea.dropWindrowWorkAreaIndex)
                spec.nativeTedderDropAreaIndices[workArea] = dropAreaIndex
            end

            local dropArea = getAreaByWorkAreaIndex(spec.dropAreas, dropAreaIndex)
            if dropArea == nil then
                restoreTedderDropAreaMappings(spec)
                return false
            end

            targetDropArea = targetDropArea or dropArea
            targetDropAreaIndex = targetDropAreaIndex or dropAreaIndex
            tedderAreaCount = tedderAreaCount + 1
        end
    end

    if tedderAreaCount == 0 or not configureSyntheticAreaSet(
        spec,
        {targetDropArea},
        "syntheticTedderDropArea",
        "TedderDropArea"
    ) then
        restoreTedderDropAreaMappings(spec)
        return false
    end

    for workArea in pairs(spec.nativeTedderDropAreaIndices) do
        workArea.dropWindrowWorkAreaIndex = targetDropAreaIndex
    end
    spec.sharedTedderDropAreaConfigured = true
    return true
end

local function captureNativeDropArea(spec, dropArea)
    local nodes = {}
    local minProjection = math.huge
    local maxProjection = -math.huge

    for _, node in ipairs({dropArea.startNode, dropArea.widthNode, dropArea.heightNode}) do
        local x, y, z = getNodePositionInReference(node, spec.referenceNode)
        if x ~= nil then
            local projection = getProjection(x, y, z, spec.widthAxisX, spec.widthAxisY, spec.widthAxisZ)
            table.insert(nodes, {node = node, x = x, y = y, z = z, projection = projection})
            minProjection = math.min(minProjection, projection)
            maxProjection = math.max(maxProjection, projection)
        end
    end

    if #nodes < 2 or maxProjection - minProjection <= 0.01 then
        return nil
    end

    return {
        area = dropArea,
        nodes = nodes,
        minProjection = minProjection,
        maxProjection = maxProjection
    }
end

local function configureNativeMowerDropAreas(vehicle, spec)
    spec.nativeMowerDropAreas = nil
    spec.nativeMowerBaseMappings = nil
    spec.nativeMowerSharedDropAreas = nil

    local workModeSpec = vehicle.spec_workMode
    local baseMode = workModeSpec ~= nil and workModeSpec.workModes ~= nil and workModeSpec.workModes[1] or nil
    if baseMode == nil or baseMode.workAreas == nil or #spec.areas < 2 or #spec.dropAreas <= #spec.areas then
        return false
    end

    local dropAreas = {}
    for _, dropArea in ipairs(spec.dropAreas) do
        local captured = captureNativeDropArea(spec, dropArea)
        if captured ~= nil then
            dropAreas[dropArea.workAreaIndex] = captured
        end
    end

    local baseMappings = {}
    local usedBaseDropAreas = {}
    for _, mapping in pairs(baseMode.workAreas) do
        local sourceArea = getAreaByWorkAreaIndex(spec.areas, mapping.workAreaIndex)
        if sourceArea == nil
            or dropAreas[mapping.dropAreaIndex] == nil
            or usedBaseDropAreas[mapping.dropAreaIndex] == true then
            return false
        end

        baseMappings[mapping.workAreaIndex] = mapping.dropAreaIndex
        usedBaseDropAreas[mapping.dropAreaIndex] = true
    end

    local sharedDropAreas = {}
    for _, workMode in ipairs(workModeSpec.workModes) do
        for _, mapping in pairs(workMode.workAreas or {}) do
            if dropAreas[mapping.dropAreaIndex] ~= nil
                and usedBaseDropAreas[mapping.dropAreaIndex] ~= true then
                sharedDropAreas[mapping.dropAreaIndex] = true
            end
        end
    end

    if next(sharedDropAreas) == nil then
        return false
    end

    spec.nativeMowerDropAreas = dropAreas
    spec.nativeMowerBaseMappings = baseMappings
    spec.nativeMowerSharedDropAreas = sharedDropAreas
    return true
end

local function setCapturedDropAreaBounds(spec, captured, targetMin, targetMax, appliedNodes)
    local sourceWidth = captured.maxProjection - captured.minProjection
    if sourceWidth <= 0.01 or targetMin == nil or targetMax == nil then
        return false
    end

    for _, entry in ipairs(captured.nodes) do
        local ratio = (entry.projection - captured.minProjection) / sourceWidth
        local targetProjection = targetMin + (targetMax - targetMin) * ratio
        local projectionDelta = targetProjection - entry.projection
        local x = entry.x + spec.widthAxisX * projectionDelta
        local y = entry.y + spec.widthAxisY * projectionDelta
        local z = entry.z + spec.widthAxisZ * projectionDelta
        if setNodePositionFromReference(entry.node, spec.referenceNode, x, y, z) then
            appliedNodes[entry.node] = true
        end
    end

    return true
end

local function getNativeMowerMode(vehicle, state)
    local workModeSpec = vehicle.spec_workMode
    state = tonumber(state) or (workModeSpec ~= nil and tonumber(workModeSpec.state))
    return state ~= nil and workModeSpec ~= nil and workModeSpec.workModes ~= nil
        and workModeSpec.workModes[state] or nil
end

local function applyNativeMowerDropMode(vehicle, spec, state, appliedNodes)
    local workMode = getNativeMowerMode(vehicle, state)
    if workMode == nil
        or workMode.workAreas == nil
        or spec.nativeMowerDropAreas == nil
        or spec.nativeMowerBaseMappings == nil then
        return false
    end

    appliedNodes = appliedNodes or {}
    local activeSharedArea
    for _, mapping in pairs(workMode.workAreas) do
        if spec.nativeMowerSharedDropAreas[mapping.dropAreaIndex] == true then
            activeSharedArea = spec.nativeMowerDropAreas[mapping.dropAreaIndex]
            break
        end
    end

    for workAreaIndex, dropAreaIndex in pairs(spec.nativeMowerBaseMappings) do
        local sourceArea = getAreaByWorkAreaIndex(spec.areas, workAreaIndex)
        local dropArea = spec.nativeMowerDropAreas[dropAreaIndex]
        if sourceArea ~= nil and dropArea ~= nil then
            local targetMin, targetMax = getAreaProjectionBounds({sourceArea}, spec.referenceNode, spec.widthAxisX, spec.widthAxisY, spec.widthAxisZ)
            if activeSharedArea ~= nil and targetMin ~= nil
                and targetMin <= spec.widthCenterProjection
                and targetMax >= spec.widthCenterProjection then
                targetMin = activeSharedArea.minProjection
                targetMax = activeSharedArea.maxProjection
            end
            setCapturedDropAreaBounds(spec, dropArea, targetMin, targetMax, appliedNodes)
        end
    end

    for dropAreaIndex in pairs(spec.nativeMowerSharedDropAreas) do
        local dropArea = spec.nativeMowerDropAreas[dropAreaIndex]
        if dropArea ~= nil then
            setCapturedDropAreaBounds(spec, dropArea, dropArea.minProjection, dropArea.maxProjection, appliedNodes)
        end
    end

    updateChangedWorkAreas(vehicle, spec.dropAreas)
    return true
end

local function configureSyntheticMowerModes(vehicle, spec)
    spec.syntheticMowerModes = false
    spec.dropModeAreas = nil
    spec.currentDropWidth = nil

    local mowerSpec = vehicle.spec_mower
    local hasNativeMowerToggle = mowerSpec ~= nil
        and mowerSpec.toggleWindrowDropEnableText ~= nil
        and mowerSpec.toggleWindrowDropDisableText ~= nil
    if mowerSpec == nil or hasNativeMowerModes(vehicle) or hasNativeMowerToggle or #spec.dropAreas == 0 then
        return false
    end

    local minProjection, maxProjection = getAreaProjectionBounds(spec.dropAreas, spec.referenceNode, spec.widthAxisX, spec.widthAxisY, spec.widthAxisZ)
    if minProjection == nil or maxProjection - minProjection <= 0.01 then
        return false
    end

    local dropModeAreas = captureDropModeAreas(spec)
    if #dropModeAreas == 0 then
        return false
    end

    spec.syntheticMowerModes = true
    spec.dropModeAreas = dropModeAreas
    spec.dropCenterProjection = (minProjection + maxProjection) * 0.5

    local useWindrowDropAreas = spec.requestedUseWindrowDropAreas
    if useWindrowDropAreas == nil then
        useWindrowDropAreas = mowerSpec.useWindrowDropAreas == true
    end
    mowerSpec.useWindrowDropAreas = useWindrowDropAreas
    return true
end

local function applySyntheticMowerMode(vehicle, useWindrowDropAreas)
    local spec = getSpec(vehicle)
    if spec.syntheticMowerModes ~= true then
        return false
    end

    useWindrowDropAreas = useWindrowDropAreas == true
    local changedNodes = setDropModeNodePositions(spec, useWindrowDropAreas)
    if changedNodes == 0 then
        return false
    end

    vehicle.spec_mower.useWindrowDropAreas = useWindrowDropAreas
    spec.requestedUseWindrowDropAreas = useWindrowDropAreas

    local minProjection, maxProjection = getAreaProjectionBounds(spec.dropAreas, spec.referenceNode, spec.widthAxisX, spec.widthAxisY, spec.widthAxisZ)
    if minProjection ~= nil then
        spec.currentDropWidth = round2(maxProjection - minProjection)
    end

    updateChangedWorkAreas(vehicle, spec.dropAreas)

    return true
end


local function scaleMarkerSet(spec, leftMarker, rightMarker, backMarker, factor, appliedNodes)
    scaleNodeAlongWidthAxis(spec, leftMarker, factor, appliedNodes)
    scaleNodeAlongWidthAxis(spec, rightMarker, factor, appliedNodes)
    scaleNodeAlongWidthAxis(spec, backMarker, factor, appliedNodes)
end

local function setNodeLateralPosition(spec, node, x, z, appliedNodes)
    if node == nil or node == 0 or appliedNodes[node] == true then
        return false
    end

    local _, y, currentZ = getNodePositionInReference(node, spec.referenceNode)
    if y == nil then
        return false
    end

    if setNodePositionFromReference(node, spec.referenceNode, x, y, z or currentZ) then
        appliedNodes[node] = true
        return true
    end

    return false
end

local function setPlowMarkerSet(spec, leftMarker, rightMarker, backMarker, appliedNodes)
    local leftX, _, leftZ = getNodePositionInReference(leftMarker, spec.referenceNode)
    local rightX, _, rightZ = getNodePositionInReference(rightMarker, spec.referenceNode)
    if leftX == nil or rightX == nil then
        return
    end

    local halfWidth = spec.currentWidth * 0.5
    local minX = spec.widthCenterProjection - halfWidth
    local maxX = spec.widthCenterProjection + halfWidth
    local markerZ = (leftZ + rightZ) * 0.5
    if leftX >= rightX then
        setNodeLateralPosition(spec, leftMarker, maxX, markerZ, appliedNodes)
        setNodeLateralPosition(spec, rightMarker, minX, markerZ, appliedNodes)
    else
        setNodeLateralPosition(spec, leftMarker, minX, markerZ, appliedNodes)
        setNodeLateralPosition(spec, rightMarker, maxX, markerZ, appliedNodes)
    end

    setNodeLateralPosition(spec, backMarker, spec.widthCenterProjection, nil, appliedNodes)
end

local function refreshAIMarkerCaches(vehicle, aiSpec)
    aiSpec.aiMarkerWidth = nil

    if aiSpec.aiBaseSetups ~= nil then
        for _, aiSetup in ipairs(aiSpec.aiBaseSetups) do
            aiSetup.aiMarkerWidth = nil
        end
    end

    if vehicle.updateAIMarkerWidth ~= nil then
        pcall(vehicle.updateAIMarkerWidth, vehicle)
    end

    aiSpec.inputAttacherJointToMarkerOffset = {}
    if vehicle.calcAIMarkerAttacherJointOffset ~= nil then
        if aiSpec.leftMarker ~= nil and aiSpec.rightMarker ~= nil and aiSpec.backMarker ~= nil then
            pcall(vehicle.calcAIMarkerAttacherJointOffset, vehicle, aiSpec.leftMarker, aiSpec.rightMarker, aiSpec.backMarker)
        end

        if aiSpec.aiBaseSetups ~= nil then
            for _, aiSetup in ipairs(aiSpec.aiBaseSetups) do
                if aiSetup.leftMarker ~= nil and aiSetup.rightMarker ~= nil and aiSetup.backMarker ~= nil then
                    pcall(vehicle.calcAIMarkerAttacherJointOffset, vehicle, aiSetup.leftMarker, aiSetup.rightMarker, aiSetup.backMarker)
                end
            end
        end
    end

    if vehicle.updateFieldCropsQuery ~= nil then
        pcall(vehicle.updateFieldCropsQuery, vehicle)
    end
end

local function applyAIMarkerWidth(vehicle, spec, factor, appliedNodes)
    local aiSpec = vehicle.spec_aiImplement
    if aiSpec == nil then
        return
    end

    local applyMarkerSet = scaleMarkerSet
    if spec.usePlowWidthAxis then
        applyMarkerSet = function(unusedSpec, leftMarker, rightMarker, backMarker, unusedFactor, nodes)
            setPlowMarkerSet(spec, leftMarker, rightMarker, backMarker, nodes)
        end
    end

    applyMarkerSet(spec, aiSpec.leftMarker, aiSpec.rightMarker, aiSpec.backMarker, factor, appliedNodes)
    applyMarkerSet(spec, aiSpec.sizeLeftMarker, aiSpec.sizeRightMarker, aiSpec.sizeBackMarker, factor, appliedNodes)

    if aiSpec.aiBaseSetups ~= nil then
        for _, aiSetup in ipairs(aiSpec.aiBaseSetups) do
            applyMarkerSet(spec, aiSetup.leftMarker, aiSetup.rightMarker, aiSetup.backMarker, factor, appliedNodes)
            applyMarkerSet(spec, aiSetup.sizeLeftMarker, aiSetup.sizeRightMarker, aiSetup.sizeBackMarker, factor, appliedNodes)
        end
    end

    refreshAIMarkerCaches(vehicle, aiSpec)
end

local function scaleSprayerUsageWidth(spec, usageScale, factor)
    if usageScale == nil
        or usageScale.workAreaIndex ~= nil
        or type(usageScale.workingWidth) ~= "number" then
        return
    end

    spec.sprayerBaseUsageWidths = spec.sprayerBaseUsageWidths or {}
    local baseWidth = spec.sprayerBaseUsageWidths[usageScale]
    if baseWidth == nil then
        baseWidth = usageScale.workingWidth
        spec.sprayerBaseUsageWidths[usageScale] = baseWidth
    end

    usageScale.workingWidth = baseWidth * factor
end

local function applySprayerUsageWidths(vehicle, spec, factor)
    local sprayerSpec = vehicle.spec_sprayer
    if sprayerSpec == nil then
        return
    end

    scaleSprayerUsageWidth(spec, sprayerSpec.usageScale, factor)
    for _, sprayType in ipairs(sprayerSpec.sprayTypes or {}) do
        scaleSprayerUsageWidth(spec, sprayType.usageScale, factor)
    end
end

local function isValidEffectNode(node)
    if type(node) ~= "number" or node == 0 then
        return false
    end

    if entityExists ~= nil then
        local ok, exists = pcall(entityExists, node)
        if ok and exists ~= true then
            return false
        end
    end

    return true
end

local function effectIsA(effect, effectClass)
    if effectClass == nil or type(effect) ~= "table" or type(effect.isa) ~= "function" then
        return false
    end

    local ok, result = pcall(effect.isa, effect, effectClass)
    return ok and result == true
end

local function isSupportedVisualEffect(effect)
    return effectIsA(effect, ShaderPlaneEffect)
        or effectIsA(effect, MotionPathEffect)
        or (type(effect) == "table" and type(effect.getIsSharedEffectMatching) == "function")
end

local function addEffectNode(nodes, seen, node, effectData)
    if not isValidEffectNode(node) or seen[node] == true then
        return
    end

    seen[node] = true
    table.insert(nodes, {node = node, effectData = effectData})
end

local function addEffectObjects(nodes, seen, effects)
    for _, effect in pairs(effects or {}) do
        if isSupportedVisualEffect(effect) then
            local node = effect.linkNode
            if not isValidEffectNode(node) then
                node = effect.effectNode
            end
            if not isValidEffectNode(node) then
                node = effect.node
            end
            addEffectNode(nodes, seen, node)
        end
    end
end

local function getActiveSprayType(vehicle)
    if vehicle.getActiveSprayType == nil then
        return nil
    end

    local ok, sprayType = pcall(vehicle.getActiveSprayType, vehicle)
    return ok and sprayType or nil
end

local function collectSprayerVisualEffectNodes(vehicle)
    local nodes = {}
    local seen = {}
    local extendedNodes = AdjustSuitePrecisionFarming.getVisualEffectNodes(vehicle)
    if extendedNodes ~= nil then
        for _, entry in pairs(extendedNodes) do
            addEffectNode(nodes, seen, entry.node, entry.effectData)
        end
        return nodes
    end

    local sprayerSpec = vehicle.spec_sprayer
    if sprayerSpec ~= nil then
        addEffectObjects(nodes, seen, sprayerSpec.effects)
        local activeSprayType = getActiveSprayType(vehicle)
        if activeSprayType ~= nil then
            addEffectObjects(nodes, seen, activeSprayType.effects)
        else
            for _, sprayType in pairs(sprayerSpec.sprayTypes or {}) do
                addEffectObjects(nodes, seen, sprayType.effects)
            end
        end
    end

    return nodes
end

local function getNodeScaleSafe(node)
    if getScale == nil then
        return nil
    end

    local ok, x, y, z = pcall(getScale, node)
    if ok and type(x) == "number" and type(y) == "number" and type(z) == "number" then
        return x, y, z
    end

    return nil
end

local function getWidthAlignedScaleAxis(spec, node)
    if localDirectionToLocal == nil then
        return nil
    end

    local axes = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}
    local bestIndex = nil
    local bestAlignment = -1

    for index, axis in ipairs(axes) do
        local ok, x, y, z = pcall(localDirectionToLocal, node, spec.referenceNode, axis[1], axis[2], axis[3])
        if ok and type(x) == "number" and type(y) == "number" and type(z) == "number" then
            local length = distance3(0, 0, 0, x, y, z)
            if length > 0.0001 then
                local alignment = math.abs(getProjection(
                    x / length,
                    y / length,
                    z / length,
                    spec.widthAxisX,
                    spec.widthAxisY,
                    spec.widthAxisZ
                ))
                if alignment > bestAlignment then
                    bestAlignment = alignment
                    bestIndex = index
                end
            end
        end
    end

    return bestIndex
end

local function getVisualEffectBaseTransform(spec, node)
    spec.visualEffectBaseTransforms = spec.visualEffectBaseTransforms or {}
    local base = spec.visualEffectBaseTransforms[node]
    if base ~= nil then
        return base
    end

    local x, y, z = getNodePositionInReference(node, spec.referenceNode)
    local scaleX, scaleY, scaleZ = getNodeScaleSafe(node)
    if x == nil or scaleX == nil then
        return nil
    end

    base = {
        x = x,
        y = y,
        z = z,
        scaleX = scaleX,
        scaleY = scaleY,
        scaleZ = scaleZ,
        scaleAxis = getWidthAlignedScaleAxis(spec, node)
    }
    spec.visualEffectBaseTransforms[node] = base
    return base
end

local function scaleEffectNodeGeometry(node, factor, base)
    if setScale == nil then
        return false
    end

    local scaleX, scaleY, scaleZ = base.scaleX, base.scaleY, base.scaleZ
    local axis = base.scaleAxis
    if axis == nil then
        return false
    end

    if axis == 1 then
        scaleX = scaleX * factor
    elseif axis == 2 then
        scaleY = scaleY * factor
    else
        scaleZ = scaleZ * factor
    end

    local ok = pcall(setScale, node, scaleX, scaleY, scaleZ)
    return ok == true
end

local function scaleVisualEffectNode(spec, node, factor)
    local base = getVisualEffectBaseTransform(spec, node)
    if base == nil then
        return false
    end

    local projection = getProjection(base.x, base.y, base.z, spec.widthAxisX, spec.widthAxisY, spec.widthAxisZ)
    local targetProjection = spec.widthCenterProjection + (projection - spec.widthCenterProjection) * factor
    local projectionDelta = targetProjection - projection
    local positionChanged = setNodePositionFromReference(
        node,
        spec.referenceNode,
        base.x + spec.widthAxisX * projectionDelta,
        base.y + spec.widthAxisY * projectionDelta,
        base.z + spec.widthAxisZ * projectionDelta
    )

    return scaleEffectNodeGeometry(node, factor, base) or positionChanged
end

local function resetExtendedEffectPosition(effectData)
    if effectData == nil or getWorldTranslation == nil then
        return
    end

    local ok, x, y, z = pcall(getWorldTranslation, effectData.effectNode)
    if ok and type(x) == "number" and type(y) == "number" and type(z) == "number" then
        effectData.lastWorldTranslation = effectData.lastWorldTranslation or {}
        effectData.lastWorldTranslation[1] = x
        effectData.lastWorldTranslation[2] = y
        effectData.lastWorldTranslation[3] = z
    end
end

local function getVisualEffectPoseIsReady(vehicle)
    local foldableSpec = vehicle.spec_foldable
    if foldableSpec == nil or foldableSpec.hasFoldingParts ~= true then
        return true
    end

    if math.abs(tonumber(foldableSpec.foldMoveDirection) or 0) > 0.001 then
        return false
    end

    if vehicle.getIsUnfolded ~= nil then
        local ok, isUnfolded = pcall(vehicle.getIsUnfolded, vehicle)
        if ok then
            return isUnfolded == true
        end
    end

    return true
end

local function applyVisualEffectWidth(vehicle, spec)
    if vehicle.isClient ~= true or spec.isBase then
        return true
    end

    local nodes = collectSprayerVisualEffectNodes(vehicle)
    for _, entry in ipairs(nodes) do
        if scaleVisualEffectNode(spec, entry.node, spec.currentFactor) then
            resetExtendedEffectPosition(entry.effectData)
        end
    end

    return true
end

local function getCurrentDisplayWidth(vehicle, spec)
    if spec.referenceNode == nil then
        return spec.currentWidth
    end

    if vehicle.spec_windrower ~= nil or vehicle.spec_shovel ~= nil then
        return spec.currentWidth
    end

    if vehicle.getAIMarkers ~= nil then
        local ok, leftMarker, rightMarker, _, _, markerWidth = pcall(vehicle.getAIMarkers, vehicle)
        if ok then
            markerWidth = tonumber(markerWidth)
            if markerWidth ~= nil and markerWidth > 0 then
                return round2(markerWidth)
            end

            local _, _, _, markerDistance = getAxisFromNodes(leftMarker, rightMarker, spec.referenceNode)
            if markerDistance ~= nil then
                return round2(markerDistance)
            end
        end
    end

    return spec.currentWidth
end

local function setCurrentWidthState(vehicle, spec, factor, measuredBaseWidth)
    local configuredBaseWidth = getConfiguredWorkingWidth(vehicle)
    spec.baseWidth = round2(configuredBaseWidth > 0 and configuredBaseWidth or measuredBaseWidth)
    if spec.baseWidth <= 0 then
        return false
    end

    spec.currentOffset = clampOffset(getSelectedOffset(vehicle))
    spec.currentFactor = factor
    spec.currentWidth = round2(spec.baseWidth * factor)
    spec.isBase = spec.currentOffset == 0
    if spec.isBase then
        spec.currentWidth = spec.baseWidth
    end
    return true
end

local function applyLevelerWidth(vehicle, spec, factor)
    local levelerNodes = vehicle.spec_leveler ~= nil and vehicle.spec_leveler.nodes or nil
    if levelerNodes == nil or #levelerNodes == 0 then
        return false
    end

    local measuredBaseWidth = 0
    for _, levelerNode in ipairs(levelerNodes) do
        levelerNode.AWWBaseWidth = levelerNode.AWWBaseWidth or tonumber(levelerNode.width)
        levelerNode.AWWBaseMinDropWidth = levelerNode.AWWBaseMinDropWidth or tonumber(levelerNode.minDropWidth)
        levelerNode.AWWBaseMaxDropWidth = levelerNode.AWWBaseMaxDropWidth or tonumber(levelerNode.maxDropWidth)

        local baseWidth = levelerNode.AWWBaseWidth
        if baseWidth ~= nil and baseWidth > 0 then
            measuredBaseWidth = math.max(measuredBaseWidth, baseWidth)
            levelerNode.width = baseWidth * factor
            levelerNode.halfWidth = levelerNode.width * 0.5
        end

        local baseMinDropWidth = levelerNode.AWWBaseMinDropWidth
        if baseMinDropWidth ~= nil and baseMinDropWidth > 0 then
            levelerNode.minDropWidth = baseMinDropWidth * factor
            levelerNode.halfMinDropWidth = levelerNode.minDropWidth * 0.5
        end

        local baseMaxDropWidth = levelerNode.AWWBaseMaxDropWidth
        if baseMaxDropWidth ~= nil and baseMaxDropWidth > 0 then
            levelerNode.maxDropWidth = baseMaxDropWidth * factor
            levelerNode.halfMaxDropWidth = levelerNode.maxDropWidth * 0.5
        end
    end

    return setCurrentWidthState(vehicle, spec, factor, measuredBaseWidth)
end

local function applyBunkerSiloCompacterWidth(vehicle, spec, factor)
    local compacterSpec = vehicle.spec_bunkerSiloCompacter
    if compacterSpec == nil then
        return false
    end

    compacterSpec.AWWBaseScale = compacterSpec.AWWBaseScale or tonumber(compacterSpec.scale)
    local baseScale = compacterSpec.AWWBaseScale
    if baseScale == nil or baseScale <= 0 then
        return false
    end

    compacterSpec.scale = baseScale * factor
    return setCurrentWidthState(vehicle, spec, factor, 0)
end

local function applyShovelWidth(vehicle, spec, factor)
    local shovelNodes = vehicle.spec_shovel ~= nil and vehicle.spec_shovel.shovelNodes or nil
    if shovelNodes == nil or #shovelNodes == 0 then
        return false
    end

    local measuredBaseWidth = 0
    for _, shovelNode in ipairs(shovelNodes) do
        shovelNode.AWWBaseWidth = shovelNode.AWWBaseWidth or tonumber(shovelNode.width)
        shovelNode.AWWBaseFillLitersPerSecond = shovelNode.AWWBaseFillLitersPerSecond
            or tonumber(shovelNode.fillLitersPerSecond)

        local baseWidth = shovelNode.AWWBaseWidth
        if baseWidth ~= nil and baseWidth > 0 then
            shovelNode.width = baseWidth * factor
            measuredBaseWidth = math.max(measuredBaseWidth, baseWidth)
        end

        local baseFillLitersPerSecond = shovelNode.AWWBaseFillLitersPerSecond
        if baseFillLitersPerSecond ~= nil and baseFillLitersPerSecond > 0
            and baseFillLitersPerSecond < math.huge then
            shovelNode.fillLitersPerSecond = baseFillLitersPerSecond * factor
        end
    end

    return measuredBaseWidth > 0 and setCurrentWidthState(vehicle, spec, factor, measuredBaseWidth)
end

local function getSprayTypeDisplayWidth(vehicle, sprayType)
    local usageScale = sprayType ~= nil and sprayType.usageScale or nil
    if usageScale == nil then
        return nil
    end

    if usageScale.workAreaIndex ~= nil and vehicle.getWorkAreaWidth ~= nil then
        local ok, width = pcall(vehicle.getWorkAreaWidth, vehicle, usageScale.workAreaIndex)
        width = ok and tonumber(width) or nil
        if width ~= nil and width > 0 then
            return round2(width)
        end
    end

    local width = tonumber(usageScale.workingWidth)
    return width ~= nil and width > 0 and round2(width) or nil
end

local function sprayTypeMatchesCurrentConfiguration(vehicle, sprayType)
    if sprayType == nil or sprayType.hasRequiredFoldingConfiguration == false then
        return false
    end

    if sprayType.foldMinLimit ~= nil and sprayType.foldMaxLimit ~= nil then
        local foldAnimTime = vehicle.spec_foldable ~= nil and vehicle.spec_foldable.foldAnimTime or nil
        if foldAnimTime ~= nil
            and (foldAnimTime < sprayType.foldMinLimit or foldAnimTime > sprayType.foldMaxLimit) then
            return false
        end
    end

    return type(sprayType.fillTypes) == "table" and #sprayType.fillTypes > 0
end

local function getDisplayWidths(vehicle, spec)
    local widths = {}

    if vehicle.spec_sprayer ~= nil then
        for _, sprayType in ipairs(vehicle.spec_sprayer.sprayTypes or {}) do
            if sprayTypeMatchesCurrentConfiguration(vehicle, sprayType) then
                local width = getSprayTypeDisplayWidth(vehicle, sprayType)
                if width ~= nil then
                    local isDuplicate = false
                    for _, existingWidth in ipairs(widths) do
                        if math.abs(existingWidth - width) < 0.005 then
                            isDuplicate = true
                            break
                        end
                    end

                    if not isDuplicate then
                        table.insert(widths, width)
                    end
                end
            end
        end
    end

    if #widths < 2 then
        return {getCurrentDisplayWidth(vehicle, spec)}
    end

    table.sort(widths)
    return widths
end

local function formatDisplayWidths(vehicle, spec)
    local unitText = g_i18n:getText("CONFIG_AS_M")
    local values = {}
    for _, width in ipairs(getDisplayWidths(vehicle, spec)) do
        table.insert(values, string.format("%.2f %s", width, unitText))
    end

    return table.concat(values, " - ")
end

local function applyWidth(vehicle)
    if not Suite.getIsModuleEnabled("AWW") then
        return false
    end

    local spec = getSpec(vehicle)
    local offset = getSelectedOffset(vehicle)
    local factor = getFactorFromOffset(offset)

    if not collectWorkAreas(vehicle) then
        return applyShovelWidth(vehicle, spec, factor)
            or applyLevelerWidth(vehicle, spec, factor)
            or applyBunkerSiloCompacterWidth(vehicle, spec, factor)
    end

    if not setCurrentWidthState(vehicle, spec, factor, spec.baseWidth) then
        return false
    end

    configureSingleWindrowDropArea(vehicle, spec)
    local appliedNodes = {}
    local areaFactor = factor
    if vehicle.spec_tedder ~= nil and not spec.isBase
        and spec.measuredBaseWidth ~= nil and spec.measuredBaseWidth > 0 then
        areaFactor = spec.currentWidth / spec.measuredBaseWidth
    end

    if not spec.isBase then
        local changedAreas = spec.areas
        if spec.usePlowWidthAxis then
            setPlowAreaWidths(spec, appliedNodes)
            changedAreas = {}
            for _, area in ipairs(spec.plowAreas or {}) do
                table.insert(changedAreas, area)
            end
            if configureSyntheticAreaSet(spec, spec.plowPackerAreas, "syntheticPlowPackerArea", "PlowPackerArea") then
                for _, area in ipairs(spec.plowPackerAreas) do
                    table.insert(changedAreas, area)
                end
            end
        else
            if spec.sharedWindrowDropAreaConfigured ~= true
                or not scaleWindrowerAreasAroundCenterGap(spec, spec.areas, areaFactor, appliedNodes) then
                scaleAreaNodes(spec, spec.areas, areaFactor, appliedNodes)
            end
        end

        applyAIMarkerWidth(vehicle, spec, areaFactor, appliedNodes)
        updateChangedWorkAreas(vehicle, changedAreas)
    end

    local sharedTedderDropArea = configureSharedTedderDropArea(vehicle, spec)
    applySprayerUsageWidths(vehicle, spec, factor)
    spec.visualEffectsPending = vehicle.spec_sprayer ~= nil and not spec.isBase

    if configureSyntheticMowerModes(vehicle, spec) then
        applySyntheticMowerMode(vehicle, vehicle.spec_mower.useWindrowDropAreas)
    elseif not spec.isBase and hasNativeMowerModes(vehicle) and configureNativeMowerDropAreas(vehicle, spec) then
        applyNativeMowerDropMode(vehicle, spec, nil, appliedNodes)
    elseif not spec.isBase
        and (vehicle.spec_windrower == nil or spec.singleWindrowDropAreaConfigured ~= true)
        and not sharedTedderDropArea then
        local dropAreas = spec.dropAreas
        local dropAreaFactor = areaFactor
        local dropAreaCenter = nil
        if vehicle.spec_windrower ~= nil then
            dropAreas = getIntermediateWindrowDropAreas(spec)
        elseif vehicle.spec_tedder ~= nil then
            local minProjection, maxProjection = getAreaProjectionBounds(
                dropAreas,
                spec.referenceNode,
                spec.widthAxisX,
                spec.widthAxisY,
                spec.widthAxisZ
            )
            if minProjection ~= nil and maxProjection - minProjection > 0.01 then
                dropAreaFactor = spec.currentWidth / (maxProjection - minProjection)
                dropAreaCenter = (minProjection + maxProjection) * 0.5
            end
        end
        scaleAreaNodes(spec, dropAreas, dropAreaFactor, appliedNodes, dropAreaCenter)
        updateChangedWorkAreas(vehicle, dropAreas)
    end

    if spec.syntheticMowerModes ~= true and hasNativeMowerModes(vehicle) then
        synchronizeNativeMowerModeAreas(vehicle)
    end

    return true
end

function AWW.prerequisitesPresent(specializations)
    if Pickup ~= nil and SpecializationUtil.hasSpecialization(Pickup, specializations) then
        return false
    end

    return (WorkArea ~= nil and SpecializationUtil.hasSpecialization(WorkArea, specializations))
        or (Leveler ~= nil and SpecializationUtil.hasSpecialization(Leveler, specializations))
        or (BunkerSiloCompacter ~= nil and SpecializationUtil.hasSpecialization(BunkerSiloCompacter, specializations))
        or (Shovel ~= nil and SpecializationUtil.hasSpecialization(Shovel, specializations))
end

function AWW.initSpecialization()
    Vehicle.xmlSchemaSavegame:register(XMLValueType.BOOL, "vehicles.vehicle(?).FS25_AdjustSuite.AWW#useWindrowDropAreas", "AWW generated mower drop mode")
end

function AWW.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", AWW)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", AWW)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", AWW)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", AWW)
    SpecializationUtil.registerEventListener(vehicleType, "onStartWorkAreaProcessing", AWW)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", AWW)
    SpecializationUtil.registerEventListener(vehicleType, "onChangedFillType", AWW)
    SpecializationUtil.registerEventListener(vehicleType, "onSprayTypeChange", AWW)
    SpecializationUtil.registerEventListener(vehicleType, "onTurnedOn", AWW)
    SpecializationUtil.registerEventListener(vehicleType, "onTurnedOff", AWW)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", AWW)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", AWW)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", AWW)
    SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", AWW)
end

function AWW.registerOverwrittenFunctions(vehicleType)
    if Plow ~= nil and SpecializationUtil.hasSpecialization(Plow, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "processPlowArea", AWW.processPlowArea)
    end
    if Cultivator ~= nil and SpecializationUtil.hasSpecialization(Cultivator, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "processCultivatorArea", AWW.processCultivatorArea)
    end
    if Mower ~= nil and SpecializationUtil.hasSpecialization(Mower, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "setUseMowerWindrowDropAreas", AWW.setUseMowerWindrowDropAreas)
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "getDropArea", AWW.getDropArea)
    end
    if WorkMode ~= nil and SpecializationUtil.hasSpecialization(WorkMode, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "setWorkMode", AWW.setWorkMode)
    end
end

local function processSyntheticArea(superFunc, vehicle, workArea, dt, areaSet)
    if areaSet ~= nil and areaSet.active == true and areaSet.members[workArea] == true then
        if areaSet.processed == true then
            return 0, 0
        end

        areaSet.processed = true
    end

    return superFunc(vehicle, workArea, dt)
end

function AWW:processPlowArea(superFunc, workArea, dt)
    return processSyntheticArea(superFunc, self, workArea, dt, getSpec(self).syntheticPlowArea)
end

function AWW:processCultivatorArea(superFunc, workArea, dt)
    return processSyntheticArea(superFunc, self, workArea, dt, getSpec(self).syntheticPlowPackerArea)
end

function AWW:onStartWorkAreaProcessing(dt, workAreas)
    local spec = getSpec(self)
    if spec.syntheticPlowArea ~= nil then
        updateSyntheticAreaSetGeometry(spec, spec.syntheticPlowArea)
        spec.syntheticPlowArea.processed = false
    end
    if spec.syntheticPlowPackerArea ~= nil then
        if not copySyntheticAreaSetGeometry(spec, spec.syntheticPlowArea, spec.syntheticPlowPackerArea) then
            updateSyntheticAreaSetGeometry(spec, spec.syntheticPlowPackerArea)
        end
        spec.syntheticPlowPackerArea.processed = false
    end
    if spec.syntheticTedderDropArea ~= nil then
        updateSyntheticAreaSetGeometry(spec, spec.syntheticTedderDropArea)
    end
end

function AWW:onLoad(savegame)
    if not Suite.getIsModuleEnabled("AWW") or self.spec_pickup ~= nil then
        return
    end

    local spec = getSpec(self)
    spec.pendingApply = true
    spec.actionEvents = {}

    if savegame ~= nil and not savegame.resetVehicles then
        spec.requestedUseWindrowDropAreas = savegame.xmlFile:getValue(savegame.key .. SAVEGAME_PATH)
    end
end

local function queueSprayerVisualEffectUpdate(vehicle)
    if vehicle.isClient == true and vehicle.spec_sprayer ~= nil then
        local spec = getSpec(vehicle)
        if spec.currentOffset ~= nil and not spec.isBase then
            spec.visualEffectsPending = true
        end
    end
end

function AWW:onChangedFillType(fillUnitIndex, fillTypeIndex, oldFillTypeIndex)
    queueSprayerVisualEffectUpdate(self)
    AdjustSuitePrecisionFarming.stopLimeFallback(self, getSpec(self))
end

function AWW:onSprayTypeChange(sprayType)
    queueSprayerVisualEffectUpdate(self)
    AdjustSuitePrecisionFarming.stopLimeFallback(self, getSpec(self))
end

function AWW:onTurnedOn()
    queueSprayerVisualEffectUpdate(self)
end

function AWW:onTurnedOff()
    AdjustSuitePrecisionFarming.stopLimeFallback(self, getSpec(self))
end

function AWW:onPostLoad(savegame)
    if not Suite.getIsModuleEnabled("AWW") then
        return
    end

    local spec = getSpec(self)
    local waitForNativeMower = self.spec_mower ~= nil
        and self.spec_foldable ~= nil
        and hasNativeMowerModes(self)
        and not getIsLoweredForWork(self)
    local waitForWidthVisuals = getSelectedOffset(self) ~= 0
        and (self.spec_windrower ~= nil or self.spec_tedder ~= nil)
        and self.spec_foldable ~= nil
        and not getVisualEffectPoseIsReady(self)

    if spec.pendingApply == true and not waitForNativeMower and not waitForWidthVisuals and applyWidth(self) then
        spec.pendingApply = false
    end

    if AdjustSuiteCourseplay ~= nil then
        AdjustSuiteCourseplay.update(self)
    end

end

local function getMowerDropModeText(useWindrowDropAreas)
    if useWindrowDropAreas == true then
        return g_i18n:getText("ACTION_AWW_SWATH")
    end

    return g_i18n:getText("ACTION_AWW_BROAD")
end

local function updateMowerDropModeActionText(vehicle)
    local spec = getSpec(vehicle)
    local actionEvent = spec.actionEvents ~= nil and spec.actionEvents[InputAction.TOGGLE_WORKMODE] or nil
    if actionEvent == nil then
        return
    end

    local useWindrowDropAreas = vehicle.spec_mower.useWindrowDropAreas == true
    local textKey = useWindrowDropAreas and "ACTION_AWW_BROAD" or "ACTION_AWW_SWATH"
    g_inputBinding:setActionEventText(actionEvent.actionEventId, g_i18n:getText(textKey))
end

local function updateNativeMowerModeAction(vehicle)
    local workModeSpec = vehicle.spec_workMode
    if workModeSpec == nil
        or (tonumber(workModeSpec.stateMax) or 0) <= 1
        or workModeSpec.actionEvents == nil then
        return
    end

    local actionEvent = workModeSpec.actionEvents[InputAction.TOGGLE_WORKMODE]
    if actionEvent == nil or actionEvent.actionEventId == nil then
        return
    end

    local isAllowed = true
    if vehicle.getIsWorkModeChangeAllowed ~= nil then
        local ok, result = pcall(vehicle.getIsWorkModeChangeAllowed, vehicle)
        isAllowed = ok and result == true
    end

    g_inputBinding:setActionEventActive(actionEvent.actionEventId, isAllowed)
end

function AWW.actionEventToggleMowerDropMode(vehicle, actionName, inputValue, callbackState, isAnalog)
    local mowerSpec = vehicle.spec_mower
    if mowerSpec ~= nil and vehicle.setUseMowerWindrowDropAreas ~= nil then
        vehicle:setUseMowerWindrowDropAreas(not mowerSpec.useWindrowDropAreas)
    end
end

function AWW:setUseMowerWindrowDropAreas(superFunc, useWindrowDropAreas, noEventSend)
    local result = superFunc(self, useWindrowDropAreas, noEventSend)
    local spec = getSpec(self)

    if spec.syntheticMowerModes == true then
        applySyntheticMowerMode(self, useWindrowDropAreas)
        updateMowerDropModeActionText(self)
    end

    return result
end

function AWW:getDropArea(superFunc, workArea)
    if not Suite.getIsModuleEnabled("AWW") then
        return superFunc(self, workArea)
    end

    local spec = getSpec(self)
    if spec.syntheticMowerModes ~= true and hasNativeMowerModes(self) then
        local dropArea = getNativeMowerDropArea(self, workArea)
        if dropArea ~= nil then
            return dropArea
        end
    end

    return superFunc(self, workArea)
end

function AWW:setWorkMode(superFunc, state, noEventSend)
    local result = superFunc(self, state, noEventSend)
    if not Suite.getIsModuleEnabled("AWW") then
        return result
    end

    local spec = getSpec(self)

    if spec.syntheticMowerModes ~= true and self.spec_mower ~= nil then
        synchronizeNativeMowerModeAreas(self, state)
        if not spec.isBase then
            applyNativeMowerDropMode(self, spec, state)
        end
    end

    return result
end

function AWW:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if self.isClient ~= true or not Suite.getIsModuleEnabled("AWW") then
        return
    end

    local spec = getSpec(self)
    self:clearActionEventsTable(spec.actionEvents)

    if spec.syntheticMowerModes ~= true or isActiveForInputIgnoreSelection ~= true then
        return
    end

    local _, actionEventId
    if self.addPoweredActionEvent ~= nil then
        _, actionEventId = self:addPoweredActionEvent(spec.actionEvents, InputAction.TOGGLE_WORKMODE, self, AWW.actionEventToggleMowerDropMode, false, true, false, true, nil)
    else
        _, actionEventId = self:addActionEvent(spec.actionEvents, InputAction.TOGGLE_WORKMODE, self, AWW.actionEventToggleMowerDropMode, false, true, false, true, nil)
    end

    if actionEventId ~= nil then
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_NORMAL)
        updateMowerDropModeActionText(self)
    end
end

function AWW:onWriteStream(streamId, connection)
    local spec = getSpec(self)
    local useWindrowDropAreas = Suite.getIsModuleEnabled("AWW")
        and spec.syntheticMowerModes == true
        and self.spec_mower ~= nil
        and self.spec_mower.useWindrowDropAreas == true
    streamWriteBool(streamId, useWindrowDropAreas)
end

function AWW:onReadStream(streamId, connection)
    local spec = getSpec(self)
    local useWindrowDropAreas = streamReadBool(streamId)
    spec.requestedUseWindrowDropAreas = useWindrowDropAreas

    if Suite.getIsModuleEnabled("AWW")
        and spec.syntheticMowerModes == true and self.spec_mower ~= nil then
        applySyntheticMowerMode(self, useWindrowDropAreas)
    end

    if AdjustSuiteCourseplay ~= nil then
        AdjustSuiteCourseplay.update(self)
    end
end

function AWW:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = getSpec(self)
    if Suite.getIsModuleEnabled("AWW")
        and spec.syntheticMowerModes == true and self.spec_mower ~= nil then
        xmlFile:setValue(key .. "#useWindrowDropAreas", self.spec_mower.useWindrowDropAreas == true)
    end
end

function AWW:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if not Suite.getIsModuleEnabled("AWW") then
        return
    end

    local spec = getSpec(self)

    local canApply = self.spec_mower == nil
        or self.spec_foldable == nil
        or not hasNativeMowerModes(self)
        or getIsLoweredForWork(self)
    if canApply and getSelectedOffset(self) ~= 0
        and (self.spec_windrower ~= nil or self.spec_tedder ~= nil)
        and self.spec_foldable ~= nil then
        canApply = getVisualEffectPoseIsReady(self)
    end

    if spec.pendingApply == true and canApply and applyWidth(self) then
        spec.pendingApply = false
    end

    if spec.visualEffectsPending == true and getVisualEffectPoseIsReady(self) then
        spec.visualEffectsPending = not applyVisualEffectWidth(self, spec)
    end

    if AdjustSuiteCourseplay ~= nil then
        AdjustSuiteCourseplay.update(self)
    end

    if self.isClient ~= true or isActiveForInputIgnoreSelection ~= true then
        return
    end

    if spec.syntheticMowerModes ~= true and hasNativeMowerModes(self) then
        updateNativeMowerModeAction(self)
    end

end

function AWW:onDraw(isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = getSpec(self)
    if spec.currentWidth == nil or spec.baseWidth == nil or spec.baseWidth <= 0 then
        return
    end

    if not getIsLoweredForWork(self) then
        return
    end

    if not Suite.canShowHelpText(self, isActiveForInputIgnoreSelection) then
        return
    end

    local offset = spec.currentOffset or 0
    local mowerModeText = ""
    if spec.syntheticMowerModes == true and self.spec_mower ~= nil then
        mowerModeText = string.format(" - %s: %.2f %s", getMowerDropModeText(self.spec_mower.useWindrowDropAreas), spec.currentDropWidth or 0, g_i18n:getText("CONFIG_AS_M"))
    end
    Suite.addHelpText(string.format("AWW: %s [%s] - %s%s", Suite.getOffsetText(offset), Suite.getStatusText(offset), formatDisplayWidths(self, spec), mowerModeText))
end

function AWW:onUpdateTick(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if Suite.getIsModuleEnabled("AWW") then
        AdjustSuitePrecisionFarming.updateLimeFallback(self, getSpec(self))
    end
end
