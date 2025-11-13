--https://github.com/0zd3m1r/KOReader.patches/--
--[[ User patch for KOReader to add compact page count and format badges ]]--
local Blitbuffer = require("ffi/blitbuffer")

--========================== [[Edit your preferences here]] ================================
-- Badge appearance
local page_font_size = 0.7                      -- Smaller font (0.5 to 1.0)
local page_text_color = Blitbuffer.COLOR_WHITE
local border_thickness = 1                      -- Thin border
local border_corner_radius = 8                  -- Rounded corners
local border_color = Blitbuffer.COLOR_DARK_GRAY
local background_color = Blitbuffer.COLOR_GRAY_3

-- Badge position
local badge_position = "bottom-left"               -- Options: "top-left", "top-right", "bottom-left", "bottom-right"
local move_from_border = 4                      -- Small distance from edge

-- What to show
local show_pages = true                         -- Show page count
local show_format = true                        -- Show format (EPUB, PDF, etc.)
local show_for_all_books = true                 -- true = all books, false = only unread
local show_file_size_if_no_pages = true         -- Show file size for unopened EPUB/KEPUB

-- Debug
local debug_mode = false                         -- Show debug logs

--==========================================================================================

local userpatch = require("userpatch")
local logger = require("logger")
local TextWidget = require("ui/widget/textwidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Screen = require("device").screen
local lfs = require("libs/libkoreader-lfs")

local count_cache = {}

-- Get file extension
local function getFileExtension(filepath)
    if not filepath then return "" end
    if filepath:match("%.kepub%.epub$") then return "kepub" end
    local ext = filepath:match("%.([^%.]+)$")
    return ext and ext:lower() or ""
end

-- Read page count from .sdr/metadata.epub.lua file
local function getPageCountFromSDR(filepath)
    if debug_mode then
        logger.info("SDR: Checking file:", filepath)
    end
    
    -- Construct .sdr metadata path
    local sdr_path
    
    -- SDR path is always: replace last extension with .sdr
    -- book.pdf -> book.sdr
    -- book.kepub.epub -> book.kepub.sdr
    -- book.epub -> book.sdr
    sdr_path = filepath:gsub("%.([^%.]+)$", ".sdr")
    
    local metadata_file = sdr_path .. "/metadata.epub.lua"
    
    if debug_mode then
        logger.info("SDR: Looking for:", metadata_file)
    end
    
    -- Check if metadata file exists
    local attr = lfs.attributes(metadata_file)
    if not attr then
        if debug_mode then
            logger.info("SDR: Metadata file NOT found")
        end
        return nil
    end
    
    if debug_mode then
        logger.info("SDR: Metadata file found! Reading...")
    end
    
    -- Read and parse metadata file
    local f = io.open(metadata_file, "r")
    if not f then 
        logger.warn("SDR: Cannot open file")
        return nil 
    end
    
    local content = f:read("*all")
    f:close()
    
    if debug_mode then
        logger.info("SDR: File read, size:", #content)
    end
    
    -- Look for pagemap_doc_pages
    local pages = content:match('%["pagemap_doc_pages"%]%s*=%s*(%d+)')
    if pages then
        pages = tonumber(pages)
        logger.info("SDR: ✅ Found pages:", pages)
        return pages
    else
        logger.warn("SDR: ❌ pagemap_doc_pages not found in metadata")
        -- Try alternative patterns
        pages = content:match('%["doc_pages"%]%s*=%s*(%d+)')
        if pages then
            pages = tonumber(pages)
            logger.info("SDR: ✅ Found pages (doc_pages):", pages)
            return pages
        end
    end
    
    return nil
end

-- Get page count from cache or metadata
local function getCachedPageCount(filepath)
    -- First try SDR metadata (fastest and most reliable)
    local pages = getPageCountFromSDR(filepath)
    if pages and pages > 0 then
        return pages
    end
    
    -- Fallback to BookInfoManager
    local BookInfoManager = require("bookinfomanager")
    local bookinfo = BookInfoManager:getBookInfo(filepath, false)
    
    if bookinfo and bookinfo.pages and bookinfo.pages > 0 then
        if debug_mode then
            logger.info("SDR: Using BookInfoManager pages:", bookinfo.pages)
        end
        return bookinfo.pages
    end
    
    return nil
end

-- Get page count for PDF (quick, from metadata)
local function getPdfPageCount(filepath)
    local DocumentRegistry = require("document/documentregistry")
    local ok, doc = pcall(DocumentRegistry.openDocument, DocumentRegistry, filepath)
    if ok and doc then
        local pages = doc:getPageCount()
        doc:close()
        return pages
    end
    return nil
end

-- Get file size and format it
local function getFileSize(filepath)
    local attr = lfs.attributes(filepath)
    if not attr or not attr.size then return nil end
    
    local size = attr.size
    local size_mb = size / (1024 * 1024)
    
    if size_mb < 0.1 then
        -- Less than 0.1 MB, show in KB
        local size_kb = size / 1024
        return string.format("%.0fK", size_kb)
    elseif size_mb < 1 then
        -- 0.1 - 1 MB
        return string.format("%.1fM", size_mb)
    elseif size_mb < 10 then
        -- 1 - 10 MB
        return string.format("%.1fM", size_mb)
    else
        -- 10+ MB
        return string.format("%.0fM", size_mb)
    end
end

-- Get book stats
local function getBookStats(filepath)
    if count_cache[filepath] then
        if debug_mode then
            logger.info("SDR: Using cached stats for:", filepath)
        end
        return count_cache[filepath]
    end
    
    local stats = { pages = nil, file_size = nil }
    local attr = lfs.attributes(filepath)
    if not attr then return stats end
    
    local ext = getFileExtension(filepath)
    
    if show_pages then
        if ext == "epub" or ext == "kepub" or ext == "mobi" or ext == "azw3" or ext == "fb2" then
            -- Read from .sdr metadata (works for KEPUB and EPUB)
            local pages = getCachedPageCount(filepath)
            if pages then
                stats.pages = pages
                if debug_mode then
                    logger.info("SDR: Stored pages:", pages)
                end
            elseif show_file_size_if_no_pages then
                -- No pages found, store file size instead
                stats.file_size = getFileSize(filepath)
                if debug_mode then
                    logger.info("SDR: No pages, stored file size:", stats.file_size)
                end
            end
        elseif ext == "pdf" or ext == "djvu" or ext == "cbz" or ext == "cbt" then
            local success, pages = pcall(getPdfPageCount, filepath)
            if success and pages then
                stats.pages = pages
            end
        end
    end
    
    count_cache[filepath] = stats
    return stats
end

-- Format number
local function formatNumber(num)
    if num >= 1000 then
        return string.format("%.1fK", num / 1000)
    end
    return tostring(num)
end

-- Get file size and format it
local function getFileSize(filepath)
    local attr = lfs.attributes(filepath)
    if not attr or not attr.size then return nil end
    
    local size = attr.size
    local size_mb = size / (1024 * 1024)
    
    if size_mb < 0.1 then
        -- Less than 0.1 MB, show in KB
        local size_kb = size / 1024
        return string.format("%.0fK", size_kb)
    elseif size_mb < 1 then
        -- 0.1 - 1 MB
        return string.format("%.1fM", size_mb)
    elseif size_mb < 10 then
        -- 1 - 10 MB
        return string.format("%.1fM", size_mb)
    else
        -- 10+ MB
        return string.format("%.0fM", size_mb)
    end
end

-- Get format name
local function getFormatName(ext)
    local map = {
        epub = "EPUB", kepub = "KEPUB", pdf = "PDF", mobi = "MOBI",
        azw3 = "AZW3", fb2 = "FB2", djvu = "DJVU", cbz = "CBZ"
    }
    return map[ext] or ext:upper()
end

local function patchCoverBrowserPageCount(plugin)
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    local origMosaicMenuItemPaintTo = MosaicMenuItem.paintTo
    
    function MosaicMenuItem:paintTo(bb, x, y)
        origMosaicMenuItemPaintTo(self, bb, x, y)
        
        local success, err = pcall(function()
            local target = self[1][1][1]
            if not target or not target.dimen then return end
            
            -- Check if we should show badge
            if self.is_directory or self.file_deleted or not self.filepath then return end
            
            -- If show_for_all_books is false, only show for unread
            if not show_for_all_books then
                if self.been_opened or self.status == "complete" then 
                    return 
                end
            end
            
            local stats = getBookStats(self.filepath)
            local ext = getFileExtension(self.filepath)
            
            local display_text = nil
            if stats.pages then
                display_text = formatNumber(stats.pages) .. "p"
                if debug_mode then
                    logger.info("SDR: Display text (pages):", display_text)
                end
            elseif stats.file_size then
                display_text = stats.file_size
                if debug_mode then
                    logger.info("SDR: Display text (size):", display_text)
                end
            end
            
            if debug_mode then
                logger.info("SDR: Format:", ext, "Display:", display_text, "Show format:", show_format)
            end
            
            -- Only create badges if we have something to show
            if not display_text and not show_format then return end
            
            local corner_mark_size = Screen:scaleBySize(10)
            local font_size = math.floor(corner_mark_size * page_font_size)
            local badges = {}
            
            -- Page count badge
            if display_text then
                local text_widget = TextWidget:new{
                    text = display_text,
                    face = Font:getFace("cfont", font_size),
                    fgcolor = page_text_color,
                    bold = true,
                    padding = 1,
                }
                
                local badge = FrameContainer:new{
                    bordersize = border_thickness,
                    radius = Screen:scaleBySize(border_corner_radius),
                    color = border_color,
                    background = background_color,
                    padding = Screen:scaleBySize(2),
                    margin = 0,
                    text_widget,
                }
                table.insert(badges, badge)
            end
            
            -- Format badge
            if show_format then
                local format_text = getFormatName(ext)
                local format_font_size = math.floor(font_size * 0.85)
                
                local format_widget = TextWidget:new{
                    text = format_text,
                    face = Font:getFace("cfont", format_font_size),
                    fgcolor = page_text_color,
                    bold = false,
                    padding = 1,
                }
                
                local format_badge = FrameContainer:new{
                    bordersize = 1,
                    radius = Screen:scaleBySize(border_corner_radius - 2),
                    color = border_color,
                    background = background_color,
                    padding = Screen:scaleBySize(1),
                    margin = 0,
                    format_widget,
                }
                table.insert(badges, format_badge)
            end
            
            if #badges == 0 then return end
            
            -- Calculate positions
            local cover_width = target.dimen.w
            local cover_height = target.dimen.h
            local cover_left = x + math.floor((self.width - cover_width) / 2)
            local cover_top = y + math.floor((self.height - cover_height) / 2)
            local cover_right = cover_left + cover_width
            local cover_bottom = cover_top + cover_height
            
            local pad = Screen:scaleBySize(move_from_border)
            local spacing = Screen:scaleBySize(2)
            
            -- Calculate total height
            local total_height = 0
            for _, badge in ipairs(badges) do
                total_height = total_height + badge:getSize().h + spacing
            end
            total_height = total_height - spacing
            
            -- Determine starting position
            local pos_x, pos_y
            local is_opened = self.been_opened or self.status == "complete"
            if badge_position == "top-left" then
                pos_y = cover_top + pad
            elseif badge_position == "top-right" then
                pos_y = cover_top + pad
            elseif badge_position == "bottom-right" then
                pos_y = cover_bottom - pad - total_height
            else -- bottom-left
                if is_opened then
                    pos_y = cover_top + pad
                else
                    pos_y = cover_bottom - pad - total_height
                end
            end
            
            -- Draw badges
            for _, badge in ipairs(badges) do
                local badge_w = badge:getSize().w
                local badge_h = badge:getSize().h
                
                if badge_position == "top-right" or badge_position == "bottom-right" then
                    pos_x = cover_right - pad - badge_w
                else
                    pos_x = cover_left + pad
                end
                
                badge:paintTo(bb, pos_x, pos_y)
                pos_y = pos_y + badge_h + spacing
            end
        end)
        
        if not success then
            logger.warn("Badge error:", err)
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverBrowserPageCount)
