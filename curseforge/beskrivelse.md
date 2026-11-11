# D2Map

A Diablo II-style automap for **WoW: Forever**: a see-through map in the middle of your screen that shows where your quest targets are, without ever getting in the way. It never takes mouse input, so camera, movement and targeting go straight through it.

Out of the box the map is hidden while you stand still and fades in when you move. Type `/d2map` to open the options window and change that.

## What it shows

- **Quest pins** from Questie around your character, with Questie's own icons, colours and filters.
- **Pull routes**: a short loop through each group of quest objectives, placed so that every target is within pull range (40 yards by default). Run the loop and pull from it instead of walking up to every mob. A small camp becomes a single spot to stand on.
- **The guide path** from Factoruide as a bright dotted line to the guide's next place.
- **Out-of-range markers** (optional, off by default): quest targets and the guide's goal that are off the map shown as small markers on the rim.
- **Terrain** (optional, off by default): the game's own minimap tiles, with soft round or square edges and three looks (colour, sepia, ghost).
- **Your character** as an arrow in the middle. The map turns with the way you face, or stays north up.

## Staying out of the way

- Click-through at all times. Unlock it in the options to drag it somewhere else or zoom with the mouse wheel.
- Three opacity levels: standing still, moving, and in combat. By default it is invisible when you stand still and shows while you move; a separate combat level is there if you want it.
- Hidden costs nothing: the update loop only runs while the map is shown.

## Options and commands

`/d2map` opens a window with every setting. The same settings exist as commands (`/d2map help`), and there are key bindings for toggle, zoom in and zoom out under Key Bindings > D2Map. Alt+M is bound to toggle on first login if the key is free.

Settings are saved per character.

## Works with

- **Questie** (optional): quest pins. Without Questie, D2Map falls back to the game's own quest markers, one per quest.
- **Factoruide Guide** (optional): the guide path.

Other addons can add their own pins and paths through `D2Map.RegisterAdapter` and `D2Map.RegisterPathSource`.

## Good to know

- Instances hide your position from addons, so the map is empty there.
- Terrain covers Eastern Kingdoms and Kalimdor. Other maps show pins only.
- The addon is new. If something looks wrong, please open an issue on GitHub.

## Credits

The minimap tile table comes from [OpenMap](https://github.com/openmap-world/openmap) (MIT licensed). The tiles themselves are Blizzard's art and are loaded from the game.

Source and issues: https://github.com/LarsArnth/D2Map (MIT licence)
