-- busted specs for the Categories game logic and content banks.
package.path = "./?.lua;./common/?.lua;" .. package.path
local Game = require("game")

local function bank(lang) return dofile("content_" .. lang .. ".lua") end

local function newGame(opts)
    opts = opts or {}
    opts.players = opts.players or { "Ann", "Bob", "Cy" }
    opts.bank = opts.bank or bank(opts.lang or "fr")
    opts.lang = opts.lang or "fr"
    return Game.new(opts)
end

describe("content", function()
    for _, lang in ipairs({ "fr", "en" }) do
        it(lang .. " bank has at least 400 tagged, distinct categories", function()
            local b = bank(lang)
            assert.is_true(#b >= 900, "only " .. #b)
            local seen, tags = {}, {}
            for _, c in ipairs(b) do
                assert.is_string(c.text)
                assert.is_true(#c.text > 3)
                assert.is_nil(seen[c.text:lower()], "duplicate: " .. c.text)
                for _, bad in ipairs({ "hitler", "staline", "stalin", "mussolini", "pol pot", "ben laden" }) do
                    assert.is_nil(c.text:lower():find(bad, 1, true), c.text)
                end
                seen[c.text:lower()] = true
                local known = {}
                for _, t in ipairs(Game.PACKS) do known[t] = true end
                assert.is_true(known[c.tag], c.text)
                tags[c.tag] = (tags[c.tag] or 0) + 1
            end
            -- every pack holds about 120 categories (110 at least)
            for _, t in ipairs(Game.PACKS) do
                assert.is_true((tags[t] or 0) >= 110, t .. ": " .. tostring(tags[t]))
            end
        end)
    end
end)

describe("letters", function()
    it("skips hard letters by default and includes them when asked", function()
        local g = newGame()
        for _ = 1, 200 do
            local l = g:drawLetter()
            assert.is_nil(Game.HARD_LETTERS.fr[l], l)
        end
        local h = newGame{ hard_letters = true }
        local seen = {}
        for _ = 1, 26 do seen[h:drawLetter()] = true end
        local n = 0
        for _ in pairs(seen) do n = n + 1 end
        assert.are.equal(26, n)   -- no repeat until every letter came up
    end)

    it("does not repeat a letter within a game until the pool is exhausted", function()
        local g = newGame()
        local allowed = #g:allowedLetters()
        local seen = {}
        for _ = 1, allowed do
            local l = g:drawLetter()
            assert.is_nil(seen[l], "repeat " .. l)
            seen[l] = true
        end
        assert.is_string(g:drawLetter())  -- wraps around
    end)
end)

describe("categories draw", function()
    it("draws distinct categories from the chosen mix", function()
        local b = bank("fr")
        local kids = {}
        for _, c in ipairs(b) do if c.tag == "kids" then kids[c.text] = true end end
        local g = newGame{ packs = { kids = true }, nb_categories = 12 }
        local cats = g:drawCategories(12)
        assert.are.equal(12, #cats)
        local seen = {}
        for _, t in ipairs(cats) do
            assert.is_true(kids[t], t)
            assert.is_nil(seen[t]); seen[t] = true
        end
    end)

    it("falls back to the default packs when a selection is too small", function()
        local g = newGame{ packs = { nosuch = true }, nb_categories = 8 }
        assert.are.equal(8, #g:drawCategories(8))
        assert.is_true(g:packCounts().classic > 0)
    end)

    it("avoids repeats across rounds", function()
        local g = newGame{ packs = { classic = true }, nb_categories = 10 }
        local seen = {}
        for _ = 1, 5 do
            for _, t in ipairs(g:drawCategories(10)) do
                assert.is_nil(seen[t], t); seen[t] = true
            end
        end
    end)
end)

describe("round flow and scoring", function()
    it("plays a round, scores it and keeps running totals", function()
        local g = newGame{ nb_categories = 6, scoring = "2-1" }
        assert.are.equal("setup", g.phase)
        local r = g:startRound()
        assert.are.equal("play", g.phase)
        assert.are.equal(6, #r.categories)
        assert.are.equal(1, g.round_no)
        g:stopRound()
        assert.are.equal("score", g.phase)
        g:setScore(1, 1, Game.UNIQUE)
        g:setScore(1, 2, Game.SHARED)
        g:setScore(2, 1, Game.SHARED)
        assert.are.equal(3, g:roundPoints(1))
        assert.are.equal(1, g:roundPoints(2))
        assert.are.equal(0, g:roundPoints(3))
        assert.is_false(g:isRoundOver())
        g:finishRound()
        assert.is_true(g:isRoundOver())
        assert.are.equal(3, g.players[1].total)
        assert.are.same({ 1, 2, 3 }, g:ranking())

        g.phase = "setup"
        g:startRound(); g:stopRound()
        for c = 1, 6 do g:setScore(3, c, Game.UNIQUE) end
        g:finishRound()
        assert.are.equal(12, g.players[3].total)
        assert.are.same({ 3, 1, 2 }, g:ranking())
        assert.are.equal(2, #g.history)
    end)

    it("uses the configured points", function()
        local g = newGame{ scoring = "10-5" }
        g:startRound(); g:stopRound()
        g:setScore(1, 1, Game.UNIQUE); g:setScore(1, 2, Game.SHARED)
        assert.are.equal(15, g:roundPoints(1))
    end)

    it("ignores stop/finish outside their phase", function()
        local g = newGame()
        g:finishRound()
        assert.are.equal("setup", g.phase)
        g:stopRound()
        assert.are.equal("setup", g.phase)
    end)

    it("keeps typed answers, empty clears", function()
        local g = newGame()
        g:startRound()
        g:setTyped(2, "Paris")
        assert.are.equal("Paris", g.round.typed[2])
        g:setTyped(2, "")
        assert.is_nil(g.round.typed[2])
    end)
end)

describe("save / restore", function()
    it("round-trips a game in the middle of scoring", function()
        local g = newGame{ nb_categories = 7 }
        g:startRound(); g:setTyped(3, "Tokyo"); g:stopRound()
        g:setScore(2, 4, Game.UNIQUE); g:setScorePage(2)
        g.round.time_left = 42
        local s = g:serialize()
        local h = newGame{ players = { "x" } }
        assert.is_true(h:load(s))
        assert.are.equal("score", h.phase)
        assert.are.equal(3, #h.players)
        assert.are.equal(g.round.letter, h.round.letter)
        assert.are.same(g.round.categories, h.round.categories)
        assert.are.equal("Tokyo", h.round.typed[3])
        assert.is_nil(h.round.typed[1])
        assert.are.equal(Game.UNIQUE, h:getScore(2, 4))
        assert.are.equal(2, h.round.score_page)
        assert.are.equal(42, h.round.time_left)
        assert.is_true(h.used_letters[g.round.letter])
    end)

    it("restores a finished round as over", function()
        local g = newGame()
        g:startRound(); g:stopRound(); g:finishRound()
        local h = newGame()
        h:load(g:serialize())
        assert.is_true(h:isRoundOver())
    end)

    it("rejects garbage", function()
        local g = newGame()
        assert.is_false(g:load(nil))
        assert.is_false(g:load({ version = 99 }))
        assert.are.equal("setup", g.phase)
    end)
end)

describe("no repeat across games (SeenHistory)", function()
    local SeenHistory = require("seen_history")
    local function fakePlugin()
        local store = {}
        return {
            getSetting = function(_, k, d) if store[k] == nil then return d end return store[k] end,
            saveSetting = function(_, k, v) store[k] = v end,
            store = store,
        }
    end

    for _, lang in ipairs({ "fr", "en" }) do
        it(lang .. ": consecutive games draw new categories until the selection is used up", function()
            local plugin = fakePlugin()
            local function session()
                return newGame{ lang = lang, nb_categories = 12, packs = { geo = true },
                    seen = SeenHistory.open(plugin, "cats_" .. lang, { max = 1500 }) }
            end
            local pool = #session():eligibleCategories()
            local seen, drawn = {}, 0
            -- several sessions (a new Game, the history reopened from settings each time)
            while drawn + 12 <= pool do
                local g = session()
                local r = g:startRound()
                for _, c in ipairs(r.categories) do
                    assert.is_nil(seen[c], "repeated before the pool ran out: " .. c)
                    seen[c] = true
                    drawn = drawn + 1
                end
            end
            assert.is_true(drawn >= 100)
            -- the pool runs out: the next draws still give a full, distinct round
            local g = session()
            for _ = 1, 3 do
                local r = g:startRound()
                assert.are.equal(12, #r.categories)
                local d = {}
                for _, c in ipairs(r.categories) do assert.is_nil(d[c]); d[c] = true end
            end
        end)
    end

    it("keeps one history per language", function()
        local plugin = fakePlugin()
        newGame{ lang = "fr", seen = SeenHistory.open(plugin, "cats_fr") }:startRound()
        assert.is_table(plugin.store.seen_cats_fr)
        assert.is_nil(plugin.store.seen_cats_en)
    end)
end)

describe("content families", function()
    it("no category text is shared between packs or appears twice", function()
        for _, lang in ipairs({ "fr", "en" }) do
            local seen = {}
            for _, c in ipairs(bank(lang)) do
                local k = c.text:lower():gsub("%s+", " ")
                assert.is_nil(seen[k], lang .. " duplicate: " .. c.text)
                seen[k] = c.tag
            end
        end
    end)
end)
