import json
import subprocess
from pathlib import Path

release = {
    "assets": [
        {"name": "ddns-darwin_amd64", "browser_download_url": "https://example.invalid/darwin"},
        {"name": "ddns-musl-linux_amd64", "browser_download_url": "https://example.invalid/musl"},
        {"name": "ddns-glibc-linux_amd64", "browser_download_url": "https://example.invalid/glibc"},
    ]
}
path = Path(".tmp-release.json")
path.write_text(json.dumps(release), encoding="utf-8")
script = Path("ddns-manager.sh").read_text(encoding="utf-8")
start = script.index("find_asset_url()")
end = script.index("\n}\n\nextract_binary()", start) + 3
func = script[start:end]
cmd = func + "\nfind_asset_url amd64 .tmp-release.json\n"
result = subprocess.run(["bash", "-c", cmd], text=True, capture_output=True)
if result.returncode != 0:
    raise AssertionError(result.stderr or result.stdout)
if result.stdout.strip() != "https://example.invalid/glibc":
    raise AssertionError(result.stdout)
print("release-asset-match-ok")
