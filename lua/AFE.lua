AdjustSuiteAFE = AdjustSuiteAFE or {}
local AFE = AdjustSuiteAFE

local Suite = AdjustSuite
Suite.moduleClasses["AFE"] = AFE
local getSpec, getSelectedOffset, hasSelectedConfiguration, getFactor = Suite.createModuleAccessors("AFE")

function AFE.prerequisitesPresent(specializations)
    return Motorized ~= nil and SpecializationUtil.hasSpecialization(Motorized, specializations)
end

function AFE.initSpecialization()
    Suite.registerOffsetSavegamePaths("AFE")
end

function AFE:onPreLoad(savegame)
    Suite.loadStoredOffsets(self, "AFE", savegame)
    Suite.resolveConfiguration(self, "AFE", self.isServer)
end

function AFE:saveToXMLFile(xmlFile, key, _usedModNames)
    Suite.saveStoredOffsets(self, "AFE", xmlFile, key)
end

function AFE.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onPreLoad", AFE)
    SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", AFE)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", AFE)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", AFE)
end

function AFE:onPostLoad(_savegame)
    local spec = getSpec(self)
    local motorizedSpec = self.spec_motorized
    if spec.usageApplied == true or motorizedSpec == nil or motorizedSpec.consumers == nil then
        return
    end
    spec.usageApplied = true

    if not hasSelectedConfiguration(self) then
        return
    end

    local factor = getFactor(self)
    if factor == 1 then
        return
    end

    for _, consumer in pairs(motorizedSpec.consumers) do
        if
            consumer ~= nil
            and type(consumer.usage) == "number"
            and consumer.usage > 0
            and not Suite.fillTypeIsAir(consumer.fillType)
        then
            consumer.usage = consumer.usage / factor
        end
    end
end

function AFE:onDraw(_isActiveForInput, isActiveForInputIgnoreSelection, _isSelected)
    if not Suite.canShowHelpText(self, isActiveForInputIgnoreSelection) then
        return
    end

    local offset = getSelectedOffset(self)
    Suite.addHelpText(string.format("AFE: %s [%s]", Suite.getOffsetText(offset), Suite.getStatusText(offset)))
end
