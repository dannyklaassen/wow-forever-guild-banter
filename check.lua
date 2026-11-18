-- Ontwikkelcontrole, niet in de .toc: `lua check.lua` vanuit de addonmap.
-- Toetst elk taalbestand tegen de Nederlandse opbouw: zelfde tabellen en aantallen, {name} in elke chatregel,
-- past in een chatbericht (255 tekens, met een naam van 12 tekens en 3 cijfers voor {days}), geen emdash.
-- De ui-teksten (optiescherm, /gb) volgen dezelfde opbouw maar hoeven geen {name} te bevatten.
local langs = {"nl", "en", "de", "fr", "es"}
for _, lang in ipairs(langs) do dofile("Messages_" .. lang .. ".lua") end

local errors = 0
local function fail(where, msg)
    errors = errors + 1
    print(where .. ": " .. msg)
end

local function checkText(text, where, needsName)
    if type(text) ~= "string" then return fail(where, "geen tekst") end
    if needsName and not text:find("{name}", 1, true) then fail(where, "geen {name}") end
    local filled = text:gsub("{name}", ("x"):rep(12)):gsub("{days}", "999")
    if #filled > 255 then fail(where, #filled .. " bytes, max 255") end
    if text:find("\226\128\148") then fail(where, "emdash") end
end

local function compare(ref, t, where, needsName)
    if type(ref) == "string" then return checkText(t, where, needsName) end
    if type(t) ~= "table" then return fail(where, "ontbreekt") end
    if #t ~= #ref then fail(where, ("%d regels, verwacht %d"):format(#t, #ref)) end
    for i = 1, #t do compare(ref[1], t[i], where .. "[" .. i .. "]", needsName) end
    for k, v in pairs(ref) do
        if type(k) ~= "number" then compare(v, t[k], where .. "." .. tostring(k), needsName and k ~= "ui") end
    end
    for k in pairs(t) do
        if type(k) ~= "number" and ref[k] == nil then fail(where .. "." .. tostring(k), "onbekende sleutel") end
    end
end

local ref = GuildBanterMessages.nl
for _, lang in ipairs(langs) do compare(ref, GuildBanterMessages[lang], lang, true) end
print(errors == 0 and "OK" or (errors .. " fouten"))
os.exit(errors == 0 and 0 or 1)
