-- CopyPageToClipboard - Xournal++ Lua Plugin
-- Enables copying the currently active page directly to the system clipboard
-- as a PNG image with a single shortcut (<Control><Alt>c) or menu action.
--
-- Developed by Antigravity, directed by @m-sarabi.
-- Compatible with Xournal++ 1.3.8+ and Lua 5.3+.

local CopyPagePlugin = {
    version = "1.0.0",
    author = "Antigravity (directed by @m-sarabi)"
}

--------------------------------------------------------------------------------
-- 1. Configuration Management
--------------------------------------------------------------------------------

local DEFAULT_CONFIG = {
    mode = "dpi",      -- "dpi" or "width"
    dpi = 300,         -- default 300 DPI
    width = 1920       -- default 1920 pixels
}

CopyPagePlugin.config = {
    mode = DEFAULT_CONFIG.mode,
    dpi = DEFAULT_CONFIG.dpi,
    width = DEFAULT_CONFIG.width
}

--- Determine the path for persistent configuration storage.
-- Checks:
-- 1. Environment variable COPYPAGE_CONFIG_PATH (useful for testing or overrides)
-- 2. Plugin directory (if writable)
-- 3. User config directory fallback
function CopyPagePlugin.getConfigFilePath()
    if CopyPagePlugin.customConfigPath and CopyPagePlugin.customConfigPath ~= "" then
        return CopyPagePlugin.customConfigPath
    end

    local envPath = os.getenv("COPYPAGE_CONFIG_PATH")
    if envPath and envPath ~= "" then
        return envPath
    end

    local sep = package.config:sub(1, 1)
    local pluginDir = nil

    local info = debug.getinfo(1, "S")
    if info and info.source and info.source:sub(1, 1) == "@" then
        local scriptPath = info.source:sub(2)
        pluginDir = scriptPath:match("^(.*)[/\\]")
    end

    if pluginDir and pluginDir ~= "" then
        local testPath = pluginDir .. sep .. "config.ini"
        if CopyPagePlugin.fileExists(testPath) then
            local testFile = io.open(testPath, "r+")
            if testFile then
                testFile:close()
                return testPath
            end
        else
            -- Check if directory is writable using a temporary probe file
            local probePath = pluginDir .. sep .. ".copypage_probe.tmp"
            local probeFile = io.open(probePath, "w")
            if probeFile then
                probeFile:close()
                pcall(os.remove, probePath)
                return testPath
            end
        end
    end

    -- Fallback to OS user configuration directories
    if sep == "\\" then
        local appdata = os.getenv("APPDATA") or os.getenv("LOCALAPPDATA") or os.getenv("USERPROFILE")
        if appdata then
            return appdata .. "\\xournalpp\\copypage_config.ini"
        end
        return "C:\\Temp\\copypage_config.ini"
    else
        local home = os.getenv("HOME")
        if home then
            return home .. "/.config/xournalpp/copypage_config.ini"
        end
        return "/tmp/copypage_config.ini"
    end
end

--- Load configuration from INI file.
-- @param filePath string path to config file
-- @return table loaded config merged with defaults
function CopyPagePlugin.loadConfig(filePath)
    local cfg = {
        mode = DEFAULT_CONFIG.mode,
        dpi = DEFAULT_CONFIG.dpi,
        width = DEFAULT_CONFIG.width
    }

    local targetPath = filePath or CopyPagePlugin.getConfigFilePath()
    local file = io.open(targetPath, "r")
    if not file then
        return cfg
    end

    for line in file:lines() do
        -- Trim whitespace and skip comments/empty lines
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" and trimmed:sub(1, 1) ~= ";" and trimmed:sub(1, 1) ~= "[" then
            local key, val = trimmed:match("^([%w_]+)%s*=%s*(.-)$")
            if key and val then
                key = key:lower()
                val = val:match("^%s*(.-)%s*$")
                if key == "mode" then
                    val = val:lower()
                    if val == "dpi" or val == "width" then
                        cfg.mode = val
                    end
                elseif key == "dpi" then
                    local num = tonumber(val)
                    if num and num >= 50 and num <= 2400 then
                        cfg.dpi = math.floor(num)
                    end
                elseif key == "width" then
                    local num = tonumber(val)
                    if num and num >= 100 and num <= 10000 then
                        cfg.width = math.floor(num)
                    end
                end
            end
        end
    end
    file:close()
    return cfg
end

--- Save configuration to INI file.
-- @param filePath string destination path
-- @param configToSave table configuration to persist
-- @return boolean success, string error message or nil
function CopyPagePlugin.saveConfig(filePath, configToSave)
    local cfg = configToSave or CopyPagePlugin.config
    local targetPath = filePath or CopyPagePlugin.getConfigFilePath()

    local file, err = io.open(targetPath, "w")
    if not file then
        return false, tostring(err)
    end

    file:write("; CopyPageToClipboard Plugin Configuration\n")
    file:write("; Options:\n")
    file:write(";   mode = dpi | width\n")
    file:write(";   dpi = integer (e.g. 150, 300, 600)\n")
    file:write(";   width = integer pixels (e.g. 1280, 1920, 2560)\n\n")
    file:write("[settings]\n")
    file:write(string.format("mode=%s\n", tostring(cfg.mode or DEFAULT_CONFIG.mode)))
    file:write(string.format("dpi=%d\n", tonumber(cfg.dpi or DEFAULT_CONFIG.dpi)))
    file:write(string.format("width=%d\n", tonumber(cfg.width or DEFAULT_CONFIG.width)))
    file:close()

    return true, nil
end

--- Initialize configuration on startup
function CopyPagePlugin.initConfiguration()
    local path = CopyPagePlugin.getConfigFilePath()
    local loaded = CopyPagePlugin.loadConfig(path)
    CopyPagePlugin.config.mode = loaded.mode
    CopyPagePlugin.config.dpi = loaded.dpi
    CopyPagePlugin.config.width = loaded.width
end

--------------------------------------------------------------------------------
-- 2. Operating System Detection & Clipboard Integration
--------------------------------------------------------------------------------

--- Detect host operating system.
-- @return string "windows" | "macos" | "linux"
function CopyPagePlugin.detectOS()
    local sep = package.config:sub(1, 1)
    if sep == "\\" then
        return "windows"
    end

    local unameHandle = io.popen("uname -s 2>/dev/null")
    if unameHandle then
        local unameOut = unameHandle:read("*l") or ""
        unameHandle:close()
        unameOut = unameOut:lower()
        if unameOut:find("darwin") then
            return "macos"
        elseif unameOut:find("linux") then
            return "linux"
        end
    end

    local ostype = (os.getenv("OSTYPE") or ""):lower()
    if ostype:find("darwin") then
        return "macos"
    end

    return "linux"
end

--- Safely escape an argument for POSIX shell command strings.
-- Wraps in single quotes and replaces single quotes with '\''.
-- @param str string argument to escape
-- @return string safely escaped shell literal
function CopyPagePlugin.shellEscape(str)
    return "'" .. tostring(str):gsub("'", "'\\''") .. "'"
end

--- Build Windows PowerShell clipboard command using .NET Clipboard API.
-- @param imagePath string absolute path to the PNG image
-- @return string execution command
function CopyPagePlugin.getWindowsClipboardCommand(imagePath)
    -- Normalize backslashes to forward slashes for clean PowerShell string literal handling
    local normalized = imagePath:gsub("\\", "/")
    -- Escape single quotes for PowerShell single-quoted string literal (' -> '')
    local escaped = normalized:gsub("'", "''")
    return string.format(
        'powershell.exe -Sta -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command "' ..
        '$img = $null; try { ' ..
        'Add-Type -AssemblyName System.Windows.Forms; ' ..
        'Add-Type -AssemblyName System.Drawing; ' ..
        '$img = [System.Drawing.Image]::FromFile(\'%s\'); ' ..
        '[System.Windows.Forms.Clipboard]::SetDataObject($img, $true, 10, 100); ' ..
        '} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 } ' ..
        'finally { if ($null -ne $img) { $img.Dispose() } }"',
        escaped
    )
end

--- Build Linux Wayland clipboard command.
-- @param imagePath string absolute path to the PNG image
-- @return string execution command
function CopyPagePlugin.getLinuxWaylandCommand(imagePath)
    return string.format('wl-copy -t image/png < %s', CopyPagePlugin.shellEscape(imagePath))
end

--- Build Linux X11 clipboard command.
-- @param imagePath string absolute path to the PNG image
-- @return string execution command
function CopyPagePlugin.getLinuxX11Command(imagePath)
    return string.format('xclip -selection clipboard -t image/png -i %s', CopyPagePlugin.shellEscape(imagePath))
end

--- Build Linux universal clipboard command with Wayland (wl-copy) and X11 (xclip / xsel) fallback.
-- @param imagePath string absolute path to the PNG image
-- @return string execution command
function CopyPagePlugin.getLinuxCommand(imagePath)
    local q = CopyPagePlugin.shellEscape(imagePath)
    return string.format(
        'if command -v wl-copy >/dev/null 2>&1; then ' ..
        'wl-copy -t image/png < %s; ' ..
        'elif command -v xclip >/dev/null 2>&1; then ' ..
        'xclip -selection clipboard -t image/png -i %s; ' ..
        'elif command -v xsel >/dev/null 2>&1; then ' ..
        'xsel -b -i < %s; ' ..
        'else exit 127; fi',
        q, q, q
    )
end

--- Build macOS osascript clipboard command using native PNG class.
-- @param imagePath string absolute path to the PNG image
-- @return string execution command
function CopyPagePlugin.getMacClipboardCommand(imagePath)
    -- Escape backslashes and double quotes for AppleScript string literal
    local asEscaped = tostring(imagePath):gsub("\\", "\\\\"):gsub('"', '\\"')
    local script = string.format('set the clipboard to (read (POSIX file "%s") as «class PNGf»)', asEscaped)
    -- Escape single quotes for shell argument
    return string.format("osascript -e '%s'", script:gsub("'", "'\\''"))
end

--- Form clipboard copy command for the specified or detected OS.
-- @param imagePath string path to the image
-- @param osName string optional OS name override
-- @return string command string
function CopyPagePlugin.getClipboardCommand(imagePath, osName)
    local targetOS = osName or CopyPagePlugin.detectOS()
    if targetOS == "windows" then
        return CopyPagePlugin.getWindowsClipboardCommand(imagePath)
    elseif targetOS == "macos" then
        return CopyPagePlugin.getMacClipboardCommand(imagePath)
    else
        return CopyPagePlugin.getLinuxCommand(imagePath)
    end
end

--------------------------------------------------------------------------------
-- 3. File System & Temporary File Management
--------------------------------------------------------------------------------

--- Check whether a file exists and is accessible.
-- @param filePath string path to test
-- @return boolean
function CopyPagePlugin.fileExists(filePath)
    if not filePath then return false end
    local f = io.open(filePath, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

--- Resolve the system temporary directory.
-- @param osName string optional OS name override
-- @return string directory path without trailing slash, string directory separator
function CopyPagePlugin.getTempDir(osName)
    local targetOS = osName or CopyPagePlugin.detectOS()
    local sep = (targetOS == "windows") and "\\" or "/"
    local tempDir = nil

    if targetOS == "windows" then
        tempDir = os.getenv("TEMP") or os.getenv("TMP") or (os.getenv("USERPROFILE") and (os.getenv("USERPROFILE") .. "\\AppData\\Local\\Temp"))
        if not tempDir or tempDir == "" then
            tempDir = "C:\\Temp"
        end
    else
        tempDir = os.getenv("TMPDIR") or "/tmp"
        if not tempDir or tempDir == "" then
            tempDir = "/tmp"
        end
    end

    -- Strip trailing separators
    while #tempDir > 1 and (tempDir:sub(-1) == "\\" or tempDir:sub(-1) == "/") do
        tempDir = tempDir:sub(1, -2)
    end

    return tempDir, sep
end

--- Generate a unique temporary PNG file path.
-- @param osName string optional OS name override
-- @return string fullFilePath, string baseNameWithoutExt, string tempDir, string sep
function CopyPagePlugin.createTempPngPath(osName)
    local tempDir, sep = CopyPagePlugin.getTempDir(osName)
    local timestamp = tostring(os.time())
    local randVal = tostring(math.random(100000, 999999))
    local baseName = "xopp_clip_" .. timestamp .. "_" .. randVal
    local fullPath = tempDir .. sep .. baseName .. ".png"
    return fullPath, baseName, tempDir, sep
end

--- Generate all possible output filename candidates that Xournal++ may produce.
-- @param basePath string destination path originally passed to export
-- @param pageIndex number 1-based page index
-- @return table list of candidate file paths
function CopyPagePlugin.getCandidatePaths(basePath, pageIndex)
    local candidates = { basePath }
    local stem = basePath:match("^(.-)%.png$") or basePath
    local idx = tonumber(pageIndex) or 1

    -- Suffix formats with exact page index: -2.png, _2.png
    table.insert(candidates, stem .. "-" .. tostring(idx) .. ".png")
    table.insert(candidates, stem .. "_" .. tostring(idx) .. ".png")

    -- Suffix formats with index 1 (single-page export ranges): -1.png, _1.png
    table.insert(candidates, stem .. "-1.png")
    table.insert(candidates, stem .. "_1.png")

    -- Zero-padded variants: -01, _01, -02, _02, -001, etc.
    table.insert(candidates, stem .. string.format("-%02d.png", idx))
    table.insert(candidates, stem .. string.format("_%02d.png", idx))
    table.insert(candidates, stem .. string.format("-%03d.png", idx))
    table.insert(candidates, stem .. string.format("_%03d.png", idx))
    table.insert(candidates, stem .. string.format("-%04d.png", idx))
    table.insert(candidates, stem .. string.format("_%04d.png", idx))
    table.insert(candidates, stem .. "-01.png")
    table.insert(candidates, stem .. "_01.png")

    -- Descriptive variants: -page1.png, _page1.png, -page-1.png, _page_1.png
    table.insert(candidates, stem .. "-page" .. tostring(idx) .. ".png")
    table.insert(candidates, stem .. "_page" .. tostring(idx) .. ".png")
    table.insert(candidates, stem .. "-page-" .. tostring(idx) .. ".png")
    table.insert(candidates, stem .. "_page_" .. tostring(idx) .. ".png")

    return candidates
end

--- Find the exported PNG file on disk.
-- Xournal++ image exports can produce `prefix.png` or `prefix-<pageNum>.png` or `prefix-1.png`.
-- @param basePath string expected base file path
-- @param pageIndex number 1-based page index
-- @param baseName string base name without extension
-- @param tempDir string temp directory
-- @param sep string path separator
-- @return string or nil path to verified file
function CopyPagePlugin.findExportedPngFile(basePath, pageIndex, baseName, tempDir, sep)
    local candidates = CopyPagePlugin.getCandidatePaths(basePath, pageIndex)
    for _, path in ipairs(candidates) do
        if CopyPagePlugin.fileExists(path) then
            return path
        end
    end
    return nil
end

--- Safely delete temporary files created during the export and clipboard pipeline.
-- @param fileList table array of string file paths
function CopyPagePlugin.cleanupFiles(fileList)
    if not fileList then return end
    for _, path in ipairs(fileList) do
        if path and CopyPagePlugin.fileExists(path) then
            pcall(os.remove, path)
        end
    end
end

--------------------------------------------------------------------------------
-- 4. User Feedback & Notifications
--------------------------------------------------------------------------------

--- Display brief notification to user using Xournal++ Lua UI API if supported.
-- @param message string message to display
-- @param isError boolean optional error flag
function CopyPagePlugin.notify(message, isError)
    local isErr = (isError == true)
    if not app then
        print("[CopyPageToClipboard] " .. message)
        return
    end

    -- 1. Try modern Xournal++ 1.3.8+ dialog API: app.openDialog
    if type(app.openDialog) == "function" then
        local ok = pcall(app.openDialog, message, { "OK" }, "", isErr)
        if ok then return end
    end

    -- 2. Try legacy app.msgbox with options table
    local msgFunc = app.msgbox or app.msgBox
    if type(msgFunc) == "function" then
        local ok = pcall(msgFunc, message, { [1] = "OK" })
        if not ok then
            pcall(msgFunc, message)
        end
        return
    end

    -- 3. Fallback to status bar or print
    if type(app.setStatus) == "function" then
        pcall(app.setStatus, message)
        return
    end

    print("[CopyPageToClipboard] " .. message)
end

--------------------------------------------------------------------------------
-- 5. Page Export & Clipboard Pipeline
--------------------------------------------------------------------------------

--- Resolve the currently active page index (1-based).
-- @return number pageIndex, table or nil documentStructure
function CopyPagePlugin.getActivePageIndex()
    local doc = nil
    if app and type(app.getDocumentStructure) == "function" then
        local ok, res = pcall(app.getDocumentStructure)
        if ok and type(res) == "table" then
            doc = res
        end
    end

    local pageIndex = 1
    if doc and doc.currentPage then
        local num = tonumber(doc.currentPage)
        if num and num >= 1 then
            pageIndex = math.floor(num)
        end
    end

    return pageIndex, doc
end

--- Export the specified page to a temporary PNG file.
-- Tries Xournal++ Lua export API first (`app.export`), falling back to CLI (`xournalpp`).
-- @param pageIndex number 1-based page index
-- @param targetPath string destination PNG path
-- @param doc table optional document structure
-- @return string or nil path to verified exported PNG file, string or nil error message
function CopyPagePlugin.exportPage(pageIndex, targetPath, doc)
    local cfg = CopyPagePlugin.config
    local baseName = targetPath:match("([^/\\]+)%.png$")
    local tempDir, sep = CopyPagePlugin.getTempDir()

    local exportError = nil
    local docWidth = (doc and doc.pages and doc.pages[pageIndex] and doc.pages[pageIndex].pageWidth) or 595.28
    local calculatedDpi = math.floor(((tonumber(cfg.width) or 1920) * 72.0) / docWidth + 0.5)

    -- 1. Try Xournal++ Lua export API: app.export
    if app and type(app.export) == "function" then
        -- Attempt 1: string range (e.g. "1")
        local exportParams1 = {
            ["outputFile"] = targetPath,
            ["range"] = tostring(pageIndex)
        }

        if cfg.mode == "width" and cfg.width then
            exportParams1["pngWidth"] = tonumber(cfg.width)
            exportParams1["pngDpi"] = calculatedDpi
        else
            exportParams1["pngDpi"] = tonumber(cfg.dpi) or 300
        end

        local ok1, err1 = pcall(app.export, exportParams1)
        if ok1 then
            local found = CopyPagePlugin.findExportedPngFile(targetPath, pageIndex, baseName, tempDir, sep)
            if found then
                return found, nil
            end
        else
            exportError = tostring(err1)
        end

        -- Attempt 2: array range fallback (e.g. {1, 1})
        local exportParams2 = {
            ["outputFile"] = targetPath,
            ["range"] = { pageIndex, pageIndex },
            ["pngDpi"] = exportParams1["pngDpi"],
            ["pngWidth"] = exportParams1["pngWidth"]
        }
        local ok2, err2 = pcall(app.export, exportParams2)
        if ok2 then
            local found = CopyPagePlugin.findExportedPngFile(targetPath, pageIndex, baseName, tempDir, sep)
            if found then
                return found, nil
            end
        else
            if not exportError then exportError = tostring(err2) end
        end
    end

    -- 2. Fallback to CLI export if document has a saved filename on disk
    if doc and doc.xoppFilename and doc.xoppFilename ~= "" and CopyPagePlugin.fileExists(doc.xoppFilename) then
        local effectiveDpi = (cfg.mode == "width") and calculatedDpi or (tonumber(cfg.dpi) or 300)
        local cliCmd = string.format('xournalpp %q -i %q --export-range=%s --export-png-dpi=%d',
            doc.xoppFilename, targetPath, tostring(pageIndex), effectiveDpi)

        pcall(os.execute, cliCmd)
        local found = CopyPagePlugin.findExportedPngFile(targetPath, pageIndex, baseName, tempDir, sep)
        if found then
            return found, nil
        end
    end

    local errMsg = "Failed to export page " .. tostring(pageIndex) .. " to PNG."
    if exportError then
        errMsg = errMsg .. " (" .. exportError .. ")"
    end
    return nil, errMsg
end

--- Execute clipboard copy and clean up temporary files.
-- @param imagePath string absolute path to verified image file
-- @param filesToClean table list of file paths to remove afterwards
-- @return boolean success, string or nil error message
function CopyPagePlugin.copyImageToClipboard(imagePath, filesToClean)
    local osType = CopyPagePlugin.detectOS()
    local cmd = CopyPagePlugin.getClipboardCommand(imagePath, osType)

    local execStatus, execKind, execCode = os.execute(cmd)

    -- In Lua 5.3+, os.execute returns (true, "exit", 0) on success.
    -- In Lua 5.1/LuaJIT, it returns status code 0 on success.
    local success = (execStatus == true or execStatus == 0)

    -- Clean up temporary files immediately after clipboard transfer
    CopyPagePlugin.cleanupFiles(filesToClean)

    if success then
        return true, nil
    else
        return false, string.format("Clipboard command failed (status=%s, code=%s)", tostring(execStatus), tostring(execCode))
    end
end

--- Primary callback triggered by shortcut (<Control><Alt>c) or menu item.
-- Coordinates active page detection, export, clipboard transfer, cleanup, and user notification.
function CopyPagePlugin.copyCurrentPage()
    local pageIndex, doc = CopyPagePlugin.getActivePageIndex()
    local tempPath, baseName, tempDir, sep = CopyPagePlugin.createTempPngPath()

    -- Candidate paths to clean up
    local filesToClean = CopyPagePlugin.getCandidatePaths(tempPath, pageIndex)

    local exportedFile, exportErr = CopyPagePlugin.exportPage(pageIndex, tempPath, doc)
    if not exportedFile then
        CopyPagePlugin.cleanupFiles(filesToClean)
        CopyPagePlugin.notify("Copy Page failed: " .. (exportErr or "Export error"), true)
        return false
    end

    -- Add the actual found file to cleanup list
    table.insert(filesToClean, exportedFile)

    local ok, clipErr = CopyPagePlugin.copyImageToClipboard(exportedFile, filesToClean)
    if ok then
        local qualityStr = (CopyPagePlugin.config.mode == "width")
            and (tostring(CopyPagePlugin.config.width) .. "px width")
            or (tostring(CopyPagePlugin.config.dpi) .. " DPI")
        CopyPagePlugin.notify(string.format("Page %d copied to clipboard (%s)!", pageIndex, qualityStr))
        return true
    else
        CopyPagePlugin.notify("Copy Page failed: " .. (clipErr or "Clipboard error"), true)
        return false
    end
end

--------------------------------------------------------------------------------
-- 6. Quality Configuration Actions
--------------------------------------------------------------------------------

--- Set quality mode to DPI and persist.
-- @param dpiValue number optional DPI value
function CopyPagePlugin.setQualityDpi(dpiValue)
    CopyPagePlugin.config.mode = "dpi"
    if dpiValue and tonumber(dpiValue) then
        CopyPagePlugin.config.dpi = math.floor(tonumber(dpiValue))
    end
    CopyPagePlugin.saveConfig()
    CopyPagePlugin.notify(string.format("Quality mode set to DPI (%d DPI).", CopyPagePlugin.config.dpi))
end

--- Set quality mode to Fixed Width and persist.
-- @param widthValue number optional width value in pixels
function CopyPagePlugin.setQualityWidth(widthValue)
    CopyPagePlugin.config.mode = "width"
    if widthValue and tonumber(widthValue) then
        CopyPagePlugin.config.width = math.floor(tonumber(widthValue))
    end
    CopyPagePlugin.saveConfig()
    CopyPagePlugin.notify(string.format("Quality mode set to Fixed Width (%d px).", CopyPagePlugin.config.width))
end

--- Toggle between DPI and Fixed Width modes and persist.
function CopyPagePlugin.toggleMode()
    if CopyPagePlugin.config.mode == "dpi" then
        CopyPagePlugin.config.mode = "width"
        CopyPagePlugin.notify(string.format("Switched to Fixed Width mode (%d px).", CopyPagePlugin.config.width))
    else
        CopyPagePlugin.config.mode = "dpi"
        CopyPagePlugin.notify(string.format("Switched to DPI mode (%d DPI).", CopyPagePlugin.config.dpi))
    end
    CopyPagePlugin.saveConfig()
end

--- Cycle through standard DPI presets: 150 -> 300 -> 600.
function CopyPagePlugin.cycleDpi()
    local presets = { 150, 300, 600 }
    local current = CopyPagePlugin.config.dpi or 300
    local nextDpi = presets[1]

    for i, val in ipairs(presets) do
        if current == val then
            nextDpi = presets[(i % #presets) + 1]
            break
        end
    end

    CopyPagePlugin.config.mode = "dpi"
    CopyPagePlugin.config.dpi = nextDpi
    CopyPagePlugin.saveConfig()
    CopyPagePlugin.notify(string.format("DPI set to %d DPI.", nextDpi))
end

--- Cycle through standard Width presets: 1280 -> 1920 -> 2560 -> 3840.
function CopyPagePlugin.cycleWidth()
    local presets = { 1280, 1920, 2560, 3840 }
    local current = CopyPagePlugin.config.width or 1920
    local nextWidth = presets[1]

    for i, val in ipairs(presets) do
        if current == val then
            nextWidth = presets[(i % #presets) + 1]
            break
        end
    end

    CopyPagePlugin.config.mode = "width"
    CopyPagePlugin.config.width = nextWidth
    CopyPagePlugin.saveConfig()
    CopyPagePlugin.notify(string.format("Fixed width set to %d px.", nextWidth))
end

--- Display current settings.
function CopyPagePlugin.showSettings()
    local modeStr = (CopyPagePlugin.config.mode == "width") and "Fixed Width" or "DPI"
    CopyPagePlugin.notify(string.format(
        "CopyPageToClipboard Settings:\nActive Mode: %s\nDPI: %d\nWidth: %d px\nConfig File: %s",
        modeStr,
        CopyPagePlugin.config.dpi,
        CopyPagePlugin.config.width,
        CopyPagePlugin.getConfigFilePath()
    ))
end

--------------------------------------------------------------------------------
-- 7. Xournal++ Plugin Initialization & Global Callbacks
--------------------------------------------------------------------------------

-- Global wrapper functions for Xournal++ Lua callbacks
function copyCurrentPage()
    return CopyPagePlugin.copyCurrentPage()
end

function actionSetDpiMode()
    CopyPagePlugin.setQualityDpi(300)
end

function actionSetWidthMode()
    CopyPagePlugin.setQualityWidth(1920)
end

function actionToggleMode()
    CopyPagePlugin.toggleMode()
end

function actionCycleDpi()
    CopyPagePlugin.cycleDpi()
end

function actionCycleWidth()
    CopyPagePlugin.cycleWidth()
end

function actionShowSettings()
    CopyPagePlugin.showSettings()
end

--- Register plugin UI entries in Xournal++ menu bar and bind accelerator shortcut.
function initUi()
    -- Initialize configuration from disk
    CopyPagePlugin.initConfiguration()

    if not app or type(app.registerUi) ~= "function" then
        return
    end

    -- Primary action: Copy current page to clipboard with shortcut accelerator
    app.registerUi({
        ["menu"] = "Copy Current Page to Clipboard",
        ["callback"] = "copyCurrentPage",
        ["accelerator"] = "<Control><Alt>c"
    })

    -- Quality configuration menu entries
    app.registerUi({
        ["menu"] = "Quality: DPI Mode (300 DPI)",
        ["callback"] = "actionSetDpiMode"
    })

    app.registerUi({
        ["menu"] = "Quality: Fixed Width Mode (1920 px)",
        ["callback"] = "actionSetWidthMode"
    })

    app.registerUi({
        ["menu"] = "Quality: Toggle Mode (DPI / Width)",
        ["callback"] = "actionToggleMode"
    })

    app.registerUi({
        ["menu"] = "Quality: Cycle DPI (150 -> 300 -> 600)",
        ["callback"] = "actionCycleDpi"
    })

    app.registerUi({
        ["menu"] = "Quality: Cycle Width (1280 -> 1920 -> 2560)",
        ["callback"] = "actionCycleWidth"
    })

    app.registerUi({
        ["menu"] = "Quality: Show Current Settings",
        ["callback"] = "actionShowSettings"
    })
end

-- Automatically load configuration when script is parsed
CopyPagePlugin.initConfiguration()

return CopyPagePlugin
