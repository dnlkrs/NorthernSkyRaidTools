local _, NSI = ... -- Internal namespace

-- Alerts that are linked to a BigWigs bar instead of an encounter timeline.
-- They are scheduled when BigWigs starts the bar and count down to its expiry.

NSI.BigWigsAlerts = NSI.BigWigsAlerts or {}

local activeTimers = {}   -- [barKey] = { timers }

local function GetModuleEncounterID(module)
    if type(module) ~= "table" then return nil end
    local engageId = module.engageId
    if type(engageId) == "table" then engageId = engageId[1] end
    return tonumber(engageId)
end

local function GetBarKey(module, spellID)
    local moduleName = (type(module) == "table" and (module.moduleName or module.name)) or tostring(module)
    return moduleName .. ":" .. tostring(spellID)
end

local function MatchesModule(alert, module, moduleEncID)
    local link = alert.bigwigs
    if not link then return false end
    if link.module and type(module) == "table" then
        local moduleName = module.moduleName or module.name
        if moduleName and link.module == moduleName then return true end
    end
    local alertEncID = alert.encID or 0
    if alertEncID == 0 then return true end
    return alertEncID == moduleEncID
end

function NSI:GetBigWigsAlertsForBar(module, spellID)
    local matches
    local moduleEncID = GetModuleEncounterID(module)
    for _, alerts in pairs(NSRT.BigWigsAlerts or {}) do
        for _, alert in pairs(alerts) do
            if type(alert) == "table" and alert.enabled ~= false
                    and alert.bigwigs and alert.bigwigs.spellID == spellID
                    and MatchesModule(alert, module, moduleEncID)
                    and self:EvaluateLoad(alert) then
                matches = matches or {}
                matches[#matches + 1] = alert
            end
        end
    end
    return matches
end

local function CancelBar(barKey)
    local timers = activeTimers[barKey]
    if not timers then return end
    for _, timer in ipairs(timers) do
        timer:Cancel()
    end
    activeTimers[barKey] = nil
end

function NSI:CancelAllBigWigsAlerts()
    for barKey in pairs(activeTimers) do
        CancelBar(barKey)
    end
end

function NSI:ScheduleBigWigsAlert(alert, barKey, barTime, barText)
    local info = CopyTable(alert)
    info.IsAlert = true
    info.bigwigs = nil
    info.time    = math.max(barTime - (tonumber(alert.offset) or 0), 0)
    if info.time <= 0 then return end
    if not info.text or info.text == "" then
        info.text = barText or alert.name
    end

    info = self:CreateReminder(info)
    if not info then return end   -- nil while alerts are routed to TimelineReminders

    local delay = math.max(info.time - info.dur, 0)
    activeTimers[barKey] = activeTimers[barKey] or {}
    local timers = activeTimers[barKey]
    timers[#timers + 1] = C_Timer.NewTimer(delay, function()
        self:DisplayReminder(info)
    end)
end

local messageHandler = {}

function messageHandler:BigWigs_StartBar(_, module, spellID, barText, barTime)
    barTime = tonumber(barTime)
    if type(spellID) ~= "number" or not barTime or barTime <= 0 then return end

    local alerts = NSI:GetBigWigsAlertsForBar(module, spellID)
    if not alerts then return end

    local barKey = GetBarKey(module, spellID)
    CancelBar(barKey)
    for _, alert in ipairs(alerts) do
        NSI:ScheduleBigWigsAlert(alert, barKey, barTime, barText)
    end
end

function messageHandler:BigWigs_StopBar(_, module, spellID)
    -- BigWigs sends the bar text here when the bar was started with custom text.
    if type(spellID) == "number" then
        CancelBar(GetBarKey(module, spellID))
    end
end

function messageHandler:BigWigs_StopBars(_, module)
    local moduleName = (type(module) == "table" and (module.moduleName or module.name)) or tostring(module)
    for barKey in pairs(activeTimers) do
        if barKey:sub(1, #moduleName + 1) == moduleName .. ":" then
            CancelBar(barKey)
        end
    end
end

function messageHandler:BigWigs_OnBossDisable(_, module)
    self:BigWigs_StopBars(nil, module)
end

local registered = false

function NSI:RegisterBigWigsAlerts()
    if registered then return end
    local loader = _G.BigWigsLoader
    if not (loader and loader.RegisterMessage) then return end

    loader.RegisterMessage(messageHandler, "BigWigs_StartBar")
    loader.RegisterMessage(messageHandler, "BigWigs_StopBar")
    loader.RegisterMessage(messageHandler, "BigWigs_StopBars")
    loader.RegisterMessage(messageHandler, "BigWigs_OnBossDisable")
    registered = true
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("ENCOUNTER_END")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ENCOUNTER_END" then
        NSI:CancelAllBigWigsAlerts()
    elseif event == "PLAYER_LOGIN" or arg1 == "BigWigs" or arg1 == "BigWigs_Core" then
        NSI:RegisterBigWigsAlerts()
    end
end)
