-- Tegner formerne om klynger af mål for nogle prøvesæt, så man kan SE, hvad
-- algoritmen i D2Map.lua (afsnit 8) gør – tal siger ikke, om en form er pæn.
--
--   lua test/tegn.lua [mappe]                 (fra projektets rod; standard: docs)
--   rsvg-convert -w 1500 docs/former.svg -o docs/former.png
--
-- Scriptet genbruger attrappen af WoW's API fra test/koer.lua (alt før
-- «print("Terræn")») og læser de linjestykker, addon'en ville have tegnet.

local mappe = arg[1] or "docs"
local kilde = assert(io.open("test/koer.lua")):read("a")
local slut = assert(kilde:find('print("Terræn")', 1, true), "fandt ikke mærket i test/koer.lua")
-- Hjælperne i koer.lua er lokale, så scenarierne herunder hænges på samme
-- stykke kode og køres sammen med det.
local selv = assert(io.open(arg[0])):read("a")
local maerke = "--[[" .. "SCENARIER]]"
local scenarier = selv:sub(select(2, assert(selv:find(maerke, 1, true))) + 1)
assert(load(kilde:sub(1, slut - 1) .. "\nlocal mappe = ...\n" .. scenarier, "=tegn"))(mappe)
do return end

--[[SCENARIER]]
local navne, svg = {}, {}
local function scenarie(navn, punkter, span)
    D2Map.RegisterAdapter("tegn", {
        name = "tegn",
        IsAvailable = function() return true end,
        Collect = function(out)
            for i, m in ipairs(punkter) do
                D2Map.EmitPin(out, i, 0, spiller.nord + m[2], spiller.vest - m[1], "p.blp", 1, 1, 1, "objective", 1)
            end
            return #punkter
        end,
    })
    SlashCmdList.D2MAP("source tegn")
    SlashCmdList.D2MAP("shape square")
    SlashCmdList.D2MAP("zoom " .. span)
    kor(1.3)
    local k = 560 / span
    local ud = { '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-300 -300 600 600" width="900" height="900"><rect x="-300" y="-300" width="600" height="600" fill="#1e1e1e"/>' }
    for _, l in ipairs(linjer()) do
        ud[#ud + 1] = ('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#f2cc59" stroke-width="2"/>'):format(l.fra.x, -l.fra.y, l.til.x, -l.til.y)
    end
    for _, m in ipairs(punkter) do
        ud[#ud + 1] = ('<circle cx="%.1f" cy="%.1f" r="3.5" fill="#fff"/>'):format(m[1] * k, -m[2] * k)
    end
    ud[#ud + 1] = '<text x="-290" y="-278" fill="#aaa" font-size="14" font-family="sans-serif">' .. navn .. ' – ' .. #linjer() .. ' linjestykker</text></svg>'
    local f = io.open(mappe .. "/" .. navn .. ".svg", "w") f:write(table.concat(ud, "\n")) f:close()
    SlashCmdList.D2MAP("status")
    print(navn .. ": " .. chat[#chat]:gsub("^.-outlines: on, ", ""))
    navne[#navne + 1] = navn
    svg[navn] = table.concat(ud, "\n")
end

-- A: to lejre og tre enlige
scenarie("a-lejre", {
    {-180, 120}, {-140, 150}, {-110, 110}, {-150, 80}, {-90, 160}, {-60, 120}, {-100, 60}, {-190, 60},
    {140, -100}, {180, -130}, {200, -80}, {160, -160}, {120, -140},
    {20, 10}, {240, 180}, {-220, -170}, {-20, 150},
}, 700)
-- B: en bananformet klynge
local banan = {}
for i = 0, 15 do
    local v = math.pi * (0.1 + 0.8 * i / 15)
    banan[#banan + 1] = { math.cos(v) * 200 + (i % 3 - 1) * 8, math.sin(v) * 200 - 110 + (i % 2) * 14 }
end
scenarie("b-banan", banan, 700)
-- C: en tæt mark og en lejr langt væk
local mark = {}
for x = 0, 6 do for y = 0, 4 do mark[#mark + 1] = { -230 + x * 38 + (y % 2) * 15, -40 + y * 34 + (x % 3) * 6 } end end
for _, p in ipairs({ {170, -190}, {210, -160}, {230, -210}, {190, -240} }) do mark[#mark + 1] = p end
scenarie("c-mark", mark, 700)
-- D: punkterne fra Lars' skitse (2000 x 1360 px → yards)
local skitse = {}
for _, p in ipairs({ {110,125},{310,207},{663,80},{1245,122},{1000,225},{716,300},{1168,375},{432,465},{845,573},{190,725},{463,737},{659,730},{1167,698},{1027,953},{1332,1084},{1358,1270},{1681,770},{1518,950},{1797,1125},{1670,1230},{1920,946},{1886,1315} }) do
    skitse[#skitse + 1] = { (p[1] - 1000) * 0.3, (680 - p[2]) * 0.3 }
end
scenarie("d-skitse", skitse, 700)

-- E: en ren bue (alle mål på skallen) og en vej (næsten ret linje)
local bue = {}
for i = 0, 12 do local v = math.pi * (0.1 + 0.8 * i / 12) bue[#bue + 1] = { math.cos(v) * 170, math.sin(v) * 170 + 40 } end
for i = 0, 7 do bue[#bue + 1] = { -210 + i * 40, -190 + (i % 2) * 10 + i * 6 } end
scenarie("e-bue", bue, 700)

-- Alle prøvesæt samlet i ét billede, tre i bredden.
local raekker = math.ceil(#navne / 3)
local samlet = { ('<svg xmlns="http://www.w3.org/2000/svg" width="1800" height="%d" viewBox="0 0 1800 %d"><rect width="1800" height="%d" fill="#1e1e1e"/>'):format(raekker * 600, raekker * 600, raekker * 600) }
for i, navn in ipairs(navne) do
    samlet[#samlet + 1] = (svg[navn]:gsub('width="900" height="900"', ('x="%d" y="%d" width="600" height="600"'):format((i - 1) % 3 * 600, math.floor((i - 1) / 3) * 600), 1))
    os.remove(mappe .. "/" .. navn .. ".svg")
end
samlet[#samlet + 1] = "</svg>"
local f = assert(io.open(mappe .. "/former.svg", "w"))
f:write(table.concat(samlet, "\n"))
f:close()
print("Skrev " .. mappe .. "/former.svg")
