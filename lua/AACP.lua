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

function AACP.liftHorseLimit(placeable, outdoorAreaSqm)
    local spec = placeable.spec_husbandryAnimals
    if spec == nil then
        return
    end

    local uncapped = tonumber(spec.baseMaxNumAnimals) or 0
    if outdoorAreaSqm ~= nil and tonumber(spec.sqmPerAnimal) ~= nil and spec.sqmPerAnimal > 0 then
        uncapped = uncapped + math.floor(outdoorAreaSqm / spec.sqmPerAnimal)
    end
    uncapped = math.min(uncapped, MAX_NETWORK_ANIMALS)

    if uncapped > (tonumber(spec.maxNumAnimals) or 0) then
        spec.maxNumAnimals = uncapped
    end
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
        placeable.setMaxNumAnimals = Utils.overwrittenFunction(
            placeable.setMaxNumAnimals,
            function(self, superFunc, outdoorAreaSqm)
                if outdoorAreaSqm ~= nil then
                    outdoorAreaSqm = outdoorAreaSqm * (self.adjustSuiteAACPFactor or 1)
                end
                local result = superFunc(self, outdoorAreaSqm)
                AACP.liftHorseLimit(self, outdoorAreaSqm)
                return result
            end
        )
    end
end
