local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Menu            = require("ui/widget/menu")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase   = require("screen_base")
local DailySeed    = require("daily_seed")
local GenProgress  = require("gen_progress")
local MenuHelper   = require("menu_helper")
local Board        = lrequire("board")
local BoardWidget  = lrequire("board_widget")
local Levels       = lrequire("levels")
local Progress     = lrequire("progress")

local DeviceScreen = Device.screen

local GAME_RULES_EN = [[
Klotski — Rules

The tray is 4 squares wide and 5 high, with a gap two squares wide in the middle of the bottom wall. Bring the big 2×2 block (black, with a white arrow) down to that gap: the level is solved when it sits on the two bottom rows, in the middle.

• Blocks slide up, down, left or right, into empty squares only — never through another block, never lifted.
• One move is one block going anywhere it can reach, even round a corner, as long as no other block moves in between. Moving the same block again straight after counts as the same move.

Each level shows its optimal number of moves: the fewest it can be solved in. Solving it in that many, without a hint, is a perfect score: the level gets a star (★) instead of a check mark (✓) in the Level list.

Controls:
• Tap a block to select it (thick outline). Dots mark the empty squares it can reach; tap one to move it there (if two places fit, the nearer one). Tap the block again to deselect it.
• Or swipe on a block to slide it straight as far as it goes in that direction.
• Undo takes back the last move; Restart puts every block back where the level started.
• Hint: the first tap marks the block to move next and outlines where it goes (dashed); the second tap plays that move. Every hint follows an optimal solution from where you are.
• Show solution (menu) gives up the level and lets you step through an optimal solution.

Difficulty: Easy levels take 5 to 15 moves, Medium 16 to 35, Hard 36 to 60, Expert 61 or more. Classics are the traditional layouts — the Red Donkey (81 moves) is the famous one — and the hardest starts found. "New game" opens the next level you haven't solved yet; "Level" lets you pick any level. The Daily Challenge is the same level for everyone today.
]]

local GAME_RULES_FR = [[
L'Âne rouge — Règles

Le plateau mesure 4 cases de large sur 5 de haut, avec une ouverture de deux cases au milieu du bord inférieur. Amenez le gros bloc 2×2 (noir, à flèche blanche) devant cette ouverture : le niveau est résolu quand il occupe les deux rangées du bas, au milieu.

• Les blocs glissent vers le haut, le bas, la gauche ou la droite, dans des cases vides uniquement — jamais à travers un autre bloc, jamais soulevés.
• Un coup, c'est un bloc qui va où il peut, même en tournant un coin, tant qu'aucun autre bloc ne bouge entre-temps. Redéplacer aussitôt le même bloc compte pour le même coup.

Chaque niveau indique son nombre de coups optimal : le minimum pour le résoudre. Le réussir en autant de coups, sans astuce, c'est le score parfait : le niveau reçoit une étoile (★) au lieu d'une coche (✓) dans la liste des niveaux.

Commandes :
• Touchez un bloc pour le sélectionner (contour épais). Des points marquent les cases vides qu'il peut atteindre ; touchez-en une pour l'y déplacer (si deux places conviennent, la plus proche). Touchez à nouveau le bloc pour le désélectionner.
• Ou balayez un bloc pour le faire glisser tout droit aussi loin que possible dans cette direction.
• Annuler reprend le dernier coup ; Recommencer remet tous les blocs à leur place de départ.
• Astuce : le premier appui marque le bloc à déplacer et entoure (en pointillés) sa destination ; le second joue ce coup. Chaque indice suit une solution optimale depuis la position actuelle.
• Voir la solution (menu) abandonne le niveau et permet de parcourir une solution optimale pas à pas.

Difficulté : les niveaux Facile se font en 5 à 15 coups, Moyen de 16 à 35, Difficile de 36 à 60, Expert en 61 ou plus. Les Classiques sont les dispositions traditionnelles — l'Âne rouge (81 coups) est la plus célèbre — et les départs les plus durs trouvés. « Nouvelle partie » ouvre le prochain niveau pas encore résolu ; « Niveau » permet de choisir n'importe quel niveau. Le Défi du jour est le même niveau pour tout le monde aujourd'hui.
]]

local BAND_LABELS = {
    easy    = _("Easy"),
    medium  = _("Medium"),
    hard    = _("Hard"),
    expert  = _("Expert"),
    classic = _("Classics"),
}

-- Names of the classic layouts (levels_data.lua keys), translated here so
-- the extractor sees them.
local CLASSIC_NAMES = {
    ["Red Donkey"]    = _("Red Donkey"),
    ["Calm Command"]  = _("Calm Command"),
    ["Side by Side"]  = _("Side by Side"),
    ["Three Columns"] = _("Three Columns"),
    ["The Long Way"]  = _("The Long Way"),
    ["Crosswind"]     = _("Crosswind"),
    ["Off Centre"]    = _("Off Centre"),
    ["Winding Road"]  = _("Winding Road"),
}

local function levelName(name)
    return name and (CLASSIC_NAMES[name] or name)
end

local KlotskiScreen = ScreenBase:extend{}

function KlotskiScreen:init()
    self.progress = Progress.new(self.plugin)
    self.board = Board:new()
    if not self.board:load(self.plugin:loadState()) then
        self:_startLevel(self:_getBand(), self:_nextUnsolved(self:_getBand()))
    end
    ScreenBase.init(self)
end

function KlotskiScreen:serializeState()
    return self.board:serialize()
end

function KlotskiScreen:_save()
    self.plugin:saveState(self.board:serialize())
end

-- ---------------------------------------------------------------------------
-- Levels and progress
-- ---------------------------------------------------------------------------

function KlotskiScreen:_getBand()
    local b = self.plugin:getSetting("difficulty", Levels.DEFAULT_BAND)
    return Levels.isBand(b) and b or Levels.DEFAULT_BAND
end

-- Solved / solved-in-the-optimum levels: see progress.lua.
function KlotskiScreen:isLevelSolved(band, index)
    return self.progress:isSolved(band, index)
end

-- A win marks the level solved, and optimal too when it took the optimal
-- number of moves with no hint. Marks are never taken back.
function KlotskiScreen:_markSolved()
    local b = self.board
    self.progress:record(b.band, b.index, b:isOptimalWin())
end

-- The first level of the band not solved yet (other than the one on the
-- board), or the one after the current level once they are all solved.
function KlotskiScreen:_nextUnsolved(band)
    local total = Levels.count(band)
    local cur = self.board.band == band and self.board.index or nil
    for i = 1, total do
        if i ~= cur and not self:isLevelSolved(band, i) then return i end
    end
    if total == 0 then return nil end
    return cur and (cur % total) + 1 or 1
end

function KlotskiScreen:_startLevel(band, index, daily)
    local lv = index and Levels.get(band, index)
    if not lv then return false end
    self.board:setLevel(lv.str, lv.optimal, band, index, daily, lv.name)
    self.hint_cell = nil
    self:_save()
    return true
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function KlotskiScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Klotski"), function()
        local items = {
            { text = _("New game"), callback = function() self:onNewGame() end },
            self:makeDailyButtonConfig(),
            { text = T(_("Difficulty: %1"), BAND_LABELS[self:_getBand()]),
              callback = function() self:openDifficultyMenu() end },
            { text = self:_levelButtonText(), callback = function() self:openLevelMenu() end },
        }
        if not self.board:isShowingSolution() and not self.board:isWon() then
            items[#items + 1] = { text = _("Show solution"), callback = function() self:onShowSolution() end }
        end
        items[#items + 1] = self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR)
        return items
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local undo    = { id = "undo_btn",    text = _("Undo"),    callback = function() self:onUndo() end }
    local restart = { id = "restart_btn", text = _("Restart"), callback = function() self:onRestart() end }
    local hint    = { text = _("Hint"), callback = function() self:onHint() end }
    -- The landscape side panel is too narrow for three labels on one row.
    local action_bar = self:buildActionBar(is_landscape
        and { { undo, restart }, { hint } }
        or  { undo, restart, hint })
    self.undo_btn    = action_bar:getButtonById("undo_btn")
    self.restart_btn = action_bar:getButtonById("restart_btn")
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        action_bar,
    }

    -- The widget draws its own walls, so the frame only pads.
    local frame_pad = Size.padding.large
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = BoardWidget:new{
        board           = self.board,
        max_width       = math.max(budget_w - 2 * frame_pad, 84),
        max_height      = math.max(budget_h - 2 * frame_pad, 72),
        cellTapCallback = function(r, c) self:onCellTap(r, c) end,
        swipeCallback   = function(r, c, dir) self:onSwipe(r, c, dir) end,
    }
    local board_frame = FrameContainer:new{
        padding    = frame_pad,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }
    self:_updateButtons()

    if is_landscape then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Interaction
-- ---------------------------------------------------------------------------

-- After anything that moved a block: one repaint (updateStatus dirties the
-- whole screen once), the save, and the level marked solved on a win.
function KlotskiScreen:_afterMove()
    self.hint_cell = nil
    local b = self.board
    if b:isWon() then self:_markSolved() end
    self:_save()
    self:_updateButtons()
    self:updateStatus()
end

function KlotskiScreen:onCellTap(r, c)
    local b = self.board
    if b:isWon() or b:isShowingSolution() then return end
    local i = b:blockAt(r, c)
    if i then
        b:select(b.selected ~= i and i or nil)
        b.hint_shown = nil
        self.hint_cell = nil
        self.board_widget:refresh()
        return
    end
    local sel = b.selected
    local to = sel and b:targetFor(sel, r, c)
    if to and b:move(sel, to) then
        self:_afterMove()
    elseif sel then
        b:select(nil)
        self.board_widget:refresh()
    end
end

function KlotskiScreen:onSwipe(r, c, dir)
    local b = self.board
    if b:isWon() or b:isShowingSolution() then return end
    local i = (r and b:blockAt(r, c)) or b.selected
    if not i then return end
    b:select(i)
    if b:slide(i, dir) then
        self:_afterMove()
    else
        self.board_widget:refresh()
    end
end

function KlotskiScreen:onUndo()
    if self.board:undoMove() then self:_afterMove() end
end

function KlotskiScreen:onRestart()
    if self.board:restart() then self:_afterMove() end
end

-- Each hint step names the block by marking it on the board.
function KlotskiScreen:describeHintStep(_step, level)
    if level == 1 then
        return _("Move the marked block to the dashed box.")
    end
    return _("Hint played.")
end

-- Runs the solver search ahead of a hint or the solution when its answer
-- isn't known yet, behind a progress bar: from a fresh position the search
-- can take a couple of seconds on an e-reader (it appears after 0.2 s).
function KlotskiScreen:_planAhead()
    local b = self.board
    if b:isWon() or b:isShowingSolution() or b:hasPlan() then return end
    GenProgress.run(function(on_progress) b:plan(on_progress) end,
        { title = _("Thinking…") })
end

-- A hint can bring the big block home, so the round may end here.
-- A hint shown, even one only marked, rules out the optimal mark.
function KlotskiScreen:onHint()
    self:_planAhead()
    local b = self.board
    local used = b:getHintsUsed()
    ScreenBase.onHint(self)
    if (self.hint_cell or b:getHintsUsed() > used) and not b.hint_seen then
        b:noteHintSeen()
        self:_save()
    end
    if b:isWon() then
        self:_markSolved()
        self:_save()
    end
    self:_updateButtons()
    self:refreshActionBar()
end

function KlotskiScreen:onShowSolution()
    self:_planAhead()
    if not self.board:showSolution() then
        self:updateStatus(_("No hint is available here."))
        return
    end
    self.hint_cell = nil
    self:_save()
    self:_updateButtons()
    self:updateStatus()
end

function KlotskiScreen:onSolutionStep(dir)
    if self.board:solutionStep(dir) then
        self:_save()
        self:updateStatus()
    end
end

function KlotskiScreen:onNewGame()
    local band = self:_getBand()
    self:_startLevel(band, self:_nextUnsolved(band))
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- Today's level: picked from the bank by the daily seed, so everyone playing
-- the same difficulty gets the same one today.
function KlotskiScreen:onDailyGame()
    local band = self:_getBand()
    -- Eight classics would repeat within a week: their fans get an Expert.
    if band == "classic" then band = "expert" end
    local total = Levels.count(band)
    if total == 0 then return end
    local plugin = self.plugin
    local key = (plugin.getPluginId and plugin:getPluginId() or plugin.name) .. "_" .. band
    local index
    DailySeed.run(key, function() index = math.random(total) end)
    self:_startLevel(band, index, os.date("%Y-%m-%d"))
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function KlotskiScreen:openDifficultyMenu()
    local items = {}
    for _i, id in ipairs(Levels.BANDS) do
        items[#items + 1] = {
            id   = id,
            text = BAND_LABELS[id] .. " · " .. T(_("Solved: %1/%2 · minimum: %3"),
                self.progress:solvedCount(id), Levels.count(id), self.progress:optimalCount(id)),
        }
    end
    MenuHelper.openPickerMenu{
        title      = _("Difficulty"),
        items      = items,
        -- Wide enough for "Intermédiaire · Résolus : 600/600 · au minimum : 600".
        width_ratio = 0.9,
        current_id = self:_getBand(),
        parent     = self,
        on_select  = function(id)
            self.plugin:saveSetting("difficulty", id)
            self:onNewGame()
        end,
    }
end

-- Every level of the current difficulty, opened on the page of the level in
-- play; solved ones carry a check mark, a star if solved in the optimum.
function KlotskiScreen:openLevelMenu()
    local band = self:_getBand()
    local total = Levels.count(band)
    if total == 0 then return end
    local cur = (self.board.band == band and not self.board.daily) and self.board.index or nil
    local menu
    local item_table = {}
    for i = 1, total do
        local lv = Levels.get(band, i)
        item_table[i] = {
            text     = T("%1 · %2", lv.name and levelName(lv.name) or i, T(_("Optimal: %1"), lv.optimal)),
            mandatory = self.progress:mark(band, i),
            checked  = i == cur,
            callback = function()
                UIManager:close(menu)
                self:_startLevel(band, i)
                self:buildLayout()
                UIManager:setDirty(self, function() return "ui", self.dimen end)
            end,
        }
    end
    menu = Menu:new{
        title                  = T("%1 · %2", _("Level"), BAND_LABELS[band]),
        item_table             = item_table,
        width                  = math.floor(DeviceScreen:getWidth() * 0.8),
        height                 = math.floor(DeviceScreen:getHeight() * 0.9),
        disable_footer_padding = true,
        show_parent            = self,
    }
    if cur then menu:switchItemTable(nil, item_table, cur) end
    UIManager:show(menu)
    return menu
end

-- ---------------------------------------------------------------------------
-- Round over: a win, or the solution on show (one-way).
-- ---------------------------------------------------------------------------

function KlotskiScreen:isRoundOver()
    return self.board:isWon() or self.board:isShowingSolution()
end

function KlotskiScreen:getRoundOverButtons()
    local new_game = { text = _("New game"), callback = function() self:onNewGame() end }
    if self.board:isShowingSolution() then
        local back = { text = _("Step back"),    callback = function() self:onSolutionStep(-1) end }
        local fwd  = { text = _("Step forward"), callback = function() self:onSolutionStep(1) end }
        if self:isLandscape() then
            return { { back, fwd }, { new_game } }
        end
        return { { back, fwd, new_game } }
    end
    return { new_game }
end

-- ---------------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------------

function KlotskiScreen:_levelButtonText()
    local b = self.board
    if b.daily or not b.index then
        return T(_("Level: %1"), "–")
    end
    return T(_("Level: %1"), T("%1/%2", b.index, Levels.count(b.band)))
end

function KlotskiScreen:updateStatus(msg)
    local b = self.board
    local status
    if msg then
        status = msg
    elseif b:isShowingSolution() then
        status = T(_("Solution: move %1/%2"), b.sol_step, #b.solution)
    elseif b:isWon() then
        if b:isOptimalWin() then
            status = T(_("Solved in %1 moves, the optimum! Time: %2"), b:getMoves(), b.timer:format())
        elseif b.hint_seen or b:getHintsUsed() > 0 then
            -- Hints follow an optimal solution: no credit for the count.
            status = T(_("Solved with hints in %1 moves (optimal: %2). Time: %3"), b:getMoves(),
                b.optimal or "?", b.timer:format())
        else
            status = T(_("Solved in %1 moves (optimal: %2). Time: %3"), b:getMoves(), b.optimal or "?",
                b.timer:format())
        end
    else
        local where
        if b.daily then
            where = _("Daily Challenge")
        elseif b.name then
            where = levelName(b.name)
        elseif b.index then
            where = T(_("No. %1"), b.index)
        end
        status = self:joinStatus(
            BAND_LABELS[b.band],
            where,
            T(_("Moves: %1"), b:getMoves()),
            b.optimal and T(_("Optimal: %1"), b.optimal))
    end
    ScreenBase.updateStatus(self, status)
    -- Every move, hint, undo and reveal ends here, so the bar follows the board.
    self:refreshActionBar()
end

function KlotskiScreen:_updateButtons()
    if self.undo_btn then self.undo_btn:enableDisable(self.board:canUndo()) end
    if self.restart_btn then self.restart_btn:enableDisable(self.board:canUndo()) end
end

-- The level bank is only needed while the game is open: drop it when the
-- screen closes (the next game parses it again).
function KlotskiScreen:onCloseWidget()
    Levels.release()
end

return KlotskiScreen
