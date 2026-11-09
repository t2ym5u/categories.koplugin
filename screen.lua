local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputDialog     = require("ui/widget/inputdialog")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local RightContainer  = require("ui/widget/container/rightcontainer")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

-- French and English plurals: "1 point", "0 point" (fr) / "0 points" (en).
local function singular(n)
    if _.lang() == "fr" then return n >= -1 and n <= 1 end
    return n == 1 or n == -1
end

local MenuHelper = require("menu_helper")
local ScreenBase = require("screen_base")
local SeenHistory = require("seen_history")
local Game       = lrequire("game")
local W          = lrequire("widgets")

local DeviceScreen = Device.screen

local MAX_PLAYERS = 10
local TIMER_CHOICES = { 0, 60, 120, 180, 240, 300 }

local GAME_RULES_EN = [[
Categories — Rules

Each round the reader draws a letter and a list of categories. Every player writes, on paper, one answer per category starting with that letter: a country, a capital, a ridiculous name for a dog…

• Tap Draw a letter to start the round. The timer (if any) starts at once.
• Players write their answers on paper. One player may type theirs instead: tap a category on the reader to type an answer (it is shown on the first player's scoring page).
• When the timer ends, or when someone shouts and taps Stop!, the round is over.

Scoring: read the answers out loud, category by category. On each player's page, tap Unique when nobody else wrote the same answer, Shared when someone else did, None for no (or a wrong) answer. Previous / Next move between players; Finish round adds the points to the totals.

Settings: number of categories (6 to 12), timer (off or 1 to 5 minutes), category packs (classic, fun, geography, history & famous people, pop culture, food, absurd, kids), hard letters (K, Q, W, X, Y, Z…) and the points for a unique / shared answer.
]]

local GAME_RULES_FR = [[
Petit Bac — Règles

À chaque manche, la liseuse tire une lettre et une liste de catégories. Chaque joueur écrit, sur papier, une réponse par catégorie commençant par cette lettre : un pays, une capitale, un prénom de chien ridicule…

• Touchez « Tirer une lettre » pour lancer la manche. Le chrono (s'il y en a un) démarre aussitôt.
• Les joueurs écrivent sur papier. Un joueur peut taper ses réponses à la place : touchez une catégorie sur la liseuse pour saisir une réponse (elle apparaît sur la page de score du premier joueur).
• Quand le chrono sonne, ou quand quelqu'un crie et touche « Stop ! », la manche s'arrête.

Score : lisez les réponses à voix haute, catégorie par catégorie. Sur la page de chaque joueur, touchez « Unique » si personne d'autre n'a la même réponse, « Partagé » si quelqu'un l'a aussi, « Aucun » s'il n'y a pas de réponse (ou une fausse). « Précédent » / « Suivant » passent d'un joueur à l'autre ; « Fin de la manche » ajoute les points au total.

Réglages : nombre de catégories (6 à 12), chrono (aucun ou 1 à 5 minutes), paquets de catégories (classiques, drôles, géographie, histoire et célébrités, culture pop, cuisine, absurde, enfants), lettres difficiles (K, Q, W, X, Y, Z…) et points pour une réponse unique / partagée.
]]

-- "Categories" itself is a shared key translated "Catégories"; the game's
-- name ("Petit Bac" in French) needs a key of its own.
local NAME_KEY = "Categories (word game)"
local function gameName()
    local t = _(NAME_KEY)
    return t == NAME_KEY and "Categories" or t
end

local function loadBank(lang)
    local chunk = loadfile(_dir .. "content_" .. lang .. ".lua")
    local ok, data = pcall(chunk or error)
    return ok and type(data) == "table" and data or {}
end

local function packLabel(tag)
    local labels = {
        classic = _("Classic"),
        fun     = _("Fun"),
        kids    = _("Kids"),
        geo     = _("Geography"),
        history = _("History & famous people"),
        pop     = _("Pop culture"),
        food    = _("Food & drink"),
        absurd  = _("Absurd"),
    }
    return labels[tag] or tag
end

local function timerLabel(secs)
    if not secs or secs <= 0 then return _("Off") end
    return T(_("%1 min"), math.floor(secs / 60))
end

local function scoringLabel(id)
    local s = Game.SCORINGS[id]
    return T("%1 / %2", s[1], s[2])
end

-- ---------------------------------------------------------------------------

local CategoriesScreen = ScreenBase:extend{}
CategoriesScreen.gameName = gameName

function CategoriesScreen:init()
    local plugin = self.plugin
    self.lang     = plugin:getLang({ "fr", "en" })
    self.duration = plugin:getSetting("duration", 120)
    local names   = plugin:getSetting("players", nil)
    if type(names) ~= "table" or #names == 0 then
        names = { T(_("Player %1"), 1), T(_("Player %1"), 2), T(_("Player %1"), 3) }
    end
    self.game = Game.new{
        players       = names,
        lang          = self.lang,
        bank          = loadBank(self.lang),
        nb_categories = plugin:getSetting("nb_categories", 8),
        hard_letters  = plugin:getSetting("hard_letters", false),
        packs         = self:_loadPacks(),
        scoring       = plugin:getSetting("scoring", "2-1"),
        seen          = self:_openSeen(self.lang),
    }
    self.game:load(plugin:loadState())
    ScreenBase.init(self)
    if self.game.phase == "play" and self:_timeLeft() then
        self:_startCountdown()
    end
end

-- Categories drawn in earlier games (one history per content language), so
-- the next games bring new ones until the selection has been used up.
function CategoriesScreen:_openSeen(lang)
    return SeenHistory.open(self.plugin, "cats_" .. lang, { max = 1500 })
end

function CategoriesScreen:_loadPacks()
    local saved = self.plugin:getSetting("packs", nil)
    if type(saved) ~= "table" or #saved == 0 then return nil end
    local set = {}
    for _i, t in ipairs(saved) do set[t] = true end
    return set
end

function CategoriesScreen:serializeState()
    return self.game:serialize()
end

function CategoriesScreen:_save()
    self.plugin:saveState(self:serializeState())
end

function CategoriesScreen:_redraw()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Timer
-- ---------------------------------------------------------------------------

function CategoriesScreen:_timeLeft()
    local r = self.game.round
    return r and r.time_left
end

function CategoriesScreen:_startCountdown()
    self._tick_gen = (self._tick_gen or 0) + 1
    local gen = self._tick_gen
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

function CategoriesScreen:_stopCountdown()
    self._tick_gen = (self._tick_gen or 0) + 1
end

function CategoriesScreen:_timerText()
    local t = self:_timeLeft()
    if not t then return "—" end
    return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

function CategoriesScreen:_onTick(gen)
    if gen ~= self._tick_gen or self.game.phase ~= "play" then return end
    local r = self.game.round
    r.time_left = math.max(0, (r.time_left or 0) - 1)
    if r.time_left <= 0 then
        self:onStop(true)
        return
    end
    -- Only the timer changes: refresh just its frame.
    if self.timer_widget then
        self.timer_widget:setText(self:_timerText())
        UIManager:setDirty(self, function()
            return "fast", self.timer_frame and self.timer_frame.dimen or self.dimen
        end)
    end
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function CategoriesScreen:onDraw()
    self.list_page = 1
    local r = self.game:startRound()
    r.time_left = self.duration > 0 and self.duration or nil
    self:_save()
    self:_redraw()
    if r.time_left then self:_startCountdown() end
end

function CategoriesScreen:onStop(timed_out)
    self:_stopCountdown()
    self.score_sub = 1
    self.game:stopRound()
    self:_save()
    self:_redraw()
    if timed_out then self:showMessage(_("Time's up! Pens down."), 2) end
end

function CategoriesScreen:onScoreTap(row, level)
    local g = self.game
    g:setScore(g.round.score_page, row, level)
    self:_redraw()
end

-- Previous / Next walk through each player's pages (a long category list
-- on a small screen takes more than one).
function CategoriesScreen:onPrevPlayer()
    local g = self.game
    if (self.score_sub or 1) > 1 then
        self.score_sub = self.score_sub - 1
    elseif g.round.score_page > 1 then
        g:setScorePage(g.round.score_page - 1)
        self.score_sub = math.huge   -- clamped to the last page on build
    end
    self:_redraw()
end

function CategoriesScreen:onNextPlayer()
    local g = self.game
    if (self.score_sub or 1) < (self.score_pages_n or 1) then
        self.score_sub = self.score_sub + 1
        self:_redraw()
        return
    end
    self.score_sub = 1
    if g.round.score_page >= #g.players then
        g:finishRound()
        self:_save()
        self:_redraw()
        return
    end
    g:setScorePage(g.round.score_page + 1)
    self:_redraw()
end

function CategoriesScreen:onNextRound()
    self.game.phase = "setup"
    self:_save()
    self:_redraw()
end

function CategoriesScreen:onNewGame()
    self:_stopCountdown()
    local names = {}
    for i, p in ipairs(self.game.players) do names[i] = p.name end
    self.game:newGame(names)
    self:_save()
    self:_redraw()
end

function CategoriesScreen:openAnswerDialog(c)
    local g = self.game
    local dialog
    dialog = InputDialog:new{
        title = g.round.categories[c],
        input = g.round.typed[c] or "",
        input_hint = T(_("Starts with %1"), g.round.letter),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("OK"), is_enter_default = true, callback = function()
                local text = (dialog:getInputText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
                UIManager:close(dialog)
                g:setTyped(c, text)
                self:_save()
                self:_redraw()
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

function CategoriesScreen:openPlayersDialog()
    local names = {}
    for i, p in ipairs(self.game.players) do names[i] = p.name end
    local dialog
    dialog = InputDialog:new{
        title = _("Players"),
        description = T(_("One name per line (up to %1)."), MAX_PLAYERS),
        input = table.concat(names, "\n"),
        allow_newline = true,
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("OK"), callback = function()
                local text = dialog:getInputText() or ""
                UIManager:close(dialog)
                self:applyPlayerNames(text)
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- Same number of players: rename and keep the scores; otherwise a new game.
function CategoriesScreen:applyPlayerNames(text)
    local names = {}
    for raw in (text .. "\n"):gmatch("(.-)\n") do
        local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and #names < MAX_PLAYERS then names[#names + 1] = line end
    end
    if #names == 0 then return end
    self.plugin:saveSetting("players", names)
    local g = self.game
    if #names == #g.players then
        for i, n in ipairs(names) do g.players[i].name = n end
    else
        g:newGame(names)
    end
    self:_save()
    self:_redraw()
end

function CategoriesScreen:_picker(title, items, current, on_select)
    MenuHelper.openPickerMenu{
        title = title, items = items, current_id = current, parent = self,
        on_select = function(id)
            on_select(id)
            self:_redraw()
        end,
    }
end

function CategoriesScreen:openLangMenu()
    self:_picker(_("Language"),
        { { id = "fr", text = "Français" }, { id = "en", text = "English" } }, self.lang,
        function(lang)
            self.lang = lang
            self.plugin:setLang(lang)
            self.game.lang = lang
            self.game.bank = loadBank(lang)
            self.game.seen = self:_openSeen(lang)
            self.game.used_cats = {}
        end)
end

function CategoriesScreen:openCountMenu()
    local items = {}
    for n = 6, 12 do items[#items + 1] = { id = n, text = tostring(n) } end
    self:_picker(_("Categories"), items, self.game.nb_categories, function(n)
        self.game.nb_categories = n
        self.plugin:saveSetting("nb_categories", n)
    end)
end

function CategoriesScreen:openTimerMenu()
    local items = {}
    for _i, d in ipairs(TIMER_CHOICES) do items[#items + 1] = { id = d, text = timerLabel(d) } end
    self:_picker(_("Timer"), items, self.duration, function(d)
        self.duration = d
        self.plugin:saveSetting("duration", d)
    end)
end

-- The packs currently in play (the default selection when none is saved).
function CategoriesScreen:_packSet()
    return self.game.packs or Game.DEFAULT_PACKS
end

function CategoriesScreen:_packsText()
    if not self.game.packs then return T(_("Category packs: %1"), _("Default")) end
    local n = 0
    for _i, t in ipairs(Game.PACKS) do if self.game.packs[t] then n = n + 1 end end
    return T(_("Category packs: %1"), n .. "/" .. #Game.PACKS)
end

-- Multi-select: re-opens after each toggle.
function CategoriesScreen:openPacksMenu()
    local counts = self.game:packCounts()
    local set = self:_packSet()
    local items = { { id = "__default__",
        text = (self.game.packs and "  " or "★ ") .. _("Default (all but Kids)") } }
    for _i, t in ipairs(Game.PACKS) do
        items[#items + 1] = { id = t, text = (set[t] and "✓ " or "○ ") .. packLabel(t)
            .. string.format("  (%d)", counts[t] or 0) }
    end
    MenuHelper.openPickerMenu{
        title = _("Category packs"), items = items, parent = self,
        on_select = function(id)
            self:togglePack(id)
            self:_redraw()
            self:openPacksMenu()
        end,
    }
end

function CategoriesScreen:togglePack(id)
    local g = self.game
    if id == "__default__" then
        g.packs = nil
    else
        local set = {}
        for t in pairs(self:_packSet()) do set[t] = true end
        set[id] = not set[id] or nil
        local default, any = true, false
        for _i, t in ipairs(Game.PACKS) do
            if set[t] then any = true end
            if (set[t] or false) ~= (Game.DEFAULT_PACKS[t] or false) then default = false end
        end
        if default then
            g.packs = nil
        elseif any then
            g.packs = set
        end   -- the last pack can't be switched off
    end
    g.used_cats = {}
    local list = {}
    if g.packs then
        for _i, t in ipairs(Game.PACKS) do if g.packs[t] then list[#list + 1] = t end end
    end
    self.plugin:saveSetting("packs", list)
end

function CategoriesScreen:openScoringMenu()
    local items = {}
    for _i, id in ipairs(Game.SCORING_ORDER) do
        items[#items + 1] = { id = id, text = T(_("Unique %1 · Shared %2"),
            Game.SCORINGS[id][1], Game.SCORINGS[id][2]) }
    end
    self:_picker(_("Scoring"), items, self.game.scoring, function(id)
        self.game.scoring = id
        self.plugin:saveSetting("scoring", id)
    end)
end

function CategoriesScreen:toggleHardLetters()
    local g = self.game
    g.hard_letters = not g.hard_letters
    self.plugin:saveSetting("hard_letters", g.hard_letters)
    self:_redraw()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function CategoriesScreen:isRoundOver()
    return self.game:isRoundOver()
end

-- Landscape's narrow side panel gets one button per row.
function CategoriesScreen:getRoundOverButtons()
    local next_b = self:_bigButton(_("Next round"), function() self:onNextRound() end)
    local new_b  = self:_bigButton(_("New game"), function() self:onNewGame() end)
    if self:isLandscape() then return { { next_b }, { new_b } } end
    return { next_b, new_b }
end

function CategoriesScreen:_titleBar()
    local g = self.game
    return self:buildTitleBar(gameName(), function()
        return {
            { text = _("New game"), callback = function() self:onNewGame() end },
            { text = T(_("Language: %1"), self.lang:upper()), callback = function() self:openLangMenu() end },
            { text = T(_("Players: %1"), #g.players), callback = function() self:openPlayersDialog() end },
            { text = T(_("Categories: %1"), g.nb_categories), callback = function() self:openCountMenu() end },
            { text = T(_("Timer: %1"), timerLabel(self.duration)), callback = function() self:openTimerMenu() end },
            { text = self:_packsText(), callback = function() self:openPacksMenu() end },
            { text = T(_("Hard letters: %1"), g.hard_letters and _("On") or _("Off")),
              callback = function() self:toggleHardLetters() end },
            { text = T(_("Scoring: %1"), scoringLabel(g.scoring)), callback = function() self:openScoringMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)
end

-- Tall action-bar button: the players are in a hurry.
function CategoriesScreen:_bigButton(text, callback, extra)
    local b = { text = text, callback = callback,
                height = DeviceScreen:scaleBySize(64), font_size = 24 }
    for k, v in pairs(extra or {}) do b[k] = v end
    return b
end

function CategoriesScreen:_controls(rows, extra_top)
    self.status_text:setMaxWidth(self:getControlsWidth())
    local g = VerticalGroup:new{ align = "center" }
    if extra_top then
        g[#g + 1] = extra_top
        g[#g + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    end
    g[#g + 1] = self.status_text
    g[#g + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    g[#g + 1] = self:buildActionBar(rows)
    return g
end

function CategoriesScreen:_place(title_bar, content, controls)
    if self:isLandscape() then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            content,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, content,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
end

function CategoriesScreen:buildLayout()
    local phase = self.game.phase
    self.timer_widget, self.timer_frame = nil, nil
    if phase == "play" then
        self:_buildPlay()
    elseif phase == "score" then
        self:_buildScore()
    else
        self:_buildBoard()
    end
    self[1] = self.layout
    self:updateStatus()
end

-- Table of players: name · this round (when given) · total.
function CategoriesScreen:_scoreTable(width, max_h, round_row)
    local g = self.game
    local order = g:ranking()
    local n = #order
    local row_h = math.floor(math.min(max_h / math.max(n, 1), width * 0.11))
    local px = math.max(14, math.floor(row_h * 0.5))
    local name_w = math.floor(width * (round_row and 0.56 or 0.72))
    local col_w = math.floor((width - name_w) / (round_row and 2 or 1))
    local leader = g.players[order[1]].total
    local group = VerticalGroup:new{ align = "left" }
    for _i, p in ipairs(order) do
        local pl = g.players[p]
        local mark = (g.round_no > 0 and pl.total == leader and leader > 0) and "★ " or ""
        local row = HorizontalGroup:new{
            align = "center",
            LeftContainer:new{ dimen = Geom:new{ w = name_w, h = row_h },
                W.fitLine(mark .. pl.name, px, name_w - Size.padding.default, true) },
        }
        if round_row then
            row[#row + 1] = RightContainer:new{ dimen = Geom:new{ w = col_w, h = row_h },
                TextWidget:new{ text = "+" .. tostring(round_row[p] or 0), face = W.pxFace(px) } }
        end
        row[#row + 1] = RightContainer:new{ dimen = Geom:new{ w = col_w, h = row_h },
            TextWidget:new{ text = tostring(pl.total), face = W.pxFace(px, true), bold = true } }
        group[#group + 1] = row
    end
    return group
end

-- Setup (before a round) and summary (after it).
function CategoriesScreen:_buildBoard()
    local g = self.game
    local title_bar = self:_titleBar()
    local summary = g.phase == "summary"
    local controls = self:_controls({ self:_bigButton(_("Draw a letter"), function() self:onDraw() end) })
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large

    local heading = summary and T(_("Round %1 results"), g.round_no) or T(_("Round %1"), g.round_no + 1)
    local info
    if summary then
        local best = g.players[g:ranking()[1]]
        info = T(singular(best.total) and _("Leader: %1 (%2 point)") or _("Leader: %1 (%2 points)"), best.name, best.total)
    else
        info = self:joinStatus(T(_("%1 categories"), g.nb_categories),
            T(_("Timer: %1"), timerLabel(self.duration)), self:_packsText(),
            g.hard_letters and _("Hard letters") or nil)
    end
    local head = W.fitLine(heading, short * 0.1, bw, true)
    local info_w = TextBoxWidget:new{ text = info, face = Font:getFace("infofont"), width = bw,
                                      alignment = "center" }
    local used = head:getSize().h + info_w:getSize().h + 3 * vs
    local tbl = self:_scoreTable(math.floor(bw * 0.9), bh - used,
        summary and g.history[#g.history] or nil)
    local content = VerticalGroup:new{
        align = "center",
        head,
        VerticalSpan:new{ width = vs },
        info_w,
        VerticalSpan:new{ width = vs * 2 },
        tbl,
    }
    self:_place(title_bar, content, controls)
end

function CategoriesScreen:_letterBlock(side)
    local g = self.game
    local box = FrameContainer:new{
        bordersize = Size.border.thick * 2, padding = 0, margin = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = side, h = side },
            TextWidget:new{ text = g.round.letter, face = W.pxFace(side * 0.75, true), bold = true },
        },
    }
    local timer_px = math.floor(side * 0.42)
    self.timer_widget = TextWidget:new{ text = self:_timerText(), face = W.pxFace(timer_px, true),
                                        bold = true }
    self.timer_frame = FrameContainer:new{
        bordersize = 0, padding = 0, margin = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = W.fitLine("00:00", timer_px, 10000, true):getSize().w,
                              h = self.timer_widget:getSize().h },
            self.timer_widget,
        },
    }
    local right = VerticalGroup:new{
        align = "center",
        self:_timeLeft() and self.timer_frame
            or TextWidget:new{ text = _("No timer"), face = Font:getFace("infofont") },
        VerticalSpan:new{ width = Size.span.vertical_default },
        TextWidget:new{ text = T(_("Round %1"), g.round_no), face = Font:getFace("infofont") },
    }
    return HorizontalGroup:new{
        align = "center",
        box,
        HorizontalSpan:new{ width = side * 0.3 },
        right,
    }
end

function CategoriesScreen:_buildPlay()
    local g = self.game
    local title_bar = self:_titleBar()
    local land = self:isLandscape()
    local many = #g.round.categories > 8
    local letter_side = math.floor(math.min(self.dimen.w, self.dimen.h)
        * (land and 0.2 or (many and 0.12 or 0.16)))
    local items = {}
    for c, text in ipairs(g.round.categories) do
        items[c] = { label = text, answer = g.round.typed[c] }
    end
    local stop = self:_bigButton(_("Stop!"), function() self:onStop() end)
    local function controls(rows)
        return self:_controls(rows, land and self:_letterBlock(letter_side) or nil)
    end
    -- Size the list against the taller (paged) bar, so paging never makes
    -- the list too short for its own pages.
    local function paged_rows(n)
        local cur = self.list_page or 1
        return {
            { self:_bigButton("◀", function() self:onListPage(-1) end, { enabled = cur > 1 }),
              self:_bigButton("▶", function() self:onListPage(1) end, { enabled = cur < n }) },
            { stop },
        }
    end
    local block = not land and self:_letterBlock(letter_side) or nil
    local vs = Size.span.vertical_large
    local bw, bh = self:getBoardBudget(title_bar, controls({ stop }))
    local list_h = bh - (block and block:getSize().h + vs or 0)
    local px, pages = W.CategoryList.layoutPages(items, bw, list_h)
    local ctrl
    if #pages > 1 then
        local _w, bh2 = self:getBoardBudget(title_bar, controls(paged_rows(2)))
        list_h = bh2 - (block and block:getSize().h + vs or 0)
        px, pages = W.CategoryList.layoutPages(items, bw, list_h)
    end
    self.list_pages_n = #pages
    self.list_page = math.max(1, math.min(#pages, self.list_page or 1))
    if #pages > 1 then
        ctrl = controls(paged_rows(#pages))
    else
        ctrl = controls({ stop })
    end
    local pg = pages[self.list_page]
    local page_items = {}
    for c = pg[1], pg[2] do page_items[#page_items + 1] = items[c] end
    local list = W.CategoryList:new{ width = bw, items = page_items, first = pg[1], px = px,
        on_tap = function(c) self:openAnswerDialog(c) end }
    self.category_list = list
    local content = list
    if block then
        content = VerticalGroup:new{ align = "center", block, VerticalSpan:new{ width = vs }, list }
    end
    self:_place(title_bar, content, ctrl)
end

function CategoriesScreen:onListPage(delta)
    self.list_page = math.max(1, math.min(self.list_pages_n or 1, (self.list_page or 1) + delta))
    self:_redraw()
end

function CategoriesScreen:_buildScore()
    local g = self.game
    local r = g.round
    local p = r.score_page
    local title_bar = self:_titleBar()
    local function controls(prev_on, next_text)
        return self:_controls({
            self:_bigButton("◀ " .. _("Previous"), function() self:onPrevPlayer() end,
                { enabled = prev_on }),
            self:_bigButton(next_text, function() self:onNextPlayer() end),
        })
    end
    -- Same height whatever the labels: size the grid first, then build the
    -- real bar once the number of pages is known.
    local bw, bh = self:getBoardBudget(title_bar, controls(true, _("Finish round")))
    local vs = Size.span.vertical_default
    local head_px = math.min(bw, bh) * 0.065
    local head_h = W.fitLine("Ag", head_px, bw, true):getSize().h
    local labels = {}
    for c, text in ipairs(r.categories) do
        labels[c] = text
        if p == 1 and r.typed[c] then labels[c] = text .. "\n“" .. r.typed[c] .. "”" end
    end
    local px, pages = W.ScoreGrid.layoutPages(labels, bw, bh - head_h - vs)
    self.score_sub = math.max(1, math.min(#pages, self.score_sub or 1))
    self.score_pages_n = #pages
    local sub = self.score_sub
    local last = p >= #g.players and sub >= #pages
    local ctrl = controls(p > 1 or sub > 1, last and _("Finish round") or (_("Next") .. " ▶"))
    local pts = g:roundPoints(p)
    local head_text = T(singular(pts) and _("%1 — %2 point") or _("%1 — %2 points"), g.players[p].name, pts)
    if #pages > 1 then head_text = head_text .. string.format(" (%d/%d)", sub, #pages) end
    local head = W.fitLine(head_text, head_px, bw, true)
    local first, stop = pages[sub][1], pages[sub][2]
    local rows = {}
    for c = first, stop do
        rows[#rows + 1] = { label = labels[c], level = g:getScore(p, c) }
    end
    local grid = W.ScoreGrid:new{
        width = bw, rows = rows, px = px,
        headers = { _("Unique"), _("Shared"), _("None") },
        points = Game.SCORINGS[g.scoring],
        on_tap = function(row, level) self:onScoreTap(first + row - 1, level) end,
    }
    self.score_grid = grid
    local content = VerticalGroup:new{ align = "center", head, VerticalSpan:new{ width = vs }, grid }
    self:_place(title_bar, content, ctrl)
end

function CategoriesScreen:updateStatus(msg)
    if msg then ScreenBase.updateStatus(self, msg); return end
    local g = self.game
    local s
    if g.phase == "play" then
        s = _("Tap a category to type an answer.")
    elseif g.phase == "score" then
        s = self:joinStatus(T(_("Letter: %1"), g.round.letter),
            T(_("Player %1/%2"), g.round.score_page, #g.players))
    else
        s = self:joinStatus(T(_("Players: %1"), #g.players),
            g.round_no > 0 and T(_("Rounds played: %1"), g.round_no) or nil)
    end
    ScreenBase.updateStatus(self, s)
end

function CategoriesScreen:closeScreen()
    self:_stopCountdown()
    ScreenBase.closeScreen(self)
end

return CategoriesScreen
