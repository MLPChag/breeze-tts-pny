#!/usr/bin/env python3
"""Build the pinned native Breeze runtime plus the local LoRA patch."""
import argparse
from pathlib import Path
import subprocess
REVISION='87b43667ca5597f826441991e416a279ed7373b9'
URL='https://github.com/HoppouAI/Breeze-TTS-2.cpp.git'
def run(*args,**kwargs):subprocess.run(args,check=True,**kwargs)
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source',type=Path,required=True);ap.add_argument('--build',type=Path,required=True)
    ap.add_argument('--cpu',action='store_true');ap.add_argument('--jobs',type=int,default=8)
    ap.add_argument('--windows',action='store_true',help='Apply the Windows portability patch')
    ap.add_argument('--skip-tests',action='store_true',help='Cross builds require separate execution under Wine or Windows')
    ap.add_argument('--cmake-arg',action='append',default=[],help='Additional CMake option, e.g. --cmake-arg=-DVulkan_INCLUDE_DIR=/sdk/include')
    args=ap.parse_args();src=args.source.resolve();build=args.build.resolve()
    if not src.exists():run('git','clone','--branch','v0.1.6','--depth','1',URL,str(src))
    actual=subprocess.check_output(['git','rev-parse','HEAD'],cwd=src,text=True).strip()
    if actual!=REVISION:raise RuntimeError('Unexpected upstream revision: '+actual)
    patch=Path(__file__).with_name('breeze-native-lora.patch').resolve()
    already=subprocess.run(['git','apply','--reverse','--check',str(patch)],cwd=src,capture_output=True).returncode==0
    if not already:
        if subprocess.check_output(['git','status','--porcelain','--untracked-files=all'],cwd=src,text=True).strip():
            raise RuntimeError('Use a clean upstream checkout; refusing to patch unrelated local edits')
        run('git','apply','--check',str(patch),cwd=src);run('git','apply',str(patch),cwd=src)
    portable=Path(__file__).with_name('breeze-portable-build.patch').resolve()
    applied=subprocess.run(['git','apply','--reverse','--check',str(portable)],cwd=src,capture_output=True).returncode==0
    if not applied:
        run('git','apply','--check',str(portable),cwd=src);run('git','apply',str(portable),cwd=src)
    if args.windows:
        windows_patch=Path(__file__).with_name('breeze-windows.patch').resolve()
        applied=subprocess.run(['git','apply','--reverse','--check',str(windows_patch)],cwd=src,capture_output=True).returncode==0
        if not applied:
            run('git','apply','--check',str(windows_patch),cwd=src);run('git','apply',str(windows_patch),cwd=src)
    run('git','submodule','update','--init','--depth','1','third_party/ggml',cwd=src)
    run('cmake','-S',str(src),'-B',str(build),'-DBREEZE_VULKAN='+('OFF' if args.cpu else 'ON'),
        '-DBREEZE_MP3=OFF','-DBREEZE_BUILD_TESTS=ON',*args.cmake_arg)
    run('cmake','--build',str(build),'-j',str(args.jobs))
    if not args.skip_tests:
        run('ctest','--test-dir',str(build),'-R','lora-cpu|depth-replay-cpu','--output-on-failure')
if __name__=='__main__':main()
