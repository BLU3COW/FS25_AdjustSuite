AdjustSuiteAPC = AdjustSuiteAPC or {}
local APC = AdjustSuiteAPC

local Suite = AdjustSuite
local getSpec, _, hasSelectedConfiguration, getSelectionFactor = Suite.createModuleAccessors("APC")
local IGNORED_FILLTYPE_NAMES = Suite.ignoredFillTypeNames

local function getFillTypeName(fillTypeIndex)
    if fillTypeIndex == nil then
        return nil
    end

    if g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeNameByIndex ~= nil then
        local ok, name = pcall(g_fillTypeManager.getFillTypeNameByIndex, g_fillTypeManager, fillTypeIndex)
        if ok then
            return name
        end
    end

    return nil
end

local function fillTypeIsIgnored(fillTypeIndex)
    local name = getFillTypeName(fillTypeIndex)
    return name ~= nil and IGNORED_FILLTYPE_NAMES[string.upper(tostring(name))] == true
end

local function getFillTypeMassPerLiter(fillTypeIndex)
    if fillTypeIndex == nil
        or (FillType ~= nil and fillTypeIndex == FillType.UNKNOWN)
        or fillTypeIsIgnored(fillTypeIndex)
        or g_fillTypeManager == nil then
        return nil
    end

    local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
    local massPerLiter = fillType ~= nil and tonumber(fillType.massPerLiter) or nil
    return massPerLiter ~= nil and massPerLiter > 0 and massPerLiter or nil
end

local function getPayloadMassFactor(vehicle)
    local selectionFactor = getSelectionFactor(vehicle)
    return selectionFactor > 0 and 1 / selectionFactor or 1
end

local function getFillUnitXMLKey(vehicle, fillUnitIndex)
    if vehicle == nil or vehicle.xmlFile == nil or tonumber(fillUnitIndex) == nil then
        return nil
    end

    local configurationId = vehicle.configurations ~= nil and tonumber(vehicle.configurations.fillUnit) or 1
    configurationId = math.max(math.floor((configurationId or 1) + 0.5), 1)
    local configurationKey = string.format(
        "vehicle.fillUnit.fillUnitConfigurations.fillUnitConfiguration(%d)",
        configurationId - 1
    )
    local fillUnitKey = string.format("%s.fillUnits.fillUnit(%d)", configurationKey, fillUnitIndex - 1)

    if not vehicle.xmlFile:hasProperty(fillUnitKey) and configurationId == 1 then
        fillUnitKey = string.format("vehicle.fillUnit.fillUnits.fillUnit(%d)", fillUnitIndex - 1)
    end

    return vehicle.xmlFile:hasProperty(fillUnitKey) and fillUnitKey or nil
end

local function fillUnitIsTechnicalHidden(vehicle, fillUnitIndex, fillUnit)
    if fillUnit == nil or fillUnit.showOnHud ~= false then
        return false
    end

    local fillUnitKey = getFillUnitXMLKey(vehicle, fillUnitIndex)
    return fillUnitKey ~= nil
        and (vehicle.xmlFile:getValue(fillUnitKey .. "#showInShop", true) == false
            or vehicle.xmlFile:getValue(fillUnitKey .. "#showCapacityInShop", true) == false)
end

local function fillUnitIsEligible(vehicle, fillUnitIndex, fillUnit, fillTypeIndex)
    return fillUnit ~= nil
        and fillUnit.updateMass == true
        and fillUnit.fillMassNode ~= nil
        and fillUnit.fillMassNode ~= 0
        and not Suite.fillUnitIsOperatingConsumer(vehicle, fillUnitIndex)
        and not fillUnitIsTechnicalHidden(vehicle, fillUnitIndex, fillUnit)
        and getFillTypeMassPerLiter(fillTypeIndex) ~= nil
end

local function hasEligibleFillUnit(vehicle)
    local fillUnits = vehicle.spec_fillUnit ~= nil and vehicle.spec_fillUnit.fillUnits or nil
    if fillUnits == nil then
        return false
    end

    for fillUnitIndex, fillUnit in ipairs(fillUnits) do
        if not fillUnitIsTechnicalHidden(vehicle, fillUnitIndex, fillUnit)
            and not Suite.fillUnitIsOperatingConsumer(vehicle, fillUnitIndex)
            and fillUnit.updateMass == true and fillUnit.fillMassNode ~= nil and fillUnit.fillMassNode ~= 0 then
            for fillTypeIndex in pairs(fillUnit.fillTypes or {}) do
                if getFillTypeMassPerLiter(fillTypeIndex) ~= nil then
                    return true
                end
            end

            if getFillTypeMassPerLiter(fillUnit.fillType) ~= nil then
                return true
            end
        end
    end

    return false
end

function APC.prerequisitesPresent(specializations)
    return FillUnit ~= nil and SpecializationUtil.hasSpecialization(FillUnit, specializations)
end

function APC.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getAdditionalComponentMass", APC.getAdditionalComponentMass)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "addFillUnitFillLevel", APC.addFillUnitFillLevel)
end

function APC.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", APC)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", APC)
end


function APC:onPostLoad(savegame)
    if hasSelectedConfiguration(self) and self.setMassDirty ~= nil then
        self:setMassDirty()
    end
end

function APC:getAdditionalComponentMass(superFunc, component)
    local additionalMass = tonumber(superFunc(self, component)) or 0
    if not hasSelectedConfiguration(self) then
        return additionalMass
    end

    local payloadMassFactor = getPayloadMassFactor(self)
    if payloadMassFactor == 1 then
        return additionalMass
    end

    local fillUnits = self.spec_fillUnit ~= nil and self.spec_fillUnit.fillUnits or nil
    for fillUnitIndex, fillUnit in ipairs(fillUnits or {}) do
        if fillUnit.fillMassNode == component.node
            and fillUnitIsEligible(self, fillUnitIndex, fillUnit, fillUnit.fillType) then
            local massPerLiter = getFillTypeMassPerLiter(fillUnit.fillType)
            local fillLevel = tonumber(fillUnit.fillLevel) or 0
            additionalMass = additionalMass + fillLevel * massPerLiter * (payloadMassFactor - 1)
        end
    end

    return math.max(additionalMass, 0)
end

function APC:addFillUnitFillLevel(superFunc, farmId, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData)
    local fillUnits = self.spec_fillUnit ~= nil and self.spec_fillUnit.fillUnits or nil
    local fillUnit = fillUnits ~= nil and fillUnits[fillUnitIndex] or nil
    if not hasSelectedConfiguration(self)
        or not self.isServer
        or (tonumber(fillLevelDelta) or 0) <= 0
        or fillUnit == nil
        or fillUnit.ignoreFillLimit == true
        or not fillUnitIsEligible(self, fillUnitIndex, fillUnit, fillTypeIndex)
        or g_currentMission == nil
        or g_currentMission.missionInfo == nil
        or g_currentMission.missionInfo.trailerFillLimit ~= true then
        return superFunc(self, farmId, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData)
    end

    local payloadMassFactor = getPayloadMassFactor(self)
    if payloadMassFactor == 1 then
        return superFunc(self, farmId, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData)
    end

    local massPerLiter = getFillTypeMassPerLiter(fillTypeIndex)
    local availableMass = self.getAvailableComponentMass ~= nil and self:getAvailableComponentMass() or math.huge
    local adjustedDelta = math.min(fillLevelDelta, availableMass / (massPerLiter * payloadMassFactor))

    local ignoreFillLimit = fillUnit.ignoreFillLimit
    fillUnit.ignoreFillLimit = true
    local ok, appliedDelta = pcall(
        superFunc,
        self,
        farmId,
        fillUnitIndex,
        adjustedDelta,
        fillTypeIndex,
        toolType,
        fillPositionData
    )
    fillUnit.ignoreFillLimit = ignoreFillLimit
    if not ok then
        error(appliedDelta, 0)
    end
    return appliedDelta
end

function APC:onDraw(isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if not Suite.canShowHelpText(self, isActiveForInputIgnoreSelection)
        or not hasSelectedConfiguration(self)
        or not hasEligibleFillUnit(self) then
        return
    end

    local spec = getSpec(self)
    local offset = spec.currentOffset or 0
    Suite.addHelpText(string.format(
        "APC: %s [%s]",
        Suite.getOffsetText(offset),
        Suite.getStatusText(offset)
    ))
end
