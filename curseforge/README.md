# CurseForge

Projektet har id **1798915** (https://authors.curseforge.com/#/projects/1798915/files),
oprettet af Lars 2026-11-11. Felterne herunder er dem, projektet blev oprettet
med. Uploadet med `scripts/udgiv.py`:

| Version | Dato | CurseForges fil-id |
|---|---|---|
| 1.5.1 | 2026-11-11 | 9562101 |
| 1.5.2 | 2026-11-11 | 9562470 |

| Felt | Værdi |
|---|---|
| Spil | World of Warcraft |
| Type | Addon |
| Navn | D2Map |
| Resumé (højst 120 tegn) | Diablo II-style automap: a click-through, see-through quest map in the middle of your screen. |
| Beskrivelse | `beskrivelse.md` (engelsk; CurseForge kan tage Markdown) |
| Logo | `logo.png` (512 × 512, tegnet af `logo.svg`) |
| Kategori | Map & Minimap; evt. også Quests & Leveling |
| Licens | MIT License |
| Kildekode | https://github.com/LarsArnth/D2Map |
| Issues | https://github.com/LarsArnth/D2Map/issues |

Fil til upload: `dist/D2Map-<version>.zip` fra `./scripts/pak.sh`. Vælg
spilversionen for **WoW: Forever** (interface 16001), og «Release».
Valgfri afhængighed: Questie.

## Upload med script

Når projektet findes, kan nye versioner uploades uden om websiden:

```sh
./scripts/pak.sh
./scripts/udgiv.py --toer      # viser spilversion og metadata, uploader intet
./scripts/udgiv.py             # uploader som «release»
```

Scriptet skal bruge projektets id (`## X-Curse-Project-ID:` i toc-filen eller
`--projekt <id>`) og et API-token fra authors.curseforge.com → API Tokens.
Tokenet ligger i `~/.config/d2map/curseforge.env` som
`CURSEFORGE_API_TOKEN=…` (chmod 600) – aldrig i repoet. API'et kan ikke oprette
selve projektet. Valgfri afhængighed: `questie` (listen `VALGFRIE` i
scriptet). Factoruide ligger ikke på CurseForge og kan derfor ikke angives.

Nye projekter og filer bliver gennemset af CurseForge, før de bliver synlige.
Id'et står i `D2Map/D2Map.toc` (`## X-Curse-Project-ID`), så CurseForge-appen
genkender addon'en. Ændringsloggen til hver version ligger her som
`aendringer-<version>.md` og gives til scriptet med
`--aendringer "$(cat curseforge/aendringer-<version>.md)"`.
