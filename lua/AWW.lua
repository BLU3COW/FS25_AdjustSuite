AWW = AWW or {}

local Suite = AdjustSuite
local clampOffset = Suite.clampOffset
local getFactorFromOffset = Suite.getFactorFromOffset
local getIsLoweredForWork = Suite.getIsLoweredForWork
local SAVEGAME_PATH = ".FS25_AdjustSuite.AWW#useWindrowDropAreas"
local PF_LIME_EFFECT_RETRY_DELAY_MS = 1000
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

local function getWidthAxis(vehicle, areas, referenceNode)
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
                if vehicle.spec_mower ~= nil then
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

    local axisX, axisY, axisZ = getWidthAxis(vehicle, spec.areas, referenceNode)
    if axisX == nil then
        return false
    end

    local minProjection, maxProjection = getAreaProjectionBounds(spec.areas, referenceNode, axisX, axisY, axisZ)
    if minProjection == nil or maxProjection - minProjection <= 0.01 then
        return false
    end

    spec.referenceNode = referenceNode
    spec.widthAxisX = axisX
    spec.widthAxisY = axisY
    spec.widthAxisZ = axisZ
    spec.widthCenterProjection = (minProjection + maxProjection) * 0.5
    spec.baseWidth = round2(maxProjection - minProjection)
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

    scaleMarkerSet(spec, aiSpec.leftMarker, aiSpec.rightMarker, aiSpec.backMarker, factor, appliedNodes)
    scaleMarkerSet(spec, aiSpec.sizeLeftMarker, aiSpec.sizeRightMarker, aiSpec.sizeBackMarker, factor, appliedNodes)

    if aiSpec.aiBaseSetups ~= nil then
        for _, aiSetup in ipairs(aiSpec.aiBaseSetups) do
            scaleMarkerSet(spec, aiSetup.leftMarker, aiSetup.rightMarker, aiSetup.backMarker, factor, appliedNodes)
            scaleMarkerSet(spec, aiSetup.sizeLeftMarker, aiSetup.sizeRightMarker, aiSetup.sizeBackMarker, factor, appliedNodes)
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

local function getPrecisionFarmingSpecializationClass(classObject, specializationName)
    if type(classObject) == "table" then
        return classObject
    end

    if g_specializationManager ~= nil
        and type(g_specializationManager.getSpecializationObjectByName) == "function" then
        return g_specializationManager:getSpecializationObjectByName("FS25_precisionFarming." .. specializationName)
    end

    return nil
end

local function getExtendedSprayerEffectsSpec(vehicle)
    local classObject = getPrecisionFarmingSpecializationClass(ExtendedSprayerEffects, "extendedSprayerEffects")
    if classObject ~= nil and classObject.SPEC_TABLE_NAME ~= nil then
        local spec = vehicle[classObject.SPEC_TABLE_NAME]
        if spec ~= nil then
            return spec
        end
    end

    return vehicle.spec_extendedSprayerEffects
end

local function getExtendedSprayerSpec(vehicle)
    local classObject = getPrecisionFarmingSpecializationClass(ExtendedSprayer, "extendedSprayer")

    if classObject ~= nil and classObject.SPEC_TABLE_NAME ~= nil then
        local spec = vehicle[classObject.SPEC_TABLE_NAME]
        if spec ~= nil then
            return spec, classObject
        end
    end

    return vehicle.spec_extendedSprayer, classObject
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
    local extendedSpec = getExtendedSprayerEffectsSpec(vehicle)
    local extendedEffects = extendedSpec ~= nil and extendedSpec.sprayerEffects or nil
    local hasExtendedEffects = extendedSpec ~= nil
        and (extendedSpec.hasCustomEffects == true or (extendedEffects ~= nil and #extendedEffects > 0))

    if hasExtendedEffects then
        for _, effectData in pairs(extendedEffects) do
            addEffectNode(nodes, seen, effectData.effectNode, effectData)
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

local function applySprayerVisualEffectWidth(vehicle, spec)
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
    local spec = getSpec(vehicle)
    local offset = getSelectedOffset(vehicle)
    local factor = getFactorFromOffset(offset)

    if not collectWorkAreas(vehicle) then
        return applyLevelerWidth(vehicle, spec, factor)
            or applyBunkerSiloCompacterWidth(vehicle, spec, factor)
    end

    if not setCurrentWidthState(vehicle, spec, factor, spec.baseWidth) then
        return false
    end

    local appliedNodes = {}

    if not spec.isBase then
        scaleAreaNodes(spec, spec.areas, factor, appliedNodes)
        applyAIMarkerWidth(vehicle, spec, factor, appliedNodes)
        updateChangedWorkAreas(vehicle, spec.areas)
    end

    applySprayerUsageWidths(vehicle, spec, factor)
    spec.visualEffectsPending = vehicle.spec_sprayer ~= nil and not spec.isBase

    if configureSyntheticMowerModes(vehicle, spec) then
        applySyntheticMowerMode(vehicle, vehicle.spec_mower.useWindrowDropAreas)
    elseif not spec.isBase then
        scaleAreaNodes(spec, spec.dropAreas, factor, appliedNodes)
        updateChangedWorkAreas(vehicle, spec.dropAreas)
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
end

function AWW.initSpecialization()
    Vehicle.xmlSchemaSavegame:register(XMLValueType.BOOL, "vehicles.vehicle(?).FS25_AdjustSuite.AWW#useWindrowDropAreas", "AWW generated mower drop mode")
end

function AWW.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", AWW)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", AWW)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", AWW)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", AWW)
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
    if Mower ~= nil and SpecializationUtil.hasSpecialization(Mower, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "setUseMowerWindrowDropAreas", AWW.setUseMowerWindrowDropAreas)
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "getDropArea", AWW.getDropArea)
    end
    if WorkMode ~= nil and SpecializationUtil.hasSpecialization(WorkMode, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "setWorkMode", AWW.setWorkMode)
    end
end

function AWW:onLoad(savegame)
    if self.spec_pickup ~= nil then
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

local function getSprayerFillType(vehicle)
    local sprayerSpec = vehicle.spec_sprayer
    if sprayerSpec == nil or vehicle.getSprayerFillUnitIndex == nil then
        return nil
    end

    local indexOk, fillUnitIndex = pcall(vehicle.getSprayerFillUnitIndex, vehicle)
    if not indexOk or fillUnitIndex == nil then
        return nil
    end

    local fillType
    if vehicle.getFillUnitLastValidFillType ~= nil then
        local ok, value = pcall(vehicle.getFillUnitLastValidFillType, vehicle, fillUnitIndex)
        fillType = ok and value or nil
    end

    if (fillType == nil or (FillType ~= nil and fillType == FillType.UNKNOWN))
        and vehicle.getFillUnitFirstSupportedFillType ~= nil then
        local ok, value = pcall(vehicle.getFillUnitFirstSupportedFillType, vehicle, fillUnitIndex)
        fillType = ok and value or fillType
    end

    return fillType
end

local function effectsAreRunning(effects)
    local found = false
    for _, effect in pairs(effects or {}) do
        if type(effect) == "table" and type(effect.isRunning) == "function" then
            found = true
            local ok, isRunning = pcall(effect.isRunning, effect)
            if not ok or isRunning ~= true then
                return false
            end
        end
    end

    return found
end

local function setSprayerVisualEffectsState(vehicle, sprayType, fillType, state)
    local sprayerSpec = vehicle.spec_sprayer
    if sprayerSpec == nil or g_effectManager == nil or sprayType == nil then
        return
    end

    if state then
        if g_effectManager.setEffectTypeInfo ~= nil then
            g_effectManager:setEffectTypeInfo(sprayerSpec.effects, fillType)
            g_effectManager:setEffectTypeInfo(sprayType.effects, fillType)
        end
        g_effectManager:startEffects(sprayerSpec.effects)
        g_effectManager:startEffects(sprayType.effects)
        if g_animationManager ~= nil then
            g_animationManager:startAnimations(sprayerSpec.animationNodes)
            g_animationManager:startAnimations(sprayType.animationNodes)
        end
    else
        g_effectManager:stopEffects(sprayerSpec.effects)
        g_effectManager:stopEffects(sprayType.effects)
        if g_animationManager ~= nil then
            g_animationManager:stopAnimations(sprayerSpec.animationNodes)
            g_animationManager:stopAnimations(sprayType.animationNodes)
        end
    end
end

local function stopPrecisionFarmingLimeFallback(vehicle, spec)
    if spec.precisionFarmingLimeEffectActive == true then
        setSprayerVisualEffectsState(vehicle, spec.precisionFarmingLimeSprayType, nil, false)
    end
    spec.precisionFarmingLimeEffectActive = false
    spec.precisionFarmingLimeSprayType = nil
    spec.precisionFarmingLimeEffectRetryAt = nil
    spec.precisionFarmingLimeEffectRetryDone = false
end

local function synchronizePrecisionFarmingSprayerMode(vehicle, extendedSpec)
    if vehicle.getCurrentSprayerMode == nil then
        return
    end

    local ok, isLiming, isFertilizing = pcall(vehicle.getCurrentSprayerMode, vehicle)
    if ok then
        extendedSpec.isLiming = isLiming
        extendedSpec.isFertilizing = isFertilizing
    end
end

local function updatePrecisionFarmingLimeFallback(vehicle, spec)
    local sprayerSpec = vehicle.spec_sprayer
    local extendedSpec = getExtendedSprayerSpec(vehicle)
    local effectsSpec = getExtendedSprayerEffectsSpec(vehicle)
    local sprayType = getActiveSprayType(vehicle)
    local fillType = getSprayerFillType(vehicle)
    local isLime = FillType ~= nil and fillType == FillType.LIME

    if vehicle.isClient ~= true
        or sprayerSpec == nil
        or extendedSpec == nil
        or (effectsSpec ~= nil and effectsSpec.hasCustomEffects == true)
        or sprayType == nil
        or not isLime
        or vehicle.getIsTurnedOn == nil
        or vehicle.getAreEffectsVisible == nil then
        stopPrecisionFarmingLimeFallback(vehicle, spec)
        return
    end

    local turnedOnOk, isTurnedOn = pcall(vehicle.getIsTurnedOn, vehicle)
    local visibleOk, effectsVisible = pcall(vehicle.getAreEffectsVisible, vehicle)
    if not turnedOnOk or not visibleOk or isTurnedOn ~= true or effectsVisible ~= true then
        stopPrecisionFarmingLimeFallback(vehicle, spec)
        return
    end

    synchronizePrecisionFarmingSprayerMode(vehicle, extendedSpec)
    if vehicle.getIsPrecisionSprayingRequired ~= nil then
        local ok, required = pcall(vehicle.getIsPrecisionSprayingRequired, vehicle)
        if ok and required == false then
            stopPrecisionFarmingLimeFallback(vehicle, spec)
            return
        end
    end

    if spec.precisionFarmingLimeSprayType ~= nil
        and spec.precisionFarmingLimeSprayType ~= sprayType then
        stopPrecisionFarmingLimeFallback(vehicle, spec)
    end

    local now = g_time or 0
    if spec.precisionFarmingLimeEffectActive ~= true then
        setSprayerVisualEffectsState(vehicle, sprayType, fillType, true)
        spec.precisionFarmingLimeEffectActive = true
        spec.precisionFarmingLimeSprayType = sprayType
        spec.precisionFarmingLimeEffectRetryAt = now + PF_LIME_EFFECT_RETRY_DELAY_MS
        spec.precisionFarmingLimeEffectRetryDone = false
    elseif spec.precisionFarmingLimeEffectRetryDone ~= true
        and now >= (spec.precisionFarmingLimeEffectRetryAt or math.huge) then
        spec.precisionFarmingLimeEffectRetryDone = true
        if not effectsAreRunning(sprayType.effects) then
            setSprayerVisualEffectsState(vehicle, sprayType, fillType, true)
        end
    end
end

function AWW:onChangedFillType(fillUnitIndex, fillTypeIndex, oldFillTypeIndex)
    queueSprayerVisualEffectUpdate(self)
    stopPrecisionFarmingLimeFallback(self, getSpec(self))
end

function AWW:onSprayTypeChange(sprayType)
    queueSprayerVisualEffectUpdate(self)
    stopPrecisionFarmingLimeFallback(self, getSpec(self))
end

function AWW:onTurnedOn()
    queueSprayerVisualEffectUpdate(self)
end

function AWW:onTurnedOff()
    stopPrecisionFarmingLimeFallback(self, getSpec(self))
end

function AWW:onPostLoad(savegame)
    local spec = getSpec(self)
    local waitForNativeMower = self.spec_mower ~= nil
        and self.spec_foldable ~= nil
        and hasNativeMowerModes(self)
        and not getIsLoweredForWork(self)

    if spec.pendingApply == true and not waitForNativeMower and applyWidth(self) then
        spec.pendingApply = false
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
    local spec = getSpec(self)

    if spec.syntheticMowerModes ~= true and self.spec_mower ~= nil then
        synchronizeNativeMowerModeAreas(self, state)
    end

    return result
end

function AWW:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if self.isClient ~= true then
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
    local useWindrowDropAreas = spec.syntheticMowerModes == true
        and self.spec_mower ~= nil
        and self.spec_mower.useWindrowDropAreas == true
    streamWriteBool(streamId, useWindrowDropAreas)
end

function AWW:onReadStream(streamId, connection)
    local spec = getSpec(self)
    local useWindrowDropAreas = streamReadBool(streamId)
    spec.requestedUseWindrowDropAreas = useWindrowDropAreas

    if spec.syntheticMowerModes == true and self.spec_mower ~= nil then
        applySyntheticMowerMode(self, useWindrowDropAreas)
    end
end

function AWW:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = getSpec(self)
    if spec.syntheticMowerModes == true and self.spec_mower ~= nil then
        xmlFile:setValue(key .. "#useWindrowDropAreas", self.spec_mower.useWindrowDropAreas == true)
    end
end

function AWW:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = getSpec(self)
    local canApply = self.spec_mower == nil
        or self.spec_foldable == nil
        or not hasNativeMowerModes(self)
        or getIsLoweredForWork(self)

    if spec.pendingApply == true and canApply and applyWidth(self) then
        spec.pendingApply = false
    end

    if spec.visualEffectsPending == true and getVisualEffectPoseIsReady(self) then
        spec.visualEffectsPending = not applySprayerVisualEffectWidth(self, spec)
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
    updatePrecisionFarmingLimeFallback(self, getSpec(self))
end
