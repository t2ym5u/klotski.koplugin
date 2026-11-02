-- ---------------------------------------------------------------------------
-- gen_levels.lua — offline candidate generator for Klotski levels.
--
-- usage: luajit gen_levels.lua <nV> <nH> <nS> <nEmpty> [max_cluster]
--
-- For one block set (one 2×2 plus nV vertical, nH horizontal and nS small
-- blocks, nEmpty empty squares), enumerates EVERY legal layout of the 4×5
-- tray, splits them into clusters (layouts reachable from one another), and
-- in each cluster that contains a solved layout runs one breadth-first search
-- from all solved layouts at once, which gives every layout its exact optimal
-- move count.
--
-- A candidate level is a layout whose optimal count is a local maximum: no
-- single move leads to a layout that is further from solved, so the level is
-- never just the middle of a longer one. Mirror images are merged (the goal is
-- symmetric). Clusters larger than max_cluster (default 100000) are skipped:
-- the hint search on the reader explores at most one whole cluster.
--
-- Prints one line per candidate: "<20-char board> <optimal> <cluster size>".
-- ---------------------------------------------------------------------------

local here = arg[0]:match("(.*[/\\])") or "./"
package.path = here .. "../?.lua;" .. package.path
local S = require("solver")

local nV, nH, nS, nE = tonumber(arg[1]), tonumber(arg[2]), tonumber(arg[3]), tonumber(arg[4])
local max_cluster = tonumber(arg[5] or 100000)
assert(nV and nH and nS and nE and 4 + 2 * nV + 2 * nH + nS + nE == 20, "block counts must fill 20 squares")
local W, H = S.W, S.H

-- Every legal layout, as keys.
local taken = {}
for i = 0, W * H - 1 do taken[i] = false end
local left = { [0] = nE, [1] = nS, [2] = nV, [3] = nH, [4] = 1 }
local blocks, all = {}, {}
local function fill(i)
    while i < W * H and taken[i] do i = i + 1 end
    if i == W * H then all[#all + 1] = S.encode(blocks) return end
    if left[0] > 0 then
        left[0] = left[0] - 1; taken[i] = true
        fill(i + 1)
        taken[i] = false; left[0] = left[0] + 1
    end
    for code = 1, 4 do
        local sh = S.SHAPE[code]
        local r, c = math.floor(i / W), i % W
        if left[code] > 0 and r + sh.h <= H and c + sh.w <= W then
            local cells = S.cellsOf(code, i)
            local ok = true
            for _, x in ipairs(cells) do if taken[x] then ok = false end end
            if ok then
                left[code] = left[code] - 1
                for _, x in ipairs(cells) do taken[x] = true end
                blocks[#blocks + 1] = { code = code, a = i }
                fill(i + 1)
                blocks[#blocks] = nil
                for _, x in ipairs(cells) do taken[x] = false end
                left[code] = left[code] + 1
            end
        end
    end
end
fill(0)

local seen = {}
local out = {}
for _, k in ipairs(all) do
    if not seen[k] then
        local states, dist = S.cluster(k, nil, seen)
        if dist and #states <= max_cluster then
            for _, s in ipairs(states) do
                local d = dist[s]
                if d and d >= 3 then
                    local localmax = true
                    S.eachMove(s, function(_, _, nk)
                        if (dist[nk] or -1) > d then localmax = false end
                    end)
                    if localmax then
                        local str = S.format(S.blocksOf(s))
                        local m = S.mirror(str)
                        if m < str then str = m end
                        if not out[str] then
                            out[str] = true
                            print(str .. " " .. d .. " " .. #states)
                        end
                    end
                end
            end
        end
    end
end
