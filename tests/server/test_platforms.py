import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server'))
from breeze_pny.platforms import acquire_lock, platform_id, runtime_environment


class PlatformChecks(unittest.TestCase):
    def test_install_lock_excludes_other_process_and_releases_on_close(self):
        code = '''import sys
from breeze_pny.platforms import acquire_lock
with open(sys.argv[1], 'a+b') as lock:
    try: acquire_lock(lock)
    except BlockingIOError: sys.exit(23)
'''
        bootstrap = 'import sys;sys.path.insert(0,sys.argv.pop(1));' + code
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'service.lock'
            command = [sys.executable, '-c', bootstrap, str(ROOT / 'server'), str(path)]
            with path.open('a+b') as lock:
                acquire_lock(lock)
                self.assertEqual(subprocess.run(command, timeout=15).returncode, 23)
            self.assertEqual(subprocess.run(command, timeout=15).returncode, 0)

    def test_runtime_search_path_prepends_binary_directory(self):
        binary = Path(tempfile.gettempdir()) / 'runtime with spaces' / 'breeze-server'
        env = runtime_environment(binary)
        key = 'PATH' if os.name == 'nt' else 'LD_LIBRARY_PATH'
        self.assertEqual(env[key].split(os.pathsep)[0], str(binary.parent))
        self.assertNotEqual(env, {})

    def test_platform_has_matching_runtime_tag(self):
        expected = 'windows-x86_64' if os.name == 'nt' else 'linux-x86_64'
        self.assertEqual(platform_id(), expected)
