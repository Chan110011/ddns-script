import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
assert data["dns"] == "cloudflare"
assert data["token"]
assert isinstance(data["ipv4"], list)
assert isinstance(data["ipv6"], list)
assert data["ipv4"] or data["ipv6"]
assert isinstance(data["ttl"], int)
assert isinstance(data["proxy"], bool)
assert data["index4"] == "public"
assert data["index6"] == "public"
print("valid")
