"""Renders the UI mockups in docs/mockups to 1920 x 1080 PNGs with a local Chrome or Edge in headless mode.

    python tools/render_mockups.py

The PNGs are not kept in git (they are large and come straight from the HTML); run this to make them again.
The browser runs with a throwaway profile in the system temp folder, never your own.
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOCKUPS = ROOT / "docs" / "mockups"
BROWSERS = [
    pathlib.Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe"),
    pathlib.Path(r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"),
    pathlib.Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
    pathlib.Path(r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"),
]
# page, look, picture
RENDERS = [
    ("dispatch_card.html", "a", "dispatch_card_A.png"),
    ("dispatch_card.html", "b", "dispatch_card_B.png"),
    ("dispatch_card.html", "c", "dispatch_card_C.png"),
    ("tip_card.html", "b", "tip_card_B.png"),
    ("tip_banner.html", "b", "tip_banner_B.png"),
    ("call_hud.html", "a", "call_hud_A.png"),
    ("call_hud.html", "b", "call_hud_B.png"),
    ("call_hud.html", "c", "call_hud_C.png"),
    ("menu_page.html", "b", "menu_page_B.png"),
    ("welcome_dialog.html", "b", "welcome_dialog_B.png"),
]


def main():
    browser = next((b for b in BROWSERS if b.exists()), None)
    if browser is None:
        sys.exit("No Chrome or Edge found")
    with tempfile.TemporaryDirectory() as profile:
        for page, look, picture in RENDERS:
            url = (MOCKUPS / page).as_uri() + "?look=%s&png" % look
            result = subprocess.run([str(browser), "--headless=new", "--disable-gpu", "--hide-scrollbars", "--user-data-dir=" + profile,
                                     "--virtual-time-budget=4000", "--window-size=1920,1080", "--screenshot=" + str(MOCKUPS / picture), url],
                                    capture_output=True, text=True, timeout=90)
            print(picture, "ok" if result.returncode == 0 and (MOCKUPS / picture).exists() else "FAILED")


if __name__ == "__main__":
    main()
