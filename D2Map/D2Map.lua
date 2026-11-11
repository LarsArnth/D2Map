--------------------------------------------------------------------------------
-- D2Map – et Diablo II-inspireret automap midt på skærmen.
--
-- Viser spillets egne minimap-fliser (terræn) og quest-pins omkring spilleren,
-- halvgennemsigtigt og med nord opad. Rammen tager aldrig imod mus, så kamera,
-- bevægelse og targeting går lige igennem til spilverdenen.
--
-- Filen er delt i:
--   1. Konfigurationsdefaults
--   2. Hjælpefunktioner (hemmelige værdier, tal, chat)
--   3. Koordinater (spillerens position, zone → verden)
--   4. Rammer, styling og click-through
--   5. Terræn (minimap-fliser)
--   6. Adaptere til quest-pins (Questie, Blizzards egne quest-punkter)
--   7. Pins på automappet
--   8. Former om klyngerne af quest-mål
--   9. Gennemsigtighed og fading i combat
--  10. Opdateringsløkken (droslet OnUpdate)
--  11. Indstillinger: ét sted, hvor en værdi sættes
--  12. Indstillingsvinduet (/d2map)
--  13. Offentlig API, tastaturgenveje og slash-kommandoer
--  14. Events
--
-- Skrevet til WoW: Forever (interface 16001), men bruger kun API'er, der også
-- findes i Classic Era, og tjekker for hver af dem, om den findes.
--------------------------------------------------------------------------------

local ADDON, ns = ...

--------------------------------------------------------------------------------
-- 1. Konfigurationsdefaults
--------------------------------------------------------------------------------

-- Alt herunder gemmes pr. figur i D2MapDB (SavedVariablesPerCharacter).
local DEFAULTS = {
    enabled        = true,     -- er automappet slået til?
    opacity        = 40,       -- gennemsigtighed uden for combat, i procent
    combatOpacity  = 18,       -- gennemsigtighed i combat, i procent
    combatFade     = true,     -- skal det tones ned i combat?
    fadeTime       = 0.35,     -- sekunder en toning varer
    size           = 560,      -- rammens bredde og højde i UI-enheder
    span           = 500,      -- hvor mange yards rammen dækker fra kant til kant
    shape          = "round",  -- round | square | plain (plain = ingen maske)
    style          = "color",  -- color | sepia | ghost
    terrain        = false,    -- vis minimap-fliserne (fra: kun pins og pilen)
    pins           = "all",    -- all | objectives | off
    pinScale       = 1.0,      -- størrelsesfaktor for pins
    pinBoost       = 2.0,      -- pins er så mange gange mere synlige end terrænet
    edgePins       = true,     -- vis nærmeste pin for hver quest på kanten, når den er uden for
    route          = true,     -- tegn en blød form om hver klynge af quest-mål
    rotate         = false,    -- drej kortet, så det, figuren ser mod, er opad (ellers nord opad)
    source         = "auto",   -- auto | questie | blizzard (hvilken adapter)
    strata         = "LOW",    -- frame strata: under de fleste UI-elementer
    x              = 0,        -- forskydning fra skærmens midte
    y              = 0,
    locked         = true,     -- false = rammen kan flyttes med musen
    updateInterval = 0.1,      -- sekunder mellem opdateringer af fliser og pins
    pinSyncInterval = 1.0,     -- sekunder mellem at pins hentes fra adapteren
    maxPins        = 200,      -- loft over pins tegnet på én gang
    bindingOffered = false,    -- har vi prøvet at lægge Alt+M på toggle?
    settingsVersion = 2,       -- se MigrateSettings
}

-- Tilladte intervaller for de tal, brugeren kan sætte.
local LIMITS = {
    opacity       = { 0, 100 },
    combatOpacity = { 0, 100 },
    size          = { 200, 1400 },
    span          = { 150, 2000 },
    pinScale      = { 0.5, 3 },
}

-- Disse gemmes som hele tal (procent, pixels, yards).
local WHOLE = { opacity = true, combatOpacity = true, size = true, span = true }

local SHAPES = { round = true, square = true, plain = true }
local PIN_MODES = { all = true, objectives = true, off = true }
local SOURCES = { auto = true, questie = true, blizzard = true }

-- Hvordan fliserne farves. "ghost" lægger dem additivt oven på spillet, så
-- mørke områder forsvinder – det, der ligner Diablo II's automap mest.
local STYLES = {
    color = { desaturate = false, r = 1.00, g = 1.00, b = 1.00, blend = "BLEND" },
    sepia = { desaturate = true,  r = 1.00, g = 0.86, b = 0.62, blend = "BLEND" },
    ghost = { desaturate = true,  r = 0.78, g = 0.88, b = 1.00, blend = "ADD" },
}

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local MASKS = {
    round  = MEDIA .. "mask-round.tga",
    square = MEDIA .. "mask-square.tga",
}

-- Hvor langt ude (andel af den halve rammebredde) en pin stadig tegnes.
local PIN_REACH = { round = 0.90, square = 0.93, plain = 0.95 }

-- En minimap-flise er 1600/3 yards på hver led; verden er 64 x 64 fliser.
local TILE_YARDS = 1600 / 3

-- Pins: størrelse (UI-enheder) og tegnerækkefølge pr. slags.
local PIN_KINDS = {
    manual    = { size = 14, level = 0, edge = false },
    objective = { size = 16, level = 1, edge = true },
    available = { size = 20, level = 2, edge = false },
    complete  = { size = 22, level = 3, edge = true },
}

--------------------------------------------------------------------------------
-- 2. Hjælpefunktioner
--------------------------------------------------------------------------------

local floor, abs, sqrt, min, max = math.floor, math.abs, math.sqrt, math.min, math.max
local sin, cos = math.sin, math.cos
local pairs, ipairs, type, tonumber, tostring, pcall = pairs, ipairs, type, tonumber, tostring, pcall
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local db                       -- peger på D2MapDB, når ADDON_LOADED er kommet

-- Forever har «secret values»: tal, som addons får udleveret, men ikke må regne
-- på. Alt, der kommer fra spillet og bruges i regnestykker, går gennem IsNumber.
local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

local function IsNumber(v)
    return not IsSecret(v) and type(v) == "number" and v == v and abs(v) < 1e8
end

local function Clamp(v, low, high)
    if v < low then return low end
    if v > high then return high end
    return v
end

local function Print(msg)
    local text = "|cffc8a04bD2Map|r: " .. tostring(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    else
        print(text)
    end
end

-- Ændringer i standarderne, som også skal gælde figurer med gemte indstillinger.
local function MigrateSettings()
    local version = tonumber(db.settingsVersion) or 1
    -- Version 2: terrænet er slået fra som standard. Den første udgave gemte
    -- "til" hos alle, så det rettes én gang; slår man det til igen, bliver det.
    if version < 2 then db.terrain = false end
    db.settingsVersion = DEFAULTS.settingsVersion
end

-- Fylder manglende nøgler ud og retter værdier, der er af forkert type eller
-- uden for intervallet (fx efter en håndrettet SavedVariables-fil).
local function ValidateSettings()
    for key, default in pairs(DEFAULTS) do
        if type(db[key]) ~= type(default) then db[key] = default end
    end
    for key, limit in pairs(LIMITS) do
        if not IsNumber(db[key]) then db[key] = DEFAULTS[key] end
        db[key] = Clamp(db[key], limit[1], limit[2])
        if WHOLE[key] then db[key] = floor(db[key] + 0.5) end
    end
    if not SHAPES[db.shape] then db.shape = DEFAULTS.shape end
    if not STYLES[db.style] then db.style = DEFAULTS.style end
    if not PIN_MODES[db.pins] then db.pins = DEFAULTS.pins end
    if not SOURCES[db.source] then db.source = DEFAULTS.source end
    db.updateInterval = Clamp(db.updateInterval, 0.02, 1)
    db.pinSyncInterval = Clamp(db.pinSyncInterval, 0.2, 10)
    db.fadeTime = Clamp(db.fadeTime, 0, 5)
    db.pinBoost = Clamp(db.pinBoost, 0.5, 10)
    db.maxPins = Clamp(floor(db.maxPins), 10, 600)
    if not IsNumber(db.x) then db.x = 0 end
    if not IsNumber(db.y) then db.y = 0 end
end

--------------------------------------------------------------------------------
-- 3. Koordinater
--
-- Spillets verdenskoordinater: første tal vokser mod NORD, andet mod VEST, og
-- begge måles i yards på et kontinent (0 = Eastern Kingdoms, 1 = Kalimdor).
-- Skærmen har x mod højre (øst) og y opad (nord), så:
--     skærm-x = (spillerVest - punktVest) * pixels pr. yard
--     skærm-y = (punktNord  - spillerNord) * pixels pr. yard
--------------------------------------------------------------------------------

-- Reserve, når UnitPosition mangler eller er hemmelig: zonekortets position
-- regnet om til verdenskoordinater.
local function MapPosition()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not IsNumber(mapID) then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos or IsSecret(pos) then return end
    local continent, world = C_Map.GetWorldPosFromMapPos(mapID, pos)
    if not world or IsSecret(world) then return end
    return continent, world.x, world.y
end

-- Spillerens position: kontinent, nord, vest – eller nil (fx i instances).
local function PlayerPosition()
    if UnitPosition then
        local ok, north, west, _, continent = pcall(UnitPosition, "player")
        if ok and IsNumber(north) and IsNumber(west) and IsNumber(continent) then
            return continent, north, west
        end
    end
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos then
        local ok, continent, north, west = pcall(MapPosition)
        if ok and IsNumber(continent) and IsNumber(north) and IsNumber(west) then
            return continent, north, west
        end
    end
end

-- Et punkt på et zonekort (x og y fra 0 til 1) → kontinent, nord, vest.
local function ZoneToWorld(uiMapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, CreateVector2D(x, y))
    if not ok or not world or IsSecret(world) or not IsNumber(continent) then return end
    local north, west = world.x, world.y
    if IsNumber(north) and IsNumber(west) then
        return continent, north, west
    end
end

-- Spillerens retning i radianer (0 = nord, vokser mod uret), eller nil.
local function PlayerFacing()
    if not GetPlayerFacing then return end
    local ok, facing = pcall(GetPlayerFacing)
    if ok and IsNumber(facing) then return facing end
end

-- Kortets drejning i den igangværende opdatering. 0 = nord opad. Med «rotate»
-- slået til er det spillerens retning, så det, figuren ser mod, peger opad.
-- Sættes én gang pr. opdatering (Tick), så fliser, pins og former er enige.
local viewAngle, viewSin, viewCos = 0, 0, 1

local function SetViewAngle(angle)
    viewAngle, viewSin, viewCos = angle, sin(angle), cos(angle)
end

-- Drejer et punkt (øst, nord) i pixels fra rammens midte med uret med viewAngle.
-- Retningen figuren ser i, (-sin f, cos f), ender dermed på (0, 1): lige op.
local function ToScreen(east, north)
    return east * viewCos + north * viewSin, north * viewCos - east * viewSin
end

--------------------------------------------------------------------------------
-- 4. Rammer, styling og click-through
--
--   root      den centrerede ramme; klipper sine børn og kører OnUpdate
--   canvas    terrænet (fliserne) + masken, der giver bløde kanter
--   pinLayer  quest-pins og spillerens pil, over terrænet
--   mover     kant og tekst, kun synlig mens rammen er låst op
--------------------------------------------------------------------------------

local root, canvas, pinLayer, mover, mask, arrow
local tiles = {}              -- genbrugte flise-teksturer
local pinTextures = {}        -- genbrugte pin-teksturer
local forceTick = true        -- næste OnUpdate skal opdatere med det samme
local forceSync = true        -- næste opdatering skal hente pins forfra

-- Slår mus til eller fra på en ramme. Fra er standard: så findes rammen slet
-- ikke for musen, og klik, træk og musehjul rammer spilverdenen bagved.
local function SetMouse(frame, enabled)
    frame:EnableMouse(enabled)
    if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(enabled) end
    if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(enabled) end
    if frame.EnableMouseWheel then frame:EnableMouseWheel(enabled) end
end

local function ApplyTileStyle(tex)
    local style = STYLES[db.style] or STYLES.color
    if tex.SetDesaturated then tex:SetDesaturated(style.desaturate) end
    tex:SetVertexColor(style.r, style.g, style.b)
    tex:SetBlendMode(style.blend)
end

-- Sætter (eller fjerner) masken på én flise.
local function ApplyTileMask(tex)
    local want = mask ~= nil and MASKS[db.shape] ~= nil
    if want and not tex.masked then
        tex:AddMaskTexture(mask)
        tex.masked = true
    elseif not want and tex.masked then
        tex:RemoveMaskTexture(mask)
        tex.masked = false
    end
end

local function ApplyShape()
    if mask and MASKS[db.shape] then
        -- Uden for maskens kant er alt gennemsigtigt («clamp to black»).
        mask:SetTexture(MASKS[db.shape], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    for _, tex in ipairs(tiles) do ApplyTileMask(tex) end
end

local function ApplyStyle()
    for _, tex in ipairs(tiles) do ApplyTileStyle(tex) end
end

-- Størrelse, placering og strata. Rammen er ikke beskyttet, så det må også
-- ændres i combat.
local function ApplyLayout()
    root:SetFrameStrata(db.strata)
    root:SetSize(db.size, db.size)
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    forceTick = true
end

-- Låst = fuld click-through. Låst op = rammen kan trækkes, og musehjulet zoomer.
local function ApplyLock()
    SetMouse(root, not db.locked)
    if db.locked then
        mover:Hide()
    else
        mover:Show()
    end
end

local function SavePosition()
    local cx, cy = root:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if IsNumber(cx) and IsNumber(cy) and IsNumber(ux) and IsNumber(uy) then
        db.x = floor(cx - ux + 0.5)
        db.y = floor(cy - uy + 0.5)
    end
    ApplyLayout()
end

local SetSpan                  -- defineres i afsnit 11; bruges af musehjulet

local function CreateFrames()
    root = CreateFrame("Frame", "D2MapFrame", UIParent)
    root:SetFrameLevel(1)
    root:SetMovable(true)
    root:SetClampedToScreen(true)
    -- Reserve for klienter uden masker: fliserne skæres af ved rammens kant.
    if root.SetClipsChildren then root:SetClipsChildren(true) end
    root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart", function(self)
        if not db.locked then self:StartMoving() end
    end)
    root:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    root:SetScript("OnMouseWheel", function(_, delta)
        if not db.locked then SetSpan(db.span * (delta > 0 and 0.85 or 1 / 0.85)) end
    end)

    canvas = CreateFrame("Frame", nil, root)
    canvas:SetAllPoints(root)
    canvas:SetFrameLevel(root:GetFrameLevel() + 1)
    SetMouse(canvas, false)
    if canvas.CreateMaskTexture then
        mask = canvas:CreateMaskTexture()
        mask:SetAllPoints(canvas)
    end

    pinLayer = CreateFrame("Frame", nil, root)
    pinLayer:SetAllPoints(root)
    pinLayer:SetFrameLevel(root:GetFrameLevel() + 5)
    SetMouse(pinLayer, false)

    -- Spilleren står altid i midten; pilen drejer med figuren.
    arrow = pinLayer:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(26, 26)
    arrow:SetPoint("CENTER", pinLayer, "CENTER", 0, 0)
    local atlas = "UI-HUD-Minimap-Arrow-Player"
    if arrow.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        arrow:SetAtlas(atlas)
    else
        arrow:SetTexture("Interface\\WorldMap\\WorldMapArrow")
    end

    -- Synlig kant og vejledning, mens rammen er låst op.
    mover = CreateFrame("Frame", nil, root)
    mover:SetAllPoints(root)
    mover:SetFrameLevel(root:GetFrameLevel() + 8)
    SetMouse(mover, false)
    local tint = mover:CreateTexture(nil, "BACKGROUND")
    tint:SetAllPoints(mover)
    tint:SetColorTexture(0, 0, 0, 0.25)
    local function Edge(point, relPoint, width, height)
        local line = mover:CreateTexture(nil, "BORDER")
        line:SetColorTexture(0.78, 0.63, 0.29, 0.9)
        line:SetPoint(point, mover, point, 0, 0)
        line:SetPoint(relPoint, mover, relPoint, 0, 0)
        if width then line:SetWidth(width) else line:SetHeight(height) end
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, 2)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
    Edge("TOPLEFT", "BOTTOMLEFT", 2, nil)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil)
    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOP", mover, "TOP", 0, -10)
    label:SetText("D2Map unlocked\nDrag to move, mouse wheel to zoom\n/d2map lock when done")

    ApplyShape()
    ApplyLayout()
    ApplyLock()
end

--------------------------------------------------------------------------------
-- 5. Terræn
--
-- Fliserne lægges i et gitter omkring spilleren. Flise (kolonne, række) har sin
-- midte (kolonne + ½ - cx) fliser øst og (række + ½ - cy) fliser syd for
-- spilleren, hvor cx, cy er spillerens egen position målt i fliser.
-- Hver opdatering flytter kun fliserne; teksturen skiftes først, når spilleren
-- går ind på en ny flise. Drejes kortet, drejes hver flise om sin egen midte og
-- flyttes til den drejede plads – det er det samme som at dreje hele kortet.
--------------------------------------------------------------------------------

local tilesShown = 0

local function AcquireTile(index)
    local tex = tiles[index]
    if tex then return tex end
    tex = canvas:CreateTexture(nil, "ARTWORK")
    -- Fliserne står på brøkdele af pixels; uden snapping bliver der ingen sprækker.
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
    tiles[index] = tex
    ApplyTileStyle(tex)
    ApplyTileMask(tex)
    return tex
end

local function HideTiles(from)
    for i = from, #tiles do
        local tex = tiles[i]
        if tex.shown then
            tex:Hide()
            tex.shown = false
        end
    end
end

local function UpdateTerrain(continent, north, west)
    local data = db.terrain and ns.Tiles and ns.Tiles[continent]
    if not data then
        HideTiles(1)
        tilesShown = 0
        return
    end
    local tilePx = TILE_YARDS * db.size / db.span          -- en flises kant på skærmen
    local cx, cy = 32 - west / TILE_YARDS, 32 - north / TILE_YARDS
    local half = db.span / TILE_YARDS / 2                  -- den halve ramme målt i fliser
    -- En drejet firkant når længere ud i hjørnerne (√2); cirklen gør ikke.
    if viewAngle ~= 0 and db.shape ~= "round" then half = half * 1.4143 end
    local count = 0
    for col = max(0, floor(cx - half)), min(63, floor(cx + half)) do
        for row = max(0, floor(cy - half)), min(63, floor(cy + half)) do
            local fileID = data[col * 64 + row]
            if fileID then
                count = count + 1
                local tex = AcquireTile(count)
                if tex.fileID ~= fileID then
                    tex:SetTexture(fileID, nil, nil, "TRILINEAR")
                    tex.fileID = fileID
                end
                if tex.px ~= tilePx then
                    tex:SetSize(tilePx, tilePx)
                    tex.px = tilePx
                end
                if tex.angle ~= viewAngle and tex.SetRotation then
                    tex:SetRotation(-viewAngle)                -- SetRotation drejer mod uret
                    tex.angle = viewAngle
                end
                tex:SetPoint("CENTER", canvas, "CENTER",
                    ToScreen((col + 0.5 - cx) * tilePx, -(row + 0.5 - cy) * tilePx))
                if not tex.shown then
                    tex:Show()
                    tex.shown = true
                end
            end
        end
    end
    HideTiles(count + 1)
    tilesShown = count
end

--------------------------------------------------------------------------------
-- 6. Adaptere til quest-pins
--
-- En adapter er en tabel med:
--     name                     navnet, der vises i /d2map status
--     IsAvailable()            true, når kilden er indlæst og har data
--     Collect(out, wants)      fylder out[1..n] med pins og returnerer n
--
-- wants er en tabel { objective = bool, complete = bool, available = bool,
-- manual = bool }, så adapteren kan springe det over, brugeren har slået fra.
-- Hver pin skrives med ns.EmitPin(out, n, continent, north, west, texture,
-- r, g, b, kind, questID). Koordinaterne er verdenskoordinater i yards.
--
-- Nye kilder (fx pfQuest på en 1.12-klient) registreres med
-- D2Map.RegisterAdapter("navn", adapter) – resten af addon'en er ligeglad med,
-- hvor pins kommer fra.
--------------------------------------------------------------------------------

local adapters = {}                          -- navn → adapter
local adapterOrder = {}                      -- prioriteret rækkefølge for "auto"

local function RegisterAdapter(key, adapter)
    if type(key) ~= "string" or type(adapter) ~= "table"
        or type(adapter.IsAvailable) ~= "function" or type(adapter.Collect) ~= "function" then
        error("D2Map.RegisterAdapter(key, adapter): adapter needs IsAvailable() and Collect(out, wants)", 2)
    end
    key = key:lower()
    if not adapters[key] then adapterOrder[#adapterOrder + 1] = key end
    adapters[key] = adapter
    SOURCES[key] = true
    forceSync = true
end

-- Genbruger tabellerne i out, så der ikke laves affald hvert sekund.
local function EmitPin(out, n, continent, north, west, texture, r, g, b, kind, questID)
    local rec = out[n]
    if not rec then
        rec = {}
        out[n] = rec
    end
    rec.continent, rec.north, rec.west = continent, north, west
    rec.texture, rec.r, rec.g, rec.b = texture, r or 1, g or 1, b or 1
    rec.kind, rec.quest = kind, questID
    return rec
end
ns.EmitPin = EmitPin

---- Questie -------------------------------------------------------------------
-- Questie lægger alle sine kort-ikoner i HereBeDragons' register:
--     LibStub("HereBeDragonsQuestie-Pins-2.0").worldmapPinRegistry[Questie]
-- Nøglerne er ikon-rammerne. Hver har x og y (zone-koordinater i procent),
-- UiMapID, data (Type, Id, Icon …), texture og hidden (Questies egne filtre).
-- Vi læser kun – Questie bestemmer selv, hvad der findes og er synligt.

local QUESTIE_KINDS = {
    monster = "objective", object = "objective", item = "objective", event = "objective",
    complete = "complete", available = "available", manual = "manual",
}

-- Zone → verden koster et opslag og en vektor, så resultatet huskes pr. ikon.
-- Questie genbruger sine rammer, derfor sammenlignes x, y og kort hver gang.
local questieWorld = setmetatable({}, { __mode = "k" })

local function QuestieRegistry()
    if not Questie or not LibStub then return end
    for _, name in ipairs({ "HereBeDragonsQuestie-Pins-2.0", "HereBeDragons-Pins-2.0" }) do
        local ok, lib = pcall(LibStub, name, true)
        if ok and type(lib) == "table" and type(lib.worldmapPinRegistry) == "table"
            and type(lib.worldmapPinRegistry[Questie]) == "table" then
            return lib.worldmapPinRegistry[Questie]
        end
    end
end

local function QuestieIconWorld(icon)
    local x, y, mapID = icon.x, icon.y, icon.UiMapID
    if not (IsNumber(x) and IsNumber(y) and IsNumber(mapID)) then return end
    local cached = questieWorld[icon]
    if cached and cached.x == x and cached.y == y and cached.mapID == mapID then
        return cached.continent, cached.north, cached.west
    end
    local continent, north, west = ZoneToWorld(mapID, x / 100, y / 100)
    cached = cached or {}
    cached.x, cached.y, cached.mapID = x, y, mapID
    cached.continent, cached.north, cached.west = continent, north, west
    questieWorld[icon] = cached
    return continent, north, west
end

-- Det billede, Questie faktisk viser på ikonet (stien eller fil-id'et).
local function QuestieIconTexture(icon, data)
    local texture = icon.texture
    if texture and texture.GetTexture then
        local ok, shown = pcall(texture.GetTexture, texture)
        if ok and shown and not IsSecret(shown) then return shown end
    end
    local used = Questie.usedIcons
    if used and data.Icon ~= nil and used[data.Icon] then return used[data.Icon] end
    if type(data.Icon) == "string" then return data.Icon end
end

RegisterAdapter("questie", {
    name = "Questie",
    IsAvailable = function()
        return QuestieRegistry() ~= nil
    end,
    Collect = function(out, wants)
        local registry = QuestieRegistry()
        if not registry then return 0 end
        local n = 0
        for icon in pairs(registry) do
            local data = icon.data
            if type(data) == "table" and not icon.hidden and not icon.miniMapIcon then
                local kind = QUESTIE_KINDS[data.Type]
                if kind and wants[kind] then
                    local continent, north, west = QuestieIconWorld(icon)
                    local image = continent and QuestieIconTexture(icon, data)
                    if image then
                        n = n + 1
                        local tex = icon.texture
                        -- Questie gemmer sin farve på teksturen (r, g, b).
                        EmitPin(out, n, continent, north, west, image,
                            tex and tex.r, tex and tex.g, tex and tex.b,
                            kind, kind ~= "manual" and data.Id or nil)
                    end
                end
            end
        end
        return n
    end,
})

---- Blizzards egne quest-punkter ---------------------------------------------
-- Reserve, når Questie ikke er installeret: de quest-punkter, spillet selv
-- viser på zonekortet (ét punkt pr. quest, ikke hver enkelt mob).

local function QuestIsComplete(questID)
    if C_QuestLog and C_QuestLog.IsComplete then
        local ok, done = pcall(C_QuestLog.IsComplete, questID)
        if ok and not IsSecret(done) then return done == true end
    end
    if IsQuestComplete then
        local ok, done = pcall(IsQuestComplete, questID)
        if ok and not IsSecret(done) then return done == true end
    end
    return false
end

RegisterAdapter("blizzard", {
    name = "Blizzard quest log",
    IsAvailable = function()
        return C_QuestLog ~= nil and C_QuestLog.GetQuestsOnMap ~= nil
            and C_Map ~= nil and C_Map.GetBestMapForUnit ~= nil
    end,
    Collect = function(out, wants)
        local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
        if not okMap or not IsNumber(mapID) then return 0 end
        local ok, quests = pcall(C_QuestLog.GetQuestsOnMap, mapID)
        if not ok or type(quests) ~= "table" then return 0 end
        local n = 0
        for i = 1, #quests do
            local quest = quests[i]
            if type(quest) == "table" and IsNumber(quest.x) and IsNumber(quest.y) and IsNumber(quest.questID) then
                local complete = QuestIsComplete(quest.questID)
                local kind = complete and "complete" or "objective"
                if wants[kind] then
                    local continent, north, west = ZoneToWorld(mapID, quest.x, quest.y)
                    if continent then
                        n = n + 1
                        EmitPin(out, n, continent, north, west,
                            complete and "Interface\\GossipFrame\\ActiveQuestIcon"
                                or "Interface\\COMMON\\Indicator-Yellow",
                            1, 1, 1, kind, quest.questID)
                    end
                end
            end
        end
        return n
    end,
})

-- Den adapter, der skal bruges lige nu: den valgte, eller ved "auto" den første
-- i rækkefølgen, som har data.
local function ActiveAdapter()
    if db.source ~= "auto" then
        local chosen = adapters[db.source]
        if chosen and chosen.IsAvailable() then return chosen end
        return nil
    end
    for _, key in ipairs(adapterOrder) do
        local adapter = adapters[key]
        if adapter.IsAvailable() then return adapter end
    end
end

--------------------------------------------------------------------------------
-- 7. Pins på automappet
--
-- To takter: pins HENTES fra adapteren ca. én gang i sekundet (SyncPins), og de
-- FLYTTES i forhold til spilleren ved hver opdatering (UpdatePins). At flytte
-- er kun et par gange og plus pr. pin.
--------------------------------------------------------------------------------

local records = {}             -- pins fra adapteren (genbrugte tabeller)
local recordCount = 0
local pinsShown = 0
local activeAdapterName = "none"
local wants = {}               -- hvilke slags pins brugeren vil se

-- Arbejdstabeller til kant-pins, genbrugt mellem opdateringer.
local questInView = {}         -- questID → true, når en af dens pins er inden for rammen
local nearestRec, nearestDist, nearestX, nearestY = {}, {}, {}, {}

local function SyncPins()
    forceSync = false
    recordCount = 0
    activeAdapterName = "none"
    if db.pins == "off" then return end
    wants.objective = true
    wants.complete = true
    wants.available = db.pins == "all"
    wants.manual = db.pins == "all"
    local adapter = ActiveAdapter()
    if not adapter then return end
    activeAdapterName = adapter.name or "?"
    local ok, count = pcall(adapter.Collect, records, wants)
    if ok and IsNumber(count) then
        recordCount = count
    else
        activeAdapterName = activeAdapterName .. " (error: " .. tostring(count) .. ")"
    end
end

local function AcquirePin(index)
    local tex = pinTextures[index]
    if tex then return tex end
    tex = pinLayer:CreateTexture(nil, "ARTWORK")
    pinTextures[index] = tex
    return tex
end

-- Tegner én pin på (x, y) fra rammens midte. scale og alpha bruges til de
-- mindre, svagere pins på kanten.
local function PlacePin(index, rec, x, y, scale, alpha)
    local tex = AcquirePin(index)
    local kind = PIN_KINDS[rec.kind] or PIN_KINDS.objective
    if tex.image ~= rec.texture then
        tex:SetTexture(rec.texture)
        tex.image = rec.texture
    end
    if tex.level ~= kind.level then
        tex:SetDrawLayer("ARTWORK", kind.level)
        tex.level = kind.level
    end
    local size = kind.size * db.pinScale * scale
    if tex.px ~= size then
        tex:SetSize(size, size)
        tex.px = size
    end
    tex:SetVertexColor(rec.r, rec.g, rec.b, alpha)
    tex:SetPoint("CENTER", pinLayer, "CENTER", x, y)
    if not tex.shown then
        tex:Show()
        tex.shown = true
    end
end

local function HidePins(from)
    for i = from, #pinTextures do
        local tex = pinTextures[i]
        if tex.shown then
            tex:Hide()
            tex.shown = false
        end
    end
end

local function UpdatePins(continent, north, west)
    if recordCount == 0 then
        HidePins(1)
        pinsShown = 0
        return
    end
    local pxPerYard = db.size / db.span
    local reach = db.size / 2 * (PIN_REACH[db.shape] or 0.9)
    local roundShape = db.shape == "round"
    local edgePins = db.edgePins
    local maxPins = db.maxPins
    local shown = 0

    wipe(questInView)
    wipe(nearestRec)

    for i = 1, recordCount do
        local rec = records[i]
        if rec.continent == continent then
            -- øst er til højre og nord opad, før kortet evt. drejes
            local x, y = ToScreen((west - rec.west) * pxPerYard, (rec.north - north) * pxPerYard)
            local inside
            if roundShape then
                inside = x * x + y * y <= reach * reach
            else
                inside = abs(x) <= reach and abs(y) <= reach
            end
            if inside then
                if shown < maxPins then
                    shown = shown + 1
                    PlacePin(shown, rec, x, y, 1, 1)
                end
                if rec.quest then questInView[rec.quest] = true end
            elseif edgePins and rec.quest and (PIN_KINDS[rec.kind] or PIN_KINDS.objective).edge then
                -- Husk den nærmeste pin uden for rammen for hver quest.
                local dist = x * x + y * y
                local quest = rec.quest
                if not nearestRec[quest] or dist < nearestDist[quest] then
                    nearestRec[quest], nearestDist[quest] = rec, dist
                    nearestX[quest], nearestY[quest] = x, y
                end
            end
        end
    end

    -- Quests helt uden pins i rammen får én lille pin på kanten, i den retning
    -- den nærmeste ligger – så man kan se, hvilken vej man skal.
    if edgePins then
        for quest, rec in pairs(nearestRec) do
            if not questInView[quest] and shown < maxPins then
                local x, y = nearestX[quest], nearestY[quest]
                local factor
                if roundShape then
                    factor = reach / sqrt(nearestDist[quest])
                else
                    factor = reach / max(abs(x), abs(y))
                end
                shown = shown + 1
                PlacePin(shown, rec, x * factor, y * factor, 0.75, 0.75)
            end
        end
    end

    HidePins(shown + 1)
    pinsShown = shown
end

--------------------------------------------------------------------------------
-- 8. Former om klyngerne af quest-mål
--
-- I stedet for en streg, der rammer hver mob, tegnes en blød, lukket form om
-- hver klynge af mål: «her er området – løb rundt i det». Enlige mål får ingen
-- form; de har deres pin. Fire trin:
--   1. Klynger: mål, der ligger tættere end en «lænkeafstand», hører sammen
--      (og dermed også deres naboers naboer). Afstanden er det dobbelte af
--      den typiske afstand til nærmeste nabo (mindst 60, højst 150 yards), så
--      det passer både til tætte og spredte pins.
--   2. Omrids: den konvekse skal om klyngen (som en elastik om søm).
--   3. Indhak: en lang kant graves ind til det nærmeste mål bag den, så formen
--      følger klyngen i stedet for at spænde over tomme områder.
--   4. Blødgøring: hjørnerne skæres af et par gange (Chaikin), så omridset
--      bliver en jævn kurve. Hvert hjørne flyttes først så meget, at kurven
--      ender en halv snes yards uden om målet – ikke igennem det.
--
-- Formerne ligger fast i verden og afhænger ikke af, hvor spilleren står. De
-- regnes derfor kun om, når målene ændrer sig, eller spilleren har flyttet sig
-- et godt stykke – ikke hvert sekund.
--------------------------------------------------------------------------------

local LOOP_MAX_POINTS = 250        -- kun de nærmeste mål regnes med
local LOOP_MERGE_YARDS = 8         -- mål tættere end det er samme sted
local LOOP_MIN_CLUSTER = 3         -- så mange mål skal der til en form
local LOOP_LINK_FACTOR = 2         -- lænkeafstand = så mange gange den typiske afstand til nærmeste nabo
local LOOP_LINK_MIN = 60           -- … men inden for disse grænser (yards)
local LOOP_LINK_MAX = 150
local LOOP_DIG_RATIO = 2           -- grav ind, når kanten er så mange gange længere end dybden
local LOOP_MARGIN_YARDS = 12       -- så langt uden om de yderste mål går den færdige form
local LOOP_MAX_PUSH = 70           -- et hjørne flyttes højst så langt for at opnå det
local LOOP_MAX_LINES = 400         -- loft over linjestykker tegnet på én gang

local loopNorth, loopWest = {}, {} -- alle formers punkter efter hinanden (verdenskoordinater)
local loopStart = {}               -- loopStart[k] = første punkt i form k; [loopCount + 1] = slut + 1
local loopCount = 0
local loopLink = 0                 -- den lænkeafstand, der blev brugt (til /d2map status)
local loopLines = {}               -- genbrugte linjer
local loopLinesShown = 0

-- Hvad formerne sidst blev regnet ud fra.
local builtSignature, builtContinent, builtNorth, builtWest, builtSpan

-- Målene, der regnes på: x mod øst, y mod nord (yards).
local pointX, pointY, pointDist, pointOrder = {}, {}, {}, {}

local function ByPointDistance(a, b)
    return pointDist[a] < pointDist[b]
end

local function ByPosition(a, b)
    if pointX[a] ~= pointX[b] then return pointX[a] < pointX[b] end
    return pointY[a] < pointY[b]
end

local function PointDistance(a, b)
    local dx, dy = pointX[a] - pointX[b], pointY[a] - pointY[b]
    return sqrt(dx * dx + dy * dy)
end

-- Afstanden fra punkt p til linjestykket a-b.
local function SegmentDistance(p, a, b)
    local ax, ay = pointX[a], pointY[a]
    local dx, dy = pointX[b] - ax, pointY[b] - ay
    local px, py = pointX[p] - ax, pointY[p] - ay
    local length = dx * dx + dy * dy
    local t = length > 0 and Clamp((px * dx + py * dy) / length, 0, 1) or 0
    local ex, ey = px - t * dx, py - t * dy
    return sqrt(ex * ex + ey * ey)
end

-- Positiv, når o → a → b drejer mod uret.
local function Cross(o, a, b)
    return (pointX[a] - pointX[o]) * (pointY[b] - pointY[o]) - (pointY[a] - pointY[o]) * (pointX[b] - pointX[o])
end

-- Den konvekse skal om en klynge (Andrews «monotone chain»), mod uret.
local function ConvexHull(members)
    table.sort(members, ByPosition)
    local hull = {}
    for pass = 1, 2 do
        local base = #hull
        local from, to, step = 1, #members, 1
        if pass == 2 then from, to, step = #members, 1, -1 end
        for i = from, to, step do
            local p = members[i]
            while #hull >= base + 2 and Cross(hull[#hull - 1], hull[#hull], p) <= 0 do
                hull[#hull] = nil
            end
            hull[#hull + 1] = p
        end
        hull[#hull] = nil                                  -- sidste punkt er næste halvdels første
    end
    return hull
end

-- Graver lange kanter ind til klyngens rand: en kant, der er længere end
-- lænkeafstanden, får det nærmeste mål sat ind, hvis det ligger tæt på kanten
-- i forhold til dens længde – og ikke tættere på en af nabokanterne.
-- Et mål må stå i omridset to gange. Det er det, der lader en smal række af
-- mål (langs en vej eller en kyst) blive til et bånd: omridset går ud langs
-- rækken og tilbage igen, og blødgøringen skubber de to sider fra hinanden.
local function DigHull(hull, members, link)
    local uses = {}
    for _, p in ipairs(hull) do uses[p] = 1 end
    local i, guard = 1, 0
    while i <= #hull and guard < 600 do
        guard = guard + 1
        local count = #hull
        local a, b = hull[i], hull[i % count + 1]
        local length = PointDistance(a, b)
        local dug = false
        if length > link then
            -- Det nærmeste mål, som hører til denne kant (ikke en nabokant).
            local before, after = hull[(i - 2) % count + 1], hull[(i + 1) % count + 1]
            local best, bestDist
            for _, p in ipairs(members) do
                if (uses[p] or 0) < 2 and p ~= a and p ~= b and p ~= before and p ~= after then
                    local d = SegmentDistance(p, a, b)
                    if (not bestDist or d < bestDist)
                        and d <= SegmentDistance(p, before, a) and d <= SegmentDistance(p, b, after) then
                        best, bestDist = p, d
                    end
                end
            end
            if best and length / max(bestDist, 1) > LOOP_DIG_RATIO then
                table.insert(hull, i + 1, best)
                uses[best] = (uses[best] or 0) + 1
                dug = true                                 -- prøv den samme kant igen: den er kortere nu
            end
        end
        if not dug then i = i + 1 end
    end
end

-- Gør omridset til en blød form. Returnerer to lister (x og y) med formens punkter.
--
-- Chaikins hjørneskæring ender i en kurve, der ved hjørnet V med naboerne A og
-- B går gennem (A + 6V + B) / 8 – altså et stykke inden for V, og mere jo
-- spidsere hjørnet og jo længere kanterne er. Skal kurven i stedet gå gennem
-- V + margen · n (n = retningen udad), må hjørnet flyttes til
--     V' = V + 4/3 · margen · n + (2V - A - B) / 6
-- (naboernes egen flytning er ikke regnet med; det er tæt nok).
local function SmoothOutline(hull)
    local xs, ys = {}, {}
    local count = #hull
    if count < 3 then
        -- Alle mål på én linje: en smal kasse om linjen.
        local a, b = hull[1], hull[count]
        local dx, dy = pointX[b] - pointX[a], pointY[b] - pointY[a]
        local length = max(sqrt(dx * dx + dy * dy), 1)
        local ux, uy = dx / length * LOOP_MARGIN_YARDS, dy / length * LOOP_MARGIN_YARDS
        xs = { pointX[a] - ux + uy, pointX[b] + ux + uy, pointX[b] + ux - uy, pointX[a] - ux - uy }
        ys = { pointY[a] - uy - ux, pointY[b] + uy - ux, pointY[b] + uy + ux, pointY[a] - uy + ux }
    else
        -- Skallen står mod uret, og indhakkene ændrer ikke på det. Så peger
        -- (dy, -dx) udad for hver kant – også på tilbagevejen i et bånd, hvor
        -- kanten løber modsat og normalen derfor vender til den anden side.
        local sign = 1
        for i = 1, count do
            local before, here, after = hull[(i - 2) % count + 1], hull[i], hull[i % count + 1]
            -- Udadrettede normaler på de to kanter, der mødes i hjørnet.
            local ax, ay = pointY[here] - pointY[before], pointX[before] - pointX[here]
            local bx, by = pointY[after] - pointY[here], pointX[here] - pointX[after]
            local al, bl = max(sqrt(ax * ax + ay * ay), 0.001), max(sqrt(bx * bx + by * by), 0.001)
            local nx, ny = ax / al + bx / bl, ay / al + by / bl
            local nl = sqrt(nx * nx + ny * ny)
            if nl < 0.001 then nx, ny, nl = ax / al, ay / al, 1 end
            local push = 4 / 3 * LOOP_MARGIN_YARDS * sign / nl
            local mx = push * nx + (2 * pointX[here] - pointX[before] - pointX[after]) / 6
            local my = push * ny + (2 * pointY[here] - pointY[before] - pointY[after]) / 6
            local moved = sqrt(mx * mx + my * my)
            if moved > LOOP_MAX_PUSH then mx, my = mx / moved * LOOP_MAX_PUSH, my / moved * LOOP_MAX_PUSH end
            xs[i], ys[i] = pointX[here] + mx, pointY[here] + my
        end
    end

    -- Chaikin: hver kant bliver til to punkter, ¼ og ¾ henne. Tre runder giver
    -- en jævn kurve; store omrids nøjes med to.
    for _ = 1, (#xs > 10 and 2 or 3) do
        local nx, ny, n = {}, {}, #xs
        for i = 1, n do
            local j = i % n + 1
            nx[#nx + 1], ny[#ny + 1] = 0.75 * xs[i] + 0.25 * xs[j], 0.75 * ys[i] + 0.25 * ys[j]
            nx[#nx + 1], ny[#ny + 1] = 0.25 * xs[i] + 0.75 * xs[j], 0.25 * ys[i] + 0.75 * ys[j]
        end
        xs, ys = nx, ny
    end
    return xs, ys
end

-- Regner formerne ud, hvis der er grund til det. Kaldes, når pins er hentet
-- (ca. én gang i sekundet), men gør for det meste ingenting.
local function BuildLoops(continent, north, west)
    if not db.route or recordCount == 0 then
        loopCount, builtSignature = 0, nil
        return
    end

    -- Et fingeraftryk af alle mål på kontinentet (hele tal, så rækkefølgen er ligegyldig).
    local signature = continent
    for i = 1, recordCount do
        local rec = records[i]
        if rec.continent == continent and rec.kind == "objective" then
            signature = signature + 1000003 + floor(rec.north * 4 + 0.5) * 3 + floor(rec.west * 4 + 0.5)
        end
    end
    if signature == builtSignature and continent == builtContinent and db.span == builtSpan
        and max(abs(north - builtNorth), abs(west - builtWest)) < db.span / 4 then
        return                                             -- intet nyt, og spilleren er ikke gået langt
    end
    builtSignature, builtContinent, builtNorth, builtWest, builtSpan = signature, continent, north, west, db.span
    loopCount = 0

    -- Mål inden for to rammebredder; så er alt i rammen med, også efter man har
    -- flyttet sig en kvart ramme.
    local radius = db.span
    local found = 0
    for i = 1, recordCount do
        local rec = records[i]
        if rec.continent == continent and rec.kind == "objective" then
            local dn, dw = rec.north - north, rec.west - west
            local dist = dn * dn + dw * dw
            if dist <= radius * radius then
                found = found + 1
                pointX[found], pointY[found], pointDist[found] = -rec.west, rec.north, dist
            end
        end
    end

    -- De nærmeste først; mål samme sted (to quests på samme mob) tæller én gang.
    for i = 1, found do pointOrder[i] = i end
    for i = found + 1, #pointOrder do pointOrder[i] = nil end
    table.sort(pointOrder, ByPointDistance)
    local points = {}
    for _, p in ipairs(pointOrder) do
        local merged = false
        for _, q in ipairs(points) do
            local dx, dy = pointX[p] - pointX[q], pointY[p] - pointY[q]
            if dx * dx + dy * dy <= LOOP_MERGE_YARDS * LOOP_MERGE_YARDS then
                merged = true
                break
            end
        end
        if not merged then
            points[#points + 1] = p
            if #points >= LOOP_MAX_POINTS then break end
        end
    end
    if #points < LOOP_MIN_CLUSTER then return end

    -- 1. Lænkeafstand: det dobbelte af den typiske (median) afstand til nærmeste nabo.
    local nearest = {}
    for i, p in ipairs(points) do
        local best
        for j, q in ipairs(points) do
            if i ~= j then
                local d = PointDistance(p, q)
                if not best or d < best then best = d end
            end
        end
        nearest[i] = best
    end
    table.sort(nearest)
    local link = Clamp(LOOP_LINK_FACTOR * nearest[floor((#nearest + 1) / 2)], LOOP_LINK_MIN, LOOP_LINK_MAX)
    link = floor(link / 10 + 0.5) * 10                     -- hele tiere, så klyngerne ikke flakker
    loopLink = link

    -- Klynger: to mål inden for lænkeafstanden får samme «rod».
    local parent = {}
    for i = 1, #points do parent[i] = i end
    local function Root(i)
        while parent[i] ~= i do
            parent[i] = parent[parent[i]]
            i = parent[i]
        end
        return i
    end
    for i = 1, #points do
        for j = i + 1, #points do
            if PointDistance(points[i], points[j]) <= link then
                parent[Root(i)] = Root(j)
            end
        end
    end
    local clusters, order = {}, {}
    for i = 1, #points do
        local root = Root(i)
        if not clusters[root] then
            clusters[root] = {}
            order[#order + 1] = root
        end
        table.insert(clusters[root], points[i])
    end

    -- 2.-4. En form pr. klynge.
    local total = 0
    for _, root in ipairs(order) do
        local members = clusters[root]
        if #members >= LOOP_MIN_CLUSTER then
            local hull = ConvexHull(members)
            if #hull >= 3 then DigHull(hull, members, link) end
            local xs, ys = SmoothOutline(hull)
            loopCount = loopCount + 1
            loopStart[loopCount] = total + 1
            for i = 1, #xs do
                total = total + 1
                loopNorth[total], loopWest[total] = ys[i], -xs[i]
            end
        end
    end
    loopStart[loopCount + 1] = total + 1
end

local function AcquireLine(index)
    local line = loopLines[index]
    if line then return line end
    line = pinLayer:CreateLine(nil, "BORDER")              -- under pins (ARTWORK)
    line:SetThickness(2)
    line:SetColorTexture(0.95, 0.80, 0.35, 0.85)
    loopLines[index] = line
    return line
end

-- Flytter formernes linjer i forhold til spilleren. Kaldes ved hver opdatering.
-- Et stykke tegnes kun, når begge ender ligger inden for rammen.
local function UpdateLoops(north, west)
    local count = (db.route and pinLayer.CreateLine) and loopCount or 0
    local pxPerYard = db.size / db.span
    local reach = db.size / 2 * (PIN_REACH[db.shape] or 0.9)
    local roundShape = db.shape == "round"
    local used = 0
    for k = 1, count do
        local first, last = loopStart[k], loopStart[k + 1] - 1
        -- Formen er lukket: begynd ved det sidste punkt.
        local fromX, fromY = ToScreen((west - loopWest[last]) * pxPerYard, (loopNorth[last] - north) * pxPerYard)
        local fromInside
        if roundShape then
            fromInside = fromX * fromX + fromY * fromY <= reach * reach
        else
            fromInside = abs(fromX) <= reach and abs(fromY) <= reach
        end
        for i = first, last do
            local x, y = ToScreen((west - loopWest[i]) * pxPerYard, (loopNorth[i] - north) * pxPerYard)
            local inside
            if roundShape then
                inside = x * x + y * y <= reach * reach
            else
                inside = abs(x) <= reach and abs(y) <= reach
            end
            if inside and fromInside and used < LOOP_MAX_LINES then
                used = used + 1
                local line = AcquireLine(used)
                line:SetStartPoint("CENTER", pinLayer, fromX, fromY)
                line:SetEndPoint("CENTER", pinLayer, x, y)
                if not line.shown then
                    line:Show()
                    line.shown = true
                end
            end
            fromX, fromY, fromInside = x, y, inside
        end
    end
    for i = used + 1, #loopLines do
        local line = loopLines[i]
        if line.shown then
            line:Hide()
            line.shown = false
        end
    end
    loopLinesShown = used
end

--------------------------------------------------------------------------------
-- 9. Gennemsigtighed og fading i combat
--
-- Terrænet får den valgte gennemsigtighed; pins og pilen er pinBoost gange mere
-- synlige (ellers drukner de). I combat glider begge ned til combatOpacity.
--------------------------------------------------------------------------------

local inCombat = false
local alpha = 0                -- den gennemsigtighed, der vises lige nu (0-1)

local function TargetAlpha()
    local percent = db.opacity
    if inCombat and db.combatFade then percent = min(db.opacity, db.combatOpacity) end
    -- Mens rammen flyttes, skal den kunne ses.
    if not db.locked then percent = max(percent, 60) end
    return percent / 100
end

local function ApplyAlpha()
    canvas:SetAlpha(alpha)
    pinLayer:SetAlpha(Clamp(alpha * db.pinBoost, 0, 1))
end

-- Kaldes hver frame, men gør kun noget, mens der tones.
local function UpdateFade(elapsed)
    local target = TargetAlpha()
    if alpha == target then return end
    if db.fadeTime <= 0 then
        alpha = target
    else
        -- Farten svarer til, at springet mellem normal og combat tager fadeTime.
        local range = max(0.1, abs(db.opacity - db.combatOpacity) / 100)
        local step = range / db.fadeTime * elapsed
        if alpha < target then
            alpha = min(target, alpha + step)
        else
            alpha = max(target, alpha - step)
        end
    end
    ApplyAlpha()
end

local function SnapAlpha()
    alpha = TargetAlpha()
    ApplyAlpha()
end

--------------------------------------------------------------------------------
-- 10. Opdateringsløkken
--
-- OnUpdate sidder på root, så et skjult automap koster ingenting. Fliser og
-- pins opdateres hvert updateInterval sekund (0,1 som standard), ikke hver frame.
--------------------------------------------------------------------------------

local sinceTick, sinceSync = 0, 0
local hasPosition = nil        -- nil = ukendt, true/false = sidste opdatering
local lastFacing = nil         -- figurens retning ved sidste opdatering
local tickFailed = false

local function Tick(elapsed)
    local continent, north, west = PlayerPosition()
    if not continent then
        -- Ingen position (instance, loading screen, hemmelig værdi): vis intet
        -- frem for et kort, der står stille et forkert sted.
        if hasPosition ~= false then
            canvas:Hide()
            pinLayer:Hide()
            hasPosition = false
        end
        return
    end
    if hasPosition ~= true then
        canvas:Show()
        pinLayer:Show()
        hasPosition = true
    end

    -- Kortets drejning i denne opdatering: figurens retning, eller nord opad.
    local facing = PlayerFacing()
    lastFacing = facing
    SetViewAngle(db.rotate and facing or 0)

    UpdateTerrain(continent, north, west)

    sinceSync = sinceSync + elapsed
    if forceSync or sinceSync >= db.pinSyncInterval then
        sinceSync = 0
        SyncPins()
        BuildLoops(continent, north, west)
    end
    UpdatePins(continent, north, west)
    UpdateLoops(north, west)

    -- Pilen viser figurens retning på kortet: lige op, når kortet drejer med.
    if arrow.SetRotation then arrow:SetRotation((facing or 0) - viewAngle) end
end

local function OnUpdate(_, elapsed)
    UpdateFade(elapsed)
    sinceTick = sinceTick + elapsed
    -- Et kort, der drejer i ti hak i sekundet, ser hakkende ud. Mens figuren
    -- drejer, opdateres der derfor hver frame; står den stille, er takten som før.
    if db.rotate and PlayerFacing() ~= lastFacing then forceTick = true end
    if not forceTick and sinceTick < db.updateInterval then return end
    local passed = sinceTick
    sinceTick = 0
    forceTick = false
    if tickFailed then return end
    local ok, err = pcall(Tick, passed)
    if not ok then
        -- Én besked og så stilhed – ikke ti fejl i sekundet.
        tickFailed = true
        canvas:Hide()
        pinLayer:Hide()
        hasPosition = nil
        Print("stopped after an error: " .. tostring(err) .. " – /d2map toggle twice to retry.")
    end
end

-- Viser eller skjuler hele automappet efter db.enabled.
local function ApplyEnabled()
    if db.enabled then
        tickFailed = false
        forceTick = true
        forceSync = true
        SnapAlpha()
        root:Show()
    else
        root:Hide()
    end
end

--------------------------------------------------------------------------------
-- 11. Indstillinger: ét sted, hvor en værdi sættes
--
-- Indstillingsvinduet, slash-kommandoerne og tastaturgenvejene går alle gennem
-- Set(), så de aldrig kommer ud af trit: ændrer man noget ét sted, følger de
-- andre med.
--------------------------------------------------------------------------------

local RefreshOptions = function() end      -- erstattes i afsnit 12, når vinduet er bygget

local function Redraw() forceTick = true end
local function Resync() forceSync = true forceTick = true end

-- Hvad der skal ske, når en indstilling har fået ny værdi. Gennemsigtighed står
-- her ikke: toningen (afsnit 9) finder selv det nye mål.
local AFTER = {
    enabled  = ApplyEnabled,
    size     = ApplyLayout,
    locked   = ApplyLock,
    style    = ApplyStyle,
    shape    = function() ApplyShape() Redraw() end,
    span     = Redraw,
    pinScale = Redraw,
    edgePins = Redraw,
    terrain  = Redraw,
    rotate   = Redraw,
    route    = Resync,
    pins     = Resync,
    source   = Resync,
}

local function Set(key, value)
    local limit = LIMITS[key]
    if limit then
        value = Clamp(value, limit[1], limit[2])
        if WHOLE[key] then value = floor(value + 0.5) end
    end
    db[key] = value
    local after = AFTER[key]
    if after then after() end
    RefreshOptions()
end

local function Toggle()
    if not root then return end
    Set("enabled", not db.enabled)
end

SetSpan = function(yards)
    Set("span", yards)
end

local function Center()
    db.x, db.y = 0, 0
    ApplyLayout()
end

local function ResetAll()
    local offered = db.bindingOffered
    wipe(db)
    for key, value in pairs(DEFAULTS) do db[key] = value end
    db.bindingOffered = offered
    ApplyLayout()
    ApplyShape()
    ApplyStyle()
    ApplyLock()
    ApplyEnabled()
    RefreshOptions()
end

--------------------------------------------------------------------------------
-- 12. Indstillingsvinduet (/d2map)
--
-- Et lille vindue med afkrydsningsfelter, skydere og valg. Alt virker med det
-- samme, så man kan se automappet ændre sig, mens man trækker. Vinduet bygges
-- først, når det åbnes første gang, og bruger kun Blizzards egne skabeloner.
--------------------------------------------------------------------------------

local PANEL_WIDTH = 380
local options                  -- vinduet (nil, til det åbnes første gang)
local controls = {}            -- alt i vinduet, der skal vise en indstillings værdi
local refreshing = false       -- true, mens vinduet selv sætter værdier i sine felter

local function MakeLabel(parent, text, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    label:SetText(text)
    return label
end

-- Teksten ved siden af et afkrydsningsfelt; et klik på teksten tæller også.
local function LabelCheck(check, text, gap)
    local label = MakeLabel(check, text)
    label:SetPoint("LEFT", check, "RIGHT", gap, 0)
    if check.SetHitRectInsets and label.GetStringWidth then
        check:SetHitRectInsets(0, -(label:GetStringWidth() + gap), 0, 0)
    end
end

-- Afkrydsningsfelt for en til/fra-indstilling. inverted bruges til «Unlock»,
-- som er det modsatte af db.locked.
local function MakeCheck(parent, y, text, key, inverted)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    LabelCheck(check, text, 2)
    check:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if inverted then on = not on end
        Set(key, on)
    end)
    check.Refresh = function()
        local on = db[key] and true or false
        if inverted then on = not on end
        check:SetChecked(on)
    end
    controls[#controls + 1] = check
    return check
end

-- Skyder for et tal. describe(value) giver teksten over skyderen, fx "Opacity: 40%".
local function MakeSlider(parent, y, key, low, high, step, describe)
    local title = MakeLabel(parent, "")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, y - 17)
    slider:SetWidth(PANEL_WIDTH - 44)
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    -- Skabelonens egne tekster (titel, min, maks) bruges ikke.
    for _, name in ipairs({ "Text", "Low", "High" }) do
        local region = slider[name]
        if region and region.SetText then region:SetText("") end
    end
    slider:SetScript("OnValueChanged", function(_, value)
        if refreshing then return end
        Set(key, floor(value / step + 0.5) * step)      -- hold værdien på trinnet
    end)
    slider.Refresh = function()
        slider:SetValue(db[key])
        title:SetText(describe(db[key]))
    end
    controls[#controls + 1] = slider
    return slider
end

-- En række med ét valg blandt flere (som radioknapper): choices er en liste af
-- { værdi, tekst }.
local function MakeChoice(parent, y, text, key, choices)
    MakeLabel(parent, text):SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y - 5)
    local row = { buttons = {} }
    for i, choice in ipairs(choices) do
        local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        check:SetSize(22, 22)
        check:SetPoint("TOPLEFT", parent, "TOPLEFT", 78 + (i - 1) * 98, y)
        LabelCheck(check, choice[2], 0)
        check:SetScript("OnClick", function() Set(key, choice[1]) end)
        row.buttons[i] = check
    end
    row.Refresh = function()
        for i, choice in ipairs(choices) do
            row.buttons[i]:SetChecked(db[key] == choice[1])
        end
    end
    controls[#controls + 1] = row
    return row
end

local function MakeButton(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function CreateOptions()
    local frame = CreateFrame("Frame", "D2MapOptions", UIParent, "BasicFrameTemplateWithInset")
    frame:SetFrameStrata("DIALOG")
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    -- Til højre for midten, så vinduet ikke dækker automappet, mens man indstiller.
    frame:SetPoint("CENTER", UIParent, "CENTER", 440, 0)
    if frame.TitleText then frame.TitleText:SetText("D2Map") end
    -- Escape lukker vinduet, som Blizzards egne vinduer.
    if UISpecialFrames then table.insert(UISpecialFrames, "D2MapOptions") end

    -- Rækkerne lægges oppefra; Row(højde) giver næste rækkes y og rykker ned.
    local y = -34
    local function Row(height)
        local at = y
        y = y - height
        return at
    end

    local byKey = {}           -- indstilling → felt (bruges af testen og til fejlfinding)

    byKey.enabled = MakeCheck(frame, Row(26), "Show automap", "enabled")
    byKey.opacity = MakeSlider(frame, Row(42), "opacity", 0, 100, 1, function(v)
        return ("Opacity: %d%%"):format(v)
    end)
    byKey.combatFade = MakeCheck(frame, Row(26), "Fade in combat", "combatFade")
    byKey.combatOpacity = MakeSlider(frame, Row(42), "combatOpacity", 0, 100, 1, function(v)
        return ("Opacity in combat: %d%%"):format(v)
    end)
    byKey.span = MakeSlider(frame, Row(42), "span", LIMITS.span[1], LIMITS.span[2], 50, function(v)
        return ("Zoom: %d yards across"):format(v)
    end)
    byKey.size = MakeSlider(frame, Row(46), "size", LIMITS.size[1], LIMITS.size[2], 20, function(v)
        return ("Size: %d pixels"):format(v)
    end)

    byKey.rotate = MakeCheck(frame, Row(30), "Rotate map to the way I'm facing", "rotate")

    byKey.pins = MakeChoice(frame, Row(28), "Pins", "pins", {
        { "all", "All" }, { "objectives", "Objectives" }, { "off", "Off" },
    })
    byKey.pinScale = MakeSlider(frame, Row(42), "pinScale", LIMITS.pinScale[1], LIMITS.pinScale[2], 0.1, function(v)
        return ("Pin size: %.1fx"):format(v)
    end)
    byKey.edgePins = MakeCheck(frame, Row(26), "Show nearest off-map objective on the rim", "edgePins")
    byKey.route = MakeCheck(frame, Row(30), "Outline each cluster of objectives", "route")

    byKey.terrain = MakeCheck(frame, Row(26), "Show terrain (minimap tiles)", "terrain")
    byKey.style = MakeChoice(frame, Row(26), "Look", "style", {
        { "color", "Color" }, { "sepia", "Sepia" }, { "ghost", "Ghost" },
    })
    byKey.shape = MakeChoice(frame, Row(30), "Shape", "shape", {
        { "round", "Round" }, { "square", "Square" }, { "plain", "Plain" },
    })

    byKey.locked = MakeCheck(frame, Row(30), "Unlock to move (drag the map, wheel zooms)", "locked", true)

    local center = MakeButton(frame, "Center map", 110, Center)
    center:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, Row(30))
    local reset = MakeButton(frame, "Reset all", 110, ResetAll)
    reset:SetPoint("LEFT", center, "RIGHT", 8, 0)

    -- Hvilken tast åbner og lukker automappet lige nu?
    local hint = MakeLabel(frame, "", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, Row(18))
    controls[#controls + 1] = { Refresh = function()
        local key = GetBindingKey and GetBindingKey("D2MAP_TOGGLE")
        hint:SetText(key and ("Toggle key: " .. key .. "  (Key Bindings > D2Map)")
            or "No toggle key set  (Key Bindings > D2Map)")
    end }

    frame:SetSize(PANEL_WIDTH, -y + 12)
    frame.controls = byKey
    frame:SetScript("OnShow", RefreshOptions)
    frame:Hide()
    return frame
end

-- Sætter alle felter efter de gemte indstillinger. Kaldes, når vinduet åbnes,
-- og hver gang Set() har ændret noget, mens det er åbent.
RefreshOptions = function()
    if not options or not options:IsShown() then return end
    refreshing = true
    for _, control in ipairs(controls) do control.Refresh() end
    refreshing = false
end

local function ToggleOptions()
    if not root then return end
    if not options then options = CreateOptions() end
    if options:IsShown() then
        options:Hide()
    else
        options:Show()
    end
end

--------------------------------------------------------------------------------
-- 13. Offentlig API, tastaturgenveje og slash-kommandoer
--------------------------------------------------------------------------------

-- Globale navne: bruges af Bindings.xml og af andre addons.
D2Map = {
    Toggle = Toggle,
    ToggleOptions = ToggleOptions,
    RegisterAdapter = RegisterAdapter,
    EmitPin = EmitPin,
}

function D2Map_Toggle()
    Toggle()
end

-- direction > 0 zoomer ind (færre yards i rammen), < 0 zoomer ud.
function D2Map_Zoom(direction)
    if not root then return end
    SetSpan(db.span * (direction > 0 and 0.8 or 1.25))
end

-- Teksterne i spillets Key Bindings-menu (Bindings.xml har selve bindingerne).
BINDING_HEADER_D2MAP = "D2Map"
BINDING_NAME_D2MAP_TOGGLE = "Toggle automap"
BINDING_NAME_D2MAP_ZOOMIN = "Zoom automap in"
BINDING_NAME_D2MAP_ZOOMOUT = "Zoom automap out"

-- Binder en tast til toggle og gemmer det, som spillets egen menu ville gøre.
local function BindToggle(key)
    if not (SetBinding and SaveBindings and GetCurrentBindingSet) then return false end
    local ok, set = pcall(SetBinding, key, "D2MAP_TOGGLE")
    if not (ok and set) then return false end
    pcall(SaveBindings, GetCurrentBindingSet())
    RefreshOptions()
    return true
end

-- Findes den handling, en tast peger på, stadig? En tast kan blive hængende på
-- en addon, der er slået fra eller slettet (fx "DandyMap_AUTOMAP"); så gør den
-- ingenting, og vi må gerne bruge den.
local function BindingCommandExists(command)
    if type(command) ~= "string" then return true end
    -- Klik, spells, makroer og ting er gyldige uden at stå på listen.
    if command:find("^CLICK ") or command:find("^SPELL ") or command:find("^MACRO ") or command:find("^ITEM ") then
        return true
    end
    if not (GetNumBindings and GetBinding) then return true end      -- kan ikke afgøres: regn den for i brug
    for i = 1, GetNumBindings() do
        if GetBinding(i) == command then return true end
    end
    return false
end

-- Lægger Alt+M på toggle første gang – men kun hvis tasten er ledig (eller
-- peger på en addon, der ikke findes længere), og aldrig igen, så et fravalg i
-- menuen bliver respekteret.
local function OfferDefaultBinding()
    if db.bindingOffered or not (SetBinding and GetBindingKey and GetBindingAction) then return end
    if InCombatLockdown and InCombatLockdown() then return end       -- prøv igen næste gang
    db.bindingOffered = true
    if GetBindingKey("D2MAP_TOGGLE") then return end
    local current = GetBindingAction("ALT-M")
    if current and current ~= "" and BindingCommandExists(current) then
        -- Tasten er optaget (fx af et andet automap): tag den ikke, men sig det.
        Print("Alt+M is already bound to " .. tostring(current)
            .. ". Type /d2map bind to take it over, or pick a key under Key Bindings > D2Map.")
        return
    end
    if BindToggle("ALT-M") then
        Print("Alt+M toggles the automap (change it under Key Bindings > D2Map).")
    end
end

-- "40", "40%" og "40 %" er alle 40.
local function ParseNumber(text)
    return tonumber((text:gsub("%%", ""):gsub("%s+", "")))
end

local function OnOff(value)
    return value and "on" or "off"
end

local function PrintHelp()
    Print("/d2map opens the options window. The same settings as commands:")
    local lines = {
        "/d2map toggle – show or hide the automap (also: on, off)",
        "/d2map opacity <0-100> – opacity out of combat (now " .. db.opacity .. ")",
        "/d2map combat <0-100|on|off> – opacity in combat (now " .. db.combatOpacity .. ", fade " .. OnOff(db.combatFade) .. ")",
        "/d2map zoom <yards|in|out> – yards across the frame (now " .. db.span .. ")",
        "/d2map size <pixels> – frame size (now " .. db.size .. ")",
        "/d2map shape <round|square|plain> – edge mask (now " .. db.shape .. ")",
        "/d2map style <color|sepia|ghost> – terrain look (now " .. db.style .. ")",
        "/d2map pins <all|objectives|off> – which quest pins (now " .. db.pins .. ")",
        "/d2map pinsize <0.5-3> – pin scale (now " .. db.pinScale .. ")",
        "/d2map edge <on|off> – nearest off-map objective on the rim (now " .. OnOff(db.edgePins) .. ")",
        "/d2map outlines <on|off> – a soft outline around each cluster of objectives (now " .. OnOff(db.route) .. ")",
        "/d2map rotate <on|off> – turn the map to the way you face (now " .. OnOff(db.rotate) .. ")",
        "/d2map terrain <on|off> – minimap tiles (now " .. OnOff(db.terrain) .. ")",
        "/d2map source <auto|questie|blizzard> – where pins come from (now " .. db.source .. ")",
        "/d2map bind [key] – put a key on toggle (Alt+M if none given)",
        "/d2map unlock / lock – move the frame with the mouse; locked is click-through",
        "/d2map center – back to the middle of the screen",
        "/d2map status – what the automap is showing right now",
        "/d2map reset – all settings back to defaults",
    }
    for _, line in ipairs(lines) do
        DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
    end
end

local function PrintStatus()
    local continent, north, west = PlayerPosition()
    Print(("%s, opacity %d%% (combat %d%%, fade %s), %d yards across %d px, shape %s, style %s"):format(
        db.enabled and "shown" or "hidden", db.opacity, db.combatOpacity, OnOff(db.combatFade),
        db.span, db.size, db.shape, db.style))
    if continent then
        Print(("position: continent %d, %.0f north, %.0f west; terrain %s, %d tiles%s"):format(
            continent, north, west, OnOff(db.terrain), tilesShown,
            (ns.Tiles and ns.Tiles[continent]) and "" or " (no tile data for this continent)"))
    else
        Print("position: not available here (instances hide it from addons)")
    end
    Print(("pins: %s, source %s, %d known, %d drawn%s"):format(
        db.pins, activeAdapterName, recordCount, pinsShown, mask and "" or "; no mask support, using hard edges"))
    Print(("outlines: %s, %d clusters (objectives within %d yards belong together), %d line pieces drawn; map %s"):format(
        OnOff(db.route), loopCount, loopLink, loopLinesShown, db.rotate and "rotates with you" or "north up"))
    if tickFailed then Print("the update loop is stopped after an error – /d2map toggle twice to retry.") end
end

-- Sætter et tal fra en kommando, hvis det er gyldigt. Returnerer true, når det lykkedes.
local function SetNumber(key, text, label)
    local value = ParseNumber(text)
    local limit = LIMITS[key]
    if not value then
        Print(("usage: /d2map %s <%s-%s>"):format(label, tostring(limit[1]), tostring(limit[2])))
        return false
    end
    Set(key, value)
    Print(("%s set to %s"):format(label, tostring(db[key])))
    return true
end

-- Sætter et valg blandt faste ord (shape, style …).
local function SetChoice(key, text, choices, label)
    if not choices[text] then
        local names = {}
        for name in pairs(choices) do names[#names + 1] = name end
        table.sort(names)
        Print(("usage: /d2map %s <%s>"):format(label, table.concat(names, "|")))
        return false
    end
    Set(key, text)
    Print(("%s set to %s"):format(label, text))
    return true
end

-- on, off eller ingenting (= skift).
local function SetFlag(key, text, label)
    local value
    if text == "on" then
        value = true
    elseif text == "off" then
        value = false
    elseif text == "" then
        value = not db[key]
    else
        Print(("usage: /d2map %s <on|off>"):format(label))
        return false
    end
    Set(key, value)
    Print(("%s %s"):format(label, OnOff(db[key])))
    return true
end

local commands = {}

commands.options = ToggleOptions
commands.config = ToggleOptions

commands.toggle = function() Toggle() end
commands.on = function() Set("enabled", true) end
commands.off = function() Set("enabled", false) end
commands.show = commands.on
commands.hide = commands.off

commands.opacity = function(rest) SetNumber("opacity", rest, "opacity") end
commands.alpha = commands.opacity

commands.combat = function(rest)
    if rest == "on" or rest == "off" then
        SetFlag("combatFade", rest, "combat fade")
    else
        SetNumber("combatOpacity", rest, "combat")
    end
end

commands.zoom = function(rest)
    if rest == "in" or rest == "out" then
        SetSpan(db.span * (rest == "in" and 0.8 or 1.25))
        Print("zoom set to " .. db.span .. " yards")
    else
        SetNumber("span", rest, "zoom")
    end
end

commands.size = function(rest) SetNumber("size", rest, "size") end
commands.shape = function(rest) SetChoice("shape", rest, SHAPES, "shape") end
commands.style = function(rest) SetChoice("style", rest, STYLES, "style") end
commands.pins = function(rest) SetChoice("pins", rest, PIN_MODES, "pins") end
commands.pinsize = function(rest) SetNumber("pinScale", rest, "pinsize") end
commands.edge = function(rest) SetFlag("edgePins", rest, "edge pins") end
commands.terrain = function(rest) SetFlag("terrain", rest, "terrain") end
commands.route = function(rest) SetFlag("route", rest, "outlines") end
commands.outlines = commands.route
commands.rotate = function(rest) SetFlag("rotate", rest, "rotate") end
commands.source = function(rest) SetChoice("source", rest, SOURCES, "source") end

commands.unlock = function()
    Set("locked", false)
    Print("unlocked: drag to move, mouse wheel to zoom. /d2map lock makes it click-through again.")
end

commands.lock = function()
    Set("locked", true)
    Print("locked: mouse clicks pass straight through.")
end

commands.center = function()
    Center()
    Print("centered.")
end

-- /d2map bind [tast]: læg en tast (Alt+M, hvis ingen nævnes) på toggle, også
-- selvom den er i brug af noget andet. Brugeren har selv bedt om det.
commands.bind = function(rest)
    local key = rest ~= "" and rest:upper() or "ALT-M"
    if InCombatLockdown and InCombatLockdown() then
        Print("key bindings can't be changed in combat.")
    elseif BindToggle(key) then
        db.bindingOffered = true
        Print(key .. " now toggles the automap.")
    else
        Print("could not bind " .. key .. " – use Key Bindings > D2Map instead.")
    end
end

commands.status = PrintStatus

commands.reset = function()
    ResetAll()
    Print("all settings reset.")
end

commands.help = PrintHelp

-- /d2map uden noget efter åbner indstillingsvinduet; med et ord er det en kommando.
local function SlashHandler(message)
    if not db or not root then return end
    local command, rest = (message or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "" then
        ToggleOptions()
        return
    end
    local handler = commands[command]
    if handler then
        handler(rest)
    else
        Print("unknown command '" .. command .. "'.")
        PrintHelp()
    end
end

SLASH_D2MAP1 = "/d2map"
SLASH_D2MAP2 = "/automap"
SlashCmdList["D2MAP"] = SlashHandler

--------------------------------------------------------------------------------
-- 14. Events
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")

local handlers = {}

local function LoadSettings()
    if type(D2MapDB) ~= "table" then D2MapDB = {} end
    db = D2MapDB
    MigrateSettings()
    ValidateSettings()
end

-- Gemte indstillinger er klar: fyld defaults ud.
function handlers.ADDON_LOADED(name)
    if name ~= ADDON then return end
    events:UnregisterEvent("ADDON_LOADED")
    LoadSettings()
end

-- UIParent har sin endelige størrelse: byg rammerne.
function handlers.PLAYER_LOGIN()
    if not db then LoadSettings() end
    inCombat = InCombatLockdown ~= nil and InCombatLockdown() == true
    CreateFrames()
    root:SetScript("OnUpdate", OnUpdate)
    ApplyEnabled()
end

-- Efter hver loading screen: hent pins forfra, og tilbyd Alt+M én gang.
function handlers.PLAYER_ENTERING_WORLD()
    forceSync = true
    forceTick = true
    hasPosition = nil
    if C_Timer and C_Timer.After then
        C_Timer.After(3, OfferDefaultBinding)
    else
        OfferDefaultBinding()
    end
end

-- Combat begynder: ton ned, så automappet ikke dækker for kampen.
function handlers.PLAYER_REGEN_DISABLED()
    inCombat = true
end

-- Combat slut: tilbage til normal gennemsigtighed.
function handlers.PLAYER_REGEN_ENABLED()
    inCombat = false
end

-- Ny zone: Questie tegner sine ikoner om, så hent dem straks.
function handlers.ZONE_CHANGED_NEW_AREA()
    forceSync = true
end

events:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then handler(...) end
end)

for event in pairs(handlers) do
    events:RegisterEvent(event)
end
