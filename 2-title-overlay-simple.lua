--https://github.com/0zd3m1r/KOReader.patches/--
--[[ Ultra simple title overlay - just text, no complex widgets ]]--
local Blitbuffer = require("ffi/blitbuffer")

--========================== [[Edit your preferences here]] ================================
local show_for_unread = true                    -- Show for unread books
local show_for_reading = true                   -- Show for books in progress
local show_for_finished = false                 -- Show for finished books
local font_size = 0.6                           -- Smaller font (was 0.8)
local text_color = Blitbuffer.COLOR_WHITE
local bg_color = Blitbuffer.COLOR_BLACK
local border_color = Blitbuffer.COLOR_WHITE
local max_width_percent = 0.75                  -- Max 75% of cover width

--==========================================================================================

local userpatch = require("userpatch")
local logger = require("logger")
local TextWidget = require("ui/widget/textwidget")
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
    title = title:match("^%s*(.-)%s*$")
    if #title > 50 then
        title = title:sub(1, 47) .. "..."
    end
    return title
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
            
            local title = cleanTitle(self.text)
            if not title or #title == 0 then return end
            
            local cover_w = cover.dimen.w
            local cover_h = cover.dimen.h
            local cover_x = x + math.floor((self.width - cover_w) / 2)
            local cover_y = y + math.floor((self.height - cover_h) / 2)
            
            -- Calculate max width based on cover
            local max_width = math.floor(cover_w * max_width_percent)
            local fsize = Screen:scaleBySize(math.floor(10 * font_size))
            
            -- Simple text widget
            local text_widget = TextWidget:new{
                text = title,
                face = Font:getFace("cfont", fsize),
                fgcolor = text_color,
                bold = true,
                max_width = max_width,  -- Limit width
            }
            
            -- Container
            local container = FrameContainer:new{
                bordersize = 2,
                radius = Screen:scaleBySize(8),
                color = border_color,
                background = bg_color,
                padding = Screen:scaleBySize(4),
                margin = 0,
                text_widget,
            }
            
            -- Position: center
            local cont_w = container:getSize().w
            local cont_h = container:getSize().h
            
            -- Make sure container doesn't overflow cover
            if cont_w > cover_w then
                cont_w = cover_w - Screen:scaleBySize(8)
            end
            if cont_h > cover_h then
                cont_h = cover_h - Screen:scaleBySize(8)
            end
            
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

