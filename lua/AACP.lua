AdjustSuiteAACP = AdjustSuiteAACP or {}
local AACP = AdjustSuiteAACP

local Suite = AdjustSuite
Suite.moduleClasses["AACP"] = AACP
local ANIMALS_PATH = "placeable.husbandry.animals"
local MAX_NETWORK_ANIMALS = 65535

local function scaleCount(value, factor)
    return math.max(math.floor(value * factor + 0.5), 1)
end

function AACP.getStoreContext(xmlFile, _configurations, _defaultConfigurationIds, _customEnvironment, storeItem)
    if storeItem == nil or not xmlFile:hasProperty(ANIMALS_PATH) then
        return nil
    end

    return { basePrice = Suite.getStoreItemPrice(storeItem, xmlFile) }
end

function AACP.getOutdoorAnimals(spec, outdoorAreaSqm)
    local sqmPerAnimal = tonumber(spec.sqmPerAnimal)
    if outdoorAreaSqm == nil or sqmPerAnimal == nil or sqmPerAnimal <= 0 then
        return 0
    end

    return math.floor(outdoorAreaSqm / sqmPerAnimal)
end

function AACP.getScaledMaxNumAnimals(placeable, outdoorAreaSqm)
    local spec = placeable.spec_husbandryAnimals
    local base = tonumber(placeable.adjustSuiteAACPBaseMaxNumAnimals) or tonumber(spec.baseMaxNumAnimals) or 0
    local total = base + AACP.getOutdoorAnimals(spec, outdoorAreaSqm)

    return math.min(scaleCount(total, placeable.adjustSuiteAACPFactor or 1), MAX_NETWORK_ANIMALS)
end

function AACP:setMaxNumAnimals(superFunc, outdoorAreaSqm)
    local spec = self.spec_husbandryAnimals
    if spec == nil then
        return superFunc(self, outdoorAreaSqm)
    end

    local target = AACP.getScaledMaxNumAnimals(self, outdoorAreaSqm)
    local storedBase = spec.baseMaxNumAnimals
    spec.baseMaxNumAnimals = target - AACP.getOutdoorAnimals(spec, outdoorAreaSqm)
    local result = superFunc(self, outdoorAreaSqm)
    spec.baseMaxNumAnimals = storedBase

    if target > (tonumber(spec.maxNumAnimals) or 0) then
        spec.maxNumAnimals = target
    end

    return result
end

function AACP.applyToPlaceableXML(placeable, offset)
    local factor = Suite.getFactorFromOffset(offset)
    if factor == 1 then
        return
    end

    local xmlFile = placeable.xmlFile
    if not xmlFile:hasProperty(ANIMALS_PATH) then
        return
    end

    local configured = tonumber(xmlFile:getValue(ANIMALS_PATH .. "#maxNumAnimals", 16)) or 16
    local base = tonumber(xmlFile:getValue(ANIMALS_PATH .. "#baseMaxNumAnimals", configured)) or configured
    xmlFile:setValue(ANIMALS_PATH .. "#maxNumAnimals", scaleCount(configured, factor))
    xmlFile:setValue(ANIMALS_PATH .. "#baseMaxNumAnimals", scaleCount(base, factor))

    if placeable.setMaxNumAnimals ~= nil and placeable.adjustSuiteAACPHooked ~= true then
        placeable.adjustSuiteAACPHooked = true
        placeable.adjustSuiteAACPFactor = factor
        placeable.adjustSuiteAACPBaseMaxNumAnimals = base
        placeable.setMaxNumAnimals = Utils.overwrittenFunction(placeable.setMaxNumAnimals, AACP.setMaxNumAnimals)
    end
end
