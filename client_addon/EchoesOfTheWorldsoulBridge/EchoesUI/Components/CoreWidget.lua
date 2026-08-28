local UI = EchoesUI
if not UI or not UI.Landmark then return end

local CoreWidget = {}

function CoreWidget:Create(parent, options)
    options = options or {}
    local object = UI.Landmark:Create(parent, options)
    object.isCoreWidget = true
    object.homeSemantic = true
    return object
end

UI.CoreWidget = CoreWidget
UI.modules.CoreWidget = true
