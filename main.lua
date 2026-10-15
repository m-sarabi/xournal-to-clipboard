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

--- Locate the plugin directory across platforms.
-- Robustly resolves the directory where the CopyPageToClipboard plugin files reside.
-- Checks:
-- 1. Caller stack info via debug.getinfo (checking levels 1 to 5)
-- 2. Standard Xournal++ user plugin directories across Windows, Linux, and macOS
-- 3. Working directory fallback (e.g. tests or standalone repo)
-- @return string or nil plugin directory path
function CopyPagePlugin.getPluginDir()
    local sep = package.config:sub(1, 1)

    -- 1. Try debug.getinfo up the call stack (levels 1 to 5)
    for level = 1, 5 do
        local info = debug.getinfo(level, "S")
        if info and info.source and info.source:sub(1, 1) == "@" then
            local scriptPath = info.source:sub(2)
            local dir = scriptPath:match("^(.*)[/\\]")
            if dir and dir ~= "" then
                if CopyPagePlugin.fileExists(dir .. sep .. "plugin.ini") or
                   CopyPagePlugin.fileExists(dir .. sep .. "main.lua") or
                   CopyPagePlugin.fileExists(dir .. sep .. "config.ini") then
                    return dir
                end
            end
        end
    end

    -- 2. Check candidate Xournal++ plugin directories across platforms
    local candidates = {}
    local pluginFolderNames = { "CopyPageToClipboard", "xournal-to-clipboard" }

    if sep == "\\" then
        local localAppData = os.getenv("LOCALAPPDATA")
        local appData = os.getenv("APPDATA")
        local userProfile = os.getenv("USERPROFILE")

        local baseDirs = {}
        if localAppData and localAppData ~= "" then
            table.insert(baseDirs, localAppData .. "\\xournalpp\\plugins")
        end
        if appData and appData ~= "" then
            table.insert(baseDirs, appData .. "\\xournalpp\\plugins")
        end
        if userProfile and userProfile ~= "" then
            table.insert(baseDirs, userProfile .. "\\.xournalpp\\plugins")
        end

        for _, base in ipairs(baseDirs) do
            for _, name in ipairs(pluginFolderNames) do
                table.insert(candidates, base .. "\\" .. name)
            end
        end
    else
        local home = os.getenv("HOME") or ""
        local xdgConfig = os.getenv("XDG_CONFIG_HOME")
        local baseDirs = {}

        if xdgConfig and xdgConfig ~= "" then
            table.insert(baseDirs, xdgConfig .. "/xournalpp/plugins")
        elseif home ~= "" then
            table.insert(baseDirs, home .. "/.config/xournalpp/plugins")
        end

        if home ~= "" then
            table.insert(baseDirs, home .. "/.xournalpp/plugins")
            table.insert(baseDirs, home .. "/Library/Application Support/xournalpp/plugins")
        end

        for _, base in ipairs(baseDirs) do
            for _, name in ipairs(pluginFolderNames) do
                table.insert(candidates, base .. "/" .. name)
            end
        end
    end

    -- First pass: find an existing plugin directory that contains plugin.ini or main.lua or config.ini
    for _, dir in ipairs(candidates) do
        if CopyPagePlugin.fileExists(dir .. sep .. "plugin.ini") or
           CopyPagePlugin.fileExists(dir .. sep .. "main.lua") or
           CopyPagePlugin.fileExists(dir .. sep .. "config.ini") then
            return dir
        end
    end

    -- Second pass: check current working directory (e.g. standalone test runs or local dev)
    if CopyPagePlugin.fileExists("plugin.ini") or CopyPagePlugin.fileExists("main.lua") then
        return "."
    end

    -- Third pass: default candidate plugin directory
    if #candidates > 0 then
        return candidates[1]
    end

    return nil
end

--- Determine the path for persistent configuration storage.
-- Always targets 'config.ini' directly inside the plugin directory.
-- Checks:
-- 1. Custom config path override (CopyPagePlugin.customConfigPath)
-- 2. Environment variable COPYPAGE_CONFIG_PATH
-- 3. Plugin directory config.ini
-- 4. Standard platform plugin directory config.ini
-- @return string config file path
function CopyPagePlugin.getConfigFilePath()
    if CopyPagePlugin.customConfigPath and CopyPagePlugin.customConfigPath ~= "" then
        return CopyPagePlugin.customConfigPath
    end

    local envPath = os.getenv("COPYPAGE_CONFIG_PATH")
    if envPath and envPath ~= "" then
        return envPath
    end

    local sep = package.config:sub(1, 1)
    local pluginDir = CopyPagePlugin.getPluginDir()

    if pluginDir and pluginDir ~= "" then
        return pluginDir .. sep .. "config.ini"
    end

    -- Fallback to standard platform plugin directory
    if sep == "\\" then
        local appdata = os.getenv("LOCALAPPDATA") or os.getenv("APPDATA") or os.getenv("USERPROFILE") or "C:\\Temp"
        return appdata .. "\\xournalpp\\plugins\\CopyPageToClipboard\\config.ini"
    else
        local home = os.getenv("HOME") or "/tmp"
        return home .. "/.config/xournalpp/plugins/CopyPageToClipboard/config.ini"
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
    if not file and not filePath then
        -- Check if fallback config exists in system temporary directory
        local tempDir, sep = CopyPagePlugin.getTempDir()
        local fallbackPath = tempDir .. sep .. "config.ini"
        if fallbackPath ~= targetPath then
            file = io.open(fallbackPath, "r")
        end
    end
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
                -- Strip trailing inline comments starting with # or ;
                val = val:match("^([^#;]*)") or val
                val = val:match("^%s*(.-)%s*$")
                -- Strip optional surrounding quotes ("..." or '...')
                if (#val >= 2) and ((val:sub(1, 1) == '"' and val:sub(-1) == '"') or (val:sub(1, 1) == "'" and val:sub(-1) == "'")) then
                    val = val:sub(2, -2):match("^%s*(.-)%s*$")
                end
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
        -- Attempt to create parent directory if missing
        local dir = targetPath:match("^(.*)[/\\]")
        if dir and dir ~= "" then
            local sep = package.config:sub(1, 1)
            if sep == "\\" then
                pcall(os.execute, 'mkdir "' .. dir:gsub("/", "\\") .. '" 2>nul')
            else
                pcall(os.execute, 'mkdir -p "' .. dir .. '" 2>/dev/null')
            end
            file, err = io.open(targetPath, "w")
        end
    end

    if not file then
        -- Last resort fallback: save to system temporary directory
        local tempDir, sep = CopyPagePlugin.getTempDir()
        local fallbackPath = tempDir .. sep .. "config.ini"
        file, err = io.open(fallbackPath, "w")
        if not file then
            return false, tostring(err)
        end
    end

    local modeVal = (cfg.mode == "width") and "width" or "dpi"
    local dpiVal = tonumber(cfg.dpi) or DEFAULT_CONFIG.dpi
    local widthVal = tonumber(cfg.width) or DEFAULT_CONFIG.width

    file:write("; CopyPageToClipboard Plugin Configuration\n")
    file:write("; Options:\n")
    file:write(";   mode = dpi | width\n")
    file:write(";   dpi = integer (e.g. 150, 300, 600)\n")
    file:write(";   width = integer pixels (e.g. 1280, 1920, 2560)\n\n")
    file:write("[settings]\n")
    file:write(string.format("mode=%s\n", modeVal))
    file:write(string.format("dpi=%d\n", math.floor(dpiVal)))
    file:write(string.format("width=%d\n", math.floor(widthVal)))
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

--- Format a list of file paths into a PowerShell string array literal @('p1', 'p2').
-- @param files table array of file paths
-- @return string PowerShell array expression
function CopyPagePlugin.formatFilesForPowerShell(files)
    local items = {}
    for _, f in ipairs(files or {}) do
        if f and f ~= "" then
            local norm = f:gsub("\\", "/"):gsub("'", "''")
            table.insert(items, string.format("'%s'", norm))
        end
    end
    if #items == 0 then
        return "@()"
    end
    return "@(" .. table.concat(items, ", ") .. ")"
end

--- Format a list of file paths for POSIX shell command arguments.
-- @param files table array of file paths
-- @return string space-separated escaped file paths
function CopyPagePlugin.formatFilesForPosix(files)
    local items = {}
    for _, f in ipairs(files or {}) do
        if f and f ~= "" then
            table.insert(items, CopyPagePlugin.shellEscape(f))
        end
    end
    return table.concat(items, " ")
end

--- Build Windows PowerShell clipboard command using .NET Clipboard API.
-- @param imagePath string absolute path to the PNG image
-- @param filesToClean table optional list of files to safely delete in finally block
-- @param isAsync boolean optional flag to launch in background without blocking UI
-- @return string execution command
function CopyPagePlugin.getWindowsClipboardCommand(imagePath, filesToClean, isAsync)
    -- Normalize backslashes to forward slashes for clean PowerShell string literal handling
    local normalized = imagePath:gsub("\\", "/")
    -- Escape single quotes for PowerShell single-quoted string literal (' -> '')
    local escaped = normalized:gsub("'", "''")

    local cleanupSnippet = ""
    if isAsync and filesToClean and #filesToClean > 0 then
        local cleanList = CopyPagePlugin.formatFilesForPowerShell(filesToClean)
        cleanupSnippet = string.format("; Remove-Item -LiteralPath %s -Force -ErrorAction SilentlyContinue", cleanList)
    end

    local psCore = string.format(
        '$img = $null; try { ' ..
        'Add-Type -AssemblyName System.Windows.Forms; ' ..
        'Add-Type -AssemblyName System.Drawing; ' ..
        '$img = [System.Drawing.Image]::FromFile(\'%s\'); ' ..
        '[System.Windows.Forms.Clipboard]::SetDataObject($img, $true, 10, 100); ' ..
        '} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 } ' ..
        'finally { if ($null -ne $img) { $img.Dispose() }%s }',
        escaped,
        cleanupSnippet
    )

    local baseCmd = string.format(
        'powershell.exe -Sta -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command "%s"',
        psCore
    )

    if isAsync then
        return 'start "" /B ' .. baseCmd
    else
        return baseCmd
    end
end

--- Build Linux Wayland clipboard command.
-- @param imagePath string absolute path to the PNG image
-- @param filesToClean table optional list of files to remove afterwards
-- @param isAsync boolean optional flag for background execution
-- @return string execution command
function CopyPagePlugin.getLinuxWaylandCommand(imagePath, filesToClean, isAsync)
    local q = CopyPagePlugin.shellEscape(imagePath)
    local cleanupSnippet = ""
    if isAsync and filesToClean and #filesToClean > 0 then
        local cleanList = CopyPagePlugin.formatFilesForPosix(filesToClean)
        if cleanList ~= "" then
            cleanupSnippet = " ; rm -f " .. cleanList
        end
    end
    local base = string.format('wl-copy -t image/png < %s%s', q, cleanupSnippet)
    if isAsync then
        return string.format('( %s ) >/dev/null 2>&1 &', base)
    else
        return base
    end
end

--- Build Linux X11 clipboard command.
-- @param imagePath string absolute path to the PNG image
-- @param filesToClean table optional list of files to remove afterwards
-- @param isAsync boolean optional flag for background execution
-- @return string execution command
function CopyPagePlugin.getLinuxX11Command(imagePath, filesToClean, isAsync)
    local q = CopyPagePlugin.shellEscape(imagePath)
    local cleanupSnippet = ""
    if isAsync and filesToClean and #filesToClean > 0 then
        local cleanList = CopyPagePlugin.formatFilesForPosix(filesToClean)
        if cleanList ~= "" then
            cleanupSnippet = " ; rm -f " .. cleanList
        end
    end
    local base = string.format('xclip -selection clipboard -t image/png -i %s%s', q, cleanupSnippet)
    if isAsync then
        return string.format('( %s ) >/dev/null 2>&1 &', base)
    else
        return base
    end
end

--- Build Linux universal clipboard command with Wayland (wl-copy) and X11 (xclip / xsel) fallback.
-- @param imagePath string absolute path to the PNG image
-- @param filesToClean table optional list of files to remove afterwards
-- @param isAsync boolean optional flag for background execution
-- @return string execution command
function CopyPagePlugin.getLinuxCommand(imagePath, filesToClean, isAsync)
    local q = CopyPagePlugin.shellEscape(imagePath)
    local cleanupSnippet = ""
    if isAsync and filesToClean and #filesToClean > 0 then
        local cleanList = CopyPagePlugin.formatFilesForPosix(filesToClean)
        if cleanList ~= "" then
            cleanupSnippet = " ; rm -f " .. cleanList
        end
    end

    local base = string.format(
        'ret=0; ' ..
        'if command -v wl-copy >/dev/null 2>&1; then ' ..
        'wl-copy -t image/png < %s || ret=$?; ' ..
        'elif command -v xclip >/dev/null 2>&1; then ' ..
        'xclip -selection clipboard -t image/png -i %s || ret=$?; ' ..
        'elif command -v xsel >/dev/null 2>&1; then ' ..
        'xsel -b -i < %s || ret=$?; ' ..
        'else ret=127; fi%s; exit $ret',
        q, q, q, cleanupSnippet
    )

    if isAsync then
        return string.format('( %s ) >/dev/null 2>&1 &', base)
    else
        return base
    end
end

--- Build macOS osascript clipboard command using native PNG class.
-- @param imagePath string absolute path to the PNG image
-- @param filesToClean table optional list of files to remove afterwards
-- @param isAsync boolean optional flag for background execution
-- @return string execution command
function CopyPagePlugin.getMacClipboardCommand(imagePath, filesToClean, isAsync)
    -- Escape backslashes and double quotes for AppleScript string literal
    local asEscaped = tostring(imagePath):gsub("\\", "\\\\"):gsub('"', '\\"')
    local script = string.format('set the clipboard to (read (POSIX file "%s") as «class PNGf»)', asEscaped)
    local osaCmd = string.format("osascript -e '%s'", script:gsub("'", "'\\''"))

    local cleanupSnippet = ""
    if isAsync and filesToClean and #filesToClean > 0 then
        local cleanList = CopyPagePlugin.formatFilesForPosix(filesToClean)
        if cleanList ~= "" then
            cleanupSnippet = " ; rm -f " .. cleanList
        end
    end

    if isAsync then
        return string.format('( %s%s ) >/dev/null 2>&1 &', osaCmd, cleanupSnippet)
    else
        return osaCmd
    end
end

--- Form clipboard copy command for the specified or detected OS.
-- @param imagePath string path to the image
-- @param osName string optional OS name override
-- @param filesToClean table optional list of files to clean up
-- @param isAsync boolean optional flag for background execution
-- @return string command string
function CopyPagePlugin.getClipboardCommand(imagePath, osName, filesToClean, isAsync)
    local targetOS = osName or CopyPagePlugin.detectOS()
    if targetOS == "windows" then
        return CopyPagePlugin.getWindowsClipboardCommand(imagePath, filesToClean, isAsync)
    elseif targetOS == "macos" then
        return CopyPagePlugin.getMacClipboardCommand(imagePath, filesToClean, isAsync)
    else
        return CopyPagePlugin.getLinuxCommand(imagePath, filesToClean, isAsync)
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

    -- Short page-prefixed variants: -p1.png, _p1.png, -p01.png, _p01.png
    table.insert(candidates, stem .. "-p" .. tostring(idx) .. ".png")
    table.insert(candidates, stem .. "_p" .. tostring(idx) .. ".png")
    table.insert(candidates, stem .. "-p1.png")
    table.insert(candidates, stem .. "_p1.png")
    table.insert(candidates, stem .. "-p" .. string.format("%02d", idx) .. ".png")
    table.insert(candidates, stem .. "_p" .. string.format("%02d", idx) .. ".png")

    -- Dot-separated variants: .1.png, .2.png, .p1.png
    table.insert(candidates, stem .. "." .. tostring(idx) .. ".png")
    table.insert(candidates, stem .. ".1.png")
    table.insert(candidates, stem .. ".p" .. tostring(idx) .. ".png")
    table.insert(candidates, stem .. ".p1.png")

    -- 0-based page index variants (e.g. -0.png, _0.png, -page0.png, .0.png)
    local zeroIdx = idx - 1
    if zeroIdx >= 0 then
        table.insert(candidates, stem .. "-" .. tostring(zeroIdx) .. ".png")
        table.insert(candidates, stem .. "_" .. tostring(zeroIdx) .. ".png")
        table.insert(candidates, stem .. string.format("-%02d.png", zeroIdx))
        table.insert(candidates, stem .. string.format("_%02d.png", zeroIdx))
        table.insert(candidates, stem .. "-page" .. tostring(zeroIdx) .. ".png")
        table.insert(candidates, stem .. "_page" .. tostring(zeroIdx) .. ".png")
        table.insert(candidates, stem .. "." .. tostring(zeroIdx) .. ".png")
    end

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

--- Find the exported PNG file on disk with retry to handle filesystem sync latency.
-- @param basePath string expected base file path
-- @param pageIndex number 1-based page index
-- @param baseName string base name without extension
-- @param tempDir string temp directory
-- @param sep string path separator
-- @param maxAttempts number optional maximum polling attempts (default 3)
-- @return string or nil path to verified file
function CopyPagePlugin.findExportedPngFileWithRetry(basePath, pageIndex, baseName, tempDir, sep, maxAttempts)
    local attempts = maxAttempts or 3
    for i = 1, attempts do
        local found = CopyPagePlugin.findExportedPngFile(basePath, pageIndex, baseName, tempDir, sep)
        if found then
            return found
        end
        if i < attempts then
            local t0 = os.clock()
            while (os.clock() - t0) < 0.03 do end
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
    local pageInfo = doc and doc.pages and (doc.pages[pageIndex] or doc.pages[pageIndex - 1] or doc.pages[1])
    local docWidth = (pageInfo and pageInfo.pageWidth and pageInfo.pageWidth > 0) and pageInfo.pageWidth or 595.28
    if docWidth <= 0 then docWidth = 595.28 end
    local calculatedDpi = math.floor(((tonumber(cfg.width) or 1920) * 72.0) / docWidth + 0.5)
    if calculatedDpi < 50 then calculatedDpi = 50 end

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
            local found = CopyPagePlugin.findExportedPngFileWithRetry(targetPath, pageIndex, baseName, tempDir, sep)
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
            local found = CopyPagePlugin.findExportedPngFileWithRetry(targetPath, pageIndex, baseName, tempDir, sep)
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
        local osType = CopyPagePlugin.detectOS()
        local cliCmd
        if osType == "windows" then
            cliCmd = string.format('xournalpp "%s" -i "%s" --export-range=%s --export-png-dpi=%d',
                doc.xoppFilename:gsub('"', ''), targetPath:gsub('"', ''), tostring(pageIndex), effectiveDpi)
        else
            cliCmd = string.format('xournalpp %s -i %s --export-range=%s --export-png-dpi=%d',
                CopyPagePlugin.shellEscape(doc.xoppFilename),
                CopyPagePlugin.shellEscape(targetPath),
                tostring(pageIndex), effectiveDpi)
        end

        pcall(os.execute, cliCmd)
        local found = CopyPagePlugin.findExportedPngFileWithRetry(targetPath, pageIndex, baseName, tempDir, sep)
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
-- @param isAsync boolean optional flag to execute in background (default true)
-- @return boolean success, string or nil error message
function CopyPagePlugin.copyImageToClipboard(imagePath, filesToClean, isAsync)
    local osType = CopyPagePlugin.detectOS()
    -- Default to asynchronous execution (isAsync ~= false) to prevent UI freezing
    local async = (isAsync ~= false)
    local cmd = CopyPagePlugin.getClipboardCommand(imagePath, osType, filesToClean, async)

    local execStatus, execKind, execCode = os.execute(cmd)

    -- In Lua 5.3+, os.execute returns (true, "exit", 0) on success.
    -- In Lua 5.1/LuaJIT, it returns status code 0 on success.
    local success = (execStatus == true or execStatus == 0)

    -- If synchronous execution was requested, perform cleanup now
    if not async then
        CopyPagePlugin.cleanupFiles(filesToClean)
    else
        -- If background launch itself failed, clean up immediately
        if not success then
            CopyPagePlugin.cleanupFiles(filesToClean)
        end
    end

    if success then
        return true, nil
    else
        local errMsg = string.format("Clipboard command failed (status=%s, code=%s)", tostring(execStatus), tostring(execCode))
        if osType == "linux" and (execCode == 127 or execStatus == false or execStatus == nil) then
            errMsg = errMsg .. ". No clipboard tool found. Please install wl-clipboard (Wayland) or xclip/xsel (X11)."
        end
        return false, errMsg
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

    -- Run clipboard operation asynchronously in the background to keep the UI completely responsive
    local ok, clipErr = CopyPagePlugin.copyImageToClipboard(exportedFile, filesToClean, true)
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
-- 6. Quality Configuration & Input Dialog
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

--- Build Windows PowerShell dialog command.
-- Displays a WinForms dialog allowing user to choose mode and enter custom value.
-- @param currentConfig table current active config
-- @return string execution command
function CopyPagePlugin.getWindowsDialogCommand(currentConfig)
    local cfg = currentConfig or CopyPagePlugin.config
    local isWidth = (cfg.mode == "width")
    local currentDpi = tostring(tonumber(cfg.dpi) or 300)
    local currentWidth = tostring(tonumber(cfg.width) or 1920)
    local initVal = isWidth and currentWidth or currentDpi
    local dpiChecked = isWidth and "$false" or "$true"
    local widthChecked = isWidth and "$true" or "$false"

    local ps = string.format(
        'Add-Type -AssemblyName System.Windows.Forms; ' ..
        'Add-Type -AssemblyName System.Drawing; ' ..
        '$f = New-Object System.Windows.Forms.Form; ' ..
        '$f.Text = \'Quality Settings\'; ' ..
        '$f.Size = New-Object System.Drawing.Size(320, 230); ' ..
        '$f.StartPosition = \'CenterScreen\'; ' ..
        '$f.FormBorderStyle = \'FixedDialog\'; ' ..
        '$f.MaximizeBox = $false; $f.MinimizeBox = $false; ' ..
        '$lbl = New-Object System.Windows.Forms.Label; ' ..
        '$lbl.Text = \'Select Quality Mode:\'; ' ..
        '$lbl.Location = New-Object System.Drawing.Point(20, 15); ' ..
        '$lbl.Size = New-Object System.Drawing.Size(260, 20); ' ..
        '$f.Controls.Add($lbl); ' ..
        '$rbDpi = New-Object System.Windows.Forms.RadioButton; ' ..
        '$rbDpi.Text = \'DPI (dots/in)\'; ' ..
        '$rbDpi.Location = New-Object System.Drawing.Point(30, 40); ' ..
        '$rbDpi.Size = New-Object System.Drawing.Size(110, 22); ' ..
        '$rbDpi.Checked = %s; ' ..
        '$f.Controls.Add($rbDpi); ' ..
        '$rbW = New-Object System.Windows.Forms.RadioButton; ' ..
        '$rbW.Text = \'Width (pixels)\'; ' ..
        '$rbW.Location = New-Object System.Drawing.Point(150, 40); ' ..
        '$rbW.Size = New-Object System.Drawing.Size(120, 22); ' ..
        '$rbW.Checked = %s; ' ..
        '$f.Controls.Add($rbW); ' ..
        '$lblVal = New-Object System.Windows.Forms.Label; ' ..
        '$lblVal.Text = \'Enter Value (DPI: 50-2400, Width: 100-10000):\'; ' ..
        '$lblVal.Location = New-Object System.Drawing.Point(20, 72); ' ..
        '$lblVal.Size = New-Object System.Drawing.Size(270, 20); ' ..
        '$f.Controls.Add($lblVal); ' ..
        '$txt = New-Object System.Windows.Forms.TextBox; ' ..
        '$txt.Text = \'%s\'; ' ..
        '$txt.Location = New-Object System.Drawing.Point(20, 95); ' ..
        '$txt.Size = New-Object System.Drawing.Size(260, 24); ' ..
        '$f.Controls.Add($txt); ' ..
        '$rbW.add_CheckedChanged({ if ($rbW.Checked -and $txt.Text -eq \'%s\') { $txt.Text = \'%s\' } }); ' ..
        '$rbDpi.add_CheckedChanged({ if ($rbDpi.Checked -and $txt.Text -eq \'%s\') { $txt.Text = \'%s\' } }); ' ..
        '$btnOk = New-Object System.Windows.Forms.Button; ' ..
        '$btnOk.Text = \'OK\'; ' ..
        '$btnOk.Location = New-Object System.Drawing.Point(50, 140); ' ..
        '$btnOk.Size = New-Object System.Drawing.Size(90, 30); ' ..
        '$btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK; ' ..
        '$f.AcceptButton = $btnOk; ' ..
        '$f.Controls.Add($btnOk); ' ..
        '$btnCan = New-Object System.Windows.Forms.Button; ' ..
        '$btnCan.Text = \'Cancel\'; ' ..
        '$btnCan.Location = New-Object System.Drawing.Point(160, 140); ' ..
        '$btnCan.Size = New-Object System.Drawing.Size(90, 30); ' ..
        '$btnCan.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; ' ..
        '$f.CancelButton = $btnCan; ' ..
        '$f.Controls.Add($btnCan); ' ..
        '$f.TopMost = $true; ' ..
        '$res = $f.ShowDialog(); ' ..
        '$outStr = if ($res -eq [System.Windows.Forms.DialogResult]::OK) { ' ..
        '$m = if ($rbW.Checked) { \'width\' } else { \'dpi\' }; ' ..
        '\'MODE=\' + $m + \';VALUE=\' + $txt.Text.Trim() ' ..
        '} else { \'CANCEL\' }; ' ..
        '$f.Dispose(); ' ..
        'Write-Output $outStr;',
        dpiChecked, widthChecked, initVal, currentDpi, currentWidth, currentWidth, currentDpi
    )

    return string.format(
        'powershell.exe -Sta -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "%s"',
        ps
    )
end

--- Build Linux dialog command using zenity or kdialog.
-- @param currentConfig table current active config
-- @return string execution command
function CopyPagePlugin.getLinuxDialogCommand(currentConfig)
    local cfg = currentConfig or CopyPagePlugin.config
    local isWidth = (cfg.mode == "width")
    local initVal = isWidth and tostring(cfg.width or 1920) or tostring(cfg.dpi or 300)
    local comboValues = isWidth and "Fixed Width|DPI" or "DPI|Fixed Width"

    return string.format(
        'if command -v zenity >/dev/null 2>&1; then ' ..
        'zenity --forms --title="Quality Settings" --text="Configure CopyPageToClipboard Settings" ' ..
        '--add-combo="Mode" --combo-values="%s" --add-entry="Value (e.g. 300 for DPI, 1920 for Width)" 2>/dev/null; ' ..
        'elif command -v kdialog >/dev/null 2>&1; then ' ..
        'kdialog --title "Quality Settings" --inputbox "Enter Quality (e.g. 300 dpi or 1920 px):" "%s" 2>/dev/null; ' ..
        'else echo "CANCEL"; fi',
        comboValues, initVal
    )
end

--- Build macOS AppleScript dialog command.
-- @param currentConfig table current active config
-- @return string execution command
function CopyPagePlugin.getMacDialogCommand(currentConfig)
    local cfg = currentConfig or CopyPagePlugin.config
    local isWidth = (cfg.mode == "width")
    local defaultText = isWidth and string.format("%d px", cfg.width or 1920) or string.format("%d dpi", cfg.dpi or 300)

    local script = string.format(
        'try\n' ..
        '  set res to (display dialog "Enter Quality Setting (e.g. 300 dpi or 1920 px):" default answer "%s" with title "Quality Settings" buttons {"Cancel", "OK"} default button "OK")\n' ..
        '  text returned of res\n' ..
        'on error number -128\n' ..
        '  "CANCEL"\n' ..
        'end try',
        defaultText
    )

    return string.format("osascript -e '%s'", script:gsub("'", "'\\''"))
end

--- Resolve the dialog command for the current or specified OS.
-- @param osName string optional OS name override
-- @param currentConfig table optional config table
-- @return string execution command
function CopyPagePlugin.getDialogCommand(osName, currentConfig)
    local targetOS = osName or CopyPagePlugin.detectOS()
    if targetOS == "windows" then
        return CopyPagePlugin.getWindowsDialogCommand(currentConfig)
    elseif targetOS == "macos" then
        return CopyPagePlugin.getMacDialogCommand(currentConfig)
    else
        return CopyPagePlugin.getLinuxDialogCommand(currentConfig)
    end
end

--- Prompt the user for quality settings via GUI dialog.
-- Checks:
-- 1. dialogPromptOverride / mockDialogInput (useful for testing or automation)
-- 2. Native GTK3 dialog via Lua lgi (if embedded within Xournal++ GTK environment)
-- 3. Native host OS dialog (PowerShell WinForms on Windows, zenity on Linux, osascript on macOS)
-- @return string or nil raw response from user or dialog
function CopyPagePlugin.promptQualityDialog()
    if type(CopyPagePlugin.dialogPromptOverride) == "function" then
        return CopyPagePlugin.dialogPromptOverride()
    end
    if CopyPagePlugin.mockDialogInput ~= nil then
        return CopyPagePlugin.mockDialogInput
    end

    -- 1. Try GTK3 Dialog via lgi if available in Xournal++
    local okLgi, lgi = pcall(require, "lgi")
    if okLgi and lgi then
        local okGtk, Gtk = pcall(lgi.require, "Gtk", "3.0")
        if okGtk and Gtk and Gtk.Dialog then
            local okRun, result = pcall(function()
                local isWidth = (CopyPagePlugin.config.mode == "width")
                local initVal = isWidth and tostring(CopyPagePlugin.config.width or 1920) or tostring(CopyPagePlugin.config.dpi or 300)

                local dlg = Gtk.Dialog({
                    title = "Quality Settings",
                    modal = true,
                    destroy_with_parent = true
                })
                dlg:add_button("Cancel", Gtk.ResponseType.CANCEL)
                dlg:add_button("OK", Gtk.ResponseType.OK)

                local content = dlg:get_content_area()
                content:set_spacing(8)
                content:set_border_width(12)

                local lblMode = Gtk.Label({ label = "<b>Quality Mode:</b>", use_markup = true, xalign = 0 })
                content:add(lblMode)

                local rbDpi = Gtk.RadioButton({ label = "DPI (dots per inch)", active = not isWidth })
                local rbWidth = Gtk.RadioButton({ label = "Fixed Width (pixels)", group = rbDpi, active = isWidth })
                content:add(rbDpi)
                content:add(rbWidth)

                local lblVal = Gtk.Label({ label = "<b>Value (DPI: 50-2400, Width: 100-10000):</b>", use_markup = true, xalign = 0 })
                content:add(lblVal)

                local entry = Gtk.Entry({ text = initVal })
                content:add(entry)

                dlg:show_all()
                local response = dlg:run()
                local chosenMode = rbWidth:get_active() and "width" or "dpi"
                local textVal = entry:get_text() or ""
                dlg:destroy()

                if response == Gtk.ResponseType.OK then
                    return string.format("MODE=%s;VALUE=%s", chosenMode, textVal)
                else
                    return "CANCEL"
                end
            end)
            if okRun and result then
                return result
            end
        end
    end

    -- 2. Fallback to OS native GUI prompt via io.popen
    local cmd = CopyPagePlugin.getDialogCommand()
    local handle = io.popen(cmd)
    if not handle then
        return nil
    end

    local output = handle:read("*a") or ""
    handle:close()

    local trimmed = ""
    for line in output:gmatch("[^\r\n]+") do
        local l = line:match("^%s*(.-)%s*$")
        if l ~= "" then
            if l:upper() == "CANCEL" or l:upper():match("^MODE=") then
                trimmed = l
                break
            else
                trimmed = l
            end
        end
    end

    if trimmed == "" then
        return "CANCEL"
    end
    return trimmed
end

--- Parse and validate raw user input from settings dialog or text prompt.
-- Supports:
-- - Structured format: "MODE=dpi;VALUE=450" or "MODE=width;VALUE=2560"
-- - Pipe format: "DPI|300" or "Fixed Width|1920"
-- - Natural format with units: "450 dpi", "2560 px", "width 1920", "1280w"
-- - Pure numbers: "600", "2560" (uses defaultMode or current mode)
-- @param inputStr string raw input string
-- @param defaultMode string optional fallback mode ("dpi" or "width")
-- @return table { mode = "dpi"|"width", value = number } or nil, string error message
function CopyPagePlugin.parseQualityInput(inputStr, defaultMode)
    if not inputStr or inputStr == "" then
        return nil, "No input provided."
    end

    local raw = inputStr:gsub("[\r\n]+", " "):match("^%s*(.-)%s*$")
    if not raw or raw == "" or raw:upper() == "CANCEL" then
        return nil, "Cancelled"
    end

    if raw:match("^([^|]+)|%s*$") then
        return nil, "No quality value entered."
    end

    -- Check structured output: MODE=xxx;VALUE=yyy or MODE=xxx|VALUE=yyy
    local sMode, sVal = raw:match("^[Mm][Oo][Dd][Ee]%s*[:=]%s*([%w_]+)%s*[;|]%s*[Vv][Aa][Ll][Uu][Ee]%s*[:=]%s*(.-)$")
    if not sMode then
        -- Check pipe-delimited format (e.g. from zenity --forms): "DPI|300" or "Fixed Width|1920"
        local pMode, pVal = raw:match("^([^|]+)|([^|]+)$")
        if pMode and pVal then
            pMode = pMode:lower():gsub("%s+", "")
            if pMode:find("width") or pMode:find("pixel") then
                sMode = "width"
            else
                sMode = "dpi"
            end
            sVal = pVal
        end
    end

    local mode = defaultMode or CopyPagePlugin.config.mode or "dpi"
    local num = nil

    if sMode and sVal then
        local m = sMode:lower()
        if m == "dpi" or m == "width" then
            mode = m
        end
        sVal = sVal:match("^%s*(.-)%s*$")
        local sign, digits = sVal:match("([%+%-]?)%s*(%d+%.?%d*)")
        if digits and digits ~= "" then
            num = tonumber(digits)
            if num and sign == "-" then
                num = -num
            end
        end
    else
        local lower = raw:lower()
        if lower:find("width") or lower:find("px") or lower:find("pixel") or lower:match("%d+%s*w$") then
            mode = "width"
        elseif lower:find("dpi") or lower:find("dots") then
            mode = "dpi"
        end

        local sign, digits = lower:match("([%+%-]?)%s*(%d+%.?%d*)")
        if digits and digits ~= "" then
            num = tonumber(digits)
            if num and sign == "-" then
                num = -num
            end
        end
    end

    if not num then
        return nil, string.format("Invalid numeric value in '%s'.", raw)
    end

    num = math.floor(num)

    if mode == "dpi" then
        if num < 50 or num > 2400 then
            return nil, string.format("DPI %d out of valid range (50 - 2400 DPI).", num)
        end
        return { mode = "dpi", value = num }, nil
    else
        if num < 100 or num > 10000 then
            return nil, string.format("Width %d px out of valid range (100 - 10000 px).", num)
        end
        return { mode = "width", value = num }, nil
    end
end

--- Apply and persist new quality settings.
-- @param mode string "dpi" or "width"
-- @param value number numeric setting
-- @return boolean success, string message
function CopyPagePlugin.applyQualitySettings(mode, value)
    if mode == "width" then
        CopyPagePlugin.config.mode = "width"
        CopyPagePlugin.config.width = math.floor(value)
    else
        CopyPagePlugin.config.mode = "dpi"
        CopyPagePlugin.config.dpi = math.floor(value)
    end

    local ok, err = CopyPagePlugin.saveConfig()
    if ok then
        local msg = (CopyPagePlugin.config.mode == "width")
            and string.format("Quality settings updated: Fixed Width (%d px).", CopyPagePlugin.config.width)
            or string.format("Quality settings updated: DPI (%d DPI).", CopyPagePlugin.config.dpi)
        CopyPagePlugin.notify(msg, false)
        return true, msg
    else
        local errMsg = "Failed to save configuration: " .. tostring(err)
        CopyPagePlugin.notify(errMsg, true)
        return false, errMsg
    end
end

--- Open quality dialog, parse result, and update configuration.
-- @param rawInput string optional direct input string (bypasses dialog GUI prompt)
-- @return boolean success, string or nil message
function CopyPagePlugin.configureQuality(rawInput)
    local input = rawInput
    if not input then
        input = CopyPagePlugin.promptQualityDialog()
    end

    if not input or input == "CANCEL" or input == "" then
        return false, "Operation cancelled by user."
    end

    local parsed, err = CopyPagePlugin.parseQualityInput(input, CopyPagePlugin.config.mode)
    if not parsed then
        CopyPagePlugin.notify("Invalid quality setting: " .. tostring(err), true)
        return false, err
    end

    return CopyPagePlugin.applyQualitySettings(parsed.mode, parsed.value)
end

--------------------------------------------------------------------------------
-- 7. Xournal++ Plugin Initialization & Global Callbacks
--------------------------------------------------------------------------------

-- Global wrapper functions for Xournal++ Lua callbacks
function copyCurrentPage()
    return CopyPagePlugin.copyCurrentPage()
end

function actionConfigureQuality()
    return CopyPagePlugin.configureQuality()
end

-- Backward compatibility actions
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

    -- Single clean quality settings menu entry replacing 6 cluttered preset options
    app.registerUi({
        ["menu"] = "Quality Settings...",
        ["callback"] = "actionConfigureQuality"
    })
end

-- Automatically load configuration when script is parsed
CopyPagePlugin.initConfiguration()

return CopyPagePlugin
