local UI = EchoesUI
if not UI then return end

local InputManager = {}
InputManager.__index = InputManager

function InputManager:New(owner, options)
    options = options or {}
    local manager = setmetatable({
        owner = owner,
        controls = {},
        controlsById = {},
        focusIndex = nil,
        focusId = nil,
        orderedIds = nil,
        navigation = nil,
        onEscape = nil,
        isInputCaptured = options.isInputCaptured,
    }, self)

    if options.installHandler ~= false then
        owner:EnableKeyboard(true)
        owner:SetScript("OnKeyDown", function(_, key)
            manager:HandleKey(key)
        end)
    end
    return manager
end

function InputManager:Add(control, id)
    self.controls[#self.controls + 1] = control
    local controlId = id or control.id
    if controlId then self.controlsById[controlId] = control end
end

function InputManager:SetNavigation(orderedIds, navigation)
    self.orderedIds = orderedIds
    self.navigation = navigation
end

function InputManager:ClearFocus()
    if self.focusIndex and self.controls[self.focusIndex] then
        self.controls[self.focusIndex]:SetFocused(false)
    end
    self.focusIndex = nil
    self.focusId = nil
end

function InputManager:SetFocus(index)
    if #self.controls == 0 then return end
    if index < 1 then index = #self.controls end
    if index > #self.controls then index = 1 end

    if self.focusIndex and self.controls[self.focusIndex] then
        self.controls[self.focusIndex]:SetFocused(false)
    end
    self.focusIndex = index
    local control = self.controls[index]
    control:SetFocused(true)
    self.focusId = control.id
    UI:Debug("focus=" .. tostring(control.id or index))
end

function InputManager:SetFocusById(id)
    local control = self.controlsById[id]
    if not control then return false end

    if self.focusId and self.controlsById[self.focusId] then
        self.controlsById[self.focusId]:SetFocused(false)
    elseif self.focusIndex and self.controls[self.focusIndex] then
        self.controls[self.focusIndex]:SetFocused(false)
    end

    self.focusId = id
    self.focusIndex = nil
    for index, candidate in ipairs(self.controls) do
        if candidate == control then self.focusIndex = index break end
    end
    control:SetFocused(true)
    UI:Debug("focus=" .. tostring(id))
    return true
end

function InputManager:HandleKey(key)
    -- Never intercept keystrokes while a chat edit box has focus (typing a
    -- message, a slash command, whispering, etc.) - the proof host must
    -- not swallow Enter/letters meant for chat just because it also has
    -- EnableKeyboard(true) active.
    if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return end
    if self.isInputCaptured and self.isInputCaptured() then return end

    if key == "ESCAPE" then
        if self.onEscape then self.onEscape() end
    elseif key == "TAB" then
        if self.orderedIds and #self.orderedIds > 0 then
            if not self.focusId then
                local target = IsShiftKeyDown() and self.orderedIds[#self.orderedIds]
                    or self.orderedIds[1]
                self:SetFocusById(target)
                return
            end
            local current = 1
            for index, id in ipairs(self.orderedIds) do
                if id == self.focusId then current = index break end
            end
            local delta = IsShiftKeyDown() and -1 or 1
            local nextIndex = current + delta
            if nextIndex < 1 then nextIndex = #self.orderedIds end
            if nextIndex > #self.orderedIds then nextIndex = 1 end
            self:SetFocusById(self.orderedIds[nextIndex])
            return
        end
        local delta = IsShiftKeyDown() and -1 or 1
        self:SetFocus((self.focusIndex or (delta > 0 and 0 or 1)) + delta)
    elseif key == "ENTER" or key == "SPACE" then
        if not self.focusIndex then
            if self.defaultFocusId then self:SetFocusById(self.defaultFocusId)
            else self:SetFocus(1) end
        end
        local control = self.controls[self.focusIndex]
        if control then control:Activate("keyboard") end
    elseif self.navigation and (self.focusId or self.defaultFocusId) then
        if not self.focusId then self:SetFocusById(self.defaultFocusId) end
        if self.onNavigate and self.onNavigate(key, self.focusId) then return end
        local graph = self.navigation[self.focusId]
        if graph and graph[key] then self:SetFocusById(graph[key]) end
    end
end

UI.InputManager = InputManager
UI.modules.InputManager = true
