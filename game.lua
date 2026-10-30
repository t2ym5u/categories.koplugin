-- Categories game logic: letters, category draws, per-round scoring and
-- running totals. Pure Lua, no UI, so the specs can drive it headless.

local Game = {}
Game.__index = Game

-- Rough weight of each letter as the first letter of a word. A common letter
-- comes up more often than an awkward one, so most rounds stay playable.
Game.LETTER_WEIGHTS = {
    fr = { A = 4, B = 4, C = 5, D = 3, E = 3, F = 3, G = 3, H = 2, I = 2, J = 2,
           K = 1, L = 4, M = 5, N = 2, O = 2, P = 5, Q = 1, R = 4, S = 5, T = 4,
           U = 1, V = 3, W = 1, X = 1, Y = 1, Z = 1 },
    en = { A = 4, B = 5, C = 5, D = 4, E = 2, F = 4, G = 4, H = 4, I = 2, J = 2,
           K = 2, L = 4, M = 5, N = 3, O = 2, P = 5, Q = 1, R = 4, S = 6, T = 5,
           U = 1, V = 2, W = 3, X = 1, Y = 1, Z = 1 },
}

-- Letters left out unless "Hard letters" is on.
Game.HARD_LETTERS = {
    fr = { K = true, Q = true, W = true, X = true, Y = true, Z = true },
    en = { K = true, Q = true, U = true, X = true, Y = true, Z = true },
}

-- Points for an answer nobody else wrote / a shared answer / no answer.
Game.SCORINGS = {
    ["2-1"]  = { 2, 1, 0 },
    ["10-5"] = { 10, 5, 0 },
    ["3-1"]  = { 3, 1, 0 },
}
Game.SCORING_ORDER = { "2-1", "10-5", "3-1" }

-- Category packs (the `tag` of each category). `packs` is a set of the
-- selected ones; nil means the default selection.
Game.PACKS = { "classic", "fun", "geo", "history", "pop", "food", "absurd", "kids" }
Game.DEFAULT_PACKS = { classic = true, fun = true, geo = true, history = true, pop = true,
                       food = true, absurd = true }

-- Score levels stored per answer: 1 = unique, 2 = shared, 3 = none.
Game.UNIQUE, Game.SHARED, Game.NONE = 1, 2, 3

local function copyList(t)
    local out = {}
    for i, v in ipairs(t or {}) do out[i] = v end
    return out
end

-- opts: players (list of names), lang, nb_categories, hard_letters, packs (set),
-- scoring, bank (list of { text, tag }), rng (function(n) -> 1..n)
function Game.new(opts)
    local self = setmetatable({}, Game)
    self.rng           = opts.rng or math.random
    self.bank          = opts.bank or {}
    self.lang          = opts.lang or "en"
    self.nb_categories = opts.nb_categories or 8
    self.hard_letters  = opts.hard_letters and true or false
    self.packs         = opts.packs
    self.scoring       = Game.SCORINGS[opts.scoring] and opts.scoring or "2-1"
    self:newGame(opts.players or { "Player 1", "Player 2" })
    return self
end

function Game:newGame(players)
    self.players = {}
    for i, name in ipairs(players) do
        self.players[i] = { name = name, total = 0 }
    end
    self.round_no     = 0
    self.phase        = "setup"   -- setup | play | score | summary
    self.used_letters = {}
    self.used_cats    = {}
    self.round        = nil
    self.history      = {}        -- history[r][p] = points
end

-- ---------------------------------------------------------------------------
-- Draws
-- ---------------------------------------------------------------------------

function Game:allowedLetters()
    local weights = Game.LETTER_WEIGHTS[self.lang] or Game.LETTER_WEIGHTS.en
    local hard    = Game.HARD_LETTERS[self.lang] or Game.HARD_LETTERS.en
    local out = {}
    for code = 65, 90 do
        local l = string.char(code)
        if self.hard_letters or not hard[l] then
            out[#out + 1] = { letter = l, weight = weights[l] or 1 }
        end
    end
    return out
end

-- A weighted letter not yet drawn this game (all used: start over).
function Game:drawLetter()
    local pool = {}
    local total = 0
    for _, e in ipairs(self:allowedLetters()) do
        if not self.used_letters[e.letter] then
            pool[#pool + 1] = e
            total = total + e.weight
        end
    end
    if #pool == 0 then
        self.used_letters = {}
        return self:drawLetter()
    end
    local pick = self.rng(total)
    for _, e in ipairs(pool) do
        pick = pick - e.weight
        if pick <= 0 then
            self.used_letters[e.letter] = true
            return e.letter
        end
    end
    local last = pool[#pool].letter
    self.used_letters[last] = true
    return last
end

-- Category texts in the selected packs. A selection whose packs can't fill a
-- round (an empty pack in this language) falls back to the default packs.
function Game:eligibleCategories()
    local tags = self.packs or Game.DEFAULT_PACKS
    local out = {}
    for _, c in ipairs(self.bank) do
        if tags[c.tag] then out[#out + 1] = c.text end
    end
    if #out < self.nb_categories and tags ~= Game.DEFAULT_PACKS then
        local saved = self.packs
        self.packs = nil
        out = self:eligibleCategories()
        self.packs = saved
    end
    return out
end

-- n distinct categories, avoiding the ones already played this game until
-- the selection runs dry.
function Game:drawCategories(n)
    local all = self:eligibleCategories()
    local fresh = {}
    for _, text in ipairs(all) do
        if not self.used_cats[text] then fresh[#fresh + 1] = text end
    end
    if #fresh < n then
        self.used_cats = {}
        fresh = all
    end
    fresh = copyList(fresh)
    local out = {}
    for i = 1, math.min(n, #fresh) do
        local j = i - 1 + self.rng(#fresh - i + 1)
        fresh[i], fresh[j] = fresh[j], fresh[i]
        out[i] = fresh[i]
        self.used_cats[fresh[i]] = true
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Round flow
-- ---------------------------------------------------------------------------

function Game:startRound()
    self.round_no = self.round_no + 1
    local cats = self:drawCategories(self.nb_categories)
    local scores = {}
    for p = 1, #self.players do
        scores[p] = {}
        for c = 1, #cats do scores[p][c] = Game.NONE end
    end
    self.round = {
        letter     = self:drawLetter(),
        categories = cats,
        scores     = scores,
        typed      = {},
        score_page = 1,
    }
    self.phase = "play"
    return self.round
end

-- Stop! (or the timer ran out): on to scoring.
function Game:stopRound()
    if self.phase ~= "play" then return end
    self.phase = "score"
    self.round.score_page = 1
end

function Game:setTyped(c, text)
    if not self.round then return end
    if text == "" then text = nil end
    self.round.typed[c] = text
end

function Game:setScore(p, c, level)
    local r = self.round
    if not r or not r.scores[p] or not r.scores[p][c] then return end
    r.scores[p][c] = level
end

function Game:getScore(p, c)
    return self.round.scores[p][c]
end

function Game:points(level)
    return Game.SCORINGS[self.scoring][level] or 0
end

function Game:roundPoints(p)
    local r = self.round
    if not r or not r.scores[p] then return 0 end
    local sum = 0
    for _, level in ipairs(r.scores[p]) do sum = sum + self:points(level) end
    return sum
end

-- Number of categories in each pack ({ tag = n }).
function Game:packCounts()
    local out = {}
    for _, c in ipairs(self.bank) do out[c.tag] = (out[c.tag] or 0) + 1 end
    return out
end

-- Score page navigation (one page per player).
function Game:setScorePage(p)
    if not self.round then return end
    self.round.score_page = math.max(1, math.min(#self.players, p))
end

-- Adds the round's points to every total and records them.
function Game:finishRound()
    if self.phase ~= "score" then return end
    local row = {}
    for p, pl in ipairs(self.players) do
        row[p] = self:roundPoints(p)
        pl.total = pl.total + row[p]
    end
    self.history[#self.history + 1] = row
    self.phase = "summary"
end

-- Players sorted by total, best first (stable on ties: list order).
function Game:ranking()
    local idx = {}
    for i = 1, #self.players do idx[i] = i end
    table.sort(idx, function(a, b)
        local ta, tb = self.players[a].total, self.players[b].total
        if ta ~= tb then return ta > tb end
        return a < b
    end)
    return idx
end

function Game:isRoundOver()
    return self.phase == "summary"
end

-- ---------------------------------------------------------------------------
-- Save / restore
-- ---------------------------------------------------------------------------

local function keys(set)
    local out = {}
    for k in pairs(set) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local function toSet(list)
    local out = {}
    for _, k in ipairs(list or {}) do out[k] = true end
    return out
end

function Game:serialize()
    local r = self.round
    local round
    if r then
        local scores = {}
        for p, row in ipairs(r.scores) do scores[p] = copyList(row) end
        local typed = {}
        for c = 1, #r.categories do typed[c] = r.typed[c] or "" end
        round = {
            letter = r.letter, categories = copyList(r.categories), scores = scores,
            typed = typed, score_page = r.score_page, time_left = r.time_left,
        }
    end
    local players, history = {}, {}
    for i, p in ipairs(self.players) do players[i] = { name = p.name, total = p.total } end
    for i, row in ipairs(self.history) do history[i] = copyList(row) end
    return {
        version = 1, phase = self.phase, round_no = self.round_no,
        players = players, history = history, round = round,
        used_letters = keys(self.used_letters), used_cats = keys(self.used_cats),
    }
end

function Game:load(state)
    if type(state) ~= "table" or state.version ~= 1 or type(state.players) ~= "table"
        or #state.players == 0 then
        return false
    end
    self.players = {}
    for i, p in ipairs(state.players) do
        self.players[i] = { name = tostring(p.name or i), total = tonumber(p.total) or 0 }
    end
    self.round_no     = state.round_no or 0
    self.phase        = state.phase or "setup"
    self.history      = state.history or {}
    self.used_letters = toSet(state.used_letters)
    self.used_cats    = toSet(state.used_cats)
    local r = state.round
    if r and r.letter and type(r.categories) == "table" then
        local typed = {}
        for c, t in ipairs(r.typed or {}) do if t ~= "" then typed[c] = t end end
        self.round = {
            letter = r.letter, categories = r.categories, scores = r.scores or {},
            typed = typed, score_page = r.score_page or 1, time_left = r.time_left,
        }
        for p = 1, #self.players do
            self.round.scores[p] = self.round.scores[p] or {}
            for c = 1, #r.categories do
                self.round.scores[p][c] = self.round.scores[p][c] or Game.NONE
            end
        end
    else
        self.round = nil
        if self.phase ~= "setup" then self.phase = "setup" end
    end
    return true
end

return Game
