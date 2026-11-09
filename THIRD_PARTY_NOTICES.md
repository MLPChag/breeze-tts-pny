# Third-party components

The repository's MIT license applies to original mod code. It does not relicense the following components or Home: Equestria.

| Component | Revision / provenance | License |
| --- | --- | --- |
| Talking Avatar model and inference design | [InterviewFlowAI/talking-avatar](https://github.com/interviewflowai/talking-avatar), `d3e4dcf6609d733097466eb17b3fa63fc720140a` | MIT; copyright 2026 InterviewFlowAI |
| Godot C++ bindings | [godotengine/godot-cpp](https://github.com/godotengine/godot-cpp), `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77` | MIT |
| JSON for Modern C++ | [nlohmann/json](https://github.com/nlohmann/json), 3.12.0 in the tested build | MIT |

The native implementation ports the Talking Avatar audio features and network inference to C++ and adds the Godot worker interface. The unmodified model is `mods/breeze_tts_pny/native/viseme-model.bin`, SHA-256:

```text
f1cdf2b76b9f2da8730b1d3e47d7e05a2b79c9b92d00dd00c595d64e471f419c
```

Full notices are included in `mods/breeze_tts_pny/licenses/` and in the built pack. The Linux build also links GCC runtime libraries statically under GPLv3 with the GCC Runtime Library Exception 3.1 (Free Software Foundation); the applicable license texts are included there. The exception text comes from [GCC's 14.2.0 source](https://github.com/gcc-mirror/gcc/blob/releases/gcc-14.2.0/COPYING.RUNTIME).

The pack does not contain Home: Equestria's base-game scripts or assets. At startup it reads the installed game's original scripts and caches local inheritance aliases. The official mod builder and game source required for building/testing are supplied by the developer and are not copied into this repository or distributable.

Breeze-TTS-2 weights, voice caches, adapters, personal recordings and installed service configuration are excluded from Git and the game pack. Companion release artifacts package the curated voice assets separately and download model weights from their pinned sources. Voice-pack notices and per-reference provenance travel with that archive; they are not covered by the original-code MIT license.

## Companion dependencies

- [Breeze-TTS-2.cpp](https://github.com/HoppouAI/Breeze-TTS-2.cpp), revision `87b43667ca5597f826441991e416a279ed7373b9`: Apache-2.0. The included source patch adds selectable LoRA adapters; the runtime archive includes that patch/build recipe and the Apache license. MP3 support is disabled in this build.
- ggml: MIT, notice retained in `native/breeze/LICENSE.ggml` and the runtime archive.
- [Breeze TTS 2 model weights](https://huggingface.co/BreezeBlue/Breeze-TTS-2): BreezeBlue Research and Non-Commercial License. See the model's license; the code license does not cover weights or derived adapters.

## Windows build runtime

The Windows build statically links LLVM libc++/compiler runtime and MinGW-w64 support. The LLVM Apache-2.0 license with LLVM exceptions, MinGW-w64 runtime notices and winpthreads notices are included in the runtime archive and game pack. The companion Windows ZIP also includes the unmodified official CPython embedded distribution; its complete Python and bundled-component notices are in `python/LICENSE.txt`. Embedded Python is used only as the standard-library application runtime.
