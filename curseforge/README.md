# CurseForge

Det, der skal bruges for at oprette og opdatere projektet på CurseForge
(forfatter-portalen: https://authors.curseforge.com).

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
Valgfrie afhængigheder: Questie og Factoruide Guide.

Nye projekter bliver gennemset af CurseForge, før de bliver synlige.

Når projektet har fået et id, kan det skrives i `D2Map/D2Map.toc` som
`## X-Curse-Project-ID: <id>`, så CurseForge-appen genkender addon'en.
