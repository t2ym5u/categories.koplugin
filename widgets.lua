-- Widgets for the Categories screen: the category list shown while players
-- write (tap a row to type an answer) and the per-player scoring grid.

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local VerticalGroup   = require("ui/widget/verticalgroup")

local DeviceScreen = Device.screen

-- Font:getFace() scales by DPI: pixel-derived sizes are divided back first.
local DPI_SCALE = DeviceScreen:scaleBySize(1000) / 1000

local W = {}

function W.pxFace(px, bold)
    return Font:getFace(bold and "tfont" or "cfont", math.max(8, math.floor(px / DPI_SCALE)))
end

-- One line at up to px, shrunk until it fits max_w.
function W.fitLine(text, px, max_w, bold, fgcolor)
    local tw
    while true do
        tw = TextWidget:new{ text = text, face = W.pxFace(px, bold), bold = bold,
                             fgcolor = fgcolor }
        if tw:getSize().w <= max_w or px <= 12 then break end
        tw:free()
        px = math.floor(px * 0.9)
    end
    if tw:getSize().w > max_w then
        tw:free()
        tw = TextWidget:new{ text = text, face = W.pxFace(px, bold), bold = bold,
                             fgcolor = fgcolor, max_width = max_w }
    end
    return tw
end

local function hline(w)
    return LineWidget:new{
        background = Blitbuffer.COLOR_GRAY,
        dimen = Geom:new{ w = w, h = Size.line.thin },
    }
end

-- ---------------------------------------------------------------------------
-- CategoryList: numbered rows over the full width, a typed answer on a
-- second line ("→ Paris"). Same readable-minimum font as the score grid: a
-- list that doesn't fit at that size is paged (CategoryList.layoutPages).
-- ---------------------------------------------------------------------------

W.CategoryList = InputContainer:extend{
    width  = nil,
    items  = nil,     -- { { label = "...", answer = "..."|nil }, ... } (this page)
    first  = 1,       -- category number of items[1]
    px     = nil,     -- from layoutPages
    on_tap = nil,     -- function(category_index)
}

local LIST_PAD = Size.padding.small

local function listText(it)
    return it.answer and (it.label .. "\n→ " .. it.answer) or it.label
end

local function listColumns(width, px)
    local num_w = math.floor(px * 1.8)
    return num_w, width - num_w - LIST_PAD
end

local function listRowHeights(items, width, px)
    local _n, text_w = listColumns(width, px)
    local out = {}
    for i, it in ipairs(items) do
        local tb = TextBoxWidget:new{ text = listText(it), face = W.pxFace(px), width = text_w }
        out[i] = math.max(DeviceScreen:scaleBySize(34), tb:getSize().h + 2 * LIST_PAD)
            + Size.line.thin
        tb:free()
    end
    return out
end

-- Returns px, pages = { { first, last }, ... } for `height`.
function W.CategoryList.layoutPages(items, width, height)
    local min_px = DeviceScreen:scaleBySize(17)
    local px = math.max(min_px, math.min(width * 0.05, DeviceScreen:scaleBySize(26)))
    local heights
    while true do
        heights = listRowHeights(items, width, px)
        local sum = 0
        for _, h in ipairs(heights) do sum = sum + h end
        if sum <= height or px <= min_px then break end
        px = math.max(min_px, math.floor(px * 0.92))
    end
    return px, W.splitPages(heights, height)
end

-- Splits row heights into pages of at most `limit`, evened out so the last
-- page isn't a lone straggler.
function W.splitPages(heights, limit)
    local function split(lim)
        local pages, first, acc = {}, 1, 0
        for i, h in ipairs(heights) do
            if acc + h > lim and i > first then
                pages[#pages + 1] = { first, i - 1 }
                first, acc = i, 0
            end
            acc = acc + h
        end
        pages[#pages + 1] = { first, #heights }
        return pages
    end
    local pages = split(limit)
    if #pages > 1 then
        local sum, max_h = 0, 0
        for _, h in ipairs(heights) do sum = sum + h; max_h = math.max(max_h, h) end
        local even = split(math.min(limit, math.ceil(sum / #pages) + max_h / 2))
        if #even == #pages then pages = even end
    end
    return pages
end

function W.CategoryList:init()
    local num_w, text_w = listColumns(self.width, self.px)
    local heights = listRowHeights(self.items, self.width, self.px)
    self.row_y = {}
    local y = 0
    local group = VerticalGroup:new{ align = "left" }
    for i, it in ipairs(self.items) do
        self.row_y[i] = { y, heights[i] }
        y = y + heights[i]
        local h = heights[i] - Size.line.thin
        group[#group + 1] = HorizontalGroup:new{
            align = "center",
            CenterContainer:new{
                dimen = Geom:new{ w = num_w, h = h },
                TextWidget:new{ text = tostring(self.first + i - 1),
                                face = W.pxFace(self.px * 1.1, true), bold = true },
            },
            LeftContainer:new{
                dimen = Geom:new{ w = text_w + LIST_PAD, h = h },
                TextBoxWidget:new{ text = listText(it), face = W.pxFace(self.px), width = text_w },
            },
        }
        group[#group + 1] = hline(self.width)
    end
    self[1] = group
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = group:getSize().h }
    self.ges_events = {
        TapRow = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function W.CategoryList:getSize()
    return Geom:new{ w = self.width, h = self.dimen.h }
end

function W.CategoryList:onTapRow(_, ges)
    local ry = ges.pos.y - self.dimen.y
    for i, r in ipairs(self.row_y) do
        if ry >= r[1] and ry < r[1] + r[2] then
            if self.on_tap then self.on_tap(self.first + i - 1) end
            return true
        end
    end
end

-- ---------------------------------------------------------------------------
-- ScoreGrid: one row per category, three cells (unique / shared / none).
--
-- Labels get a font no smaller than a readable minimum and wrap freely; a
-- long list is split into pages (ScoreGrid.layoutPages) rather than shrunk
-- until it no longer reads on a 6" screen.
-- ---------------------------------------------------------------------------

W.ScoreGrid = InputContainer:extend{
    width   = nil,
    rows    = nil,    -- { { label = "...", level = 1..3 }, ... } (this page)
    px      = nil,    -- label font size, from layoutPages
    headers = nil,    -- { "Unique", "Shared", "None" }
    points  = nil,    -- { 2, 1, 0 }
    on_tap  = nil,    -- function(row_on_page, level)
}

local GRID_PAD = Size.padding.small

local function gridColumns(width)
    local label_w = math.floor(width * 0.6)
    return label_w, math.floor((width - label_w) / 3)
end

local function minCellH()
    return DeviceScreen:scaleBySize(40)
end

-- Height of each label's row at px.
local function rowHeights(labels, width, px)
    local label_w = gridColumns(width)
    local out = {}
    for i, t in ipairs(labels) do
        local tb = TextBoxWidget:new{ text = t, face = W.pxFace(px), width = label_w - GRID_PAD }
        out[i] = math.max(minCellH(), tb:getSize().h + 2 * GRID_PAD)
        tb:free()
    end
    return out
end

function W.ScoreGrid.headerHeight(width)
    local _l, cell_w = gridColumns(width)
    local tw = W.fitLine("Ag", math.min(DeviceScreen:scaleBySize(16), cell_w * 0.2), cell_w, true)
    local h = tw:getSize().h + 2 * GRID_PAD
    tw:free()
    return h
end

-- Picks the label font and splits the rows into pages that fit `height`.
-- Returns px, pages = { { first, last }, ... }. The whole list on one page
-- is preferred down to the minimum font; below that it pages.
function W.ScoreGrid.layoutPages(labels, width, height)
    local avail = height - W.ScoreGrid.headerHeight(width)
    local min_px = DeviceScreen:scaleBySize(17)
    local px = math.max(min_px, math.min(width * 0.045, DeviceScreen:scaleBySize(24)))
    local heights
    while true do
        heights = rowHeights(labels, width, px)
        local sum = 0
        for _, h in ipairs(heights) do sum = sum + h end
        if sum <= avail or px <= min_px then break end
        px = math.max(min_px, math.floor(px * 0.92))
    end
    local pages = W.splitPages(heights, avail)
    return px, pages
end

function W.ScoreGrid:init()
    local pad = GRID_PAD
    self.label_w, self.cell_w = gridColumns(self.width)
    local hdr_px = math.min(DeviceScreen:scaleBySize(16), self.cell_w * 0.2)
    self.header_h = W.ScoreGrid.headerHeight(self.width)
    local hdr = HorizontalGroup:new{ HorizontalSpan:new{ width = self.label_w } }
    for i = 1, 3 do
        hdr[#hdr + 1] = CenterContainer:new{
            dimen = Geom:new{ w = self.cell_w, h = self.header_h },
            W.fitLine(self.headers[i], hdr_px, self.cell_w - 2 * pad, true) }
    end

    local labels = {}
    for i, r in ipairs(self.rows) do labels[i] = r.label end
    local heights = rowHeights(labels, self.width, self.px)
    local cell_h = minCellH() - 2 * pad
    local digit_px = math.min(cell_h * 0.7, self.cell_w * 0.4)
    local thick = Size.border.thick

    self.row_y = {}
    local y = self.header_h
    local group = VerticalGroup:new{ align = "left", hdr }
    for i, r in ipairs(self.rows) do
        self.row_y[i] = { y, heights[i] }
        y = y + heights[i]
        local row = HorizontalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = self.label_w, h = heights[i] },
                TextBoxWidget:new{ text = r.label, face = W.pxFace(self.px),
                                   width = self.label_w - pad },
            },
        }
        local box_h = math.min(heights[i] - 2 * pad, math.floor(cell_h * 1.4))
        for level = 1, 3 do
            local on = r.level == level
            local b = on and 0 or thick
            row[#row + 1] = CenterContainer:new{
                dimen = Geom:new{ w = self.cell_w, h = heights[i] },
                FrameContainer:new{
                    bordersize = b, padding = 0, margin = 0,
                    background = on and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
                    CenterContainer:new{
                        dimen = Geom:new{ w = self.cell_w - 2 * pad - 2 * b, h = box_h - 2 * b },
                        TextWidget:new{
                            text = tostring(self.points[level]),
                            face = W.pxFace(digit_px, true), bold = true,
                            fgcolor = on and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
                        },
                    },
                },
            }
        end
        group[#group + 1] = row
    end
    self[1] = group
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = group:getSize().h }
    self.ges_events = {
        TapCell = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function W.ScoreGrid:getSize()
    return Geom:new{ w = self.width, h = self.dimen.h }
end

-- Row (on this page) and level under a screen position, or nil.
function W.ScoreGrid:cellAt(x, y)
    local rx, ry = x - self.dimen.x, y - self.dimen.y
    if rx < self.label_w then return nil end
    local level = math.floor((rx - self.label_w) / self.cell_w) + 1
    if level < 1 or level > 3 then return nil end
    for i, ry_h in ipairs(self.row_y) do
        if ry >= ry_h[1] and ry < ry_h[1] + ry_h[2] then return i, level end
    end
end

-- Screen rectangle of a cell (for specs / harnesses).
function W.ScoreGrid:getCellRect(row, level)
    local ry = self.row_y[row]
    return Geom:new{
        x = self.dimen.x + self.label_w + (level - 1) * self.cell_w,
        y = self.dimen.y + ry[1], w = self.cell_w, h = ry[2],
    }
end

function W.ScoreGrid:onTapCell(_, ges)
    local row, level = self:cellAt(ges.pos.x, ges.pos.y)
    if row and self.on_tap then
        self.on_tap(row, level)
        return true
    end
end

return W
