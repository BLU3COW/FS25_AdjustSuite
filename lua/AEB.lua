AdjustSuiteAEB = AdjustSuiteAEB or {}
local AEB = AdjustSuiteAEB

local Suite = AdjustSuite
Suite.moduleClasses["AEB"] = AEB
local getSpec, getSelectedOffset, _, getFactor = Suite.createModuleAccessors("AEB")

local MAX_LOW_BRAKE_FORCE_SCALE = 1

function AEB.prerequisitesPresent(specializations)
    return Motorized ~= nil and SpecializationUtil.hasSpecialization(Motorized, specializations)
end

function AEB.initSpecialization()
    Suite.registerOffsetSavegamePaths("AEB")
end

function AEB:onPreLoad(savegame)
    Suite.loadStoredOffsets(self, "AEB", savegame)
    Suite.resolveConfiguration(self, "AEB", self.isServer)
    if self.loadMotor ~= nil then
        self.loadMotor = Utils.overwrittenFunction(self.loadMotor, AEB.loadMotor)
    end
end

function AEB:saveToXMLFile(xmlFile, key, _usedModNames)
    Suite.saveStoredOffsets(self, "AEB", xmlFile, key)
end

function AEB.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onPreLoad", AEB)
    SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", AEB)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", AEB)
end

function AEB:loadMotor(superFunc, xmlFile, motorId)
    local result = superFunc(self, xmlFile, motorId)
    local motorizedSpec = self.spec_motorized
    local motor = motorizedSpec ~= nil and motorizedSpec.motor or nil
    if motor == nil or motor.setLowBrakeForce == nil or tonumber(motor.lowBrakeForceScale) == nil then
        return result
    end

    local factor = getFactor(self)
    if factor == 1 then
        return result
    end

    local scale = math.min(motor.lowBrakeForceScale * factor, MAX_LOW_BRAKE_FORCE_SCALE)
    motor:setLowBrakeForce(scale, motor.lowBrakeForceSpeedLimit)
    getSpec(self).adjustedScale = scale
    return result
end

function AEB:onDraw(_isActiveForInput, isActiveForInputIgnoreSelection, _isSelected)
    if not Suite.canShowHelpText(self, isActiveForInputIgnoreSelection) then
        return
    end

    local offset = getSelectedOffset(self)
    Suite.addHelpText(string.format("AEB: %s [%s]", Suite.getOffsetText(offset), Suite.getStatusText(offset)))
end
