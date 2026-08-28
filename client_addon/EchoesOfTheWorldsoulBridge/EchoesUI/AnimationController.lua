local UI = EchoesUI
if not UI then return end

local Animation = {}

local function SmoothStep(value)
    local clamped = math.max(0, math.min(1, value))
    return clamped * clamped * (3 - 2 * clamped)
end

function Animation:Stop(frame)
    frame.__echoesAnimationToken = (frame.__echoesAnimationToken or 0) + 1
    frame:SetScript("OnUpdate", nil)
end

function Animation:Alpha(frame, target, duration, onComplete)
    self:Stop(frame)
    local token = frame.__echoesAnimationToken
    local from = frame:GetAlpha() or 0

    if UI:IsReducedMotion() or not duration or duration <= 0 or from == target then
        frame:SetAlpha(target)
        if onComplete then onComplete() end
        return
    end

    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, delta)
        if self.__echoesAnimationToken ~= token then
            self:SetScript("OnUpdate", nil)
            return
        end

        elapsed = elapsed + delta
        local progress = SmoothStep(elapsed / duration)
        self:SetAlpha(from + (target - from) * progress)
        if elapsed >= duration then
            self:SetAlpha(target)
            self:SetScript("OnUpdate", nil)
            if onComplete then onComplete() end
        end
    end)
end

local function PlaceMaterial(frame, offsetX, offsetY, scale)
    frame.__echoesMaterialX = offsetX
    frame.__echoesMaterialY = offsetY
    frame:ClearAllPoints()
    frame:SetPoint(frame.__echoesMaterialPoint or "TOPLEFT",
        frame.__echoesMaterialRelative,
        frame.__echoesMaterialRelativePoint or "TOPLEFT",
        (frame.__echoesMaterialBaseX or 0) + offsetX,
        -((frame.__echoesMaterialBaseY or 0) - offsetY))
    frame:SetScale(scale)
end

-- A narrow physical-state tween for pre-created landmark pieces. Alpha,
-- offset, and scale share one transient update so a plate or rune cannot
-- strand one property while another animation supersedes it.
function Animation:Material(frame, targetAlpha, targetX, targetY, targetScale, duration, onComplete)
    self:Stop(frame)
    local token = frame.__echoesAnimationToken
    local fromAlpha = frame:GetAlpha() or 0
    local fromX = frame.__echoesMaterialX or 0
    local fromY = frame.__echoesMaterialY or 0
    local fromScale = frame:GetScale() or 1
    targetX = targetX or 0
    targetY = targetY or 0
    targetScale = targetScale or 1

    if fromAlpha == targetAlpha and fromX == targetX and fromY == targetY
        and fromScale == targetScale then
        if onComplete then onComplete() end
        return
    end

    if UI:IsReducedMotion() or not duration or duration <= 0 then
        frame:SetAlpha(targetAlpha)
        PlaceMaterial(frame, targetX, targetY, targetScale)
        if onComplete then onComplete() end
        return
    end

    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, delta)
        if self.__echoesAnimationToken ~= token then
            self:SetScript("OnUpdate", nil)
            return
        end

        elapsed = elapsed + delta
        local progress = SmoothStep(elapsed / duration)
        self:SetAlpha(fromAlpha + (targetAlpha - fromAlpha) * progress)
        PlaceMaterial(self,
            fromX + (targetX - fromX) * progress,
            fromY + (targetY - fromY) * progress,
            fromScale + (targetScale - fromScale) * progress)
        if elapsed >= duration then
            self:SetAlpha(targetAlpha)
            PlaceMaterial(self, targetX, targetY, targetScale)
            self:SetScript("OnUpdate", nil)
            if onComplete then onComplete() end
        end
    end)
end

UI.AnimationController = Animation
UI.modules.AnimationController = true
