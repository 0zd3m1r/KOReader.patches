--https://github.com/0zd3m1r/KOReader.patches/--
--[[ Title overlay - just text, no complex widgets ]]--
local Blitbuffer = require("ffi/blitbuffer")

--========================== [[Edit your preferences here]] ================================
local show_for_unread = true                    -- Show for unread books
local show_for_reading = true                   -- Show for books in progress
local show_for_finished = true                 -- Show for finished books
local title_font_size = 0.5                     -- Title font size (bigger)
local author_font_size = 0.3                    -- Author font size (smaller)
local text_color = Blitbuffer.COLOR_WHITE
local bg_color = Blitbuffer.COLOR_BLACK
local border_color = Blitbuffer.COLOR_BLACK
local max_chars_title = 30                      -- Max chars for title per line
local max_chars_author = 30                     -- Max chars for author
local radius_size = 0                          -- Border radius

--==========================================================================================

local userpatch = require("userpatch")
local logger = require("logger")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Screen = require("device").screen

local function cleanTitle(text)
    if not text then return nil end
    local title = text
    title = title:gsub("%s*%b()%s*$", "")
    title = title:gsub("%s*%d+%s*[Pp]%.?%s*$", "")
    title = title:gsub("%s*%d+%.%d+%s*[MKmk][Bb]%s*$", "")
    title = title:gsub("%.epub$", "")
    title = title:gsub("%.kepub%.epub$", "")
    title = title:gsub("%.pdf$", "")
    title = title:gsub("%.kepub$", "")
    title = title:gsub("_", " ")
    title = title:match("^%s*(.-)%s*$")
    return title
end

-- Split by "-" into book title and author
local function splitTitleAuthor(text)
    if not text or text == "" then
        return "", ""
    end
    
    -- Find the last "-" separator
    local last_dash = nil
    local pos = 1
    while true do
        local found = text:find("%s*-%s*", pos)
        if found then
            last_dash = found
            pos = found + 1
        else
            break
        end
    end
    
    if last_dash then
        local book_title = text:sub(1, last_dash - 1):match("^%s*(.-)%s*$")
        local author = text:sub(last_dash):gsub("^%s*-%s*", ""):match("^%s*(.-)%s*$")
        return book_title, author
    else
        return text, ""
    end
end

-- Truncate text if too long
local function truncateText(text, max_len)
    if not text or text == "" then return "" end
    if #text > max_len then
        return text:sub(1, max_len - 2) .. ".."
    end
    return text
end

local function patchCoverBrowserTitle(plugin)
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    local origPaintTo = MosaicMenuItem.paintTo
    
    function MosaicMenuItem:paintTo(bb, x, y)
        origPaintTo(self, bb, x, y)
        
        local ok, err = pcall(function()
            local cover = self[1][1][1]
            if not cover or not cover.dimen then return end
            
            if self.is_directory or self.file_deleted then return end
            
            -- Check if we should show based on book status
            local should_show = false
            
            if show_for_unread and not self.been_opened and self.status ~= "complete" then
                should_show = true
            end
            
            if show_for_reading and self.been_opened and self.status ~= "complete" then
                should_show = true
            end
            
            if show_for_finished and self.status == "complete" then
                should_show = true
            end
            
            if not should_show then return end
            
            local raw_title = cleanTitle(self.text)
            if not raw_title or #raw_title == 0 then return end
            
            local cover_w = cover.dimen.w
            local cover_h = cover.dimen.h
            local cover_x = x + math.floor((self.width - cover_w) / 2)
            local cover_y = y + math.floor((self.height - cover_h) / 2)
            
            local max_width = math.floor(cover_w * 0.9)
            local title_fsize = Screen:scaleBySize(math.floor(10 * title_font_size))
            local author_fsize = Screen:scaleBySize(math.floor(10 * author_font_size))
            
            -- Split into book title and author
            local book_title, author = splitTitleAuthor(raw_title)
            
            -- Convert to uppercase and truncate
            book_title = string.upper(truncateText(book_title, max_chars_title))
            if author ~= "" then
                author = string.upper(truncateText(author, max_chars_author))
            end
            
            -- Create title widget (bigger font)
            local title_widget = TextWidget:new{
                text = book_title,
                face = Font:getFace("cfont", title_fsize),
                fgcolor = text_color,
                bold = true,
                max_width = max_width,
            }
            
            local content
            
            if author ~= "" then
                -- Create author widget (smaller font)
                local author_widget = TextWidget:new{
                    text = author,
                    face = Font:getFace("cfont", author_fsize),
                    fgcolor = text_color,
                    bold = true,
                    max_width = max_width,
                }
                
                -- Vertical group for both lines
                content = VerticalGroup:new{
                    align = "center",
                    title_widget,
                    author_widget,
                }
            else
                content = title_widget
            end
            
            -- Container
            local container = FrameContainer:new{
                bordersize = 2,
                radius = radius_size, --Screen:scaleBySize(8),
                color = border_color,
                background = bg_color,
                padding = Screen:scaleBySize(5),
                margin = 0,
                content,
            }
            
            -- Position: center horizontally, near bottom vertically
            local cont_w = container:getSize().w
            local cont_h = container:getSize().h
            
            local pos_x = cover_x + math.floor((cover_w - cont_w) / 2)
            local pos_y = cover_y + math.floor((cover_h - cont_h) / 2)
            
            -- Draw
            container:paintTo(bb, pos_x, pos_y)
        end)
        
        if not ok then
            logger.warn("Title error:", err)
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverBrowserTitle)
