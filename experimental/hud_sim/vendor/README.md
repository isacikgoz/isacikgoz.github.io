# Vendored for the liquid simulator (repo-only, never deployed)

| File | What | From | License |
|---|---|---|---|
| `three.module.min.js` | three.js r160, the 3D world (`../sim_world.js`) | cdn.jsdelivr.net/npm/three@0.160.0/build/, sha256 `3e690ac7d180b0aadf0891bea39eec643e29e2d3e75c99b18689518665f69ba6` | MIT, (c) 2010-2023 three.js authors (in the file's header) |
| `lua51.js`, `lua51.wasm` | Lua 5.1.5 compiled to WebAssembly with `../sim_lua.c`: the add-on's Lua in the page (`../sim_lua.js`) | `make sim-wasm` (emscripten) from lua.org's lua-5.1.5.tar.gz | MIT, (c) 1994-2012 Lua.org, PUC-Rio |

Kept in the repo so `make sim` needs neither the network nor emscripten. Lua 5.1.5 is final, so the
WebAssembly build only changes with `sim_lua.c` or emscripten flags: then `make sim-wasm` and commit both files.
