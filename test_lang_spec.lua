-- Content language: the game deals KOReader's language (French when
-- KOReader is in French), unless a language was picked in the game's menu
-- while KOReader had its current language. A language saved by an older
-- version (plain "lang", no "lang_ko") is dropped: it used to stick for good.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

-- KOReader is not there: every module the screen requires that is not in
-- this plugin or common/ is a permissive stub (any field is a stub, a call
-- returns its first number or string argument, arithmetic gives 0).
local permissive
local function first_value(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "number" or type(v) == "string" then return v end
    end
    return permissive()
end
local function zero() return 0 end
permissive = function()
    return setmetatable({}, {
        __index = function(t, k) local v = permissive(); rawset(t, k, v); return v end,
        __call = function(_, ...) return first_value(...) end,
        __add = zero, __sub = zero, __mul = zero, __div = zero, __unm = zero,
        __mod = zero, __idiv = zero,
        __concat = function() return "" end,
        __lt = function() return false end, __le = function() return false end,
    })
end
local function stubSearcher(name)
    return function() return permissive() end, name
end

-- The screen's base class: init does nothing (no layout).
local ScreenBase = {}
ScreenBase.__index = ScreenBase
function ScreenBase:extend(o) o = o or {}; o.__index = o; return setmetatable(o, self) end
function ScreenBase.init() end

-- The language menu: remember the picker it opens.
local picker
local MenuHelper = setmetatable({
    openPickerMenu = function(o) picker = o end,
}, { __index = function() return function() end end })

local PRELOADS = {
    screen_base = function() return ScreenBase end,
    menu_helper = function() return MenuHelper end,
    i18n = function()
        return setmetatable({ lang = function() return "fr" end, extend = function() end },
            { __call = function(_, s) return s end })
    end,
    ["ui/widget/container/widgetcontainer"] = function()
        return { extend = function(self, o) o = o or {}; o.__index = o; return setmetatable(o, { __index = self }) end }
    end,
}

local saved = {}
local PluginBase

local function koreader(lang)
    _G.G_reader_settings = { readSetting = function(_, k) if k == "language" then return lang end end }
end

-- A plugin whose settings live in a plain table.
local function newPlugin(store)
    store = store or {}
    local p = setmetatable({}, { __index = PluginBase })
    p.ensureSettings = function() end
    p.settings = {
        readSetting = function(_, k) return store[k] end,
        saveSetting = function(_, k, v) store[k] = v end,
        flush = function() end,
    }
    return p, store
end

local function setupHarness()
    saved.path = package.path
    saved.G = _G.G_reader_settings
    saved.preload = {}
    for name, f in pairs(PRELOADS) do
        saved.preload[name] = package.preload[name]
        package.preload[name] = f
    end
    saved.loaded = {}
    for k, v in pairs(package.loaded) do saved.loaded[k] = v end
    for name in pairs(PRELOADS) do package.loaded[name] = nil end
    package.path = DIR .. "?.lua;" .. DIR .. "common/?.lua;" .. package.path
    local searchers = package.searchers or package.loaders
    searchers[#searchers + 1] = stubSearcher
    PluginBase = dofile(DIR .. "common/plugin_base.lua")
end

local function teardownHarness()
    local searchers = package.searchers or package.loaders
    for i = #searchers, 1, -1 do
        if searchers[i] == stubSearcher then table.remove(searchers, i) end
    end
    for name, v in pairs(saved.preload) do package.preload[name] = v end
    for k in pairs(package.loaded) do
        if saved.loaded[k] == nil then package.loaded[k] = nil end
    end
    for k, v in pairs(saved.loaded) do package.loaded[k] = v end
    package.path = saved.path
    _G.G_reader_settings = saved.G
end

-- Picks `lang` in the screen's language menu.
local function pickLang(screen, lang)
    picker = nil
    screen:openLangMenu()
    assert.is_table(picker, "the language menu opened no picker")
    picker.on_select(lang)
end

local Screen
local GAME, SCREEN = "Categories", "screen.lua"
local CONTENT = {
    fr = { "content_fr.lua" },
    en = { "content_en.lua" },
}

local function dealt(screen)
    local out = {}
    for i, c in ipairs(screen.game.bank) do
        if i > 20 then break end
        out[#out + 1] = c.text
    end
    return out
end

-- Every string in the given content files.
local function strings(paths)
    local set = {}
    local function walk(v)
        if type(v) == "string" then set[v] = true
        elseif type(v) == "table" then for _k, x in pairs(v) do walk(x) end end
    end
    for _i, path in ipairs(paths) do walk(dofile(DIR .. path)) end
    return set
end

-- The screen plays `lang`: everything it deals comes from that language's
-- content, and some of it is not in the other language's.
local function dealsIn(screen, lang)
    if screen.lang ~= lang then return false end
    local mine = strings(CONTENT[lang])
    local other = strings(CONTENT[lang == "fr" and "en" or "fr"])
    local items = dealt(screen)
    assert.is_true(#items > 0, "nothing dealt")
    local own = false
    for _i, s in ipairs(items) do
        if not mine[s] then return false end
        if not other[s] then own = true end
    end
    return own
end

local function open(store)
    local s = setmetatable({ plugin = (newPlugin(store)) }, Screen)
    for _i, name in ipairs({ "_redraw", "buildLayout", "_relayout", "refresh" }) do
        s[name] = function() end
    end
    s:init()
    return s
end

describe(GAME .. " content language", function()
    setup(function()
        setupHarness()
        Screen = dofile(DIR .. SCREEN)
    end)
    teardown(teardownHarness)

    it("deals French content when KOReader is in French", function()
        koreader("fr")
        assert.is_true(dealsIn(open(), "fr"))
        koreader("en_US")
        assert.is_true(dealsIn(open(), "en"))
    end)

    it("no longer keeps English saved by an older version (no lang_ko)", function()
        koreader("fr")
        assert.is_true(dealsIn(open({ lang = "en" }), "fr"))
    end)

    it("keeps a language picked in the game while KOReader's stays the same", function()
        koreader("fr")
        local store = {}
        local s = open(store)
        pickLang(s, "en")
        assert.is_true(dealsIn(s, "en"))
        assert.is_true(dealsIn(open(store), "en"))
        koreader("en")
        pickLang(open(store), "fr")
        assert.is_true(dealsIn(open(store), "fr"))
        koreader("fr")
        assert.is_true(dealsIn(open(store), "fr"))   -- KOReader's, the choice is on hold
        koreader("en")
        assert.is_true(dealsIn(open(store), "fr"))   -- the choice holds again
    end)
end)
