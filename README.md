# D2Map

Et Diablo II-inspireret automap til **WoW: Forever** (interface 16001): spillets
egne minimap-fliser og Questies quest-pins, halvgennemsigtigt midt på skærmen
med nord opad og spilleren i midten. Rammen tager aldrig imod mus, så kamera,
bevægelse og targeting går lige igennem.

```sh
./installer.sh        # kopierer D2Map/ ind i spillets AddOns-mappe
lua test/koer.lua     # 178 tjek mod en attrap af WoW's API
lua test/tegn.lua     # tegner pull-ruterne for nogle prøvesæt til docs/former.svg
```

Første gang skal spillet genstartes helt; derefter er `/reload` nok.

## Brug

**`/d2map` åbner indstillingsvinduet** (Lars' ønske: «det gider jeg ikke» om
kommandoer). Afkrydsningsfelter, skydere og valg for alt herunder; alt virker
med det samme, Escape lukker. Kommandoerne findes stadig og holder vinduet
ajour:

| Kommando | Hvad |
|---|---|
| `/d2map toggle` | Vis eller skjul (også `on` / `off`) |
| `/d2map opacity <0-100>` | Gennemsigtighed, når man står stille (standard 0: usynligt) |
| `/d2map combat <0-100\|on\|off>` | Gennemsigtighed i combat (standard 21, men toningen er slået fra) |
| `/d2map moving <0-100\|on\|off>` | Gennemsigtighed, mens figuren bevæger sig (standard 54, slået til) |
| `/d2map zoom <yards\|in\|out>` | Hvor mange yards rammen dækker (standard 650) |
| `/d2map size <pixels>` | Rammens størrelse (standard 560) |
| `/d2map shape <round\|square\|plain>` | Bløde kanter som cirkel eller firkant; `plain` = ingen maske |
| `/d2map style <color\|sepia\|ghost>` | `ghost` lægger terrænet additivt ovenpå, mest som i Diablo II |
| `/d2map pins <all\|objectives\|off>` | Alle Questies pins, kun mål og afleveringer, eller ingen |
| `/d2map pinsize <0.5-3>` | Størrelse på pins |
| `/d2map rim <on\|off>` | Det, der ligger uden for rammen, som mærker på kanten: nærmeste pin for hver quest og guidens mål (fra som standard) |
| `/d2map route <on\|off>` | En pull-rute gennem hver klynge af quest-mål (til som standard) |
| `/d2map pull <0-60>` | Pull-afstand i yards: så langt fra de yderste mål må ruten ligge (standard 40; 0 = gennem dem) |
| `/d2map waypoint <on\|off>` | Grøn prikket streg til guidens næste sted: fra Factoruide, Shortest Path Forever eller spillets eget waypoint (til som standard) |
| `/d2map rotate <on\|off>` | Drej kortet, så det, figuren ser mod, er opad (til som standard; fra = nord opad) |
| `/d2map terrain <on\|off>` | Minimap-fliserne (**fra som standard**: kun pins og pilen) |
| `/d2map source <auto\|questie\|blizzard>` | Hvor pins kommer fra |
| `/d2map bind [tast]` | Læg en tast på toggle (Alt+M, hvis ingen nævnes) |
| `/d2map unlock` / `lock` | Flyt rammen med musen (hjulet zoomer); låst = click-through |
| `/d2map center`, `status`, `reset` | Tilbage til midten, hvad vises nu, alle defaults |

`/automap` er det samme som `/d2map`. Tastaturgenveje ligger under
**Key Bindings → D2Map** (toggle, zoom ind, zoom ud). Alt+M lægges på toggle
første gang, **hvis tasten er ledig** – eller peger på en addon, der er slået
fra eller slettet. Er den optaget af noget, der findes, siger addon'en det, og
`/d2map bind` overtager den.

Indstillingerne gemmes pr. figur i `D2MapDB`.

**Standarderne er Lars' egne** (skærmbillede 2026-11-11, version 1.5.2):
automappet er usynligt, når man står stille, og kommer frem med 54 %, når man
bevæger sig; 650 yards, drejer med figuren, ingen særskilt toning i combat,
og intet på kanten for det, der ligger uden for rammen (1.6.0).
En ny bruger ser altså ingenting, før figuren flytter sig.

## Filer

| Fil | Indhold |
|---|---|
| `D2Map/D2Map.toc` | Metadata, `SavedVariablesPerCharacter: D2MapDB`, Questie som valgfri afhængighed |
| `D2Map/D2Map.lua` | Hele addon'en, delt i 15 afsnit (defaults, koordinater, rammer, terræn, adaptere, pins, pull-ruter, guidens vej, fading, løkke, `Set()`, indstillingsvindue, kommandoer, events) |
| `D2Map/Bindings.xml` | De tre tastaturgenveje |
| `D2Map/Data/MinimapTiles.lua` | Fil-id'er for minimap-fliserne. **Genereret** af `scripts/byg-fliser.lua` |
| `D2Map/Media/*.tga` | Maskerne til de bløde kanter og prikken til guidens vej. **Genereret** af `scripts/byg-masker.py` |
| `scripts/pak.sh` | Pakker `dist/D2Map-<version>.zip` (mappen `D2Map/` med licens og noter) til CurseForge |
| `scripts/udgiv.py` | Uploader zip-filen til CurseForge (token fra `~/.config/d2map/curseforge.env`, `--toer` = tørløb) |
| `curseforge/` | Engelsk beskrivelse, logo og felterne til CurseForge-projektet |
| `test/tegn.lua` | Tegner pull-ruterne for fem prøvesæt, så man kan se dem (`docs/former.png`) |
| `test/koer.lua` | Testen: indlæser addon'en mod en attrap, der kun kender de API-metoder, addon'en må bruge |

## Sådan virker det

- **Terræn.** Forever kan tegne en minimap-flise ud fra dens fil-id
  (`texture:SetTexture(id)`). Tabellen `[kontinent][x * 64 + y] = fil-id`
  kommer fra OpenMap (MIT-licens, noten står øverst i datafilen). Hver flise er
  533,33 yards; de lægges i et gitter omkring spilleren og flyttes hver
  opdatering, mens selve teksturen først skiftes, når man går ind på en ny
  flise. Efter en patch med nye zoner: opdatér OpenMap og kør
  `lua scripts/byg-fliser.lua`.
- **Position.** `UnitPosition("player")` giver nord, vest og kontinent i yards.
  Den kan være en «secret value» i Forever, så alt går gennem `IsNumber`, og
  reserven er `C_Map.GetPlayerMapPosition` + `GetWorldPosFromMapPos`. Uden
  position (instances) er automappet tomt i stedet for at stå stille et
  forkert sted.
- **Koordinater.** Verden: første tal vokser mod nord, andet mod vest. Skærmen:
  `x = (spillerVest - punktVest) × px/yard`, `y = (punktNord - spillerNord) × px/yard`.
- **Questie.** Alle Questies kort-ikoner står i
  `LibStub("HereBeDragonsQuestie-Pins-2.0").worldmapPinRegistry[Questie]`.
  Hvert ikon har `x`, `y` (zone-procent), `UiMapID`, `data.Type`
  (`monster`/`object`/`item`/`event`/`complete`/`available`/`manual`), `texture`
  og `hidden` (Questies egne filtre). Adapteren læser kun; zone → verden huskes
  pr. ikon. Uden Questie bruges spillets egne quest-punkter
  (`C_QuestLog.GetQuestsOnMap`).
- **To takter.** Pins *hentes* fra adapteren én gang i sekundet og *flyttes*
  hvert 0,1 sekund. `OnUpdate` sidder på selve rammen, så et skjult automap
  koster ingenting.
- **Fading.** Tre tilstande giver et mål, og gennemsigtigheden glider derhen på
  0,35 sekund: står stille = `opacity`; bevæger sig = `moveOpacity` (hvis slået
  til – må gerne være højere end `opacity`); i combat = `combatOpacity`, dog
  aldrig mere end de to andre. Combat kommer fra `PLAYER_REGEN_DISABLED` /
  `PLAYER_REGEN_ENABLED`. Bevægelse afgøres på, om positionen har ændret sig
  siden sidste opdatering (virker på flyvepunkter og kræver ingen hemmelige
  værdier), og et stop på under 0,4 sekund tæller stadig som bevægelse, så
  kortet ikke blinker. Pins er dobbelt så synlige som terrænet (`pinBoost`).

- **Pull-ruter** (afsnit 8). Tredje udgave af «stregen»: først en korteste rute
  gennem hver mob (1.2), så en blød form *uden om* hver klynge (1.3), og nu en
  rute *inde i* klyngen (1.6). Lars: «jeg skal bare være i 30-50 yards afstand
  til det yderste punkt, så kan man pulle … der er ingen grund til at løbe for
  langt». Trinene:
  1. *Klynger*: mål inden for en lænkeafstand hører sammen. Afstanden er det
     dobbelte af median-afstanden til nærmeste nabo (60-150 yards, hele tiere).
     Under tre mål: ingen rute.
  2. *Omrids*: den konvekse skal.
  3. *Indhak*: en kant længere end lænkeafstanden graves ind til det nærmeste
     mål bag den, når kanten er over dobbelt så lang som dybden. Et mål må stå
     i omridset to gange, så en række mål bliver til et bånd.
  4. *Sammentrækning* (`PullLoop`): omridset er en elastik, hvor hvert hjørne er
     bundet til sit mål med en snor på pull-afstanden. Hvert hjørne søger midt
     mellem sine naboer, til snoren strammer. Et mål inde i klyngen, som ruten
     ikke når, får sit eget hjørne og sin egen snor (højst 30 af dem).
  5. *Blødgøring*: hver kant får et støttepunkt 30 yards fra hver ende, og så
     Chaikin. Uden støttepunkterne skar blødgøringen så meget af et hjørne med
     lange kanter, at hjørnets mål røg uden for pull-afstand.
  En klynge, der kan pulles fra ét sted, trækker sig sammen til et punkt og
  tegnes som en lille ring; en række mål bliver til en streg, der er kortere i
  begge ender. Ruterne ligger fast i verden og regnes kun om, når målene, zoomet
  eller pull-afstanden ændrer sig, eller spilleren har flyttet sig en kvart
  ramme. Se `docs/former.png`; justér `LOOP_…` og kør `lua test/tegn.lua`.
- **Guidens vej** (afsnit 9). `Factoruide.Pathing:Remaining(kontinent, nord,
  vest)` er den funktion, Factoruide selv tegner sin grønne prikkede streg ud
  fra (`Factoruide_Guide/PathLines.lua`): resten af vejen til guidens sted som
  `{ nord, vest }` i de samme verdenskoordinater som D2Map – uden om stejlt
  terræn, når guiden har planlagt det. D2Map kalder den højst ti gange i
  sekundet og tegner prikker hver 9. pixel, talt fra
  *målet*, så de står stille på jorden, mens man går. Prikken er D2Maps egen
  (`Media/dot.tga`, hvid med sort kant): Factoruides grå prik farvet grøn blev
  mørkegrøn og kunne ikke ses oven på spillet (Lars, 2026-11-11). Målet får et gult mærke;
  ligger det uden for rammen, sidder et mindre mærke på kanten. Er guiden skjult
  (`uiShown`), eller har Factoruide slået sin vej fra (`pathMode`), er der
  ingen streg. Andre guider: `D2Map.RegisterPathSource("navn", { name,
  IsAvailable(), GetPath(kontinent, nord, vest) })`.
- **Shortest Path Forever** (SPF, 2026-11-11). Når SPF er indlæst, overlader
  Factoruide vejen til den («Link Shortest Path Forever», til som standard), og
  `Pathing:Remaining` giver nil – stregen ville forsvinde. SPF's offentlige API
  (`ShortestPathForever.API.Journey()`) fortæller, om den guider, og hvor målet
  er, men udleverer med vilje ikke vejens punkter. Den sætter til gengæld
  spillets waypoint på det næste *knæk* på vejen (`guide.bend` i
  `Journey/JourneyGuide.lua`), og det læses med `C_Map.GetUserWaypoint`. Kilden
  `spf` tegner derfor stregen fra spilleren til næste knæk; uden waypoint (tæt
  på målet) lige til målet, hvis det er under 300 yards væk. `Journey()` bygger
  nye tabeller ved hvert kald og spørges højst én gang i sekundet. Sidste kilde,
  `waypoint`, er spillets waypoint uden nogen guide (et mærke sat på kortet).
  SPF er GPL-3.0; D2Map kalder kun dens API og kopierer ingen kode.
- **200 lokale.** Lua tillader højst 200 lokale variabler i én funktion, og
  hele filen er én. Afsnit 8 og 9 ligger derfor i `do … end`-blokke og viser
  kun deres funktioner udad. `luac -p` fanger grænsen; upvalues pr. funktion
  (højst 60 i spillets Lua 5.1, 255 i Lua 5.5) tjekkes med `luac -l`.
- **Rotation.** `SetViewAngle` sættes én gang pr. opdatering, og `ToScreen`
  drejer hvert punkt med uret med figurens retning, så fliser, pins og former er
  enige (også pull-ruterne). Fliserne drejes om deres egen midte og flyttes til den drejede plads.
  Mens figuren drejer, opdateres der hver frame (ellers hakker det); står den
  stille, er takten 0,1 sek. som før. Uden retning: nord opad.
- **Én vej ind.** Vinduet, kommandoerne og genvejene sætter alle værdier gennem
  `Set(key, value)` (afsnit 10), som klipper til intervallet, gør det, ændringen
  kræver (`AFTER`), og opdaterer vinduet. Ny indstilling = en linje i
  `DEFAULTS`, evt. en i `AFTER`, og et felt i `CreateOptions`.
- **Vinduet** bruger kun skabeloner, andre Forever-addons bruger i dag
  (`BasicFrameTemplateWithInset`, `UICheckButtonTemplate`,
  `OptionsSliderTemplate`, `UIPanelButtonTemplate`); testens attrap afviser alle
  andre.
- **Ændrede standarder** for figurer med gemte indstillinger går gennem
  `MigrateSettings` og `settingsVersion` (version 2: terræn fra).

## En anden kilde til pins (fx pfQuest)

Forever er en moderne klient, så det er Questie, der gælder her; pfQuest kører
kun på 1.12-klienter. Skal addon'en bruges et andet sted, registreres en kilde
uden at røre resten:

```lua
D2Map.RegisterAdapter("pfquest", {
    name = "pfQuest",
    IsAvailable = function() return pfMap ~= nil end,
    Collect = function(out, wants)
        -- for hver node: D2Map.EmitPin(out, n, kontinent, nord, vest, tekstur, r, g, b, "objective", questID)
        return n
    end,
})
```

På en 1.12-klient skal `PlayerPosition` og `ZoneToWorld` i afsnit 3 også
skiftes ud (ingen `C_Map`), og fliserne skal hentes med sti i stedet for fil-id.

## Afprøvet i spillet

Lars' skærmbilleder og tilbagemeldinger 2026-11-11: terræn, bløde runde kanter,
Questies pins og spillerens pil (1.0), indstillingsvinduet (1.1), klyngeformerne
(1.3), guidens vej (1.4) og den lyse grønne prik (1.5.1) virker. Ikke set i
spillet endnu: pull-ruterne og det samlede flueben for kanten (1.6.0), og
stregen til Shortest Path Forevers næste knæk (1.6.1) – især
klyngernes lænkeafstand er et gæt, indtil den er set mod flere af Questies
rigtige pins – og det er ikke afklaret, om `UnitPosition` er hemmelig i combat
(så er automappet tomt i combat).

Lua-fejl står i `_forever_/Logs/General.log` (`[E][Lua]`), også uden fejlvisning
slået til. Sker der en fejl i opdateringsløkken, skriver addon'en den én gang i
chatten og stopper, i stedet for ti fejl i sekundet.

DandyMap har sit eget automap på Alt+M. Kører begge, ligger de oven i hinanden.
Lars slog DandyMap fra 2026-11-11 (mappen ligger der stadig); tasten stod
tilbage på `DandyMap_AUTOMAP`, og D2Map overtager den ved første login.
