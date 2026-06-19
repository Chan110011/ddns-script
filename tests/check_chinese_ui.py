from pathlib import Path

required = [
    'NewFuture/DDNS Cloudflare ' + ''.join(map(chr, [0x7ba1, 0x7406, 0x811a, 0x672c])),
    ''.join(map(chr, [0x5b89, 0x88c5])) + '/' + ''.join(map(chr, [0x66f4, 0x65b0])) + ' DDNS',
    ''.join(map(chr, [0x914d, 0x7f6e])) + ' Cloudflare',
    ''.join(map(chr, [0x67e5, 0x770b, 0x5f53, 0x524d, 0x914d, 0x7f6e])),
    ''.join(map(chr, [0x5378, 0x8f7d])) + ' DDNS',
    ''.join(map(chr, [0x8bf7, 0x9009, 0x62e9])),
]

for script_name in ['ddns-manager.sh', 'install.sh']:
    text = Path(script_name).read_text(encoding='utf-8')
    if '??' in text:
        raise AssertionError(f'{script_name} contains mojibake question marks')
    missing = [item for item in required if item not in text]
    if missing:
        raise AssertionError(f'{script_name} missing Chinese UI text: {missing!r}')
print('chinese-ui-ok')
