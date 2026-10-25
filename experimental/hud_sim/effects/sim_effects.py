#!/usr/bin/env python3
"""The liquid simulator's glow and shadow effects (`make sim`): the existing ones make_media.py bakes
into the spheres' textures (glass highlights, rims, outline, edge shadows, the liquids' and the
empty orb's bottom shadows, the pet's scoop), as sliders.

    sim_effects.py serve     a worker for tools/sim_server.py: one JSON request a line on stdin, one reply
                             a line on stdout. Needs Pillow (make_media.py's).
    sim_effects.py --check   `make test`: every effect is a constant in make_media.py, every group a
                             function there (reads the file only: no Pillow)
    sim_effects.py --values  the "values" reply as JSON (make site: the public page's sliders; no Pillow)

Requests: {"op": "values"}                          the effects, their groups and make_media.py's values
          {"op": "render", "set": {...}, "changed": [...], "out": dir}
                                                    the textures the changed effects touch, with every
                                                    value in "set", written to `out` (a preview)
          {"op": "export", "set": {...}, "slosh": {...}}
                                                    the values written into make_media.py (the textures
                                                    they touch regenerated into Spheres/Media) and the
                                                    slosh's into Motion.lua's SLOSH
"""
import ast
import contextlib
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "make_media.py")
MOTION = os.path.join(os.path.dirname(HERE), "Motion.lua")

# make_media.py's texture groups: the functions that write them, and what they write
GROUPS = {
    "map": (["make_map_glass"], "the map's glass"),
    "glass": (["make_piece_glass"], "health and mana glass"),
    "whole": (["make_whole_glass"], "full health glass"),
    "pet": (["make_pet_glass"], "pet and inner glass"),
    "shade": (["make_piece_shades", "make_whole_shade"], "liquid shadows"),
    "bottom": (["make_bottom_shade"], "empty orb's shadow"),
    "bowl": (["make_pet_bowl"], "pet scoop"),
    "target": (["make_target_glass"], "target sphere glass"),
}
GLASS = ["map", "glass", "whole", "pet", "target"]
# Each effect: make_media.py's constant, its section and label, the groups it changes, and a slider
# per number (a tuple: one each): label, min, max, step.
EFFECTS = [
    # the light (the page's dial, not sliders): its placements turn with it (make_media.py light_frame)
    ("LIGHT", "Light", GLASS + ["bowl"],
     [("Light, across", -1, 1, 0.0001), ("Light, up", -1, 1, 0.0001), ("Light, towards you", 0, 1, 0.0001)]),
    ("GLASS_OUTLINE", "Glass, every sphere", GLASS, [("Glass outline, upper left", 0, 0.5, 0.005)]),
    ("TOP_RIM_STRENGTH", "Glass, every sphere", GLASS, [("Upper rim reflection", 0, 1, 0.01)]),
    ("SPEC_AT", "Glass, every sphere", GLASS, [("Highlight, across", -0.8, 0.8, 0.01), ("Highlight, up", -0.8, 0.9, 0.01)]),
    ("GLASS_RIM_SHADOW", "Glass, every sphere", ["map", "glass", "whole"],
     [("Lower edge shadow, whole spheres", 0, 1, 0.01), ("Lower edge shadow, split pieces", 0, 1, 0.01)]),
    ("PIECE_SHINE", "Health and mana glass", ["glass", "whole"], [("Highlight strength", 0, 1.5, 0.01)]),
    ("PIECE_GLOSS", "Health and mana glass", ["glass", "whole"], [("Window reflection", 0, 1.5, 0.01)]),
    ("MANA_TOP_RIM", "Health and mana glass", ["glass"], [("Mana's upper edge", 0, 3, 0.05)]),
    ("MANA_TOP_GLOW", "Health and mana glass", ["glass"], [("Mana's upper glow", 0, 0.5, 0.005)]),
    ("SEAM_CONTACT", "Health and mana glass", ["glass", "pet"], [("Seam shadow", 0, 0.3, 0.005)]),
    ("SEAM_REFLECTION", "Health and mana glass", ["glass", "pet"], [("Seam light", 0, 0.3, 0.005)]),
    ("MAP_SHINE", "Map glass", ["map"], [("Highlight strength", 0, 1.5, 0.01)]),
    ("MAP_GLOSS", "Map glass", ["map"], [("Window reflection", 0, 1, 0.01)]),
    ("MAP_RIM", "Map glass", ["map"], [("Upper edge glint", 0, 1.5, 0.01)]),
    ("MAP_EDGE_LIGHT", "Map glass", ["map"], [("Light along the rim", 0, 1.5, 0.01)]),
    ("INNER_SHINE", "Pet and inner sphere glass", ["pet"], [("Highlight strength", 0, 1, 0.01)]),
    ("INNER_GLOSS", "Pet and inner sphere glass", ["pet"], [("Window reflection", 0, 1, 0.01)]),
    ("LIQUID_SHADE", "Shadows", ["shade"], [("Liquid's bottom shadow", 0, 1, 0.01), ("Liquid's edge shade", 0, 1, 0.01)]),
    ("BOTTOM_SHADE", "Shadows", ["bottom"],
     [("Empty orb's bottom shadow, starts", -0.2, 0.9, 0.01), ("Empty orb's bottom shadow, darkness", 0, 255, 1)]),
    ("PET_BOWL_SHADE", "Pet scoop", ["bowl"], [("Scoop shade", 0, 1, 0.01), ("Scoop contact shadow", 0, 1, 0.01)]),
    ("PET_BOWL_HIGHLIGHT", "Pet scoop", ["bowl"], [("Scoop wall light", 0, 1, 0.01), ("Scoop lip light", 0, 1, 0.01)]),
    ("PET_BOWL_ARC_SHADOW", "Pet scoop", ["bowl"], [("Lower-right shadow", 0, 1, 0.01), ("Its sharpness", 0.1, 3, 0.05)]),
    ("TARGET_EDGE_LIGHT", "Target sphere glass (experimental)", ["target"], [("Light round the edge", 0, 1, 0.01)]),
    ("TARGET_SHINE", "Target sphere glass (experimental)", ["target"], [("Highlight strength", 0, 1.5, 0.01)]),
    ("TARGET_GLOSS", "Target sphere glass (experimental)", ["target"], [("Window reflection", 0, 1.5, 0.01)]),
    ("TARGET_LOWER_FADE", "Target sphere glass (experimental)", ["target"], [("Lower half's light fades", 0, 1, 0.01)]),
]


def constants(path=SCRIPT):
    """make_media.py's top-level constants: name -> (value, the value's source span)."""
    with open(path, encoding="utf-8") as f:
        source = f.read()
    found = {}
    for node in ast.parse(source).body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            try:
                value = ast.literal_eval(node.value)
            except ValueError:
                continue
            found[node.targets[0].id] = (value, (node.value.lineno, node.value.col_offset,
                                                 node.value.end_lineno, node.value.end_col_offset))
    return source, found


def functions(path=SCRIPT):
    with open(path, encoding="utf-8") as f:
        return {n.name for n in ast.parse(f.read()).body if isinstance(n, ast.FunctionDef)}


def literal(value):
    """A value as make_media.py writes its constants: 0.42, 230, (0.42, 0.7)."""
    def one(x):
        if isinstance(x, bool):
            return repr(x)
        if isinstance(x, int) or (isinstance(x, float) and x.is_integer() and abs(x) >= 10):
            return str(int(round(x)))
        return repr(round(float(x), 4))
    if isinstance(value, (list, tuple)):
        return "(" + ", ".join(one(x) for x in value) + ")"
    return one(value)


def write_slosh(values, path=MOTION):
    """Motion.lua's `local SLOSH = { ... }`: each given value in place, its layout kept. Returns what changed."""
    with open(path, encoding="utf-8") as f:
        source = f.read()
    start = source.find("local SLOSH = {")
    end = source.find("}", start)
    if start < 0 or end < 0:
        raise ValueError("no `local SLOSH = { ... }` in Motion.lua")
    changed = {}

    def number(match):
        key, old = match.group(1), match.group(2)
        if key not in values or float(old) == float(values[key]):
            return match.group(0)
        v = float(values[key])
        decimals = len(old.split(".")[1]) if "." in old else 0
        new = str(int(round(v))) if decimals == 0 and v.is_integer() else "%.*f" % (max(2, decimals), v)
        if abs(float(new) - v) > 1e-9:  # needs more decimals than the file's (0.475)
            new = repr(round(v, 4))
        changed[key] = [old, new]
        return "%s = %s" % (key, new)
    table = re.sub(r"(\w+) = (-?[\d.]+)", number, source[start:end])
    if changed:
        with open(path, "w", encoding="utf-8") as f:
            f.write(source[:start] + table + source[end:])
    return changed


def check():
    _, found = constants()
    have = functions()
    problems = []
    for name, _, groups, parts in EFFECTS:
        if name not in found:
            problems.append(name + ": not a constant in make_media.py")
            continue
        value = found[name][0]
        n = len(value) if isinstance(value, tuple) else 1
        if n != len(parts):
            problems.append("%s: %d numbers in make_media.py, %d sliders here" % (name, n, len(parts)))
        for g in groups:
            if g not in GROUPS:
                problems.append(name + ": no group " + g)
    for g, (fns, _) in GROUPS.items():
        for fn in fns:
            if fn not in have:
                problems.append("group %s: no %s() in make_media.py" % (g, fn))
    parts_of = {name: len(parts) for name, _, _, parts in EFFECTS}
    for key, _, scale in SIMPLE:
        for name, indices in scale.items():
            if name not in parts_of or any(i >= parts_of[name] for i in indices):
                problems.append("%s: scales %s %s, not an effect's numbers" % (key, name, indices))
    if problems:
        sys.exit("sim effects: FAIL: " + "; ".join(problems))
    print("sim effects: ok (%d effects, %d groups)" % (len(EFFECTS), len(GROUPS)))


# The few knobs (the simulator's Light group; the effects above under Advanced): each scales these
# effects' numbers (by index in a tuple) from make_media.py's values, together.
SIMPLE = [
    ("shine", "Shine", {"PIECE_SHINE": [0], "MAP_SHINE": [0], "INNER_SHINE": [0], "TARGET_SHINE": [0],
                        "PIECE_GLOSS": [0], "MAP_GLOSS": [0], "INNER_GLOSS": [0], "TARGET_GLOSS": [0],
                        "TOP_RIM_STRENGTH": [0], "MAP_RIM": [0], "MANA_TOP_GLOW": [0], "PET_BOWL_HIGHLIGHT": [0, 1]}),
    ("outline", "Outline", {"GLASS_OUTLINE": [0], "MAP_EDGE_LIGHT": [0], "TARGET_EDGE_LIGHT": [0],
                            "SEAM_REFLECTION": [0]}),
    ("shadow", "Shadow", {"GLASS_RIM_SHADOW": [0, 1], "SEAM_CONTACT": [0], "LIQUID_SHADE": [0, 1],
                          "BOTTOM_SHADE": [1], "PET_BOWL_SHADE": [0, 1], "PET_BOWL_ARC_SHADOW": [0]}),
]


def values():
    """The effects, their groups and make_media.py's values: from its source, so no Pillow."""
    _, found = constants()
    effects = []
    for name, section, groups, parts in EFFECTS:
        value = found[name][0]
        effects.append({"name": name, "section": section, "groups": groups,
                        "value": list(value) if isinstance(value, tuple) else value,
                        "parts": [{"label": p[0], "min": p[1], "max": p[2], "step": p[3]} for p in parts]})
    return {"effects": effects, "groups": {g: d for g, (_, d) in GROUPS.items()},
            "simple": [{"key": k, "label": label, "scale": scale} for k, label, scale in SIMPLE]}


class Worker:
    def __init__(self):
        self.load()

    def load(self):
        spec = importlib.util.spec_from_file_location("make_media", SCRIPT)
        self.mm = importlib.util.module_from_spec(spec)
        with contextlib.redirect_stdout(sys.stderr):  # stdout is the server's replies
            spec.loader.exec_module(self.mm)
        self.media = self.mm.OUT
        self.original = {name: getattr(self.mm, name) for name, *_ in EFFECTS}
        self.written = []
        real_write = self.mm.write

        def write(name, im):
            self.written.append(name)
            real_write(name, im)
        self.mm.write = write

    def apply(self, values):
        for name, *_ in EFFECTS:
            v = values.get(name, self.original[name])
            setattr(self.mm, name, tuple(v) if isinstance(v, (list, tuple)) else v)

    def groups_of(self, names):
        out = []
        for name, _, groups, _ in EFFECTS:
            if name in names:
                out += [g for g in groups if g not in out]
        return out

    def run(self, groups, out):
        os.makedirs(out, exist_ok=True)
        self.mm.OUT = out
        self.written = []
        with contextlib.redirect_stdout(sys.stderr):  # make_media.py's "wrote ..." lines
            for g in groups:
                for fn in GROUPS[g][0]:
                    getattr(self.mm, fn)()
        return self.written

    def values(self):
        return values()

    def render(self, request):
        self.apply(request.get("set", {}))
        groups = self.groups_of(request.get("changed", []))
        return {"written": self.run(groups, request["out"]), "groups": groups}

    def export(self, request):
        slosh = write_slosh(request.get("slosh", {})) if request.get("slosh") else {}
        reply = self.export_media(request.get("set", {}))
        reply["slosh"] = slosh
        return reply

    def export_media(self, values):
        source, found = constants()
        lines = source.split("\n")
        changed = {}
        # replace each value's own source text, last first so earlier spans stay put
        edits = []
        for name, *_ in EFFECTS:
            if name not in values:
                continue
            new = literal(values[name])
            old_value, span = found[name]
            if literal(old_value) == new:
                continue
            changed[name] = [literal(old_value), new]
            edits.append((span, new))
        for (l0, c0, l1, c1), new in sorted(edits, reverse=True):
            first, last = lines[l0 - 1], lines[l1 - 1]
            lines[l0 - 1:l1] = [first[:c0] + new + last[c1:]]
        if not changed:
            return {"changed": {}, "written": []}
        with open(SCRIPT, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        self.load() # the file's new values, as make_media.py will run them
        written = self.run(self.groups_of(changed.keys()), self.media)
        return {"changed": changed, "written": written}


def serve():
    worker = Worker()
    for line in sys.stdin:
        try:
            request = json.loads(line)
            op = request.get("op")
            if op == "values":
                reply = worker.values()
            elif op == "render":
                reply = worker.render(request)
            elif op == "export":
                reply = worker.export(request)
            else:
                reply = {"error": "unknown op " + str(op)}
        except Exception as err:  # the page shows it; the worker keeps serving
            reply = {"error": "%s: %s" % (type(err).__name__, err)}
        sys.stdout.write(json.dumps(reply) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    if "--check" in sys.argv:
        check()
    elif "--values" in sys.argv:
        print(json.dumps(values()))
    elif "serve" in sys.argv:
        serve()
    else:
        sys.exit(__doc__)
