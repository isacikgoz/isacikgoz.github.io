// The liquid simulator's Lua side, in the page: Lua 5.1 compiled to WebAssembly (vendor/lua51.wasm, built
// by make sim-wasm from lua.org's source and sim_lua.c) running sim_bridge.lua over Spheres' own files,
// as make sim's Lua process did before. read(path) answers a file's text, path from the Spheres folder.
import createLua from "./vendor/lua51.js";

// sim_bridge.lua and the add-on's files it loads (its own list: keep the two in step)
export const FILES = ["Art.lua", "Sphere.lua", "Track.lua", "Motion.lua", "tools/sim_bridge.lua"];

// Starts the bridge; resolves to ask(request): its reply, parsed (an error reply as { error }).
export async function startLua(read, log = console.warn) {
  const lua = await createLua({ print: log, printErr: log });
  const texts = await Promise.all(FILES.map(read));
  lua.FS.mkdirTree("/spheres/tools");
  FILES.forEach((file, i) => lua.FS.writeFile("/spheres/" + file, texts[i]));
  const start = lua.cwrap("sim_start", "string", ["string", "string"]);
  const send = lua.cwrap("sim_ask", "string", ["string"]);
  const error = start("/spheres/tools/sim_bridge.lua", "/spheres");
  if (error) throw new Error(error);
  return line => {
    const text = send(line);
    try { return JSON.parse(text); } catch (e) { return { error: String(text) }; }
  };
}

// The browser UI's bars, rings and target use the actual add-on modules. Its independent Lua
// state runs the same full TOC and frame/API mocks as tests/harness.lua, isolated from the HUD
// liquids bridge above.
export async function startGameUI(read, log = console.warn) {
  const lua = await createLua({ print: log, printErr: log });
  const toc = await read("Spheres.toc");
  const addonFiles = toc.split(/\r?\n/).map(line => line.trim()).filter(line => line.endsWith(".lua"));
  const files = ["Spheres.toc", ...addonFiles, "tests/harness.lua", "tools/sim_game_bridge.lua"];
  const texts = await Promise.all(files.map(read));
  lua.FS.mkdirTree("/spheres/tools");
  lua.FS.mkdirTree("/spheres/tests");
  files.forEach((file, i) => lua.FS.writeFile("/spheres/" + file, texts[i]));
  const start = lua.cwrap("sim_start", "string", ["string", "string"]);
  const send = lua.cwrap("sim_ask", "string", ["string"]);
  const error = start("/spheres/tools/sim_game_bridge.lua", "/spheres");
  if (error) throw new Error(error);
  return line => {
    const text = send(line);
    try { return JSON.parse(text); } catch { return { error: String(text) }; }
  };
}
