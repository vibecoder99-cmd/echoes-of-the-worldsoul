local UI = EchoesUI
if not UI then return end

local Layout = {
    logicalWidth = 1672,
    logicalHeight = 941,
}

function Layout:PlaceProofHost(host, legacyFrame)
    host:ClearAllPoints()
    host:SetScale(1)

    if legacyFrame and legacyFrame:IsShown() and legacyFrame:GetRight() then
        local available = (UIParent:GetRight() or UIParent:GetWidth()) - legacyFrame:GetRight()
        if available >= 150 then
            host:SetPoint("TOPLEFT", legacyFrame, "TOPRIGHT", 10, -20)
            return
        end
    end

    host:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -18, -90)
end

UI.Layout = Layout
UI.modules.Layout = true

