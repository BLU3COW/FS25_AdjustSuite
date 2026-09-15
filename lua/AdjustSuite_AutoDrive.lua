local safeCall = pcall
AdjustSuiteAutoDrive = AdjustSuiteAutoDrive or {}

local Compatibility = AdjustSuiteAutoDrive
local Suite = AdjustSuite

function Compatibility.getBunkerSiloSpeed(trailerModule, superFunc)
    local trailer = trailerModule.bunkerTrailer
    local dischargeNode = trailer ~= nil
            and trailer.getCurrentDischargeNode ~= nil
            and trailer:getCurrentDischargeNode()
        or nil
    local baseEmptySpeed = dischargeNode ~= nil and tonumber(dischargeNode.emptySpeed) or nil
    local factor = Suite.getFactorFromOffset(Suite.getSelectedOffset(trailer, "ADR"))

    if baseEmptySpeed == nil or baseEmptySpeed <= 0 or factor == 1 then
        return superFunc(trailerModule)
    end

    dischargeNode.emptySpeed = baseEmptySpeed * factor
    local ok, speed = safeCall(superFunc, trailerModule)
    dischargeNode.emptySpeed = baseEmptySpeed
    if not ok then
        error(speed, 0)
    end
    return speed
end

function Compatibility.install()
    if Compatibility.installed == true or Compatibility.abandoned == true then
        return
    end

    if ADTrailerModule == nil or ADTrailerModule.getBunkerSiloSpeed == nil then
        Compatibility.attempts = (Compatibility.attempts or 0) + 1
        if Compatibility.attempts >= 600 then
            Compatibility.abandoned = true
        end
        return
    end

    ADTrailerModule.getBunkerSiloSpeed =
        Utils.overwrittenFunction(ADTrailerModule.getBunkerSiloSpeed, Compatibility.getBunkerSiloSpeed)
    Compatibility.installed = true
end
