// Where the page's files come from on the public page (make site copies this file in as sim_host.js): static
// files beside the page, the add-on's Lua in lua/, its textures as PNG in media/, the glows and shadows' Python in
// a worker running Pyodide (sim_effects_worker.js, loaded the first time a slider moves). The same answers as
// sim_host.js gives under make sim, but nothing is exported: that writes into the add-on's files.
import { decodePNG, decodeTGA } from "./sim_media.js";

const here = new URL("./", import.meta.url);
const previews = {}; // a glow render's textures by name, before the page's own

function get(path) {
  return fetch(new URL(path, here)).then(r => { if (!r.ok) throw new Error(path + ": " + r.status); return r; });
}

let worker = null, asked = 0, say = () => {};
const waiting = new Map();
function python(request) {
  if (!worker) {
    worker = new Worker(new URL("sim_effects_worker.js", here));
    worker.onmessage = ({ data }) => {
      if (data.say) { say(data.say); return; }
      const done = waiting.get(data.id);
      waiting.delete(data.id);
      if (done) done(data.reply);
    };
    worker.onerror = e => {
      for (const done of waiting.values()) done({ error: "Python stopped: " + (e.message || "the worker failed") });
      waiting.clear();
      worker = null;
    };
  }
  const id = ++asked;
  return new Promise(done => { waiting.set(id, done); worker.postMessage({ id, request }); });
}

export const host = {
  site: true,
  text: path => get("lua/" + path).then(r => r.text()),
  image: name => previews[name] ? Promise.resolve(previews[name])
    : get("media/" + name + ".png").then(r => r.arrayBuffer()).then(b => decodePNG(b, name)),
  // progress (text) while Python loads or renders: the page shows it
  set say(fn) { say = fn; },
  async effects(request) {
    if (request.op === "values") return get("effects/values.json").then(r => r.json());
    if (request.op === "reset") {
      const cleared = Object.keys(previews);
      for (const name of cleared) delete previews[name];
      return { cleared };
    }
    if (request.op === "export") return { error: "exporting writes into the add-on's files: run make sim in its repo" };
    const reply = await python(request);
    for (const [name, bytes] of Object.entries(reply.files || {})) previews[name] = decodeTGA(bytes, name);
    delete reply.files;
    return reply;
  },
};
