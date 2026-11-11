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
    "SetSnapToPixelGrid", "SetTexelSnappingBias", "SetDrawLayer", "SetText",
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
function Widget:Show() self.synlig = true end
function Widget:Hide() self.synlig = false end
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

local rammer = {}
UIParent = NyWidget("Frame")
function CreateFrame(slags, navn, foraelder)
    local w = NyWidget(slags, foraelder)
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
local function pinVed(x, y)
    for _, p in ipairs(pins()) do
        if taet(p.punkter.CENTER.x, x, 0.05) and taet(p.punkter.CENTER.y, y, 0.05) then return p end
    end
end

print("Terræn")
kor(0.3)
local f = fliser()
tjek("fliser tegnes omkring spilleren", #f >= 1 and #f <= 4, #f)
-- Spilleren står i flise (32, 48): cx = 32 + 100/533,33, cy = 32 + 9000/533,33
local tilePx = (1600 / 3) * 560 / 500
local cx, cy = 32 + 100 / (1600 / 3), 32 + 9000 / (1600 / 3)
local egen
for _, t in ipairs(f) do if t.tekstur == ns.Tiles[0][32 * 64 + 48] then egen = t end end
tjek("spillerens egen flise har det rigtige fil-id", egen ~= nil)
tjek("flisen ligger rigtigt i forhold til spilleren", egen and taet(egen.punkter.TOPLEFT.x, (32 - cx) * tilePx)
    and taet(egen.punkter.TOPLEFT.y, -(48 - cy) * tilePx), egen and (egen.punkter.TOPLEFT.x .. ", " .. egen.punkter.TOPLEFT.y))
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
slash("")
slash("status")
slash("help")
tjek("hjælp og status skriver i chatten", #chat > 20)

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
tjek("/d2map reset", D2MapDB.opacity == 40 and D2MapDB.span == 500 and D2MapDB.bindingOffered == true)
-- En ødelagt SavedVariables-fil: indlæs addon'en forfra og se, at den retter op.
D2MapDB.opacity = "vrøvl"
D2MapDB.size = 99999
D2MapDB.shape = "trekant"
D2MapDB.span = 432.7
assert(loadfile("D2Map/D2Map.lua"))("D2Map", ns)
rammer[#rammer].scripts.OnEvent(rammer[#rammer], "ADDON_LOADED", "D2Map")
tjek("forkerte gemte værdier rettes ved indlæsning", D2MapDB.opacity == 40 and D2MapDB.size == 1400
    and D2MapDB.shape == "round" and D2MapDB.span == 433)

print(("\n%d af %d tjek bestod"):format(antal - fejl, antal))
os.exit(fejl == 0 and 0 or 1)
