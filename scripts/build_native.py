#!/usr/bin/env python3
"""Build the lip-sync extension against the pinned Godot 4.5 bindings."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GODOT_CPP = 'e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot-cpp', type=Path, required=True)
    parser.add_argument('--jobs', type=int, default=6)
    parser.add_argument('--platform', choices=['linux-x86_64', 'windows-x86_64'], default='linux-x86_64')
    parser.add_argument('--toolchain', type=Path)
    parser.add_argument('--json-include', type=Path, help='Directory containing nlohmann/json.hpp for cross builds')
    parser.add_argument('--build', type=Path)
    args = parser.parse_args()
    bindings = args.godot_cpp.resolve()
    commit = subprocess.check_output(['git', '-C', str(bindings), 'rev-parse', 'HEAD'], text=True).strip()
    if commit != GODOT_CPP:
        raise RuntimeError('Expected godot-cpp revision ' + GODOT_CPP)
    build = (args.build or ROOT/('build/native-windows' if args.platform == 'windows-x86_64' else 'build/native')).resolve()
    options = []
    if args.toolchain: options.append('-DCMAKE_TOOLCHAIN_FILE='+str(args.toolchain.resolve()))
    if args.json_include: options.append('-DTALKING_AVATAR_JSON_INCLUDE='+str(args.json_include.resolve()))
    subprocess.run(['cmake', '-S', str(ROOT/'native/talking_avatar'), '-B', str(build), '-G', 'Ninja',
                    '-DCMAKE_BUILD_TYPE=Release', '-DGODOT_CPP='+str(bindings), *options], check=True)
    subprocess.run(['cmake', '--build', str(build), '--target', 'talking_avatar', '-j', str(args.jobs)], check=True)
    print(build/('bin/libtalking_avatar.dll' if args.platform == 'windows-x86_64' else 'bin/libtalking_avatar.so'))


if __name__ == '__main__':
    main()
