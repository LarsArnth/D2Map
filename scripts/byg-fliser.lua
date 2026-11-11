-- Bygger D2Map/Data/MinimapTiles.lua ud fra OpenMaps flisetabel (MIT-licens).
--
--   lua scripts/byg-fliser.lua ["<sti til OpenMap/Data/Forever/Minimap.lua>"]
--
-- Kør den igen, når spillet har fået en patch med nye zoner, og OpenMap er
-- opdateret. Tabellen er [kontinent][x * 64 + y] = fil-id for minimap-flisen
-- (x løber mod øst, y mod syd, hver flise er 533,33 yards).

local kilde = arg[1]
    or "/Applications/World of Warcraft/_forever_/Interface/AddOns/OpenMap/Data/Forever/Minimap.lua"
local maal = arg[2] or "D2Map/Data/MinimapTiles.lua"

local chunk, fejl = loadfile(kilde)
if not chunk then
    io.stderr:write("Kan ikke læse " .. kilde .. ": " .. tostring(fejl) .. "\n")
    os.exit(1)
end

-- OpenMaps fil er en almindelig addon-fil: `local _, ns = ...` og så ns.MapMinimap = {...}
local ns = {}
chunk("OpenMap", ns)
local tabel = ns.MapMinimap
if type(tabel) ~= "table" then
    io.stderr:write("Fandt ikke ns.MapMinimap i " .. kilde .. "\n")
    os.exit(1)
end

-- Byggenummeret står i OpenMaps egen kommentar; tag det med, så man kan se alderen.
local build = "ukendt"
for linje in io.lines(kilde) do
    local b = linje:match("%(build ([%d%.]+)%)")
    if b then build = b break end
end

local ud = {}
local function skriv(s) ud[#ud + 1] = s end

skriv([[
-- Spillets minimap-fliser: [kontinent][x * 64 + y] = fil-id
-- (flise-x løber mod øst, flise-y mod syd; hver flise er 533,33 yards).
--
-- GENERERET af scripts/byg-fliser.lua – ret ikke i hånden.
-- Kilde: OpenMap (https://github.com/openmap-world/openmap), Data/Forever/Minimap.lua,
-- klient-build ]] .. build .. [[.
--
-- OpenMaps datatabeller er MIT-licenserede:
--
--   MIT License
--
--   Copyright (c) 2026 OpenMap contributors
--
--   Permission is hereby granted, free of charge, to any person obtaining a copy
--   of this software and associated documentation files (the "Software"), to deal
--   in the Software without restriction, including without limitation the rights
--   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--   copies of the Software, and to permit persons to whom the Software is
--   furnished to do so, subject to the following conditions:
--
--   The above copyright notice and this permission notice shall be included in all
--   copies or substantial portions of the Software.
--
--   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--   SOFTWARE.
--
-- Selve fliserne er Blizzards egne teksturer og ligger i spillet, ikke her.

local _, ns = ...

ns.Tiles = {
]])

local kontinenter = {}
for k in pairs(tabel) do kontinenter[#kontinenter + 1] = k end
table.sort(kontinenter)

local ialt = 0
for _, k in ipairs(kontinenter) do
    local noegler = {}
    for idx in pairs(tabel[k]) do noegler[#noegler + 1] = idx end
    table.sort(noegler)
    skriv(("\t[%d] = {\n"):format(k))
    local linje = {}
    for i, idx in ipairs(noegler) do
        linje[#linje + 1] = ("[%d]=%d,"):format(idx, tabel[k][idx])
        if #linje == 10 or i == #noegler then
            skriv("\t\t" .. table.concat(linje, " ") .. "\n")
            linje = {}
        end
    end
    skriv("\t},\n")
    ialt = ialt + #noegler
end
skriv("}\n")

local f = assert(io.open(maal, "w"))
f:write(table.concat(ud))
f:close()
print(("Skrev %s: %d fliser på %d kontinenter (build %s)"):format(maal, ialt, #kontinenter, build))
