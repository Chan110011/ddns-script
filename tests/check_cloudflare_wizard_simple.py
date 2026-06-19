from pathlib import Path

for script_name in ["ddns-manager.sh", "install.sh"]:
    text = Path(script_name).read_text(encoding="utf-8")
    forbidden = [
        "Enable IPv6",
        "???? IPv6",
        "Enter IPv6",
        "??? IPv6",
        "proxied?",
        "?? proxied",
    ]
    present = [item for item in forbidden if item in text]
    if present:
        raise AssertionError(f"{script_name} still prompts optional IPv6/proxy fields: {present!r}")
    required = [
        'ipv6_raw=""',
        'proxied="false"',
        'write_cloudflare_config "$token" "$ipv4_raw" "$ipv6_raw" "$ttl" "$proxied"',
    ]
    missing = [item for item in required if item not in text]
    if missing:
        raise AssertionError(f"{script_name} missing fixed IPv6/proxy defaults: {missing!r}")
print("cloudflare-wizard-simple-ok")
