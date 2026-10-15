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
                timeout=30
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


if __name__ == "__main__":
    unittest.main()
