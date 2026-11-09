#!/usr/bin/env python3
"""Scan release contents for private setup data and nonportable ELF search paths."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import struct
import sys
import tarfile
import zipfile

PATTERNS = {
    'personal-source-path': re.compile(rb'/(?:home|Users)/[^/\s\x00]+/|[A-Za-z]:[\\/](?:Users|home)[\\/][^\\/\s\x00]+[\\/]', re.I),
    'temporary-build-path': re.compile(rb'/(?:tmp|var/tmp)/[^/\s\x00]+/'),
    'private-network-address': re.compile(rb'\b(?:192\.168|10\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b'),
    'private-key': re.compile(rb'-----BEGIN (?:OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----'),
    'credential-pattern': re.compile(rb'\b(?:sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{30,}|hf_[A-Za-z0-9]{30,}|AKIA[A-Z0-9]{16})\b'),
}
# Prebuilt LLVM runtimes retain their public upstream CI assertion locations.
# This exception does not apply to credentials, endpoints or project paths.
PUBLIC_COMPILER_CI = b'/home/runner/work/llvm-mingw/llvm-mingw'
# Known reference/build-path constants from the SHA-verified official embedded runtime.
PUBLIC_RUNTIME_REFERENCES = {'d8a06cc6ca3348925ea29e343e1c5c5895fe0bb433ff913e1cee44caf358aa6a': 'CPython 3.14.10 python314.dll', '9f734a894f7eee8b620afc649e2a93a0b8531be7c6b5fc00ff28e5377769d57a': 'CPython 3.14.10 ipaddress.pyc'}


def elf_search_paths(raw):
    """Read DT_RPATH/DT_RUNPATH from little-endian ELF64 without loading code."""
    if raw[:6] != b'\x7fELF\x02\x01': return []
    offset = struct.unpack_from('<Q', raw, 32)[0]
    size, count = struct.unpack_from('<HH', raw, 54)
    segments = [struct.unpack_from('<IIQQQQQQ', raw, offset + i * size) for i in range(count)]
    dynamic = next((item for item in segments if item[0] == 2), None)
    if dynamic is None: return []
    table, paths = None, []
    for at in range(dynamic[2], dynamic[2] + dynamic[5], 16):
        tag, value = struct.unpack_from('<qQ', raw, at)
        if tag == 0: break
        if tag == 5: table = value
        if tag in (15, 29): paths.append(value)
    if table is None: return []
    load = next(item for item in segments if item[0] == 1 and item[3] <= table < item[3] + item[5])
    base = load[2] + table - load[3]
    return [raw[base + item:].split(b'\0', 1)[0].decode('utf-8', errors='replace') for item in paths]


class Audit:
    def __init__(self, forbidden=(), max_bytes=2 * 1024**3):
        self.forbidden = [item.encode() for item in forbidden]
        self.max_bytes = max_bytes
        self.bytes = self.entries = 0
        self.findings = []
        self.public_compiler_paths = 0
        self.public_runtime_references = []

    def check(self, name, raw, depth=0):
        self.bytes += len(raw); self.entries += 1
        if self.bytes > self.max_bytes: raise ValueError('Audit expansion limit exceeded')
        known_runtime = PUBLIC_RUNTIME_REFERENCES.get(hashlib.sha256(raw).hexdigest())
        for kind, pattern in PATTERNS.items():
            count = 0
            for match in pattern.finditer(raw):
                if kind == 'personal-source-path' and raw.startswith(PUBLIC_COMPILER_CI, match.start()):
                    end = match.start() + len(PUBLIC_COMPILER_CI)
                    if raw[end:end+1] in (b'/', b'\0'):
                        self.public_compiler_paths += 1
                        continue
                count += 1
            if count:
                item = {'file': name, 'kind': kind, 'count': count}
                if known_runtime and kind in ('personal-source-path', 'temporary-build-path', 'private-network-address'):
                    self.public_runtime_references.append({**item, 'provenance': known_runtime})
                else:
                    self.findings.append(item)
        for item in self.forbidden:
            if item in raw: self.findings.append({'file': name, 'kind': 'forbidden-string', 'count': raw.count(item)})
        for path in elf_search_paths(raw):
            if any(item != '$ORIGIN' and not item.startswith('$ORIGIN/') for item in path.split(':')):
                self.findings.append({'file': name, 'kind': 'nonportable-elf-search-path', 'count': 1})
        if depth >= 4: return
        if raw[:2] == b'\x1f\x8b':
            with tarfile.open(fileobj=io.BytesIO(raw), mode='r:gz') as bundle:
                for item in bundle:
                    if item.isfile():
                        if item.size > self.max_bytes - self.bytes: raise ValueError('Audit member exceeds expansion limit')
                        self.check(name + '!' + item.name, bundle.extractfile(item).read(), depth + 1)
        elif raw[:4] == b'PK\x03\x04':
            with zipfile.ZipFile(io.BytesIO(raw)) as bundle:
                for item in bundle.infolist():
                    if not item.is_dir():
                        if item.file_size > self.max_bytes - self.bytes: raise ValueError('Audit member exceeds expansion limit')
                        self.check(name + '!' + item.filename, bundle.read(item), depth + 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifacts', nargs='+', type=Path)
    parser.add_argument('--forbid', action='append', default=[], help='Additional private string to reject; values are not echoed')
    parser.add_argument('--report', type=Path)
    parser.add_argument('--max-mib', type=int, default=2048, help='Maximum total expanded bytes in MiB')
    args = parser.parse_args()
    if args.max_mib <= 0: parser.error('--max-mib must be positive')
    audit = Audit(args.forbid, max_bytes=args.max_mib * 1024**2)
    inputs = []
    for path in args.artifacts:
        if path.stat().st_size > audit.max_bytes: raise ValueError('Input exceeds audit limit')
        raw = path.read_bytes()
        inputs.append({'file': path.name, 'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw)})
        audit.check(path.name, raw)
    result = {'artifacts': inputs, 'entries': audit.entries, 'expanded_bytes': audit.bytes,
              'public_upstream_compiler_ci_paths': audit.public_compiler_paths,
              'public_upstream_runtime_references': audit.public_runtime_references,
              'findings': audit.findings,
              'scope': 'Heuristic byte scan of artifacts/nested archives and ELF64 library search paths; no code is executed or extracted.'}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'entries': audit.entries, 'findings': len(audit.findings)}))
    for item in audit.findings: print(json.dumps(item))
    return 1 if audit.findings else 0


if __name__ == '__main__':
    try: sys.exit(main())
    except (OSError, ValueError, tarfile.TarError, zipfile.BadZipFile, struct.error, StopIteration) as error:
        print('Release audit failed: ' + type(error).__name__, file=sys.stderr)
        sys.exit(2)
