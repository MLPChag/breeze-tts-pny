#!/usr/bin/env python3
"""Package a verified native LoRA runtime with source patch and license notices."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
from export_voice_pack import write_bundle

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--platform', choices=['linux-x86_64', 'windows-x86_64'], default='linux-x86_64')
    args = parser.parse_args()
    inventory = json.loads(args.receipt.read_text())
    files = {}
    for item in inventory:
        if not item['path'].startswith('runtime/'): continue
        name = Path(item['path']).name
        raw = (args.runtime / name).read_bytes()
        if hashlib.sha256(raw).hexdigest() != item['sha256']: raise ValueError('Runtime checksum mismatch: ' + name)
        files['runtime/' + name] = raw
    entrypoint = 'runtime/breeze-server.exe' if args.platform == 'windows-x86_64' else 'runtime/breeze-server'
    if entrypoint not in files: raise ValueError('Runtime receipt lacks the executable')
    sources = ['build.py', 'breeze-native-lora.patch', 'breeze-windows.patch', 'breeze-portable-build.patch']
    sources += [path.name for path in (ROOT / 'native/breeze').glob('LICENSE*')]
    for name in sorted(sources):
        files['source/' + name] = (ROOT / 'native/breeze' / name).read_bytes()
    files['source/windows-llvm-mingw.cmake'] = (ROOT / 'native/windows-llvm-mingw.cmake').read_bytes()
    manifest = {'schema': 1, 'id': 'breeze-0.1.6-native-lora-v1'+('-windows' if args.platform == 'windows-x86_64' else ''), 'platform': args.platform,
                'adapter_selection': True, 'entrypoint': entrypoint,
                'upstream': 'https://github.com/HoppouAI/Breeze-TTS-2.cpp',
                'revision': '87b43667ca5597f826441991e416a279ed7373b9',
                'files': {name: hashlib.sha256(raw).hexdigest() for name, raw in files.items()}}
    files['runtime.json'] = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
    write_bundle(args.output, files)
    print(args.output)


if __name__ == '__main__': main()
