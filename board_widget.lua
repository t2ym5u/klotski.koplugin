local Blitbuffer     = require("ffi/blitbuffer")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager      = require("ui/uimanager")

local C_BG   = Blitbuffer.COLOR_WHITE
local C_FG   = Blitbuffer.COLOR_BLACK
local C_GRID = Blitbuffer.COLOR_GRAY_D

local W, H = 4, 5
local GOAL_COL = 1   -- 0-based first column of the exit gap

-- ---------------------------------------------------------------------------
-- KlotskiBoardWidget: the 4×5 tray, its walls and the exit gap in the bottom
-- wall (columns 2–3), with a chevron under it. Blocks are drawn with a gap
-- between them; each shape has its own look so the tray reads on a grey-scale
-- screen: the 2×2 is solid black with a white arrow pointing at the exit,
-- vertical blocks light grey, horizontal blocks darker grey, small blocks
-- white with a frame inside.
--
-- Taps go to cellTapCallback(r, c); a swipe that starts on a square goes to
-- swipeCallback(r, c, dir) with dir one of "left", "right", "up", "down".
-- ---------------------------------------------------------------------------

local KlotskiBoardWidget = InputContainer:extend{
    board           = nil,
    max_width       = 0,
    max_height      = 0,
    cellTapCallback = nil,
    swipeCallback   = nil,
}

function KlotskiBoardWidget:init()
    -- Width: walls + 4 cells. Height: walls + 5 cells + the exit band.
    local cell = math.floor(math.min(self.max_width / (W + 0.2), self.max_height / (H + 0.75)))
    cell = math.max(cell, 12)
    self.cell = cell
    self.wall = math.max(3, math.floor(cell * 0.07))
    self.band = math.floor(cell * 0.55) - self.wall
    self.grid_x = self.wall
    self.grid_y = self.wall
    self.w = cell * W + 2 * self.wall
    self.h = cell * H + 2 * self.wall + self.band
    self.dimen = Geom:new{ w = self.w, h = self.h }

    self.paint_rect = nil
    local range = function() return self.paint_rect end
    self.ges_events = {
        CellTap   = { GestureRange:new{ ges = "tap",   range = range } },
        CellSwipe = { GestureRange:new{ ges = "swipe", range = range } },
    }
end

function KlotskiBoardWidget:_cellAt(pos)
    if not self.paint_rect then return nil end
    local lx = pos.x - self.paint_rect.x - self.grid_x
    local ly = pos.y - self.paint_rect.y - self.grid_y
    if lx < 0 or ly < 0 then return nil end
    local c = math.floor(lx / self.cell) + 1
    local r = math.floor(ly / self.cell) + 1
    if r > H or c > W then return nil end
    return r, c
end

-- Screen centre of cell (r, c), for tests driving the widget.
function KlotskiBoardWidget:getCellCenter(r, c)
    local rect = self.paint_rect or Geom:new{ x = 0, y = 0 }
    local half = math.floor(self.cell / 2)
    return rect.x + self.grid_x + (c - 1) * self.cell + half,
           rect.y + self.grid_y + (r - 1) * self.cell + half
end

function KlotskiBoardWidget:onCellTap(_, ges)
    local r, c = self:_cellAt(ges.pos)
    if r and self.cellTapCallback then self.cellTapCallback(r, c) end
    return true
end

local SWIPE_DIR = { west = "left", east = "right", north = "up", south = "down" }

function KlotskiBoardWidget:onCellSwipe(_, ges)
    local r, c = self:_cellAt(ges.pos)
    local dir = SWIPE_DIR[ges.direction]
    if dir and self.swipeCallback then self.swipeCallback(r, c, dir) end
    return true
end

function KlotskiBoardWidget:refresh()
    UIManager:setDirty(self, function()
        return "ui", self.paint_rect or self.dimen
    end)
end

-- ---------------------------------------------------------------------------
-- Drawing helpers
-- ---------------------------------------------------------------------------

-- A filled downward chevron (triangle) centred on cx, top at y.
local function triangleDown(bb, cx, y, half, len, color)
    for k = 0, len - 1 do
        local hh = math.floor(half * (1 - k / len))
        bb:paintRect(cx - hh, y + k, 2 * hh + 1, 1, color)
    end
end

-- The 2×2's white arrow, pointing down at the exit.
local function arrowDown(bb, x, y, w, h)
    local cx = x + math.floor(w / 2)
    local head = math.floor(w * 0.42)
    local hl = math.floor(head * 0.8)
    local sw = math.max(2, math.floor(w * 0.12))
    local y_beg = y + math.floor(h * 0.2)
    local y_end = y + h - math.floor(h * 0.2)
    bb:paintRect(cx - math.floor(sw / 2), y_beg, sw, y_end - hl - y_beg + 1, C_BG)
    triangleDown(bb, cx, y_end - hl, math.floor(head / 2), hl, C_BG)
end

local function dashedOutline(bb, x, y, w, h, t, dash)
    for xx = x, x + w - 1, 2 * dash do
        local l = math.min(dash, x + w - xx)
        bb:paintRect(xx, y, l, t, C_FG)
        bb:paintRect(xx, y + h - t, l, t, C_FG)
    end
    for yy = y, y + h - 1, 2 * dash do
        local l = math.min(dash, y + h - yy)
        bb:paintRect(x, yy, t, l, C_FG)
        bb:paintRect(x + w - t, yy, t, l, C_FG)
    end
end

-- Rectangle of a block of `kind` at anchor a, inset by the gap.
function KlotskiBoardWidget:_blockRect(gx, gy, code, a)
    local cell, gap = self.cell, math.max(2, math.floor(self.cell * 0.05))
    local bw = (code == 3 or code == 4) and 2 or 1
    local bh = (code == 2 or code == 4) and 2 or 1
    local r, c = math.floor(a / W), a % W
    return gx + c * cell + gap, gy + r * cell + gap, bw * cell - 2 * gap, bh * cell - 2 * gap
end

local FILL = {
    [1] = C_BG,                       -- small: white, with an inner frame
    [2] = Blitbuffer.COLOR_GRAY_B,    -- vertical: light grey
    [3] = Blitbuffer.COLOR_GRAY_7,    -- horizontal: darker grey
}

function KlotskiBoardWidget:_paintBlock(bb, gx, gy, i, selected)
    local b = self.board.blocks[i]
    local x, y, w, h = self:_blockRect(gx, gy, b.code, b.a)
    local cell = self.cell
    local bw = math.max(2, math.floor(cell / 26))
    local radius = math.floor(cell * 0.12)
    if selected then
        -- Thick black rim, then a white ring, so the selection reads on the
        -- black 2×2 and on white blocks alike.
        local t = math.max(4, math.floor(cell / 9))
        bb:paintRoundedRect(x, y, w, h, C_FG, radius)
        local ring = math.max(2, math.floor(t / 2))
        bb:paintRect(x + t, y + t, w - 2 * t, h - 2 * t, C_BG)
        x, y, w, h = x + t + ring, y + t + ring, w - 2 * (t + ring), h - 2 * (t + ring)
        bb:paintRect(x, y, w, h, C_FG)
        bw = math.max(1, math.floor(bw / 2))
    else
        bb:paintRoundedRect(x, y, w, h, C_FG, radius)
    end
    if b.code == 4 then
        arrowDown(bb, x, y, w, h)
        return
    end
    local ix, iy, iw, ih = x + bw, y + bw, w - 2 * bw, h - 2 * bw
    bb:paintRect(ix, iy, iw, ih, FILL[b.code])
    if b.code == 1 then
        -- A second frame inside: reads as a block, not as a target dot.
        local i = math.max(3, math.floor(cell * 0.14))
        local lw = math.max(2, math.floor(cell / 22))
        bb:paintRect(ix + i, iy + i, iw - 2 * i, ih - 2 * i, C_FG)
        bb:paintRect(ix + i + lw, iy + i + lw, iw - 2 * (i + lw), ih - 2 * (i + lw), C_BG)
    end
end

function KlotskiBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local board = self.board
    local cell, wall = self.cell, self.wall
    local gx, gy = x + self.grid_x, y + self.grid_y
    local gw, gh = cell * W, cell * H

    bb:paintRect(x, y, self.w, self.h, C_BG)

    -- Squares: thin lines.
    for k = 1, W - 1 do bb:paintRect(gx + k * cell, gy, 1, gh, C_GRID) end
    for k = 1, H - 1 do bb:paintRect(gx, gy + k * cell, gw, 1, C_GRID) end

    -- Walls, with the exit gap in the bottom wall.
    local wx, wy = gx - wall, gy - wall
    bb:paintRect(wx, wy, gw + 2 * wall, wall, C_FG)
    bb:paintRect(wx, wy, wall, gh + 2 * wall, C_FG)
    bb:paintRect(gx + gw, wy, wall, gh + 2 * wall, C_FG)
    local gap_x0 = gx + GOAL_COL * cell
    local gap_x1 = gap_x0 + 2 * cell
    bb:paintRect(wx, gy + gh, gap_x0 - wx, wall, C_FG)
    bb:paintRect(gap_x1, gy + gh, gx + gw + wall - gap_x1, wall, C_FG)
    -- The gap itself: a thin dashed line, and a chevron under it.
    local t = math.max(1, math.floor(wall / 3))
    for xx = gap_x0, gap_x1 - 1, 2 * math.max(3, math.floor(cell / 10)) do
        bb:paintRect(xx, gy + gh + math.floor((wall - t) / 2), math.min(math.max(3, math.floor(cell / 10)), gap_x1 - xx), t, C_FG)
    end
    if self.band >= 6 then
        local len = math.floor(self.band * 0.75)
        triangleDown(bb, gap_x0 + cell, gy + gh + wall + math.floor((self.band - len) / 2),
            math.floor(cell * 0.35), len, C_FG)
    end

    -- Where the selected block can go: a dot on every free square it can
    -- reach.
    local sel = board.selected
    if sel and board.blocks[sel] and not board.won then
        local own = {}
        for _, rc in ipairs(board:cellsOf(sel)) do own[rc[1] * 10 + rc[2]] = true end
        local dotted = {}
        local d = math.max(4, math.floor(cell / 8))
        for _, to in ipairs(board:reach(sel)) do
            for _, rc in ipairs(board:cellsOf(sel, to)) do
                local k = rc[1] * 10 + rc[2]
                if not own[k] and not dotted[k] then
                    dotted[k] = true
                    bb:paintRect(gx + (rc[2] - 1) * cell + math.floor((cell - d) / 2),
                                 gy + (rc[1] - 1) * cell + math.floor((cell - d) / 2), d, d, C_FG)
                end
            end
        end
    end

    local nxt = board.nextSolutionMove and board:nextSolutionMove()
    for i = 1, #board.blocks do
        local selected = (i == sel) or (nxt and i == nxt.v)
        self:_paintBlock(bb, gx, gy, i, selected)
    end

    -- Where the hinted (or next solution) move goes: a dashed outline,
    -- drawn over the blocks: it often overlaps the block that moves.
    local ghost = board.hint_shown
    if nxt then ghost = nxt end
    if ghost and board.blocks[ghost.v] then
        local rx, ry, rw, rh = self:_blockRect(gx, gy, board.blocks[ghost.v].code, ghost.to)
        dashedOutline(bb, rx, ry, rw, rh, math.max(2, math.floor(cell / 16)), math.max(4, math.floor(cell / 7)))
    end
end

return KlotskiBoardWidget
