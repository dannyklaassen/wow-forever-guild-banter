local frame = CreateFrame("Frame")
local pending, level, offlineSince = {}, {}, {}

-- Bouw een Lua-pattern uit een (gelokaliseerde) systeemtekst, bv. "%s has joined the guild."
local function pattern(text)
    return "^" .. text:gsub("([%.%-%(%)%[%]%+%*%?%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$"
end
local joinPattern = pattern(ERR_GUILD_JOIN_S)
local leavePattern = pattern(ERR_GUILD_LEAVE_S)
local onlinePattern = pattern(ERR_FRIEND_ONLINE_SS)

local function shortName(fullName)
    return fullName and fullName:match("^[^-]+")
end

local function requestRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    else
        GuildRoster()
    end
end

-- Taal van de berichten in guild chat én van het optiescherm. Engels is de standaard.
-- Nederlands is geen WoW-clienttaal, dus GetLocale() helpt niet: het is altijd een eigen keuze.
local languages = {{"en", "English"}, {"nl", "Nederlands"}, {"de", "Deutsch"}, {"fr", "Français"}, {"es", "Español"}}
local periods = {7, 14, 30, 60, 90}

-- Instellingen per guild (naam + realm), zodat een alt in een andere guild eigen taal en vinkjes heeft.
-- nil betekent standaard (aan), alleen expliciet false zet een soort uit.
local function settings()
    GuildBanterDB = GuildBanterDB or {}
    GuildBanterDB.guilds = GuildBanterDB.guilds or {}
    local key = (GetGuildInfo("player") or "") .. "-" .. GetRealmName()
    local s = GuildBanterDB.guilds[key]
    if not s then
        -- ponytail: een nieuwe guild start met de oude accountbrede instellingen uit 1.3 (losse sleutels in de root)
        s = {}
        for k, v in pairs(GuildBanterDB) do
            if type(v) ~= "table" then s[k] = v end
        end
        GuildBanterDB.guilds[key] = s
    end
    return s
end

local function language()
    local lang = settings().language
    return GuildBanterMessages[lang] and lang or "en"
end

local function messages() return GuildBanterMessages[language()] end

local function ui() return messages().ui end

-- kind: HI, BYE, BACK of een mijlpaal ("40", "60"). Mijlpalen hebben eigen teksten per class, anders default.
local function linesFor(kind, class)
    local m = messages()
    if kind == "HI" then return m.welcome[class] end
    if kind == "BYE" then return m.farewell end
    if kind == "BACK" then return m.comeback end
    local milestone = m.milestones[tonumber(kind)]
    return milestone and (milestone[class] or milestone.default)
end

-- Shuffle-bag per lijst: elke regel komt één keer langs voordat er een herhaling komt.
local bags = {}
local function pick(lines)
    local bag = bags[lines]
    if not bag or #bag == 0 then
        bag = {}
        for i = 1, #lines do bag[i] = i end
        for i = #bag, 2, -1 do
            local j = math.random(i)
            bag[i], bag[j] = bag[j], bag[i]
        end
        bags[lines] = bag
    end
    return lines[table.remove(bag)]
end

local function line(kind, class, name, days)
    local lines = linesFor(kind, class)
    if not lines then return nil end
    return (pick(lines):gsub("{name}", name):gsub("{days}", days or ""))
end

local function comebackDays()
    local days = settings().comebackDays or 14
    return days == 28 and 30 or days -- 4 weken uit 1.2 is nu 1 maand
end

-- Guild chat van anderen in de laatste 90 seconden. Noemt iemand de naam al (een andere GuildBanter,
-- een andere addon of gewoon een speler), dan zwijgen we. 90 s, omdat elke client de roster op een
-- eigen minuut-tik scant en dings dus tot een minuut na elkaar ziet.
local heard = {}
local function forget()
    local cutoff = GetTime() - 90
    while heard[1] and heard[1].at < cutoff do table.remove(heard, 1) end
end

local function hear(author, text)
    if shortName(author) == UnitName("player") then return end
    forget()
    heard[#heard + 1] = {at = GetTime(), text = text}
end

local function mentioned(name)
    forget()
    for _, entry in ipairs(heard) do
        -- ponytail: substring, dus "Al" telt ook in "Also"; hooguit een gemist bericht, nooit een dubbel
        if entry.text:find(name, 1, true) then return true end
    end
    return false
end

local function say(kind, class, name, days)
    if settings()[kind] == false then return end
    -- ponytail: willekeurige wachttijd van 1 tot 8 s spreidt gelijktijdige GuildBanters; posten twee binnen
    -- dezelfde chat-roundtrip (circa 0,5 s), dan komen er toch twee. Sluitend wordt het pas met een
    -- leider-keuze via SendAddonMessage.
    C_Timer.After(1 + math.random() * 7, function()
        if mentioned(name) then return end
        local text = line(kind, class, name, days)
        if text then SendChatMessage(text, "GUILD") end
    end)
end

local function scanRoster()
    local now, me = time(), UnitName("player")
    for i = 1, GetNumGuildMembers() do
        local fullName, _, _, lvl, _, _, _, _, online, _, class = GetGuildRosterInfo(i)
        local name = shortName(fullName)
        if name then
            if pending[name] then
                pending[name] = nil
                say("HI", class, name)
            end
            -- Eerste scan (of nieuw lid) slaat alleen het level op, dus geen felicitaties achteraf.
            local old = level[name]
            if old and lvl and name ~= me then
                for milestone in pairs(messages().milestones) do
                    if old < milestone and lvl >= milestone then say(tostring(milestone), class, name) end
                end
            end
            level[name] = lvl
            if not online then
                local years, months, days, hours = GetGuildRosterLastOnline(i)
                -- ponytail: maand = 30 dagen; ruim genoeg voor perioden van weken tot maanden
                offlineSince[name] = now - (((years or 0) * 12 + (months or 0)) * 30 + (days or 0)) * 86400 - (hours or 0) * 3600
            end
        end
    end
end

frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_GUILD")
frame:SetScript("OnEvent", function(_, event, msg, author)
    if event == "GUILD_ROSTER_UPDATE" then return scanRoster() end
    if event == "CHAT_MSG_GUILD" then return hear(author, msg) end

    local name = msg:match(joinPattern)
    if name then
        pending[name] = true
        -- ponytail: korte vertraging zodat de server de roster eerst bijwerkt
        C_Timer.After(2, requestRoster)
        return
    end

    name = msg:match(leavePattern)
    if name then return say("BYE", nil, name) end

    -- Online-melding: alleen guildleden staan in offlineSince, vrienden buiten de guild vallen zo vanzelf af.
    name = shortName(msg:match(onlinePattern))
    local since = name and offlineSince[name]
    if since then
        offlineSince[name] = nil
        local days = math.floor((time() - since) / 86400)
        if days >= comebackDays() then
            -- ponytail: even wachten tot ze uit het laadscherm zijn en guild chat zien
            C_Timer.After(10, function() say("BACK", nil, name, days) end)
        end
    end
end)

-- De server meldt levels niet uit zichzelf; elke minuut de roster verversen houdt de mijlpalen actueel.
C_Timer.NewTicker(60, requestRoster)

-- Optiescherm (Esc > Options > AddOns > GuildBanter): taal, per soort bericht een vinkje, en de comeback-periode.
-- Alle labels volgen de gekozen taal; refresh() zet ze opnieuw bij openen en na een taalwissel.
local panel = CreateFrame("Frame")
local labels, dropdowns = {}, {}

local function setOption(key, value)
    settings()[key] = value
end

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("GuildBanter")

-- Regel onder de titel: voor welke guild deze instellingen gelden.
local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

local function refresh()
    local guild = GetGuildInfo("player")
    subtitle:SetText(guild and ui().guild:format(guild) or ui().noGuild)
    for fontString, key in pairs(labels) do fontString:SetText(ui()[key]) end
    for _, dropdown in ipairs(dropdowns) do dropdown:GenerateMenu() end
end

-- items() geeft {waarde, tekst}-paren; een functie, zodat de teksten mee vertalen.
local function addDropdown(labelKey, y, items, get, set)
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 20, y)
    labels[label] = labelKey
    local dropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", 20, y - 18)
    dropdown:SetWidth(200)
    dropdown:SetupMenu(function(_, root)
        for _, item in ipairs(items()) do
            root:CreateRadio(item[2], function() return get() == item[1] end, function() set(item[1]) end)
        end
    end)
    dropdowns[#dropdowns + 1] = dropdown
end

addDropdown("language", -70, function() return languages end, language, function(lang)
    setOption("language", lang)
    refresh()
end)

local kinds = {"HI", "BYE", "40", "60", "BACK"}
for i, kind in ipairs(kinds) do
    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 16, -100 - i * 30)
    local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    labels[label] = kind
    check:SetScript("OnShow", function(self) self:SetChecked(settings()[kind] ~= false) end)
    check:SetScript("OnClick", function(self) setOption(kind, self:GetChecked() and true or false) end)
end

addDropdown("comebackDays", -120 - (#kinds + 1) * 30, function()
    local items = {}
    for i, days in ipairs(periods) do items[i] = {days, ui().periods[i]} end
    return items
end, comebackDays, function(days) setOption("comebackDays", days) end)

panel:SetScript("OnShow", refresh)

local category = Settings.RegisterCanvasLayoutCategory(panel, "GuildBanter")
Settings.RegisterAddOnCategory(category)

-- /gb opent de opties; /gb test hi|bye|back|40|60 [class]: toont lokaal een voorbeeld, zonder iets in guild chat te zetten.
SLASH_GUILDBANTER1 = "/gb"
SLASH_GUILDBANTER2 = "/gw" -- oude commando van GuildWelcome blijft werken
SlashCmdList.GUILDBANTER = function(arg)
    if arg == "" then return Settings.OpenToCategory(category:GetID()) end
    local kind, class = arg:match("^test%s+(%w+)%s*(%a*)")
    if not kind then
        print(ui().usage)
        return
    end
    class = class ~= "" and class:upper() or select(2, UnitClass("player"))
    print(line(kind:upper(), class, UnitName("player"), 12) or ui().noLines:format(kind, class))
end
