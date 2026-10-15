-- test_plugin.lua: Automated test suite for CopyPageToClipboard
-- Compatible with Lua 5.3+

local testsPassed = 0
local testsFailed = 0

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        local err = string.format("FAIL: %s (Expected: %s, Got: %s)", msg or "Assertion failed", tostring(expected), tostring(actual))
        print(err)
        testsFailed = testsFailed + 1
        error(err)
    else
        testsPassed = testsPassed + 1
    end
end

local function assert_true(cond, msg)
    if not cond then
        local err = string.format("FAIL: %s (Expected truthy, got %s)", msg or "Assertion failed", tostring(cond))
        print(err)
        testsFailed = testsFailed + 1
        error(err)
    else
        testsPassed = testsPassed + 1
    end
end

print("======================================================================")
print("Running CopyPageToClipboard Lua Test Suite")
print("======================================================================")

-- Load plugin module
local plugin = require("main")

--------------------------------------------------------------------------------
-- 1. Plugin.ini Specification Verification
--------------------------------------------------------------------------------
print("\n[Test 1] Verifying plugin.ini...")
local iniFile = io.open("plugin.ini", "r")
assert_true(iniFile ~= nil, "plugin.ini must exist")
local iniContent = iniFile:read("*a")
iniFile:close()

assert_true(iniContent:find("%[about%]"), "plugin.ini must contain [about] section")
assert_true(iniContent:find("author="), "plugin.ini must contain author")
assert_true(iniContent:find("description="), "plugin.ini must contain description")
assert_true(iniContent:find("version=<xournalpp>"), "plugin.ini must have version=<xournalpp>")
assert_true(iniContent:find("%[plugin%]"), "plugin.ini must contain [plugin] section")
assert_true(iniContent:find("mainfile=main.lua"), "plugin.ini must specify mainfile=main.lua")
assert_true(iniContent:find("<Control><Alt>c"), "plugin.ini must define <Control><Alt>c shortcut")
print("  PASSED: plugin.ini matches all specifications.")

--------------------------------------------------------------------------------
-- 2. Configuration Persistence Tests
--------------------------------------------------------------------------------
print("\n[Test 2] Verifying configuration persistence...")
local tempDir = plugin.getTempDir()
local sep = (plugin.detectOS() == "windows") and "\\" or "/"
local testConfigPath = tempDir .. sep .. "test_copypage_config_" .. tostring(os.time()) .. ".ini"

-- Test 2a: Save custom settings (Fixed Width mode, 2560px)
local customConfig = {
    mode = "width",
    dpi = 150,
    width = 2560
}
local saveOk, saveErr = plugin.saveConfig(testConfigPath, customConfig)
assert_true(saveOk, "Saving config should succeed: " .. tostring(saveErr))
assert_true(plugin.fileExists(testConfigPath), "Config file must exist on disk")

-- Test 2b: Load custom settings back and verify values
local loadedConfig = plugin.loadConfig(testConfigPath)
assert_eq(loadedConfig.mode, "width", "Config mode should be width")
assert_eq(loadedConfig.width, 2560, "Config width should be 2560")
assert_eq(loadedConfig.dpi, 150, "Config dpi should be 150")

-- Test 2c: Update to DPI mode, 600 DPI, and verify
customConfig.mode = "dpi"
customConfig.dpi = 600
plugin.saveConfig(testConfigPath, customConfig)
local loadedConfig2 = plugin.loadConfig(testConfigPath)
assert_eq(loadedConfig2.mode, "dpi", "Config mode should be dpi")
assert_eq(loadedConfig2.dpi, 600, "Config dpi should be 600")

-- Test 2d: Test edge cases and fallbacks in config loading
local invalidConfigPath = tempDir .. sep .. "invalid_config.ini"
local f = io.open(invalidConfigPath, "w")
f:write("# Comment line\n")
f:write("; Another comment\n")
f:write("mode = INVALID_MODE\n")
f:write("dpi = -100\n")
f:write("width = 9999999\n")
f:close()
local safeConfig = plugin.loadConfig(invalidConfigPath)
assert_eq(safeConfig.mode, "dpi", "Invalid mode should fallback to default (dpi)")
assert_eq(safeConfig.dpi, 300, "Negative DPI should fallback to default (300)")
assert_eq(safeConfig.width, 1920, "Out-of-range width should fallback to default (1920)")

-- Test 2e: Comments, quotes, and whitespace in config loading
local commentConfigPath = tempDir .. sep .. "comment_config.ini"
local fc = io.open(commentConfigPath, "w")
fc:write("  mode = \"width\" # inline comment\n")
fc:write("  dpi = '600' ; trailing comment\n")
fc:write("  width = 2560\n")
fc:close()
local parsedCommentConfig = plugin.loadConfig(commentConfigPath)
assert_eq(parsedCommentConfig.mode, "width", "Quoted mode with inline comment should parse correctly")
assert_eq(parsedCommentConfig.dpi, 600, "Quoted dpi with trailing comment should parse correctly")
assert_eq(parsedCommentConfig.width, 2560, "Width should parse correctly")
os.remove(commentConfigPath)

-- Test 2f: Corrupted / non-numeric config table resilience in saveConfig
local corruptConfig = { mode = "unexpected", dpi = "not_a_number", width = nil }
local corruptSavePath = tempDir .. sep .. "corrupt_save_test.ini"
local cSaveOk, cSaveErr = plugin.saveConfig(corruptSavePath, corruptConfig)
assert_true(cSaveOk, "saveConfig should succeed even with corrupted values without runtime error")
local reloadedCorrupt = plugin.loadConfig(corruptSavePath)
assert_eq(reloadedCorrupt.mode, "dpi", "Corrupted mode should fallback to dpi")
assert_eq(reloadedCorrupt.dpi, 300, "Corrupted dpi should fallback to 300")
assert_eq(reloadedCorrupt.width, 1920, "Nil width should fallback to 1920")
os.remove(corruptSavePath)

-- Cleanup test config files
os.remove(testConfigPath)
os.remove(invalidConfigPath)
print("  PASSED: Configuration persistence correctly reads, writes, and validates settings.")

--------------------------------------------------------------------------------
-- 3. Quality Mode Actions and Cycling
--------------------------------------------------------------------------------
print("\n[Test 3] Verifying quality presets and cycling...")
local cycleConfigPath = tempDir .. sep .. "test_copypage_cycle_" .. tostring(os.time()) .. ".ini"
plugin.customConfigPath = cycleConfigPath
plugin.config.mode = "dpi"
plugin.config.dpi = 300
plugin.config.width = 1920

plugin.toggleMode()
assert_eq(plugin.config.mode, "width", "Toggling from dpi should give width")
plugin.toggleMode()
assert_eq(plugin.config.mode, "dpi", "Toggling from width should give dpi")

-- Cycle DPI: 150 -> 300 -> 600 -> 150
plugin.config.dpi = 150
plugin.cycleDpi()
assert_eq(plugin.config.dpi, 300, "150 DPI should cycle to 300 DPI")
plugin.cycleDpi()
assert_eq(plugin.config.dpi, 600, "300 DPI should cycle to 600 DPI")
plugin.cycleDpi()
assert_eq(plugin.config.dpi, 150, "600 DPI should cycle back to 150 DPI")

-- Cycle Width: 1280 -> 1920 -> 2560 -> 3840 -> 1280
plugin.config.width = 1280
plugin.cycleWidth()
assert_eq(plugin.config.width, 1920, "1280 px should cycle to 1920 px")
plugin.cycleWidth()
assert_eq(plugin.config.width, 2560, "1920 px should cycle to 2560 px")
plugin.cycleWidth()
assert_eq(plugin.config.width, 3840, "2560 px should cycle to 3840 px")
plugin.cycleWidth()
assert_eq(plugin.config.width, 1280, "3840 px should cycle back to 1280 px")

-- Reset configuration to clean default state and clean up temp file
plugin.config.mode = "dpi"
plugin.config.dpi = 300
plugin.config.width = 1920
plugin.saveConfig(cycleConfigPath, plugin.config)
os.remove(cycleConfigPath)
plugin.customConfigPath = nil
print("  PASSED: Mode toggling and preset cycling function correctly without polluting environment.")

--------------------------------------------------------------------------------
-- 4. Operating System Detection & Command Formation
--------------------------------------------------------------------------------
print("\n[Test 4] Verifying OS detection and clipboard commands...")
local detected = plugin.detectOS()
assert_true(detected == "windows" or detected == "linux" or detected == "macos", "detectOS must return valid OS name")
print("  Detected host OS: " .. detected)

local sampleImagePath = "/path/to/test page.png"
if detected == "windows" then
    sampleImagePath = "C:\\path\\to\\test page.png"
end

-- Test Windows Command
local winCmd = plugin.getWindowsClipboardCommand("C:\\Users\\Test\\AppData\\Local\\Temp\\page.png")
assert_true(winCmd:find("powershell%.exe"), "Windows command must invoke powershell.exe")
assert_true(winCmd:find("-Sta"), "Windows command must use -Sta for STA apartment state")
assert_true(winCmd:find("System%.Windows%.Forms"), "Windows command must load System.Windows.Forms")
assert_true(winCmd:find("System%.Drawing"), "Windows command must load System.Drawing")
assert_true(winCmd:find("Clipboard%]:%:SetDataObject") or winCmd:find("Clipboard%]:%:SetImage"), "Windows command must call SetDataObject or SetImage")
assert_true(winCmd:find("Dispose%(%)"), "Windows command must dispose image to release file lock")
assert_true(not winCmd:find("\\"), "Windows command should normalize backslashes to forward slashes")
assert_true(winCmd:find("-ExecutionPolicy Bypass"), "Windows command should use -ExecutionPolicy Bypass")
assert_true(winCmd:find("try"), "Windows command must use try block for robust error handling")
assert_true(winCmd:find("catch"), "Windows command must use catch block")
assert_true(winCmd:find("exit 1"), "Windows command must exit 1 on failure")

-- Test Windows Command with embedded single quotes (e.g. John O'Connor)
local winCmdQuotes = plugin.getWindowsClipboardCommand("C:\\Users\\John O'Connor\\AppData\\Local\\Temp\\page.png")
assert_true(winCmdQuotes:find("O''Connor"), "Windows command must escape single quotes as double single-quotes")

-- Test shellEscape helper directly
local escaped = plugin.shellEscape("/tmp/path with 'quotes' and $VAR and `cmd`.png")
assert_true(escaped:sub(1, 1) == "'", "shellEscape must start with single quote")
assert_true(escaped:sub(-1) == "'", "shellEscape must end with single quote")
assert_true(escaped:find("'\\''quotes'\\''") ~= nil, "shellEscape must safely escape embedded single quotes")

-- Test Linux Wayland Command
local waylandCmd = plugin.getLinuxWaylandCommand("/tmp/page.png")
assert_true(waylandCmd:find("wl%-copy"), "Wayland command must invoke wl-copy")
assert_true(waylandCmd:find("image/png"), "Wayland command must specify image/png MIME type")

-- Test Linux X11 Command
local x11Cmd = plugin.getLinuxX11Command("/tmp/page.png")
assert_true(x11Cmd:find("xclip"), "X11 command must invoke xclip")
assert_true(x11Cmd:find("clipboard"), "X11 command must specify clipboard selection")
assert_true(x11Cmd:find("image/png"), "X11 command must specify image/png target")

-- Test Linux Universal Fallback Command
local linuxCmd = plugin.getLinuxCommand("/tmp/page.png")
assert_true(linuxCmd:find("wl%-copy"), "Linux universal command must check wl-copy")
assert_true(linuxCmd:find("xclip"), "Linux universal command must check xclip")
assert_true(linuxCmd:find("xsel"), "Linux universal command must check xsel")

-- Test macOS Command
local macCmd = plugin.getMacClipboardCommand("/tmp/page.png")
assert_true(macCmd:find("osascript"), "macOS command must invoke osascript")
assert_true(macCmd:find("«class PNGf»"), "macOS command must cast to «class PNGf»")
assert_true(macCmd:find("POSIX file"), "macOS command must use POSIX file handler")

-- Test macOS Command escaping
local macEscaped = plugin.getMacClipboardCommand("/tmp/test 'image' \"quoted\".png")
assert_true(macEscaped:find("\\\"quoted\\\"") ~= nil, "macOS command must escape double quotes for AppleScript")

-- Test Linux missing clipboard tool informative error message
local savedDetect = plugin.detectOS
plugin.detectOS = function() return "linux" end
local origExec = os.execute
os.execute = function() return nil, "exit", 127 end
local lOk, lErr = plugin.copyImageToClipboard("/tmp/test.png", {})
assert_true(not lOk, "copyImageToClipboard should report failure on exit code 127")
assert_true(lErr:find("wl%-clipboard") ~= nil, "Linux exit code 127 error message should mention wl-clipboard")
assert_true(lErr:find("xclip") ~= nil, "Linux exit code 127 error message should mention xclip")
os.execute = origExec
plugin.detectOS = savedDetect

-- Test Asynchronous Clipboard Commands & Background Cleanup formatting
local asyncWinCmd = plugin.getWindowsClipboardCommand("C:\\page.png", { "C:\\page.png", "C:\\page-1.png" }, true)
assert_true(asyncWinCmd:find('start "" /B'), "Windows async command must use start \"\" /B")
assert_true(asyncWinCmd:find("Remove%-Item"), "Windows async command must include Remove-Item in finally block")
assert_true(asyncWinCmd:find("@%('C:/page%.png', 'C:/page%-1%.png'%)") ~= nil, "Windows async command must format file cleanup array")

local asyncLinuxCmd = plugin.getLinuxCommand("/tmp/page.png", { "/tmp/page.png", "/tmp/page-1.png" }, true)
assert_true(asyncLinuxCmd:sub(1, 2) == "( ", "Linux async command must start with subshell (")
assert_true(asyncLinuxCmd:find("&%s*$") ~= nil, "Linux async command must end with background operator &")
assert_true(asyncLinuxCmd:find("rm %-f '/tmp/page%.png' '/tmp/page%-1%.png'") ~= nil, "Linux async command must include rm -f cleanup")

local asyncMacCmd = plugin.getMacClipboardCommand("/tmp/page.png", { "/tmp/page.png" }, true)
assert_true(asyncMacCmd:find("&%s*$") ~= nil, "macOS async command must end with background operator &")
assert_true(asyncMacCmd:find("rm %-f '/tmp/page%.png'") ~= nil, "macOS async command must include rm -f cleanup")

print("  PASSED: Cross-platform clipboard commands correctly formed and escaped for Windows, Linux, and macOS (sync & async).")

--------------------------------------------------------------------------------
-- 5. Temporary File Management & Path Resolution
--------------------------------------------------------------------------------
print("\n[Test 5] Verifying temporary path resolution and file cleanup...")
local resolvedTempDir, pathSep = plugin.getTempDir()
assert_true(resolvedTempDir ~= nil and resolvedTempDir ~= "", "Temp dir must not be empty")

local tempPath, baseName, d, s = plugin.createTempPngPath()
assert_true(tempPath:find("%.png$"), "Generated temp path must have .png extension")
assert_true(tempPath:find(baseName, 1, true) ~= nil, "Temp path must contain unique baseName")

-- Test findExportedPngFile variations
local dummyBase = tempDir .. sep .. "test_export_search_" .. tostring(os.time())
local dummy1 = dummyBase .. ".png"
local dummyPaged = dummyBase .. "-3.png"
local dummySingle = dummyBase .. "-1.png"

-- Case A: Direct file exists
local fA = io.open(dummy1, "wb") fA:write("dummy") fA:close()
assert_eq(plugin.findExportedPngFile(dummy1, 1), dummy1, "Should find direct file match")
os.remove(dummy1)

-- Case B: Page index suffixed file exists (e.g. -3.png for page 3)
local fB = io.open(dummyPaged, "wb") fB:write("dummy") fB:close()
assert_eq(plugin.findExportedPngFile(dummyBase .. ".png", 3), dummyPaged, "Should find page-indexed file match")
os.remove(dummyPaged)

-- Case C: Single suffix file exists (-1.png)
local fC = io.open(dummySingle, "wb") fC:write("dummy") fC:close()
assert_eq(plugin.findExportedPngFile(dummyBase .. ".png", 2), dummySingle, "Should find single-page -1.png match")
os.remove(dummySingle)

-- Case D: Underscore suffix file exists (e.g. _3.png for page 3)
local dummyUnderscore = dummyBase .. "_3.png"
local fD = io.open(dummyUnderscore, "wb") fD:write("dummy") fD:close()
assert_eq(plugin.findExportedPngFile(dummyBase .. ".png", 3), dummyUnderscore, "Should find underscore-suffixed _3.png match")
os.remove(dummyUnderscore)

-- Case E: Zero-padded underscore file exists (e.g. _01.png)
local dummyPadded_ = dummyBase .. "_01.png"
local fE = io.open(dummyPadded_, "wb") fE:write("dummy") fE:close()
assert_eq(plugin.findExportedPngFile(dummyBase .. ".png", 1), dummyPadded_, "Should find zero-padded underscore match")
os.remove(dummyPadded_)

-- Case F: Page-prefixed suffix exists (e.g. _page3.png)
local dummyPagePrefixed = dummyBase .. "_page3.png"
local fF = io.open(dummyPagePrefixed, "wb") fF:write("dummy") fF:close()
assert_eq(plugin.findExportedPngFile(dummyBase .. ".png", 3), dummyPagePrefixed, "Should find page-prefixed match")
os.remove(dummyPagePrefixed)

-- Case G: 0-based suffix match (e.g. -0.png for page 1)
local dummyZero = dummyBase .. "-0.png"
local fG = io.open(dummyZero, "wb") fG:write("dummy") fG:close()
assert_eq(plugin.findExportedPngFile(dummyBase .. ".png", 1), dummyZero, "Should find 0-based -0.png match")
os.remove(dummyZero)

-- Case H: Dot-separated match (e.g. .1.png)
local dummyDot = dummyBase .. ".1.png"
local fH = io.open(dummyDot, "wb") fH:write("dummy") fH:close()
assert_eq(plugin.findExportedPngFile(dummyBase .. ".png", 1), dummyDot, "Should find dot-separated .1.png match")
os.remove(dummyDot)

-- Case I: findExportedPngFileWithRetry verifies finding existing file
local dummyRetry = dummyBase .. "-retry.png"
local fI = io.open(dummyRetry, "wb") fI:write("dummy") fI:close()
assert_eq(plugin.findExportedPngFileWithRetry(dummyRetry, 1), dummyRetry, "findExportedPngFileWithRetry should find existing file")
os.remove(dummyRetry)

-- Test cleanupFiles safely removes list of files
local cleanFile1 = tempDir .. sep .. "clean_test_1.tmp"
local cleanFile2 = tempDir .. sep .. "clean_test_2.tmp"
local fc1 = io.open(cleanFile1, "w") fc1:write("a") fc1:close()
local fc2 = io.open(cleanFile2, "w") fc2:write("b") fc2:close()
assert_true(plugin.fileExists(cleanFile1), "cleanFile1 should exist before cleanup")
assert_true(plugin.fileExists(cleanFile2), "cleanFile2 should exist before cleanup")

plugin.cleanupFiles({ cleanFile1, cleanFile2, tempDir .. sep .. "non_existent.tmp" })
assert_true(not plugin.fileExists(cleanFile1), "cleanFile1 should be deleted after cleanup")
assert_true(not plugin.fileExists(cleanFile2), "cleanFile2 should be deleted after cleanup")
print("  PASSED: Path resolution, search patterns, and safe cleanup verified.")

--------------------------------------------------------------------------------
-- 6. Xournal++ UI Registration & Accelerator Verification
--------------------------------------------------------------------------------
print("\n[Test 6] Verifying Xournal++ UI registration...")
local registeredMenus = {}
local registeredAccelerators = {}

-- Create mock Xournal++ `app` global environment
_G.app = {
    registerUi = function(tbl)
        table.insert(registeredMenus, tbl.menu)
        if tbl.accelerator then
            table.insert(registeredAccelerators, tbl.accelerator)
        end
    end,
    getDocumentStructure = function()
        return {
            currentPage = 2,
            pages = { { pageWidth = 595, pageHeight = 842 }, { pageWidth = 595, pageHeight = 842 } },
            xoppFilename = "test_note.xopp"
        }
    end,
    msgbox = function(msg)
        print("  [Mock UI msgbox]: " .. tostring(msg))
    end
}

-- Execute initUi()
initUi()

assert_eq(#registeredMenus, 2, "Exactly 2 UI menu actions should be registered (decluttered)")
local hasPrimaryMenu = false
local hasQualityMenu = false
local hasCtrlAltC = false

for _, menu in ipairs(registeredMenus) do
    if menu:find("Copy Current Page") then
        hasPrimaryMenu = true
    elseif menu:find("Quality Settings") then
        hasQualityMenu = true
    end
end

for _, acc in ipairs(registeredAccelerators) do
    if acc == "<Control><Alt>c" then
        hasCtrlAltC = true
    end
end

assert_true(hasPrimaryMenu, "Primary 'Copy Current Page to Clipboard' menu must be registered")
assert_true(hasQualityMenu, "Single 'Quality Settings...' menu item must be registered")
assert_true(hasCtrlAltC, "<Control><Alt>c accelerator shortcut must be bound")

-- Verify active page index resolution
local resolvedPage, docStruct = plugin.getActivePageIndex()
assert_eq(resolvedPage, 2, "Active page index should match mock document currentPage (2)")

-- Test notification routing with app.openDialog
local openDialogCalled = false
local openDialogMsg = nil
local openDialogErr = nil
_G.app.openDialog = function(msg, options, cb, isError)
    openDialogCalled = true
    openDialogMsg = msg
    openDialogErr = isError
end

plugin.notify("Test Notification", false)
assert_true(openDialogCalled, "app.openDialog should be called by notify")
assert_eq(openDialogMsg, "Test Notification", "Notification message must match")
assert_eq(openDialogErr, false, "Notification isError must be false")

plugin.notify("Test Error Notification", true)
assert_eq(openDialogErr, true, "Notification isError must be true")

-- Test CLI export fallback DPI calculation in width mode
local docMock = {
    xoppFilename = tempDir .. sep .. "test_note_mock.xopp",
    currentPage = 1,
    pages = { { pageWidth = 595.28, pageHeight = 842 } }
}
local fx = io.open(docMock.xoppFilename, "w") fx:write("mock xopp") fx:close()

local capturedCliCmd = nil
local originalOsExec = os.execute
os.execute = function(cmd)
    capturedCliCmd = cmd
    return true, "exit", 0
end

plugin.config.mode = "width"
plugin.config.width = 1920
local savedExport = app.export
app.export = nil

local mockExportTarget = tempDir .. sep .. "test_cli_calc.png"
local fTarget = io.open(mockExportTarget, "wb") fTarget:write("test") fTarget:close()

local expFile, expErr = plugin.exportPage(1, mockExportTarget, docMock)
assert_true(capturedCliCmd ~= nil, "CLI command should be executed on fallback")
assert_true(capturedCliCmd:find("%-%-export%-png%-dpi="), "CLI command should use calculated DPI")
assert_true(not capturedCliCmd:find("%-%-export%-png%-width"), "CLI command must NOT use unsupported --export-png-width")
-- 1920 * 72 / 595.28 ≈ 232 DPI
assert_true(capturedCliCmd:find("%-%-export%-png%-dpi=232") ~= nil, "CLI command should calculate correct equivalent DPI (232)")

-- Restore mocks and cleanup
os.execute = originalOsExec
app.export = savedExport
os.remove(docMock.xoppFilename)
os.remove(mockExportTarget)
plugin.config.mode = "dpi"
plugin.config.dpi = 300

print("  PASSED: UI registration, accelerator shortcut, dialog notifications, and CLI DPI calculation verified.")

--------------------------------------------------------------------------------
-- 7. Live Windows Clipboard Execution & Cleanup (if running on Windows)
--------------------------------------------------------------------------------
if detected == "windows" then
    print("\n[Test 7] Executing live Windows clipboard integration test...")
    local randSuffix = tostring(os.time()) .. "_" .. tostring(math.random(10000, 99999))
    local testPngPath = tempDir .. sep .. "live_clip_test_" .. randSuffix .. ".png"
    -- 1x1 valid PNG image bytes
    local pngBytes = "\137\80\78\71\13\10\26\10\0\0\0\13\73\72\68\82\0\0\0\1\0\0\0\1\8\6\0\0\0\31\21\196\137\0\0\0\11\73\68\65\84\120\156\99\96\0\0\0\2\0\1\244\113\100\166\0\0\0\0\73\69\78\68\174\66\96\130"
    local fp = io.open(testPngPath, "wb")
    fp:write(pngBytes)
    fp:close()

    assert_true(plugin.fileExists(testPngPath), "Live test PNG file should be created")

    -- 7a. Asynchronous non-blocking copy test
    local t0 = os.clock()
    local copyOk, copyErr = plugin.copyImageToClipboard(testPngPath, { testPngPath }, true)
    local elapsed = os.clock() - t0
    assert_true(copyOk, "copyImageToClipboard async should succeed: " .. tostring(copyErr))
    assert_true(elapsed < 1.5, string.format("Async clipboard execution must return quickly to avoid freezing UI (took %.3fs)", elapsed))

    -- Poll for background PowerShell cleanup (up to 25 wall-clock seconds)
    local tPoll = os.time()
    local asyncCleaned = false
    while (os.time() - tPoll) < 25 do
        if not plugin.fileExists(testPngPath) then
            asyncCleaned = true
            break
        end
        local tw = os.clock()
        while (os.clock() - tw) < 0.2 do end
    end
    assert_true(asyncCleaned, "Async background process must automatically clean up the image file")

    -- 7b. Synchronous copy test with apostrophe path (backwards compatibility)
    local testAposPath = tempDir .. sep .. "live_clip_O'Connor_test_" .. randSuffix .. ".png"
    local fp2 = io.open(testAposPath, "wb")
    fp2:write(pngBytes)
    fp2:close()
    assert_true(plugin.fileExists(testAposPath), "Live apostrophe test PNG should be created")
    local copyAposOk, copyAposErr = plugin.copyImageToClipboard(testAposPath, { testAposPath }, false)
    assert_true(copyAposOk, "copyImageToClipboard sync with apostrophe path should execute successfully: " .. tostring(copyAposErr))
    assert_true(not plugin.fileExists(testAposPath), "Live apostrophe test PNG should be safely deleted immediately in sync mode")

    print("  PASSED: Live Windows PowerShell/.NET clipboard copy and cleanup succeeded (async and sync paths).")
end

--------------------------------------------------------------------------------
-- 8. Quality Settings Input Dialog & Custom Value Validation
--------------------------------------------------------------------------------
print("\n[Test 8] Verifying Quality Settings input parsing, validation, and dialog...")

-- 8a. Parse structured dialog outputs
local resDpi = plugin.parseQualityInput("MODE=dpi;VALUE=450")
assert_true(resDpi ~= nil, "parseQualityInput should parse MODE=dpi;VALUE=450")
assert_eq(resDpi.mode, "dpi", "Parsed mode should be dpi")
assert_eq(resDpi.value, 450, "Parsed value should be 450")

local resWidth = plugin.parseQualityInput("MODE=width;VALUE=2560")
assert_true(resWidth ~= nil, "parseQualityInput should parse MODE=width;VALUE=2560")
assert_eq(resWidth.mode, "width", "Parsed mode should be width")
assert_eq(resWidth.value, 2560, "Parsed value should be 2560")

-- 8b. Parse pipe format (e.g. Zenity)
local resZen1 = plugin.parseQualityInput("DPI|600")
assert_eq(resZen1.mode, "dpi", "Zenity DPI format should parse as dpi")
assert_eq(resZen1.value, 600, "Zenity DPI format value should be 600")

local resZen2 = plugin.parseQualityInput("Fixed Width|3840")
assert_eq(resZen2.mode, "width", "Zenity Width format should parse as width")
assert_eq(resZen2.value, 3840, "Zenity Width format value should be 3840")

-- 8c. Parse natural strings with units
local resNat1 = plugin.parseQualityInput("500 dpi")
assert_eq(resNat1.mode, "dpi", "500 dpi should parse as dpi")
assert_eq(resNat1.value, 500, "500 dpi value should be 500")

local resNat2 = plugin.parseQualityInput("2560 px")
assert_eq(resNat2.mode, "width", "2560 px should parse as width")
assert_eq(resNat2.value, 2560, "2560 px value should be 2560")

local resNat3 = plugin.parseQualityInput("width 1440")
assert_eq(resNat3.mode, "width", "width 1440 should parse as width")
assert_eq(resNat3.value, 1440, "width 1440 value should be 1440")

local resNat4 = plugin.parseQualityInput("1280w")
assert_eq(resNat4.mode, "width", "1280w should parse as width")
assert_eq(resNat4.value, 1280, "1280w value should be 1280")

-- 8d. Parse plain numbers using default mode
local resNum1 = plugin.parseQualityInput("400", "dpi")
assert_eq(resNum1.mode, "dpi", "400 with default mode dpi should be dpi")
assert_eq(resNum1.value, 400, "400 with default mode dpi value should be 400")

local resNum2 = plugin.parseQualityInput("1920", "width")
assert_eq(resNum2.mode, "width", "1920 with default mode width should be width")
assert_eq(resNum2.value, 1920, "1920 with default mode width value should be 1920")

-- 8e. Boundary validations
-- Valid boundaries: DPI 50 and 2400
local bDpiMin = plugin.parseQualityInput("MODE=dpi;VALUE=50")
assert_true(bDpiMin ~= nil, "50 DPI should be valid minimum")
local bDpiMax = plugin.parseQualityInput("MODE=dpi;VALUE=2400")
assert_true(bDpiMax ~= nil, "2400 DPI should be valid maximum")

-- Valid boundaries: Width 100 and 10000
local bWMin = plugin.parseQualityInput("MODE=width;VALUE=100")
assert_true(bWMin ~= nil, "100 px should be valid minimum width")
local bWMax = plugin.parseQualityInput("MODE=width;VALUE=10000")
assert_true(bWMax ~= nil, "10000 px should be valid maximum width")

-- Out-of-bounds rejected
local bDpiLow, errDpiLow = plugin.parseQualityInput("MODE=dpi;VALUE=49")
assert_true(bDpiLow == nil, "49 DPI should be rejected")
assert_true(errDpiLow:find("out of valid range") ~= nil, "Error should explain range")

local bDpiHigh, errDpiHigh = plugin.parseQualityInput("MODE=dpi;VALUE=2401")
assert_true(bDpiHigh == nil, "2401 DPI should be rejected")

local bWLow, errWLow = plugin.parseQualityInput("MODE=width;VALUE=99")
assert_true(bWLow == nil, "99 px width should be rejected")

local bWHigh, errWHigh = plugin.parseQualityInput("MODE=width;VALUE=10001")
assert_true(bWHigh == nil, "10001 px width should be rejected")

-- Negative values rejected
local bNegDpi, errNegDpi = plugin.parseQualityInput("-300 dpi")
assert_true(bNegDpi == nil, "Negative DPI must be rejected")
assert_true(errNegDpi:find("out of valid range") ~= nil, "Negative DPI error must indicate range")

local bNegW, errNegW = plugin.parseQualityInput("-1920 px")
assert_true(bNegW == nil, "Negative Width must be rejected")

local bNegStruct = plugin.parseQualityInput("MODE=dpi;VALUE=-300")
assert_true(bNegStruct == nil, "Structured negative value must be rejected")

-- Floating point quality values accepted and floored
local bFloatDpi = plugin.parseQualityInput("450.9 dpi")
assert_true(bFloatDpi ~= nil and bFloatDpi.value == 450, "Floating point DPI must be parsed and floored")

-- Zenity empty entry input rejected
local bEmptyZen, errEmptyZen = plugin.parseQualityInput("DPI|")
assert_true(bEmptyZen == nil, "Empty zenity entry must be rejected")
assert_true(errEmptyZen:find("No quality value entered") ~= nil, "Empty zenity message must be informative")

-- Invalid strings and cancellation
local inv1 = plugin.parseQualityInput("invalid_text")
assert_true(inv1 == nil, "Invalid non-numeric text should be rejected")

local inv2 = plugin.parseQualityInput("")
assert_true(inv2 == nil, "Empty text should be rejected")

local invCancel = plugin.parseQualityInput("CANCEL")
assert_true(invCancel == nil, "CANCEL should return nil")

-- 8f. Test applyQualitySettings and configureQuality persistence
local testCfgPath = tempDir .. sep .. "test_dialog_config_" .. tostring(os.time()) .. ".ini"
plugin.customConfigPath = testCfgPath

local confOk, confMsg = plugin.configureQuality("MODE=width;VALUE=2880")
assert_true(confOk, "configureQuality with custom width should succeed: " .. tostring(confMsg))
assert_eq(plugin.config.mode, "width", "Active mode should be width")
assert_eq(plugin.config.width, 2880, "Active width should be 2880")

local reloaded = plugin.loadConfig(testCfgPath)
assert_eq(reloaded.mode, "width", "Config on disk should persist mode=width")
assert_eq(reloaded.width, 2880, "Config on disk should persist width=2880")

-- Configure with custom DPI
local confOk2 = plugin.configureQuality("450 dpi")
assert_true(confOk2, "configureQuality with 450 dpi should succeed")
assert_eq(plugin.config.mode, "dpi", "Active mode should be dpi")
assert_eq(plugin.config.dpi, 450, "Active dpi should be 450")

local reloaded2 = plugin.loadConfig(testCfgPath)
assert_eq(reloaded2.mode, "dpi", "Config on disk should persist mode=dpi")
assert_eq(reloaded2.dpi, 450, "Config on disk should persist dpi=450")

-- Cancel action leaves config intact
local confCancel = plugin.configureQuality("CANCEL")
assert_true(not confCancel, "CANCEL should return false")
assert_eq(plugin.config.dpi, 450, "Config dpi should remain unchanged after cancel")

-- Cleanup test config file
os.remove(testCfgPath)
plugin.customConfigPath = nil

-- 8g. Test OS Dialog command formation
local winDlgCmd = plugin.getWindowsDialogCommand()
assert_true(winDlgCmd:find("powershell%.exe"), "Windows dialog command must invoke powershell")
assert_true(winDlgCmd:find("%-WindowStyle Hidden"), "Windows dialog command must use WindowStyle Hidden to avoid console window flash")
assert_true(winDlgCmd:find("System%.Windows%.Forms"), "Windows dialog command must load System.Windows.Forms")
assert_true(winDlgCmd:find("Copy Quality Settings"), "Windows dialog command must set title")
assert_true(winDlgCmd:find("RadioButton"), "Windows dialog command must include RadioButtons")
assert_true(winDlgCmd:find("TextBox"), "Windows dialog command must include TextBox")
assert_true(winDlgCmd:find("%$f%.Dispose%(%)"), "Windows dialog command must dispose Form on exit")

local linuxDlgCmd = plugin.getLinuxDialogCommand()
assert_true(linuxDlgCmd:find("zenity") ~= nil, "Linux dialog command must check zenity")
assert_true(linuxDlgCmd:find("kdialog") ~= nil, "Linux dialog command must check kdialog")

local macDlgCmd = plugin.getMacDialogCommand()
assert_true(macDlgCmd:find("osascript") ~= nil, "macOS dialog command must invoke osascript")
assert_true(macDlgCmd:find("display dialog") ~= nil, "macOS dialog command must use display dialog")

local osDlgCmd = plugin.getDialogCommand()
assert_true(osDlgCmd ~= nil and #osDlgCmd > 0, "getDialogCommand must return non-empty command")

print("  PASSED: Quality Settings dialog, input parsing, boundaries, and persistence verified.")

print("\n======================================================================")
print(string.format("All tests completed: %d assertions passed, %d failed.", testsPassed, testsFailed))
print("======================================================================")

if testsFailed > 0 then
    os.exit(1)
else
    os.exit(0)
end
