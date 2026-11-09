#!/usr/bin/env python3
"""Stage only portable headers and generate a Windows Vulkan import library."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--toolchain', type=Path, required=True)
    parser.add_argument('--include', type=Path, required=True, help='Vulkan and nlohmann include directory')
    parser.add_argument('--spirv-include', type=Path, required=True)
    parser.add_argument('--registry', type=Path, required=True, help='Matching Khronos vk.xml')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve(); include = output / 'include'
    include.mkdir(parents=True, exist_ok=True)
    for name in ('vulkan', 'vk_video', 'nlohmann'):
        shutil.copytree(args.include / name, include / name, dirs_exist_ok=True)
    shutil.copytree(args.spirv_include / 'spirv', include / 'spirv', dirs_exist_ok=True)
    if not (include / 'spirv/unified1/spirv.hpp').exists():
        raise ValueError('Use compatible SPIR-V headers, such as vulkan-sdk-1.4.341.0')
    commands = ET.parse(args.registry).findall('./commands/command/proto/name')
    definition = output / 'vulkan-1.def'
    definition.write_text('LIBRARY vulkan-1.dll\nEXPORTS\n' + ''.join('    '+item.text+'\n' for item in commands))
    tool = args.toolchain.resolve() / 'bin/x86_64-w64-mingw32-dlltool'
    subprocess.run([str(tool), '-d', str(definition), '-l', str(output / 'libvulkan-1.a')], check=True)
    inventory = {path.relative_to(output).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in sorted(output.rglob('*')) if path.is_file() and path.name != 'sdk-receipt.json'}
    (output / 'sdk-receipt.json').write_text(json.dumps(inventory, indent=2) + '\n')
    print(output)


if __name__ == '__main__': main()
