AdjustSuiteABP = AdjustSuiteABP or {}
local ABP = AdjustSuiteABP

local Suite = AdjustSuite
local getSpec, _, hasSelectedConfiguration, getFactor = Suite.createModuleAccessors("ABP")

function ABP.prerequisitesPresent(specializations)
    local hasWheels = Wheels ~= nil and SpecializationUtil.hasSpecialization(Wheels, specializations)
    local isRoadVehicle = Motorized ~= nil
        and Drivable ~= nil
        and SpecializationUtil.hasSpecialization(Motorized, specializations)
        and SpecializationUtil.hasSpecialization(Drivable, specializations)
    local isAttachable = Attachable ~= nil and SpecializationUtil.hasSpecialization(Attachable, specializations)
    return hasWheels and (isRoadVehicle or isAttachable)
end

function ABP.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getBrakeForce", ABP.getBrakeForce)
end

function ABP.initSpecialization()
    Suite.registerOffsetSavegamePaths("ABP")
end

function ABP:onPreLoad(savegame)
    Suite.loadStoredOffsets(self, "ABP", savegame)
    Suite.resolveConfiguration(self, "ABP", self.isServer)
end

function ABP:saveToXMLFile(xmlFile, key, _usedModNames)
    Suite.saveStoredOffsets(self, "ABP", xmlFile, key)
end

function ABP.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onPreLoad", ABP)
    SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", ABP)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ABP)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", ABP)
end

function ABP:onLoad(_savegame)
    if hasSelectedConfiguration(self) then
        getFactor(self)
    end
end

function ABP:getBrakeForce(superFunc)
    local brakeForce = tonumber(superFunc(self)) or 0
    if not hasSelectedConfiguration(self) then
        return brakeForce
    end

    return brakeForce * getFactor(self)
end

function ABP:onDraw(_isActiveForInput, isActiveForInputIgnoreSelection, _isSelected)
    if not Suite.canShowHelpText(self, isActiveForInputIgnoreSelection) or not hasSelectedConfiguration(self) then
        return
    end

    local brakeForce = self:getBrakeForce()
    if type(brakeForce) ~= "number" or brakeForce <= 0 then
        return
    end

    local spec = getSpec(self)
    Suite.addHelpText(
        string.format(
            "ABP: %s [%s] - %.1f %s",
            Suite.getOffsetText(spec.currentOffset or 0),
            Suite.getStatusText(spec.currentOffset or 0),
            brakeForce,
            g_i18n:getText("CONFIG_AS_KN")
        )
    )
end
