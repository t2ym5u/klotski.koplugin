-- ---------------------------------------------------------------------------
-- levels.lua — the level bank (levels_data.lua, built offline by tools/).
--
-- levels_data.lua returns one text: a band header per difficulty
-- ("# easy 400") and one line per level, the 20-character tray, its
-- optimal move count and that solution packed (see Solver.packPath; the
-- classics add their name). Each generated band is
-- sorted by optimal count, so level 1 is the gentlest of its band. Parsed
-- on first use, dropped by release() when the game closes.
-- ---------------------------------------------------------------------------

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

local Levels = {}

Levels.BANDS = { "easy", "medium", "hard", "expert", "classic" }
Levels.DEFAULT_BAND = "easy"

local bank

local function load()
    if bank then return bank end
    bank = {}
    for _, id in ipairs(Levels.BANDS) do bank[id] = {} end
    local chunk = loadfile(_dir .. "levels_data.lua")
    local ok, text = pcall(chunk or error)
    if not ok or type(text) ~= "string" then return bank end
    local band
    for line in text:gmatch("[^\n]+") do
        local b = line:match("^# (%a+)")
        if b then
            band = bank[b]
        elseif band then
            local str, d, packed, name = line:match("^([%.A%^v<>o]+) (%d+) (%S*) ?(.*)$")
            if str and #str == 20 then
                band[#band + 1] = { str = str, optimal = tonumber(d), packed = packed,
                                    name = name ~= "" and name or nil }
            end
        end
    end
    return bank
end

function Levels.isBand(id)
    for _, b in ipairs(Levels.BANDS) do
        if b == id then return true end
    end
    return false
end

-- Number of levels in a band.
function Levels.count(band)
    local t = load()[band]
    return t and #t or 0
end

-- Level `index` of `band`: { str, optimal, packed, name }, or nil.
function Levels.get(band, index)
    local t = load()[band]
    return t and t[index]
end

-- The bank (~70 KB of text, a few hundred KB parsed) is only needed while
-- the game is open: the screen drops it on close and the next use parses
-- it again (a few ms on a desktop).
function Levels.release()
    bank = nil
end

function Levels.isLoaded()
    return bank ~= nil
end

return Levels
