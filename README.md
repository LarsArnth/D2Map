# D2Map

Et Diablo II-inspireret automap til **WoW: Forever** (interface 16001): spillets
egne minimap-fliser og Questies quest-pins, halvgennemsigtigt midt på skærmen
med nord opad og spilleren i midten. Rammen tager aldrig imod mus, så kamera,
bevægelse og targeting går lige igennem.

```sh
./installer.sh        # kopierer D2Map/ ind i spillets AddOns-mappe
lua test/koer.lua     # 137 tjek mod en attrap af WoW's API
lua test/tegn.lua     # tegner formerne for nogle prøvesæt til docs/former.svg
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
| `/d2map opacity <0-100>` | Gennemsigtighed uden for combat (standard 40) |
| `/d2map combat <0-100\|on\|off>` | Gennemsigtighed i combat (standard 18), eller slå toningen fra |
| `/d2map zoom <yards\|in\|out>` | Hvor mange yards rammen dækker (standard 500) |
| `/d2map size <pixels>` | Rammens størrelse (standard 560) |
| `/d2map shape <round\|square\|plain>` | Bløde kanter som cirkel eller firkant; `plain` = ingen maske |
| `/d2map style <color\|sepia\|ghost>` | `ghost` lægger terrænet additivt ovenpå, mest som i Diablo II |
| `/d2map pins <all\|objectives\|off>` | Alle Questies pins, kun mål og afleveringer, eller ingen |
| `/d2map pinsize <0.5-3>` | Størrelse på pins |
| `/d2map edge <on\|off>` | Nærmeste pin for hver quest vises på kanten, når den ligger uden for |
| `/d2map outlines <on\|off>` | En blød form om hver klynge af quest-mål (til som standard; `route` er det gamle navn og virker også) |
| `/d2map waypoint <on\|off>` | Guidens vej: Factoruides grønne prikkede streg til næste sted (til som standard) |
| `/d2map rotate <on\|off>` | Drej kortet, så det, figuren ser mod, er opad (fra som standard: nord opad) |
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

## Filer

| Fil | Indhold |
|---|---|
| `D2Map/D2Map.toc` | Metadata, `SavedVariablesPerCharacter: D2MapDB`, Questie som valgfri afhængighed |
| `D2Map/D2Map.lua` | Hele addon'en, delt i 15 afsnit (defaults, koordinater, rammer, terræn, adaptere, pins, klyngeformer, guidens vej, fading, løkke, `Set()`, indstillingsvindue, kommandoer, events) |
| `D2Map/Bindings.xml` | De tre tastaturgenveje |
| `D2Map/Data/MinimapTiles.lua` | Fil-id'er for minimap-fliserne. **Genereret** af `scripts/byg-fliser.lua` |
| `D2Map/Media/mask-*.tga` | Maskerne til de bløde kanter. **Genereret** af `scripts/byg-masker.py` |
| `test/tegn.lua` | Tegner klyngeformerne for fem prøvesæt, så man kan se dem (`docs/former.png`) |
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
- **Fading.** `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` sætter et mål, og
  gennemsigtigheden glider derhen på 0,35 sekund. Pins er dobbelt så synlige som
  terrænet (`pinBoost`).

- **Former om klynger** (afsnit 8). Først var det en streg gennem hvert mål
  (korteste rute, version 1.2), men Lars ville ikke ramme hver mob: «tegn en
  form som er tættest på alle pletter som muligt, gerne i clustre». Nu:
  1. *Klynger*: mål inden for en lænkeafstand hører sammen. Afstanden er det
     dobbelte af median-afstanden til nærmeste nabo (60-150 yards, hele tiere),
     så det passer til både tætte og spredte pins. Under tre mål: ingen form.
  2. *Omrids*: den konvekse skal.
  3. *Indhak*: en kant længere end lænkeafstanden graves ind til det nærmeste
     mål bag den, når kanten er over dobbelt så lang som dybden, og målet ikke
     ligger tættere på en nabokant. Et mål må stå i omridset to gange – det gør
     en række mål langs en vej til et bånd (ud og tilbage).
  4. *Blødgøring*: Chaikin. Kurven ender i (A + 6V + B)/8 ved hjørnet V, så
     hjørnet flyttes først til V + 4/3·margen·n + (2V − A − B)/6; så går
     kurven 12 yards uden om målet.
  Formerne ligger fast i verden og regnes kun om, når målene ændrer sig
  (fingeraftryk af hele tal), zoomet ændres, eller spilleren har flyttet sig en
  kvart ramme. Stykker uden for rammen tegnes ikke. Se `docs/former.png`;
  justér konstanterne `LOOP_…` og kør `lua test/tegn.lua` for at se virkningen.
- **Guidens vej** (afsnit 9). `Factoruide.Pathing:Remaining(kontinent, nord,
  vest)` er den funktion, Factoruide selv tegner sin grønne prikkede streg ud
  fra (`Factoruide_Guide/PathLines.lua`): resten af vejen til guidens sted som
  `{ nord, vest }` i de samme verdenskoordinater som D2Map – uden om stejlt
  terræn, når guiden har planlagt det. D2Map kalder den højst ti gange i
  sekundet og tegner prikker (samme tekstur og farve) hver 9. pixel, talt fra
  *målet*, så de står stille på jorden, mens man går. Målet får et gult mærke;
  ligger det uden for rammen, sidder et mindre mærke på kanten. Er guiden skjult
  (`uiShown`), eller har Factoruide slået sin vej fra (`pathMode`), er der
  ingen streg. Andre guider: `D2Map.RegisterPathSource("navn", { name,
  IsAvailable(), GetPath(kontinent, nord, vest) })`.
- **200 lokale.** Lua tillader højst 200 lokale variabler i én funktion, og
  hele filen er én. Afsnit 8 og 9 ligger derfor i `do … end`-blokke og viser
  kun deres funktioner udad. `luac -p` fanger grænsen; upvalues pr. funktion
  (højst 60 i spillets Lua 5.1, 255 i Lua 5.5) tjekkes med `luac -l`.
- **Rotation.** `SetViewAngle` sættes én gang pr. opdatering, og `ToScreen`
  drejer hvert punkt med uret med figurens retning, så fliser, pins og former er
  enige (også klyngeformerne). Fliserne drejes om deres egen midte og flyttes til den drejede plads.
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

Lars' skærmbilleder 2026-11-11: terræn, bløde runde kanter, Questies pins og
spillerens pil (1.0) og indstillingsvinduet (1.1) virker. Rotationen (1.2) og
klyngeformerne (1.3) og guidens vej (1.4) er ikke set i spillet endnu – især lænkeafstanden er et
gæt, indtil den er set mod Questies rigtige pins – og det er ikke afklaret, om
`UnitPosition` er hemmelig i combat (så er automappet tomt i combat).

Lua-fejl står i `_forever_/Logs/General.log` (`[E][Lua]`), også uden fejlvisning
slået til. Sker der en fejl i opdateringsløkken, skriver addon'en den én gang i
chatten og stopper, i stedet for ti fejl i sekundet.

DandyMap har sit eget automap på Alt+M. Kører begge, ligger de oven i hinanden.
Lars slog DandyMap fra 2026-11-11 (mappen ligger der stadig); tasten stod
tilbage på `DandyMap_AUTOMAP`, og D2Map overtager den ved første login.
