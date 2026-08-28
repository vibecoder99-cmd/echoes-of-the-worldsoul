local UI = EchoesUI
if not UI then return end

local Screens = {
    registry = {},
    history = {},
    current = nil,
    homeId = nil,
}

function Screens:Register(id, screen, isHome)
    if not id or type(screen) ~= "table" then return false end
    self.registry[id] = screen
    if isHome then self.homeId = id end
    return true
end

function Screens:Show(id, remember, ...)
    local screen = self.registry[id]
    if not screen or type(screen.Show) ~= "function" then return false end

    local ok, shown = UI:SafeCall("screen route " .. tostring(id), screen.Show, screen, ...)
    if not ok or shown == false then return false end
    if remember ~= false and self.current and self.current ~= id then
        self.history[#self.history + 1] = self.current
    end
    self.current = id
    return true
end

function Screens:Close(id)
    local targetId = id or self.current
    local screen = targetId and self.registry[targetId]
    if screen and type(screen.Hide) == "function" then screen:Hide() end
    if self.current == targetId then self.current = nil end
end

function Screens:Back()
    local id = table.remove(self.history)
    if id then return self:Show(id, false) end
    return false
end

function Screens:Home()
    if not self.homeId then return false end
    return self:Show(self.homeId, false)
end

function Screens:CloseCompanion()
    local screen = self.current and self.registry[self.current]
    if screen and type(screen.Hide) == "function" then
        UI:SafeCall("close screen " .. tostring(self.current), screen.Hide, screen)
    end
    self.current = nil
    self.history = {}
    if APB and APB.C43 and APB.C43.Hide then APB.C43:Hide() end
end

UI.ScreenManager = Screens
UI.modules.ScreenManager = true
