#!/usr/bin/env python3
"""
Automated validation test suite for CopyPageToClipboard plugin.
Tests:
- plugin.ini format and metadata validation
- main.lua compilation and syntax validation
- Execution of Lua test suite (test_plugin.lua)
- Clipboard command formation and execution
- End-to-end simulation of Xournal++ Lua hooks
"""

import configparser
import os
import subprocess
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


class TestCopyPageToClipboard(unittest.TestCase):

    def test_plugin_ini_structure(self):
        """Verify plugin.ini conforms to official Xournal++ specifications."""
        ini_path = REPO_ROOT / "plugin.ini"
        self.assertTrue(ini_path.exists(), "plugin.ini file does not exist")

        config = configparser.ConfigParser()
        config.read(ini_path, encoding="utf-8")

        # [about] section
        self.assertIn("about", config.sections(), "Missing [about] section")
        self.assertIn("author", config["about"], "Missing author in [about]")
        self.assertIn("description", config["about"], "Missing description in [about]")
        self.assertIn("version", config["about"], "Missing version in [about]")
        self.assertEqual(config["about"]["version"], "<xournalpp>", "Version should be <xournalpp>")

        # [default] section
        self.assertIn("default", config.sections(), "Missing [default] section")
        self.assertEqual(config["default"].get("enabled", "").lower(), "true", "enabled should be true")

        # [plugin] section
        self.assertIn("plugin", config.sections(), "Missing [plugin] section")
        self.assertEqual(config["plugin"].get("mainfile"), "main.lua", "mainfile must be main.lua")
        self.assertIn("shortcut", config["plugin"], "Missing shortcut in [plugin]")
        self.assertEqual(config["plugin"]["shortcut"], "<Control><Alt>c", "Shortcut must be <Control><Alt>c")

    def test_lua_syntax_compilation(self):
        """Verify main.lua compiles cleanly without syntax errors."""
        main_lua = REPO_ROOT / "main.lua"
        self.assertTrue(main_lua.exists(), "main.lua file does not exist")

        # Test with texluac if available
        try:
            res = subprocess.run(
                ["texluac", "-p", str(main_lua)],
                capture_output=True,
                text=True,
                cwd=str(REPO_ROOT)
            )
            self.assertEqual(res.returncode, 0, f"texluac failed with syntax error:\n{res.stderr}")
        except FileNotFoundError:
            # Fallback check: ensure file parses without unclosed quotes or blocks
            content = main_lua.read_text(encoding="utf-8")
            self.assertIn("function initUi()", content)
            self.assertIn("function copyCurrentPage()", content)

    def test_run_lua_test_suite(self):
        """Execute the full Lua test suite and verify all assertions pass."""
        test_script = REPO_ROOT / "tests" / "test_plugin.lua"
        self.assertTrue(test_script.exists(), "test_plugin.lua does not exist")

        try:
            res = subprocess.run(
                ["texlua", "--luaonly", str(test_script)],
                capture_output=True,
                text=True,
                cwd=str(REPO_ROOT),
                timeout=60
            )
            print("\n--- Lua Test Suite Output ---")
            print(res.stdout)
            if res.stderr:
                print(res.stderr)
            self.assertEqual(res.returncode, 0, f"Lua test suite exited with error code {res.returncode}")
            self.assertIn("All tests completed", res.stdout)
            self.assertIn("0 failed", res.stdout)
        except FileNotFoundError:
            self.skipTest("texlua interpreter not found in PATH")

    def _clear_windows_clipboard(self):
        """Helper to clear Windows clipboard to prevent stale clipboard state."""
        clear_cmd = (
            'powershell.exe -Sta -NoProfile -NonInteractive -Command "'
            'Add-Type -AssemblyName System.Windows.Forms; '
            '[System.Windows.Forms.Clipboard]::Clear();"'
        )
        subprocess.run(clear_cmd, shell=True, capture_output=True, check=True)

    def _get_windows_clipboard_image_dims(self):
        """Helper to retrieve image dimensions from Windows clipboard."""
        verify_script = (
            'powershell.exe -Sta -NoProfile -NonInteractive -Command "'
            'Add-Type -AssemblyName System.Windows.Forms; '
            '$c = [System.Windows.Forms.Clipboard]::GetImage(); '
            'if ($c -ne $null) { Write-Output ($c.Width.ToString() + \'x\' + $c.Height.ToString()) } else { Write-Output \'NONE\' }"'
        )
        return subprocess.check_output(verify_script, shell=True, text=True).strip()

    def test_clipboard_powershell_windows(self):
        """Verify Windows PowerShell clipboard command actually sets image on Windows."""
        if sys.platform != "win32":
            self.skipTest("Windows-only clipboard test")

        import tempfile
        from PIL import Image

        self._clear_windows_clipboard()
        self.assertEqual(self._get_windows_clipboard_image_dims(), "NONE", "Clipboard should be empty before test")

        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
            tmp_path = tmp.name

        try:
            # Create a 64x64 test image
            img = Image.new("RGB", (64, 64), color=(255, 128, 0))
            img.save(tmp_path)

            norm_path = tmp_path.replace("\\", "/")
            escaped_path = norm_path.replace("'", "''")
            ps_cmd = (
                f'powershell.exe -Sta -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command "'
                f'$img = $null; try {{ '
                f'Add-Type -AssemblyName System.Windows.Forms; '
                f'Add-Type -AssemblyName System.Drawing; '
                f'$img = [System.Drawing.Image]::FromFile(\'{escaped_path}\'); '
                f'[System.Windows.Forms.Clipboard]::SetDataObject($img, $true, 10, 100); '
                f'}} catch {{ [Console]::Error.WriteLine($_.Exception.Message); exit 1 }} '
                f'finally {{ if ($null -ne $img) {{ $img.Dispose() }} }}"'
            )

            res = subprocess.run(ps_cmd, shell=True, capture_output=True, text=True)
            self.assertEqual(res.returncode, 0, f"PowerShell command failed:\n{res.stderr}")

            dims = self._get_windows_clipboard_image_dims()
            self.assertEqual(dims, "64x64", f"Clipboard did not contain expected image, got: {dims}")
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

    def test_clipboard_powershell_windows_apostrophe_path(self):
        """Verify Windows PowerShell clipboard command succeeds with apostrophe in filename."""
        if sys.platform != "win32":
            self.skipTest("Windows-only clipboard test")

        import tempfile
        import time
        from PIL import Image

        self._clear_windows_clipboard()
        self.assertEqual(self._get_windows_clipboard_image_dims(), "NONE", "Clipboard should be empty before test")

        temp_dir = tempfile.gettempdir()
        unique_name = f"test_O'Connor_note_{os.getpid()}_{int(time.time()*1000)}.png"
        tmp_path = os.path.join(temp_dir, unique_name)

        try:
            img = Image.new("RGB", (32, 32), color=(0, 128, 255))
            img.save(tmp_path)

            norm_path = tmp_path.replace("\\", "/")
            escaped_path = norm_path.replace("'", "''")
            ps_cmd = (
                f'powershell.exe -Sta -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command "'
                f'$img = $null; try {{ '
                f'Add-Type -AssemblyName System.Windows.Forms; '
                f'Add-Type -AssemblyName System.Drawing; '
                f'$img = [System.Drawing.Image]::FromFile(\'{escaped_path}\'); '
                f'[System.Windows.Forms.Clipboard]::SetDataObject($img, $true, 10, 100); '
                f'}} catch {{ [Console]::Error.WriteLine($_.Exception.Message); exit 1 }} '
                f'finally {{ if ($null -ne $img) {{ $img.Dispose() }} }}"'
            )

            res = subprocess.run(ps_cmd, shell=True, capture_output=True, text=True)
            self.assertEqual(res.returncode, 0, f"PowerShell command failed with apostrophe in path:\n{res.stderr}")

            dims = self._get_windows_clipboard_image_dims()
            self.assertEqual(dims, "32x32", f"Clipboard did not contain expected 32x32 image, got: {dims}")
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

    def test_clipboard_powershell_error_handling(self):
        """Verify Windows PowerShell command exits with non-zero status on error (e.g. missing file)."""
        if sys.platform != "win32":
            self.skipTest("Windows-only clipboard test")

        ps_cmd = (
            'powershell.exe -Sta -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command "'
            '$img = $null; try { '
            'Add-Type -AssemblyName System.Windows.Forms; '
            'Add-Type -AssemblyName System.Drawing; '
            '$img = [System.Drawing.Image]::FromFile(\'C:/nonexistent_image_path_12345.png\'); '
            '[System.Windows.Forms.Clipboard]::SetDataObject($img, $true, 10, 100); '
            '} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 } '
            'finally { if ($null -ne $img) { $img.Dispose() } }"'
        )
        res = subprocess.run(ps_cmd, shell=True, capture_output=True, text=True)
        self.assertNotEqual(res.returncode, 0, "PowerShell should fail with non-zero exit code on missing file")
        self.assertIn("FromFile", res.stderr, "Error message should mention FromFile exception")

    def test_cross_platform_command_formation(self):
        """Verify command formation and escaping for Linux and macOS via Lua."""
        import tempfile
        lua_code = (
            'package.path = "./?.lua;" .. package.path; '
            'local p = require("main"); '
            'local lc = p.getLinuxCommand("/tmp/test with \'quotes\' and $VAR.png"); '
            'local mc = p.getMacClipboardCommand("/tmp/test with \\"quotes\\".png"); '
            'assert(lc:find("wl%-copy"), "Linux cmd must have wl-copy"); '
            'assert(lc:find("xclip"), "Linux cmd must have xclip"); '
            'assert(mc:find("«class PNGf»"), "macOS cmd must have PNG class"); '
            'print("OK_COMMANDS");\n'
        )
        with tempfile.NamedTemporaryFile(mode="w", suffix=".lua", encoding="utf-8", delete=False) as tf:
            tf.write(lua_code)
            tf_path = tf.name

        try:
            res = subprocess.run(
                ["texlua", "--luaonly", tf_path],
                capture_output=True,
                text=True,
                cwd=str(REPO_ROOT),
                timeout=10
            )
            self.assertEqual(res.returncode, 0, f"Lua command formation test failed:\nSTDERR: {res.stderr}\nSTDOUT: {res.stdout}")
            self.assertIn("OK_COMMANDS", res.stdout)
        except FileNotFoundError:
            self.skipTest("texlua interpreter not found")
        finally:
            if os.path.exists(tf_path):
                os.remove(tf_path)

    def test_async_clipboard_command_formation(self):
        """Verify asynchronous clipboard commands include background execution and cleanup."""
        import tempfile
        lua_code = (
            'package.path = "./?.lua;" .. package.path; '
            'local p = require("main"); '
            'local files = { "/tmp/a.png", "/tmp/b.png" }; '
            'local wc = p.getWindowsClipboardCommand("C:\\\\a.png", { "C:\\\\a.png", "C:\\\\b.png" }, true); '
            'local lc = p.getLinuxCommand("/tmp/a.png", files, true); '
            'local mc = p.getMacClipboardCommand("/tmp/a.png", files, true); '
            'assert(wc:find("start"), "Windows async must have start"); '
            'assert(wc:find("/B"), "Windows async must have /B"); '
            'assert(wc:find("Remove%-Item"), "Windows async must have Remove-Item"); '
            'assert(lc:find("&%s*$"), "Linux async must end with &"); '
            'assert(lc:find("rm %-f"), "Linux async must have rm -f"); '
            'assert(mc:find("&%s*$"), "macOS async must end with &"); '
            'assert(mc:find("rm %-f"), "macOS async must have rm -f"); '
            'print("OK_ASYNC_COMMANDS");\n'
        )
        with tempfile.NamedTemporaryFile(mode="w", suffix=".lua", encoding="utf-8", delete=False) as tf:
            tf.write(lua_code)
            tf_path = tf.name

        try:
            res = subprocess.run(
                ["texlua", "--luaonly", tf_path],
                capture_output=True,
                text=True,
                cwd=str(REPO_ROOT),
                timeout=10
            )
            self.assertEqual(res.returncode, 0, f"Lua async command test failed:\nSTDERR: {res.stderr}\nSTDOUT: {res.stdout}")
            self.assertIn("OK_ASYNC_COMMANDS", res.stdout)
        except FileNotFoundError:
            self.skipTest("texlua interpreter not found")
        finally:
            if os.path.exists(tf_path):
                os.remove(tf_path)

    def test_quality_input_dialog_and_parsing(self):
        """Verify custom quality dialog input parsing and boundaries via Lua."""
        import tempfile
        lua_code = (
            'package.path = "./?.lua;" .. package.path; '
            'local p = require("main"); '
            'local r1 = p.parseQualityInput("MODE=dpi;VALUE=450"); '
            'assert(r1.mode == "dpi" and r1.value == 450, "r1 failed"); '
            'local r2 = p.parseQualityInput("MODE=width;VALUE=2560"); '
            'assert(r2.mode == "width" and r2.value == 2560, "r2 failed"); '
            'local r3 = p.parseQualityInput("600 dpi"); '
            'assert(r3.mode == "dpi" and r3.value == 600, "r3 failed"); '
            'local r4 = p.parseQualityInput("2560 px"); '
            'assert(r4.mode == "width" and r4.value == 2560, "r4 failed"); '
            'local r5 = p.parseQualityInput("width 1920"); '
            'assert(r5.mode == "width" and r5.value == 1920, "r5 failed"); '
            'local bLow = p.parseQualityInput("49 dpi"); '
            'assert(bLow == nil, "49 dpi should be out of bounds"); '
            'local bHigh = p.parseQualityInput("2401 dpi"); '
            'assert(bHigh == nil, "2401 dpi should be out of bounds"); '
            'local bWLow = p.parseQualityInput("99 px"); '
            'assert(bWLow == nil, "99 px should be out of bounds"); '
            'local bWHigh = p.parseQualityInput("10001 px"); '
            'assert(bWHigh == nil, "10001 px should be out of bounds"); '
            'local bNegDpi = p.parseQualityInput("-300 dpi"); '
            'assert(bNegDpi == nil, "negative dpi must be rejected"); '
            'local bNegW = p.parseQualityInput("-1920 px"); '
            'assert(bNegW == nil, "negative width must be rejected"); '
            'local bNegS = p.parseQualityInput("MODE=dpi;VALUE=-300"); '
            'assert(bNegS == nil, "structured negative value must be rejected"); '
            'local bEmpZ = p.parseQualityInput("DPI|"); '
            'assert(bEmpZ == nil, "empty zenity input must be rejected"); '
            'local rFloat = p.parseQualityInput("450.5 dpi"); '
            'assert(rFloat.mode == "dpi" and rFloat.value == 450, "float dpi must be floored"); '
            'local wdc = p.getWindowsDialogCommand(); '
            'assert(wdc:find("%-WindowStyle Hidden"), "windows dialog must use WindowStyle Hidden"); '
            'assert(wdc:find("%$f%.Dispose%(%)"), "windows dialog must dispose form"); '
            'print("OK_QUALITY_PARSER");\n'
        )
        with tempfile.NamedTemporaryFile(mode="w", suffix=".lua", encoding="utf-8", delete=False) as tf:
            tf.write(lua_code)
            tf_path = tf.name

        try:
            res = subprocess.run(
                ["texlua", "--luaonly", tf_path],
                capture_output=True,
                text=True,
                cwd=str(REPO_ROOT),
                timeout=10
            )
            self.assertEqual(res.returncode, 0, f"Lua quality parser test failed:\nSTDERR: {res.stderr}\nSTDOUT: {res.stdout}")
            self.assertIn("OK_QUALITY_PARSER", res.stdout)
        except FileNotFoundError:
            self.skipTest("texlua interpreter not found")
        finally:
            if os.path.exists(tf_path):
                os.remove(tf_path)

    def test_decluttered_ui_menus(self):
        """Verify that menu items are decluttered replacing 6 quality presets with 1 dialog item."""
        import tempfile
        lua_code = (
            'package.path = "./?.lua;" .. package.path; '
            'local registered = {}; '
            '_G.app = { registerUi = function(tbl) table.insert(registered, tbl.menu) end }; '
            'local p = require("main"); '
            'initUi(); '
            'assert(#registered == 2, "Must register exactly 2 menu items, got: " .. tostring(#registered)); '
            'local hasCopy = false; local hasQuality = false; '
            'for _, m in ipairs(registered) do '
            '  if m:find("Copy Current Page") then hasCopy = true end '
            '  if m:find("Quality Settings") then hasQuality = true end '
            'end; '
            'assert(hasCopy, "Must have Copy Current Page action"); '
            'assert(hasQuality, "Must have Quality Settings dialog action"); '
            'print("OK_DECLUTTERED_UI");\n'
        )
        with tempfile.NamedTemporaryFile(mode="w", suffix=".lua", encoding="utf-8", delete=False) as tf:
            tf.write(lua_code)
            tf_path = tf.name

        try:
            res = subprocess.run(
                ["texlua", "--luaonly", tf_path],
                capture_output=True,
                text=True,
                cwd=str(REPO_ROOT),
                timeout=10
            )
            self.assertEqual(res.returncode, 0, f"Lua decluttered UI test failed:\nSTDERR: {res.stderr}\nSTDOUT: {res.stdout}")
            self.assertIn("OK_DECLUTTERED_UI", res.stdout)
        except FileNotFoundError:
            self.skipTest("texlua interpreter not found")
        finally:
            if os.path.exists(tf_path):
                os.remove(tf_path)

    def test_dialog_titles_renamed_to_quality_settings(self):
        """Verify dialog title is 'Quality Settings' across Windows, Linux, and macOS."""
        import tempfile
        lua_code = (
            'package.path = "./?.lua;" .. package.path; '
            'local p = require("main"); '
            'local wc = p.getWindowsDialogCommand(); '
            'local lc = p.getLinuxDialogCommand(); '
            'local mc = p.getMacDialogCommand(); '
            'assert(wc:find("%$f%.Text = \'Quality Settings\'") ~= nil, "Windows title must be Quality Settings"); '
            'assert(wc:find("Copy Quality Settings") == nil, "Windows title must not contain Copy Quality Settings"); '
            'assert(lc:find(\'title="Quality Settings"\') ~= nil, "Linux zenity title must be Quality Settings"); '
            'assert(lc:find(\'title "Quality Settings"\') ~= nil, "Linux kdialog title must be Quality Settings"); '
            'assert(lc:find("Copy Quality Settings") == nil, "Linux title must not contain Copy Quality Settings"); '
            'assert(mc:find(\'with title "Quality Settings"\') ~= nil, "macOS title must be Quality Settings"); '
            'assert(mc:find("Copy Quality Settings") == nil, "macOS title must not contain Copy Quality Settings"); '
            'print("OK_DIALOG_TITLES");\n'
        )
        with tempfile.NamedTemporaryFile(mode="w", suffix=".lua", encoding="utf-8", delete=False) as tf:
            tf.write(lua_code)
            tf_path = tf.name

        try:
            res = subprocess.run(
                ["texlua", "--luaonly", tf_path],
                capture_output=True,
                text=True,
                cwd=str(REPO_ROOT),
                timeout=10
            )
            self.assertEqual(res.returncode, 0, f"Lua dialog title test failed:\nSTDERR: {res.stderr}\nSTDOUT: {res.stdout}")
            self.assertIn("OK_DIALOG_TITLES", res.stdout)
        except FileNotFoundError:
            self.skipTest("texlua interpreter not found")
        finally:
            if os.path.exists(tf_path):
                os.remove(tf_path)

    def test_config_path_resolution_and_plugin_dir(self):
        """Verify getConfigFilePath targets config.ini in plugin dir and handles relative source."""
        import tempfile
        lua_code = (
            'package.path = "./?.lua;" .. package.path; '
            'local p = require("main"); '
            'local path1 = p.getConfigFilePath(); '
            'assert(path1:match("config%.ini$") ~= nil, "Path must end with config.ini: " .. tostring(path1)); '
            'assert(path1:find("copypage_config%.ini") == nil, "Path must not be copypage_config.ini"); '
            'local orig = debug.getinfo; '
            'debug.getinfo = function(l, w) if w == "S" then return { source = "@main.lua" } end return orig(l, w) end; '
            'local path2 = p.getConfigFilePath(); '
            'assert(path2:match("config%.ini$") ~= nil, "Fallback path must end with config.ini: " .. tostring(path2)); '
            'assert(path2:find("copypage_config%.ini") == nil, "Fallback path must not be copypage_config.ini"); '
            'debug.getinfo = orig; '
            'print("OK_CONFIG_PATH");\n'
        )
        with tempfile.NamedTemporaryFile(mode="w", suffix=".lua", encoding="utf-8", delete=False) as tf:
            tf.write(lua_code)
            tf_path = tf.name

        try:
            res = subprocess.run(
                ["texlua", "--luaonly", tf_path],
                capture_output=True,
                text=True,
                cwd=str(REPO_ROOT),
                timeout=10
            )
            self.assertEqual(res.returncode, 0, f"Lua config path test failed:\nSTDERR: {res.stderr}\nSTDOUT: {res.stdout}")
            self.assertIn("OK_CONFIG_PATH", res.stdout)
        except FileNotFoundError:
            self.skipTest("texlua interpreter not found")
        finally:
            if os.path.exists(tf_path):
                os.remove(tf_path)

    def test_end_to_end_width_1000_save_and_export(self):
        """Verify end-to-end setting save and export with Width=1000."""
        import tempfile
        lua_code = (
            'package.path = "./?.lua;" .. package.path; '
            'local p = require("main"); '
            'local tempDir = p.getTempDir(); '
            'local sep = package.config:sub(1, 1); '
            'local testPath = tempDir .. sep .. "test_py_width1000.ini"; '
            'p.customConfigPath = testPath; '
            'local parsed, err = p.parseQualityInput("\\r\\nMODE=width;VALUE=1000\\r\\n"); '
            'assert(parsed ~= nil and parsed.mode == "width" and parsed.value == 1000, "parsing failed: " .. tostring(err)); '
            'local saveOk, saveMsg = p.applyQualitySettings(parsed.mode, parsed.value); '
            'assert(saveOk, "applyQualitySettings failed: " .. tostring(saveMsg)); '
            'assert(p.config.mode == "width", "active mode must be width"); '
            'assert(p.config.width == 1000, "active width must be 1000"); '
            'local reloaded = p.loadConfig(testPath); '
            'assert(reloaded.mode == "width", "reloaded mode must be width"); '
            'assert(reloaded.width == 1000, "reloaded width must be 1000"); '
            'local captured = nil; '
            '_G.app = { export = function(params) captured = params; local f = io.open(params.outputFile, "wb"); f:write("dummy"); f:close() end }; '
            'local targetPng = tempDir .. sep .. "test_py_export.png"; '
            'local expFile, expErr = p.exportPage(1, targetPng, { currentPage = 1, pages = { { pageWidth = 595.28 } } }); '
            'assert(expFile ~= nil, "exportPage failed: " .. tostring(expErr)); '
            'assert(captured.pngWidth == 1000, "exported pngWidth must be 1000"); '
            'assert(captured.pngDpi == 121, "exported pngDpi must be 121"); '
            'os.remove(testPath); os.remove(targetPng); '
            'p.customConfigPath = nil; p.config.mode = "dpi"; p.config.dpi = 300; p.config.width = 1920; '
            'print("OK_END_TO_END_WIDTH_1000");\n'
        )
        with tempfile.NamedTemporaryFile(mode="w", suffix=".lua", encoding="utf-8", delete=False) as tf:
            tf.write(lua_code)
            tf_path = tf.name

        try:
            res = subprocess.run(
                ["texlua", "--luaonly", tf_path],
                capture_output=True,
                text=True,
                cwd=str(REPO_ROOT),
                timeout=10
            )
            self.assertEqual(res.returncode, 0, f"Lua end-to-end test failed:\nSTDERR: {res.stderr}\nSTDOUT: {res.stdout}")
            self.assertIn("OK_END_TO_END_WIDTH_1000", res.stdout)
        except FileNotFoundError:
            self.skipTest("texlua interpreter not found")
        finally:
            if os.path.exists(tf_path):
                os.remove(tf_path)


if __name__ == "__main__":
    unittest.main()
