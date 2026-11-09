local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

-- Trays are written row by row (4 squares each), see solver.lua.
local function rows(...)
    return table.concat({ ... })
end

local CLASSIC = rows("^AA^", "vAAv", "^<>^", "voov", "o..o")
-- Two moves, only because a small block may turn a corner in one move: the
-- one in the way goes down then left, then the 2×2 drops.
local CORNER = rows("<><>", "^AA^", "vAAv", "oo.^", "...v")

describe("Solver", function()
    local Solver
    setup(function() Solver = require("solver") end)

    it("parses and formats a level string", function()
        local blocks = assert(Solver.parse(CLASSIC))
        assert.are.equal(10, #blocks)
        assert.are.same({ code = 4, a = 1 }, blocks[1])   -- the 2×2 first
        assert.are.same({ code = 2, a = 0 }, blocks[2])   -- then reading order
        assert.are.equal(CLASSIC, Solver.format(blocks))
        assert.are.equal(CLASSIC, Solver.format(Solver.blocksOf(Solver.encode(blocks))))
        assert.are.equal(rows("^AA^", "vAAv", "^<>^", "voov", "o..o"), Solver.mirror(CLASSIC))
        assert.are.equal(rows("..<>", "...o", "....", "....", "...."),
            Solver.mirror(rows("<>..", "o...", "....", "....", "....")))
    end)

    it("rejects malformed levels", function()
        assert.is_nil(Solver.parse("too short"))
        assert.is_nil(Solver.parse(rows("....", "....", "....", "....", "....")))      -- no 2×2
        assert.is_nil(Solver.parse(rows("AA..", "A...", "....", "....", "....")))      -- broken 2×2
        assert.is_nil(Solver.parse(rows("AA..", "AA..", "..AA", "..AA", "....")))      -- two 2×2
        assert.is_nil(Solver.parse(rows("AA^.", "AA..", "....", "....", "....")))      -- half a vertical
        assert.is_nil(Solver.parse(rows("AA.<", "AA..", "....", "....", "....")))      -- out of the tray
        assert.is_nil(Solver.parse(rows("AAoo", "AAoo", "oooo", "oooo", "oooo")))      -- no gap
    end)

    it("finds the optimal count on hand-made cases", function()
        local function dist(s) return Solver.distance(assert(Solver.parse(s))) end
        assert.are.equal(0, dist(rows("....", "....", "....", ".AA.", ".AA.")))
        -- One move, any distance.
        assert.are.equal(1, dist(rows(".AA.", ".AA.", "....", "....", "....")))
        assert.are.equal(2, dist(CORNER))
        -- Walled in for good.
        assert.is_nil((dist(rows("AA^o", "AAvo", "<><>", "<><>", "<>o."))))
    end)

    it("counts a move round a corner as one move", function()
        local blocks = assert(Solver.parse(CORNER))
        local s = 0
        for i, b in ipairs(blocks) do if b.a == 13 then s = i end end
        local reach = Solver.reach(blocks, s)
        table.sort(reach)
        -- Right, down, down-right and down-then-left.
        assert.are.same({ 14, 16, 17, 18 }, reach)
    end)

    it("knows the famous optimum of the traditional layouts", function()
        local function dist(s) return Solver.distance(assert(Solver.parse(s))) end
        assert.are.equal(81, dist(CLASSIC))                                  -- the Red Donkey
        assert.are.equal(70, dist(rows("^AA^", "vAAv", "o<>o", "^oo^", "v..v")))
        assert.are.equal(60, dist(rows("^AA^", "vAAv", "oooo", "^<>^", "v..v")))
        assert.are.equal(72, dist(rows("oAAo", "^AA^", "v<>v", "^oo^", "v..v")))
    end)

    it("agrees with an independent iterative-deepening search", function()
        -- Plain DFS over the rules, on the level string, without the packed
        -- states: a move is a block going anywhere its own flood fill reaches.
        local W, H = 4, 5
        local function blocksOfStr(s)
            local t, taken = {}, {}
            for i = 0, 19 do
                local ch = s:sub(i + 1, i + 1)
                if not taken[i] and ch ~= "." then
                    local w = (ch == "A" or ch == "<") and 2 or 1
                    local h = (ch == "A" or ch == "^") and 2 or 1
                    for dr = 0, h - 1 do for dc = 0, w - 1 do taken[i + dr * W + dc] = true end end
                    t[#t + 1] = { r = math.floor(i / W), c = i % W, w = w, h = h, ch = ch }
                end
            end
            return t
        end
        local function render(bl)
            local g = {}
            for i = 1, 20 do g[i] = "." end
            for _, b in ipairs(bl) do
                for dr = 0, b.h - 1 do for dc = 0, b.w - 1 do
                    local ch = b.ch
                    if ch == "^" and dr == 1 then ch = "v" end
                    if ch == "<" and dc == 1 then ch = ">" end
                    g[(b.r + dr) * W + b.c + dc + 1] = ch
                end end
            end
            return table.concat(g)
        end
        local function solved(bl)
            for _, b in ipairs(bl) do if b.ch == "A" then return b.r == 3 and b.c == 1 end end
        end
        local function free(bl, k, r, c)
            local b = bl[k]
            if r < 0 or c < 0 or r + b.h > H or c + b.w > W then return false end
            for j, o in ipairs(bl) do
                if j ~= k and r < o.r + o.h and o.r < r + b.h and c < o.c + o.w and o.c < c + b.w then
                    return false
                end
            end
            return true
        end
        local function ids(bl, limit)
            if solved(bl) then return true end
            if limit == 0 then return false end
            for k, b in ipairs(bl) do
                local r0, c0 = b.r, b.c
                local seenp, q = { [r0 * 10 + c0] = true }, { { r0, c0 } }
                local h = 1
                while q[h] do
                    local r, c = q[h][1], q[h][2]
                    h = h + 1
                    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
                        local nr, nc = r + d[1], c + d[2]
                        if not seenp[nr * 10 + nc] and free(bl, k, nr, nc) then
                            seenp[nr * 10 + nc] = true
                            q[#q + 1] = { nr, nc }
                        end
                    end
                end
                for i = 2, #q do
                    b.r, b.c = q[i][1], q[i][2]
                    local ok = ids(bl, limit - 1)
                    b.r, b.c = r0, c0
                    if ok then return true end
                end
            end
            return false
        end
        local Levels = require("levels")
        local cases = { CORNER, Levels.get("easy", 1).str, Levels.get("easy", 2).str, Levels.get("easy", 3).str }
        for _, s in ipairs(cases) do
            local d = Solver.distance(assert(Solver.parse(s)))
            assert.is_truthy(d, s)
            assert.is_true(d <= 5, s)
            local bl = blocksOfStr(s)
            assert.are.equal(s, render(bl))
            local found
            for k = 0, d do
                if ids(bl, k) then found = k break end
            end
            assert.are.equal(d, found, s)
        end
    end)
end)

describe("KlotskiBoard", function()
    local Board, Solver
    setup(function()
        Board  = require("board")
        Solver = require("solver")
    end)

    it("moves blocks only into reachable squares, the nearer place first", function()
        local b = Board:new{ level = CLASSIC, optimal = 81 }
        local v = b:blockAt(3, 1)          -- the vertical on rows 3-4, column 1
        assert.are.equal("V", b:kindOf(v))
        assert.are.same({}, b:reach(v))    -- (5,1) holds a small block
        local s = b:blockAt(5, 1)
        assert.are.equal("S", b:kindOf(s))
        assert.are.equal(17, b:targetFor(s, 5, 2))
        assert.are.equal(18, b:targetFor(s, 5, 3))
        assert.is_nil(b:targetFor(s, 4, 2))   -- taken
        assert.is_nil(b:targetFor(s, 5, 1))   -- under it
        assert.is_false(b:move(s, 19))        -- (5,4) holds a block
        assert.are.equal(0, b:getMoves())
        -- Swipe: straight, as far as it goes.
        assert.is_true(b:slide(s, "right"))
        assert.are.equal(18, b.blocks[s].a)
        -- A vertical with two free squares under it: the nearer place covers
        -- the first one.
        local b2 = Board:new{ level = rows(".AA.", ".AA.", "^...", "v...", "....") }
        local vert = b2:blockAt(3, 1)
        assert.are.equal(12, b2:targetFor(vert, 5, 1))   -- one down covers (5,1)
        assert.is_true(b2:slide(vert, "down"))
        assert.are.equal(12, b2.blocks[vert].a)
        assert.is_nil(b2:slideTarget(vert, "down"))
    end)

    it("counts a block moved again straight after as the same move", function()
        local b = Board:new{ level = CLASSIC, optimal = 81 }
        local s = b:blockAt(5, 1)
        assert.is_true(b:move(s, 17))
        assert.is_true(b:move(s, 18))
        assert.are.equal(1, b:getMoves())
        -- Back where the move began: no move at all.
        assert.is_true(b:move(s, 16))
        assert.are.equal(0, b:getMoves())
        assert.is_true(b:move(s, 18))
        local v = b:blockAt(3, 1)
        assert.is_true(b:slide(v, "down"))
        assert.are.equal(2, b:getMoves())
        -- Undo takes back whole moves.
        assert.is_true(b:undoMove())
        assert.is_true(b:undoMove())
        assert.are.equal(CLASSIC, Solver.format(b.blocks))
        assert.is_false(b:undoMove())
    end)

    it("detects the win and restarts", function()
        local b = Board:new{ level = CORNER, optimal = 2 }
        local s = b:blockAt(4, 2)
        assert.are.equal("S", b:kindOf(s))
        assert.is_true(b:move(s, 14))    -- one step right: still in the way
        assert.is_true(b:restart())
        assert.are.equal(0, b:getMoves())
        assert.is_true(b:move(s, 17))    -- down
        assert.is_true(b:move(s, 16))    -- and left: the same move
        assert.are.equal(1, b:getMoves())
        assert.is_false(b:isWon())
        assert.is_true(b:slide(1, "down"))
        assert.is_true(b:isWon())
        assert.are.equal(2, b:getMoves())
        assert.is_false(b:move(s, 17))
        assert.is_false(b:canUndo())
        assert.is_false(b:restart())
    end)

    it("gives hints that each bring the exit one move closer", function()
        local b = Board:new{ level = CLASSIC, optimal = 81 }
        -- Scramble a little first, so hints start off the stored path.
        math.randomseed(5)
        for _ = 1, 8 do
            local i = math.random(#b.blocks)
            local r = b:reach(i)
            if #r > 0 then b:move(i, r[math.random(#r)]) end
        end
        local left = b:remaining()
        assert.is_truthy(left)
        local moves = b:getMoves()
        while not b:isWon() do
            local before = b:remaining()
            local step = b:findHint()
            assert.is_truthy(step)
            assert.are.equal(step.v, b:blockAt(step.r, step.c))
            assert.is_true(b:applyHint(step))
            local after = b:isWon() and 0 or b:remaining()
            assert.are.equal(before - 1, after)
        end
        -- The first hint may extend the player's last move (same block): then
        -- it costs no extra move.
        assert.is_true(b:getMoves() - moves <= left and b:getMoves() - moves >= left - 1)
        local step, why = b:findHint()
        assert.is_nil(step)
        assert.are.equal("complete", why)
    end)

    it("keeps its plan along the path: undo, restart and hints search once", function()
        local b = Board:new{ level = CLASSIC, optimal = 81 }
        assert.are.equal(81, b:remaining())
        local plan = b._plan                -- a new search would replace it
        for _ = 1, 5 do assert.is_true(b:applyHint(b:findHint())) end
        assert.are.equal(76, b:remaining())
        assert.is_true(b:undoMove())
        assert.are.equal(77, b:remaining())
        assert.is_true(b:restart())
        assert.are.equal(81, b:remaining())
        assert.are.equal(plan, b._plan)
        -- Off the path, it searches again (and stays optimal).
        local moved = false
        for i = 1, #b.blocks do
            for _, to in ipairs(b:reach(i)) do
                local from = b.blocks[i].a
                b.blocks[i].a = to
                local on_path = plan.at[Solver.encode(b.blocks)]
                b.blocks[i].a = from
                if not on_path and not moved then moved = b:move(i, to) end
            end
        end
        assert.is_true(moved)
        assert.is_truthy(b:remaining())
        assert.are_not.equal(plan, b._plan)
    end)

    it("steps through the solution one way", function()
        local b = Board:new{ level = CORNER, optimal = 2 }
        assert.is_true(b:showSolution())
        assert.is_true(b:isShowingSolution())
        assert.are.equal(2, #b.solution)
        assert.is_false(b:slide(1, "down"))
        assert.is_false(b:solutionStep(-1))
        assert.is_truthy(b:nextSolutionMove())
        assert.is_true(b:solutionStep(1))
        assert.is_true(b:solutionStep(1))
        assert.is_true(Solver.isSolved(b.blocks))
        assert.is_nil(b:nextSolutionMove())
        assert.is_false(b:solutionStep(1))
        assert.is_true(b:solutionStep(-1))
        assert.is_false(Solver.isSolved(b.blocks))
    end)

    it("round-trips a save, mid-game, solved and with the solution on show", function()
        local LEVEL = CORNER
        local b = Board:new{ level = LEVEL, optimal = 2, band = "easy", index = 7 }
        local s = b:blockAt(4, 2)
        b:move(s, 17)
        b:noteHintUsed()
        local c = Board:new()
        assert.is_true(c:load(b:serialize()))
        assert.are.equal(Solver.format(b.blocks), Solver.format(c.blocks))
        assert.are.equal(1, c:getMoves())
        assert.are.equal("easy", c.band)
        assert.are.equal(7, c.index)
        assert.are.equal(1, c:getHintsUsed())
        -- The restored move still merges with the same block.
        assert.is_true(c:move(s, 16))
        assert.are.equal(1, c:getMoves())
        assert.is_true(c:undoMove())
        assert.are.equal(LEVEL, Solver.format(c.blocks))

        b:move(s, 16)
        b:slide(1, "down")
        local d = Board:new()
        assert.is_true(d:load(b:serialize()))
        assert.is_true(d:isWon())

        local e = Board:new{ level = CLASSIC, optimal = 81, band = "classic", index = 1, name = "Red Donkey" }
        e:showSolution()
        e:solutionStep(1)
        local f = Board:new()
        assert.is_true(f:load(e:serialize()))
        assert.is_true(f:isShowingSolution())
        assert.are.equal("Red Donkey", f.name)
        assert.are.equal(1, f.sol_step)
        assert.are.equal(Solver.format(e.blocks), Solver.format(f.blocks))
        assert.is_true(f:solutionStep(1))
    end)

    it("credits the optimal mark only for a win in the optimum with no hint", function()
        -- Round the corner in one move, then the big block down: 2, the optimum.
        local b = Board:new{ level = CORNER, optimal = 2 }
        local s = b:blockAt(4, 2)
        b:move(s, 17)
        b:move(s, 16)   -- same block straight after: still one move
        assert.is_false(b:isOptimalWin())
        b:slide(1, "down")
        assert.are.equal(2, b:getMoves())
        assert.is_true(b:isOptimalWin())

        -- An extra move of another block: 3, not optimal.
        b = Board:new{ level = CORNER, optimal = 2 }
        b:move(s, 14)
        b:move(1, b:slideTarget(1, "down") or 1)
        b:restart()
        b:noteHintSeen()   -- a hint shown before the restart still counts
        b:move(s, 16)
        b:slide(1, "down")
        assert.is_true(b:isWon())
        assert.is_false(b:isOptimalWin())

        -- Over the optimum with no hint: the other small block down, then
        -- this one left, then the big block: 3 moves.
        b = Board:new{ level = CORNER, optimal = 2 }
        local o = b:blockAt(4, 1)
        assert.is_true(b:move(o, 16))
        assert.is_true(b:move(s, 12))
        assert.is_true(b:slide(1, "down"))
        assert.is_true(b:isWon())
        assert.are.equal(3, b:getMoves())
        assert.is_false(b:isOptimalWin())

        -- A detour of the same block taken back by Undo doesn't count.
        b = Board:new{ level = CORNER, optimal = 2 }
        b:move(o, 16)
        assert.is_true(b:undoMove())
        b:move(s, 17)
        b:move(s, 16)
        b:slide(1, "down")
        assert.are.equal(2, b:getMoves())
        assert.is_true(b:isOptimalWin())

        -- A played hint.
        b = Board:new{ level = CORNER, optimal = 2 }
        assert.is_true(b:applyHint(b:findHint()))
        b:noteHintUsed()
        assert.is_true(b:applyHint(b:findHint()))
        assert.is_true(b:isWon())
        assert.are.equal(2, b:getMoves())
        assert.is_false(b:isOptimalWin())
        b:setLevel(CORNER, 2)
        assert.is_nil(b.hint_seen)
    end)

    it("keeps the hint flag in the save; old saves have none", function()
        local b = Board:new{ level = CORNER, optimal = 2 }
        b:noteHintSeen()
        local c = Board:new()
        assert.is_true(c:load(b:serialize()))
        assert.is_true(c.hint_seen)
        local old = Board:new{ level = CORNER, optimal = 2 }:serialize()
        old.hint_seen = nil
        assert.is_true(c:load(old))
        assert.is_nil(c.hint_seen)
    end)

    it("refuses corrupt saves", function()
        local b = Board:new()
        assert.is_false(b:load(nil))
        assert.is_false(b:load({ level = "nonsense" }))
        local good = Board:new{ level = CLASSIC }:serialize()
        good.pos = { 1, 0 }   -- blocks missing
        assert.is_false(b:load(good))
        good = Board:new{ level = CLASSIC }:serialize()
        good.pos[1] = 0       -- the 2×2 on top of a vertical
        assert.is_false(b:load(good))
        good = Board:new{ level = CLASSIC }:serialize()
        good.pos[1] = 3       -- sticking out of the tray
        assert.is_false(b:load(good))
    end)
end)

describe("level bank", function()
    local Levels, Solver, Board
    setup(function()
        Levels = require("levels")
        Solver = require("solver")
        Board  = require("board")
    end)

    it("parses the bank on first use and drops it on release()", function()
        Levels.release()
        assert.is_false(Levels.isLoaded())
        local first = Levels.get("easy", 1).str
        assert.is_true(Levels.isLoaded())
        Levels.release()
        assert.is_false(Levels.isLoaded())
        assert.are.equal(first, Levels.get("easy", 1).str)
        assert.are.equal(400, Levels.count("easy"))
    end)

    it("is solved by following hints in exactly the optimal count (sampled)", function()
        for _, band in ipairs(Levels.BANDS) do
            for i = 1, Levels.count(band), 133 do
                local lv = Levels.get(band, i)
                local b = Board:new{ level = lv.str, optimal = lv.optimal }
                local steps = 0
                while not b:isWon() and steps <= lv.optimal do
                    assert.is_true(b:applyHint(b:findHint()))
                    steps = steps + 1
                end
                assert.is_true(b:isWon())
                assert.are.equal(lv.optimal, steps)
                assert.are.equal(lv.optimal, b:getMoves())
            end
        end
    end)

    it("keeps every cluster small enough for the hint search (sampled)", function()
        for _, band in ipairs(Levels.BANDS) do
            for i = 1, Levels.count(band), 57 do
                local lv = Levels.get(band, i)
                local states = Solver.cluster(Solver.encode(Solver.parse(lv.str)))
                assert.is_true(#states <= 100000, band .. " #" .. i .. ": " .. #states)
            end
        end
    end)

    it("ships each level's solution: legal, optimal, the search's own (all levels)", function()
        for _, band in ipairs(Levels.BANDS) do
            for i = 1, Levels.count(band) do
                local lv = Levels.get(band, i)
                local blocks = Solver.parse(lv.str)
                local path = Solver.unpackPath(blocks, lv.packed, lv.optimal)
                assert.is_truthy(path, band .. " #" .. i)
                assert.are.equal(lv.optimal, #path)
                -- The same moves the search finds (sampled: it is slower).
                if i % 97 == 1 then
                    assert.are.same(Solver.solve(blocks, 110000), path, band .. " #" .. i)
                end
            end
        end
    end)

    it("packs and unpacks any path, and rejects data that doesn't fit", function()
        math.randomseed(11)
        for _, c in ipairs({ { "classic", 1 }, { "easy", 7 }, { "hard", 200 }, { "expert", 400 } }) do
            local lv = Levels.get(c[1], c[2])
            local blocks = Solver.parse(lv.str)
            local best = Solver.unpackPath(blocks, lv.packed, lv.optimal)
            -- A detour first (a block there and back, many times), then the
            -- optimal path: any legal path that ends solved round-trips.
            local path = {}
            local key = Solver.encode(blocks)
            for _ = 1, 40 do
                local opts = {}
                Solver.eachMove(key, function(from, to) opts[#opts + 1] = { from = from, to = to } end)
                local m = opts[math.random(#opts)]
                path[#path + 1] = m
                path[#path + 1] = { from = m.to, to = m.from }
            end
            for _, m in ipairs(best) do path[#path + 1] = m end
            local text = assert(Solver.packPath(blocks, path))
            assert.are.same(path, Solver.unpackPath(blocks, text, #path))
            -- Wrong length, foreign layout, an illegal move or junk: nil.
            assert.is_nil(Solver.unpackPath(blocks, text, #path - 1))
            assert.is_nil(Solver.unpackPath(blocks, lv.packed .. "!", lv.optimal))
            assert.is_nil(Solver.unpackPath(Solver.parse(CORNER), lv.packed, lv.optimal))
            assert.is_nil(Solver.packPath(blocks, { { from = 19, to = 0 } }))
            assert.is_nil(Solver.unpackPath(blocks, nil, 3))
        end
    end)

    it("gives the first hint of every level without searching", function()
        local worst = 0
        for _, band in ipairs(Levels.BANDS) do
            for i = 1, Levels.count(band) do
                local lv = Levels.get(band, i)
                local b = Board:new()
                b:setLevel(lv.str, lv.optimal, band, i, nil, lv.name)
                local t0 = os.clock()
                assert.is_true(b:hasPlan(), band .. " #" .. i)
                assert.is_truthy(b:findHint())
                worst = math.max(worst, os.clock() - t0)
                assert.are.equal(lv.optimal, b:remaining())
            end
        end
        -- ~1 ms on a desktop (the search it replaces took up to ~0.1 s).
        assert.is_true(worst < 0.05, "worst " .. worst)
        -- A level that isn't the bank's (or a stale save) still searches.
        local lv = Levels.get("hard", 1)
        local b = Board:new()
        b:setLevel(Levels.get("hard", 2).str, lv.optimal, "hard", 1)
        assert.is_false(b:hasPlan())
        assert.is_truthy(b:findHint())
    end)

    it("answers a hint from the hardest level starts quickly", function()
        -- Off the shipped solution, a hint searches. The slowest starts of
        -- the bank (2026-11 audit): ~0.15 s each on a
        -- desktop with the plain BFS, ~0.07 s merging mirror images. A Kobo
        -- is ~25x slower; the bound is generous for a loaded machine.
        local Levels = require("levels")
        local Solver = require("solver")
        for _, c in ipairs({ { "medium", 146 }, { "hard", 38 }, { "expert", 362 }, { "classic", 8 } }) do
            local lv = Levels.get(c[1], c[2])
            local t0 = os.clock()
            local path = Solver.solve(Solver.parse(lv.str), 110000)
            assert.is_true(os.clock() - t0 < 0.3, c[1] .. " #" .. c[2])
            assert.are.equal(lv.optimal, #path)
        end
    end)
end)
