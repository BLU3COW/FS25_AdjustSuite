AMP = AMP or {}

local Suite = AdjustSuite
local getFactorFromOffset = Suite.getFactorFromOffset
local getSpec, getSelectedOffset = Suite.createModuleAccessors("AMP")

local function formatPower(power)
    power = tonumber(power)
    if power == nil or power <= 0 then
        return nil
    end

    return string.format(g_i18n:getText("shop_maxPowerValueSingle"), math.floor(power + 0.5))
end

function AMP.prerequisitesPresent(specializations)
    return Motorized ~= nil and SpecializationUtil.hasSpecialization(Motorized, specializations)
end

function AMP.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onPreLoad", AMP)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", AMP)
end

function AMP:onPreLoad()
    if self.loadMotor ~= nil then
        self.loadMotor = Utils.overwrittenFunction(self.loadMotor, AMP.loadMotor)
    end
end

function AMP:loadMotor(superFunc, xmlFile, motorId)
    local spec = getSpec(self)
    local offset = getSelectedOffset(self)
    local factor = getFactorFromOffset(offset)

    local key = nil
    local fallbackConfigKey = "vehicle.motorized.motorConfigurations.motorConfiguration(0)"

    key, motorId = ConfigurationUtil.getXMLConfigurationKey(
        xmlFile,
        motorId,
        "vehicle.motorized.motorConfigurations.motorConfiguration",
        "vehicle.motorized",
        "motor"
    )

    local basePower = ConfigurationUtil.getConfigurationValue(
        xmlFile,
        key,
        "",
        "#hp",
        nil,
        fallbackConfigKey
    )

    if basePower == nil then
        basePower = xmlFile:getValue("vehicle.storeData.specs.power")
    end

    basePower = tonumber(basePower)
    spec.adjustedPower = basePower ~= nil and basePower * factor or nil

    local torqueScalePath = key ~= nil and key .. ".motor#torqueScale" or nil
    local originalTorqueScale = torqueScalePath ~= nil and xmlFile:getValue(torqueScalePath) or nil

    if torqueScalePath ~= nil and math.abs(offset) > 0.001 then
        local torqueScaleBefore = ConfigurationUtil.getConfigurationValue(
            xmlFile,
            key,
            ".motor",
            "#torqueScale",
            1,
            fallbackConfigKey
        )

        local torqueScaleAfter = torqueScaleBefore * factor

        if xmlFile.setValue ~= nil then
            xmlFile:setValue(torqueScalePath, torqueScaleAfter)
        elseif xmlFile.setFloat ~= nil then
            xmlFile:setFloat(torqueScalePath, torqueScaleAfter)
        end

    end

    local motor = superFunc(self, xmlFile, motorId)

    if torqueScalePath ~= nil and math.abs(offset) > 0.001 then
        if originalTorqueScale == nil then
            xmlFile:removeProperty(torqueScalePath)
        else
            xmlFile:setValue(torqueScalePath, originalTorqueScale)
        end
    end

    return motor
end

function AMP:onDraw(isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if not Suite.canShowHelpText(self, isActiveForInputIgnoreSelection) then
        return
    end

    local offset = getSelectedOffset(self)
    local helpText = string.format("AMP: %s [%s]", Suite.getOffsetText(offset), Suite.getStatusText(offset))
    local powerText = formatPower(getSpec(self).adjustedPower)

    if powerText ~= nil then
        helpText = string.format("%s - %s", helpText, powerText)
    end

    Suite.addHelpText(helpText)
end
