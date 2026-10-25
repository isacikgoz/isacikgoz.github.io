// The glows and shadows' Python on the public page (make site): Pyodide, CPython in WebAssembly, running
// make_media.py's effect functions with Pillow and numpy through sim_effects.py, as make sim's server runs them with this
// computer's Python. Started by sim_host_site.js the first time a slider moves; a request in, its reply out
// with the re-rendered textures' TGA bytes.
const PYODIDE = "https://cdn.jsdelivr.net/pyodide/v0.29.5/full/";

let python = null;
function start() {
  python = python || (async () => {
    postMessage({ say: "Loading Python for the glass (first time only, about 9 MB)…" });
    importScripts(PYODIDE + "pyodide.js");
    const quiet = () => {}; // make_media.py's "wrote ..." lines, Pyodide's own: a failure comes back as an error
    const py = await loadPyodide({ indexURL: PYODIDE, stdout: quiet, stderr: quiet });
    postMessage({ say: "Loading Pillow and numpy…" });
    await py.loadPackage(["pillow", "numpy"], { messageCallback: quiet });
    py.FS.mkdirTree("/spheres/tools");
    for (const file of ["make_media.py", "sim_effects.py"]) {
      const r = await fetch("effects/" + file);
      if (!r.ok) throw new Error(file + ": " + r.status);
      py.FS.writeFile("/spheres/tools/" + file, await r.text());
    }
    py.runPython("import sys, json\nsys.path.insert(0, '/spheres/tools')\nimport sim_effects\nworker = sim_effects.Worker()");
    return py;
  })();
  python.catch(() => { python = null; }); // a failed load is tried again next time
  return python;
}

onmessage = async ({ data: { id, request } }) => {
  try {
    if (request.op !== "render") throw new Error("only renders run here");
    const py = await start();
    postMessage({ say: "Rendering in Python…" });
    py.globals.set("request", JSON.stringify({ ...request, out: "/preview" }));
    const reply = JSON.parse(py.runPython("json.dumps(worker.render(json.loads(request)))"));
    const files = {}, moved = [];
    for (const name of reply.written) {
      const bytes = py.FS.readFile("/preview/" + name + ".tga");
      files[name] = bytes.buffer;
      moved.push(bytes.buffer);
      py.FS.unlink("/preview/" + name + ".tga");
    }
    postMessage({ id, reply: { ...reply, files } }, moved);
  } catch (e) {
    postMessage({ id, reply: { error: String((e && e.message) || e).split("\n").filter(Boolean).pop() } });
  }
};
