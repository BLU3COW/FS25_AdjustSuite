ABP = ABP or {}

local Suite = AdjustSuite
local getSpec, getSelectedOffset, hasSelectedConfiguration = Suite.createModuleAccessors("ABP")

local function getFactor(vehicle)
    local spec = getSpec(vehicle)
    if spec.currentFactor == nil then
        spec.currentOffset = getSelectedOffset(vehicle)
        spec.currentFactor = Suite.getFactorFromOffset(spec.currentOffset)
    end

    return spec.currentFactor
end

function ABP.prerequisitesPresent(specializations)
    return Motorized ~= nil
        and Drivable ~= nil
        and Wheels ~= nil
        and SpecializationUtil.hasSpecialization(Motorized, specializations)
        and SpecializationUtil.hasSpecialization(Drivable, specializations)
        and SpecializationUtil.hasSpecialization(Wheels, specializations)
end

function ABP.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getBrakeForce", ABP.getBrakeForce)
end

function ABP.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ABP)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", ABP)
end

function ABP:onLoad(savegame)
    if hasSelectedConfiguration(self) then
        getFactor(self)
    end
end

function ABP:getBrakeForce(superFunc)
    local brakeForce = superFunc(self)
    if not hasSelectedConfiguration(self) then
        return brakeForce
    end

    return brakeForce * getFactor(self)
end

function ABP:onDraw(isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if not Suite.canShowHelpText(self, isActiveForInputIgnoreSelection)
        or not hasSelectedConfiguration(self) then
        return
    end

    local brakeForce = self:getBrakeForce()
    if type(brakeForce) ~= "number" or brakeForce <= 0 then
        return
    end

    local spec = getSpec(self)
    Suite.addHelpText(string.format(
        "ABP: %s [%s] - %.1f %s",
        Suite.getOffsetText(spec.currentOffset or 0),
        Suite.getStatusText(spec.currentOffset or 0),
        brakeForce,
        g_i18n:getText("CONFIG_AS_KN")
    ))
end
