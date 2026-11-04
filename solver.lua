-- ---------------------------------------------------------------------------
-- solver.lua — rules and breadth-first solver for Klotski (L'Âne rouge).
--
-- Pure Lua (LuaJIT), no KOReader dependency: shared by the game, the specs and
-- the offline level generator in tools/.
--
-- The tray is 4 columns × 5 rows. A level is a 20-character string, row by
-- row:
--   "A"        the 2×2 block (exactly one)
--   "^" / "v"  top / bottom of a vertical 1×2 block
--   "<" / ">"  left / right of a horizontal 2×1 block
--   "o"        a 1×1 block
--   "."        an empty square
-- The goal is to bring the 2×2 block to the bottom centre (rows 4–5,
-- columns 2–3), where the exit gap is.
--
-- The move metric. A move is one block going anywhere it can reach, in one or
-- more unit steps — straight or around a corner — without any other block
-- moving in between. This is the metric of the classic "81 moves" for the
-- standard layout; the BFS here and the move counter in board.lua both use it.
--
-- State keys. Blocks of the same shape are interchangeable, so a state is the
-- picture of the tray: one base-6 digit per square — 0 empty, 1 small, 2 top
-- of a vertical, 3 left of a horizontal, 4 top-left of the 2×2, 5 any other
-- covered square. 6^20 < 2^53, so a key is an exact double, which keeps the
-- BFS tables small on a 256 MB reader.
-- ---------------------------------------------------------------------------

local floor = math.floor

local Solver = {}

local W, H = 4, 5
Solver.W, Solver.H = W, H
Solver.CELLS = W * H
Solver.GOAL = 3 * W + 1   -- anchor (top-left square) of the 2×2 when solved

-- Shapes by digit: width, height, level-string characters.
local SHAPE = {
    [1] = { w = 1, h = 1, kind = "S" },
    [2] = { w = 1, h = 2, kind = "V" },
    [3] = { w = 2, h = 1, kind = "H" },
    [4] = { w = 2, h = 2, kind = "A" },
}
Solver.SHAPE = SHAPE
local CODE = { S = 1, V = 2, H = 3, A = 4 }
Solver.CODE = CODE

local POW = {}
for i = 0, W * H do POW[i] = 6 ^ i end

-- CONTRIB[code][anchor]: what a block of that shape at that anchor adds to a
-- key (false when it would stick out of the tray). Moving a block is then
-- key - CONTRIB[k][from] + CONTRIB[k][to].
local CONTRIB = {}
for code, s in pairs(SHAPE) do
    CONTRIB[code] = {}
    for a = 0, W * H - 1 do
        local r, c = floor(a / W), a % W
        if r + s.h <= H and c + s.w <= W then
            local v = 0
            for dr = 0, s.h - 1 do
                for dc = 0, s.w - 1 do
                    local cell = (r + dr) * W + c + dc
                    v = v + ((dr == 0 and dc == 0) and code or 5) * POW[cell]
                end
            end
            CONTRIB[code][a] = v
        else
            CONTRIB[code][a] = false
        end
    end
end

-- Cells (0-based, row-major) covered by a block of `code` at anchor a.
-- MCONTRIB[code][a]: what a block at anchor `a` contributes to the key of
-- the mirrored layout (left <-> right), so a move can update both keys with
-- two lookups. The goal is symmetric, so a layout and its mirror are the
-- same distance from it, and the search below only explores one of the two.
local MCONTRIB = {}
for code, s in pairs(SHAPE) do
    MCONTRIB[code] = {}
    for a = 0, W * H - 1 do
        local r, c = floor(a / W), a % W
        if CONTRIB[code][a] then
            MCONTRIB[code][a] = CONTRIB[code][r * W + (W - c - s.w)]
        else
            MCONTRIB[code][a] = false
        end
    end
end

local function cellsOf(code, a, out)
    out = out or {}
    local s = SHAPE[code]
    local r, c = floor(a / W), a % W
    local n = 0
    for dr = 0, s.h - 1 do
        for dc = 0, s.w - 1 do
            n = n + 1
            out[n] = (r + dr) * W + c + dc
        end
    end
    for k = n + 1, #out do out[k] = nil end
    return out
end
Solver.cellsOf = cellsOf

-- ---------------------------------------------------------------------------
-- Level strings and block lists
-- ---------------------------------------------------------------------------

-- Parses a level string. Returns the block list — the 2×2 first, then the
-- others in reading order — or nil and a reason.
-- Each block: { code = 1..4, a = anchor cell (0-based) }.
function Solver.parse(str)
    if type(str) ~= "string" or #str ~= W * H then return nil, "length" end
    local taken = {}
    local blocks = {}
    local big
    local empty = 0
    for i = 0, W * H - 1 do
        if not taken[i] then
            local ch = str:sub(i + 1, i + 1)
            local code
            if ch == "." then empty = empty + 1
            elseif ch == "o" then code = 1
            elseif ch == "^" then code = 2
            elseif ch == "<" then code = 3
            elseif ch == "A" then code = 4
            else return nil, "bad square " .. (i + 1) end
            if code then
                if not CONTRIB[code][i] then return nil, "block out of the tray" end
                local want = { [1] = "o", [2] = "^", [3] = "<", [4] = "A" }
                local cells = cellsOf(code, i)
                for k, cell in ipairs(cells) do
                    local exp = want[code]
                    if code == 2 and k == 2 then exp = "v" end
                    if code == 3 and k == 2 then exp = ">" end
                    if taken[cell] or str:sub(cell + 1, cell + 1) ~= exp then
                        return nil, "bad shape at " .. (i + 1)
                    end
                    taken[cell] = true
                end
                if code == 4 then
                    if big then return nil, "two 2×2 blocks" end
                    big = { code = 4, a = i }
                else
                    blocks[#blocks + 1] = { code = code, a = i }
                end
            end
        end
    end
    if not big then return nil, "no 2×2 block" end
    if empty < 1 then return nil, "no empty square" end
    table.insert(blocks, 1, big)
    return blocks
end

-- Back to a level string.
function Solver.format(blocks)
    local t = {}
    for i = 1, W * H do t[i] = "." end
    local tmp = {}
    for _, b in ipairs(blocks) do
        local cells = cellsOf(b.code, b.a, tmp)
        for k, cell in ipairs(cells) do
            local ch
            if b.code == 1 then ch = "o"
            elseif b.code == 4 then ch = "A"
            elseif b.code == 2 then ch = (k == 1) and "^" or "v"
            else ch = (k == 1) and "<" or ">" end
            t[cell + 1] = ch
        end
    end
    return table.concat(t)
end

-- The same level seen in a mirror (left ↔ right). The goal is symmetric, so
-- both have the same solution length.
function Solver.mirror(str)
    local t = {}
    for r = 0, H - 1 do
        for c = W - 1, 0, -1 do
            local ch = str:sub(r * W + c + 1, r * W + c + 1)
            if ch == "<" then ch = ">" elseif ch == ">" then ch = "<" end
            t[#t + 1] = ch
        end
    end
    return table.concat(t)
end

function Solver.encode(blocks)
    local key = 0
    for _, b in ipairs(blocks) do key = key + CONTRIB[b.code][b.a] end
    return key
end

-- Digits of a key: out[0..19].
local function decode(key, out)
    out = out or {}
    for i = 0, W * H - 1 do
        local d = key % 6
        out[i] = d
        key = (key - d) / 6
    end
    return out
end
Solver.decode = decode

-- Block list of a key (2×2 first, then reading order), as parse() gives.
function Solver.blocksOf(key)
    local g = decode(key)
    local blocks = {}
    local big
    for i = 0, W * H - 1 do
        local d = g[i]
        if d == 4 then big = { code = 4, a = i }
        elseif d >= 1 and d <= 3 then blocks[#blocks + 1] = { code = d, a = i } end
    end
    table.insert(blocks, 1, big)
    return blocks
end

function Solver.isSolvedKey(key)
    return floor(key / POW[Solver.GOAL]) % 6 == 4
end

function Solver.isSolved(blocks)
    for _, b in ipairs(blocks) do
        if b.code == 4 then return b.a == Solver.GOAL end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Moves
-- ---------------------------------------------------------------------------

-- Precomputed per shape and anchor: the squares covered (CELLS) and the
-- anchors one unit step away that stay inside the tray (STEPS).
local CELLS, STEPS = {}, {}
for code, s in pairs(SHAPE) do
    CELLS[code], STEPS[code] = {}, {}
    for a = 0, W * H - 1 do
        if CONTRIB[code][a] then
            CELLS[code][a] = cellsOf(code, a)
            local r, c = floor(a / W), a % W
            local st = {}
            for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
                local nr, nc = r + d[1], c + d[2]
                if nr >= 0 and nc >= 0 and nr + s.h <= H and nc + s.w <= W then
                    st[#st + 1] = nr * W + nc
                end
            end
            STEPS[code][a] = st
        end
    end
end

-- Flood fill of the anchors a block of `code` at `from` can reach, given the
-- occupancy `occ` (occ[cell] true = taken, the block's own squares NOT
-- counted). Leaves them in rq[2..n] and returns n. No allocation: this runs
-- once per block per state in the BFS.
local mark, rq, gen = {}, {}, 0
for i = 0, W * H - 1 do mark[i] = 0 end
local function reachFrom(code, from, occ)
    local cells, steps = CELLS[code], STEPS[code]
    gen = gen + 1
    mark[from] = gen
    rq[1] = from
    local head, tail = 1, 1
    while head <= tail do
        local st = steps[rq[head]]
        head = head + 1
        for j = 1, #st do
            local b = st[j]
            if mark[b] ~= gen then
                local cb = cells[b]
                local free = true
                for k = 1, #cb do
                    if occ[cb[k]] then free = false break end
                end
                if free then
                    mark[b] = gen
                    tail = tail + 1
                    rq[tail] = b
                end
            end
        end
    end
    return tail
end

-- Calls fn(from, to, newkey) for every move out of the state `key`; with
-- `mkey` (the key of its mirror image) given, fn(from, to, newkey, newmkey).
local g, occ, found = {}, {}, {}
local function eachMove(key, fn, mkey)
    decode(key, g)
    for i = 0, W * H - 1 do occ[i] = g[i] ~= 0 end
    for a = 0, W * H - 1 do
        local code = g[a]
        if code >= 1 and code <= 4 then
            local own = CELLS[code][a]
            for k = 1, #own do occ[own[k]] = false end
            local n = reachFrom(code, a, occ)
            -- fn may run another search (it doesn't today), so copy first.
            for k = 2, n do found[k] = rq[k] end
            for k = 1, #own do occ[own[k]] = true end
            local con = CONTRIB[code]
            local base = key - con[a]
            if mkey then
                local mcon = MCONTRIB[code]
                local mbase = mkey - mcon[a]
                for k = 2, n do
                    local to = found[k]
                    fn(a, to, base + con[to], mbase + mcon[to])
                end
            else
                for k = 2, n do
                    local to = found[k]
                    fn(a, to, base + con[to])
                end
            end
        end
    end
end
Solver.eachMove = eachMove

-- Anchors block i of `blocks` can reach in one move (list, start excluded).
function Solver.reach(blocks, i)
    local o = {}
    local tmp = {}
    for j, b in ipairs(blocks) do
        if j ~= i then
            for _, cell in ipairs(cellsOf(b.code, b.a, tmp)) do o[cell] = true end
        end
    end
    local out = {}
    local n = reachFrom(blocks[i].code, blocks[i].a, o)
    for k = 2, n do out[#out + 1] = rq[k] end
    return out
end

-- ---------------------------------------------------------------------------
-- Search
-- ---------------------------------------------------------------------------

-- Key of the mirror image of `blocks`.
local function mirrorEncode(blocks)
    local key = 0
    for _, b in ipairs(blocks) do key = key + MCONTRIB[b.code][b.a] end
    return key
end

-- Optimal solution from `blocks`: a list of moves { from = anchor, to =
-- anchor }, empty when already solved. Returns nil, "unsolvable" when the
-- exit can't be reached, nil, "budget" past max_states explored.
--
-- Breadth-first over layouts up to mirror image: a layout and its mirror
-- count as one state (the smaller of the two keys names it), which halves
-- the states to visit -- a hint used to take up to 0.15 s on a desktop,
-- ~4 s on a Kobo. max_states counts these merged states. Only the parent of
-- each state is kept; the moves themselves are found again along the one
-- path at the end.
--
-- on_progress (optional): called every few thousand states with a rough
-- fraction done (states seen against PROGRESS_STATES), for a progress bar.
local PROGRESS_STATES = 50000
function Solver.solve(blocks, max_states, on_progress)
    max_states = max_states or 200000
    local start, mstart = Solver.encode(blocks), mirrorEncode(blocks)
    if Solver.isSolvedKey(start) then return {} end
    local cstart = start < mstart and start or mstart
    local parent = { [cstart] = false }
    -- The queue holds the layout actually reached (and its mirror's key).
    local q, mq, head, tail = { start }, { mstart }, 1, 1
    local found
    local count = 1
    local ckey
    local goal_pow = POW[Solver.GOAL]
    local function visit(_, _, nk, nmk)
        if found then return end
        local c = nk < nmk and nk or nmk
        if parent[c] ~= nil then return end
        parent[c] = ckey
        count = count + 1
        if floor(nk / goal_pow) % 6 == 4 then found = c return end
        tail = tail + 1
        q[tail], mq[tail] = nk, nmk
    end
    while head <= tail do
        local key, mkey = q[head], mq[head]
        q[head], mq[head] = nil, nil
        head = head + 1
        ckey = key < mkey and key or mkey
        eachMove(key, visit, mkey)
        if found then break end
        if count > max_states then return nil, "budget" end
        if on_progress and head % 4096 == 0 then
            on_progress(math.min(1, count / PROGRESS_STATES))
        end
    end
    if not found then return nil, "unsolvable" end
    -- The chain of merged states, start first.
    local chain = {}
    local k = found
    while k do
        table.insert(chain, 1, k)
        k = parent[k]
    end
    -- Replay it on the real layout: at each step, one of the moves leads to
    -- the next state of the chain (itself or its mirror).
    local path = {}
    local key, mkey = start, mstart
    for i = 2, #chain do
        local want = chain[i]
        local step
        eachMove(key, function(from, to, nk, nmk)
            if not step and (nk < nmk and nk or nmk) == want then
                step = { from = from, to = to, key = nk, mkey = nmk }
            end
        end, mkey)
        path[#path + 1] = { from = step.from, to = step.to }
        key, mkey = step.key, step.mkey
    end
    return path
end

-- Optimal move count, or nil plus the reason.
function Solver.distance(blocks, max_states)
    local path, why = Solver.solve(blocks, max_states)
    if not path then return nil, why end
    return #path
end

-- Every state reachable from `start` (a key), with its distance to the
-- nearest solved state (nil when the cluster has no solution). Used offline
-- by the level generator and the specs. Returns states (list of keys), dist
-- (key -> moves), max distance.
function Solver.cluster(start, max_states, seen_all)
    max_states = max_states or 2000000
    local seenk = { [start] = true }
    local states, cnt = { start }, 1
    local solved = {}
    local head = 1
    local function visit(_, _, nk)
        if not seenk[nk] then
            seenk[nk] = true
            cnt = cnt + 1
            states[cnt] = nk
        end
    end
    while head <= cnt do
        local key = states[head]
        head = head + 1
        if seen_all then seen_all[key] = true end
        if Solver.isSolvedKey(key) then solved[#solved + 1] = key end
        eachMove(key, visit)
        if cnt > max_states then return nil, "budget" end
    end
    if #solved == 0 then return states, nil, -1 end
    -- Moves are reversible, so distances to the goal come from one BFS that
    -- starts from every solved state at once.
    local dist, dq = {}, {}
    for i, k in ipairs(solved) do dist[k] = 0; dq[i] = k end
    local qh, qt = 1, #dq
    local maxd = 0
    local d
    local function relax(_, _, nk)
        if dist[nk] == nil then
            dist[nk] = d + 1
            if d + 1 > maxd then maxd = d + 1 end
            qt = qt + 1
            dq[qt] = nk
        end
    end
    while qh <= qt do
        local key = dq[qh]
        qh = qh + 1
        d = dist[key]
        eachMove(key, relax)
    end
    return states, dist, maxd
end

return Solver
