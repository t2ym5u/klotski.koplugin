local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Timer  = require("timer")
local Solver = lrequire("solver")

-- ---------------------------------------------------------------------------
-- KlotskiBoard — one level in play: where the blocks are, the moves made, the
-- clock, hints and the step-through solution. Pure Lua, no UI.
--
-- Rows and columns are 1-based here (as everywhere in the UI); anchors (the
-- top-left square of a block) are 0-based cell indices, as in solver.lua.
--
-- Blocks keep their identity (index into self.blocks, the 2×2 first) for the
-- whole level, so the move counter can follow the metric of solver.lua: moving
-- the block that moved last extends that move instead of starting a new one.
-- Two taps that take one small block round a corner are one move, exactly as
-- the solver counts it; a block put back where its move began un-counts it.
-- ---------------------------------------------------------------------------

local W, H = Solver.W, Solver.H

-- Forward BFS budget for hints and the solution. The shipped levels come from
-- clusters of at most 100 000 layouts (tools/gen_levels.lua), so this never
-- cuts a real level short; it only guards against a corrupt save.
local SOLVE_BUDGET = 110000

local KlotskiBoard = {}
KlotskiBoard.__index = KlotskiBoard
KlotskiBoard.W, KlotskiBoard.H = W, H

local function copyBlocks(t)
    local out = {}
    for i, b in ipairs(t) do out[i] = { code = b.code, a = b.a } end
    return out
end

function KlotskiBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        timer      = Timer:new(),
        hints_used = 0,
        history    = {},
    }, self)
    if opts.level then
        obj:setLevel(opts.level, opts.optimal, opts.band, opts.index, opts.daily, opts.name)
    end
    return obj
end

-- Starts `str` from scratch. Returns false if the string isn't a level.
function KlotskiBoard:setLevel(str, optimal, band, index, daily, name)
    local blocks = Solver.parse(str)
    if not blocks then return false end
    self.level        = str
    self.blocks       = blocks
    self.start_blocks = copyBlocks(blocks)
    self.optimal      = optimal
    self.band         = band
    self.index        = index
    self.daily        = daily or nil
    self.name         = name
    self.history      = {}
    self.won          = Solver.isSolved(blocks)
    self.selected     = nil
    self.hint_shown   = nil
    self.solution     = nil
    self.sol_step     = nil
    self.hints_used   = 0
    self._plan        = nil
    self.timer:reset()
    self.timer:start()
    return true
end

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------

function KlotskiBoard:blockCount()
    return #self.blocks
end

-- Shape of block i: "A" (2×2), "V" (1×2), "H" (2×1) or "S" (1×1).
function KlotskiBoard:kindOf(i)
    local b = self.blocks[i]
    return b and Solver.SHAPE[b.code].kind
end

-- Cell index → block index grid for the current position.
function KlotskiBoard:_grid()
    local grid, tmp = {}, {}
    for i, b in ipairs(self.blocks) do
        for _, cell in ipairs(Solver.cellsOf(b.code, b.a, tmp)) do grid[cell] = i end
    end
    return grid
end

-- Block index covering cell (r, c), or nil.
function KlotskiBoard:blockAt(r, c)
    if r < 1 or r > H or c < 1 or c > W then return nil end
    return self:_grid()[(r - 1) * W + (c - 1)]
end

-- Cells of block i (at anchor a, default its own): list of {r, c}, 1-based.
function KlotskiBoard:cellsOf(i, a)
    local b = self.blocks[i]
    local t = {}
    for _, cell in ipairs(Solver.cellsOf(b.code, a or b.a)) do
        t[#t + 1] = { math.floor(cell / W) + 1, cell % W + 1 }
    end
    return t
end

-- Anchors block i can reach in one move.
function KlotskiBoard:reach(i)
    if not self.blocks[i] then return {} end
    return Solver.reach(self.blocks, i)
end

-- The anchor block i would move to so that it covers (r, c): of the places it
-- can reach that cover the square, the nearest to where it is now. nil when
-- none does (or the square is already under the block).
function KlotskiBoard:targetFor(i, r, c)
    local b = self.blocks[i]
    if not b or r < 1 or r > H or c < 1 or c > W then return nil end
    local cell = (r - 1) * W + (c - 1)
    for _, own in ipairs(Solver.cellsOf(b.code, b.a)) do
        if own == cell then return nil end
    end
    local r0, c0 = math.floor(b.a / W), b.a % W
    local best, best_d
    for _, to in ipairs(self:reach(i)) do
        for _, x in ipairs(Solver.cellsOf(b.code, to)) do
            if x == cell then
                local d = math.abs(math.floor(to / W) - r0) + math.abs(to % W - c0)
                if not best_d or d < best_d or (d == best_d and to < best) then
                    best, best_d = to, d
                end
            end
        end
    end
    return best
end

-- Where block i ends up sliding straight in `dir` ("left", "right", "up",
-- "down") as far as it goes, or nil if it can't move that way.
function KlotskiBoard:slideTarget(i, dir)
    local b = self.blocks[i]
    if not b then return nil end
    local dr = (dir == "up" and -1) or (dir == "down" and 1) or 0
    local dc = (dir == "left" and -1) or (dir == "right" and 1) or 0
    if dr == 0 and dc == 0 then return nil end
    local grid = self:_grid()
    local s = Solver.SHAPE[b.code]
    local r, c = math.floor(b.a / W), b.a % W
    local moved = false
    while true do
        local nr, nc = r + dr, c + dc
        if nr < 0 or nc < 0 or nr + s.h > H or nc + s.w > W then break end
        local free = true
        for _, cell in ipairs(Solver.cellsOf(b.code, nr * W + nc)) do
            local o = grid[cell]
            if o and o ~= i then free = false break end
        end
        if not free then break end
        r, c, moved = nr, nc, true
    end
    return moved and (r * W + c) or nil
end

function KlotskiBoard:isWon()
    return self.won
end

function KlotskiBoard:getMoves()
    return #self.history
end

function KlotskiBoard:canUndo()
    return #self.history > 0 and not self.won and not self.solution
end

function KlotskiBoard:isShowingSolution()
    return self.solution ~= nil
end

-- ---------------------------------------------------------------------------
-- Moves
-- ---------------------------------------------------------------------------

-- Moves block i to anchor `to`, which must be in its reach. Returns true if
-- it moved.
function KlotskiBoard:move(i, to)
    if self.won or self.solution then return false end
    local b = self.blocks[i]
    if not b or to == b.a then return false end
    local ok = false
    for _, a in ipairs(self:reach(i)) do
        if a == to then ok = true break end
    end
    if not ok then return false end
    local from = b.a
    local last = self.history[#self.history]
    if last and last[1] == i then
        -- Same block again: still the same move.
        if last[2] == to then
            self.history[#self.history] = nil
        else
            last[3] = to
        end
    else
        self.history[#self.history + 1] = { i, from, to }
    end
    b.a = to
    self.hint_shown = nil
    if Solver.isSolved(self.blocks) then
        self.won = true
        self.selected = nil
        self.timer:stop()
    end
    return true
end

-- Slides block i straight in `dir` as far as it goes. Returns true if it moved.
function KlotskiBoard:slide(i, dir)
    local to = self:slideTarget(i, dir)
    return to ~= nil and self:move(i, to)
end

-- Takes back the last move (all of it, when it was made in several taps).
function KlotskiBoard:undoMove()
    if not self:canUndo() then return false end
    local h = table.remove(self.history)
    self.blocks[h[1]].a = h[2]
    self.hint_shown = nil
    return true
end

-- Back to the starting position. The clock keeps running.
function KlotskiBoard:restart()
    if self.won or self.solution or #self.history == 0 then return false end
    self.blocks = copyBlocks(self.start_blocks)
    self.history = {}
    self.selected = nil
    self.hint_shown = nil
    return true
end

function KlotskiBoard:select(i)
    self.selected = i
end

-- ---------------------------------------------------------------------------
-- Solving: hints and the solution
-- ---------------------------------------------------------------------------

-- Block index whose anchor is `a`.
function KlotskiBoard:_blockWithAnchor(a, blocks)
    for i, b in ipairs(blocks or self.blocks) do
        if b.a == a then return i end
    end
end

-- An optimal path from the current state ({ from, to } anchors), or nil plus
-- a reason.
--
-- The plan remembers every layout along its path, so following the hints
-- (or the solution), undoing back along it or restarting never searches
-- again; only leaving the path does. It is dropped with the level.
function KlotskiBoard:plan(on_progress)
    local key = Solver.encode(self.blocks)
    local pl = self._plan
    if pl then
        local i = pl.at[key]
        if i then
            if i == 1 then return pl.path end
            local rest = {}
            for k = i, #pl.path do rest[#rest + 1] = pl.path[k] end
            return rest
        end
    end
    local path, why = Solver.solve(self.blocks, SOLVE_BUDGET, on_progress)
    if not path then return nil, why end
    -- at[key of the layout before move i] = i (and the solved end, #path + 1).
    local at, blocks = { [key] = 1 }, copyBlocks(self.blocks)
    for i, m in ipairs(path) do
        for _, b in ipairs(blocks) do
            if b.a == m.from then b.a = m.to break end
        end
        at[Solver.encode(blocks)] = i + 1
    end
    self._plan = { at = at, path = path }
    return path
end

-- Whether plan() would answer without searching.
function KlotskiBoard:hasPlan()
    local pl = self._plan
    return pl ~= nil and pl.at[Solver.encode(self.blocks)] ~= nil
end

-- Optimal number of moves left from here.
function KlotskiBoard:remaining()
    local path = self:plan()
    return path and #path
end

-- Game-common hint convention (ScreenBase:onHint): a step names a cell (the
-- block's first square) and a tag (where it goes), so the first tap marks the
-- block and the second makes the move.
function KlotskiBoard:findHint()
    if self.won then return nil, "complete" end
    local path = self:plan()
    if not path or not path[1] then return nil, "none" end
    local m = path[1]
    local i = self:_blockWithAnchor(m.from)
    if not i then return nil, "none" end
    local cell = self:cellsOf(i)[1]
    local step = { kind = "fill", r = cell[1], c = cell[2], tag = m.to, v = i, to = m.to }
    self._last_hint = step
    return step
end

-- Called by ScreenBase:onHint with the hinted cell: marks the block and
-- remembers where it is going, for the board widget.
function KlotskiBoard:setSelection(r, c)
    local i = self:blockAt(r, c)
    self.selected = i
    local h = self._last_hint
    if h and h.v == i then self.hint_shown = { v = i, to = h.to } end
end

function KlotskiBoard:applyHint(step)
    if not step or not step.v then return false end
    return self:move(step.v, step.to)
end

function KlotskiBoard:getHintsUsed()
    return self.hints_used or 0
end

function KlotskiBoard:noteHintUsed()
    self.hints_used = (self.hints_used or 0) + 1
end

-- One-way: the solution from the current position replaces play. The player
-- then steps through it; the board shows the position after sol_step moves.
function KlotskiBoard:showSolution()
    if self.solution then return true end
    if self.won then return false end
    local path = self:plan()
    if not path then return false end
    self.solution = path
    self.sol_base = copyBlocks(self.blocks)
    self.sol_step = 0
    self.selected = nil
    self.hint_shown = nil
    self.timer:stop()
    return true
end

-- The solution move about to be played, as { v = block, to = anchor }, or nil.
function KlotskiBoard:nextSolutionMove()
    if not self.solution then return nil end
    local m = self.solution[self.sol_step + 1]
    if not m then return nil end
    local i = self:_blockWithAnchor(m.from)
    return i and { v = i, to = m.to }
end

-- Steps the solution forward (+1) or back (-1). Returns true if it moved.
function KlotskiBoard:solutionStep(dir)
    if not self.solution then return false end
    local s = self.sol_step + dir
    if s < 0 or s > #self.solution then return false end
    local blocks = copyBlocks(self.sol_base)
    for k = 1, s do
        local m = self.solution[k]
        local i = self:_blockWithAnchor(m.from, blocks)
        if not i then return false end
        blocks[i].a = m.to
    end
    self.blocks = blocks
    self.sol_step = s
    return true
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

local function anchors(blocks)
    local t = {}
    for i, b in ipairs(blocks) do t[i] = b.a end
    return t
end

function KlotskiBoard:serialize()
    if not self.level then return nil end
    local hist = {}
    for _, h in ipairs(self.history) do
        hist[#hist + 1] = h[1]; hist[#hist + 1] = h[2]; hist[#hist + 1] = h[3]
    end
    local data = {
        level      = self.level,
        optimal    = self.optimal,
        band       = self.band,
        index      = self.index,
        daily      = self.daily,
        name       = self.name,
        pos        = anchors(self.blocks),
        history    = hist,
        won        = self.won,
        hints_used = self.hints_used,
        timer      = self.timer:serialize(),
    }
    if self.solution then
        local sol = {}
        for _, m in ipairs(self.solution) do sol[#sol + 1] = m.from; sol[#sol + 1] = m.to end
        data.solution = sol
        data.sol_base = anchors(self.sol_base)
        data.sol_step = self.sol_step
    end
    return data
end

-- Restores a saved game. Returns false (board untouched) on anything that
-- doesn't fit the level it names.
function KlotskiBoard:load(data)
    if type(data) ~= "table" or type(data.level) ~= "string" then return false end
    local start = Solver.parse(data.level)
    if not start then return false end
    local n = #start
    -- Anchors for the level's blocks: in the tray, no two on one square.
    local function toBlocks(t)
        if type(t) ~= "table" or #t ~= n then return nil end
        local out, seen = {}, {}
        for i = 1, n do
            local a = tonumber(t[i])
            local code = start[i].code
            if not a or a < 0 or a >= W * H or a ~= math.floor(a) then return nil end
            local r, c = math.floor(a / W), a % W
            local s = Solver.SHAPE[code]
            if r + s.h > H or c + s.w > W then return nil end
            for _, cell in ipairs(Solver.cellsOf(code, a)) do
                if seen[cell] then return nil end
                seen[cell] = true
            end
            out[i] = { code = code, a = a }
        end
        return out
    end
    local blocks = toBlocks(data.pos)
    if not blocks then return false end
    local hist = type(data.history) == "table" and data.history or {}
    if #hist % 3 ~= 0 then return false end
    local sol, sol_base
    if data.solution ~= nil then
        sol_base = toBlocks(data.sol_base)
        if type(data.solution) ~= "table" or #data.solution % 2 ~= 0 or not sol_base then
            return false
        end
        sol = {}
        for k = 1, #data.solution, 2 do
            local from, to = tonumber(data.solution[k]), tonumber(data.solution[k + 1])
            if not from or not to then return false end
            sol[#sol + 1] = { from = from, to = to }
        end
        local s = tonumber(data.sol_step)
        if not s or s < 0 or s > #sol then return false end
    end

    self:setLevel(data.level, tonumber(data.optimal), data.band, tonumber(data.index), data.daily,
        type(data.name) == "string" and data.name or nil)
    self.blocks = blocks
    self.history = {}
    for k = 1, #hist, 3 do
        local i = tonumber(hist[k])
        if i and blocks[i] then
            self.history[#self.history + 1] = { i, tonumber(hist[k + 1]), tonumber(hist[k + 2]) }
        end
    end
    self.won = Solver.isSolved(self.blocks)
    self.hints_used = tonumber(data.hints_used) or 0
    self.timer:load(data.timer)
    if sol then
        self.solution = sol
        self.sol_base = sol_base
        self.sol_step = tonumber(data.sol_step)
        self.won = false
    end
    if self.won or self.solution then self.timer:stop() else self.timer:start() end
    return true
end

return KlotskiBoard
