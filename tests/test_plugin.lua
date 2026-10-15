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

-- Cleanup test config files
os.remove(testConfigPath)
os.remove(invalidConfigPath)
print("  PASSED: Configuration persistence correctly reads, writes, and validates settings.")

--------------------------------------------------------------------------------
-- 3. Quality Mode Actions and Cycling
--------------------------------------------------------------------------------
print("\n[Test 3] Verifying quality presets and cycling...")
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
print("  PASSED: Mode toggling and preset cycling function correctly.")

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
assert_true(winCmd:find("Clipboard%]:%:SetImage"), "Windows command must call SetImage")
assert_true(winCmd:find("Dispose%(%)"), "Windows command must dispose image to release file lock")
assert_true(not winCmd:find("\\"), "Windows command should normalize backslashes to forward slashes")

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
print("  PASSED: Cross-platform clipboard commands correctly formed for Windows, Linux, and macOS.")

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

assert_true(#registeredMenus >= 6, "At least 6 UI menu actions should be registered")
local hasPrimaryMenu = false
local hasCtrlAltC = false

for _, menu in ipairs(registeredMenus) do
    if menu:find("Copy Current Page") then
        hasPrimaryMenu = true
    end
end

for _, acc in ipairs(registeredAccelerators) do
    if acc == "<Control><Alt>c" then
        hasCtrlAltC = true
    end
end

assert_true(hasPrimaryMenu, "Primary 'Copy Current Page to Clipboard' menu must be registered")
assert_true(hasCtrlAltC, "<Control><Alt>c accelerator shortcut must be bound")

-- Verify active page index resolution
local resolvedPage, docStruct = plugin.getActivePageIndex()
assert_eq(resolvedPage, 2, "Active page index should match mock document currentPage (2)")
print("  PASSED: UI registration and accelerator shortcut successfully verified.")

--------------------------------------------------------------------------------
-- 7. Live Windows Clipboard Execution & Cleanup (if running on Windows)
--------------------------------------------------------------------------------
if detected == "windows" then
    print("\n[Test 7] Executing live Windows clipboard integration test...")
    local testPngPath = tempDir .. sep .. "live_clip_test_" .. tostring(os.time()) .. ".png"
    -- 1x1 valid PNG image bytes
    local pngBytes = "\137\80\78\71\13\10\26\10\0\0\0\13\73\72\68\82\0\0\0\1\0\0\0\1\8\6\0\0\0\31\21\196\137\0\0\0\11\73\68\65\84\120\156\99\96\0\0\0\2\0\1\244\113\100\166\0\0\0\0\73\69\78\68\174\66\96\130"
    local fp = io.open(testPngPath, "wb")
    fp:write(pngBytes)
    fp:close()

    assert_true(plugin.fileExists(testPngPath), "Live test PNG file should be created")

    local copyOk, copyErr = plugin.copyImageToClipboard(testPngPath, { testPngPath })
    assert_true(copyOk, "copyImageToClipboard should execute successfully: " .. tostring(copyErr))
    assert_true(not plugin.fileExists(testPngPath), "Live test PNG file should be safely deleted after transfer")
    print("  PASSED: Live Windows PowerShell/.NET clipboard copy and cleanup succeeded.")
end

print("\n======================================================================")
print(string.format("All tests completed: %d assertions passed, %d failed.", testsPassed, testsFailed))
print("======================================================================")

if testsFailed > 0 then
    os.exit(1)
else
    os.exit(0)
end
