-- Kører D2Map uden for spillet mod en lille attrap af WoW's API.
--
--   lua test/koer.lua          (fra projektets rod)
--
-- Attrappen kender KUN de metoder, D2Map må bruge. Kalder koden noget andet,
-- vælter testen – det fanger stavefejl i API-navne. Det, testen ikke kan vise,
-- er hvordan det ser ud i spillet: masker, fliser og farver er Blizzards.

local fejl, antal = 0, 0
local function tjek(navn, betingelse, detalje)
    antal = antal + 1
    if betingelse then
        print("  ok   " .. navn)
    else
        fejl = fejl + 1
        print("  FEJL " .. navn .. (detalje and ("  → " .. tostring(detalje)) or ""))
    end
end
local function taet(a, b, tolerance)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (tolerance or 0.01)
end

--------------------------------------------------------------------------------
-- Attrap: widgets
--------------------------------------------------------------------------------

local Widget = {}
Widget.__index = Widget

local function NyWidget(slags, foraelder)
    return setmetatable({ slags = slags, foraelder = foraelder, born = {}, punkter = {},
        scripts = {}, synlig = true, alfa = 1, niveau = 0 }, Widget)
end

local function tom() end
for _, navn in ipairs({
    "SetFrameStrata", "SetMovable", "SetClampedToScreen", "SetClipsChildren", "RegisterForDrag",
    "SetAllPoints", "SetMouseClickEnabled", "SetMouseMotionEnabled", "EnableMouseWheel",
    "ClearAllPoints", "StartMoving", "StopMovingOrSizing", "RegisterEvent", "UnregisterEvent",
    "SetAtlas", "SetColorTexture", "SetWidth", "SetHeight", "SetDesaturated", "SetBlendMode",
    "SetSnapToPixelGrid", "SetTexelSnappingBias", "SetDrawLayer",
    "SetToplevel", "SetMinMaxValues", "SetValueStep", "SetObeyStepOnDrag", "SetThickness",
}) do
    Widget[navn] = tom
end

function Widget:SetFrameLevel(n) self.niveau = n end
function Widget:GetFrameLevel() return self.niveau end
function Widget:SetScript(navn, fn) self.scripts[navn] = fn end
function Widget:EnableMouse(til) self.mus = til end
function Widget:SetSize(b, h) self.bredde, self.hoejde = b, h end
function Widget:SetPoint(punkt, rel, relPunkt, x, y) self.punkter[punkt] = { rel = rel, relPunkt = relPunkt, x = x, y = y } end
function Widget:GetCenter() return 800, 450 end
function Widget:Show()
    local var = self.synlig
    self.synlig = true
    if not var and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Widget:Hide() self.synlig = false end
function Widget:IsShown() return self.synlig end
function Widget:SetText(t) self.tekst = t end
function Widget:GetStringWidth() return 6 * #(self.tekst or "") end
function Widget:SetHitRectInsets(v, h) self.klikbredde = -h end
function Widget:SetChecked(til) self.afkrydset = til and true or false end
function Widget:GetChecked() return self.afkrydset end
function Widget:GetValue() return self.vaerdi end
-- Som i spillet: at sætte en skyders værdi fyrer OnValueChanged.
function Widget:SetValue(v)
    self.vaerdi = v
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
end
-- Et klik på et afkrydsningsfelt: skift fluebenet og kør OnClick, som spillet gør.
function Widget:Klik()
    if self.slags == "CheckButton" then self.afkrydset = not self.afkrydset end
    self.scripts.OnClick(self)
end
function Widget:SetAlpha(a) self.alfa = a end
function Widget:SetTexture(t, ...) self.tekstur = t end
function Widget:GetTexture() return self.tekstur end
function Widget:SetVertexColor(r, g, b, a) self.farve = { r, g, b, a } end
function Widget:SetRotation(r) self.rotation = r end
function Widget:AddMaskTexture(m) self.maske = m end
function Widget:RemoveMaskTexture() self.maske = nil end
local function barn(slags)
    return function(self)
        local w = NyWidget(slags, self)
        self.born[#self.born + 1] = w
        return w
    end
end
Widget.CreateTexture = barn("Texture")
Widget.CreateMaskTexture = barn("MaskTexture")
Widget.CreateFontString = barn("FontString")
Widget.CreateLine = barn("Line")
function Widget:SetStartPoint(punkt, rel, x, y) self.fra = { x = x, y = y } end
function Widget:SetEndPoint(punkt, rel, x, y) self.til = { x = x, y = y } end

local rammer = {}
UIParent = NyWidget("Frame")
UISpecialFrames = {}
-- Kun de skabeloner, andre Forever-addons bruger i dag (set i ForeverDualGathering,
-- OneForAll og OpenMap). En ukendt skabelon vælter testen.
local SKABELONER = {
    BasicFrameTemplateWithInset = function(w) w.TitleText = NyWidget("FontString", w) w.CloseButton = NyWidget("Button", w) end,
    OptionsSliderTemplate = function(w) w.Text, w.Low, w.High = NyWidget("FontString", w), NyWidget("FontString", w), NyWidget("FontString", w) end,
    UICheckButtonTemplate = function() end,
    UIPanelButtonTemplate = function() end,
}
function CreateFrame(slags, navn, foraelder, skabelon)
    local w = NyWidget(slags, foraelder)
    if skabelon then
        assert(SKABELONER[skabelon], "ukendt skabelon: " .. tostring(skabelon))(w)
        w.skabelon = skabelon
    end
    if navn then _G[navn] = w end
    rammer[#rammer + 1] = w
    return w
end

--------------------------------------------------------------------------------
-- Attrap: spillets funktioner
--------------------------------------------------------------------------------

local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, tekst) chat[#chat + 1] = tekst end }
SlashCmdList = {}

local HEMMELIG = {}                                   -- står for en «secret value»
function issecretvalue(v) return v == HEMMELIG end

-- Spilleren: midt i Elwynn Forest på Eastern Kingdoms (kontinent 0).
local spiller = { kontinent = 0, nord = -9000, vest = -100, retning = 1.25, hemmelig = false, ingen = false }
function UnitPosition()
    if spiller.ingen then return nil end
    if spiller.hemmelig then return HEMMELIG, HEMMELIG, HEMMELIG, HEMMELIG end
    return spiller.nord, spiller.vest, 0, spiller.kontinent
end
function GetPlayerFacing() return spiller.retning end

local kamp = false
function InCombatLockdown() return kamp end

-- Ét zonekort: Elwynn Forest (uiMapID 1429) med sine rigtige hjørner i yards.
local ZONE = { id = 1429, kontinent = 0, top = -7939.58, venstre = 1535.42, bredde = 3470.84, hoejde = 2314.59 }
function CreateVector2D(x, y) return { x = x, y = y } end
C_Map = {
    GetBestMapForUnit = function() return ZONE.id end,
    GetPlayerMapPosition = function(kort)
        if spiller.ingen or kort ~= ZONE.id then return nil end
        return CreateVector2D((ZONE.venstre - spiller.vest) / ZONE.bredde, (ZONE.top - spiller.nord) / ZONE.hoejde)
    end,
    GetWorldPosFromMapPos = function(kort, pos)
        if kort ~= ZONE.id then return 1, CreateVector2D(0, 0) end      -- et andet kontinent
        return ZONE.kontinent, CreateVector2D(ZONE.top - pos.y * ZONE.hoejde, ZONE.venstre - pos.x * ZONE.bredde)
    end,
}
-- Zone-procenter for et punkt et antal yards nord og øst for spilleren.
local function zonePunkt(nord, oest)
    local x = (ZONE.venstre - (spiller.vest - oest)) / ZONE.bredde * 100
    local y = (ZONE.top - (spiller.nord + nord)) / ZONE.hoejde * 100
    return x, y
end

C_Timer = { After = function(_, fn) fn() end }
local ur = 1000                                        -- spillets ur i sekunder
function GetTime() return ur end
C_Texture = { GetAtlasInfo = function() return nil end }

local bindinger = {}
function GetBindingKey(navn) for tast, n in pairs(bindinger) do if n == navn then return tast end end end
function GetBindingAction(tast) return bindinger[tast] or "" end
function SetBinding(tast, navn) bindinger[tast] = navn return true end
function GetCurrentBindingSet() return 1 end
-- De handlinger, spillet kender lige nu (indbyggede + indlæste addons).
local kendteHandlinger = { "TOGGLEWORLDMAP", "D2MAP_TOGGLE", "D2MAP_ZOOMIN", "D2MAP_ZOOMOUT" }
function GetNumBindings() return #kendteHandlinger end
function GetBinding(i) return kendteHandlinger[i], "kategori" end
local gemtBindinger = 0
function SaveBindings() gemtBindinger = gemtBindinger + 1 end

-- Questie: et register med ikon-rammer, som den rigtige addon har det.
Questie = { usedIcons = { [1] = "slay.blp", [2] = "complete.blp", [3] = "available.blp" } }
local register = {}
local pinsLib = { worldmapPinRegistry = { [Questie] = register } }
function LibStub(navn)
    if navn == "HereBeDragonsQuestie-Pins-2.0" then return pinsLib end
    return nil
end
local function questieIkon(type, quest, nord, oest, ekstra)
    local x, y = zonePunkt(nord, oest)
    local ikon = { x = x, y = y, UiMapID = ZONE.id, data = { Type = type, Id = quest, Icon = 1 },
        texture = { r = 0.2, g = 0.9, b = 0.4, GetTexture = function() return "questie-" .. type end } }
    for k, v in pairs(ekstra or {}) do ikon[k] = v end
    register[ikon] = true
    return ikon
end

C_QuestLog = {
    GetQuestsOnMap = function() return { { questID = 77, x = 0.5, y = 0.5 } } end,
    IsComplete = function() return false end,
}

--------------------------------------------------------------------------------
-- Indlæs addon'en, som spillet gør
--------------------------------------------------------------------------------

local ns = {}
assert(loadfile("D2Map/Data/MinimapTiles.lua"))("D2Map", ns)
assert(loadfile("D2Map/D2Map.lua"))("D2Map", ns)

local haendelser = rammer[#rammer]                     -- event-rammen oprettes sidst i filen
local function fyr(navn, ...) haendelser.scripts.OnEvent(haendelser, navn, ...) end

print("Opstart")
fyr("ADDON_LOADED", "EnAndenAddon")
tjek("andre addons' ADDON_LOADED rører ikke indstillingerne", D2MapDB == nil)
fyr("ADDON_LOADED", "D2Map")
tjek("defaults fyldes ud", D2MapDB.opacity == 40 and D2MapDB.combatOpacity == 18 and D2MapDB.enabled == true)
tjek("terræn er slået fra som standard", D2MapDB.terrain == false)
fyr("PLAYER_LOGIN")
fyr("PLAYER_ENTERING_WORLD")

local root = D2MapFrame
local canvas, pinLayer, mover
for _, r in ipairs(rammer) do
    if r.foraelder == root then
        if not canvas then canvas = r elseif not pinLayer then pinLayer = r else mover = r end
    end
end
tjek("rammen findes og er centreret", root and root.punkter.CENTER and root.punkter.CENTER.rel == UIParent
    and root.punkter.CENTER.x == 0 and root.punkter.CENTER.y == 0)
tjek("click-through som standard (EnableMouse(false))", root.mus == false and canvas.mus == false and pinLayer.mus == false)
tjek("Alt+M lagt på toggle og gemt", bindinger["ALT-M"] == "D2MAP_TOGGLE" and gemtBindinger == 1)
tjek("genvejen tilbydes kun én gang", D2MapDB.bindingOffered == true)

local function kor(sekunder, skridt)
    skridt = skridt or 0.02
    for _ = 1, math.floor(sekunder / skridt + 0.5) do root.scripts.OnUpdate(root, skridt) end
end
local function fliser()
    local t = {}
    for _, b in ipairs(canvas.born) do if b.slags == "Texture" and b.synlig and b.shown then t[#t + 1] = b end end
    return t
end
local function pins()
    local t = {}
    for _, b in ipairs(pinLayer.born) do if b.slags == "Texture" and b.shown then t[#t + 1] = b end end
    return t
end
local function linjer()
    local t = {}
    for _, b in ipairs(pinLayer.born) do if b.slags == "Line" and b.shown then t[#t + 1] = b end end
    return t
end
-- Rutens stop som tekst, fx "-67,-45 56,112" (skærmkoordinater, afrundet).
local function rute()
    local dele = {}
    for _, l in ipairs(linjer()) do dele[#dele + 1] = ("%d,%d"):format(math.floor(l.til.x + 0.5), math.floor(l.til.y + 0.5)) end
    return table.concat(dele, " ")
end
local function pinVed(x, y)
    for _, p in ipairs(pins()) do
        if taet(p.punkter.CENTER.x, x, 0.05) and taet(p.punkter.CENTER.y, y, 0.05) then return p end
    end
end

print("Terræn")
kor(0.3)
tjek("uden terræn tegnes ingen fliser, men pilen er der", #fliser() == 0 and pinLayer.synlig == true)
SlashCmdList.D2MAP("terrain on")
kor(0.3)
local f = fliser()
tjek("fliser tegnes omkring spilleren", #f >= 1 and #f <= 4, #f)
-- Spilleren står i flise (32, 48): cx = 32 + 100/533,33, cy = 32 + 9000/533,33
local tilePx = (1600 / 3) * 560 / 500
local cx, cy = 32 + 100 / (1600 / 3), 32 + 9000 / (1600 / 3)
local egen
for _, t in ipairs(f) do if t.tekstur == ns.Tiles[0][32 * 64 + 48] then egen = t end end
tjek("spillerens egen flise har det rigtige fil-id", egen ~= nil)
tjek("flisen ligger rigtigt i forhold til spilleren", egen and taet(egen.punkter.CENTER.x, (32.5 - cx) * tilePx)
    and taet(egen.punkter.CENTER.y, -(48.5 - cy) * tilePx), egen and (egen.punkter.CENTER.x .. ", " .. egen.punkter.CENTER.y))
tjek("uden rotation er flisen ikke drejet", egen and egen.rotation == 0)
tjek("flisen har den rigtige størrelse", egen and taet(egen.bredde, tilePx))
tjek("fliserne er maskeret (bløde kanter)", egen and egen.maske ~= nil and egen.maske.tekstur:find("mask%-round"))
tjek("spillerens pil drejer med figuren", pinLayer.born[1].rotation == 1.25)

print("Questie-pins")
questieIkon("monster", 1, 100, 50)                    -- 100 yards nord, 50 øst
questieIkon("monster", 1, -40, -60)                   -- samme quest, sydvest
questieIkon("monster", 2, 0, 1000)                    -- quest 2: langt mod øst (uden for rammen)
questieIkon("monster", 2, 0, 1500)                    -- quest 2: endnu længere væk
questieIkon("monster", 1, 900, 0)                     -- quest 1 langt væk: ingen kant-pin, den har pins inde
questieIkon("complete", 3, 30, 0)                     -- aflevering
questieIkon("available", 4, 0, -30)                   -- ny quest
questieIkon("monster", 5, 10, 10, { hidden = true })  -- skjult af Questies filtre
questieIkon("monster", 6, 20, 20, { UiMapID = 9999 }) -- på et andet kontinent
kor(1.2)
local px = 560 / 500
tjek("pin 100 nord / 50 øst står oppe til højre", pinVed(50 * px, 100 * px) ~= nil)
tjek("pin 40 syd / 60 vest står nede til venstre", pinVed(-60 * px, -40 * px) ~= nil)
local p = pinVed(50 * px, 100 * px)
tjek("pin bruger Questies billede og farve", p and p.tekstur == "questie-monster" and p.farve[1] == 0.2 and p.farve[2] == 0.9)
tjek("aflevering og ny quest vises", pinVed(0, 30 * px) ~= nil and pinVed(-30 * px, 0) ~= nil)
tjek("skjult ikon vises ikke", pinVed(10 * px, 10 * px) == nil)
tjek("ikon på et andet kontinent vises ikke", pinVed(20 * px, 20 * px) == nil)
local kant = pinVed(280 * 0.90, 0)
tjek("quest uden pins i rammen får én pin på kanten", kant ~= nil)
tjek("kant-pinnen er mindre og svagere", kant and taet(kant.bredde, 16 * 0.75) and kant.farve[4] == 0.75)
-- 4 inden for rammen (to mobs, aflevering, ny quest) + 1 på kanten for quest 2
tjek("kun den nærmeste pin pr. quest på kanten (5 pins i alt)", #pins() == 5, #pins())

print("Rute gennem målene")
-- To mål i rammen (quest 1): det nærmeste først. Aflevering, ny quest, skjulte og fjerne er ikke med.
tjek("ruten går til det nærmeste mål først og så videre", rute() == "-67,-45 56,112", rute())
local l = linjer()
tjek("første stykke begynder ved spilleren", l[1].fra.x == 0 and l[1].fra.y == 0)
tjek("næste stykke begynder, hvor det forrige slutter", l[2].fra.x == l[1].til.x and l[2].fra.y == l[1].til.y)

print("Flydende opdatering")
spiller.nord = spiller.nord + 10                      -- gå 10 yards mod nord
kor(0.12)
tjek("pins flytter sig med spilleren inden for 0,1 sek.", pinVed(50 * px, 90 * px) ~= nil)
tjek("ruten flytter sig med", linjer()[2].til.y == 90 * px)
spiller.nord = spiller.nord - 10
kor(0.12)

print("Gennemsigtighed og combat")
tjek("terræn 40 %, pins dobbelt så synlige", taet(canvas.alfa, 0.40) and taet(pinLayer.alfa, 0.80))
fyr("PLAYER_REGEN_DISABLED")
kor(0.1)
tjek("toningen er i gang efter 0,1 sek.", canvas.alfa < 0.40 and canvas.alfa > 0.18, canvas.alfa)
kor(1)
tjek("i combat: 18 %", taet(canvas.alfa, 0.18) and taet(pinLayer.alfa, 0.36), canvas.alfa)
fyr("PLAYER_REGEN_ENABLED")
kor(1)
tjek("efter combat: tilbage på 40 %", taet(canvas.alfa, 0.40), canvas.alfa)

print("Slash-kommandoer")
local slash = SlashCmdList.D2MAP
tjek("/d2map er registreret", SLASH_D2MAP1 == "/d2map" and type(slash) == "function")
slash("opacity 55")
kor(1)
tjek("/d2map opacity 55", D2MapDB.opacity == 55 and taet(canvas.alfa, 0.55))
slash("opacity 250%")
tjek("opacity holdes inden for 0-100", D2MapDB.opacity == 100)
slash("opacity abc")
tjek("ugyldigt tal ændrer ingenting", D2MapDB.opacity == 100)
slash("opacity 40")
slash("combat 15")
tjek("/d2map combat 15", D2MapDB.combatOpacity == 15)
slash("toggle")
tjek("/d2map toggle skjuler", root.synlig == false and D2MapDB.enabled == false)
slash("TOGGLE")
tjek("/d2map toggle viser igen (store bogstaver er ok)", root.synlig == true and D2MapDB.enabled == true)
D2Map_Toggle()
D2Map_Toggle()
tjek("genvejens funktion D2Map_Toggle virker", root.synlig == true)
slash("zoom 1000")
kor(0.2)
tjek("/d2map zoom 1000 giver flere, mindre fliser", D2MapDB.span == 1000 and #fliser() >= 4 and taet(fliser()[1].bredde, tilePx / 2), #fliser())
tjek("pins følger zoomet", pinVed(50 * 0.56, 100 * 0.56) ~= nil)
D2Map_Zoom(1)
tjek("zoom ind-genvejen", D2MapDB.span == 800)
slash("zoom 500")
slash("size 700")
tjek("/d2map size 700", D2MapDB.size == 700 and root.bredde == 700)
slash("size 560")
slash("shape square")
kor(0.2)
tjek("/d2map shape square skifter maske", fliser()[1].maske.tekstur:find("mask%-square") ~= nil)
slash("shape plain")
tjek("/d2map shape plain fjerner masken", fliser()[1].maske == nil)
slash("shape round")
slash("style ghost")
tjek("/d2map style ghost", D2MapDB.style == "ghost")
slash("style color")
slash("pins objectives")
kor(1.2)
tjek("/d2map pins objectives skjuler nye quests", pinVed(-30 * px, 0) == nil and pinVed(50 * px, 100 * px) ~= nil)
slash("pins off")
kor(0.2)
tjek("/d2map pins off", #pins() == 0)
slash("pins all")
slash("edge off")
kor(1.2)
tjek("/d2map edge off fjerner kant-pins", pinVed(280 * 0.90, 0) == nil and #pins() == 4, #pins())
slash("edge on")
slash("terrain off")
kor(0.2)
tjek("/d2map terrain off", #fliser() == 0)
slash("terrain on")
slash("unlock")
tjek("/d2map unlock slår mus til og viser kanten", root.mus == true and mover.synlig == true)
slash("lock")
tjek("/d2map lock er click-through igen", root.mus == false and mover.synlig == false)
slash("noget-ukendt")
slash("status")
slash("help")
tjek("hjælp og status skriver i chatten", #chat > 20)

print("Indstillingsvinduet")
tjek("vinduet bygges først, når det åbnes", D2MapOptions == nil)
slash("")
local vindue = D2MapOptions
tjek("/d2map åbner indstillingsvinduet", vindue ~= nil and vindue.synlig == true)
tjek("Escape lukker det (UISpecialFrames)", UISpecialFrames[1] == "D2MapOptions")
tjek("teksten ved et afkrydsningsfelt kan også klikkes", vindue.controls.terrain.klikbredde > 100)
local felt = vindue.controls
tjek("felterne viser de gemte værdier", felt.enabled.afkrydset == true and felt.opacity.vaerdi == 40
    and felt.span.vaerdi == 500 and felt.terrain.afkrydset == true and felt.locked.afkrydset == false)
tjek("valget for pins står på All", felt.pins.buttons[1].afkrydset == true and felt.pins.buttons[2].afkrydset == false)
felt.opacity:SetValue(70)
kor(1)
tjek("skyderen sætter opacity og virker med det samme", D2MapDB.opacity == 70 and taet(canvas.alfa, 0.70))
felt.span:SetValue(770)
tjek("zoom-skyderen holder sig til trin på 50", D2MapDB.span == 750 or D2MapDB.span == 800, D2MapDB.span)
felt.pinScale:SetValue(1.5)
tjek("pin-skyderen", taet(D2MapDB.pinScale, 1.5))
felt.terrain:Klik()
kor(0.2)
tjek("afkrydsning slår terrænet fra", D2MapDB.terrain == false and #fliser() == 0)
felt.terrain:Klik()
felt.pins.buttons[2]:Klik()
tjek("valg af Objectives", D2MapDB.pins == "objectives" and felt.pins.buttons[2].afkrydset == true
    and felt.pins.buttons[1].afkrydset == false)
felt.pins.buttons[2]:Klik()
tjek("klik på det valgte igen ændrer ingenting", D2MapDB.pins == "objectives" and felt.pins.buttons[2].afkrydset == true)
felt.shape.buttons[2]:Klik()
kor(0.2)
tjek("valg af Square skifter maske", D2MapDB.shape == "square" and fliser()[1].maske.tekstur:find("mask%-square") ~= nil)
felt.route:Klik()
kor(0.2)
tjek("afkrydsning slår ruten fra", D2MapDB.route == false and #linjer() == 0)
felt.route:Klik()
felt.rotate:Klik()
tjek("afkrydsning slår rotation til", D2MapDB.rotate == true)
felt.rotate:Klik()
felt.locked:Klik()
tjek("Unlock to move slår mus til", D2MapDB.locked == false and root.mus == true and felt.locked.afkrydset == true)
felt.locked:Klik()
tjek("…og fra igen = click-through", D2MapDB.locked == true and root.mus == false)
felt.enabled:Klik()
tjek("Show automap skjuler automappet, vinduet bliver", root.synlig == false and vindue.synlig == true)
slash("toggle")
tjek("en kommando opdaterer vinduet", root.synlig == true and felt.enabled.afkrydset == true)
slash("opacity 25")
tjek("…også skyderne", felt.opacity.vaerdi == 25)
D2Map_Zoom(-1)
tjek("…og genvejene", felt.span.vaerdi == D2MapDB.span)
slash("")
tjek("/d2map igen lukker vinduet", vindue.synlig == false)
slash("options")
tjek("/d2map options åbner det også", vindue.synlig == true)
slash("reset")
tjek("Reset sætter felterne tilbage", felt.opacity.vaerdi == 40 and felt.shape.buttons[1].afkrydset == true
    and felt.terrain.afkrydset == false)
slash("terrain on")
slash("")

print("Uden position og med hemmelige værdier")
spiller.hemmelig = true
kor(0.2)
tjek("hemmelig UnitPosition → C_Map bruges i stedet", canvas.synlig == true and #fliser() >= 1)
spiller.ingen = true
spiller.hemmelig = false
kor(0.2)
tjek("ingen position (instance) → automappet er tomt", canvas.synlig == false and pinLayer.synlig == false)
spiller.ingen = false
kor(0.2)
tjek("position igen → automappet er tilbage", canvas.synlig == true and pinLayer.synlig == true)

print("Uden Questie")
pinsLib.worldmapPinRegistry[Questie] = nil
kor(1.2)
tjek("Blizzards quest-punkter bruges som reserve", #pins() == 1, #pins())
slash("source questie")
kor(1.2)
tjek("/d2map source questie uden Questie giver ingen pins", #pins() == 0)
slash("source auto")

print("Egen adapter")
D2Map.RegisterAdapter("Proeve", {
    name = "Prøve",
    IsAvailable = function() return true end,
    Collect = function(out)
        D2Map.EmitPin(out, 1, 0, spiller.nord + 20, spiller.vest, "proeve.blp", 1, 0, 0, "objective", 500)
        return 1
    end,
})
slash("source proeve")
kor(1.2)
tjek("en registreret adapter kan vælges og tegner", pinVed(0, 20 * px) ~= nil)

print("Ruten forbedres, og besøgte mål tages ud")
-- Tre mål på en øst-vest-linje: 50 øst, 150 øst og 55 vest. Nærmeste nabo giver
-- 50 → 150 → -55 (355 yards); den korteste er -55 → 50 → 150 (260 yards).
local maal = { { 0, 50 }, { 0, 150 }, { 0, -55 } }
D2Map.RegisterAdapter("Proeve", {
    name = "Prøve",
    IsAvailable = function() return true end,
    Collect = function(out)
        for i, m in ipairs(maal) do
            D2Map.EmitPin(out, i, 0, -9000 + m[1], -100 - m[2], "proeve.blp", 1, 1, 1, "objective", 600 + i)
        end
        return #maal
    end,
})
kor(1.2)
tjek("or-opt finder den korte rækkefølge (vest først)", rute() == "-62,0 56,0 168,0", rute())
spiller.vest = -100 + 50                                -- gå hen til målet 55 yards mod vest (5 fra)
kor(1.2)
tjek("et besøgt mål tages ud af ruten", #linjer() == 2 and rute() == "112,0 224,0", rute())
spiller.vest = -100                                    -- tilbage: det besøgte mål er stadig ude
kor(1.2)
tjek("…så stregen ikke peger tilbage på det", rute() == "56,0 168,0", rute())
ur = ur + 200                                          -- tre minutter efter er det med igen (respawn)
kor(1.2)
tjek("…og er med igen efter tre minutter", #linjer() == 3, rute())
-- Hvor god er ruten? Tilfældige sæt af mål sammenlignes med den korteste af alle
-- rækkefølger: 40 sæt med 7 mål (her skal ruten være den korteste) og 12 sæt med
-- 10 mål (her er den et bud).
local froe = 12345
local function tilfaeldig()                            -- fast talrække, så testen er ens hver gang
    froe = (froe * 1103515245 + 12345) % 2147483648
    return froe / 2147483648
end
local function laengde(punkter, raekke)
    local sum, x, y = 0, 0, 0
    for _, i in ipairs(raekke) do
        sum = sum + math.sqrt((punkter[i].x - x) ^ 2 + (punkter[i].y - y) ^ 2)
        x, y = punkter[i].x, punkter[i].y
    end
    return sum
end
local function korteste(punkter)
    local bedst, brugt = math.huge, {}
    local function soeg(dybde, x, y, sum)
        if sum >= bedst then return end
        if dybde > #punkter then bedst = sum return end
        for i = 1, #punkter do
            if not brugt[i] then
                brugt[i] = true
                soeg(dybde + 1, punkter[i].x, punkter[i].y, sum + math.sqrt((punkter[i].x - x) ^ 2 + (punkter[i].y - y) ^ 2))
                brugt[i] = false
            end
        end
    end
    soeg(1, 0, 0, 0)
    return bedst
end
local function maalRuter(saet, antalMaal)
  local optimale, vaerste = 0, 1
  for _ = 1, saet do
    maal = {}
    while #maal < antalMaal do
        local vinkel, afstand = tilfaeldig() * 2 * math.pi, 30 + tilfaeldig() * 180
        local n, o = math.sin(vinkel) * afstand, math.cos(vinkel) * afstand
        local fri = true
        for _, m in ipairs(maal) do if (m[1] - n) ^ 2 + (m[2] - o) ^ 2 < 20 ^ 2 then fri = false end end
        if fri then maal[#maal + 1] = { n, o } end
    end
    ur = ur + 200                                      -- glem besøgte mål fra forrige sæt
    kor(1.2)
    local punkter, raekke = {}, {}
    for i, li in ipairs(linjer()) do punkter[i], raekke[i] = { x = li.til.x, y = li.til.y }, i end
    local forhold = #punkter == antalMaal and laengde(punkter, raekke) / korteste(punkter) or 99
    if forhold < 1.0001 then optimale = optimale + 1 end
    vaerste = math.max(vaerste, forhold)
  end
  print(("       %d mål: den korteste mulige i %d af %d sæt; værste var %.1f %% længere"):format(
      antalMaal, optimale, saet, (vaerste - 1) * 100))
  return optimale, vaerste
end
local optimale, vaerste = maalRuter(40, 7)
tjek("op til 8 mål: ruten er altid den korteste, der findes", optimale == 40 and vaerste < 1.0001, vaerste)
optimale, vaerste = maalRuter(12, 10)
tjek("10 mål: aldrig mere end 15 % længere end den korteste", vaerste <= 1.15, vaerste)

maal = {}
for i = 1, 60 do maal[i] = { math.sin(i * 1.7) * 200, math.cos(i * 2.3) * 200 } end
kor(1.2)
tjek("mange mål: højst 40 stop, og ruten besøger hvert kun én gang", (function()
    local set, n = {}, 0
    for _, li in ipairs(linjer()) do
        local k = li.til.x .. ":" .. li.til.y
        if set[k] then return false end
        set[k], n = true, n + 1
    end
    return n > 20 and n <= 40
end)(), #linjer())
slash("route off")
kor(0.2)
tjek("/d2map route off", #linjer() == 0)
slash("route on")

print("Rotation efter figurens retning")
maal = { { 0, -50 }, { 80, 0 } }                       -- ét mål 50 yards mod vest, ét 80 mod nord
spiller.retning = math.pi / 2                          -- figuren ser mod vest
kor(1.2)
tjek("nord opad: målet mod vest står til venstre", pinVed(-50 * px, 0) ~= nil)
tjek("nord opad: pilen peger mod vest", taet(pinLayer.born[1].rotation, math.pi / 2))
slash("rotate on")
kor(0.2)
tjek("rotate: det, figuren ser mod (vest), står lige op", pinVed(0, 50 * px) ~= nil)
tjek("rotate: nord ligger til højre", pinVed(80 * px, 0) ~= nil)
tjek("rotate: pilen peger lige op", taet(pinLayer.born[1].rotation, 0))
tjek("rotate: ruten drejer med", rute() == "0,56 90,0", rute())
slash("terrain on")
kor(0.2)
local drejet
for _, fl in ipairs(fliser()) do if fl.tekstur == ns.Tiles[0][32 * 64 + 48] then drejet = fl end end
local ex, ey = (32.5 - cx) * tilePx, -(48.5 - cy) * tilePx   -- flisens midte med nord opad
tjek("rotate: fliserne drejes og flyttes med", drejet and taet(drejet.rotation, -math.pi / 2)
    and taet(drejet.punkter.CENTER.x, ey) and taet(drejet.punkter.CENTER.y, -ex),
    drejet and (drejet.punkter.CENTER.x .. ", " .. drejet.punkter.CENTER.y))
slash("terrain off")
spiller.retning = math.pi                              -- vend mod syd
root.scripts.OnUpdate(root, 0.001)                     -- én frame, langt under 0,1 sek.
tjek("rotate: kortet følger med i samme frame, mens figuren drejer", pinVed(50 * px, 0) ~= nil)
spiller.retning = nil                                  -- retning ukendt (fx hemmelig)
kor(0.2)
tjek("uden retning falder kortet tilbage til nord opad", pinVed(-50 * px, 0) ~= nil)
spiller.retning = 1.25
slash("rotate off")
slash("source auto")

print("Tastaturgenvej, når Alt+M peger på en addon, der er slået fra")
bindinger["ALT-M"] = "DandyMap_AUTOMAP"                -- DandyMap er ikke indlæst: handlingen findes ikke
D2MapDB.bindingOffered = false
fyr("PLAYER_ENTERING_WORLD")
tjek("en forældet Alt+M-binding overtages", bindinger["ALT-M"] == "D2MAP_TOGGLE" and D2MapDB.bindingOffered == true)
bindinger["ALT-M"] = "MACRO Mount"
D2MapDB.bindingOffered = false
fyr("PLAYER_ENTERING_WORLD")
tjek("en makro på Alt+M bliver ikke taget", bindinger["ALT-M"] == "MACRO Mount")

print("Tastaturgenvej, når Alt+M er optaget")
kendteHandlinger[#kendteHandlinger + 1] = "DandyMap_AUTOMAP"   -- nu er DandyMap indlæst
bindinger["ALT-M"] = "DandyMap_AUTOMAP"
D2MapDB.bindingOffered = false
fyr("PLAYER_ENTERING_WORLD")
tjek("en optaget Alt+M bliver ikke taget", bindinger["ALT-M"] == "DandyMap_AUTOMAP" and D2MapDB.bindingOffered == true)
tjek("…men det siges i chatten", chat[#chat]:find("already bound to DandyMap_AUTOMAP", 1, true) ~= nil)
kamp = true
slash("bind")
tjek("/d2map bind gør ingenting i combat", bindinger["ALT-M"] == "DandyMap_AUTOMAP")
kamp = false
slash("bind")
tjek("/d2map bind overtager Alt+M", bindinger["ALT-M"] == "D2MAP_TOGGLE")
slash("bind ctrl-n")
tjek("/d2map bind ctrl-n", bindinger["CTRL-N"] == "D2MAP_TOGGLE")

print("Nulstilling og gemte indstillinger")
slash("reset")
tjek("/d2map reset", D2MapDB.opacity == 40 and D2MapDB.span == 500 and D2MapDB.bindingOffered == true
    and D2MapDB.terrain == false and D2MapDB.route == true and D2MapDB.rotate == false)
-- En ødelagt SavedVariables-fil: indlæs addon'en forfra og se, at den retter op.
D2MapDB.opacity = "vrøvl"
D2MapDB.size = 99999
D2MapDB.shape = "trekant"
D2MapDB.span = 432.7
D2MapDB.terrain = true
D2MapDB.settingsVersion = nil                          -- gemt af den første udgave
assert(loadfile("D2Map/D2Map.lua"))("D2Map", ns)
rammer[#rammer].scripts.OnEvent(rammer[#rammer], "ADDON_LOADED", "D2Map")
tjek("forkerte gemte værdier rettes ved indlæsning", D2MapDB.opacity == 40 and D2MapDB.size == 1400
    and D2MapDB.shape == "round" and D2MapDB.span == 433)
tjek("den første udgaves gemte «terræn til» slås fra én gang", D2MapDB.terrain == false and D2MapDB.settingsVersion == 2)
D2MapDB.terrain = true                                 -- slået til igen af brugeren
assert(loadfile("D2Map/D2Map.lua"))("D2Map", ns)
rammer[#rammer].scripts.OnEvent(rammer[#rammer], "ADDON_LOADED", "D2Map")
tjek("…og et senere «terræn til» bliver stående", D2MapDB.terrain == true)

print(("\n%d af %d tjek bestod"):format(antal - fejl, antal))
os.exit(fejl == 0 and 0 or 1)
