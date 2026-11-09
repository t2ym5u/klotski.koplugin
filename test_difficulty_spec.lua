local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

-- Difficulty guarantees of the level bank: a level's difficulty is its
-- optimal move count (checked against the solver on a sample); each band
-- holds only levels of its documented range, sorted, the graded ranges are
-- ordered, and the bands get harder on average. "classic" is the named
-- traditional layouts, any length.
local CLASSIC = table.concat({ "^AA^", "vAAv", "^<>^", "voov", "o..o" })
local GRADED = { "easy", "medium", "hard", "expert" }

describe("Klotski difficulty bands", function()
    local Levels, Solver
    setup(function()
        Levels = require("levels")
        Solver = require("solver")
    end)

    local RANGES = {
        easy    = { 5, 15 },
        medium  = { 16, 35 },
        hard    = { 36, 60 },
        expert  = { 61, 999 },
        classic = { 1, 999 },
    }

    it("holds 400 levels per difficulty and the classics, each within its band", function()
        local seen = {}
        for _, band in ipairs(Levels.BANDS) do
            local n = Levels.count(band)
            assert.are.equal(band == "classic" and 8 or 400, n)
            for i = 1, n do
                local lv = Levels.get(band, i)
                assert.is_truthy(Solver.parse(lv.str), lv.str)
                assert.is_true(lv.optimal >= RANGES[band][1] and lv.optimal <= RANGES[band][2], lv.str)
                -- Unique, mirror images included, across the whole bank.
                assert.is_nil(seen[lv.str], lv.str)
                seen[lv.str] = true
                seen[Solver.mirror(lv.str)] = true
                if band == "classic" then
                    assert.is_truthy(lv.name)
                elseif i > 1 then
                    assert.is_true(lv.optimal >= Levels.get(band, i - 1).optimal)
                end
            end
        end
        assert.are.equal(CLASSIC, Levels.get("classic", 1).str)
        assert.are.equal(81, Levels.get("classic", 1).optimal)
    end)

    it("stores the exact optimal count (sampled)", function()
        for _, band in ipairs(Levels.BANDS) do
            local n = Levels.count(band)
            for i = 1, n, 50 do
                local lv = Levels.get(band, i)
                assert.are.equal(lv.optimal, Solver.distance(Solver.parse(lv.str)), band .. " #" .. i)
            end
            local lv = Levels.get(band, n)
            assert.are.equal(lv.optimal, Solver.distance(Solver.parse(lv.str)), band .. " last")
        end
    end)

    it("the graded ranges are ordered and do not overlap", function()
        local prev_hi = RANGES.easy[1] - 1
        for _, band in ipairs(GRADED) do
            assert.are.equal(prev_hi + 1, RANGES[band][1], band)
            assert.is_true(RANGES[band][2] >= RANGES[band][1])
            prev_hi = RANGES[band][2]
        end
    end)

    it("the graded bands get harder on average", function()
        local prev = 0
        for _, band in ipairs(GRADED) do
            local n, sum = Levels.count(band), 0
            for i = 1, n do sum = sum + Levels.get(band, i).optimal end
            assert.is_true(sum / n > prev, band)
            prev = sum / n
        end
    end)
end)
