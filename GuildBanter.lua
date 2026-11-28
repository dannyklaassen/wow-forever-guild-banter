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
    return table.remove(bag)
end

local function line(kind, class, name, days)
    local lines = linesFor(kind, class)
    local index = lines and pick(lines)
    if not index then return nil end
    return (lines[index]:gsub("{name}", name):gsub("{days}", days or ""))
end

local function comebackDays()
    local days = settings().comebackDays or 14
    return days == 28 and 30 or days -- 4 weken uit 1.2 is nu 1 maand
end

-- WoW Forever blokkeert SendChatMessage vanuit game-events en C_Timer (taint.log: "action was blocked");
-- alleen vanuit een toets of klik van de speler komt het door. Elk bericht wacht daarom in een rij op de
-- eerstvolgende toetsaanslag of muisklik in de wereld.
-- ponytail: één bericht per toets (de client staat er mogelijk maar één per hardware-event toe); wat langer
-- dan 5 minuten wacht (afk) vervalt. Hebben meerdere guildies de addon, dan post ieder van hen; bewuste keuze.
local queue = {}
local function flush()
    local item = table.remove(queue, 1)
    while item and time() - item.at > 300 do item = table.remove(queue, 1) end
    if item then C_ChatInfo.SendChatMessage(item.text, "GUILD") end
end

local function say(kind, class, name, days)
    local s = settings()
    if s.off or s[kind] == false then return end
    local text = line(kind, class, name, days)
    if text then queue[#queue + 1] = {text = text, at = time()} end
end

-- Toetsen gaan gewoon door naar de game (propagate); dit frame kijkt alleen mee.
frame:EnableKeyboard(true)
frame:SetPropagateKeyboardInput(true)
frame:SetScript("OnKeyDown", flush)
WorldFrame:HookScript("OnMouseDown", flush)

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
frame:SetScript("OnEvent", function(_, event, msg)
    if event == "GUILD_ROSTER_UPDATE" then return scanRoster() end
    -- ponytail: in chat lockdown (Midnight secret values, o.a. tijdens encounters) is de systeemtekst secret en
    -- niet te lezen; joins, leaves en online-meldingen in die periode missen we. Roster-diff als dat stoort.
    if issecretvalue and issecretvalue(msg) then return end

    local name = msg:match(joinPattern)
    if name then
        pending[name] = true
        -- ponytail: korte vertraging zodat de server de roster eerst bijwerkt. GuildRoster() werkt hoogstens
        -- eens per ~10 s; viel de eerste aanvraag in dat venster (minuut-tik, guildvenster), dan pakt de tweede het op.
        C_Timer.After(2, requestRoster)
        C_Timer.After(13, requestRoster)
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
        if days >= comebackDays() then say("BACK", nil, name, days) end
    end
end)

-- De server meldt levels niet uit zichzelf; elke minuut de roster verversen houdt de mijlpalen actueel.
C_Timer.NewTicker(60, requestRoster)

-- Optiescherm (Esc > Options > AddOns > GuildBanter): hoofdschakelaar, taal, per soort bericht een vinkje
-- (in de volgorde van een guildleven) en, ingesprongen onder "welkom terug", de comeback-periode.
-- Alle labels volgen de gekozen taal; refresh() zet ze opnieuw bij openen en na een taalwissel.
local panel = CreateFrame("Frame")
local labels, dropdowns, dependents = {}, {}, {}

local function setOption(key, value)
    settings()[key] = value
end

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("GuildBanter")

-- Regel onder de titel: voor welke guild deze instellingen gelden.
local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

-- Grijs wat niet meedoet: alles als GuildBanter uit staat, de periode ook als "welkom terug" uit staat.
local function updateEnabled()
    for _, d in ipairs(dependents) do
        local on = d.active()
        d.widget:SetEnabled(on)
        d.label:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
    end
end

local function refresh()
    local guild = GetGuildInfo("player")
    subtitle:SetText(guild and ui().guild:format(guild) or ui().noGuild)
    for fontString, key in pairs(labels) do fontString:SetText(ui()[key]) end
    for _, dropdown in ipairs(dropdowns) do dropdown:GenerateMenu() end
    updateEnabled()
end

local function dependsOn(widget, label, active)
    if active then dependents[#dependents + 1] = {widget = widget, label = label, active = active} end
end

-- items() geeft {waarde, tekst}-paren; een functie, zodat de teksten mee vertalen.
local function addDropdown(labelKey, x, y, items, get, set, active)
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    labels[label] = labelKey
    local dropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", x, y - 18)
    dropdown:SetWidth(200)
    dropdown:SetupMenu(function(_, root)
        for _, item in ipairs(items()) do
            root:CreateRadio(item[2], function() return get() == item[1] end, function() set(item[1]) end)
        end
    end)
    dropdowns[#dropdowns + 1] = dropdown
    dependsOn(dropdown, label, active)
end

local function addCheck(labelKey, y, get, set, active)
    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 16, y)
    local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    labels[label] = labelKey
    check:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    check:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        updateEnabled()
    end)
    dependsOn(check, label, active)
end

local function enabled() return not settings().off end

-- Hoofdschakelaar, dezelfde instelling als /gb on en /gb off.
addCheck("enabled", -60, enabled, function(on) setOption("off", not on or nil) end)

addDropdown("language", 20, -100, function() return languages end, language, function(lang)
    setOption("language", lang)
    refresh()
end)

local kinds = {"HI", "40", "60", "BYE", "BACK"}
for i, kind in ipairs(kinds) do
    addCheck(kind, -130 - i * 30, function() return settings()[kind] ~= false end, function(on) setOption(kind, on) end, enabled)
end

addDropdown("comebackDays", 48, -134 - (#kinds + 1) * 30, function()
    local items = {}
    for i, days in ipairs(periods) do items[i] = {days, ui().periods[i]} end
    return items
end, comebackDays, function(days) setOption("comebackDays", days) end, function()
    return enabled() and settings().BACK ~= false
end)

panel:SetScript("OnShow", refresh)

local category = Settings.RegisterCanvasLayoutCategory(panel, "GuildBanter")
Settings.RegisterAddOnCategory(category)

-- /gb opent de opties; /gb off en /gb on zetten alles in één keer uit of aan voor deze guild (de vinkjes
-- blijven bewaard); /gb test hi|bye|back|40|60 [class] [naam]: toont lokaal een voorbeeld, opgemaakt als
-- guild chat, zonder iets naar de guild te sturen. Zonder naam is de ontvanger je eigen personage.
SLASH_GUILDBANTER1 = "/gb"
SLASH_GUILDBANTER2 = "/gw" -- oude commando van GuildWelcome blijft werken
SlashCmdList.GUILDBANTER = function(arg)
    if arg == "" then return Settings.OpenToCategory(category:GetID()) end
    if arg == "off" or arg == "on" then
        setOption("off", arg == "off" or nil)
        return print(ui()[arg])
    end
    local kind, class, name = arg:match("^test%s+(%w+)%s*(%a*)%s*(%S*)")
    if not kind then
        print(ui().usage)
        return
    end
    local me, myClass = UnitName("player"), select(2, UnitClass("player"))
    class = class ~= "" and class:upper() or myClass
    local text = line(kind:upper(), class, name ~= "" and name or me, 12)
    if not text then return print(ui().noLines:format(kind, class)) end
    -- ponytail: alleen lokaal in je eigen chatvenster, in de guildkleur, zodat het eruitziet zoals de anderen het zien
    local guild, author = ChatTypeInfo.GUILD, RAID_CLASS_COLORS[myClass]:WrapTextInColorCode("[" .. me .. "]")
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_GUILD_GET:format(author) .. text, guild.r, guild.g, guild.b)
end
