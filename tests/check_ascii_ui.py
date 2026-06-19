from pathlib import Path

SCRIPT = Path("ddns-manager.sh")
text = SCRIPT.read_text(encoding="utf-8")

non_ascii = sorted({ch for ch in text if ord(ch) > 127})
if non_ascii:
    raise AssertionError("Non-ASCII characters can render incorrectly on non-UTF-8 terminals: " + repr(non_ascii[:20]))

mojibake_lines = [
    f"{line_no}: {line}"
    for line_no, line in enumerate(text.splitlines(), 1)
    if "??" in line
]
if mojibake_lines:
    raise AssertionError("Mojibake placeholder text found:\n" + "\n".join(mojibake_lines[:30]))

print("ascii-ui-ok")

menu_requirements = [
    "NewFuture/DDNS Cloudflare Manager",
    "1. Install/Update DDNS",
    "2. Configure Cloudflare",
    "3. Show current config",
    "4. Modify config",
    "5. Start DDNS",
    "6. Stop DDNS",
    "7. Restart DDNS",
    "8. Show service status",
    "9. Show logs",
    "10. Uninstall DDNS",
    "0. Exit",
    "success \"DDNS stopped\"",
]
missing = [item for item in menu_requirements if item not in text]
if missing:
    raise AssertionError("Missing expected ASCII UI text: " + repr(missing))
