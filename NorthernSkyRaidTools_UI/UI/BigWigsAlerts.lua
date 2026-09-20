local addonId = "NorthernSkyRaidTools"
local NSI = _G.NorthernSkyRaidTools
local DF = _G["DetailsFramework"]
local Core                      = NSI.UI.Core
local NSUI                      = Core.NSUI
local content_width             = Core.content_width
local tab_content_height        = Core.tab_content_height

local CreateLocalizedButton    = NSI.UI.Components.CreateLocalizedButton
local CreateLocalizedSubButton = NSI.UI.Components.CreateLocalizedSubButton
local CreateDropdown           = NSI.UI.Components.CreateDropdown
local CreateTextEntry          = NSI.UI.Components.CreateTextEntry
local CreateCheckButton        = NSI.UI.Components.CreateCheckButton
local CreateColorPicker        = NSI.UI.Components.CreateColorPicker
local ReskinScrollbar          = NSI.UI.Components.ReskinScrollbar
local CreateStyledFrame        = NSI.UI.Components.CreateFrame
local BossData                 = NSI.UI.BossData

local function SetLocalizedText(object, key)
    NSI.UI.Components.RegisterLocalizedText(object, key)
end

-- ============================================================================
-- BigWigs addon modules
-- Add new content packs here, isCurrentContent modules are loaded
-- automatically when the timer picker opens.
-- ============================================================================
local BIGWIGS_MODULES = {
    ["BigWigs_TheVenomousAbyss"] = { isCurrentContent = true },
    ["BigWigs_MidnightLairs"]    = { isCurrentContent = true },
    ["BigWigs_Sporefall"]        = {},
    ["BigWigs_MarchOnQuelDanas"] = {},
    ["BigWigs_TheDreamrift"]     = {},
    ["BigWigs_TheVoidspire"]     = {},

    ["LittleWigs"]                  = { isCurrentContent = true },
    ["LittleWigs_BattleForAzeroth"] = { isCurrentContent = true },
}

local function LoadModules(predicate)
    local loadedAny = false
    C_AddOns.LoadAddOn("BigWigs_Core")
    for name, info in pairs(BIGWIGS_MODULES) do
        if (not predicate or predicate(info)) and not C_AddOns.IsAddOnLoaded(name)
                and C_AddOns.DoesAddOnExist(name) then
            C_AddOns.LoadAddOn(name)
        end
    end
    return loadedAny
end

local CIRCLE_TEXTURES = {
    {label="2 px",  value=[[Interface\AddOns\NorthernSkyRaidTools\Media\Textures\circle_2px.png]]},
    {label="5 px",  value=[[Interface\AddOns\NorthernSkyRaidTools\Media\Textures\circle_5px.png]]},
    {label="8 px",  value=[[Interface\AddOns\NorthernSkyRaidTools\Media\Textures\circle_8px.png]]},
    {label="10 px", value=[[Interface\AddOns\NorthernSkyRaidTools\Media\Textures\circle_10px.png]]},
    {label="15 px", value=[[Interface\AddOns\NorthernSkyRaidTools\Media\Textures\circle_15px.png]]},
}

local function GetCircleTextureLabel(texture)
    for _, option in ipairs(CIRCLE_TEXTURES) do
        if option.value == texture then return option.label end
    end
    return texture and tostring(texture) or ""
end

local function GetDefaultCircleTextureLabel()
    local texture = NSRT.ReminderSettings and NSRT.ReminderSettings.CircleSettings
        and NSRT.ReminderSettings.CircleSettings.Texture
    return NSI:Loc("Default") .. " (" .. GetCircleTextureLabel(texture) .. ")"
end

-- ============================================================================
-- BigWigs data collection
-- ============================================================================
local function GetBigWigs()
    local bw = _G.BigWigs
    if bw and type(bw.IterateBossModules) == "function" then return bw end
    return nil
end

local function GetModuleEncounterID(module)
    local engageId = module.engageId
    if type(engageId) == "table" then engageId = engageId[1] end
    return tonumber(engageId) or 0
end

local function GetModuleOptions(module)
    if type(module.GetOptions) == "function" then
        local ok, options = pcall(module.GetOptions, module)
        if ok and type(options) == "table" then return options end
    end
    if type(module.toggleOptions) == "table" then return module.toggleOptions end
    return {}
end

local function GetOptionKey(option)
    if type(option) == "table" then return option[1] end
    return option
end

local timerIndex = nil

local function BuildTimerIndex()
    local list = {}
    local bw = GetBigWigs()
    if not bw then return list end

    for a, b in bw:IterateBossModules() do
        local module = type(b) == "table" and b or a
        if type(module) == "table" then
            local encID         = GetModuleEncounterID(module)
            local moduleName    = module.moduleName or module.name or tostring(module)
            local moduleDisplay = module.displayName or moduleName
            local seen          = {}

            for _, option in ipairs(GetModuleOptions(module)) do
                local spellID = GetOptionKey(option)
                -- Options that are not positive spell IDs are BigWigs' own
                -- toggles (stages, warmups, custom keys) and carry no timer.
                if type(spellID) == "number" and spellID > 0 and not seen[spellID] then
                    seen[spellID] = true
                    local info = C_Spell.GetSpellInfo(spellID)
                    if info and info.name then
                        list[#list + 1] = {
                            encID         = encID,
                            moduleName    = moduleName,
                            moduleDisplay = moduleDisplay,
                            spellID       = spellID,
                            name          = info.name,
                            icon          = info.iconID,
                            search        = string.lower(info.name .. " " .. moduleDisplay .. " " .. spellID),
                        }
                    end
                end
            end
        end
    end

    table.sort(list, function(x, y)
        local ox = NSI.EncounterOrder[x.encID] or 99
        local oy = NSI.EncounterOrder[y.encID] or 99
        if ox ~= oy then return ox < oy end
        if x.moduleDisplay ~= y.moduleDisplay then return x.moduleDisplay < y.moduleDisplay end
        return x.name < y.name
    end)
    return list
end

local function GetTimerIndex(forceRefresh)
    if forceRefresh or not timerIndex then
        timerIndex = BuildTimerIndex()
    end
    return timerIndex
end

-- ============================================================================
-- Alert storage
-- ============================================================================
local function GetAlertStore()
    NSRT.BigWigsAlerts = NSRT.BigWigsAlerts or {}
    return NSRT.BigWigsAlerts
end

local function GetEncounterAlerts(encID)
    local store = GetAlertStore()
    store[encID] = store[encID] or {}
    return store[encID]
end

local function GetAlert(encID, key)
    local store = GetAlertStore()
    return store[encID] and store[encID][key] or nil
end

local function GetEncounterLabel(encID, fallback)
    local bossName = NSI.BossNames[encID]
    if bossName then return NSI:Loc(bossName) end
    if fallback and fallback ~= "" then return fallback end
    return NSI:Loc("Unknown Encounter")
end

local function SaveAlertData(alert, dataKey, newData)
    if not alert then return end
    alert[dataKey] = newData
end

-- ============================================================================
-- BuildBigWigsAlertsUI
-- ============================================================================
local function BuildBigWigsAlertsUI(parentFrame)
    local screen = parentFrame

    local leftWidth  = 240
    local pad        = 10
    local topY       = -10
    local lineHeight = 22
    local rightX     = leftWidth + pad * 2
    local rightW     = content_width - rightX - pad
    local listW      = leftWidth - pad * 2

    local selectedEncID, selectedKey
    local collapsedGroups = {}

    local rightPanel, RebuildList, SelectAlert, TogglePicker, PreviewAlert
    local enabledCB

    -- ------------------------------------------------------------------
    -- Left panel: title + alert list
    -- ------------------------------------------------------------------
    local title = screen:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(title, 16, "OUTLINE")
    title:SetPoint("TOPLEFT", screen, "TOPLEFT", pad, topY)
    title:SetText(NSI:Loc("|cFF00FFFFBigWigs|r Alerts"))

    local scrollTop    = topY - 24
    local scrollHeight = tab_content_height + scrollTop - pad * 2 - 18

    local listScroll = CreateFrame("ScrollFrame", "NSUIBWAlertListScroll", screen,
        "UIPanelScrollFrameTemplate")
    listScroll:SetSize(listW, scrollHeight)
    listScroll:SetPoint("TOPLEFT", screen, "TOPLEFT", pad, scrollTop)
    ReskinScrollbar(listScroll)

    local listChild = CreateFrame("Frame", nil, listScroll, "BackdropTemplate")
    listChild:SetSize(listW, 1)
    listChild:SetBackdrop({ bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
        tile = true, tileSize = 64 })
    listChild:SetBackdropColor(0.04, 0.04, 0.04, 0.6)
    listScroll:SetScrollChild(listChild)

    local listRows        = {}
    local groupHeaderRows = {}

    local function CreateGroupHeaderRow()
        local row = CreateFrame("Frame", nil, listChild, "BackdropTemplate")
        row:SetSize(listChild:GetWidth(), lineHeight)
        DF:ApplyStandardBackdrop(row)
        row.__background:SetVertexColor(0.05, 0.30, 0.40)
        row.__background:SetAlpha(0.90)

        row.collapseArrow = row:CreateTexture(nil, "OVERLAY")
        row.collapseArrow:SetSize(12, 12)
        row.collapseArrow:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.collapseArrow:SetVertexColor(0.4, 0.85, 1, 1)

        row.bossIcon = row:CreateTexture(nil, "ARTWORK")
        row.bossIcon:SetSize(16, 16)
        row.bossIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.bossIcon:SetPoint("LEFT", row, "LEFT", 18, 0)

        row.nameLabel = row:CreateFontString(nil, "OVERLAY")
        NSI:SetUIFont(row.nameLabel, 13, NSI:GetUIFontFlags())
        row.nameLabel:SetTextColor(0.2, 0.85, 1, 1)
        row.nameLabel:SetPoint("RIGHT", row, "RIGHT", -36, 0)
        row.nameLabel:SetJustifyH("LEFT")
        row.nameLabel:SetWordWrap(false)

        row.countLabel = row:CreateFontString(nil, "OVERLAY")
        NSI:SetUIFont(row.countLabel, 12, NSI:GetUIFontFlags())
        row.countLabel:SetTextColor(0.5, 0.5, 0.5, 1)
        row.countLabel:SetPoint("RIGHT", row, "RIGHT", -4, 0)

        row:EnableMouse(true)
        row:Hide()
        return row
    end

    local function CreateListRow()
        local row = CreateFrame("Frame", nil, listChild, "BackdropTemplate")
        row:SetSize(listChild:GetWidth(), lineHeight)
        DF:ApplyStandardBackdrop(row)
        row.__background:SetVertexColor(0.4, 0.4, 0.4)
        row.__background:SetAlpha(0.5)

        local cb = CreateCheckButton(row, "", nil, nil, 14, 14)
        cb:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.enabledCB = cb

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", cb.frame, "RIGHT", 4, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        row.nameLabel = row:CreateFontString(nil, "OVERLAY")
        NSI:SetUIFont(row.nameLabel, 13, "")
        row.nameLabel:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.nameLabel:SetJustifyH("LEFT")
        row.nameLabel:SetWordWrap(false)

        row.deleteBtn = CreateFrame("Button", nil, row)
        row.deleteBtn:SetSize(14, 14)
        row.deleteBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.deleteBtn:SetNormalTexture([[Interface\AddOns\NorthernSkyRaidTools\Media\Icons\trash-2.png]])
        row.deleteBtn:SetHighlightTexture([[Interface\AddOns\NorthernSkyRaidTools\Media\Icons\trash-2.png]])
        row.deleteBtn:GetNormalTexture():SetDesaturated(true)
        row.deleteBtn:GetNormalTexture():SetVertexColor(0.9, 0.3, 0.3)

        row.nameLabel:SetPoint("RIGHT", row.deleteBtn, "LEFT", -4, 0)

        row:EnableMouse(true)
        row:Hide()
        return row
    end

    local function DeleteAlert(encID, key)
        local alerts = GetAlertStore()[encID]
        if alerts then alerts[key] = nil end
        if selectedEncID == encID and selectedKey == key then
            selectedEncID, selectedKey = nil, nil
            if rightPanel then rightPanel:Hide() end
        end
        RebuildList()
    end

    local function ConfirmDeleteAlert(encID, key)
        local dialog = NSI.UI.Components.CreateDialog("NSRTDeleteBWAlertConfirm" .. tostring(key),
            NSI:Loc("Delete Alert"), NSI:Loc("Are you sure you want to delete this alert?"),
            NSI:Loc("Cancel"), nil, NSI:Loc("Delete"), function()
                DeleteAlert(encID, key)
            end, nil)
        dialog:Show()
    end

    -- Flattens the store into an ordered list of group headers and alert rows.
    local function BuildScrollData()
        local groups = {}
        for encID, alerts in pairs(GetAlertStore()) do
            local items = {}
            for key, alert in pairs(alerts) do
                if type(alert) == "table" then
                    items[#items + 1] = { encID = encID, key = key, data = alert }
                end
            end
            if #items > 0 then
                table.sort(items, function(x, y)
                    local nx = x.data.name or ""
                    local ny = y.data.name or ""
                    if nx ~= ny then return nx < ny end
                    return tostring(x.key) < tostring(y.key)
                end)
                groups[#groups + 1] = {
                    encID = encID,
                    label = GetEncounterLabel(encID, items[1].data.bigwigs and items[1].data.bigwigs.moduleDisplay),
                    items = items,
                }
            end
        end

        table.sort(groups, function(x, y)
            local ox = NSI.EncounterOrder[x.encID] or 99
            local oy = NSI.EncounterOrder[y.encID] or 99
            if ox ~= oy then return ox < oy end
            return x.label < y.label
        end)

        local data = {}
        for _, group in ipairs(groups) do
            local collapsed = collapsedGroups[group.encID] == true
            data[#data + 1] = {
                _type     = "group_header",
                encID     = group.encID,
                label     = group.label,
                count     = #group.items,
                collapsed = collapsed,
            }
            if not collapsed then
                for _, item in ipairs(group.items) do
                    item._type = "alert"
                    data[#data + 1] = item
                end
            end
        end
        return data
    end

    local function GetAlertIcon(alert)
        local customIcon = alert.customIcon and C_Spell.GetSpellInfo(alert.customIcon)
        if customIcon then return customIcon.iconID end
        local spell = alert.spellID and C_Spell.GetSpellInfo(alert.spellID)
        if spell then return spell.iconID end
        return alert.icon or BossData.BossIcons[alert.encID]
    end

    RebuildList = function()
        local savedScroll = listScroll:GetVerticalScroll()
        local data = BuildScrollData()

        local alertIdx, groupIdx, slot = 0, 0, 0

        for _, entry in ipairs(data) do
            slot = slot + 1
            if entry._type == "group_header" then
                groupIdx = groupIdx + 1
                groupHeaderRows[groupIdx] = groupHeaderRows[groupIdx] or CreateGroupHeaderRow()
                local row = groupHeaderRows[groupIdx]
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -(slot - 1) * lineHeight)
                row:SetWidth(listChild:GetWidth())
                row.collapseArrow:SetTexture(entry.collapsed and
                    [[Interface\AddOns\NorthernSkyRaidTools\Media\Icons\chevron-down.png]] or
                    [[Interface\AddOns\NorthernSkyRaidTools\Media\Icons\chevron-up.png]])

                local bossIconTex = BossData.BossIcons[entry.encID]
                row.nameLabel:ClearAllPoints()
                row.nameLabel:SetPoint("RIGHT", row, "RIGHT", -36, 0)
                if bossIconTex then
                    row.bossIcon:SetTexture(bossIconTex)
                    row.bossIcon:Show()
                    row.nameLabel:SetPoint("LEFT", row.bossIcon, "RIGHT", 4, 0)
                else
                    row.bossIcon:Hide()
                    row.nameLabel:SetPoint("LEFT", row, "LEFT", 18, 0)
                end
                row.nameLabel:SetText(entry.label)
                row.countLabel:SetText("(" .. entry.count .. ")")

                local encID = entry.encID
                row:SetScript("OnMouseDown", function()
                    collapsedGroups[encID] = not collapsedGroups[encID]
                    RebuildList()
                end)
                row:Show()
            else
                alertIdx = alertIdx + 1
                listRows[alertIdx] = listRows[alertIdx] or CreateListRow()
                local row = listRows[alertIdx]
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 14, -(slot - 1) * lineHeight)
                row:SetWidth(listChild:GetWidth() - 14)
                row:Show()

                local alert      = entry.data
                local isSelected = selectedEncID == entry.encID and selectedKey == entry.key
                if isSelected then
                    row.__background:SetVertexColor(0, 1, 1)
                    row.__background:SetAlpha(1)
                else
                    row.__background:SetVertexColor(0.4, 0.4, 0.4)
                    row.__background:SetAlpha(0.5)
                end

                local icon = GetAlertIcon(alert)
                if icon then
                    row.icon:SetTexture(icon)
                    row.icon:Show()
                else
                    row.icon:Hide()
                end

                row.nameLabel:SetText(alert.name or NSI:Loc("Unnamed"))
                row.nameLabel:SetTextColor(1, 1, 1, alert.enabled ~= false and 1 or 0.45)

                local encID, key = entry.encID, entry.key
                row.enabledCB:SetValue(alert.enabled ~= false)
                row.enabledCB:SetOnChange(function(_, value)
                    alert.enabled = value
                    if selectedEncID == encID and selectedKey == key and enabledCB then
                        enabledCB:SetValue(value)
                    end
                    RebuildList()
                end)

                row.deleteBtn:SetScript("OnClick", function()
                    ConfirmDeleteAlert(encID, key)
                end)
                row:SetScript("OnMouseDown", function()
                    if row.enabledCB.frame:IsMouseOver() then return end
                    SelectAlert(encID, key)
                end)
            end
        end

        for i = alertIdx + 1, #listRows        do listRows[i]:Hide() end
        for i = groupIdx + 1, #groupHeaderRows do groupHeaderRows[i]:Hide() end

        local totalH = math.max(slot * lineHeight, 1)
        listChild:SetHeight(totalH)
        local bar = _G["NSUIBWAlertListScrollScrollBar"]
        if bar then
            local maxScroll = math.max(0, totalH - listScroll:GetHeight())
            bar:SetMinMaxValues(0, maxScroll)
            local clamped = math.min(savedScroll, maxScroll)
            bar:SetValue(clamped)
            listScroll:SetVerticalScroll(clamped)
        end
    end
    screen.RebuildList = RebuildList

    local createBtn = CreateLocalizedButton(screen, "+ Create Alert", function()
        TogglePicker()
    end, listW, 18)
    createBtn:SetPoint("BOTTOMLEFT", screen, "BOTTOMLEFT", pad, 8)

    -- ------------------------------------------------------------------
    -- BigWigs timer picker popup
    -- ------------------------------------------------------------------
    local PICKER_PAD    = 12
    local PICKER_W      = 420
    local PICKER_H      = 460
    local PICKER_INNER  = PICKER_W - PICKER_PAD * 2
    local pickerRowH    = 24
    local pickerSearch  = ""

    local pickerFrame = CreateStyledFrame(NSUI, PICKER_W, PICKER_H, "NSRTBigWigsTimerPicker")
    pickerFrame:SetPoint("TOPLEFT", NSUI, "TOPRIGHT", 4, 0)
    pickerFrame:Hide()

    local pickerTitle = pickerFrame:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(pickerTitle, 14, "OUTLINE")
    SetLocalizedText(pickerTitle, "Select a BigWigs Timer")
    pickerTitle:SetPoint("TOPLEFT", pickerFrame, "TOPLEFT", PICKER_PAD, -10)

    local pickerSearchEntry = CreateTextEntry(pickerFrame, nil, nil, nil, PICKER_INNER, 22,
        nil, nil, nil, "NSUIBWTimerSearch")
    pickerSearchEntry:SetPoint("TOPLEFT", pickerFrame, "TOPLEFT", PICKER_PAD, -34)

    local pickerSearchHint = pickerSearchEntry.editBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pickerSearchHint:SetText("|TInterface\\Common\\UI-Searchbox-Icon:16:16:0:-2|t  " .. NSI:Loc("Search..."))
    pickerSearchHint:SetPoint("LEFT", pickerSearchEntry.editBox, "LEFT", 2, 0)
    pickerSearchHint:SetTextColor(0.5, 0.5, 0.5, 0.6)
    NSI:SetUIFont(pickerSearchHint, 14, "")

    local pickerResultsH = PICKER_H - 96
    local pickerListW    = PICKER_INNER - 20   -- leaves room for the native scrollbar
    local pickerScroll = CreateFrame("ScrollFrame", "NSUIBWTimerPickerScroll", pickerFrame,
        "UIPanelScrollFrameTemplate")
    pickerScroll:SetSize(pickerListW, pickerResultsH)
    pickerScroll:SetPoint("TOPLEFT", pickerFrame, "TOPLEFT", PICKER_PAD, -62)
    ReskinScrollbar(pickerScroll)

    local pickerChild = CreateFrame("Frame", nil, pickerScroll, "BackdropTemplate")
    pickerChild:SetSize(pickerListW, 1)
    pickerChild:SetBackdrop({ bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
        tile = true, tileSize = 64 })
    pickerChild:SetBackdropColor(0.04, 0.04, 0.04, 0.85)
    pickerScroll:SetScrollChild(pickerChild)

    local pickerStatus = pickerFrame:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(pickerStatus, 12, "")
    pickerStatus:SetTextColor(0.9, 0.75, 0.2, 1)
    pickerStatus:SetWidth(pickerListW - 12)
    pickerStatus:SetJustifyH("LEFT")
    pickerStatus:SetPoint("TOPLEFT", pickerScroll, "TOPLEFT", 6, -6)
    pickerStatus:Hide()

    local pickerRows = {}
    local RebuildPickerRows

    local function CreatePickerRow()
        local row = CreateFrame("Button", nil, pickerChild)
        row:SetSize(pickerChild:GetWidth(), pickerRowH)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(row)

        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints(row)
        row.highlight:SetColorTexture(0, 1, 1, 0.13)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        row.bossLabel = row:CreateFontString(nil, "OVERLAY")
        NSI:SetUIFont(row.bossLabel, 11, "")
        row.bossLabel:SetTextColor(0.55, 0.55, 0.55, 1)
        row.bossLabel:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.bossLabel:SetJustifyH("RIGHT")
        row.bossLabel:SetWordWrap(false)

        row.nameLabel = row:CreateFontString(nil, "OVERLAY")
        NSI:SetUIFont(row.nameLabel, 13, "")
        row.nameLabel:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.nameLabel:SetPoint("RIGHT", row.bossLabel, "LEFT", -6, 0)
        row.nameLabel:SetJustifyH("LEFT")
        row.nameLabel:SetWordWrap(false)

        row:Hide()
        return row
    end

    local function CreateAlertFromTimer(timer)
        local encID  = timer.encID or 0
        local alerts = GetEncounterAlerts(encID)
        local key    = NSI:UniqueAlertID(alerts, false)
        local s      = NSRT.ReminderSettings

        alerts[key] = {
            name    = timer.name,
            enabled = true,
            encID   = encID,
            icon    = timer.icon,
            spellID = timer.spellID,
            bigwigs = {
                module        = timer.moduleName,
                moduleDisplay = timer.moduleDisplay,
                spellID       = timer.spellID,
                timerName     = timer.name,
            },
            offset         = 0,
            DisplayType    = "Text",
            text           = timer.name,
            dur            = s.TextDuration or 8,
            TTS            = s.TextTTS and true or false,
            TTSTimer       = s.TextTTSTimer or 8,
            countdown      = false,
            sticky         = 0,
            loadConditions = { Classes = {}, SpecIDs = {}, Names = {}, Roles = {} },
        }

        pickerFrame:Hide()
        RebuildList()
        SelectAlert(encID, key)
    end

    RebuildPickerRows = function()
        local index    = GetTimerIndex()
        local filter   = string.lower(pickerSearch or "")
        local matches  = {}

        for _, timer in ipairs(index) do
            if filter == "" or string.find(timer.search, filter, 1, true) then
                matches[#matches + 1] = timer
            end
        end

        for _, row in ipairs(pickerRows) do row:Hide() end

        for i, timer in ipairs(matches) do
            pickerRows[i] = pickerRows[i] or CreatePickerRow()
            local row = pickerRows[i]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", pickerChild, "TOPLEFT", 0, -(i - 1) * pickerRowH)
            row:SetWidth(pickerChild:GetWidth())
            row.bg:SetColorTexture(0, 0, 0, i % 2 == 0 and 0.35 or 0)

            if timer.icon then
                row.icon:SetTexture(timer.icon)
                row.icon:Show()
            else
                row.icon:Hide()
            end
            row.nameLabel:SetText(timer.name)
            row.bossLabel:SetText(GetEncounterLabel(timer.encID, timer.moduleDisplay))

            local captured = timer
            row:SetScript("OnClick", function() CreateAlertFromTimer(captured) end)
            row:Show()
        end

        if #matches == 0 then
            pickerStatus:SetText(GetBigWigs() and NSI:Loc("No timers match your search.")
                or NSI:Loc("BigWigs is not loaded."))
            pickerStatus:Show()
        else
            pickerStatus:Hide()
        end

        local totalH = math.max(#matches * pickerRowH, 1)
        pickerChild:SetHeight(totalH)
        pickerScroll:UpdateScrollChildRect()
        local bar = _G["NSUIBWTimerPickerScrollScrollBar"]
        if bar then
            local maxScroll = math.max(0, totalH - pickerScroll:GetHeight())
            bar:SetMinMaxValues(0, maxScroll)
            if bar:GetValue() > maxScroll then bar:SetValue(maxScroll) end
        end
    end

    local function UpdatePickerSearchHint(editBox)
        pickerSearchHint:SetShown(editBox:GetText() == "" and not editBox:HasFocus())
    end

    pickerSearchEntry.editBox:SetScript("OnTextChanged", function(self)
        pickerSearch = self:GetText()
        UpdatePickerSearchHint(self)
        RebuildPickerRows()
    end)
    pickerSearchEntry.editBox:HookScript("OnEditFocusGained", function(self) UpdatePickerSearchHint(self) end)
    pickerSearchEntry.editBox:HookScript("OnEditFocusLost",   function(self) UpdatePickerSearchHint(self) end)

    local loadAllBtn = CreateLocalizedSubButton(pickerFrame, "Load all content", function()
        LoadModules()
        GetTimerIndex(true)
        RebuildPickerRows()
    end, 140, "NSUIBWTimerPickerLoadAll",
        { title = "Load all content", desc = "Loads every BigWigs content module so their timers can be searched" })
    loadAllBtn:SetPoint("BOTTOMLEFT", pickerFrame, "BOTTOMLEFT", PICKER_PAD, 8)

    local closeBtn = CreateLocalizedSubButton(pickerFrame, "Close", function()
        pickerFrame:Hide()
    end, 90, "NSUIBWTimerPickerClose")
    closeBtn:SetPoint("BOTTOMRIGHT", pickerFrame, "BOTTOMRIGHT", -PICKER_PAD, 8)

    pickerFrame:HookScript("OnHide", function()
        timerIndex = nil
    end)

    TogglePicker = function()
        if pickerFrame:IsShown() then
            pickerFrame:Hide()
            return
        end
        LoadModules(function(info) return info.isCurrentContent end)
        GetTimerIndex(true)
        RebuildPickerRows()
        pickerFrame:Show()
        pickerSearchEntry.editBox:SetFocus()
    end

    -- ================================================================
    -- Right Panel
    -- ================================================================
    rightPanel = CreateFrame("Frame", nil, screen)
    rightPanel:SetPoint("TOPLEFT",     screen, "TOPLEFT",     rightX, topY)
    rightPanel:SetPoint("BOTTOMRIGHT", screen, "BOTTOMRIGHT", -pad,   pad)
    rightPanel:Hide()

    local nameLbl = rightPanel:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(nameLbl, 11, "")
    nameLbl:SetTextColor(0.55, 0.55, 0.55, 1)
    SetLocalizedText(nameLbl, "Alert Name")
    nameLbl:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 0, 0)

    local nameEntry = CreateTextEntry(rightPanel, nil, nil, nil, rightW - 240, 22,
        nil, nil, nil, "NSUIBWAlertNameEntry")
    nameEntry:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 0, -14)

    enabledCB = CreateCheckButton(rightPanel, NSI:Loc("Enabled"),
        function() return false end, nil, 90, 22, "NSUIBWAlertEnabled")
    enabledCB:SetLocaleKey("Enabled")
    enabledCB:SetPoint("LEFT", nameEntry.frame, "RIGHT", 12, 0)

    -- ── Inner tab bar ────────────────────────────────────────────────────────
    local INNER_TABS     = { "Display", "Trigger", "Sound", "Load" }
    local innerTabBtns   = {}
    local innerTabFrames = {}
    local activeInnerTab = "Display"

    local tabBtnW   = 84
    local tabBtnGap = 3
    local tabRowY   = -42
    local contentY  = tabRowY - 26

    local dispF, trigF, sndF, loadF

    local function SelectInnerTab(name)
        activeInnerTab = name
        for _, tn in ipairs(INNER_TABS) do
            local f = innerTabFrames[tn]
            f:SetShown(tn == name)
            if tn == name then
                innerTabBtns[tn]:Select()
                if f.Rebuild then f.Rebuild() end
            else
                innerTabBtns[tn]:Deselect()
            end
        end
    end

    for i, tabName in ipairs(INNER_TABS) do
        local btn = CreateLocalizedSubButton(rightPanel, tabName, function()
            SelectInnerTab(tabName)
        end, tabBtnW, "NSUIBWAlertInnerTab_" .. tabName)
        btn:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", (i - 1) * (tabBtnW + tabBtnGap), tabRowY)
        innerTabBtns[tabName] = btn
    end

    local previewBtn = CreateLocalizedButton(rightPanel, "Preview", function() PreviewAlert() end, 80, 18,
        "NSUIBWAlertPreview")
    previewBtn:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", 0, tabRowY)

    local tabSep = rightPanel:CreateTexture(nil, "ARTWORK")
    tabSep:SetColorTexture(0, 1, 1, 0.20)
    tabSep:SetHeight(1)
    tabSep:SetPoint("TOPLEFT",  rightPanel, "TOPLEFT",  0, tabRowY - 20)
    tabSep:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", 0, tabRowY - 20)

    for _, tabName in ipairs(INNER_TABS) do
        local f = CreateFrame("Frame", nil, rightPanel)
        f:SetPoint("TOPLEFT",     rightPanel, "TOPLEFT",     0, contentY)
        f:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", 0, 0)
        f:Hide()
        innerTabFrames[tabName] = f
    end

    -- ================================================================
    -- DISPLAY TAB
    -- ================================================================
    do
    dispF = innerTabFrames["Display"]

    local typeLbl = dispF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(typeLbl, 12, "")
    typeLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(typeLbl, "Type")
    typeLbl:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -2)

    local TYPES    = { "Text", "Bar", "Icon", "Circle" }
    local typeBtns = {}
    local typeBtnW = 70

    local function SetTypeButtons(t)
        for _, tn in ipairs(TYPES) do
            if tn == t then typeBtns[tn]:Select() else typeBtns[tn]:Deselect() end
        end
    end

    for i, tn in ipairs(TYPES) do
        local tb = CreateLocalizedSubButton(dispF, tn, function()
            if dispF._alert then SaveAlertData(dispF._alert, "DisplayType", tn) end
            dispF.SetDisplayType(tn)
        end, typeBtnW, "NSUIBWAlertType_" .. tn)
        tb:SetPoint("TOPLEFT", dispF, "TOPLEFT", (i - 1) * (typeBtnW + 3), -18)
        typeBtns[tn] = tb
    end

    local textLbl = dispF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(textLbl, 12, "")
    textLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(textLbl, "Display Text")
    textLbl:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -46)

    local textEntry = CreateTextEntry(dispF, nil, nil, nil, rightW, 22,
        nil, nil, nil, "NSUIBWAlertDisplayText")
    textEntry:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -62)
    textEntry.editBox:SetScript("OnEditFocusLost", function(self)
        if dispF._alert then SaveAlertData(dispF._alert, "text", self:GetText()) end
    end)
    dispF.textEntry = textEntry

    local spellLbl = dispF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(spellLbl, 12, "")
    spellLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(spellLbl, "Spell ID")
    spellLbl:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -90)

    local spellEntry = CreateTextEntry(dispF, nil, nil, nil, 130, 22,
        nil, nil, nil, "NSUIBWAlertSpellID",
        { title = "Spell ID", desc = "The icon of this spellid will be used for the in-combat display" })
    spellEntry:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -106)

    local spellIconFrame = CreateFrame("Frame", nil, dispF, "BackdropTemplate")
    spellIconFrame:SetSize(22, 22)
    spellIconFrame:SetPoint("LEFT", spellEntry.frame, "RIGHT", 4, 0)
    DF:ApplyStandardBackdrop(spellIconFrame)
    local spellIconTex = spellIconFrame:CreateTexture(nil, "ARTWORK")
    spellIconTex:SetPoint("TOPLEFT",     spellIconFrame, "TOPLEFT",     1,  -1)
    spellIconTex:SetPoint("BOTTOMRIGHT", spellIconFrame, "BOTTOMRIGHT", -1,  1)
    spellIconTex:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    spellIconFrame.texture = spellIconTex
    spellIconFrame:Hide()
    dispF.spellIconFrame = spellIconFrame

    local function UpdateSpellIcon(text)
        local id = tonumber(text)
        local spell = id and C_Spell.GetSpellInfo(id)
        if spell and spell.iconID then
            spellIconTex:SetTexture(spell.iconID)
            spellIconFrame:Show()
        else
            spellIconFrame:Hide()
        end
    end

    spellEntry.editBox:SetScript("OnTextChanged", function(self) UpdateSpellIcon(self:GetText()) end)
    spellEntry.editBox:SetScript("OnEditFocusLost", function(self)
        if dispF._alert then SaveAlertData(dispF._alert, "spellID", tonumber(self:GetText()) or nil) end
        RebuildList()
    end)
    dispF.spellEntry = spellEntry

    local useTauntCB = CreateCheckButton(dispF, NSI:Loc("Use Taunt spellid"),
        function() return dispF._alert and dispF._alert.isTaunt == true or false end,
        function(_, v)
            if dispF._alert then
                SaveAlertData(dispF._alert, "isTaunt", v or nil)
                RebuildList()
            end
        end,
        150, 22, "NSUIBWAlertUseTauntSpellID", {
            title = "Use Taunt spellid",
            desc = "Automatically uses the spellid for the taunt of your current class."
        })
    useTauntCB:SetLocaleKey("Use Taunt spellid")
    useTauntCB:SetPoint("TOPLEFT", dispF, "TOPLEFT", 164, -106)
    dispF.useTauntCB = useTauntCB

    local customIconLbl = dispF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(customIconLbl, 12, "")
    customIconLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(customIconLbl, "Custom Icon (overrides icon in list)")
    customIconLbl:SetPoint("TOPLEFT", dispF, "TOPLEFT", 330, -90)

    local customIconEntry = CreateTextEntry(dispF, nil, nil, nil, 180, 22,
        nil, nil, nil, "NSUIBWAlertCustomIcon",
        { title = "Custom Icon", desc = "Uses the spellid's icon for display in the alert-list. Does NOT change the in-combat display" })
    customIconEntry:SetPoint("TOPLEFT", dispF, "TOPLEFT", 330, -106)
    customIconEntry.editBox:SetScript("OnEditFocusLost", function(self)
        if dispF._alert then SaveAlertData(dispF._alert, "customIcon", tonumber(self:GetText()) or nil) end
        RebuildList()
    end)
    dispF.customIconEntry = customIconEntry

    local durLbl = dispF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(durLbl, 12, "")
    durLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(durLbl, "Duration")
    durLbl:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -134)

    local durEntry = CreateTextEntry(dispF, nil, nil, nil, 80, 22,
        nil, nil, nil, "NSUIBWAlertDuration",
        { title = "Duration", desc = "How long before the specified time this alert should start showing up" })
    durEntry:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -150)
    durEntry.editBox:SetScript("OnEditFocusLost", function(self)
        if dispF._alert then SaveAlertData(dispF._alert, "dur", tonumber(self:GetText()) or 8) end
    end)
    dispF.durEntry = durEntry

    local stickyLbl = dispF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(stickyLbl, 12, "")
    stickyLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(stickyLbl, "Sticky duration (0 to disable)")
    stickyLbl:SetPoint("TOPLEFT", durLbl, "TOPRIGHT", 55, 0)

    local stickyEntry = CreateTextEntry(dispF, nil, nil, nil, 80, 22,
        nil, nil, nil, "NSUIBWAlertSticky",
        { title = "Sticky duration", desc = "How long the alert should remain on screen when duration hits 0" })
    stickyEntry:SetPoint("TOPLEFT", durEntry.frame, "TOPRIGHT", 20, 0)
    stickyEntry.editBox:SetScript("OnEditFocusLost", function(self)
        if dispF._alert then SaveAlertData(dispF._alert, "sticky", tonumber(self:GetText())) end
    end)
    dispF.stickyEntry = stickyEntry

    local hideTimerCB = CreateCheckButton(dispF, NSI:Loc("Hide Timer Text"),
        function()
            if not dispF._alert then return false end
            if dispF._alert.HideTimer ~= nil then return dispF._alert.HideTimer end
            return false
        end,
        function(_, v) if dispF._alert then SaveAlertData(dispF._alert, "HideTimer", v or nil) end end,
        135, 22, "NSUIBWAlertHideTimer",
        { title = "Hide Timer Text", desc = "Hides the remaining duration text of this alert" })
    hideTimerCB:SetLocaleKey("Hide Timer Text")
    hideTimerCB:SetPoint("LEFT", stickyEntry.frame, "RIGHT", 14, 0)
    dispF.hideTimerCB = hideTimerCB

    local hideSwipeCB = CreateCheckButton(dispF, NSI:Loc("Hide Swipe"),
        function()
            if not dispF._alert then return false end
            if dispF._alert.HideSwipe ~= nil then return dispF._alert.HideSwipe end
            return NSRT.ReminderSettings.IconSettings.HideSwipe or false
        end,
        function(_, v) if dispF._alert then SaveAlertData(dispF._alert, "HideSwipe", v or nil) end end,
        110, 22, "NSUIBWAlertHideSwipe")
    hideSwipeCB:SetLocaleKey("Hide Swipe")
    hideSwipeCB:SetPoint("LEFT", hideTimerCB.frame, "RIGHT", 20, 0)
    hideSwipeCB.frame:Hide()
    dispF.hideSwipeCB = hideSwipeCB

    local glowunitLbl = dispF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(glowunitLbl, 12, "")
    glowunitLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(glowunitLbl, "Glow Unit (player names, space seperated)")
    glowunitLbl:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -178)

    local glowunitEntry = CreateTextEntry(dispF, nil, nil, nil, 200, 22,
        nil, nil, nil, "NSUIBWAlertGlowUnit",
        { title = "Glow unit", desc = "Creates a glow on these player's Raidframes" })
    glowunitEntry:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -194)
    glowunitEntry.editBox:SetScript("OnEditFocusLost", function(self)
        local v = self:GetText()
        if dispF._alert then SaveAlertData(dispF._alert, "glowunit", (v ~= "") and v or nil) end
    end)
    dispF.glowunitEntry = glowunitEntry

    local glowcolorlbl = dispF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(glowcolorlbl, 12, "")
    glowcolorlbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(glowcolorlbl, "Glow Color")
    glowcolorlbl:SetPoint("TOPLEFT", dispF, "TOPLEFT", 265, -198)

    local glowunitColor = CreateColorPicker(dispF, nil,
        function()
            local c = dispF._alert and dispF._alert.glowColors
            if c then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
            return unpack(NSRT.ReminderSettings.GlowSettings.colors)
        end,
        function(_, r, g, b, a)
            if dispF._alert then SaveAlertData(dispF._alert, "glowColors", {r, g, b, a}) end
        end,
        200, 22, "NSUIBWAlertGlowColors")
    glowunitColor:SetPoint("TOPLEFT", dispF, "TOPLEFT", 60, -194)
    dispF.glowunitColor = glowunitColor

    local colorsLbl = dispF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(colorsLbl, 12, "")
    colorsLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    NSI.UI.Components.RegisterLocalizedText(colorsLbl, "Color", function()
        local t = dispF._alert and (dispF._alert.DisplayType or "Text")
        if t == "Text" or t == "Icon" or t == "Circle" then
            return NSI:Loc("Text Color")
        end
        return NSI:Loc("Color")
    end)
    colorsLbl:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -216)
    dispF.colorsLbl = colorsLbl

    local colorsPicker = CreateColorPicker(dispF, nil,
        function()
            local c = dispF._alert and dispF._alert.textColors
            if c then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
            local dt = dispF._alert and dispF._alert.DisplayType or "Text"
            local typeMap = { Text="TextSettings", Icon="IconSettings", Circle="CircleSettings", Bar="BarSettings" }
            local fc = NSRT.ReminderSettings[typeMap[dt] or "TextSettings"].textColors
            if fc then return fc[1] or 1, fc[2] or 1, fc[3] or 1, fc[4] or 1 end
            return 1, 1, 1, 1
        end,
        function(_, r, g, b, a)
            if dispF._alert then SaveAlertData(dispF._alert, "textColors", {r, g, b, a}) end
        end,
        200, 22, "NSUIBWAlertColors")
    colorsPicker:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -216)
    dispF.colorsPicker = colorsPicker

    -- ── Circle section (shown only when display type = "Circle") ────────
    local circleSection = CreateFrame("Frame", nil, dispF)
    circleSection:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -266)
    circleSection:SetSize(rightW, 88)
    circleSection:Hide()

    local circleTextureLbl = circleSection:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(circleTextureLbl, 12, "")
    circleTextureLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(circleTextureLbl, "Texture")
    circleTextureLbl:SetPoint("TOPLEFT", circleSection, "TOPLEFT", 0, 26)

    local function BuildCircleTextureOptions()
        local opts = {
            {
                label = GetDefaultCircleTextureLabel(),
                value = nil,
                onclick = function()
                    if dispF._alert then SaveAlertData(dispF._alert, "Texture", nil) end
                end,
            },
        }
        for _, option in ipairs(CIRCLE_TEXTURES) do
            local label, value = option.label, option.value
            opts[#opts + 1] = {
                label = label,
                value = value,
                onclick = function()
                    if dispF._alert then SaveAlertData(dispF._alert, "Texture", value) end
                end,
            }
        end
        return opts
    end

    local function GetSelectedCircleTexture()
        if not (dispF._alert and dispF._alert.Texture) then return GetDefaultCircleTextureLabel() end
        return GetCircleTextureLabel(dispF._alert.Texture)
    end

    local circleTextureDD = CreateDropdown(circleSection, nil, BuildCircleTextureOptions,
        GetSelectedCircleTexture, 200, 22, "NSUIBWAlertCircleTexture")
    circleTextureDD:SetPoint("TOPLEFT", circleSection, "TOPLEFT", 0, 10)
    dispF.circleTextureDD = circleTextureDD

    local ringColorsLbl = circleSection:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(ringColorsLbl, 12, "")
    ringColorsLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(ringColorsLbl, "Ring Color")
    ringColorsLbl:SetPoint("TOPLEFT", circleTextureDD.frame, "BOTTOMLEFT", 0, -8)

    local ringColorsPicker = CreateColorPicker(circleSection, nil,
        function()
            local c = dispF._alert and dispF._alert.ringColors
            if c then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
            return unpack(NSRT.ReminderSettings.CircleSettings.ringColors)
        end,
        function(_, r, g, b, a) if dispF._alert then SaveAlertData(dispF._alert, "ringColors", {r, g, b, a}) end end,
        200, 22, "NSUIBWAlertRingColors")
    ringColorsPicker:SetPoint("TOPLEFT", ringColorsLbl, "BOTTOMLEFT", 0, 12)
    dispF.ringColorsPicker = ringColorsPicker

    local showBgCB = CreateCheckButton(circleSection, NSI:Loc("Show Background Ring"),
        function()
            if not dispF._alert then return NSRT.ReminderSettings.CircleSettings.showBackground end
            if dispF._alert.showBackground ~= nil then return dispF._alert.showBackground ~= false end
            return NSRT.ReminderSettings.CircleSettings.showBackground
        end,
        function(_, v) if dispF._alert then SaveAlertData(dispF._alert, "showBackground", v) end end,
        200, 22, "NSUIBWAlertShowBg")
    showBgCB:SetLocaleKey("Show Background Ring")
    showBgCB:SetPoint("TOPLEFT", ringColorsPicker.frame, "BOTTOMLEFT", 0, -4)
    dispF.showBgCB = showBgCB

    -- ── Bars section: Ticks (shown only when display type = "Bar") ───────
    local barsSection = CreateFrame("Frame", nil, dispF)
    barsSection:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -300)
    barsSection:SetSize(rightW, 130)
    barsSection:Hide()

    local ticksLbl = barsSection:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(ticksLbl, 12, "")
    ticksLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(ticksLbl, "Ticks (seconds into the display where ticks should appear)")
    ticksLbl:SetPoint("TOPLEFT", barsSection, "TOPLEFT", 0, 0)

    local ticksListH = 100
    local ticksListW = rightW - 20

    local ticksScroll = CreateFrame("ScrollFrame", "NSUIBWAlertTicksScroll", barsSection,
        "UIPanelScrollFrameTemplate")
    ticksScroll:SetSize(ticksListW, ticksListH)
    ticksScroll:SetPoint("TOPLEFT", barsSection, "TOPLEFT", 0, -16)
    ReskinScrollbar(ticksScroll)
    local ticksBg = ticksScroll:CreateTexture(nil, "BACKGROUND")
    ticksBg:SetAllPoints(ticksScroll)
    ticksBg:SetColorTexture(0.04, 0.04, 0.04, 0.85)

    local ticksChild = CreateFrame("Frame", nil, ticksScroll, "BackdropTemplate")
    ticksChild:SetSize(ticksListW - 18, 1)
    ticksChild:SetBackdrop({ bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
        tile = true, tileSize = 64 })
    ticksChild:SetBackdropColor(0.04, 0.04, 0.04, 0.85)
    ticksScroll:SetScrollChild(ticksChild)

    local tickRowH = 22
    local tickRows = {}

    local function RebuildTickRows()
        for _, row in ipairs(tickRows) do row:Hide() end
        if not dispF._alert then return end
        local ticks = dispF._alert.Ticks or {}
        for i, v in ipairs(ticks) do
            if not tickRows[i] then
                tickRows[i] = CreateFrame("Frame", nil, ticksChild)
                tickRows[i].bg = tickRows[i]:CreateTexture(nil, "BACKGROUND")
                tickRows[i].tLbl = tickRows[i]:CreateFontString(nil, "OVERLAY")
                tickRows[i].delBtn = CreateFrame("Button", nil, tickRows[i])
                tickRows[i].tLbl:SetTextColor(1, 1, 1, 1)
                tickRows[i].tLbl:SetPoint("LEFT", tickRows[i], "LEFT", 8, 0)
                tickRows[i].bg:SetAllPoints(tickRows[i])
                tickRows[i]:SetSize(ticksChild:GetWidth(), tickRowH)
                tickRows[i]:SetPoint("TOPLEFT", ticksChild, "TOPLEFT", 0, -(i - 1) * tickRowH)
                tickRows[i].delBtn:SetSize(14, 14)
                tickRows[i].delBtn:SetPoint("RIGHT", tickRows[i], "RIGHT", -6, 0)
                tickRows[i].delBtn:SetNormalTexture([[Interface\AddOns\NorthernSkyRaidTools\Media\Icons\x.png]])
                tickRows[i].delBtn:GetNormalTexture():SetDesaturated(true)
                tickRows[i].delBtn:GetNormalTexture():SetVertexColor(0.9, 0.3, 0.3)
            end
            if i % 2 == 0 then
                tickRows[i].bg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
            else
                tickRows[i].bg:SetColorTexture(0, 0, 0, 0)
            end
            NSI:SetUIFont(tickRows[i].tLbl, 13, "")
            tickRows[i].tLbl:SetText(tostring(v))

            tickRows[i].delBtn:SetScript("OnClick", function()
                if dispF._alert then
                    table.remove(dispF._alert.Ticks, i)
                    SaveAlertData(dispF._alert, "Ticks", dispF._alert.Ticks)
                    dispF.RebuildTickRows()
                end
            end)
            tickRows[i]:Show()
        end

        local totalH = math.max(#ticks * tickRowH, 1)
        ticksChild:SetHeight(totalH)
        local bar = _G["NSUIBWAlertTicksScrollScrollBar"]
        if bar then
            local maxScroll = math.max(0, totalH - ticksListH)
            bar:SetMinMaxValues(0, maxScroll)
            if bar:GetValue() > maxScroll then bar:SetValue(0) end
        end
    end
    dispF.RebuildTickRows = RebuildTickRows

    local addTickLbl = barsSection:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(addTickLbl, 11, "")
    addTickLbl:SetTextColor(0.55, 0.55, 0.55, 1)
    SetLocalizedText(addTickLbl, "Add tick")
    addTickLbl:SetPoint("TOPLEFT", ticksScroll, "BOTTOMLEFT", 0, -4)

    local addTickEntry = CreateTextEntry(barsSection, nil, nil, nil, 90, 22,
        nil, nil, nil, "NSUIBWAlertAddTick")
    addTickEntry:SetPoint("TOPLEFT", ticksScroll, "BOTTOMLEFT", 0, -20)

    local function DoAddTick()
        local v = tonumber(addTickEntry:GetValue())
        if v and dispF._alert then
            dispF._alert.Ticks = dispF._alert.Ticks or {}
            local inserted = false
            for i2, existing in ipairs(dispF._alert.Ticks) do
                if v < existing then
                    table.insert(dispF._alert.Ticks, i2, v)
                    inserted = true
                    break
                end
            end
            if not inserted then table.insert(dispF._alert.Ticks, v) end
            addTickEntry:SetValue("")
            dispF.RebuildTickRows()
        end
    end

    addTickEntry.editBox:SetScript("OnEnterPressed", function(self)
        DoAddTick()
        self:ClearFocus()
    end)

    local addTickBtn = CreateLocalizedSubButton(barsSection, "Add", DoAddTick, 54,
        "NSUIBWAlertAddTickBtn")
    addTickBtn:SetPoint("LEFT", addTickEntry.frame, "RIGHT", 6, 0)

    local barTextColorsLbl = dispF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(barTextColorsLbl, 12, "")
    barTextColorsLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(barTextColorsLbl, "Bar Text Color")
    barTextColorsLbl:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -216)
    barTextColorsLbl:Hide()

    local barTextColorsPicker = CreateColorPicker(dispF, nil,
        function()
            local c = dispF._alert and dispF._alert.textColors
            if c then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
            return unpack(NSRT.ReminderSettings.BarSettings.textColors)
        end,
        function(_, r, g, b, a) if dispF._alert then SaveAlertData(dispF._alert, "textColors", {r, g, b, a}) end end,
        200, 22, "NSUIBWAlertBarTextColors")
    barTextColorsPicker:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -216)
    barTextColorsPicker.frame:Hide()
    dispF.barTextColorsPicker = barTextColorsPicker
    dispF.barTextColorsLbl    = barTextColorsLbl

    local barFillColorsLbl = dispF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(barFillColorsLbl, 12, "")
    barFillColorsLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(barFillColorsLbl, "Bar Fill Color")
    barFillColorsLbl:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -240)
    barFillColorsLbl:Hide()

    local barFillColorsPicker = CreateColorPicker(dispF, nil,
        function()
            local c = dispF._alert and dispF._alert.barColors
            if c then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
            return unpack(NSRT.ReminderSettings.BarSettings.barColors)
        end,
        function(_, r, g, b, a) if dispF._alert then SaveAlertData(dispF._alert, "barColors", {r, g, b, a}) end end,
        200, 22, "NSUIBWAlertBarFillColors")
    barFillColorsPicker:SetPoint("TOPLEFT", dispF, "TOPLEFT", 0, -240)
    barFillColorsPicker.frame:Hide()
    dispF.barFillColorsPicker = barFillColorsPicker
    dispF.barFillColorsLbl    = barFillColorsLbl

    dispF.SetDisplayType = function(t)
        SetTypeButtons(t)
        local isBar    = t == "Bar"
        local isCircle = t == "Circle"
        dispF.colorsLbl:SetShown(not isBar)
        dispF.colorsPicker.frame:SetShown(not isBar)
        dispF.barTextColorsLbl:SetShown(isBar)
        dispF.barTextColorsPicker.frame:SetShown(isBar)
        dispF.barFillColorsLbl:SetShown(isBar)
        dispF.barFillColorsPicker.frame:SetShown(isBar)
        barsSection:SetShown(isBar)
        circleSection:SetShown(isCircle)
        dispF.hideSwipeCB.frame:SetShown(t == "Icon")
        local COLOR_LABELS = { Text=NSI:Loc("Text Color"), Icon=NSI:Loc("Text Color"), Circle=NSI:Loc("Text Color") }
        dispF.colorsLbl:SetText(COLOR_LABELS[t] or NSI:Loc("Color"))
        if dispF.colorsPicker then dispF.colorsPicker:Refresh() end
    end
    end -- DISPLAY TAB

    -- ================================================================
    -- TRIGGER TAB
    -- ================================================================
    do
    trigF = innerTabFrames["Trigger"]

    local bossLbl = trigF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(bossLbl, 12, "")
    bossLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(bossLbl, "Boss")
    bossLbl:SetPoint("TOPLEFT", trigF, "TOPLEFT", 0, -2)

    local bossValue = trigF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(bossValue, 13, "")
    bossValue:SetTextColor(0.9, 0.9, 0.9, 1)
    bossValue:SetJustifyH("LEFT")
    bossValue:SetWidth(rightW)
    bossValue:SetPoint("TOPLEFT", trigF, "TOPLEFT", 0, -18)
    trigF.bossValue = bossValue

    local timerLbl = trigF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(timerLbl, 12, "")
    timerLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(timerLbl, "BigWigs Timer")
    timerLbl:SetPoint("TOPLEFT", trigF, "TOPLEFT", 0, -46)

    local timerIcon = trigF:CreateTexture(nil, "ARTWORK")
    timerIcon:SetSize(20, 20)
    timerIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    timerIcon:SetPoint("TOPLEFT", trigF, "TOPLEFT", 0, -62)
    trigF.timerIcon = timerIcon

    local timerValue = trigF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(timerValue, 13, "")
    timerValue:SetTextColor(0.9, 0.9, 0.9, 1)
    timerValue:SetJustifyH("LEFT")
    timerValue:SetPoint("LEFT", timerIcon, "RIGHT", 6, 0)
    timerValue:SetPoint("RIGHT", trigF, "RIGHT", 0, 0)
    trigF.timerValue = timerValue

    local offsetLbl = trigF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(offsetLbl, 12, "")
    offsetLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(offsetLbl, "Offset (seconds after the BigWigs bar starts)")
    offsetLbl:SetPoint("TOPLEFT", trigF, "TOPLEFT", 0, -98)

    local offsetEntry = CreateTextEntry(trigF, nil, nil, nil, 80, 22,
        nil, nil, nil, "NSUIBWAlertOffset",
        { title = "Offset", desc = "Delays the alert by this many seconds after the BigWigs bar starts" })
    offsetEntry:SetPoint("TOPLEFT", trigF, "TOPLEFT", 0, -114)
    offsetEntry.editBox:SetScript("OnEditFocusLost", function(self)
        if trigF._alert then SaveAlertData(trigF._alert, "offset", tonumber(self:GetText()) or 0) end
    end)
    trigF.offsetEntry = offsetEntry
    end -- TRIGGER TAB

    -- ================================================================
    -- SOUND TAB
    -- ================================================================
    do
    sndF = innerTabFrames["Sound"]

    local ttsCB = CreateCheckButton(sndF, NSI:Loc("Enable Text-to-Speech"),
        function() return false end,
        function(_, v)
            if not sndF._alert then return end
            local txt = sndF.ttsTextEntry and sndF.ttsTextEntry:GetValue() or ""
            SaveAlertData(sndF._alert, "TTS", v and ((txt ~= "") and txt or true) or false)
        end,
        rightW, 22, "NSUIBWAlertTTSCB")
    ttsCB:SetLocaleKey("Enable Text-to-Speech")
    ttsCB:SetPoint("TOPLEFT", sndF, "TOPLEFT", 0, -4)
    sndF.ttsCB = ttsCB

    local ttsTextLbl = sndF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(ttsTextLbl, 12, "")
    ttsTextLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(ttsTextLbl, "TTS Text (leave blank to speak the Display Text)")
    ttsTextLbl:SetPoint("TOPLEFT", sndF, "TOPLEFT", 0, -34)

    local ttsTextEntry = CreateTextEntry(sndF, nil, nil, nil, rightW, 22,
        nil, nil, nil, "NSUIBWAlertTTSText")
    ttsTextEntry:SetPoint("TOPLEFT", sndF, "TOPLEFT", 0, -50)
    ttsTextEntry.editBox:SetScript("OnEditFocusLost", function(self)
        local v = self:GetText()
        if not sndF._alert then return end
        if sndF._alert.TTS ~= false then
            SaveAlertData(sndF._alert, "TTS", (v ~= "") and v or true)
        end
    end)
    sndF.ttsTextEntry = ttsTextEntry

    local ttsTimerLbl = sndF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(ttsTimerLbl, 12, "")
    ttsTimerLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(ttsTimerLbl, "TTS Timer (seconds before the Alert expires)")
    ttsTimerLbl:SetPoint("TOPLEFT", sndF, "TOPLEFT", 0, -82)

    local ttsTimerEntry = CreateTextEntry(sndF, nil, nil, nil, 80, 22,
        nil, nil, nil, "NSUIBWAlertTTSTimer",
        { title = "TTS Timer", desc = "Remaining duration at which the TTS or Sound should play" })
    ttsTimerEntry:SetPoint("TOPLEFT", sndF, "TOPLEFT", 0, -98)
    ttsTimerEntry.editBox:SetScript("OnEditFocusLost", function(self)
        if sndF._alert then SaveAlertData(sndF._alert, "TTSTimer", tonumber(self:GetText()) or 8) end
    end)
    sndF.ttsTimerEntry = ttsTimerEntry

    local cdLbl = sndF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(cdLbl, 12, "")
    cdLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(cdLbl, "Countdown for")
    cdLbl:SetPoint("TOPLEFT", sndF, "TOPLEFT", 0, -138)

    local cdEntry = CreateTextEntry(sndF, nil, nil, nil, 60, 22,
        nil, nil, nil, "NSUIBWAlertCountdown",
        { title = "Countdown", desc = "At how many seconds remaining you would like to hear a TTS countdown" })
    cdEntry:SetPoint("LEFT", cdLbl, "RIGHT", 6, 0)
    cdEntry:SetPoint("TOP",  cdLbl, "TOP", 0, 6)
    cdEntry.editBox:SetScript("OnEditFocusLost", function(self)
        local v = tonumber(self:GetText())
        if sndF._alert then SaveAlertData(sndF._alert, "countdown", (v and v > 0) and v or false) end
    end)
    sndF.cdEntry = cdEntry

    local cdSecLbl = sndF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(cdSecLbl, 12, "")
    cdSecLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(cdSecLbl, "seconds")
    cdSecLbl:SetPoint("LEFT", cdEntry.frame, "RIGHT", 5, 0)

    local sndFileLbl = sndF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(sndFileLbl, 12, "")
    sndFileLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    SetLocalizedText(sndFileLbl, "Sound File")
    sndFileLbl:SetPoint("TOPLEFT", sndF, "TOPLEFT", 0, -162)

    local soundGetItems, soundGetSelected = NSI:BuildSoundDropdown(
        function() return sndF._alert and sndF._alert.sound end,
        function(v) if sndF._alert then SaveAlertData(sndF._alert, "sound", v) end end
    )
    local soundDD = CreateDropdown(sndF, nil, soundGetItems, soundGetSelected,
        rightW, 22, "NSUIBWAlertSound",
        { title = "Sound File", desc = "If you select a sound here it will take priority over any configured TTS. It will still use the TTS-Timer field to determine when to play" },
        nil, nil, true)
    soundDD:SetPoint("TOPLEFT", sndF, "TOPLEFT", 0, -178)
    sndF.soundDD = soundDD
    end -- SOUND TAB

    -- ================================================================
    -- LOAD TAB
    -- ================================================================
    do
    loadF = innerTabFrames["Load"]

    local CLASS_DATA = {
        { key = "WARRIOR",     label = "Warrior" },
        { key = "PALADIN",     label = "Paladin" },
        { key = "HUNTER",      label = "Hunter" },
        { key = "ROGUE",       label = "Rogue" },
        { key = "PRIEST",      label = "Priest" },
        { key = "DEATHKNIGHT", label = "Death Knight" },
        { key = "SHAMAN",      label = "Shaman" },
        { key = "MAGE",        label = "Mage" },
        { key = "WARLOCK",     label = "Warlock" },
        { key = "MONK",        label = "Monk" },
        { key = "DRUID",       label = "Druid" },
        { key = "DEMONHUNTER", label = "Demon Hunter" },
        { key = "EVOKER",      label = "Evoker" },
    }
    local SPEC_DATA = {
        { class="WARRIOR",     id=71,   label="Arms" },
        { class="WARRIOR",     id=72,   label="Fury" },
        { class="WARRIOR",     id=73,   label="Protection" },
        { class="PALADIN",     id=65,   label="Holy" },
        { class="PALADIN",     id=66,   label="Protection" },
        { class="PALADIN",     id=70,   label="Retribution" },
        { class="HUNTER",      id=253,  label="Beast Mastery" },
        { class="HUNTER",      id=254,  label="Marksmanship" },
        { class="HUNTER",      id=255,  label="Survival" },
        { class="ROGUE",       id=259,  label="Assassination" },
        { class="ROGUE",       id=260,  label="Outlaw" },
        { class="ROGUE",       id=261,  label="Subtlety" },
        { class="PRIEST",      id=256,  label="Discipline" },
        { class="PRIEST",      id=257,  label="Holy" },
        { class="PRIEST",      id=258,  label="Shadow" },
        { class="DEATHKNIGHT", id=250,  label="Blood" },
        { class="DEATHKNIGHT", id=251,  label="Frost" },
        { class="DEATHKNIGHT", id=252,  label="Unholy" },
        { class="SHAMAN",      id=262,  label="Elemental" },
        { class="SHAMAN",      id=263,  label="Enhancement" },
        { class="SHAMAN",      id=264,  label="Restoration" },
        { class="MAGE",        id=62,   label="Arcane" },
        { class="MAGE",        id=63,   label="Fire" },
        { class="MAGE",        id=64,   label="Frost" },
        { class="WARLOCK",     id=265,  label="Affliction" },
        { class="WARLOCK",     id=266,  label="Demonology" },
        { class="WARLOCK",     id=267,  label="Destruction" },
        { class="MONK",        id=268,  label="Brewmaster" },
        { class="MONK",        id=269,  label="Windwalker" },
        { class="MONK",        id=270,  label="Mistweaver" },
        { class="DRUID",       id=102,  label="Balance" },
        { class="DRUID",       id=103,  label="Feral" },
        { class="DRUID",       id=104,  label="Guardian" },
        { class="DRUID",       id=105,  label="Restoration" },
        { class="DEMONHUNTER", id=577,  label="Havoc" },
        { class="DEMONHUNTER", id=581,  label="Vengeance" },
        { class="DEMONHUNTER", id=1480, label="Devourer" },
        { class="EVOKER",      id=1467, label="Devastation" },
        { class="EVOKER",      id=1468, label="Preservation" },
        { class="EVOKER",      id=1473, label="Augmentation" },
    }

    local loadRowH  = 20
    local loadListW = rightW - 20
    local loadListH = 240

    local NAMES_SEC_H = 180
    local namesListH  = 112

    local loadScrollH = tab_content_height - 20 - 68 - NAMES_SEC_H - 4
    local loadScroll = CreateFrame("ScrollFrame", "NSUIBWAlertLoadScroll", loadF,
        "UIPanelScrollFrameTemplate")
    loadScroll:SetPoint("TOPLEFT", loadF, "TOPLEFT", 0, 0)
    loadScroll:SetSize(loadListW, loadScrollH)
    loadScroll:EnableMouseWheel(true)
    loadScroll:SetScript("OnMouseWheel", function(_, delta)
        local bar = _G["NSUIBWAlertLoadScrollScrollBar"]
        if bar then
            local cur = bar:GetValue()
            local mn, mx = bar:GetMinMaxValues()
            bar:SetValue(math.max(mn, math.min(mx, cur - delta * 20)))
        end
    end)
    ReskinScrollbar(loadScroll)

    local loadScrollChild = CreateFrame("Frame", nil, loadScroll, "BackdropTemplate")
    loadScrollChild:SetSize(loadListW - 18, loadListH)
    loadScrollChild:SetBackdrop({ bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
        tile = true, tileSize = 64 })
    loadScrollChild:SetBackdropColor(0.04, 0.04, 0.04, 0.85)
    loadScroll:SetScrollChild(loadScrollChild)

    local sectionCollapsed = { Roles = true, Classes = true, Specs = true }
    local RebuildLoadTab

    local function MakeSectionHdr(label, sectionKey)
        local btn = CreateFrame("Button", nil, loadScrollChild, "BackdropTemplate")
        btn:SetBackdrop({
            bgFile   = [[Interface\Tooltips\UI-Tooltip-Background]],
            tile     = true,
            tileSize = 64,
        })
        btn:SetBackdropColor(0.05, 0.30, 0.40, 0.9)
        btn:SetSize(loadListW - 18, 18)
        btn.arrowTex = btn:CreateTexture(nil, "OVERLAY")
        btn.arrowTex:SetSize(10, 10)
        btn.arrowTex:SetPoint("LEFT", btn, "LEFT", 2, 0)
        btn.arrowTex:SetTexture([[Interface\AddOns\NorthernSkyRaidTools\Media\Icons\chevron-down.png]])
        btn.arrowTex:SetVertexColor(0.6, 0.6, 0.6, 1)
        btn.textLbl = btn:CreateFontString(nil, "OVERLAY")
        NSI:SetUIFont(btn.textLbl, 11, "")
        btn.textLbl:SetTextColor(0.55, 0.55, 0.55, 1)
        btn.textLbl:SetPoint("LEFT", btn, "LEFT", 16, 0)
        btn.textLbl:SetText(label)
        btn:SetScript("OnClick", function()
            sectionCollapsed[sectionKey] = not sectionCollapsed[sectionKey]
            if RebuildLoadTab then RebuildLoadTab() end
        end)
        btn:SetScript("OnEnter", function() btn.textLbl:SetTextColor(0.85, 0.85, 0.85, 1) end)
        btn:SetScript("OnLeave", function() btn.textLbl:SetTextColor(0.55, 0.55, 0.55, 1) end)
        return btn
    end

    local function MakeCheckRow(parent)
        local BOX       = 12
        local baseLevel = parent:GetFrameLevel() + 1
        local row = CreateFrame("Button", nil, parent)
        row:SetSize(loadListW - 18, loadRowH)
        row:SetFrameLevel(baseLevel)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(row)
        row.bg:SetColorTexture(0, 0, 0, 0)

        local hoverBg = CreateFrame("Frame", nil, row)
        hoverBg:SetAllPoints(row)
        hoverBg:SetFrameLevel(baseLevel + 1)
        hoverBg:EnableMouse(false)
        local hoverTex = hoverBg:CreateTexture(nil, "BACKGROUND")
        hoverTex:SetAllPoints()
        hoverTex:SetColorTexture(0, 1, 1, 0.13)
        hoverBg:SetAlpha(0)
        row.hoverBg = hoverBg

        local checkBox = CreateFrame("Frame", nil, row, "BackdropTemplate")
        checkBox:SetSize(BOX, BOX)
        checkBox:SetPoint("LEFT", row, "LEFT", 4, 0)
        checkBox:SetFrameLevel(baseLevel + 2)
        checkBox:SetBackdrop({
            bgFile   = [[Interface\Buttons\WHITE8x8]],
            edgeFile = [[Interface\Buttons\WHITE8x8]],
            edgeSize = 1,
        })
        checkBox:SetBackdropColor(0.10, 0.10, 0.10, 0.9)
        checkBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        row.checkBox = checkBox

        local checkFill = checkBox:CreateTexture(nil, "ARTWORK")
        checkFill:SetPoint("TOPLEFT", checkBox, "TOPLEFT", 2, -2)
        checkFill:SetPoint("BOTTOMRIGHT", checkBox, "BOTTOMRIGHT", -2, 2)
        checkFill:SetColorTexture(0, 1, 1, 0.85)
        checkFill:Hide()
        row.checkFill = checkFill

        local lblFrame = CreateFrame("Frame", nil, row)
        lblFrame:SetFrameLevel(baseLevel + 2)
        lblFrame:EnableMouse(false)
        lblFrame:SetPoint("LEFT", row, "LEFT", 22, 0)
        lblFrame:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        lblFrame:SetHeight(loadRowH)

        row.nameLbl = lblFrame:CreateFontString(nil, "OVERLAY")
        NSI:SetUIFont(row.nameLbl, 12, "")
        row.nameLbl:SetAllPoints(lblFrame)
        row.nameLbl:SetJustifyH("LEFT")
        row.nameLbl:SetJustifyV("MIDDLE")

        row:SetScript("OnEnter", function()
            UIFrameFadeIn(hoverBg, 0.12, hoverBg:GetAlpha(), 1)
        end)
        row:SetScript("OnLeave", function()
            UIFrameFadeOut(hoverBg, 0.20, hoverBg:GetAlpha(), 0)
        end)
        return row
    end

    local classSecHdr = MakeSectionHdr(NSI:Loc("Classes (leave all unchecked for any class)"), "Classes")
    local specSecHdr  = MakeSectionHdr(NSI:Loc("Specializations (leave all unchecked for any spec)"), "Specs")

    local classRowFrames = {}
    for i, cd in ipairs(CLASS_DATA) do
        local row = MakeCheckRow(loadScrollChild)
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cd.key]
        if cc then row.nameLbl:SetTextColor(cc.r, cc.g, cc.b, 1)
        else       row.nameLbl:SetTextColor(1, 1, 1, 1) end
        row.nameLbl:SetText(NSI:Loc(cd.label))
        row._classKey = cd.key
        classRowFrames[i] = row
        row:Hide()
    end

    local specRowFrames = {}
    for i, sd in ipairs(SPEC_DATA) do
        local row = MakeCheckRow(loadScrollChild)
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[sd.class]
        if cc then row.nameLbl:SetTextColor(cc.r * 0.8 + 0.2, cc.g * 0.8 + 0.2, cc.b * 0.8 + 0.2, 1)
        else       row.nameLbl:SetTextColor(0.85, 0.85, 0.85, 1) end
        row.nameLbl:SetText(NSI:Loc(sd.label))
        row._specID   = sd.id
        row._classKey = sd.class
        specRowFrames[i] = row
        row:Hide()
    end

    local ROLE_DATA = {
        { key = "TANK",    label = "Tank" },
        { key = "HEALER",  label = "Healer" },
        { key = "DAMAGER", label = "DPS" },
        { key = "MELEE",   label = "Melee" },
        { key = "RANGED",  label = "Ranged" },
    }
    local ROLE_COLORS = {
        TANK    = { 0.3, 0.5, 1.0 },
        HEALER  = { 0.3, 0.9, 0.3 },
        DAMAGER = { 0.9, 0.2, 0.2 },
        MELEE   = { 0.95, 0.55, 0.2 },
        RANGED  = { 0.9, 0.8, 0.2 },
    }

    local rolesSecHdr = MakeSectionHdr(NSI:Loc("Roles (leave all unchecked for any role)"), "Roles")

    local roleRowFrames = {}
    for i, rd in ipairs(ROLE_DATA) do
        local row = MakeCheckRow(loadScrollChild)
        local rc = ROLE_COLORS[rd.key]
        row.nameLbl:SetTextColor(rc[1], rc[2], rc[3], 1)
        row.nameLbl:SetText(NSI:Loc(rd.label))
        row._roleKey = rd.key
        roleRowFrames[i] = row
        row:Hide()
    end

    local namesHdrLbl = loadF:CreateFontString(nil, "OVERLAY")
    NSI:SetUIFont(namesHdrLbl, 11, "")
    namesHdrLbl:SetTextColor(0.55, 0.55, 0.55, 1)
    SetLocalizedText(namesHdrLbl, "Character Names (no server name)")
    namesHdrLbl:SetPoint("BOTTOMLEFT", loadF, "BOTTOMLEFT", 0, NAMES_SEC_H - 12)

    local nameAddEntry = CreateTextEntry(loadF, nil, nil, nil, 180, 22,
        nil, nil, nil, "NSUIBWAlertNameAdd")
    nameAddEntry:SetPoint("BOTTOMLEFT", loadF, "BOTTOMLEFT", 0, NAMES_SEC_H - 36)

    local DoAddName
    local nameAddBtn = CreateLocalizedSubButton(loadF, "Add", function() if DoAddName then DoAddName() end end,
        54, "NSUIBWAlertNameAddBtn")
    nameAddBtn:SetPoint("LEFT", nameAddEntry.frame, "RIGHT", 6, 0)

    local namesScroll = CreateFrame("ScrollFrame", "NSUIBWAlertNamesScroll", loadF,
        "UIPanelScrollFrameTemplate")
    namesScroll:SetSize(loadListW, namesListH)
    namesScroll:SetPoint("BOTTOMLEFT", loadF, "BOTTOMLEFT", 0, 4)
    namesScroll:EnableMouseWheel(true)
    namesScroll:SetScript("OnMouseWheel", function(_, delta)
        local bar = _G["NSUIBWAlertNamesScrollScrollBar"]
        if bar then
            local cur = bar:GetValue()
            local mn, mx = bar:GetMinMaxValues()
            bar:SetValue(math.max(mn, math.min(mx, cur - delta * 20)))
        end
    end)
    ReskinScrollbar(namesScroll)
    local namesBg = namesScroll:CreateTexture(nil, "BACKGROUND")
    namesBg:SetAllPoints(namesScroll)
    namesBg:SetColorTexture(0.04, 0.04, 0.04, 0.85)

    local namesChild = CreateFrame("Frame", nil, namesScroll, "BackdropTemplate")
    namesChild:SetSize(loadListW - 18, 1)
    namesChild:SetBackdrop({ bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
        tile = true, tileSize = 64 })
    namesChild:SetBackdropColor(0.04, 0.04, 0.04, 0.85)
    namesScroll:SetScrollChild(namesChild)

    local nameRowH = 20
    local nameRows = {}

    local function RebuildNameRows()
        for _, row in ipairs(nameRows) do row:Hide() end
        if not loadF._alert then return end
        local cond = loadF._alert.loadConditions
        if not (cond and cond.Names) then return end
        local i = 0
        for name, _ in pairs(cond.Names) do
            i = i + 1
            if not nameRows[i] then
                nameRows[i] = CreateFrame("Frame", nil, namesChild)
                nameRows[i]:SetSize(namesChild:GetWidth(), nameRowH)
                nameRows[i].bg = nameRows[i]:CreateTexture(nil, "BACKGROUND")
                nameRows[i].bg:SetAllPoints(nameRows[i])
                nameRows[i].nLbl = nameRows[i]:CreateFontString(nil, "OVERLAY")
                NSI:SetUIFont(nameRows[i].nLbl, 12, "")
                nameRows[i].nLbl:SetPoint("LEFT", nameRows[i], "LEFT", 8, 0)
                nameRows[i].nLbl:SetTextColor(1, 1, 1, 1)
                nameRows[i].delBtn = CreateFrame("Button", nil, nameRows[i])
                nameRows[i].delBtn:SetSize(14, 14)
                nameRows[i].delBtn:SetPoint("RIGHT", nameRows[i], "RIGHT", -6, 0)
                nameRows[i].delBtn:SetNormalTexture([[Interface\AddOns\NorthernSkyRaidTools\Media\Icons\x.png]])
                nameRows[i].delBtn:GetNormalTexture():SetDesaturated(true)
                nameRows[i].delBtn:GetNormalTexture():SetVertexColor(0.9, 0.3, 0.3)
            end
            nameRows[i]:ClearAllPoints()
            nameRows[i]:SetPoint("TOPLEFT", namesChild, "TOPLEFT", 0, -(i - 1) * nameRowH)
            nameRows[i].bg:SetColorTexture(i % 2 == 0 and 0.2 or 0, i % 2 == 0 and 0.2 or 0,
                i % 2 == 0 and 0.2 or 0, i % 2 == 0 and 0.9 or 0)
            nameRows[i].nLbl:SetText(name)
            local capName = name
            nameRows[i].delBtn:SetScript("OnClick", function()
                if loadF._alert and loadF._alert.loadConditions
                        and loadF._alert.loadConditions.Names then
                    loadF._alert.loadConditions.Names[capName] = nil
                    RebuildNameRows()
                    RebuildList()
                end
            end)
            nameRows[i]:Show()
        end
        namesChild:SetHeight(math.max(i * nameRowH, 1))
        local bar = _G["NSUIBWAlertNamesScrollScrollBar"]
        if bar then
            local maxScroll = math.max(0, i * nameRowH - namesListH)
            bar:SetMinMaxValues(0, maxScroll)
            if bar:GetValue() > maxScroll then bar:SetValue(0) end
        end
    end

    DoAddName = function()
        if not loadF._alert then return end
        local v = nameAddEntry:GetValue()
        if not v or v == "" then return end
        loadF._alert.loadConditions = loadF._alert.loadConditions or {}
        loadF._alert.loadConditions.Names = loadF._alert.loadConditions.Names or {}
        loadF._alert.loadConditions.Names[v] = true
        nameAddEntry:SetValue("")
        RebuildNameRows()
        RebuildList()
    end
    nameAddEntry.editBox:SetScript("OnEnterPressed", function(self)
        DoAddName(); self:ClearFocus()
    end)

    RebuildLoadTab = function()
        if not loadF._alert then return end
        local alert = loadF._alert
        alert.loadConditions = alert.loadConditions or {}
        alert.loadConditions.Classes = alert.loadConditions.Classes or {}
        alert.loadConditions.SpecIDs = alert.loadConditions.SpecIDs or {}
        alert.loadConditions.Roles   = alert.loadConditions.Roles   or {}
        alert.loadConditions.Names   = alert.loadConditions.Names   or {}
        local cond = alert.loadConditions

        local y    = 0
        local hdrH = 18
        local gapH = 4

        local function LayoutSection(hdrBtn, rows, dataList, collapsedKey, isSelected, onToggle, colorFn)
            hdrBtn:ClearAllPoints()
            hdrBtn:SetPoint("TOPLEFT", loadScrollChild, "TOPLEFT", 0, -y)
            local collapsed = sectionCollapsed[collapsedKey]
            if collapsed then
                hdrBtn.arrowTex:SetTexture([[Interface\AddOns\NorthernSkyRaidTools\Media\Icons\chevron-down.png]])
            else
                hdrBtn.arrowTex:SetTexture([[Interface\AddOns\NorthernSkyRaidTools\Media\Icons\chevron-up.png]])
            end
            y = y + hdrH + 2

            for i, data in ipairs(dataList) do
                local row = rows[i]
                if collapsed then
                    row:Hide()
                else
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", loadScrollChild, "TOPLEFT", 0, -y)
                    local selected = isSelected(data)
                    if selected then
                        local r, g, b = colorFn(data)
                        row.bg:SetColorTexture(r * 0.3, g * 0.3, b * 0.3, 0.85)
                        row.checkFill:Show()
                        row.checkBox:SetBackdropBorderColor(0, 1, 1, 0.9)
                    else
                        row.bg:SetColorTexture(
                            i % 2 == 0 and 0.12 or 0,
                            i % 2 == 0 and 0.12 or 0,
                            i % 2 == 0 and 0.12 or 0,
                            i % 2 == 0 and 0.5 or 0)
                        row.checkFill:Hide()
                        row.checkBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
                    end
                    local d = data
                    row:SetScript("OnClick", function()
                        onToggle(d, cond)
                        RebuildLoadTab()
                        RebuildList()
                    end)
                    row:Show()
                    y = y + loadRowH
                end
            end
            y = y + gapH
        end

        LayoutSection(rolesSecHdr, roleRowFrames, ROLE_DATA, "Roles",
            function(d) return cond.Roles[d.key] end,
            function(d, c)
                if c.Roles[d.key] then c.Roles[d.key] = nil else c.Roles[d.key] = true end
            end,
            function(d) local rc = ROLE_COLORS[d.key]; return rc[1], rc[2], rc[3] end)

        LayoutSection(classSecHdr, classRowFrames, CLASS_DATA, "Classes",
            function(d) return cond.Classes[d.key] end,
            function(d, c)
                if c.Classes[d.key] then c.Classes[d.key] = nil else c.Classes[d.key] = true end
            end,
            function(d)
                local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.key]
                return cc and cc.r or 0.5, cc and cc.g or 0.8, cc and cc.b or 0.5
            end)

        LayoutSection(specSecHdr, specRowFrames, SPEC_DATA, "Specs",
            function(d) return cond.SpecIDs[d.id] end,
            function(d, c)
                if c.SpecIDs[d.id] then c.SpecIDs[d.id] = nil else c.SpecIDs[d.id] = true end
            end,
            function(d)
                local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.class]
                return cc and cc.r or 0.5, cc and cc.g or 0.8, cc and cc.b or 0.5
            end)

        loadScrollChild:SetHeight(math.max(y, loadListH))
        local bar = _G["NSUIBWAlertLoadScrollScrollBar"]
        if bar then
            local maxScroll = math.max(0, y - loadScroll:GetHeight())
            bar:SetMinMaxValues(0, maxScroll)
            if bar:GetValue() > maxScroll then bar:SetValue(0) end
        end

        RebuildNameRows()
    end
    loadF.Rebuild = RebuildLoadTab
    end -- LOAD TAB

    -- ================================================================
    -- PreviewAlert ── fire the current alert visually without a trigger
    -- ================================================================
    PreviewAlert = function()
        if not dispF._alert then return end
        if NSI:IsUsingTLAlerts() and not dispF._alert.isSpecialDisplay then
            print(NSI:Loc("|cFFFF0000NSRT:|r Preview is disabled because you are displaying alerts through TimelineReminders."))
            return
        end
        local info = NSI:CreateReminder(dispF._alert, true)
        NSI:HideAllReminders()
        NSI:DisplayReminder(info, true)
    end

    SelectAlert = function(encID, key)
        local alert = GetAlert(encID, key)
        if not alert then
            selectedEncID, selectedKey = nil, nil
            rightPanel:Hide()
            RebuildList()
            return
        end

        selectedEncID, selectedKey = encID, key
        rightPanel:Show()

        dispF._alert = alert
        trigF._alert = alert
        sndF._alert  = alert
        loadF._alert = alert

        -- Header
        nameEntry:SetValue(alert.name or "")
        nameEntry.editBox:SetScript("OnEditFocusLost", function(self)
            alert.name = self:GetText()
            RebuildList()
        end)
        enabledCB:SetValue(alert.enabled ~= false)
        enabledCB:SetOnChange(function(_, v)
            alert.enabled = v
            RebuildList()
        end)

        -- Display tab
        dispF.SetDisplayType(alert.DisplayType or "Text")
        dispF.textEntry:SetValue(alert.text or "")
        dispF.spellEntry:SetValue(alert.spellID and tostring(alert.spellID) or "")
        dispF.useTauntCB:SetValue(alert.isTaunt == true)
        do
            local spell = alert.spellID and C_Spell.GetSpellInfo(alert.spellID)
            if spell and spell.iconID then
                dispF.spellIconFrame.texture:SetTexture(spell.iconID)
                dispF.spellIconFrame:Show()
            else
                dispF.spellIconFrame:Hide()
            end
        end
        dispF.customIconEntry:SetValue(alert.customIcon and tostring(alert.customIcon) or "")
        dispF.durEntry:SetValue(tostring(alert.dur or 8))
        dispF.stickyEntry:SetValue(alert.sticky and tostring(alert.sticky) or "")
        dispF.hideTimerCB:SetValue(alert.HideTimer ~= nil and alert.HideTimer or false)
        dispF.hideSwipeCB:SetValue(alert.HideSwipe ~= nil and alert.HideSwipe
            or (NSRT.ReminderSettings.IconSettings.HideSwipe or false))
        local showBg = alert.showBackground ~= nil and alert.showBackground
            or NSRT.ReminderSettings.CircleSettings.showBackground
        dispF.showBgCB:SetValue(showBg ~= false)
        dispF.glowunitEntry:SetValue(alert.glowunit or "")
        dispF.colorsPicker:Refresh()
        dispF.circleTextureDD:Refresh()
        dispF.ringColorsPicker:Refresh()
        dispF.barTextColorsPicker:Refresh()
        dispF.barFillColorsPicker:Refresh()
        dispF.RebuildTickRows()

        -- Trigger tab
        local link        = alert.bigwigs or {}
        local linkSpellID = link.spellID or alert.spellID
        local linkSpell   = linkSpellID and C_Spell.GetSpellInfo(linkSpellID)
        trigF.bossValue:SetText(GetEncounterLabel(encID, link.moduleDisplay))
        if linkSpell and linkSpell.iconID then
            trigF.timerIcon:SetTexture(linkSpell.iconID)
            trigF.timerIcon:Show()
        else
            trigF.timerIcon:Hide()
        end
        trigF.timerValue:SetText(string.format("%s  |cFF808080(%s)|r",
            link.timerName or alert.name or "?", tostring(linkSpellID or "?")))
        trigF.offsetEntry:SetValue(tostring(alert.offset or 0))

        -- Sound tab
        local ttsActive = alert.TTS ~= false and alert.TTS ~= nil
        sndF.ttsCB:SetValue(ttsActive)
        sndF.ttsTextEntry:SetValue(type(alert.TTS) == "string" and alert.TTS or "")
        sndF.ttsTimerEntry:SetValue(tostring(alert.TTSTimer or alert.dur or 8))
        local hasCD = alert.countdown and alert.countdown ~= false
        sndF.cdEntry:SetValue(hasCD and tostring(alert.countdown) or "")
        sndF.soundDD:Refresh()

        -- Load tab
        loadF.Rebuild()

        RebuildList()
        SelectInnerTab(activeInnerTab)
    end
    screen.SelectAlert = SelectAlert

    SelectInnerTab("Display")

    screen:SetScript("OnShow", function()
        RebuildList()
        if selectedEncID and selectedKey then
            SelectAlert(selectedEncID, selectedKey)
        end
    end)
    screen:SetScript("OnHide", function()
        pickerFrame:Hide()
    end)

    RebuildList()
    return screen
end

-- Export to namespace
NSI.UI = NSI.UI or {}
NSI.UI.BigWigsAlerts = {
    BuildBigWigsAlertsUI = BuildBigWigsAlertsUI,
    GetTimerIndex        = GetTimerIndex,
}
