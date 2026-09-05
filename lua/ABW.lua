AdjustSuiteABW = AdjustSuiteABW or {}
local ABW = AdjustSuiteABW

local Suite = AdjustSuite
local getSpec, _, hasSelectedConfiguration, getFactor = Suite.createModuleAccessors("ABW")

local function getComponent(vehicle, node)
    for _, component in ipairs(vehicle.components or {}) do
        if component.node == node then
            return component
        end
    end
    return nil
end

local function getComponentsKey(vehicle)
    local configurationId = vehicle.configurations ~= nil and vehicle.configurations.component or 1
    local key = string.format(
        "vehicle.base.componentConfigurations.componentConfiguration(%d)",
        (tonumber(configurationId) or 1) - 1
    )
    return vehicle.xmlFile:hasProperty(key) and key or "vehicle.base.components"
end

local function getBaseComponentMass(vehicle, node)
    for componentIndex, componentKey in vehicle.xmlFile:iterator(getComponentsKey(vehicle) .. ".component") do
        local component = vehicle.components ~= nil and vehicle.components[componentIndex] or nil
        if component ~= nil and component.node == node then
            return math.max(tonumber(vehicle.xmlFile:getValue(componentKey .. "#mass", 0)) or 0, 0) * 0.001
        end
    end
    return nil
end

local function addMassAtPosition(component, mass, massNode, massOffset)
    local oldMass = tonumber(component.defaultMass) or 0
    local newMass = math.max(oldMass + mass, 0.01)
    local appliedMass = newMass - oldMass

    if math.abs(appliedMass) > 0.000001 and newMass > 0 and getCenterOfMass ~= nil and setCenterOfMass ~= nil then
        local massX, massY, massZ
        if massNode ~= nil and massNode ~= 0 and localToLocal ~= nil then
            massX, massY, massZ = localToLocal(massNode, component.node, 0, 0, 0)
        elseif massOffset ~= nil then
            massX, massY, massZ = massOffset[1], massOffset[2], massOffset[3]
        end

        if massX ~= nil then
            local centerX, centerY, centerZ = getCenterOfMass(component.node)
            setCenterOfMass(
                component.node,
                (centerX * oldMass + massX * appliedMass) / newMass,
                (centerY * oldMass + massY * appliedMass) / newMass,
                (centerZ * oldMass + massZ * appliedMass) / newMass
            )
        end
    end

    component.defaultMass = newMass
    return appliedMass
end

local function applyAdditionalMassConfiguration(vehicle, configurationKey, factor)
    local standardMass = 0
    local appliedMass = 0

    for _, componentKey in vehicle.xmlFile:iterator(configurationKey .. ".component") do
        local mass = math.max(
            tonumber(vehicle.xmlFile:getValue(componentKey .. "#additionalMass", 0)) or 0,
            0
        ) * 0.001
        local node = vehicle.xmlFile:getValue(
            componentKey .. "#node",
            nil,
            vehicle.components,
            vehicle.i3dMappings
        )
        local component = getComponent(vehicle, node)
        if mass > 0 and component ~= nil then
            local massNode = vehicle.xmlFile:getValue(
                componentKey .. "#additionalMassNode",
                nil,
                vehicle.components,
                vehicle.i3dMappings
            )
            local massOffset = vehicle.xmlFile:getValue(componentKey .. "#additionalMassOffset", nil, true)
            standardMass = standardMass + mass
            appliedMass = appliedMass + addMassAtPosition(
                component,
                mass * (factor - 1),
                massNode,
                massOffset
            )
        end
    end

    return standardMass, appliedMass
end

local function applyObjectChangeConfiguration(
    vehicle,
    configurationKey,
    configurationsKey,
    configurationBaseKey,
    factor
)
    local standardMass = 0
    local appliedMass = 0
    local entries = Suite.getBallastObjectChanges(
        vehicle.xmlFile,
        configurationKey,
        configurationsKey,
        configurationBaseKey
    )
    for _, entry in ipairs(entries) do
        local node = vehicle.xmlFile:getValue(
            entry.objectChangeKey .. "#node",
            nil,
            vehicle.components,
            vehicle.i3dMappings
        )
        local component = getComponent(vehicle, node)
        if component ~= nil then
            local entryMass = entry.mass * 0.001
            if entry.deriveFromBase then
                local baseMass = getBaseComponentMass(vehicle, node)
                entryMass = baseMass ~= nil and math.max(entry.effectiveMass * 0.001 - baseMass, 0) or 0
            end
            if entryMass > 0 then
                standardMass = standardMass + entryMass
                appliedMass = appliedMass + addMassAtPosition(component, entryMass * (factor - 1))
            end
        end
    end
    return standardMass, appliedMass
end

local function applyConfiguredBallast(vehicle, factor)
    local standardMass = 0
    local appliedMass = 0

    for configurationName, configurationId in pairs(vehicle.configurations or {}) do
        if configurationName ~= "ABW" then
            local configurationDesc = g_vehicleConfigurationManager:getConfigurationDescByName(configurationName)
            if configurationDesc ~= nil then
                local configurationKey = string.format(
                    configurationDesc.configurationKey .. "(%d)",
                    (tonumber(configurationId) or 1) - 1
                )
                local ballastMass = Suite.getBallastConfigurationMass(
                    vehicle.xmlFile,
                    configurationKey,
                    configurationDesc.configurationsKey,
                    configurationDesc.configurationKey
                )
                if ballastMass > 0 then
                    local additionalStandard, additionalApplied = applyAdditionalMassConfiguration(
                        vehicle,
                        configurationKey,
                        factor
                    )
                    standardMass = standardMass + additionalStandard
                    appliedMass = appliedMass + additionalApplied

                    if additionalStandard == 0 then
                        local objectStandard, objectApplied = applyObjectChangeConfiguration(
                            vehicle,
                            configurationKey,
                            configurationDesc.configurationsKey,
                            configurationDesc.configurationKey,
                            factor
                        )
                        standardMass = standardMass + objectStandard
                        appliedMass = appliedMass + objectApplied
                    end
                end
            end
        end
    end

    return standardMass, appliedMass
end

function ABW.prerequisitesPresent(specializations)
    local isAttachable = Attachable ~= nil and SpecializationUtil.hasSpecialization(Attachable, specializations)
    local isMotorized = Motorized ~= nil and SpecializationUtil.hasSpecialization(Motorized, specializations)
    local isDrivable = Drivable ~= nil and SpecializationUtil.hasSpecialization(Drivable, specializations)
    return isAttachable or isMotorized or isDrivable
end

function ABW.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ABW)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", ABW)
end

function ABW:onLoad(savegame)
    if not hasSelectedConfiguration(self) then
        return
    end

    local spec = getSpec(self)
    local factor = getFactor(self)
    local appliedMass = 0

    if Suite.xmlIsStandaloneWeight(self.xmlFile) then
        for _, component in ipairs(self.components or {}) do
            local oldMass = tonumber(component.defaultMass) or 0
            local newMass = math.max(oldMass * factor, 0.01)
            component.defaultMass = newMass
            spec.standardBallastMass = (spec.standardBallastMass or 0) + oldMass
            appliedMass = appliedMass + newMass - oldMass
        end
    else
        spec.standardBallastMass, appliedMass = applyConfiguredBallast(self, factor)
    end

    if (spec.standardBallastMass or 0) <= 0 then
        return
    end

    self.defaultMass = self:getDefaultMass()
    if appliedMass > 0 and self.maxComponentMass ~= nil and self.maxComponentMass < math.huge then
        self.maxComponentMass = self.maxComponentMass + appliedMass
    end
    if self.setMassDirty ~= nil then
        self:setMassDirty()
    end
end

function ABW:onDraw(isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = getSpec(self)
    if not Suite.canShowHelpText(self, isActiveForInputIgnoreSelection)
        or not hasSelectedConfiguration(self)
        or (spec.standardBallastMass or 0) <= 0 then
        return
    end

    local offset = spec.currentOffset or 0
    Suite.addHelpText(string.format(
        "ABW: %s [%s] - %s",
        Suite.getOffsetText(offset),
        Suite.getStatusText(offset),
        g_i18n:formatMass(spec.standardBallastMass * getFactor(self))
    ))
end
