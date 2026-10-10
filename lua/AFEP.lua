AdjustSuiteAFEP = AdjustSuiteAFEP or {}
local AFEP = AdjustSuiteAFEP

local Suite = AdjustSuite
Suite.moduleClasses["AFEP"] = AFEP
local ANIMALS_PATH = "placeable.husbandry.animals"
local CONSUMPTION_FIELDS = {
    { spec = "spec_husbandryFood", field = "litersPerHour" },
    { spec = "spec_husbandryWater", field = "litersPerHour" },
    { spec = "spec_husbandryStraw", field = "inputLitersPerHour" },
    { spec = "spec_husbandryBedding", field = "inputLitersPerHour" },
    { spec = "spec_husbandryBeddingMulti", field = "inputLitersPerHour" },
}

function AFEP.getStoreContext(xmlFile, _configurations, _defaultConfigurationIds, _customEnvironment, storeItem)
    if storeItem == nil or not xmlFile:hasProperty(ANIMALS_PATH) then
        return nil
    end

    return { basePrice = Suite.getStoreItemPrice(storeItem, xmlFile) }
end

function AFEP.scaleConsumption(placeable)
    local factor = tonumber(placeable.adjustSuiteAFEPFactor)
    if factor == nil or factor <= 0 or factor == 1 then
        return
    end

    for _, entry in ipairs(CONSUMPTION_FIELDS) do
        local spec = placeable[entry.spec]
        local value = type(spec) == "table" and tonumber(spec[entry.field]) or nil
        if value ~= nil and value > 0 then
            spec[entry.field] = value / factor
        end
    end
end

function AFEP.applyToPlaceableXML(placeable, offset)
    local factor = Suite.getFactorFromOffset(offset)
    if factor == 1 then
        return
    end

    if not placeable.xmlFile:hasProperty(ANIMALS_PATH) then
        return
    end

    placeable.adjustSuiteAFEPFactor = factor
    if placeable.updatedClusters ~= nil and placeable.adjustSuiteAFEPHooked ~= true then
        placeable.adjustSuiteAFEPHooked = true
        placeable.updatedClusters = Utils.overwrittenFunction(
            placeable.updatedClusters,
            function(self, superFunc, husbandry)
                local result = superFunc(self, husbandry)
                if husbandry == self then
                    AFEP.scaleConsumption(self)
                end
                return result
            end
        )
    end
end
