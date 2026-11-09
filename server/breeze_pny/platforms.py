"""Platform-specific locking and native runtime setup; inference stays shared."""
import os
from pathlib import Path
import platform


def platform_id():
    if platform.machine().lower() not in ('x86_64', 'amd64'):
        raise ValueError('This preview requires an x86_64 CPU')
    names = {'Linux': 'linux-x86_64', 'Windows': 'windows-x86_64'}
    try:
        return names[platform.system()]
    except KeyError:
        raise ValueError('This preview supports Linux and Windows x86_64') from None


def acquire_lock(lock):
    if os.name == 'nt':
        import ctypes
        from ctypes import wintypes
        import msvcrt
        class Overlapped(ctypes.Structure):
            _fields_ = [('internal', ctypes.c_size_t), ('internal_high', ctypes.c_size_t),
                        ('offset', wintypes.DWORD), ('offset_high', wintypes.DWORD),
                        ('event', wintypes.HANDLE)]
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        acquire = kernel.LockFileEx
        acquire.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.DWORD,
                            wintypes.DWORD, wintypes.DWORD, ctypes.POINTER(Overlapped)]
        acquire.restype = wintypes.BOOL
        # Exclusive, immediate byte-range lock; Windows releases it on handle close.
        state = Overlapped()
        if not acquire(msvcrt.get_osfhandle(lock.fileno()), 3, 0, 1, 0, ctypes.byref(state)):
            code = ctypes.get_last_error()
            if code in (32, 33):
                raise BlockingIOError('Companion installation is locked')
            raise ctypes.WinError(code)
    else:
        import fcntl
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)


def runtime_environment(binary):
    env = dict(os.environ)
    key = 'PATH' if os.name == 'nt' else 'LD_LIBRARY_PATH'
    env[key] = str(binary.parent) + (os.pathsep + env[key] if env.get(key) else '')
    return env


def default_prefix():
    if os.name == 'nt':
        return Path(os.environ.get('LOCALAPPDATA', Path.home() / 'AppData/Local')) / 'breeze-tts-pny'
    return Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'breeze-tts-pny'
