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
function Widget:GetHeight() return self.hoejde or 768 end      -- UIParent: 768 enheder høj
function Widget:SetScale(skala) self.skala = skala end
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
-- Spillets eget waypoint (nil = intet sat). Sættes med saetWaypoint(nord, øst) i yards fra spilleren.
local waypoint
C_Map.GetUserWaypoint = function() return waypoint end
-- Zone-procenter for et punkt et antal yards nord og øst for spilleren.
local function zonePunkt(nord, oest)
    local x = (ZONE.venstre - (spiller.vest - oest)) / ZONE.bredde * 100
    local y = (ZONE.top - (spiller.nord + nord)) / ZONE.hoejde * 100
    return x, y
end

local function saetWaypoint(nord, oest)
    if not nord then waypoint = nil return end
    local x, y = zonePunkt(nord, oest)
    waypoint = { uiMapID = ZONE.id, position = CreateVector2D(x / 100, y / 100) }
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
tjek("defaults fyldes ud", D2MapDB.opacity == 0 and D2MapDB.combatOpacity == 21 and D2MapDB.enabled == true)
tjek("standard: synlig i bevægelse (54 %), ingen combat-toning", D2MapDB.moveFade == true and D2MapDB.moveOpacity == 54
    and D2MapDB.combatFade == false)
tjek("standard: 650 yards, drejer med figuren, sepia", D2MapDB.span == 650 and D2MapDB.rotate == true and D2MapDB.style == "sepia")
tjek("standard: intet på kanten for det, der er uden for rammen", D2MapDB.edgePins == false)
tjek("terræn er slået fra som standard", D2MapDB.terrain == false)
fyr("PLAYER_LOGIN")
fyr("PLAYER_ENTERING_WORLD")

-- Resten af testen regner på et fast grundlag (40 % synlig, 500 yards, nord opad,
-- combat-toning til, bevægelse fra) i stedet for standarderne, så tallene i
-- tjekkene ikke skal skrives om, hver gang en standard ændres.
local function grundlag()
    for _, kommando in ipairs({ "opacity 40", "combat 18", "combat on", "moving 20", "moving off",
        "zoom 500", "rotate off", "style color", "rim on" }) do
        SlashCmdList.D2MAP(kommando)
    end
end
grundlag()

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

local PRIK = "Interface\\AddOns\\D2Map\\Media\\dot.tga"   -- prikken i guidens vej
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
    for _, b in ipairs(pinLayer.born) do
        if b.slags == "Texture" and b.shown and b.tekstur ~= PRIK then t[#t + 1] = b end
    end
    return t
end
-- Prikkerne i guidens vej, og mærket ved målet (nil, når det er skjult).
local function prikker()
    local t = {}
    for _, b in ipairs(pinLayer.born) do
        if b.slags == "Texture" and b.shown and b.tekstur == PRIK then t[#t + 1] = b end
    end
    return t
end
local function maalmaerke()
    for _, b in ipairs(pinLayer.born) do
        if b.slags == "Texture" and b.tekstur == PRIK and b.shown == nil and b.synlig then return b end
    end
end
local function prikVed(x, y)
    for _, p in ipairs(prikker()) do
        if taet(p.punkter.CENTER.x, x, 0.05) and taet(p.punkter.CENTER.y, y, 0.05) then return p end
    end
end
local function linjer()
    local t = {}
    for _, b in ipairs(pinLayer.born) do if b.slags == "Line" and b.shown then t[#t + 1] = b end end
    return t
end
-- Linjestykkerne samlet til former: en ny form begynder, når et stykke ikke
-- starter, hvor det forrige sluttede. Hver form er en liste af punkter.
local function former()
    local alle, form, sidste = {}, nil, nil
    for _, l in ipairs(linjer()) do
        if not sidste or l.fra.x ~= sidste.x or l.fra.y ~= sidste.y then
            form = { lukket = false, start = l.fra }
            alle[#alle + 1] = form
        end
        form[#form + 1] = l.til
        sidste = l.til
        form.lukket = l.til.x == form.start.x and l.til.y == form.start.y
    end
    return alle
end
-- Ligger punktet (x, y) inden i formen? (stråle mod højre, lige/ulige krydsninger)
local function indeni(form, x, y)
    local inde, j = false, #form
    for i = 1, #form do
        local a, b = form[i], form[j]
        if (a.y > y) ~= (b.y > y) and x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x then inde = not inde end
        j = i
    end
    return inde
end
-- Korteste afstand fra (x, y) til formens kant.
local function afstand(form, x, y)
    local mindst, j = math.huge, #form
    for i = 1, #form do
        local a, b = form[i], form[j]
        local dx, dy = b.x - a.x, b.y - a.y
        local l = dx * dx + dy * dy
        local u = l > 0 and math.max(0, math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / l)) or 0
        mindst = math.min(mindst, math.sqrt((x - a.x - u * dx) ^ 2 + (y - a.y - u * dy) ^ 2))
        j = i
    end
    return mindst
end
local function pinVed(x, y)
    for _, p in ipairs(pins()) do
        if taet(p.punkter.CENTER.x, x, 0.05) and taet(p.punkter.CENTER.y, y, 0.05) then return p end
    end
end

-- (test/tegn.lua genbruger alt herover; behold linjen herunder som mærke)
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

print("Former om klynger")
tjek("to mål er ikke en klynge: ingen form", #linjer() == 0, #linjer())

print("Flydende opdatering")
spiller.nord = spiller.nord + 10                      -- gå 10 yards mod nord
kor(0.12)
tjek("pins flytter sig med spilleren inden for 0,1 sek.", pinVed(50 * px, 90 * px) ~= nil)
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

print("Gennemsigtighed i bevægelse")
local slash = SlashCmdList.D2MAP
-- Går sekunder mod nord i løbetempo (7 yards i sekundet) og tilbage til udgangspunktet bagefter.
local function gaa(sekunder)
    local skridt, start = 0.02, spiller.nord
    for _ = 1, math.floor(sekunder / skridt + 0.5) do
        spiller.nord = spiller.nord + 7 * skridt
        root.scripts.OnUpdate(root, skridt)
    end
    return start
end
local hjem = gaa(1)
tjek("slået fra: bevægelse ændrer ikke gennemsigtigheden", taet(canvas.alfa, 0.40), canvas.alfa)
slash("moving 20")
tjek("/d2map moving 20 sætter værdien og slår den til", D2MapDB.moveOpacity == 20 and D2MapDB.moveFade == true)
kor(1)
tjek("står man stille, gælder den normale gennemsigtighed", taet(canvas.alfa, 0.40), canvas.alfa)
gaa(1)
tjek("i bevægelse: 20 %", taet(canvas.alfa, 0.20) and taet(pinLayer.alfa, 0.40), canvas.alfa)
kor(0.2)
tjek("et kort stop tæller stadig som bevægelse (intet blink)", taet(canvas.alfa, 0.20), canvas.alfa)
kor(1.2)
tjek("efter stoppet: tilbage på 40 %", taet(canvas.alfa, 0.40), canvas.alfa)
slash("moving 80")
gaa(1)
tjek("den må gerne være højere end normalt (mere synlig, mens man løber)", taet(canvas.alfa, 0.80), canvas.alfa)
fyr("PLAYER_REGEN_DISABLED")
gaa(1)
tjek("i combat vinder combat-værdien, også i bevægelse", taet(canvas.alfa, 0.18), canvas.alfa)
fyr("PLAYER_REGEN_ENABLED")
slash("moving off")
gaa(1)
tjek("/d2map moving off", D2MapDB.moveFade == false and taet(canvas.alfa, 0.40), canvas.alfa)
spiller.nord = hjem
kor(0.6)

print("Slash-kommandoer")
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
tjek("feltet og skyderen for bevægelse findes", felt.moveFade.afkrydset == false and felt.moveOpacity.vaerdi == 80)
felt.moveOpacity:SetValue(30)
tjek("at trække i skyderen slår den til", D2MapDB.moveOpacity == 30 and D2MapDB.moveFade == true and felt.moveFade.afkrydset == true)
felt.moveFade:Klik()
tjek("afkrydsningen slår den fra igen", D2MapDB.moveFade == false)
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
tjek("afkrydsning slår formerne fra", D2MapDB.route == false)
felt.route:Klik()
tjek("…og til igen", D2MapDB.route == true)
felt.routeFocus:Klik()
tjek("afkrydsning slår «kun guidens trin» fra", D2MapDB.routeFocus == false)
felt.routeFocus:Klik()
felt.pullRange:SetValue(27)
tjek("pull-skyderen går i trin på 5", D2MapDB.pullRange == 25 or D2MapDB.pullRange == 30, D2MapDB.pullRange)
felt.pullRange:SetValue(40)
felt.waypoint:Klik()
tjek("afkrydsning slår guidens vej fra", D2MapDB.waypoint == false)
felt.waypoint:Klik()
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
tjek("Reset sætter felterne tilbage til standarderne", felt.opacity.vaerdi == 0 and felt.shape.buttons[1].afkrydset == true
    and felt.terrain.afkrydset == false and felt.rotate.afkrydset == true and felt.moveOpacity.vaerdi == 54
    and felt.style.buttons[2].afkrydset == true)
grundlag()
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

print("Former om klynger af mål")
-- Mål som { nord, øst } i yards fra der, hvor spilleren står nu.
local maal = {}
local udgangsNord, udgangsVest = spiller.nord, spiller.vest
D2Map.RegisterAdapter("Proeve", {
    name = "Prøve",
    IsAvailable = function() return true end,
    Collect = function(out)
        for i, m in ipairs(maal) do
            D2Map.EmitPin(out, i, 0, udgangsNord + m[1], udgangsVest - m[2], "proeve.blp", 1, 1, 1, "objective", m[3] or 600 + i)
        end
        return #maal
    end,
})
local lejr1 = { { 60, 40 }, { 100, 60 }, { 120, 20 }, { 80, -10 }, { 50, 10 }, { 90, 30 } }
local lejr2 = { { -120, -100 }, { -150, -70 }, { -170, -120 }, { -130, -140 } }
local enlig = { 150, -150 }
local function saet(...)
    maal = {}
    for _, liste in ipairs({ ... }) do
        for _, m in ipairs(liste) do maal[#maal + 1] = m end
    end
    kor(1.2)
end
-- Den rute, der ligger nærmest målet (nummer), og afstanden til den i yards.
local function naermeste(m)
    local bedst, bedstAfstand
    for nr, form in ipairs(former()) do
        local a = afstand(form, m[2] * px, m[1] * px) / px
        if not bedstAfstand or a < bedstAfstand then bedst, bedstAfstand = nr, a end
    end
    return bedst, bedstAfstand or math.huge
end
-- Kan alle mål i listen pulles fra rute nr? (pull-afstand + lidt slæk til de bløde hjørner)
local function kanPulles(liste, nr, raekkevidde)
    for _, m in ipairs(liste) do
        local i, a = naermeste(m)
        if (nr and i ~= nr) or a > raekkevidde + 8 then return false, a end
    end
    return true
end
local function omkreds(form)
    local sum, j = 0, #form
    for i = 1, #form do
        sum = sum + math.sqrt((form[i].x - form[j].x) ^ 2 + (form[i].y - form[j].y) ^ 2)
        j = i
    end
    return sum / px
end
tjek("standard: pull-afstand 40 yards", D2MapDB.pullRange == 40)

-- To små lejre (ca. 75 yards på tværs): alt kan pulles fra ét sted i midten.
saet(lejr1, lejr2, { enlig })
local f = former()
tjek("to lejre giver to ruter", #f == 2, #f)
tjek("ruterne er lukkede kurver", f[1] and f[1].lukket and f[2] and f[2].lukket)
local nr1, nr2 = naermeste(lejr1[1]), naermeste(lejr2[1])
tjek("hver lejr har sin egen rute", nr1 and nr2 and nr1 ~= nr2)
tjek("alle lejrens mål kan pulles fra ruten", kanPulles(lejr1, nr1, 40) and kanPulles(lejr2, nr2, 40))
tjek("en lille lejr bliver til ét sted: en lille ring i midten", omkreds(f[nr1]) < 60 and #f[nr1] == 24
    and indeni(f[nr1], 25 * px, 85 * px), omkreds(f[nr1]))
tjek("det enlige mål får ingen rute", select(2, naermeste(enlig)) > 100)

local foer = linjer()[1].til.y
spiller.nord = spiller.nord + 10
kor(0.12)
tjek("ruterne flytter sig med spilleren", taet(linjer()[1].til.y, foer - 10 * px))
spiller.nord = spiller.nord - 10
kor(0.12)

local nyt = { -100, -30 }                               -- en mob mere ved den sydvestlige lejr
tjek("et nyt mål kan ikke pulles fra den gamle rute …", select(2, naermeste(nyt)) > 48)
saet(lejr1, lejr2, { enlig, nyt })
tjek("… men fra den nye, når ruten er regnet om", kanPulles({ nyt }, naermeste(lejr2[1]), 40) and kanPulles(lejr2, nil, 40),
    select(2, naermeste(nyt)))

local antalFoer = #linjer()
slash("zoom 320")                                      -- den sydvestlige lejr ligger nu uden for rammen
kor(1.2)
local yderst = 0
for _, l in ipairs(linjer()) do
    yderst = math.max(yderst, math.sqrt(l.fra.x ^ 2 + l.fra.y ^ 2), math.sqrt(l.til.x ^ 2 + l.til.y ^ 2))
end
tjek("stykker uden for rammen tegnes ikke", #linjer() > 0 and #linjer() < antalFoer and yderst <= 280 * 0.90 + 0.01, yderst)
slash("zoom 500")

-- En stor ring af mål (radius 120 yards): ruten skal ligge inde i ringen.
local ring = {}
for i = 1, 10 do
    local v = i / 10 * 2 * math.pi
    ring[i] = { math.sin(v) * 120, math.cos(v) * 120 }
end
saet(ring)
f = former()
local yderstYards, inderstYards = 0, math.huge
for _, punkt in ipairs(f[1] or {}) do
    local r = math.sqrt(punkt.x ^ 2 + punkt.y ^ 2) / px
    yderstYards, inderstYards = math.max(yderstYards, r), math.min(inderstYards, r)
end
tjek("en stor klynge: ruten ligger inde i klyngen, ikke uden om", #f == 1 and yderstYards < 95 and inderstYards > 60,
    yderstYards .. " / " .. inderstYards)
tjek("…alle de yderste mål kan stadig pulles", kanPulles(ring, 1, 40))
tjek("…og den er kortere end at løbe rundt om dem", omkreds(f[1]) < 2 * math.pi * 120 * 0.75, omkreds(f[1]))

local midt = { 0, 0 }                                  -- en mob midt i ringen: 80 yards fra ruten
saet(ring, { midt })
tjek("et mål midt i klyngen får ruten til at slå et slag ind", kanPulles({ midt }, 1, 40) and kanPulles(ring, 1, 40),
    select(2, naermeste(midt)))

slash("pull 0")
saet(ring)
tjek("/d2map pull 0: ruten går gennem de yderste mål", kanPulles(ring, 1, 0) and D2MapDB.pullRange == 0)
slash("pull 60")
saet(ring)
f = former()
tjek("/d2map pull 60: ruten trækker sig længere ind", #f == 1 and omkreds(f[1]) < 2 * math.pi * 75 and kanPulles(ring, 1, 60),
    f[1] and omkreds(f[1]))
slash("pull 40")

saet({ { 0, 60 }, { 0, 120 }, { 0, 180 }, { 0, 240 } }) -- fire mål på én linje mod øst
f = former()
tjek("mål på én linje: ruten er en streg langs linjen, kortere i begge ender", #f == 1 and f[1].lukket
    and kanPulles(maal, 1, 40) and omkreds(f[1]) < 2 * 120, f[1] and omkreds(f[1]))

-- En bue af mål: ruten skal følge buen på indersiden.
local bue = {}
for i = 0, 12 do
    local v = math.pi * (0.1 + 0.8 * i / 12)
    bue[#bue + 1] = { math.sin(v) * 170 - 80, math.cos(v) * 170 }
end
saet(bue)
f = former()
tjek("en bue af mål giver én rute, hvorfra alle kan pulles", #f == 1 and kanPulles(bue, 1, 40))
tjek("…og den spænder ikke over hullet under buen", #f == 1 and not indeni(f[1], 0, -20 * px))

saet({ { 40, 40 }, { 70, 60 } })
tjek("to mål alene giver ingen rute", #linjer() == 0)
saet(lejr1)
slash("outlines off")
kor(0.2)
tjek("/d2map outlines off", #linjer() == 0)
slash("route on")
kor(1.2)
tjek("/d2map route on", #former() == 1)

print("Guidens vej (Factoruide)")
saet({})                                               -- ingen mål: kun vejen
tjek("uden Factoruide tegnes ingen vej", #prikker() == 0 and maalmaerke() == nil)
-- En attrap af Factoruide: Pathing:Remaining giver resten af vejen som { nord, vest }.
local vej, guidenSkjult = nil, false
Factoruide = {
    Get = function(_, noegle) if noegle == "uiShown" then return not guidenSkjult end end,
    Pathing = { Remaining = function(_, kontinent, nord, vest) return vej and vej(nord, vest, kontinent) end },
}
-- Lige mod nord: 100 yards = 112 pixels. Prikkerne ligger 9 pixels fra hinanden, talt fra målet.
vej = function(n, w) return { { n, w }, { udgangsNord + 100, udgangsVest } } end
kor(0.3)
tjek("en lige vej mod nord giver en række prikker lige op", #prikker() == 11 and prikVed(0, 103) and prikVed(0, 94) and prikVed(0, 13),
    #prikker())
local maerke = maalmaerke()
tjek("målet er mærket med gult på stedet", maerke and taet(maerke.punkter.CENTER.x, 0) and taet(maerke.punkter.CENTER.y, 112)
    and maerke.bredde == 14 and maerke.farve[1] == 1)
tjek("prikkerne er klart grønne og har deres egen lyse tekstur", prikker()[1].farve[2] == 1 and prikker()[1].farve[1] < 0.4
    and prikker()[1].bredde == 7)
tjek("teksturen findes i addon'en", io.open("D2Map/Media/dot.tga") ~= nil)
spiller.nord = spiller.nord + 4                        -- gå 4 yards mod målet
kor(0.3)
tjek("prikkerne står stille på jorden, mens man går (brødkrummer)", prikVed(0, 103 - 4 * px) ~= nil and prikVed(0, 94 - 4 * px) ~= nil)
tjek("…og den nærmeste forsvinder under spillerens pil", #prikker() == 10, #prikker())
spiller.nord = spiller.nord - 4

vej = function(n, w) return { { n, w }, { udgangsNord, udgangsVest - 1000 } } end   -- 1000 yards mod øst
kor(0.3)
maerke = maalmaerke()
tjek("et mål uden for rammen: stregen løber ud til kanten", #prikker() == 27 and prikVed(247, 0) and prikVed(13, 0), #prikker())
tjek("…og et mindre mærke på kanten viser retningen", maerke and taet(maerke.punkter.CENTER.x, 252) and taet(maerke.punkter.CENTER.y, 0)
    and maerke.bredde == 10)
slash("rim off")
kor(0.3)
tjek("/d2map rim off: mærket på kanten er væk, stregen bliver", maalmaerke() == nil and #prikker() == 27, #prikker())
slash("rim on")
kor(0.3)
tjek("/d2map rim on: mærket er tilbage", maalmaerke() ~= nil)

-- En vej med et knæk: 100 yards øst, så 100 yards nord.
vej = function(n, w) return { { n, w }, { udgangsNord, udgangsVest - 100 }, { udgangsNord + 100, udgangsVest - 100 } } end
kor(0.3)
tjek("en vej med knæk følges rundt om hjørnet", prikVed(112, 103) and prikVed(112, 4) and prikVed(107, 0) and prikVed(17, 0)
    and not prikVed(56, 56), #prikker())

guidenSkjult = true
kor(0.3)
tjek("er guiden skjult, vises vejen heller ikke her", #prikker() == 0 and maalmaerke() == nil)
guidenSkjult = false
slash("waypoint off")
kor(0.3)
tjek("/d2map waypoint off", #prikker() == 0 and maalmaerke() == nil)
slash("waypoint on")
kor(0.3)
tjek("/d2map waypoint on", #prikker() > 10)
slash("pinsize 2")
kor(0.3)
tjek("prikkerne følger pin-størrelsen (halvt)", taet(prikker()[1].bredde, 7 * 1.4) and taet(maalmaerke().bredde, 14 * 1.4))
slash("pinsize 1")
kor(0.3)

vej = function() error("guiden fejler") end
kor(0.3)
tjek("fejler guiden, tegnes der bare ingen vej", #prikker() == 0 and root.synlig and canvas.synlig)
vej = function() return { { "x", 1 }, { 2, 3 } } end
kor(0.3)
tjek("vrøvl fra guiden tegnes ikke", #prikker() == 0)
vej = function(n, w, kontinent) return kontinent == 0 and { { n, w }, { udgangsNord + 100, udgangsVest } } or nil end

D2Map.RegisterPathSource("anden", {
    name = "Anden guide",
    IsAvailable = function() return true end,
    GetPath = function(_, n, w) return { { n, w }, { udgangsNord - 100, udgangsVest } } end,
})
kor(0.3)
tjek("den første kilde med en vej vinder (Factoruide før en senere)", prikVed(0, 103) ~= nil)
vej = nil
kor(0.3)
tjek("en anden registreret kilde bruges, når Factoruide ikke har en vej", prikVed(0, -103) ~= nil)
D2Map.RegisterPathSource("anden", { name = "Anden guide", IsAvailable = function() return false end, GetPath = function() end })
vej = function(n, w) return { { n, w }, { udgangsNord + 100, udgangsVest } } end
kor(0.3)

print("Shortest Path Forever og spillets waypoint")
-- Med SPF indlæst overlader Factoruide vejen til den og giver ingen selv.
vej = nil
kor(0.3)
tjek("uden nogen vej tegnes ingenting", #prikker() == 0 and maalmaerke() == nil)
saetWaypoint(0, 100)                                   -- et mærke på kortet 100 yards mod øst
kor(0.3)
tjek("spillets waypoint: en lige streg derhen", prikVed(103, 0) ~= nil and maalmaerke() and taet(maalmaerke().punkter.CENTER.x, 112),
    #prikker())
-- En attrap af SPF: Journey() fortæller, om den guider, og hvor målet er.
local rejse
ShortestPathForever = { API = { Journey = function()
    if rejse then return rejse end
    return nil, "none"
end } }
local function spf(guider, maalNord, maalOest)
    if guider == nil then
        rejse = nil
    else
        local x, y = zonePunkt(maalNord, maalOest)
        rejse = { guided = guider, goal = { map = ZONE.id, x = x / 100, y = y / 100, title = "Mål" }, legs = {}, index = 1 }
    end
    ur = ur + 2                                        -- D2Map spørger SPF højst én gang i sekundet
    kor(0.3)
end
saetWaypoint(100, 0)                                   -- SPF har sat spillets waypoint på næste knæk: 100 yards nord
spf(true, 400, 300)
tjek("SPF guider: stregen går til næste knæk, ikke til det fjerne mål", prikVed(0, 103) ~= nil and prikVed(103, 0) == nil
    and taet(maalmaerke().punkter.CENTER.y, 112))
slash("status")
tjek("status nævner Shortest Path Forever som kilde", chat[#chat]:find("Shortest Path Forever", 1, true) ~= nil, chat[#chat])
saetWaypoint(nil)
spf(true, 0, -150)                                     -- tæt på målet har SPF intet waypoint: mål 150 yards mod vest
tjek("SPF uden waypoint, tæt på målet: stregen går lige til målet", prikVed(-159, 0) ~= nil and #prikker() > 10
    and taet(maalmaerke().punkter.CENTER.x, -168), #prikker())
spf(true, 0, -1000)
tjek("SPF uden waypoint, langt fra målet: ingen streg (vejen kendes ikke)", #prikker() == 0)
saetWaypoint(0, 100)
spf(false, 400, 300)
tjek("SPF på pause: spillets waypoint bruges som almindeligt mærke", prikVed(103, 0) ~= nil)
slash("status")
tjek("…og status siger game waypoint", chat[#chat]:find("game waypoint", 1, true) ~= nil, chat[#chat])
vej = function(n, w) return { { n, w }, { udgangsNord - 100, udgangsVest } } end
spf(true, 400, 300)
tjek("har Factoruide sin egen vej, vinder den over SPF og waypointet", prikVed(0, -103) ~= nil and prikVed(103, 0) == nil)
ShortestPathForever.API.Journey = function() error("SPF fejler") end
vej = nil
ur = ur + 2
kor(0.3)
tjek("fejler SPF, bruges spillets waypoint i stedet", prikVed(103, 0) ~= nil)
ShortestPathForever = nil
saetWaypoint(nil)
vej = function(n, w) return { { n, w }, { udgangsNord + 100, udgangsVest } } end
kor(0.3)

print("Pull-ruter kun for guidens aktuelle trin")
vej = nil
-- To store lejre med hver sin quest: ring A (quest 700) mod nordøst, ring B (quest 800) mod sydvest.
local function lejr(midtNord, midtOest, quest)
    local liste = {}
    for i = 1, 8 do
        local v = i / 8 * 2 * math.pi
        liste[i] = { midtNord + math.sin(v) * 70, midtOest + math.cos(v) * 70, quest }
    end
    return liste
end
local lejrA, lejrB = lejr(110, 110, 700), lejr(-110, -110, 800)
saet(lejrA, lejrB)
tjek("uden guide: en rute om hver lejr", #former() == 2, #former())
tjek("standard: ruterne følger guidens trin", D2MapDB.routeFocus == true)
-- En attrap af Factoruides guide: trin 3 og 4 er «NOW»; trin 3 hører til quest 700.
local nuvaerende, guideRute = { 3, 4 }, { steps = { [3] = { q = 700, k = "objective", n = "Brute" }, [4] = { q = 700, k = "objective", n = "Witch Doctor" },
    [5] = { q = 800, k = "objective" }, [6] = { k = "fly" } } }
Factoruide.Guide = {
    CurrentSteps = function() return nuvaerende end,
    Route = function() return guideRute end,
}
kor(1.2)
local f = former()
tjek("med guide: kun en rute om det aktuelle trins quest", #f == 1 and kanPulles(lejrA, 1, 40) and select(2, naermeste(lejrB[1])) > 100,
    #f)
slash("status")
tjek("status fortæller om begrænsningen", (chat[#chat - 1] .. chat[#chat]):find("limited to the 1 quest", 1, true) ~= nil, chat[#chat - 1])
nuvaerende = { 5 }                                     -- guiden går videre til quest 800
kor(1.2)
f = former()
tjek("skifter guiden trin, flytter ruten med", #f == 1 and kanPulles(lejrB, 1, 40) and select(2, naermeste(lejrA[1])) > 100, #f)
nuvaerende = { 3, 5 }
kor(1.2)
tjek("to quests i samme trin: en rute om hver", #former() == 2, #former())
nuvaerende = { 6 }                                     -- et rejse-trin uden quest
kor(1.2)
tjek("et trin uden quest: ingen ruter", #linjer() == 0, #linjer())
slash("focus off")
kor(1.2)
tjek("/d2map focus off: ruter om alle quests igen", #former() == 2 and D2MapDB.routeFocus == false, #former())
slash("focus on")
guidenSkjult = true
kor(1.2)
tjek("er guiden skjult, begrænser den ikke ruterne", #former() == 2, #former())
guidenSkjult = false
Factoruide.Guide.CurrentSteps = function() error("guiden fejler") end
kor(1.2)
tjek("fejler guiden, tegnes ruter om alle quests", #former() == 2, #former())
Factoruide.Guide = nil
vej = function(n, w) return { { n, w }, { udgangsNord + 100, udgangsVest } } end
kor(1.2)

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
tjek("rotate: guidens vej mod nord går til højre", prikVed(103, 0) ~= nil and prikVed(0, 103) == nil)
maal = { { 100, -20 }, { 130, 10 }, { 150, -30 }, { 110, 30 }, { 0, -50 }, { 80, 0 } }   -- plus en lejr mod nord
kor(1.2)
local midtX, midtY, n = 0, 0, 0
for _, li in ipairs(linjer()) do midtX, midtY, n = midtX + li.til.x, midtY + li.til.y, n + 1 end
tjek("rotate: formen om lejren mod nord ligger til højre", n > 0 and midtX / n > 80 and math.abs(midtY / n) < 40,
    n > 0 and (midtX / n .. ", " .. midtY / n))
maal = { { 0, -50 }, { 80, 0 } }
kor(1.2)
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
tjek("/d2map reset", D2MapDB.opacity == 0 and D2MapDB.span == 650 and D2MapDB.bindingOffered == true
    and D2MapDB.terrain == false and D2MapDB.route == true and D2MapDB.rotate == true and D2MapDB.waypoint == true
    and D2MapDB.moveFade == true and D2MapDB.moveOpacity == 54 and D2MapDB.combatFade == false
    and D2MapDB.pullRange == 40 and D2MapDB.edgePins == false and D2MapDB.routeFocus == true)
-- Med standarderne: usynlig når man står stille, synlig når man går.
kor(1)
tjek("standard: usynligt, når man står stille", taet(canvas.alfa, 0) and taet(pinLayer.alfa, 0), canvas.alfa)
for _ = 1, 50 do
    spiller.nord = spiller.nord + 0.14
    root.scripts.OnUpdate(root, 0.02)
end
tjek("standard: 54 % i bevægelse, pins fuldt synlige", taet(canvas.alfa, 0.54) and taet(pinLayer.alfa, 1), canvas.alfa)
-- En ødelagt SavedVariables-fil: indlæs addon'en forfra og se, at den retter op.
D2MapDB.opacity = "vrøvl"
D2MapDB.size = 99999
D2MapDB.shape = "trekant"
D2MapDB.span = 432.7
D2MapDB.terrain = true
D2MapDB.settingsVersion = nil                          -- gemt af den første udgave
assert(loadfile("D2Map/D2Map.lua"))("D2Map", ns)
rammer[#rammer].scripts.OnEvent(rammer[#rammer], "ADDON_LOADED", "D2Map")
tjek("forkerte gemte værdier rettes ved indlæsning", D2MapDB.opacity == 0 and D2MapDB.size == 1400
    and D2MapDB.shape == "round" and D2MapDB.span == 433)
tjek("den første udgaves gemte «terræn til» slås fra én gang", D2MapDB.terrain == false and D2MapDB.settingsVersion == 3)
D2MapDB.terrain = true                                 -- slået til igen af brugeren
D2MapDB.edgePins = true
assert(loadfile("D2Map/D2Map.lua"))("D2Map", ns)
rammer[#rammer].scripts.OnEvent(rammer[#rammer], "ADDON_LOADED", "D2Map")
tjek("…og et senere «terræn til» bliver stående", D2MapDB.terrain == true)
tjek("…ligesom kant-mærker, man selv har slået til", D2MapDB.edgePins == true)
D2MapDB.settingsVersion = 2                            -- gemt af version 1.1-1.5 med kant-mærker til
assert(loadfile("D2Map/D2Map.lua"))("D2Map", ns)
rammer[#rammer].scripts.OnEvent(rammer[#rammer], "ADDON_LOADED", "D2Map")
tjek("gemte kant-mærker fra før 1.6 slås fra én gang", D2MapDB.edgePins == false and D2MapDB.settingsVersion == 3)

print(("\n%d af %d tjek bestod"):format(antal - fejl, antal))
os.exit(fejl == 0 and 0 or 1)
