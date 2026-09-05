AdjustSuitePrecisionFarming = AdjustSuitePrecisionFarming or {}

local Compatibility = AdjustSuitePrecisionFarming
local LIME_EFFECT_RETRY_DELAY_MS = 1000

local function getSpecializationClass(classObject, specializationName)
    if type(classObject) == "table" then
        return classObject
    end

    if g_specializationManager ~= nil
        and type(g_specializationManager.getSpecializationObjectByName) == "function" then
        return g_specializationManager:getSpecializationObjectByName("FS25_precisionFarming." .. specializationName)
    end

    return nil
end

local function getExtendedSprayerEffectsSpec(vehicle)
    local classObject = getSpecializationClass(ExtendedSprayerEffects, "extendedSprayerEffects")
    if classObject ~= nil and classObject.SPEC_TABLE_NAME ~= nil then
        local spec = vehicle[classObject.SPEC_TABLE_NAME]
        if spec ~= nil then
            return spec
        end
    end

    return vehicle.spec_extendedSprayerEffects
end

local function getExtendedSprayerSpec(vehicle)
    local classObject = getSpecializationClass(ExtendedSprayer, "extendedSprayer")
    if classObject ~= nil and classObject.SPEC_TABLE_NAME ~= nil then
        local spec = vehicle[classObject.SPEC_TABLE_NAME]
        if spec ~= nil then
            return spec
        end
    end

    return vehicle.spec_extendedSprayer
end

local function getActiveSprayType(vehicle)
    if vehicle.getActiveSprayType == nil then
        return nil
    end

    local ok, sprayType = pcall(vehicle.getActiveSprayType, vehicle)
    return ok and sprayType or nil
end

local function getSprayerFillType(vehicle)
    local sprayerSpec = vehicle.spec_sprayer
    if sprayerSpec == nil or vehicle.getSprayerFillUnitIndex == nil then
        return nil
    end

    local indexOk, fillUnitIndex = pcall(vehicle.getSprayerFillUnitIndex, vehicle)
    if not indexOk or fillUnitIndex == nil then
        return nil
    end

    local fillType
    if vehicle.getFillUnitLastValidFillType ~= nil then
        local ok, value = pcall(vehicle.getFillUnitLastValidFillType, vehicle, fillUnitIndex)
        fillType = ok and value or nil
    end

    if (fillType == nil or (FillType ~= nil and fillType == FillType.UNKNOWN))
        and vehicle.getFillUnitFirstSupportedFillType ~= nil then
        local ok, value = pcall(vehicle.getFillUnitFirstSupportedFillType, vehicle, fillUnitIndex)
        fillType = ok and value or fillType
    end

    return fillType
end

local function effectsAreRunning(effects)
    local found = false
    for _, effect in pairs(effects or {}) do
        if type(effect) == "table" and type(effect.isRunning) == "function" then
            found = true
            local ok, isRunning = pcall(effect.isRunning, effect)
            if not ok or isRunning ~= true then
                return false
            end
        end
    end

    return found
end

local function setSprayerVisualEffectsState(vehicle, sprayType, fillType, state)
    local sprayerSpec = vehicle.spec_sprayer
    if sprayerSpec == nil or g_effectManager == nil or sprayType == nil then
        return
    end

    if state then
        if g_effectManager.setEffectTypeInfo ~= nil then
            g_effectManager:setEffectTypeInfo(sprayerSpec.effects, fillType)
            g_effectManager:setEffectTypeInfo(sprayType.effects, fillType)
        end
        g_effectManager:startEffects(sprayerSpec.effects)
        g_effectManager:startEffects(sprayType.effects)
        if g_animationManager ~= nil then
            g_animationManager:startAnimations(sprayerSpec.animationNodes)
            g_animationManager:startAnimations(sprayType.animationNodes)
        end
    else
        g_effectManager:stopEffects(sprayerSpec.effects)
        g_effectManager:stopEffects(sprayType.effects)
        if g_animationManager ~= nil then
            g_animationManager:stopAnimations(sprayerSpec.animationNodes)
            g_animationManager:stopAnimations(sprayType.animationNodes)
        end
    end
end

local function synchronizeSprayerMode(vehicle, extendedSpec)
    if vehicle.getCurrentSprayerMode == nil then
        return
    end

    local ok, isLiming, isFertilizing = pcall(vehicle.getCurrentSprayerMode, vehicle)
    if ok then
        extendedSpec.isLiming = isLiming
        extendedSpec.isFertilizing = isFertilizing
    end
end

function Compatibility.getVisualEffectNodes(vehicle)
    local extendedSpec = getExtendedSprayerEffectsSpec(vehicle)
    local extendedEffects = extendedSpec ~= nil and extendedSpec.sprayerEffects or nil
    local hasExtendedEffects = extendedSpec ~= nil
        and (extendedSpec.hasCustomEffects == true or (extendedEffects ~= nil and #extendedEffects > 0))

    if not hasExtendedEffects then
        return nil
    end

    local nodes = {}
    for _, effectData in pairs(extendedEffects or {}) do
        table.insert(nodes, {node = effectData.effectNode, effectData = effectData})
    end
    return nodes
end

function Compatibility.stopLimeFallback(vehicle, spec)
    if spec.precisionFarmingLimeEffectActive == true then
        setSprayerVisualEffectsState(vehicle, spec.precisionFarmingLimeSprayType, nil, false)
    end
    spec.precisionFarmingLimeEffectActive = false
    spec.precisionFarmingLimeSprayType = nil
    spec.precisionFarmingLimeEffectRetryAt = nil
    spec.precisionFarmingLimeEffectRetryDone = false
end

function Compatibility.updateLimeFallback(vehicle, spec)
    local sprayerSpec = vehicle.spec_sprayer
    local extendedSpec = getExtendedSprayerSpec(vehicle)
    local effectsSpec = getExtendedSprayerEffectsSpec(vehicle)
    local sprayType = getActiveSprayType(vehicle)
    local fillType = getSprayerFillType(vehicle)
    local isLime = FillType ~= nil and fillType == FillType.LIME

    if vehicle.isClient ~= true
        or sprayerSpec == nil
        or extendedSpec == nil
        or (effectsSpec ~= nil and effectsSpec.hasCustomEffects == true)
        or sprayType == nil
        or not isLime
        or vehicle.getIsTurnedOn == nil
        or vehicle.getAreEffectsVisible == nil then
        Compatibility.stopLimeFallback(vehicle, spec)
        return
    end

    local turnedOnOk, isTurnedOn = pcall(vehicle.getIsTurnedOn, vehicle)
    local visibleOk, effectsVisible = pcall(vehicle.getAreEffectsVisible, vehicle)
    if not turnedOnOk or not visibleOk or isTurnedOn ~= true or effectsVisible ~= true then
        Compatibility.stopLimeFallback(vehicle, spec)
        return
    end

    synchronizeSprayerMode(vehicle, extendedSpec)
    if vehicle.getIsPrecisionSprayingRequired ~= nil then
        local ok, required = pcall(vehicle.getIsPrecisionSprayingRequired, vehicle)
        if ok and required == false then
            Compatibility.stopLimeFallback(vehicle, spec)
            return
        end
    end

    if spec.precisionFarmingLimeSprayType ~= nil
        and spec.precisionFarmingLimeSprayType ~= sprayType then
        Compatibility.stopLimeFallback(vehicle, spec)
    end

    local now = g_time or 0
    if spec.precisionFarmingLimeEffectActive ~= true then
        setSprayerVisualEffectsState(vehicle, sprayType, fillType, true)
        spec.precisionFarmingLimeEffectActive = true
        spec.precisionFarmingLimeSprayType = sprayType
        spec.precisionFarmingLimeEffectRetryAt = now + LIME_EFFECT_RETRY_DELAY_MS
        spec.precisionFarmingLimeEffectRetryDone = false
    elseif spec.precisionFarmingLimeEffectRetryDone ~= true
        and now >= (spec.precisionFarmingLimeEffectRetryAt or math.huge) then
        spec.precisionFarmingLimeEffectRetryDone = true
        if not effectsAreRunning(sprayType.effects) then
            setSprayerVisualEffectsState(vehicle, sprayType, fillType, true)
        end
    end
end
