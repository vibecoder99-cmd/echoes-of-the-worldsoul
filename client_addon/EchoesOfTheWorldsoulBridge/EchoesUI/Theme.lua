local UI = EchoesUI
if not UI then return end

UI.Theme = {
    colors = {
        void = { 0.010, 0.012, 0.016, 0.96 },
        stone = { 0.055, 0.060, 0.070, 1.00 },
        stoneLift = { 0.095, 0.100, 0.112, 1.00 },
        bronzeDark = { 0.20, 0.145, 0.075, 1.00 },
        bronze = { 0.47, 0.34, 0.16, 1.00 },
        bronzeBright = { 0.82, 0.62, 0.27, 1.00 },
        worldsoul = { 0.27, 0.70, 1.00, 1.00 },
        worldsoulPale = { 0.65, 0.88, 1.00, 1.00 },
        text = { 0.88, 0.82, 0.68, 1.00 },
        textMuted = { 0.56, 0.55, 0.52, 1.00 },
        disabled = { 0.34, 0.35, 0.37, 1.00 },
    },
    fonts = {
        monument = "Fonts\\MORPHEUS.TTF",
        readable = "Fonts\\FRIZQT__.TTF",
    },
    timing = {
        open = 0.30,
        close = 0.18,
        hoverEnter = 0.14,
        hoverRelease = 0.18,
        click = 0.12,
    },
}

function UI.Theme:SetTextureColor(texture, color, alphaOverride)
    texture:SetTexture(color[1], color[2], color[3], alphaOverride or color[4])
end

UI.modules.Theme = true

