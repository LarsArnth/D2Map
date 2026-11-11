# D2Map

Et Diablo II-inspireret automap til **WoW: Forever** (interface 16001): spillets
egne minimap-fliser og Questies quest-pins, halvgennemsigtigt midt på skærmen
med nord opad og spilleren i midten. Rammen tager aldrig imod mus, så kamera,
bevægelse og targeting går lige igennem.

```sh
./installer.sh        # kopierer D2Map/ ind i spillets AddOns-mappe
lua test/koer.lua     # 63 tjek mod en attrap af WoW's API
```

Første gang skal spillet genstartes helt; derefter er `/reload` nok.

## Brug

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
| `/d2map terrain <on\|off>` | Minimap-fliserne |
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
| `D2Map/D2Map.lua` | Hele addon'en, delt i 11 afsnit (defaults, koordinater, rammer, terræn, adaptere, pins, fading, løkke, kommandoer, events) |
| `D2Map/Bindings.xml` | De tre tastaturgenveje |
| `D2Map/Data/MinimapTiles.lua` | Fil-id'er for minimap-fliserne. **Genereret** af `scripts/byg-fliser.lua` |
| `D2Map/Media/mask-*.tga` | Maskerne til de bløde kanter. **Genereret** af `scripts/byg-masker.py` |
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

## Ikke afprøvet i spillet endnu

Testen viser, at logikken holder (placering, kant-pins, fading, kommandoer,
hemmelige værdier). Den kan ikke vise, hvordan det ser ud. Det, der først ses i
spillet:

- om maskerne giver bløde kanter (ellers: `/d2map shape plain`),
- om `UnitPosition` er hemmelig i combat (så er automappet tomt i combat),
- om Questies ikoner får rigtigt billede og farve.

Lua-fejl står i `_forever_/Logs/General.log` (`[E][Lua]`), også uden fejlvisning
slået til. Sker der en fejl i opdateringsløkken, skriver addon'en den én gang i
chatten og stopper, i stedet for ti fejl i sekundet.

DandyMap har sit eget automap på Alt+M. Kører begge, ligger de oven i hinanden.
Lars slog DandyMap fra 2026-11-11 (mappen ligger der stadig); tasten stod
tilbage på `DandyMap_AUTOMAP`, og D2Map overtager den ved første login.
