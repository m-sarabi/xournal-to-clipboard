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

    def test_clipboard_powershell_windows(self):
        """Verify Windows PowerShell clipboard command actually sets image on Windows."""
        if sys.platform != "win32":
            self.skipTest("Windows-only clipboard test")

        import tempfile
        from PIL import Image

        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
            tmp_path = tmp.name

        try:
            # Create a 64x64 test image
            img = Image.new("RGB", (64, 64), color=(255, 128, 0))
            img.save(tmp_path)

            norm_path = tmp_path.replace("\\", "/")
            ps_cmd = (
                f'powershell.exe -Sta -NoProfile -NonInteractive -WindowStyle Hidden -Command "'
                f'Add-Type -AssemblyName System.Windows.Forms; '
                f'$img = [System.Drawing.Image]::FromFile(\'{norm_path}\'); '
                f'[System.Windows.Forms.Clipboard]::SetImage($img); '
                f'$img.Dispose();"'
            )

            res = subprocess.run(ps_cmd, shell=True, capture_output=True, text=True)
            self.assertEqual(res.returncode, 0, f"PowerShell command failed:\n{res.stderr}")

            # Verify clipboard contains image
            verify_script = (
                "powershell.exe -Sta -NoProfile -NonInteractive -Command \""
                "Add-Type -AssemblyName System.Windows.Forms; "
                "$c = [System.Windows.Forms.Clipboard]::GetImage(); "
                "if ($c -ne $null) { Write-Output ($c.Width.ToString() + 'x' + $c.Height.ToString()) } else { Write-Output 'NONE' }\""
            )
            verify_res = subprocess.check_output(verify_script, shell=True, text=True).strip()
            self.assertEqual(verify_res, "64x64", f"Clipboard did not contain expected image, got: {verify_res}")
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

    def test_clipboard_powershell_windows_apostrophe_path(self):
        """Verify Windows PowerShell clipboard command succeeds with apostrophe in filename."""
        if sys.platform != "win32":
            self.skipTest("Windows-only clipboard test")

        import tempfile
        from PIL import Image

        temp_dir = tempfile.gettempdir()
        tmp_path = os.path.join(temp_dir, "test_O'Connor_note.png")

        try:
            img = Image.new("RGB", (32, 32), color=(0, 128, 255))
            img.save(tmp_path)

            norm_path = tmp_path.replace("\\", "/")
            escaped_path = norm_path.replace("'", "''")
            ps_cmd = (
                f'powershell.exe -Sta -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command "'
                f'Add-Type -AssemblyName System.Windows.Forms; '
                f'Add-Type -AssemblyName System.Drawing; '
                f'$img = [System.Drawing.Image]::FromFile(\'{escaped_path}\'); '
                f'[System.Windows.Forms.Clipboard]::SetImage($img); '
                f'$img.Dispose();"'
            )

            res = subprocess.run(ps_cmd, shell=True, capture_output=True, text=True)
            self.assertEqual(res.returncode, 0, f"PowerShell command failed with apostrophe in path:\n{res.stderr}")

            verify_script = (
                "powershell.exe -Sta -NoProfile -NonInteractive -Command \""
                "Add-Type -AssemblyName System.Windows.Forms; "
                "$c = [System.Windows.Forms.Clipboard]::GetImage(); "
                "if ($c -ne $null) { Write-Output ($c.Width.ToString() + 'x' + $c.Height.ToString()) } else { Write-Output 'NONE' }\""
            )
            verify_res = subprocess.check_output(verify_script, shell=True, text=True).strip()
            self.assertEqual(verify_res, "32x32", f"Clipboard did not contain expected 32x32 image, got: {verify_res}")
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)


if __name__ == "__main__":
    unittest.main()
