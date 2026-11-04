-- ---------------------------------------------------------------------------
-- merge_levels.lua — picks the shipped levels from gen_levels.lua's output.
--
-- usage: luajit merge_levels.lua classics.txt cand1.txt cand2.txt ...
--
-- Candidates are split into four bands by optimal moves. In each band the
-- picker goes round the move counts (so a band covers its whole range evenly)
-- and, within one count, round the block sets (so no set dominates), in a
-- fixed pseudo-random order: the output is deterministic. Every pick is solved
-- again with the forward search the game uses, which must find exactly the
-- same optimum. Bands are written sorted by optimal count.
--
-- Each line also carries that search's solution, packed by Solver.packPath,
-- so the game gives hints along it without searching.
-- ---------------------------------------------------------------------------

local here = arg[0]:match("(.*[/\\])") or "./"
package.path = here .. "../?.lua;" .. package.path
local S = require("solver")

local PER_BAND = 400
local BANDS = {
    { id = "easy",   lo = 5,  hi = 15 },
    { id = "medium", lo = 16, hi = 35 },
    { id = "hard",   lo = 36, hi = 60 },
    { id = "expert", lo = 61, hi = 999 },
}

local function hash(s)
    local h = 2166136261
    for i = 1, #s do h = ((h * 16777619) + s:byte(i)) % 4294967296 end
    return h
end

-- Solves `str` again: its optimal count must be `d` (when given). Returns the
-- count and the packed solution.
local function check(str, d)
    local blocks = assert(S.parse(str))
    local path = S.solve(blocks, 2000000)
    local got = path and #path
    if d and got ~= d then error(("%s: stated %s, solver says %s"):format(str, tostring(d), tostring(got))) end
    assert(got, "unsolvable " .. str)
    local packed = assert(S.packPath(blocks, path))
    assert(#assert(S.unpackPath(blocks, packed, got)) == got)
    return got, packed
end

-- Classics first.
local classics = {}
for line in io.lines(arg[1]) do
    local str, name = line:match("^(%S+) (.+)$")
    if str and not line:match("^#") then
        local d, packed = check(str)
        classics[#classics + 1] = { str = str, d = d, packed = packed, name = name }
    end
end
print("# classic " .. #classics)
for _, c in ipairs(classics) do print(c.str .. " " .. c.d .. " " .. c.packed .. " " .. c.name) end

-- Candidates, bucketed by band, then optimal count, then block set.
local seen = {}
for _, c in ipairs(classics) do
    seen[c.str] = true
    seen[S.mirror(c.str)] = true
end
local buckets = {}
for b = 1, #BANDS do buckets[b] = {} end
for k = 2, #arg do
    local set = arg[k]:match("([^/\\]+)%.txt$") or arg[k]
    for line in io.lines(arg[k]) do
        local str, d = line:match("^(%S+) (%d+)")
        d = tonumber(d)
        if str and not seen[str] then
            seen[str] = true
            for b, band in ipairs(BANDS) do
                if d >= band.lo and d <= band.hi then
                    local byd = buckets[b]
                    byd[d] = byd[d] or {}
                    byd[d][set] = byd[d][set] or {}
                    local t = byd[d][set]
                    t[#t + 1] = { str = str, d = d, h = hash(str) }
                end
            end
        end
    end
end

for b, band in ipairs(BANDS) do
    -- Per count: the block sets in a fixed order, each list shuffled by hash.
    local counts = {}
    for d, sets in pairs(buckets[b]) do
        local names = {}
        for name, list in pairs(sets) do
            table.sort(list, function(x, y) return x.h < y.h end)
            names[#names + 1] = name
        end
        table.sort(names)
        counts[#counts + 1] = { d = d, sets = sets, names = names, turn = 0 }
    end
    table.sort(counts, function(x, y) return x.d < y.d end)
    local function takeOne(c)
        for _ = 1, #c.names do
            c.turn = c.turn % #c.names + 1
            local list = c.sets[c.names[c.turn]]
            if #list > 0 then return table.remove(list, 1) end
        end
    end
    local picked = {}
    local progress = true
    while #picked < PER_BAND and progress do
        progress = false
        for _, c in ipairs(counts) do
            if #picked >= PER_BAND then break end
            local lv = takeOne(c)
            if lv then picked[#picked + 1] = lv; progress = true end
        end
    end
    table.sort(picked, function(x, y)
        if x.d ~= y.d then return x.d < y.d end
        return x.h < y.h
    end)
    print("# " .. band.id .. " " .. #picked)
    for _, lv in ipairs(picked) do
        local _, packed = check(lv.str, lv.d)
        print(lv.str .. " " .. lv.d .. " " .. packed)
    end
    io.stderr:write(band.id .. ": " .. #picked .. "\n")
end
