#!/usr/bin/env python3
"""Writes Spheres' art (Media/*.tga): Roth UI's (tools/roth/, MIT, see tools/roth/LICENSE.txt),
adapted, and our glass.

Roth UI (Galaxy, after zork's oUF_Diablo and Goldpaw's DiabolicUI) draws the Diablo look this
add-on is built on. From it:

  OrbBack      Roth's orb back (orb_back2) over an opaque dark disc the ball's size: dark glass
               where nothing fills an orb (Roth's back alone is see-through)
  OrbBackWhole the same without the pinch where health and mana meet at the top: full health
  OrbBottomShade ours: lower shadow for the empty left orb, separate from OrbBack
  OrbSocket    ours: the frame's dark stone behind each orb's lower part, a little past its rim
  BarShape*, BarFill*, BarGloss*, BarRim*   ours: the target card's health and power bars,
               rounded: the track, the fill (Roth's liquid), glass over it, a brass rim round it
  FluidFlow    a subtle pattern of dark fluid wisps, animated over the target card's bars
  LiquidCloud, LiquidStream, LiquidFine   ours: the liquids' moving layers, shared by both
               pieces and tinted in game: billows, smoky currents, fine turbulence
  LiquidShadeHealth, LiquidShadeMana     ours: each liquid's bottom shadow and darker outer edge
  LiquidGlint  ours: one tiny soft glint the mana carries up
  SurfaceCrest, SurfaceLine  ours: the liquids' wavy top, fading into them, and the light under it
  FillPet, MaskPet, GlassPet   ours: the pet's orb in the left orb's middle, whole: fill, mask,
               glass (the big orbs' recipe on a round ball, without broad depth shading)
  FillPetHealth/Mana, MaskPet..., GlassPet...   the same, cut in two along the left orb's seam (PET_R)
  PetCavity    ours: a mask over the left orb for its liquids: a little dimmer behind the pet's ball
  PetBack      ours: the pet's ball's own dark glass while it stands beside the left orb
  PetBowl      ours: the scoop in the pieces' front, its concave walls as light and shade on the glass,
               the pet's ball's contact shadow in it (shown only with a pet: 0.5.287)
  PetContactBase  ours: a small contact spot visible even with an empty embedded ball
  PetContactShadow*  ours: a lower contact shade outside the embedded ball, revealed by its liquid
  FillNone     ours: an empty status bar fill (the liquids' plain colour is drawn in their clip)
  FillHealth   a plain white fill cut to the health piece; FillMana is the same for mana. The left orb is two
  FillMana     pieces of glass side by side, health 60% of the ball, mana 40% (by area), a seam
               apart, rounded where they meet (FILLET). Each fill covers its piece's bounding box
               (PIECES, printed for Sphere.lua), so a status bar's 0-100% runs the piece's height
  Frame0-2     the two-row action bar frame with 0, 1 or 2 slots along its top for the experience
               and reputation bars (actionbar_2_0/1/2); each also has a Charcoal variant
  Bottom       the shaped brass ornament along the bottom edge (prepared from d3_bottom)

Ours:
  MenuLatencyRing  a thin white annulus tinted by the Game Menu hub's latency color
  FillWhole, MaskWhole, GlassWhole, LiquidShadeWhole   full health glass for players using the inner sphere for power
  GlassMap, GlassHealth, GlassMana   each globe's glass, lit from the top left: shading, a
               bright edge, a highlight. The round one a sphere; a piece the same sphere, rounded
               off towards the seam (BEVEL), so it curves there as at the ball's edge
  MaskMap      a circular minimap mask, gently fading its outer 5% into the dark backing
  MapDissolve  a full-globe black radial fade above the minimap, beneath the clouds
  MapCloud1-5  five black and charcoal smoke rings over the inset minimap, slowly counter-rotated:
               LiquidCloud's billows or LiquidFine's swirls (MAP_CLOUDS)
  MapTendrils  soft black tendrils reaching inward from the smoke, gently swaying in game, their
               body LiquidCloud's billows (TENDRIL_CLOUD)
  MaskHealth, MaskMana               each piece's shape, to clip its moving layers
  StatueLeft, StatueRight            the winged bronze lion and griffin beside the orbs (the
               player's art, tools/ornaments/winged.png, 0.5.14: in place of Roth's demon and
               angel): cut out of its painted checkerboard, brass, darks deepened, a soft shadow
               under them (falling down and right, away from the light)
  StatueLeft/RightCharcoal           matching statues in charcoal gray
  Frame0-2Charcoal                   center frames with charcoal ends and no brass transition
  StatueLeft/RightModern             supplied modern statue artwork, normalized to 512 square
  StatueRightClearHeadModern         modern griffin with a faded head, for the map arrow
  Frame0-2Modern                      supplied modern frame, with zero, one or two upper rails
The statues sit in front of the orbs, and their shadow falls on the glass and the world
(STATUE_SHADOW). The frame sits in front of the orbs, with its cutouts fitted to the glass and painted
engraved crescents continuing its side plates beneath them. The places below must match Sphere.lua's.

Brass: each pixel's brightness mapped through a ramp from near-black bronze to pale gold (BRASS).
The console fades from brass at its curved ends into charcoal gray at the center; alpha kept. A status bar crops its fill file by the hidden value itself: no
mask on a fill (masked fills drew nothing in Spheres 0.1-0.3). Masked plain textures do draw: the
liquids' moving layers in a frame clipped to the fill's top, and the wavy top pinned to it.

Uncompressed 32-bit TGA, top-left origin (what the game reads; Action Ring's Backdrop.tga too).
Needs Pillow and numpy (the glass: whole textures at a time, fast enough for the simulator's light to
follow a drag). Run from the add-on folder: python3 tools/make_media.py
"""
import argparse
import array
import math
import os
import random
import struct

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(HERE, "tools", "roth")
OUT = os.path.join(HERE, "Media")
MODERN = os.path.join(HERE, "tools", "modern")
RELIEF_DIR = os.path.join(HERE, "tools", "detail")

# brightness -> brass: near-black bronze, bronze, brass, gold, pale gold
BRASS = [(0.0, (8, 5, 2)), (0.18, (40, 26, 10)), (0.4, (105, 74, 30)), (0.62, (170, 128, 60)),
         (0.82, (222, 182, 100)), (1.0, (255, 236, 175))]
GAIN = 1.25       # a little brighter than the source: Roth's stone is dark
FRAME_GAIN = 1.6  # lift the frame's dark bronze without flattening its highlights


def ramp(level):
    for (a, ca), (b, cb) in zip(BRASS, BRASS[1:]):
        if level <= b:
            t = (level - a) / (b - a)
            return tuple(int(ca[k] + (cb[k] - ca[k]) * t) for k in range(3))
    return BRASS[-1][1]


LUT = [ramp(i / 255) for i in range(256)]


def brass(im, gain=GAIN):
    r, g, b, a = im.split()
    lum = Image.merge("RGB", (r, g, b)).convert("L").point(lambda v: min(255, int(v * gain)))
    return Image.merge("RGBA", (lum.point(lambda v: LUT[v][0]), lum.point(lambda v: LUT[v][1]),
                                lum.point(lambda v: LUT[v][2]), a))


def patina(im, gray_mix, shade, gamma=1):
    """Quiet bright brass toward charcoal while retaining its carved light and detail."""
    r, g, b, a = im.split()
    rgb = Image.merge("RGB", (r, g, b))
    lum = rgb.convert("L")
    neutral = Image.merge("RGB", (lum.point(lambda v: int(v * 0.97)), lum,
                                  lum.point(lambda v: min(255, int(v * 1.03)))))
    toned = Image.blend(rgb, neutral, gray_mix)
    if shade != 1:
        toned = toned.point(lambda v: min(255, int(v * shade)))
    if gamma != 1:
        toned = toned.point(lambda v: int(255 * (v / 255) ** gamma))
    return Image.merge("RGBA", (*toned.split(), a))


def frame_finish(im, centers, radius):
    """Keep engraved plate artwork brass around each socket, fading into the gray console."""
    gray = patina(im, 0.88, 1.0, 0.72)
    w, h = im.size
    scale = w / 1024
    start, end = 225 * scale, 360 * scale
    weights = []
    for x in range(w):
        distance = min(x, w - 1 - x)
        t = max(0.0, min(1.0, (distance - start) / (end - start)))
        t = t * t * (3 - 2 * t)
        weights.append(int(255 * (1 - t)))
    mask = Image.new("L", (w, 1))
    mask.putdata(weights)
    mask = mask.resize((w, h))
    px = mask.load()
    mw, mh, mid, bottom = PLACES["Frame"]
    sx, sy = mw / w, mh / h
    left = mid - mw / 2
    for y in range(h):
        hy = bottom + (h - y - 0.5) * sy
        for x in range(w):
            hx = left + (x + 0.5) * sx
            weight = px[x, y] / 255
            for cx, cy in centers:
                t = max(0.0, min(1.0,
                    (math.hypot(hx - cx, hy - cy) - radius - FRAME_EDGE_KEEP) / FRAME_EDGE_BLEND))
                curved = 1 - t * t * (3 - 2 * t)
                weight = max(weight, curved)
            px[x, y] = int(weight * 255 + 0.5)
    return Image.composite(im, gray, mask)


def crisp_resize(im, size, strength):
    """Enlarge painted art without softening its relief or changing transparent edges."""
    im = im.resize(size, Image.LANCZOS)
    r, g, b, a = im.split()
    rgb = Image.merge("RGB", (r, g, b)).filter(
        ImageFilter.UnsharpMask(radius=1.15, percent=strength, threshold=2))
    return Image.merge("RGBA", (*rgb.split(), a))


def detail_color(base, reference, weight):
    """Use painted detail while keeping the exact original silhouette and alpha."""
    valid = ImageChops.multiply(reference.split()[3], base.split()[3])
    weight = ImageChops.multiply(valid, weight)
    rgb = Image.composite(reference.convert("RGB"), base.convert("RGB"), weight)
    return Image.merge("RGBA", (*rgb.split(), base.split()[3]))


def frame_surface(base, centers, radius):
    """Smooth the console center while preserving carved source art around each orb curve."""
    w, h = base.size
    surface = Image.new("RGB", (w, h))
    rows = []
    for y in range(h):
        height = max(0.0, 1.0 - abs(y - 335) / 200)
        row = []
        for x in range(w):
            edge = max(0.0, 1.0 - min(x, w - 1 - x) / 650)
            light = 24 + 10 * height + 3 * edge
            row.append((int(light + 8 * edge), int(light + 4 * edge), int(light)))
        rows.extend(row)
    surface.putdata(rows)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rectangle((455, 286, 1593, 459), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(9))
    # Keep engraved plate detail beside the sphere cutouts. The smooth console treatment fades
    # in only farther from each glass edge, following its circular contour.
    mw, mh, mid, bottom = PLACES["Frame"]
    sx, sy = mw / w, mh / h
    left = mid - mw / 2
    mpx = mask.load()
    for y in range(h):
        hy = bottom + (h - y - 0.5) * sy
        for x in range(w):
            if not mpx[x, y]:
                continue
            hx = left + (x + 0.5) * sx
            keep = 1.0
            for cx, cy in centers:
                t = max(0.0, min(1.0, (math.hypot(hx - cx, hy - cy) - radius - FRAME_EDGE_KEEP) /
                                 FRAME_EDGE_BLEND))
                t = t * t * (3 - 2 * t)
                keep = min(keep, t)
            mpx[x, y] = int(mpx[x, y] * keep + 0.5)
    rgb = Image.composite(surface, base.convert("RGB"), mask)
    return Image.merge("RGBA", (*rgb.split(), base.split()[3]))


def engraved_frame_ends(base):
    """Fit the painted engraving's inner contour to the glass circle on each end.

    The source is the right end, cropped from x=218..394, y=0..110 in HUD units. Only its new
    lower crescent is composited; the console, original corner, XP openings and upper rail stay
    in the original frame. The painted source has its own inner arc. Measure that arc along
    each ray and move its detail outward along the ray so the painted lip meets FRAME_CUT,
    rather than clipping through the scrollwork. Mirror the result for the left end.
    """
    W, H = base.size
    fw, fh, _, _ = PLACES["Frame"]
    left = round((fw / 2 + 218) * W / fw)
    top = round((fh - 110) * H / fh)
    size = (W - left, H - top)
    painted = Image.open(os.path.join(RELIEF_DIR, "frame_socket_engraving.png")).convert("RGBA")
    painted = patina(painted.resize(size, Image.LANCZOS), 0.04, 0.78)
    src = painted.load()
    end = Image.new("RGBA", size)
    px = end.load()
    old = base.load()

    def ease(v):
        v = max(0.0, min(1.0, v))
        return v * v * (3 - 2 * v)

    def sample(angle, radius):
        hx = FRAME_ORB_X + radius * math.cos(angle)
        hy = ORB_Y + radius * math.sin(angle)
        sx = round((hx + fw / 2) * W / fw - left - 0.5)
        sy = round((fh - hy) * H / fh - top - 0.5)
        if 0 <= sx < size[0] and 0 <= sy < size[1]:
            return src[sx, sy]
        return (0, 0, 0, 0)

    # A half-degree table is enough at the frame's 2048-pixel resolution. Its measured
    # source edge differs from the actual sphere by up to 20 HUD units near the outer end.
    source_edges = []
    for i in range(361):
        angle = math.pi + i * math.pi / 360
        edge = FRAME_CUT
        for step in range(240, 481):  # 60..120 HUD units, quarter-unit precision
            radius = step / 4
            if sample(angle, radius)[3] >= 200:
                edge = radius
                break
        source_edges.append(edge)

    for y in range(size[1]):
        hy = fh - (top + y + 0.5) * fh / H
        for x in range(size[0]):
            hx = (left + x + 0.5) * fw / W - fw / 2
            dx, dy = hx - FRAME_ORB_X, hy - ORB_Y
            d = math.hypot(dx, dy)
            if hx < FRAME_ORB_X - FRAME_CUT or hy > 96 or not (FRAME_CUT - 0.4 < d < FRAME_CUT + 22):
                continue
            inner = ease((d - FRAME_CUT + 0.4) / 0.85)
            # Feather into existing carved metal; keep a crisp outer silhouette where it is new.
            feather = 3.0 if old[left + x, top + y][3] > 200 else 0.8
            outer = ease((FRAME_CUT + 22 - d) / feather)
            alpha = inner * outer * ease((96 - hy) / 5)
            if alpha <= 0:
                continue
            angle = math.atan2(dy, dx)
            if angle < 0:
                angle += 2 * math.pi
            index = max(0.0, min(360.0, (angle - math.pi) * 360 / math.pi))
            lower = min(359, int(index))
            source_edge = source_edges[lower] * (1 - (index - lower)) + source_edges[lower + 1] * (index - lower)
            source_radius = d - FRAME_CUT + source_edge
            color = sample(angle, source_radius)
            if color[3] < 220:
                # Bleed the painted lip's color into its subpixel edge.
                for step in range(1, 17):
                    color = sample(angle, source_radius + step * 0.4)
                    if color[3] >= 220:
                        break
                else:
                    continue
            px[x, y] = color[:3] + (round(alpha * 255),)
    out = base.copy()
    out.alpha_composite(end, (left, top))
    out.alpha_composite(ImageOps.mirror(end), (0, top))
    return out


def charcoal_frame(base):
    """Keep the frame's carved relief while giving all its metal a dark gray finish."""
    r, g, b, a = base.split()
    lum = Image.merge("RGB", (r, g, b)).convert("L")
    tone = lum.point(lambda v: min(255, round(8 + 0.58 * v)))
    return Image.merge("RGBA", (tone, tone.point(lambda v: min(255, v + 1)),
                                tone.point(lambda v: min(255, v + 3)), a))


def graded_frame(base):
    """Fade the charcoal panel into its original brass carving toward both outer ends."""
    gray = charcoal_frame(base)
    w, h = base.size
    frame_width = PLACES["Frame"][0]
    weights = []
    for x in range(w):
        hud_x = abs((x + 0.5) * frame_width / w - frame_width / 2)
        t = max(0.0, min(1.0, (hud_x - 245) / 145))
        weights.append(round(255 * t * t * (3 - 2 * t)))
    mask = Image.new("L", (w, 1))
    mask.putdata(weights)
    return Image.composite(base, gray, mask.resize((w, h)))


def frame_corner_sockets(base):
    """Inlay dark console texture and a continuous, even rim into both wells."""
    w, h = base.size
    fw, fh, _, _ = PLACES["Frame"]
    sx, sy = w / fw, h / fh
    out = base.copy()
    source, pixels = base.load(), out.load()

    def smooth(v):
        v = max(0.0, min(1.0, v))
        return v * v * (3 - 2 * v)

    def mix(a, b, t):
        return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(3))

    for side in (-1, 1):
        x = (fw / 2 + side * 241) * sx
        y = (fh - 29) * sy
        shift = round(-side * 64 * sx)
        for py in range(max(0, int(y - 14 * sy)), min(h, int(y + 14 * sy) + 1)):
            for px in range(max(0, int(x - 14 * sx)), min(w, int(x + 14 * sx) + 1)):
                distance = math.hypot((px + 0.5 - x) / sx, (py + 0.5 - y) / sy)
                coverage = smooth((13.65 - distance) * sx)
                if not coverage:
                    continue
                original, texture = source[px, py], source[px + shift, py]
                # Replace the engraving beneath the entire lip. Previously it showed
                # through between separate ellipse strokes, most visibly at the bottom.
                interior = tuple(round(v * 0.82) for v in texture[:3])
                inner = smooth((distance - 11.55) / 0.5)
                highlight = smooth((distance - 12.05) / 0.3) * (1 - smooth((distance - 12.65) / 0.3))
                outer = smooth((distance - 12.8) / 0.35)
                rim_light = (97, 89, 74) if py < y else (71, 68, 62)
                color = mix(interior, (5, 6, 8), inner)
                color = mix(color, rim_light, highlight)
                color = mix(color, (11, 12, 14), outer)
                pixels[px, py] = (mix(original, color, coverage) +
                                  (round(original[3] * (1 - coverage) + 255 * coverage),))
    return out


def straight_frame_edges(base):
    """Continue the side rim and level the lower metal edge.

    The original carved side loses its narrow highlight just below the top tip.
    Follow the existing opaque silhouette so the added line stays on the metal.
    """
    out = base.copy()
    px = out.load()
    w, h = out.size
    sx, sy = w / 2048, h / 512
    for side in (-1, 1):
        corner = round(w / 2 + side * 600 * sx)
        for y in range(round(211 * sy), round(316 * sy)):
            candidates = [x for x in range(corner - round(24 * sx), corner + round(24 * sx))
                          if px[x, y][3] >= 100]
            if not candidates:
                continue
            edge = max(candidates) if side > 0 else min(candidates)
            top = min(1.0, (y / sy - 211) / 9)
            bottom = min(1.0, (316 - y / sy) / 18)
            fade = max(0.0, min(top, bottom))
            for inset in range(1, round(5 * sx) + 1):
                x = edge - side * inset
                r, g, b, a = px[x, y]
                if a < 60:
                    continue
                strength = fade * 0.7 * math.exp(-((inset / sx - 2.3) / 1.5) ** 2)
                px[x, y] = (min(255, round(r + 68 * strength)),
                            min(255, round(g + 70 * strength)),
                            min(255, round(b + 72 * strength)), a)
    # The engraved crescent's old curved foot remains visible inside the new
    # straight silhouette. Continue the console's lower metal strip behind the
    # scrolls and keep their raised detail above it.
    source = out.copy().load()
    fw, fh, _, _ = PLACES["Frame"]
    center_y = ORB_Y
    for x in range(w):
        distance = abs(x - w / 2) / sx
        enter = max(0.0, min(1.0, (distance - 570) / 45))
        weight_x = enter
        if not weight_x:
            continue
        side = 1 if x > w / 2 else -1
        sample_x = round(w / 2 + side * 530 * sx)
        sphere_dx = (x + 0.5) * fw / w - fw / 2 - side * FRAME_ORB_X
        for y in range(round(454 * sy), round(500 * sy)):
            sphere_dy = fh - (y + 0.5) * fh / h - center_y
            glass_distance = math.hypot(sphere_dx, sphere_dy)
            metal = max(0.0, min(1.0, (glass_distance - FRAME_CUT + 0.2) / 0.8))
            if not metal:
                continue
            v = max(0.0, min(1.0, (y / sy - 454) / 16))
            original, straight = source[x, y], source[sample_x, y]
            detail = max(0.0, min(1.0, (max(original[:3]) - 38) / 22))
            detail *= max(0.0, min(1.0, (490 - y / sy) / 12))
            weight = weight_x * metal * v * v * (3 - 2 * v) * (1 - detail)
            px[x, y] = tuple(round(original[k] * (1 - weight) + straight[k] * weight)
                             for k in range(4))
    # At y=500 all of the lower metal is still continuous from the panel to
    # the outer scroll. The original shape dips below it in several lobes.
    baseline = round(500 * sy)
    out.paste((0, 0, 0, 0), (0, baseline, w, h))
    # Taper the two outer ends back to the sphere rim instead of leaving the
    # frame art's square texture edges beside the glass.
    for y in range(round(386 * sy), baseline):
        t = max(0.0, min(1.0, (y / sy - 386) / 114))
        taper = t * t * (3 - 2 * t)
        outer_x = w - 63 * sx * taper
        for x in range(max(0, round(outer_x - 2 * sx)), w):
            coverage = max(0.0, min(1.0, (outer_x - x - 0.5) / sx))
            for edge_x in (x, w - 1 - x):
                r, g, b, a = px[edge_x, y]
                px[edge_x, y] = (r, g, b, round(a * coverage))
        # Pick up the fine carved rim on the new contour. The line eases into
        # the existing inner rim above and into the lower metal band below.
        head = max(0.0, min(1.0, (y / sy - 386) / 10))
        foot = max(0.0, min(1.0, (500 - y / sy) / 16))
        fade = head * head * (3 - 2 * head) * foot * foot * (3 - 2 * foot)
        for x in range(max(0, round(outer_x - 7 * sx)), min(w, round(outer_x))):
            inset = (outer_x - x - 0.5) / sx
            strength = 0.92 * fade * math.exp(-((inset - 3.0) / 1.8) ** 2)
            for edge_x in (x, w - 1 - x):
                r, g, b, a = px[edge_x, y]
                if a < 100:
                    continue
                px[edge_x, y] = (min(255, round(r + 55 * strength)),
                                 min(255, round(g + 57 * strength)),
                                 min(255, round(b + 60 * strength)), a)
    return out


def trim_upper_ornament(base, slots, native=False):
    """Trim each variant's own metal contour without moving any painted pixels.

    These points follow the actual highlighted edge in the 2048x512 work image,
    before the console is compacted. Alpha thresholds cannot remove these caps:
    they have the same opacity as the metal. Both finishes use the same contour.
    Frame0 also needs its old opaque bridge above the crest cleared. Its native
    circular seat and texture must never be replaced with another frame's patch.
    """
    import numpy as np

    contours = {
        0: [(406, 245), (424, 242), (428, 247), (432, 248), (440, 243),
            (448, 239), (454, 236), (457, 237), (459, 270), (464, 272),
            (472, 275), (480, 276), (488, 276), (492, 273), (496, 268),
            (508, 268), (512, 273), (516, 274), (524, 273), (530, 266),
            (536, 264), (540, 264), (548, 266), (556, 268), (564, 272),
            (572, 278), (580, 282), (588, 284), (640, 284)],
        1: [(406, 223), (420, 223), (422, 221), (424, 218), (428, 218),
            (432, 216), (436, 215), (438, 216), (439, 220), (440, 248),
            (444, 251), (448, 253), (452, 255), (456, 256)],
        2: [(406, 219), (420, 221), (422, 223), (424, 224), (428, 229),
            (432, 231), (436, 232), (440, 232), (444, 231), (448, 226),
            (452, 226), (456, 226)],
    }
    points = contours[slots]
    if native:
        # The traced contour is in console-warp coordinates. Map it back for
        # the untouched seat layer so its cleaned terminal uses the same rim.
        sx, sy = base.width / 788, base.height / 202
        original = []
        for x, y in points:
            hx = (x - base.width / 2) / sx
            weight = max(0.0, min(1.0, (240 - abs(hx)) / 20))
            weight = weight * weight * (3 - 2 * weight)
            original.append((x - hx * (3 / 220) * sx * weight, y - 4 * sy * weight))
        points = original
    left, right = math.floor(points[0][0]), math.ceil(points[-1][0])
    xs = np.arange(left, right, dtype=np.float64) + 0.5
    top = np.interp(xs, [p[0] for p in points], [p[1] for p in points])
    coverage = np.clip(np.arange(base.height)[:, None] + 1 - top, 0, 1)
    # Fade the correction into the already clean horizontal carving, below the
    # end of the upright terminal; do not leave a new vertical mask boundary.
    weight = np.clip((right - xs) / 6, 0, 1)
    coverage = 1 - (1 - coverage) * weight
    alpha = np.array(base.getchannel("A"))
    alpha[:, left:right] = np.rint(alpha[:, left:right] * coverage).astype("uint8")
    out = base.copy()
    out.putalpha(Image.fromarray(alpha))
    return out


def extend_xp_window(base, half_width):
    """Continue the frame's transparent XP slot through its old opaque end caps.

    Roth's opening stops near x=175 although the status bar runs farther out. Reuse the
    transparent interior and its fine vertical dividers so the fill and rested marker remain
    visible at both ends without replacing the rail above or below the slot.
    """
    out = base.copy()
    dst = out.load()
    src = base.load()
    w, h = base.size
    fw, fh, _, _ = PLACES["Frame"]
    for y in range(h):
        hy = fh - (y + 0.5) * fh / h
        if not 93 <= hy <= 102:
            continue
        for x in range(w):
            hx = (x + 0.5) * fw / w - fw / 2
            ax = abs(hx)
            if not 174.5 < ax < half_width - 1:
                continue
            # The dividers repeat at roughly 37 HUD units. Sample a complete interior
            # cell so the end extensions have the same alpha and edge shading.
            sample = ax - 37 * math.floor((ax - 100) / 37)
            if hx < 0:
                sample = -sample
            sx = round((sample + fw / 2) * w / fw - 0.5)
            dst[x, y] = src[sx, y]
    return out


def bottom_detail(base):
    """Sharper brass carving in the prepared bottom art's original transparency."""
    painted = Image.open(os.path.join(RELIEF_DIR, "bottom_relief.png")).convert("RGBA")
    painted = painted.crop((0, 490, 2172, 625)).resize((2048, 168), Image.LANCZOS)
    reference = Image.new("RGBA", base.size, (0, 0, 0, 0))
    reference.alpha_composite(painted, (0, 344))
    return detail_color(base, reference, Image.new("L", base.size, 182))


def bottom_art():
    """Upsample the prepared brass ornament for its wide runtime display."""
    im = Image.open(os.path.join(HERE, "tools", "bottom_base.tga")).convert("RGBA")
    im = im.resize(BOTTOM_TEX_SIZE, Image.LANCZOS)
    r, g, b, a = im.split()
    rgb = Image.merge("RGB", (r, g, b)).filter(
        ImageFilter.UnsharpMask(radius=1.0, percent=65, threshold=3))
    r, g, b = rgb.split()
    return Image.merge("RGBA", (r, g, b, a))


# Where Sphere.lua draws things, in Roth's units from the bottom middle of the screen: each piece's
# size and the middle of its bottom edge (Sphere.lua ART), the orbs' centres (ORB_X, ORB_Y) and
# their balls' radius (BALL / 2). The 206-unit orbs are about 10% larger than the former
# 187-unit size. Their centers also move outward to keep the corner wells unobstructed.
ORB_D = 206
ORB_X, ORB_Y = 332, 102 # statue seating retains its 12-unit offset from the runtime spheres
STATUE_ORB_Y = 85       # preserve the statues' original seating as the spheres rise
FRAME_ORB_X = 320       # the runtime orb centers used to trim the frame openings
FRAME_H = 202                  # Roth's 220, a little shorter: the rows fill its inside (Sphere.lua ART)
FRAME_TEX_SIZE = (2048, 512)  # work size; generated frame files crop 12 transparent rows from the bottom
FRAME_BOTTOM_CROP = 12
FRAME_CONSOLE_DROP = 10.0       # open this much world space above the center rail; bottom and orb seats stay fixed
BOTTOM_TEX_SIZE = (1024, 256) # original bottom ornament draws at 720 x 112
STATUE_Y = -2                  # the statues' bottom edge (soft in Roth's art) off the screen
PLACES = {"Frame": (788, FRAME_H, 0, 0),
          "Bottom": (720, 112, 0, 3)}  # the original shaped ornament below the rows
# The statues (tools/ornaments/winged.png, its two halves), facing the orbs: each STATUE_W wide
# (0.5.20: the griffin too, "proportionally similar" to the wind rider), their heads STATUE_IN over the orbs' outer lower
# edges, covering about 7-8% of each (the player: no more than 15%; 0.5.15 turned them to face out,
# wings on the orbs: "doesn't look good"), a shadow pad round each.
ORNAMENTS = os.path.join(HERE, "tools", "ornaments", "winged.png")
STATUE_W = 108.8               # 20% smaller than 136 for proportion testing
GRIFFIN_HEIGHT = 0.90           # bring its raised wing closer to the lion's scale, feet aligned
GRIFFIN_HEAD_DROP = 58          # stronger downward tilt from the neck toward the beak
GRIFFIN_BEAK_DROP = 12           # add a little depth along the beak's lower edge
GRIFFIN_HEAD_OPACITY = 0.68     # StatueRightClearHead*: the minimap's arrow shows through the griffin's
                                # head while Spheres' copy of it is off (the questArrow setting)
STATUE_IN = {"StatueLeft": 72, "StatueRight": 86}
                               # lion's head juts further than the griffin's: 8 less (0.5.19)
STATUE_OPTICAL_X = {"StatueLeft": 20, "StatueRight": -28}  # match Sphere.lua's balanced positions
STATUE_PAD = 6.4
BALL_R = ORB_D * 226 / 256 / 2  # Sphere.lua's glass radius
FRAME_CUT = BALL_R              # cut to the visible glass edge, not the backing
FRAME_EDGE_KEEP = 18.0          # retain engraved brass detail beside the visible glass curve
FRAME_EDGE_BLEND = 56.0         # fade the curved detail smoothly into the charcoal console
SOFT = 1.0                     # the cut's edge, smoothed over this much
SEAT_REACH = 7.0               # out to where the art stands this far off it
SEAT_SOFT = 1.2                # its edge on the glass, smoothed over this

# The left orb's two pieces (in ball radii, the ball's centre at 0, y up)
HEALTH_SHARE = 0.6             # of the ball's area; mana the rest
SEAM = 0.5                     # the fine joint between the glass pieces, in Roth's units
FILLET = 0.1                   # their corners' radius where they meet (0.22: "too much angle",
BEVEL = 0.36                   # how far the glass rounds into the centre join
BEVEL_DEPTH = 0.58             # and by how much of its height
FEATHER = 1.9                  # their edges along the seam fade over this much (Roth's units; 2.4 a bit too soft)
SEAM_CONTACT = 0.075          # narrow shade immediately inside the joined edges
SEAM_REFLECTION = 0.05        # faint neutral edge light on the split glass
OUTER_SEAM_LOWER_DIM = 0.22   # soften the large pieces' reflection toward the bottom
SPEC_FADE = 0.05               # the highlight fades out this close to the seam (ball radii; it sits by it)
GLINT_FADE = 3.0               # the sharp glint and bright edge fade in over this many BEVELs from the seam
SKY = (-0.3, 0.8, 0.52)        # the glass mirrors a window this way (gloss): its upper left
SKY_FROM, SKY_TO = 0.88, 0.95  # how far round from it the mirrored window shows, softening in
SKY_RIM = (0.84, 0.95)         # and kept in from the rim (a crescent, glass's look)
PIECE_GLOSS = 0.52             # restrained mirrored window and lower bounce
SPEC_AT = (-0.2, 0.58)         # the round highlight's place on the ball, just under the window
                               # (0.5.10: "a bit upper, to meet the glass reflection"); was where
                               # LIGHT put it, (-0.18, 0.40)
LIGHT = (-0.3235, 0.7189, 0.6152)  # from the top left, towards the viewer: the highlight at
                               # (-0.18, 0.40) of the ball, its upper left (0.5.8: "more up and left";
                               # 0.24, 0.27 to 0.5.6, 0.19, 0.33 in 0.5.7)
DESIGN_LIGHT = (-0.3235, 0.7189, 0.6152)  # the light the glass's placements were tuned under (SPEC_AT,
                               # SKY, OUTLINE_ARC, the rims, the lower shade): moving LIGHT turns them with
                               # it (light_frame; the simulator's light, 0.5.493). Keep it as it is.
MAP_SHINE = 0.48               # reduce white reflection over map pixels to retain terrain saturation
PIECE_SHINE = 0.60              # the health and mana pieces keep their stronger glass reflections
INNER_SHINE = 0.18              # the embedded sphere borrows its light from the outer glass
INNER_GLOSS = 0.08              # keep its window and lower bounce from reading as a second lamp
MAP_GLOSS = 0.12               # faint window reflection, so it does not wash out map colors
MAP_RIM = 0.36                 # a soft upper edge glint, kept restrained on the map
MAP_EDGE_LIGHT = 0.65          # the light along its rim, a third down with MAP_RIM (0.56 and 1 until
                               # 0.5.348, the player's: "too bright and blocking the cloudy movements")
# The glass sphere's own edge (0.5.350, the player's: "on the left top side, sphere should have a faded
# light gray outline indicating of it's glass nature ... there is like a black circle around the
# sphere"): a thin light line `GLASS_OUTLINE` strong at OUTLINE_RADIUS (ball radii, OUTLINE_WIDTH
# wide), along OUTLINE_ARC (degrees counter-clockwise from 3 o'clock: 1 o'clock round to 10),
# fading out over OUTLINE_SOFT degrees at each end. 0.5.354: "make the arc from 9:30 to 1:30
# o clock and strength to 0.11".
GLASS_OUTLINE = 0.11
OUTLINE_ARC = (60, 150)
OUTLINE_SOFT = 30
OUTLINE_RADIUS, OUTLINE_WIDTH = 0.976, 0.024
TOP_RIM_STRENGTH = 0.24        # soften the broad reflected rim beyond the thin glass outline
GLASS_RIM_SHADOW = (0.42, 0.70)  # the dark rim shadow along the lower edge: a whole ball's (the map's,
                               # the full health's), a split piece's
MANA_TOP_RIM = 1.2              # a small lift on the large mana vessel's upper edge
MANA_TOP_GLOW = 0.10            # broad reflected light across its upper-right glass
MANA_TOP_GLOW_WIDTH = 0.0622    # two-thirds of the previous 0.0933 radial spread
SEAM_BOW = 0.035               # gently bow the shared join so it reads as two shaped vessels
TOP_PINCH_START = 0.78         # only the upper meeting point opens to the world
TOP_PINCH_WIDTH = 5.0          # widest part of that small opening, in Roth's units
MANA_DETAIL = 1.8               # stronger fubble texture so the blue reads as liquid, not flat glass
STATUE_SHADOW = (3, -4, 3.5, 0.6)  # the statues' shadow: offset x, y, blur, alpha (down and right:
                                   # the light is top left, LIGHT)
STATUE_DARKS = 1.35            # their brightness to this power before the brass ramp: deeper shadows
STATUE_SATURATION = 0.78       # mute the gold without flattening the carved highlights
STATUE_BRIGHTNESS = 0.88       # keep the statues a little darker than the frame's brass ends
STATUE_BRONZE = (1.04, 0.96, 0.88)  # warm the muted finish while preserving its light and shade


def orbs(x=ORB_X):
    return ((-x, ORB_Y), (x, ORB_Y))


def socket(im, place, cut, centers=None):
    """Cut the frame artwork to the visible glass edge, with a softly sampled edge."""
    w, h, mid, bottom = place
    W, H = im.size
    sx, sy = w / W, h / H
    left = mid - w / 2
    src = im.load()
    out = im.copy()
    px = out.load()

    for y in range(H):
        hy = bottom + (H - y - 0.5) * sy
        for x in range(W):
            hx = left + (x + 0.5) * sx
            for cx, cy in centers or orbs():
                dx, dy = hx - cx, hy - cy
                d = math.hypot(dx, dy)
                if d >= cut:
                    continue
                r, g, b, a = src[x, y]
                keep = max(0.0, min(1.0, (d - (cut - SOFT)) / SOFT))
                a = a / 255 * keep
                px[x, y] = (r, g, b, int(a * 255 + 0.5))
                break
    return out


def seat(im, place, below=None, inner_bottom=0, centers=None, radius=BALL_R):
    """The art's edges round an orb brought in to its glass where they stand just off it: each
    texel in the band by the ball's edge that the art leaves open takes the colour of the art
    found a little further out along the same ray. The frame's ends were drawn for Roth's orbs:
    a thin sliver showed between the left orb's mana and the frame's arch (0.5.12). `below`: only
    under this height (the statues: their claws and bodies; their wings' fine edges streaked).
    `inner_bottom`: extra reach below the orb centres on the frame's inward-facing ends."""
    w, h, mid, bottom = place
    W, H = im.size
    sx, sy = w / W, h / H
    left = mid - w / 2
    src = im.load()
    out = im.copy()
    px = out.load()

    def at(hx, hy):
        x, y = int((hx - left) / sx), int(H - (hy - bottom) / sy)
        if 0 <= x < W and 0 <= y < H:
            return src[x, y]
        return None

    for y in range(H):
        hy = bottom + (H - y - 0.5) * sy
        if below is not None and hy > below:
            continue
        for x in range(W):
            hx = left + (x + 0.5) * sx
            if src[x, y][3] >= 200:
                continue
            for cx, cy in centers or orbs():
                dx, dy = hx - cx, hy - cy
                d = math.hypot(dx, dy)
                inward = abs(hx) < abs(cx) and hy < cy
                reach = SEAT_REACH + (inner_bottom if inward else 0)
                if not (radius - 1.0 <= d <= radius + reach):
                    continue
                step = 0.5
                while step <= reach:
                    c = at(cx + dx / d * (d + step), cy + dy / d * (d + step))
                    if c and c[3] >= 220:
                        a = max(0.0, min(1.0, (d - (radius - 1.0)) / SEAT_SOFT))  # soften the seated edge
                        r0, g0, b0, a0 = src[x, y]
                        a0 /= 255
                        oa = a + a0 * (1 - a)
                        col = [c[k] * a + (r0, g0, b0)[k] * a0 * (1 - a) for k in range(3)]
                        px[x, y] = tuple(int(v / oa) for v in col) + (int(oa * 255 + 0.5),)
                        break
                    step += 0.5
                break
    return out


def ornaments(head_opacity=1.0):
    """The two creatures cut out of their image: its background is a painted checkerboard of
    light greys (239 and 253), not transparency. Neutral light texels are background; edges
    partly so, the light unmixed out of them; the outermost texel shaved (a light fringe).
    `head_opacity` under 1: the griffin's head that see-through (GRIFFIN_HEAD_OPACITY)."""
    src = Image.open(ORNAMENTS).convert("RGB")
    W, H = src.size
    # The source griffin's raised wing is much taller than the lion's wing and
    # makes the pair look mismatched at the same creature width. Slightly
    # compress the griffin vertically, keeping its feet aligned. The uniform
    # resize preserves the feather detail and silhouette. Work before keying.
    half = W // 2
    griffin = src.crop((half, 0, W, H))
    shorter = int(round(H * GRIFFIN_HEIGHT))
    griffin = griffin.resize((griffin.width, shorter), Image.LANCZOS)
    canvas = Image.new("RGB", (half, H), (246, 246, 246))
    canvas.paste(griffin, (0, H - shorter))
    griffin = canvas
    # Tilt the head down locally: the beak end moves most, fading toward the neck and chest.
    def head_drop(x, y):
        hx = max(0.0, min(1.0, (610 - x) / 260))
        hx = hx * hx * (3 - 2 * hx)
        rise = max(0.0, min(1.0, (y - 300) / 55))
        fall = max(0.0, min(1.0, (560 - y) / 65))
        bx = max(0.0, min(1.0, (470 - x) / 110))
        bx = bx * bx * (3 - 2 * bx)
        by = max(0.0, min(1.0, (y - 470) / 50))
        by = by * by * (3 - 2 * by)
        return GRIFFIN_HEAD_DROP * hx * rise * fall + GRIFFIN_BEAK_DROP * bx * by * fall

    xs = sorted(set([0, half, 300, 340, 380, 420, 460, 500, 540, 580, 610, 640]))
    ys = sorted(set([0, 280, 320, 350, 380, 410, 440, 470, 500, 530, 570, H]))
    mesh = []
    for y0, y1 in zip(ys, ys[1:]):
        for x0, x1 in zip(xs, xs[1:]):
            mesh.append(((x0, y0, x1, y1),
                         (x0, y0 - head_drop(x0, y0), x0, y1 - head_drop(x0, y1),
                          x1, y1 - head_drop(x1, y1), x1, y0 - head_drop(x1, y0))))
    griffin = griffin.transform(griffin.size, Image.Transform.MESH, mesh,
                                 resample=Image.Resampling.BICUBIC)
    src.paste(griffin, (half, 0))
    px = src.load()
    out = Image.new("RGBA", (W, H))
    op = out.load()
    bg = 246
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            dist = max(bg - r, bg - g, bg - b, max(r, g, b) - min(r, g, b) - 12)
            a = max(0.0, min(1.0, (dist - 14) / 60))
            if a > 0:
                op[x, y] = tuple(max(0, min(255, int((v - (1 - a) * bg) / a))) for v in (r, g, b)) + (int(a * 255 + 0.5),)
    # Fade the head into the map without a visible cutout edge. The opacity reaches
    # head_opacity over the central head and eases back to full strength outside it.
    if head_opacity < 1:
        alpha = out.getchannel("A")
        ap = alpha.load()
        cx, cy = 580, 470  # coordinates in the right half of the source, after the head tilt
        rx, ry = 245, 180
        for y in range(H):
            for x in range(half, W):
                d = math.sqrt(((x - half - cx) / rx) ** 2 + ((y - cy) / ry) ** 2)
                t = max(0.0, min(1.0, (d - 0.72) / 0.48))
                fade = t * t * (3 - 2 * t)
                factor = head_opacity + (1 - head_opacity) * fade
                ap[x, y] = int(ap[x, y] * factor + 0.5)
        out.putalpha(alpha)
    r, g, b, a = out.split()
    out = Image.merge("RGBA", (r, g, b, Image.blend(a, a.filter(ImageFilter.MinFilter(3)), 0.6)))
    halves = (out.crop((0, 0, W // 2, H)), out.crop((W // 2, 0, W, H)))
    return [h.crop(h.split()[3].getbbox()) for h in halves]


def statue_places(head_opacity=1.0):
    """Each statue's texture area (Roth's units: width, height, middle of its bottom edge), the
    creature and its shadow pad, and the creature's own size."""
    left, right = ornaments(head_opacity)
    places = {}
    for name, im, side in (("StatueLeft", left, -1), ("StatueRight", right, 1)):
        k = STATUE_W / im.size[0]   # each as wide (the griffin was at the rider's scale, 7% narrower, to 0.5.19)
        w, h = im.size[0] * k, im.size[1] * k
        inner = side * (ORB_X + BALL_R - STATUE_IN[name])  # its head, over the orb's outer lower edge
        mid = inner + side * w / 2 + STATUE_OPTICAL_X[name]
        places[name] = (w + 2 * STATUE_PAD, h + 2 * STATUE_PAD, mid, STATUE_Y - STATUE_PAD)
    return places, (left, right)


def write_statues(say=False):
    """Both statues in both finishes, and the griffin again with its see-through head
    (StatueRightClearHead*, for while Spheres' own quest arrow is off)."""
    places, creatures = statue_places()
    for (name, place), im in zip(places.items(), creatures):
        for suffix, finish in (("", "brass"), ("Charcoal", "charcoal")):
            write(name + suffix, seat(statue(im, place, finish=finish), place, below=STATUE_ORB_Y - 10,
                                      centers=orbs(STATUE_ORB_Y)))  # keep the statue artwork stable
        if say:
            print("  %s = { %.1f, %.1f, %.1f, %.1f }, -- w, h, x, y: Sphere.lua ART" % ((name,) + place))
    places, creatures = statue_places(GRIFFIN_HEAD_OPACITY)
    place, im = places["StatueRight"], creatures[1]
    for suffix, finish in (("", "brass"), ("Charcoal", "charcoal")):
        write("StatueRightClearHead" + suffix, seat(statue(im, place, finish=finish), place,
                                                    below=STATUE_ORB_Y - 10, centers=orbs(STATUE_ORB_Y)))
    make_modern_statues()


def make_modern_statues():
    """Write the supplied Modern cutouts and the griffin's translucent head variant."""
    for name in ("StatueLeft", "StatueRight"):
        modern = load_modern(name).resize((512, 512), Image.Resampling.LANCZOS)
        write(name + "Modern", modern)
        if name == "StatueRight":
            # Keep the minimap's native quest arrow faintly visible through the griffin's face.
            mask = Image.new("L", modern.size, 0)
            ImageDraw.Draw(mask).polygon(((20, 245), (275, 245), (290, 300), (255, 370),
                                          (190, 405), (85, 398), (28, 368)), fill=255)
            mask = mask.filter(ImageFilter.GaussianBlur(8))
            alpha = modern.getchannel("A")
            alpha = ImageChops.multiply(alpha, Image.eval(mask, lambda v: 255 - int(v * 0.78)))
            modern.putalpha(alpha)
            write("StatueRightClearHeadModern", modern)


def statue(im, place, size=512, finish="brass"):
    """A statue in muted brass, its darks deepened, with its shadow under it, in a size x size texture
    standing for `place` (its creature in the middle, STATUE_PAD round it)."""
    w, h, _, _ = place
    r, g, b, a = im.split()
    lum = Image.merge("RGB", (r, g, b)).convert("L").point(lambda v: int(255 * (v / 255) ** STATUE_DARKS))
    brass = Image.merge("RGB", (lum.point(lambda v: LUT[v][0]), lum.point(lambda v: LUT[v][1]),
                                lum.point(lambda v: LUT[v][2])))
    gray = brass.convert("L").convert("RGB")
    muted = Image.blend(gray, brass, STATUE_SATURATION)
    art = Image.merge("RGBA", (*[c.point(lambda v, gain=gain: min(255, int(v * STATUE_BRIGHTNESS * gain)))
                                 for c, gain in zip(muted.split(), STATUE_BRONZE)], a))
    if finish == "charcoal":
        art = charcoal_frame(art)
    sx, sy = size / w, size / h                        # texels per unit
    cw, ch = int(round((w - 2 * STATUE_PAD) * sx)), int(round((h - 2 * STATUE_PAD) * sy))
    art = art.resize((cw, ch), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ox, oy, blur, strength = STATUE_SHADOW
    shade = Image.new("L", (size, size), 0)
    shade.paste(art.split()[3], (int(round(STATUE_PAD * sx + ox * sx)), int(round(STATUE_PAD * sy - oy * sy))))
    shade = shade.filter(ImageFilter.GaussianBlur(blur * (sx + sy) / 2)).point(lambda v: int(v * strength))
    out = Image.merge("RGBA", (Image.new("L", (size, size), 0),) * 3 + (shade,))
    out.alpha_composite(art, (int(round(STATUE_PAD * sx)), int(round(STATUE_PAD * sy))))
    return out


# --- the glass shapes: signed distance inside (positive) -------------------------------------
def split_x(share):
    """x left of which `share` of the unit disc's area lies."""
    lo, hi = -1.0, 1.0
    for _ in range(60):
        m = (lo + hi) / 2
        if 0.5 + (m * math.sqrt(1 - m * m) + math.asin(m)) / math.pi < share:
            lo = m
        else:
            hi = m
    return lo


# The shapes below take numpy arrays of points (a whole texture at once) as well as single points.
def ball(x, y):
    return 1 - np.hypot(x, y)


class Cut:
    """Where a ball is cut in two: at a (its radii) along the cut's normal, `angle` (radians) from
    +x (0: a vertical cut, "health" left), h either side (half the seam), the join bowed by `bow`,
    `radius` units to its radius (the feathered edge is in units). `edge(y)`, if given, is where the
    seam's middle runs instead (another ball's seam carried across this one)."""
    def __init__(self, a, h, bow, radius, angle=0.0, edge=None):
        self.a, self.h, self.bow, self.radius, self.edge = a, h, bow, radius, edge
        self.cos, self.sin = math.cos(angle), math.sin(angle)

    def centre(self, y):
        """The seam's middle at height y (along it), in this ball's radii."""
        return self.edge(y) if self.edge else self.a + self.bow * np.maximum(0.0, 1 - y * y)

    def turn(self, x, y):
        """A point across the cut (along its normal) and along it."""
        return x * self.cos + y * self.sin, -x * self.sin + y * self.cos


def big_cut():
    """The left orb: health 60% of the ball's area, mana the rest (HEALTH_SHARE, SEAM, SEAM_BOW)."""
    return Cut(split_x(HEALTH_SHARE), SEAM / BALL_R / 2, SEAM_BOW, BALL_R)


def piece(side, cut=None):
    """A piece's distance function: the ball cut by a vertical line, the corners rounded."""
    cut = cut or big_cut()
    a, h, bow = cut.a, cut.h, cut.bow

    def d(x, y):
        A = -ball(x, y)
        x, y = cut.turn(x, y)
        edge = (cut.centre(y) - h) if side == "health" else (cut.centre(y) + h)
        B = (x - edge) if side == "health" else (edge - x)
        u, v = np.maximum(A + FILLET, 0.0), np.maximum(B + FILLET, 0.0)
        return -(np.minimum(-FILLET, np.maximum(A, B)) + np.hypot(u, v))
    return d


def bounds_of(d, steps=800):
    """A shape's box in its ball's radii, all four sides (an angled cut isn't symmetric)."""
    at = -1 + 2 * np.arange(steps + 1) / steps
    x, y = np.meshgrid(at, at)
    inside = d(x, y) > 0
    xs, ys = x[inside], y[inside]
    pad = 1 / steps
    return (max(-1.0, float(xs.min()) - pad), min(1.0, float(xs.max()) + pad),
            max(-1.0, float(ys.min()) - pad), min(1.0, float(ys.max()) + pad))


def box(d, x0, x1):
    """The shape's bounding box: x0, x1 given, its top (it is symmetric about y = 0): its height
    at 401 places across, each found by halving."""
    x = x0 + (x1 - x0) * np.arange(401) / 400
    inside = d(x, np.zeros_like(x)) > 0
    lo, hi = np.zeros_like(x), np.ones_like(x)
    for _ in range(40):
        m = (lo + hi) / 2
        up = d(x, m) > 0
        lo, hi = np.where(up, m, lo), np.where(up, hi, m)
    return x0, x1, float(max(0.0, lo[inside].max(initial=0.0)))


def seam(side, cut=None):
    """How far inside a piece a point is from the seam (ball radii)."""
    cut = cut or big_cut()
    a, h, bow = cut.a, cut.h, cut.bow
    def distance(x, y):
        x, y = cut.turn(x, y)
        edge = cut.centre(y)
        return (edge - h - x) if side == "health" else (x - edge - h)
    return distance


def coverage(d, near_seam, pix, radius=BALL_R):
    """How much of a pixel the shape covers: its edge smoothed over a pixel, and along the seam
    faded over FEATHER (softer where the pieces meet; `radius` units to the ball's radius)."""
    def cover(x, y):
        c = np.clip(d(x, y) / pix + 0.5, 0.0, 1.0)
        if near_seam:
            u = np.clip(near_seam(x, y) / (FEATHER / radius), 0.0, 1.0)
            c = np.minimum(c, u * u * (3 - 2 * u))
        return c
    return cover


def pieces():
    a, h = split_x(HEALTH_SHARE), SEAM / BALL_R / 2
    return {"health": box(piece("health"), -1.0, a - h + SEAM_BOW), "mana": box(piece("mana"), a + h, 1.0)}


def normalize(x, y, z):
    n = np.sqrt(x * x + y * y + z * z)
    return x / n, y / n, z / n


def sphere(x, y):
    return np.sqrt(np.maximum(0.0, 1 - x * x - y * y))


def piece_height(side, cut=None):
    """A piece's glass: the ball's own curve, falling off towards the seam over BEVEL, by
    BEVEL_DEPTH of its height, along a smooth curve. Falling all the way (0.5.0-0.5.4) it stood
    nearly upright at the seam: its shade sat at its darkest across the rounding, then gave way to
    the light in a hard line ("a very sharp line between the shadow part and the other side")."""
    cut = cut or big_cut()
    a, h, bow = cut.a, cut.h, cut.bow

    def height(x, y):
        tx, ty = cut.turn(x, y)
        t = ((cut.centre(ty) - h) - tx) if side == "health" else (tx - (cut.centre(ty) + h))
        u = np.minimum(t, BEVEL) / BEVEL
        ease = 1 - (1 - u) ** 3  # steepest at the seam, easing flat (and straight) into the ball: no crease
        return np.where(t <= 0, 0.0, sphere(x, y) * (1 - BEVEL_DEPTH * (1 - ease)))
    return height


def span(bounds):
    """A box as x0, x1, y0, y1: (x0, x1, top) is symmetric about y = 0, or all four given."""
    return bounds if len(bounds) == 4 else (bounds[0], bounds[1], -bounds[2], bounds[2])


def grid(bounds, size):
    """A texture's pixel centres over a box (ball radii, y up): x and y, size x size arrays, row 0 the top;
    and the box's step a pixel, the larger way."""
    x0, x1, y0, top = span(bounds)
    sx, sy = (x1 - x0) / size, (top - y0) / size
    steps = np.arange(size) + 0.5
    x, y = np.meshgrid(x0 + steps * sx, top - steps * sy)
    return x, y, max(sx, sy)


def ramp(e0, e1, v):
    """smoothstep for arrays."""
    t = np.clip((v - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def rgba(r, g, b, a):
    """An image from four arrays of 0-255 (or single values for the colour)."""
    a = np.asarray(a)
    planes = [np.broadcast_to(np.asarray(c), a.shape) for c in (r, g, b, a)]
    return Image.fromarray(np.stack(planes, axis=-1).astype(np.uint8), "RGBA")


def seam_bridge(bounds, near_seam, radius, size):
    """Dark backing for the fine joint, including the space neither glass piece covers."""
    x, y, pix = grid(bounds, size)
    edge = np.clip(ball(x, y) / pix + 0.5, 0.0, 1.0)
    # near_seam is zero on this piece's edge; the joint's centre is
    # half the physical SEAM away from it, regardless of ball size.
    distance = radius * near_seam(x, y) + SEAM / 2
    end = 1 - ramp(0.92, 0.966, np.abs(y))
    alpha = 0.94 * np.exp(-(distance / 0.65) ** 2) * edge * end
    drawn = alpha > 0.002
    near_black = np.where(drawn, 4, 0)  # undrawn: (0, 0, 0, 0), as compositing reads it
    return rgba(near_black, near_black, near_black, np.where(drawn, np.round(255 * alpha), 0))


def light_frame():
    """The glass is lit from LIGHT; its placements (the highlight, the mirrored window, the outline's
    arc, the rims, the lower half's shade and edge shadow) were tuned under DESIGN_LIGHT. They turn
    with the light round the view (cos, sin of that turn) and the highlight moves out as the light
    goes low, in as it comes round in front (reach: SPEC_AT's distance from the centre is times this).
    At DESIGN_LIGHT: 1, 0, 1 exactly."""
    lx, ly, lz = normalize(*LIGHT)
    dx, dy, dz = normalize(*DESIGN_LIGHT)
    turn = math.atan2(ly, lx) - math.atan2(dy, dx)
    # the highlight sits halfway between the light and the eye (the half vector): its distance from
    # the centre is the sine of half the light's angle off the view
    reach = math.sin(math.acos(min(1.0, float(lz))) / 2) / math.sin(math.acos(min(1.0, float(dz))) / 2)
    if (lx, ly, lz) == (dx, dy, dz):
        return 1.0, 0.0, 1.0
    return math.cos(turn), math.sin(turn), reach


def glass(d, height, bounds, size=256, near_seam=None, shine=1.0, gloss=0.0, rim=1.0, radius=BALL_R,
          shade=True, edge_light=1.0, outline=0.0, surface_glow=0.0, bridge=False,
          seam_lower_dim=0.0, lower_fade=0.98, halo=0.0):
    """Specular glass reflections over a shape, leaving its color and texture unobscured.
    `edge_light`: the light along the rim where the glass turns away (the map's is lower:
    MAP_EDGE_LIGHT; named so: `edge` below is the map's sealed outer texels). `outline`: the glass's
    own edge catching the light on its upper left (GLASS_OUTLINE), a thin light line fading round.
    `lower_fade`: how much of its reflections the lower half loses (turned from the light); `halo`:
    light all round its rim, the top's brighter (the target sphere's: TARGET_EDGE_LIGHT).
    Every pixel at once (numpy). Where it says upper, lower, left or right: as lit by DESIGN_LIGHT,
    turned with LIGHT (light_frame: tx, ty are the point's place in that turned frame)."""
    x, y, pix = grid(bounds, size)
    cov = coverage(d, near_seam, pix, radius)(x, y)
    lx, ly, lz = normalize(*LIGHT)
    c, s_, reach = light_frame()
    tx, ty = x * c + y * s_, -x * s_ + y * c
    hx_, hy_ = SPEC_AT[0] * reach, SPEC_AT[1] * reach
    far = math.hypot(hx_, hy_)
    if far > 0.95:  # a grazing light: the highlight stays on the ball
        hx_, hy_ = hx_ * 0.95 / far, hy_ * 0.95 / far
    hz_ = math.sqrt(1 - hx_ * hx_ - hy_ * hy_)
    ux, uy, uz = normalize(*SKY)
    e = 0.003
    gx = (height(x + e, y) - height(x - e, y)) / (2 * e)
    gy = (height(x, y + e) - height(x, y - e)) / (2 * e)
    nx, ny, nz = normalize(-gx, -gy, 1)
    lit = np.maximum(0.0, nx * lx + ny * ly + nz * lz)
    # the highlight off the ball itself, not off a piece's fall-off towards the seam (there
    # it drew a streak along the seam): one round highlight, as on the whole ball
    bz = sphere(x, y)
    spec = np.maximum(0.0, tx * hx_ + ty * hy_ + bz * hz_)
    # along the seam no sharp glint or bright edge: they drew hard lines there (on the
    # mana's, which faces away from the light, the glint ran where its rounding turns back
    # to the light: faded out over GLINT_FADE bevels, 0.5.3)
    k = ks = 1.0
    seam_shadow = seam_glint = 0.0
    if near_seam:
        t = near_seam(x, y)
        u = np.clip(t / (BEVEL * GLINT_FADE), 0.0, 1.0)
        k = u * u * (3 - 2 * u)
        u = np.clip(t / SPEC_FADE, 0.0, 1.0)  # the round highlight: only off the very seam
        ks = u * u * (3 - 2 * u)
    radial = np.hypot(x, y)
    angle = np.degrees(np.arctan2(ty, tx))
    top_rim = np.exp(-((radial - 0.94) / 0.045) ** 2) * np.clip((ty - 0.04) / 0.62, 0.0, 1.0)
    # Let the broad top reflection taper off around 1:30 on the right, instead of
    # carrying the bright edge down toward 3 o'clock. The thin outline has its own arc.
    top_rim = np.where(tx > 0, top_rim * ramp(30, 45, angle), top_rim)
    mana_glow = 0.0
    if surface_glow:
        # Start the mana glint's fade around 2 o'clock so it blends into the
        # broader top rim instead of leaving a small gap near 1:30.
        upper_right = ramp(30, 60, angle) * (1 - ramp(90, 110, angle))
        mana_glow = np.where(radial > 0, surface_glow * upper_right
                             * np.exp(-((radial - 0.90) / MANA_TOP_GLOW_WIDTH) ** 2), 0.0)
    white = shine * np.minimum(1.0, 0.82 * spec ** 64 * ks + 0.08 * spec ** 7 +
                               0.30 * edge_light * (1 - nz) ** 2 * (0.35 + 0.65 * lit) * k +
                               (TOP_RIM_STRENGTH if not near_seam else TOP_RIM_STRENGTH * 0.75)
                               * top_rim * k * rim)
    white = np.minimum(1.0, white + mana_glow)
    if near_seam:
        # The shadow touches the translucent cut, then gives way to a narrow
        # neutral reflection on the rounded surface. A small lift at either end
        # follows the ball's curvature without widening the joint.
        end_light = 1 + 0.22 * ramp(0.45, 0.92, np.abs(y))
        seam_shadow = SEAM_CONTACT * np.exp(-((t - 0.019) / 0.019) ** 2) * end_light
        seam_glint = SEAM_REFLECTION * np.exp(-((t - 0.045) / 0.021) ** 2) * end_light
        seam_glint = seam_glint * (0.65 + 0.35 * shine)
        seam_glint = seam_glint * (1 - seam_lower_dim * ramp(0.0, 0.8, -ty))
    if gloss:
        # glass: the sky above mirrored in its upper part (a soft-edged window), and the
        # light coming back up through it along the bottom rim
        sky = tx * ux + ty * uy + bz * uz
        u = np.clip((sky - SKY_FROM) / (SKY_TO - SKY_FROM), 0.0, 1.0)
        v = np.clip((radial - SKY_RIM[0]) / (SKY_RIM[1] - SKY_RIM[0]), 0.0, 1.0)
        window = u * u * (3 - 2 * u) * (1 - v * v * (3 - 2 * v)) * ks
        bounce = np.maximum(0.0, -ty) ** 2 * (1 - bz) ** 2 * k
        white = np.minimum(1.0, white + gloss * (0.45 * window + 0.55 * bounce))
    # Shade the lower edges of every globe. Their tops stay clear while the lower
    # half turns away from the light into a soft, dark rim shadow.
    lower = np.clip((-ty + 0.04) / 0.58, 0.0, 1.0)
    white = white * (1 - lower_fade * lower)
    if halo:
        ring = np.exp(-((radial - 0.95) / 0.035) ** 2) * (0.55 + 0.45 * ramp(-1.0, 1.0, ty))
        white = np.minimum(1.0, white + halo * ring)
    side = 0.0
    if outline:
        a = angle % 360
        lo, hi = OUTLINE_ARC
        side = np.where((radial > 0) & (lo <= a) & (a <= hi),
                        ramp(lo, lo + OUTLINE_SOFT, a) * (1 - ramp(hi - OUTLINE_SOFT, hi, a)), 0.0)
        band = np.exp(-((radial - OUTLINE_RADIUS) / OUTLINE_WIDTH) ** 2)
        white = np.minimum(1.0, white + outline * side * band)
    rim_shadow = GLASS_RIM_SHADOW[0] if not near_seam else GLASS_RIM_SHADOW[1]
    dark = rim_shadow * np.exp(-((radial - 0.90) / 0.15) ** 2) * lower if shade else 0.0
    dark = np.maximum(dark, seam_shadow)
    if not near_seam and shade:
        # The circular rim shade thins out at the lower center of the map.
        # Bridge that small bright pocket into the existing shadow without
        # deepening the rim or changing the other two glass pieces.
        bottom = np.clip((-ty - 0.48) / 0.40, 0.0, 1.0)
        bottom = bottom * bottom * (3 - 2 * bottom)
        dark = np.maximum(dark, 0.12 * bottom)
        # Gently seal the minimap's zoom-sensitive outer texels without a visible
        # dark halo against the game world.
        edge = np.clip((radial - 0.952) / 0.032, 0.0, 1.0)
        edge = edge * edge * (3 - 2 * edge)
        dark = np.maximum(dark, 0.14 * edge * (1 - side))  # not under the outline
    light = white + seam_glint
    alpha = dark + light * (1 - dark)
    drawn = (cov > 0) & ((light > 0) | (dark > 0))
    with np.errstate(divide="ignore", invalid="ignore"):
        reflected = np.where(alpha > 0, np.minimum(255, np.floor(255 * light / alpha + 0.5)), 0)
    im = rgba(*(np.where(drawn, reflected, 0),) * 3, np.where(drawn, np.floor(np.minimum(1.0, alpha) * cov * 255 + 0.5), 0))
    if bridge:
        backing = seam_bridge(bounds, near_seam, radius, size)
        backing.alpha_composite(im)
        return backing
    return im


def shape_mask(d, bounds, size=256, near_seam=None, radius=BALL_R):
    x, y, pix = grid(bounds, size)
    v = np.floor(coverage(d, near_seam, pix, radius)(x, y) * 255 + 0.5)
    return rgba(v, v, v, v)


def liquid_base(side, bounds, size=256, cut=None):
    """Only the fill silhouette; all visible pattern is on animated overlays."""
    alpha = shape_mask(piece(side, cut), bounds, size, seam(side, cut),
                       cut.radius if cut else BALL_R).getchannel("A")
    white = Image.new("L", (size, size), 255)
    return Image.merge("RGBA", (white, white, white, alpha))


def fluid_flow(size=256):
    """A soft, low-contrast pattern of curved dark clouds for the animated liquid overlay."""
    alpha = Image.new("L", (size, size), 0)
    px = alpha.load()
    for j in range(size):
        y = j / size
        for i in range(size):
            x = i / size
            # Several broad, curved ribbons, offset and tilted so slow rotation is visible.
            field = (math.sin(2 * math.pi * (2.0 * y + 0.72 * x + 0.12 * math.sin(2 * math.pi * x))) +
                     0.48 * math.sin(2 * math.pi * (1.1 * y - 1.35 * x + 0.08 * math.sin(2 * math.pi * y))))
            # A broad smoothstep avoids the hard contour from the previous thresholded ribbon.
            t = max(0.0, min(1.0, (field - 0.04) / 1.28))
            cloud = t * t * (3 - 2 * t)
            px[i, j] = int(150 * cloud ** 1.25 + 0.5)
    alpha = alpha.filter(ImageFilter.GaussianBlur(1.25 * size / 256))
    white = Image.new("L", (size, size), 255)
    return Image.merge("RGBA", (white, white, white, alpha))


# The liquids' moving layers (Sphere.lua LIQUID_LAYERS) share three square textures, white with
# the pattern in alpha, tinted in game. Each is seen through a window turned and drifted, and
# lifted as the liquid regenerates (0.5.269), wrapping round: they tile seamlessly, shown with
# REPEAT. 0.5.259-0.5.268's didn't tile; these keep their density (mean alpha). Fluid: fractal noise read through a fractal
# displacement (ink in water), not strokes: drawn currents (0.5.258) looked painted on the glass.
LIQUID_TEX = 512


def noise_field(rng, size, cells, cells_y=None):
    """Smooth value noise that tiles, as a flat row-major array of floats: a random grid (cells
    across, cells_y down) laid three times each way, enlarged bicubically, and its middle cut out
    at a random offset, so it wraps seamlessly and octaves don't share a lattice."""
    cy = cells_y or cells
    values = [rng.random() for _ in range(cells * cy)]
    grid = Image.new("F", (3 * cells, 3 * cy))
    grid.putdata([values[(j % cy) * cells + i % cells] for j in range(3 * cy) for i in range(3 * cells)])
    big = grid.resize((3 * size, 3 * size), Image.Resampling.BICUBIC)
    ox, oy = size + rng.randrange(size // cells), size + rng.randrange(size // cy)
    return array.array("f", big.crop((ox, oy, ox + size, oy + size)).tobytes())


def stretch(values, lo_q=0.01, hi_q=0.99):
    """Values rescaled so their lo_q and hi_q quantiles reach 0 and 1, clamped."""
    ranked = sorted(values)
    lo, hi = ranked[int(lo_q * (len(ranked) - 1))], ranked[int(hi_q * (len(ranked) - 1))]
    k = 1 / (hi - lo)
    return [min(1.0, max(0.0, (v - lo) * k)) for v in values]


def fractal(rng, size, cells, octaves, gain=0.5, cells_y=None):
    """Octaves of noise_field, each twice as fine and gain as strong, stretched to 0-1."""
    total = [0.0] * (size * size)
    weight = 1.0
    for i in range(octaves):
        layer = noise_field(rng, size, cells * 2 ** i, (cells_y or cells) * 2 ** i)
        total = [t + weight * v for t, v in zip(total, layer)]
        weight *= gain
    return stretch(total)


def lookup(field, size, x, y):
    """Bilinear lookup in a flat size x size field, wrapping round (it tiles)."""
    x, y = x % size, y % size
    i, j = int(x), int(y)
    fx, fy = x - i, y - j
    i1, j1 = (i + 1) % size, (j + 1) % size
    row, row1 = j * size, j1 * size
    a = field[row + i] + (field[row + i1] - field[row + i]) * fx
    b = field[row1 + i] + (field[row1 + i1] - field[row1 + i]) * fx
    return a + (b - a) * fy


def warped(rng, size, cells, octaves, amount, stretch_y=1.0, warp_cells=3):
    """Fractal noise read through a fractal displacement of `amount` of the size: the curls and
    folds of ink in water. stretch_y under 1 draws it out along y (rising currents): fewer cells
    down than across, so it still tiles."""
    qx = fractal(rng, size, warp_cells, 4)
    qy = fractal(rng, size, warp_cells, 4)
    base = fractal(rng, size, cells, octaves, cells_y=max(1, round(cells * stretch_y)))
    a = amount * size
    out = [0.0] * (size * size)
    for j in range(size):
        for i in range(size):
            k = j * size + i
            out[k] = lookup(base, size, i + a * (qx[k] - 0.5), j + a * (qy[k] - 0.5))
    return out


def smoothstep(e0, e1, v):
    t = min(1.0, max(0.0, (v - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def white_alpha(values, size):
    alpha = Image.new("L", (size, size))
    alpha.frombytes(bytes(round(255 * min(1.0, max(0.0, v))) for v in values))
    white = Image.new("L", (size, size), 255)
    return Image.merge("RGBA", (white, white, white, alpha))


_CLOUD_FIELDS = {}


def liquid_cloud_field(size=LIQUID_TEX):
    """The warped field (0-1, tiling) LiquidCloud's billows are cut from; the map's smoke reads it
    too (map_cloud, map_tendrils)."""
    if size not in _CLOUD_FIELDS:
        _CLOUD_FIELDS[size] = warped(random.Random(7), size, 4, 5, 0.4)
    return _CLOUD_FIELDS[size]


def liquid_cloud(size=LIQUID_TEX):
    """Billows: soft masses with curled, marbled edges (the dark clouds, the light ones, and the
    mana's purple)."""
    v = liquid_cloud_field(size)
    # 0.35: the tiling noise sits higher than 0.5.259's; this keeps its density (mean alpha 0.27)
    return white_alpha([smoothstep(0.35, 1.0, x) ** 1.4 for x in v], size)


def pattern_at(field, u, v, tiles, turn, offset):
    """A liquid's tiling field (liquid_cloud_field, liquid_fine_field) at (u, v) in -0.5..0.5 of a
    texture: the field turned by `turn`, `tiles` times across it, moved by `offset` (fractions of
    the field)."""
    c, s = math.cos(turn), math.sin(turn)
    x, y = (c * u - s * v) * tiles + offset[0], (s * u + c * v) * tiles + offset[1]
    return lookup(field, LIQUID_TEX, x * LIQUID_TEX, y * LIQUID_TEX)


def liquid_stream(size=LIQUID_TEX):
    """Currents: smoky wisps drawn out along y, where the warped field folds over its middle,
    fading in and out along their length."""
    rng = random.Random(37)
    v = warped(rng, size, 5, 5, 0.5, stretch_y=0.4)
    reach = fractal(rng, size, 3, 3)
    grain = fractal(rng, size, 24, 2)
    out = []
    for x, f, n in zip(v, reach, grain):
        ridge = 1 - abs(2 * x - 1)
        out.append(ridge ** 6 * smoothstep(0.1, 0.6, f) * (0.6 + 0.4 * n))
    return white_alpha(out, size)


_FINE_FIELDS = {}


def liquid_fine_field(size=LIQUID_TEX):
    """The warped field (0-1, tiling) LiquidFine's swirls are cut from; two of the map's smoke
    rings read it too (map_cloud)."""
    if size not in _FINE_FIELDS:
        _FINE_FIELDS[size] = warped(random.Random(41), size, 14, 3, 0.12, warp_cells=7)
    return _FINE_FIELDS[size]


def liquid_fine(size=LIQUID_TEX):
    """Fine turbulence: small swirls, so the liquid never looks flat between the clouds."""
    v = liquid_fine_field(size)
    return white_alpha([smoothstep(0.22, 1.0, x) ** 1.3 for x in v], size)


LIQUID_SHADE = (0.72, 0.35)  # the liquid's bottom shadow and outer-edge shade, at their darkest


def liquid_shade(side, bounds, size=256, cut=None, d=None):
    """Depth in a piece's liquid (0.5.259: "add some shadow to the bottom end"): its lower part
    falls into shadow, deepest at the bottom, and its outer edge darkens a little more lower
    down. Black, the strength in alpha, cut to the piece; over the moving layers, under the glass."""
    x, y, pix = grid(bounds, size)
    if d:  # a whole ball (the pet's)
        cover = coverage(d, None, pix)
    else:
        cover = coverage(piece(side, cut), seam(side, cut), pix, cut.radius if cut else BALL_R)
    cov = cover(x, y)
    bottom_alpha, rim_alpha = LIQUID_SHADE
    t = np.clip((0.1 - y) / 1.05, 0.0, 1.0)
    bottom = t ** 1.6
    rim = ramp(0.7, 1.0, np.hypot(x, y)) * (0.35 + 0.65 * t)
    a = 1 - (1 - bottom_alpha * bottom) * (1 - rim_alpha * rim)
    return rgba(0, 0, 0, np.where(cov > 0, np.round(255 * a * cov), 0))


def liquid_glint(size=64):
    """One tiny soft glint carried up through the mana: a core, a glow, very short rays (a glint
    in the liquid, not a star icon)."""
    c = (size - 1) / 2
    k = size / 21  # drawn on 21 px in 0.5.258's full-piece ManaSpark files
    alpha = Image.new("L", (size, size), 0)
    ap = alpha.load()
    for y in range(size):
        for x in range(size):
            dx, dy = (x - c) / k, (y - c) / k
            radial = math.hypot(dx, dy)
            glow = 54 * math.exp(-((radial / 4.4) ** 2))
            core = 190 * math.exp(-((radial / 1.05) ** 2))
            ray = 58 * math.exp(-((dx / 0.65) ** 2)) * math.exp(-((dy / 3.0) ** 2))
            ray += 42 * math.exp(-((dy / 0.65) ** 2)) * math.exp(-((dx / 2.4) ** 2))
            edge = smoothstep(c, c - 3 * k, max(abs(x - c), abs(y - c)))
            ap[x, y] = min(255, int((glow + core + ray) * edge + 0.5))
    return Image.merge("RGBA", (Image.new("L", (size, size), 255),) * 3 + (alpha,))


# The liquid's surface (0.5.263, in place of Roth's OrbSpark: a soft glow half over the level,
# "a ghosty layer ... a glow with no real purpose"). Drawn, not masked: in game it stays pinned to
# the level and only its texture coordinates move (0.5.264 moved a mask pinned to the hidden level
# every frame: the client moved it only when the level changed, the waves stood still and jumped).
# Sphere.lua SURFACE: keep these in step.
SURFACE_WAVELENGTH = 56.0  # units; the strips span SURFACE_PERIODS of them and scroll by up to
SURFACE_PERIODS = 3        # one, so 2 must cover the widest piece (the health's 108)
SURFACE_CREST = 2.2        # the crests' height over the level; the troughs sit on it (0.5.263's
                           # 4, sharpened, 37 apart: "like mountain edges")
SURFACE_PAD = 3.0          # the strips' top over the level: a crest and a soft edge
SURFACE_FADE = 8.0         # the crest strip's liquid fades into the moving layers over this
SURFACE_GLOW = 12.0        # the light reaches this far under the level (0.5.264's 5: "very thin")


def wave(u):
    """The surface's height over one wavelength (u 0-1), 0 at the troughs to 1 at the crests:
    a rolling swell, a faint second harmonic keeping its crests from looking drawn."""
    def raw(t):
        return math.sin(2 * math.pi * t) + 0.18 * math.sin(4 * math.pi * t + 1.3)
    samples = [raw(i / 720) for i in range(720)]
    lo, hi = min(samples), max(samples)
    return (raw(u) - lo) / (hi - lo)


def surface_strip(depth, alpha_at, width=512, height=64):
    """A strip from SURFACE_PAD over the level to `depth` under it, spanning SURFACE_PERIODS waves:
    alpha_at(d, f) for d units under the wave's edge, f its height there (0-1); white."""
    span_x = SURFACE_WAVELENGTH * SURFACE_PERIODS
    span_y = SURFACE_PAD + depth
    alpha = Image.new("L", (width, height))
    px = alpha.load()
    for i in range(width):
        f = wave(((i + 0.5) / width * span_x / SURFACE_WAVELENGTH) % 1)
        edge = SURFACE_CREST * f
        for j in range(height):
            y = SURFACE_PAD - (j + 0.5) / height * span_y  # over the level
            px[i, j] = round(255 * min(1.0, max(0.0, alpha_at(edge - y, y, f))))
    white = Image.new("L", (width, height), 255)
    return Image.merge("RGBA", (white, white, white, alpha))


def surface_crest():
    """The waves' liquid: solid from their edge down to the level (the crests over the moving
    layers' flat top), then fading into those layers, so the surface reads as a body of liquid."""
    def alpha(d, y, f):
        top = min(1.0, max(0.0, d / 0.6 + 0.5))  # the edge, softened over a little over half a unit
        return top * (1 - smoothstep(0.0, SURFACE_FADE, -y))
    return surface_strip(SURFACE_FADE, alpha)


def surface_line():
    """Light under the waves' edge: brightest just under it and on the crests, then a long soft
    fall into the liquid (0.5.264's band was "very thin")."""
    def alpha(d, y, f):
        edge = smoothstep(-0.3, 0.6, d)
        line = 0.75 * math.exp(-((d - 1.2) / 1.8) ** 2)
        glow = 0.5 * math.exp(-max(d, 0.0) / 3.8) * (1 - smoothstep(5.0, SURFACE_GLOW - 0.5, d))
        return (line + glow) * edge * (0.8 + 0.2 * f)
    return surface_strip(SURFACE_GLOW, alpha)


# The pet's orb (0.5.271, the player's reference art; 0.5.270 docked a small sphere on the rim):
# a ball in the middle of the left orb, in front of a cavity in its pieces. Whole for
# a pet without mana, cut in two for one with along the left orb's own seam (0.5.280; 0.5.273-0.5.279
# cut it at 45 degrees). Its textures are over its own ball
# (radius 1, or each half's box). It sits in a concave dent in the pieces: their liquid seen behind
# it (PetCavity), the dent's walls as light and shade on their glass (PetBowl), no gap to the world.
# Sphere.lua PET: keep in step.
PET_R = 0.4275                 # the pet's ball, in the left orb's ball radii (0.5.271's 0.57: "too big")
PET_AT = (27.0, 8.0)           # the scoop's and the ball's centre, units right and up of the left orb's:
                               # far enough right that the left orb's seam cuts the ball about a quarter
                               # of its radius left of its centre (0.5.283: health and mana swapped,
                               # "a nice off centered look", "maintain the bigger part on the health";
                               # 0.5.280-0.5.282: 8, 8, the seam a quarter right of it)
PET_ROLES = {"health": "Mana", "mana": "Health"}  # the cut's left piece is the pet's mana, its right its health
PET_BEHIND = 0.8               # your liquid behind the pet's ball, seen through it, a little dimmer (deeper)
PET_BOWL = 7.0                 # units the cavity's concave wall shows round the ball (0.5.278: no gap,
                               # "those sections in the outer sphere parts have a concave form creating
                               # the space"; 0.5.276-0.5.277 cut a ring to the world: "I still see the
                               # god damn background")
PET_TEX_BOWL = 256
PET_BOWL_SHADE = (0.22, 0.34)  # the dent's shade all over, and its softer contact shadow
                               # (0.5.281: "more shadow overall, but even more around the gap")
PET_BOWL_HIGHLIGHT = (0.34, 0.10)  # keep the cavity wall and lip from shining through the ball
PET_BOWL_ARC_SHADOW = (0.18, 0.7)  # extra contact shadow from 2 to 7, with the same edge falloff


def bowl_radius():
    """The cavity's rim, in units from the left orb's centre."""
    return BALL_R * PET_R + PET_BOWL
PET_TEX = 256


def pet_cut():
    """The pet's halves: cut upright along the left orb's own seam where it crosses the ball (0.5.280:
    "vertical separation again ... align the separation with the outer spheres separation"; 0.5.273
    cut it at 45 degrees), the same width and fillet: mana the smaller left part, health the bigger
    right (PET_ROLES, 0.5.283)."""
    radius = BALL_R * PET_R
    big = big_cut()

    def edge(y):
        gy = (PET_AT[1] + y * radius) / BALL_R
        return (BALL_R * big.centre(gy) - PET_AT[0]) / radius
    return Cut(0.0, SEAM / radius / 2, 0.0, radius, edge=edge)


def pet_pieces():
    cut = pet_cut()
    return {side: bounds_of(piece(side, cut)) for side in ("health", "mana")}


def pet_cavity(size=512, at=PET_AT, ratio=PET_R):
    """A mask over the left orb's ball for its liquids (0.5.275: the pet's ball "is sitting in front
    of the cavity", your liquid seen behind it): whole, but PET_BEHIND behind the ball. `at` and
    `ratio`: another ball's place and size (the target sphere's, TargetCavity)."""
    rb = BALL_R * ratio
    mask = Image.new("L", (size, size), 0)
    px = mask.load()
    for j in range(size):
        y = (1 - (j + 0.5) * 2 / size) * BALL_R
        for i in range(size):
            x = ((i + 0.5) * 2 / size - 1) * BALL_R
            behind = 1 - smoothstep(rb - 1.5, rb, math.hypot(x - at[0], y - at[1]))
            px[i, j] = round(255 * (1 - (1 - PET_BEHIND) * behind))
    return Image.merge("RGBA", (mask, mask, mask, mask))


# The target's sphere (0.5.468, experimental, Sphere.lua TARGET): your orb's pieces, smaller, with its
# portrait's ball in the very centre, `TARGET_AVATAR` of the ball's radius; its liquids cut round it.
TARGET_AVATAR = 0.55  # 0.47 in 0.5.468 (0.5.469, the player's: "increase the avatar picture a little to take
                      # sphere out from the focus")


def target_cavity():
    return pet_cavity(at=(0.0, 0.0), ratio=TARGET_AVATAR)


CRACK_CAVITY_SOFT = 2.5  # units over which a crack fades out at the scoop's rim (Sphere.lua CRACK)


def crack_cavity(size=512):
    """A mask over the left orb's ball for its cracks (0.5.464, the player's: with the inner sphere
    "it should also warp with the cutouts structure"): whole, but nothing inside the scoop's rim, so
    a crack stops there as at the seam (the level it breaks at is hidden from Lua: no bending)."""
    rim = bowl_radius()
    mask = Image.new("L", (size, size), 0)
    px = mask.load()
    for j in range(size):
        y = (1 - (j + 0.5) * 2 / size) * BALL_R
        for i in range(size):
            x = ((i + 0.5) * 2 / size - 1) * BALL_R
            px[i, j] = round(255 * smoothstep(rim - CRACK_CAVITY_SOFT, rim, math.hypot(x - PET_AT[0], y - PET_AT[1])))
    return Image.merge("RGBA", (mask, mask, mask, mask))


def pet_back(size=PET_TEX):
    """The pet's ball's own dark glass, as the left orb's empty glass (GLASS): while it stands
    beside the left orb (Sphere.lua PET.inside false) nothing else is behind it."""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = im.load()
    pix = 2 / size
    for j in range(size):
        y = 1 - (j + 0.5) * pix
        for i in range(size):
            x = (i + 0.5) * pix - 1
            c = max(0.0, min(1.0, (1 - math.hypot(x, y)) / pix + 0.5))
            if c > 0:
                px[i, j] = (GLASS[0], GLASS[1], GLASS[2], round(GLASS[3] * c))
    return im


def pet_bowl(size=PET_TEX_BOWL):
    """The scoop as light and shade on the pieces' glass (0.5.279: "use the scooped sphere parts for
    health and mana"; the liquid continues inside it, never the world; darkened with black, never
    with less liquid, PET_BOWL_SHADE): a concave dent out to bowl_radius() (the texture's
    edge), lit from the top left (LIGHT): its lower right inner wall faces the light, its upper left
    turns from it; its lip catches a soft line of light. Over the pieces' glass, under the pet's.
    Its lower right shadow turns with the light (light_frame)."""
    lx, ly, lz = normalize(*LIGHT)
    c, s_, _ = light_frame()
    rim = 1.0  # the bowl's rim, in the texture's radii
    depth = 0.55  # how deep it reads: the walls' slope at the rim
    inner = BALL_R * PET_R / bowl_radius()  # the pet's ball's edge, in the texture's radii
    base, contact = PET_BOWL_SHADE
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = im.load()
    pix = 2 / size
    for j in range(size):
        y = 1 - (j + 0.5) * pix
        for i in range(size):
            x = (i + 0.5) * pix - 1
            r = math.hypot(x, y)
            if r >= rim:
                continue
            # a paraboloid dent, its walls steepest at the rim, easing flat into the glass there
            ease = 1 - smoothstep(0.82, 1.0, r)
            gx, gy = 2 * depth * x * ease, 2 * depth * y * ease  # the surface rises outwards
            nx, ny, nz = normalize(-gx, -gy, 1.0)
            lit = nx * lx + ny * ly + nz * lz
            light = max(0.0, lit - lz)
            shadow = max(0.0, lz - lit)
            lip = math.exp(-((r - 0.9) / 0.05) ** 2) * max(0.0, (x * lx + y * ly) / r if r else 0.0) * -1
            white = min(1.0, PET_BOWL_HIGHLIGHT[0] * light + PET_BOWL_HIGHLIGHT[1] * max(0.0, lip))
            # shade all over the dent, easing out at its lip; deepest in the gap by the pet's ball,
            # falling off up the wall (and a little under the ball's edge, seen through its glass).
            all_over = base * (1 - smoothstep(0.9, 1.0, r))
            arc_strength, arc_power = PET_BOWL_ARC_SHADOW
            arc = max(0.0, math.cos(math.atan2(-x * s_ + y * c, x * c + y * s_) + math.pi / 6)) ** arc_power
            contact_here = contact + arc_strength * arc
            gap = contact_here * math.exp(-((r - inner - 0.02) / (0.06 if r > inner else 0.04)) ** 2)
            dark = min(0.85, 1 - (1 - min(0.55, 1.4 * shadow)) * (1 - all_over) * (1 - gap))
            alpha = dark + white * (1 - dark)
            if alpha <= 0.003:
                continue
            v = round(255 * white / alpha) if alpha else 0
            px[i, j] = (v, v, v, round(255 * min(1.0, alpha)))
    return im


def pet_contact_shadow(side=None, size=PET_TEX):
    """Dark contact outside the embedded ball; a status bar reveals it with its liquid."""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = im.load()
    inner = BALL_R * PET_R / bowl_radius()
    cut = pet_cut()
    pix = 2 / size
    for j in range(size):
        y = 1 - (j + 0.5) * pix
        lower = 1 - smoothstep(-0.08, 0.24, y)
        if lower <= 0:
            continue
        for i in range(size):
            x = (i + 0.5) * pix - 1
            r = math.hypot(x, y)
            if r >= 1 + pix or r <= inner - pix:
                continue
            edge = math.exp(-((r - inner - 0.043) / 0.072) ** 2)
            coverage = smoothstep(inner, inner + pix, r) * (1 - smoothstep(0.93, 1.0, r))
            split = 1.0
            if side:
                seam = cut.centre(max(-1, min(1, y / inner))) * inner
                right = smoothstep(seam - pix, seam + pix, x)
                split = right if side == "mana" else 1 - right
            alpha = lower * coverage * split * 0.62 * edge
            if alpha > 0.003:
                px[i, j] = (0, 0, 0, round(255 * min(0.62, alpha)))
    return im


def pet_contact_base(size=PET_TEX):
    """A small bottom arc that joins the liquid shade as the embedded ball fills."""
    shadow = pet_contact_shadow(size=size)
    px = shadow.load()
    pix = 2 / size
    for j in range(size):
        for i in range(size):
            r, g, b, alpha = px[i, j]
            if alpha:
                x = (i + 0.5) * pix - 1
                strength = 0.55 * math.exp(-(x / 0.25) ** 4)
                px[i, j] = (r, g, b, round(alpha * strength))
    return shadow


def make_pet_contact_shadows():
    write("PetContactBase", pet_contact_base())
    write("PetContactShadow", pet_contact_shadow())
    for side in ("health", "mana"):
        write("PetContactShadow" + PET_ROLES[side], pet_contact_shadow(side))


def make_pet():
    whole = (-1.0, 1.0, 1.0)
    # No broad depth shading on the pet's ball, liquid or glass (0.5.274: "shouldn't have shadow
    # at the bottom. It's creating a donut effect"). The contact shade stays outside the ball.
    write("FillPet", white_alpha_image(shape_mask(ball, whole, PET_TEX)))
    write("MaskPet", shape_mask(ball, whole, PET_TEX))
    make_pet_glass()
    cut = pet_cut()
    for side, bounds in pet_pieces().items():
        name = "Pet" + PET_ROLES[side]
        d = piece(side, cut)
        write("Fill" + name, liquid_base(side, bounds, PET_TEX, cut))
        write("Mask" + name, shape_mask(d, bounds, PET_TEX, seam(side, cut), cut.radius))
        print("  %s = { %.4f, %.4f, %.4f, %.4f }, -- x0, x1, y0, y1 (its ball's radii): Sphere.lua PET pieces"
              % ((PET_ROLES[side].lower(),) + bounds))
    write("PetCavity", pet_cavity())
    write("TargetCavity", target_cavity())
    make_target_glass()
    write("PetBack", pet_back())
    make_pet_bowl()
    make_pet_contact_shadows()
    write("FillNone", Image.new("RGBA", (8, 8), (255, 255, 255, 0)))


def make_pet_glass():
    whole = (-1.0, 1.0, 1.0)
    write("GlassPet", glass(ball, sphere, whole, size=PET_TEX, shine=INNER_SHINE, gloss=INNER_GLOSS,
                            shade=False, outline=GLASS_OUTLINE))
    cut = pet_cut()
    for side, bounds in pet_pieces().items():
        name = "Pet" + PET_ROLES[side]
        d = piece(side, cut)
        write("Glass" + name, glass(d, piece_height(side, cut), bounds, size=PET_TEX, near_seam=seam(side, cut),
                                    shine=INNER_SHINE, gloss=INNER_GLOSS, radius=cut.radius, shade=False,
                                    outline=GLASS_OUTLINE, bridge=side == "health"))


def white_alpha_image(mask):
    """A white texture with `mask`'s alpha."""
    white = Image.new("L", mask.size, 255)
    return Image.merge("RGBA", (white, white, white, mask.getchannel("A")))


def make_liquids():
    for side, bounds in pieces().items():
        write("Fill" + side.capitalize(), liquid_base(side, bounds))
    make_piece_shades()
    write("LiquidCloud", liquid_cloud())
    write("LiquidStream", liquid_stream())
    write("LiquidFine", liquid_fine())
    write("LiquidGlint", liquid_glint())
    write("SurfaceCrest", surface_crest())
    write("SurfaceLine", surface_line())
    make_pet()


def map_mask(size=256):
    """Fade only the map's outer 5% into the dark backing, inside a safe inset edge."""
    im = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    px = im.load()
    center = size / 2
    # Leave a narrow safety margin inside the map's own zoom-scaled edge. The minimap's
    # texture can expose patterned transparent texels at some zooms if the mask reaches
    # the frame boundary; this inset keeps those texels outside the visible circle.
    radius = size / 2 - 3.0
    fade = radius * 0.05
    for j in range(size):
        for i in range(size):
            distance = math.hypot(i + 0.5 - center, j + 0.5 - center)
            t = max(0.0, min(1.0, (radius - distance) / fade))
            alpha = round(255 * t * t * (3 - 2 * t))
            px[i, j] = (alpha, alpha, alpha, alpha)
    return im


# The map's smoke rings (MapCloud1-5): black and charcoal, each its own strength (`opacity`) and
# its own window on a liquid's pattern (pattern_at: `tiles`, `turn`, `offset`), cut at `cut` (mean
# alpha after it). 0.5.341, the player's: "change minimap cloud layer texture to our liquid cloud
# texture ... preserving their transparency and color scheme": LiquidCloud's billows, each ring
# keeping the mean alpha of 0.5.340's (value noise with angular curls). 0.5.342: "add 1 more layer
# but this time make it with fine liquid texture, also convert one of the existing ring to have
# fine liquid pattern": the lightest charcoal ring (its mean kept) and a fifth, near black, in
# LiquidFine's swirls, at about their size in the liquids (1.8 across the globe). `reach`: where
# a ring starts fading in, in map radii: the thick billows with MapDissolve (MAP_FADE_START), the
# thin swirls 0.10 further in (0.5.345, the player's: "the thin cloud layers go a little bit
# inwards compared to the thick ones as they won't distort the map too much on the edges").
# 0.5.347 pulled all of them, and the black fade, out from 0.80 (thin 0.70) to 0.85 (0.75): "pull
# all of them a little behind to give a little more visibility to the map".
MAP_FADE_START = 0.85
MAP_CLOUDS = (
    ((0, 0, 0), 0.74, 0.146, 2.2, 0.0, (0.13, 0.71), "cloud", MAP_FADE_START),
    ((49, 51, 54), 0.62, 0.044, 2.6, 1.9, (0.58, 0.22), "cloud", MAP_FADE_START),
    ((3, 4, 5), 0.60, 0.250, 3.0, 3.7, (0.37, 0.49), "cloud", MAP_FADE_START),
    ((57, 60, 63), 0.44, 0.241, 1.8, 5.1, (0.81, 0.93), "fine", MAP_FADE_START - 0.10),
    ((8, 9, 10), 0.60, 0.230, 1.8, 2.6, (0.27, 0.64), "fine", MAP_FADE_START - 0.10),
)
CLOUD_SOFT = 0.65          # LiquidCloud's: its billows fade in over this much of the field
# each pattern as its liquid texture cuts it: the field, how far its edges fade in, their curve
PATTERNS = { "cloud": (liquid_cloud_field, CLOUD_SOFT, 1.4), "fine": (liquid_fine_field, 0.78, 1.3) }


def map_cloud(index, size=512, cut=None):
    """Layered smoke fading in across the map's outer part (`reach`: the outer 15% for the thick
    rings, as MapDissolve; 25% for the thin ones): a liquid's pattern in the layer's colour and
    strength."""
    color, opacity, layer_cut, tiles, turn, offset, pattern, reach = MAP_CLOUDS[index - 1]
    field_of, soft, power = PATTERNS[pattern]
    field = field_of()
    cut = layer_cut if cut is None else cut
    out = Image.new("RGBA", (size, size))
    pixels = out.load()
    center = size / 2
    glass_radius = size / 2
    map_radius = 0.945  # Sphere.lua MAP_SIZE / BALL
    inner = map_radius * reach

    def smooth(value):
        value = max(0.0, min(1.0, value))
        return value * value * (3 - 2 * value)

    for y in range(size):
        dy = y + 0.5 - center
        for x in range(size):
            dx = x + 0.5 - center
            radius = math.hypot(dx, dy) / glass_radius
            if radius < inner or radius >= 1:
                continue
            inward = smooth((radius - inner) / (map_radius - inner))
            outward = 1 - smooth((radius - 0.955) / 0.045)
            c = pattern_at(field, dx / size, dy / size, tiles, turn, offset)
            density = smoothstep(cut, cut + soft, c) ** power
            pixels[x, y] = color + (round(255 * opacity * density * inward * outward),)
    return out


TENDRIL_SCALE = 1.04       # Sphere.lua draws the tendrils up to this times the globe
TENDRIL_EDGE = (0.86, 0.94)  # so their alpha fades out across these radii: none past the glass
                             # (0.94 x 1.04 = 0.978); 0.5.261's reached 1.04 and stood out of it
# The tendrils' body is LiquidCloud's billows too (0.5.341): the strands thin to `floor` where the
# field is empty and fill where it billows (pattern_at: `tiles`, `turn`, `offset`), times `gain`,
# which keeps the mean alpha of 0.5.340's plain strands; none darker than their darkest.
TENDRIL_CLOUD = { "floor": 0.5, "tiles": 2.4, "turn": 0.6, "offset": (0.42, 0.17), "gain": 1.463 }


def map_tendrils(size=512, gain=None):
    """Black, branching smoke rooted in the map's dark outer ring, made of LiquidCloud's billows
    (TENDRIL_CLOUD), faded out before the glass's edge at the largest size they are drawn
    (TENDRIL_EDGE)."""
    body = TENDRIL_CLOUD
    gain = body["gain"] if gain is None else gain
    scale = 2
    canvas = size * scale
    center = canvas / 2
    radius = canvas / 2
    rng = random.Random(98614)
    alpha = Image.new("L", (canvas, canvas), 0)
    draw = ImageDraw.Draw(alpha)

    def smooth(value):
        value = max(0.0, min(1.0, value))
        return value * value * (3 - 2 * value)

    for strand in range(10):
        angle = 2 * math.pi * (strand + rng.uniform(-0.43, 0.43)) / 10
        inner = rng.uniform(0.62, 0.78)
        outer = rng.uniform(0.97, 1.01)
        bend = rng.uniform(-0.85, 0.85)
        wave = rng.uniform(0.10, 0.20)
        phase = rng.uniform(0, 2 * math.pi)

        def point(t):
            r = inner + (outer - inner) * t
            a = angle + bend * (1 - t) ** 2 + wave * math.sin(2.5 * math.pi * t + phase) * (1 - t)
            return center + radius * r * math.cos(a), center + radius * r * math.sin(a), r, a

        previous = point(0)
        for step in range(1, 73):
            t = step / 72
            current = point(t)
            tip = smooth(t / 0.25)
            strength = round(210 * tip)
            width = round(scale * (3.5 + 8 * t))
            draw.line((previous[0], previous[1], current[0], current[1]), fill=strength, width=width)
            previous = current

        if strand % 2 == 0:
            attach = point(rng.uniform(0.43, 0.68))
            branch_inner = max(0.56, inner - rng.uniform(0.04, 0.09))
            previous = attach
            direction = -1 if strand % 4 == 0 else 1
            for step in range(1, 37):
                t = step / 36
                r = attach[2] + (branch_inner - attach[2]) * t
                a = attach[3] + direction * (0.32 * t * t + 0.05 * math.sin(5 * t))
                current = (center + radius * r * math.cos(a), center + radius * r * math.sin(a))
                draw.line((previous[0], previous[1], current[0], current[1]),
                          fill=round(170 * (1 - smooth((t - 0.65) / 0.35))),
                          width=round(scale * (3.5 - 2 * t)))
                previous = current

    haze = alpha.filter(ImageFilter.GaussianBlur(scale * 10)).point(lambda value: round(value * 0.48))
    alpha = ImageChops.lighter(alpha.filter(ImageFilter.GaussianBlur(scale * 3.2)), haze)
    alpha = alpha.resize((size, size), Image.Resampling.LANCZOS)
    # the roots fade into the dark ring (black there anyway) instead of past the glass
    pixels = alpha.load()
    plain = {}
    for y in range(size):
        for x in range(size):
            if pixels[x, y]:
                r = math.hypot(x + 0.5 - size / 2, y + 0.5 - size / 2) / (size / 2)
                plain[x, y] = pixels[x, y] * (1 - smooth((r - TENDRIL_EDGE[0]) /
                                                         (TENDRIL_EDGE[1] - TENDRIL_EDGE[0])))
    darkest = max(plain.values())
    for (x, y), a in plain.items():
        c = pattern_at(liquid_cloud_field(), (x + 0.5) / size - 0.5, (y + 0.5) / size - 0.5,
                       body["tiles"], body["turn"], body["offset"])
        billow = body["floor"] + (1 - body["floor"]) * smoothstep(0.2, 0.2 + CLOUD_SOFT, c)
        pixels[x, y] = round(min(darkest, a * gain * billow))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.putalpha(alpha)
    return out


def map_dissolve(size=512):
    """Fade across the map's outer 15% (MAP_FADE_START), then cover its exposed perimeter in black."""
    out = Image.new("RGBA", (size, size))
    pixels = out.load()
    center = size / 2
    map_radius = center * 0.945  # Sphere.lua MAP_SIZE / BALL
    start = map_radius * MAP_FADE_START
    for y in range(size):
        for x in range(size):
            distance = math.hypot(x + 0.5 - center, y + 0.5 - center)
            if distance < start or distance >= center:
                continue
            t = max(0.0, min(1.0, (distance - start) / (map_radius - start)))
            fade = t * t * (3 - 2 * t)
            outer = max(0.0, min(1.0, center - distance))
            pixels[x, y] = (0, 0, 0, round(255 * fade * outer))
    return out


def fill(src, d, bounds, size=256, near_seam=None):
    """Roth's filling over a piece's bounding box, cut to the piece."""
    x0, x1, top = bounds
    l, t, r, b = src.split()[3].getbbox()      # the ball in the filling (15..241)
    cx, cy, rad = (l + r) / 2, (t + b) / 2, (r - l) / 2
    im = src.transform((size, size), Image.EXTENT,
                       (cx + x0 * rad, cy - top * rad, cx + x1 * rad, cy + top * rad), Image.BICUBIC)
    m = shape_mask(d, bounds, size, near_seam).split()[3]
    r_, g_, b_, a_ = im.split()
    a_ = Image.composite(a_, Image.new("L", im.size, 0), m)
    return Image.merge("RGBA", (r_, g_, b_, a_))


GLASS = (14, 11, 12, 102)  # a subtle 40% dark tint under empty orb areas

# The health liquid: Roth's fubble (16) half and half with its dominion (19), veined, its fine
# detail strengthened (0.5.7: "more texture"; the mana keeps the fubble).
HEALTH_FILLINGS = ((16, 0.5), (19, 0.5))
DETAIL = 1.6      # fine detail (the filling less its blur at DETAIL_BLUR px) times this
DETAIL_BLUR = 10


def detailed(im, amount=DETAIL):
    """Strengthen fine detail: brightness = blur + (brightness - blur) * amount."""
    r, g, b, a = im.split()
    lum = Image.merge("RGB", (r, g, b)).convert("L")
    blur = lum.filter(ImageFilter.GaussianBlur(DETAIL_BLUR))
    out = Image.new("L", lum.size)
    o, lp, bp = out.load(), lum.load(), blur.load()
    for y in range(lum.size[1]):
        for x in range(lum.size[0]):
            o[x, y] = max(0, min(255, int(bp[x, y] + (lp[x, y] - bp[x, y]) * amount)))
    return Image.merge("RGBA", (out, out, out, a))


def health_filling():
    (first, _), *rest = HEALTH_FILLINGS
    im = load("orb_filling%d" % first)
    for n, share in rest:
        im = Image.blend(im, load("orb_filling%d" % n), share)
    im = detailed(im)
    # Fine, branching pale strands sit mainly in the dark parts of the red fluid. Supersampling
    # keeps them delicate at the game's orb size instead of making them look drawn on.
    scale = 4
    veins = Image.new("L", (im.width * scale, im.height * scale), 0)
    draw = ImageDraw.Draw(veins)

    def path(points, width=3):
        draw.line([(int(x * scale), int(y * scale)) for x, y in points],
                  fill=255, width=width, joint="curve")

    path([(9, 224), (36, 204), (57, 174), (82, 157), (106, 126),
          (139, 110), (164, 83), (194, 66), (221, 37), (246, 24)], 4)
    path([(56, 175), (43, 151), (24, 137), (16, 111)], 3)
    path([(82, 157), (91, 183), (111, 201), (119, 230)], 3)
    path([(137, 111), (157, 132), (181, 139), (203, 159)], 3)
    path([(164, 83), (169, 58), (190, 43), (198, 19)], 3)
    veins = veins.resize(im.size, Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(0.28))
    lum = Image.merge("RGB", im.split()[:3]).convert("L")
    lp, vp = lum.load(), veins.load()
    out = Image.new("L", im.size)
    op = out.load()
    for y in range(im.height):
        for x in range(im.width):
            base, strand = lp[x, y], vp[x, y] / 255
            lift = strand * (1 - base / 255) * 0.24
            op[x, y] = min(255, int(base + (255 - base) * lift + 0.5))
    return Image.merge("RGBA", (out, out, out, im.getchannel("A")))


def dark_back(back, opening=True):
    """Roth's orb back over a 40% dark tint, cropped and feathered at the ball edge; `opening`:
    the small pinch where health and mana meet at the top (none for full health)."""
    size = back.size[0]
    # A translucent disc gives empty health and mana areas a little depth while allowing the
    # game world to remain visible through them.
    lo, hi = 15 * 4 * size // 256, 241 * 4 * size // 256
    disc = Image.new("RGBA", (size * 4, size * 4), (0, 0, 0, 0))
    ImageDraw.Draw(disc).ellipse((lo, lo, hi, hi), fill=GLASS)
    disc = disc.resize((size, size), Image.LANCZOS)
    disc.alpha_composite(back)
    # Roth's source has a gray translucent rim outside the actual glass ball. It reads as
    # a dark halo against the game world, so clip that rim and feather the disc's last few pixels.
    edge = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(edge).ellipse((lo, lo, hi, hi), fill=255)
    edge = edge.filter(ImageFilter.GaussianBlur(1.5 * size / 256)).resize((size, size), Image.LANCZOS)
    disc.putalpha(ImageChops.multiply(disc.getchannel("A"), edge))
    if not opening:
        return disc
    # Keep the tinted backing continuous behind the two halves. Only cut a tiny angled pinch
    # where their inner edges meet at the top, so the long center join is not a dark split.
    scale = (size * 226 / 256) / 2
    a = split_x(HEALTH_SHARE)
    left, right = [], []
    for i in range(81):
        y = TOP_PINCH_START + (1 - TOP_PINCH_START) * i / 80
        x = a + SEAM_BOW * max(0.0, 1 - y * y)
        half = TOP_PINCH_WIDTH / 2 * (y - TOP_PINCH_START) / (1 - TOP_PINCH_START)
        py = (size / 2 - y * scale) * 4
        left.append(((size / 2 + (x - half / BALL_R) * scale) * 4, py))
        right.append(((size / 2 + (x + half / BALL_R) * scale) * 4, py))
    opening = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(opening).polygon(left + right[::-1], fill=255)
    opening = opening.resize((size, size), Image.LANCZOS)
    opening = opening.filter(ImageFilter.GaussianBlur(0.45 * size / 256))
    disc.putalpha(ImageChops.multiply(disc.getchannel("A"), ImageChops.invert(opening)))
    return disc


BOTTOM_SHADE = (0.45, 230)     # the empty player orb's bottom shadow: where it starts (ball radii under
                               # the centre) and its darkest alpha (0-255)


def bottom_shade(size=512):
    """Deep shadow in the bottom of the empty player orb, without editing OrbBack."""
    radius = size * 113 / 256
    center = (size - 1) / 2
    image = Image.new("RGBA", (size, size), (4, 3, 4, 0))
    pixels = image.load()
    for y in range(size):
        ny = (y - center) / radius
        depth = max(0.0, min(1.0, (ny - BOTTOM_SHADE[0]) / (1 - BOTTOM_SHADE[0])))
        depth = depth * depth * (3 - 2 * depth)
        if depth <= 0:
            continue
        for x in range(size):
            distance = math.hypot(x - center, y - center)
            edge = max(0.0, min(1.0, (radius - distance) / 2))
            if edge > 0:
                pixels[x, y] = (4, 3, 4, round(BOTTOM_SHADE[1] * depth * edge))
    return image


SOCKET_R = ORB_D / 2 - 1  # the socket's radius: past the orb's ball, to its rim's edge (wider showed
                          # as a dark halo where no art reached it, 0.5.15)
SOCKET = 2 * round(SOCKET_R) + 8  # its square (Roth's units; Sphere.lua SOCKET)


STONE = ("actionbar_2_1", (300, 150, 724, 232))  # the frame's dark stone, where the rows sit (no buttons drawn)


def stone(size):
    """The frame's own dark stone, brass, tiled (mirrored, so no seams) over size x size."""
    src = brass(load(STONE[0])).crop(STONE[1])
    w, h = src.size
    tiles = (src, src.transpose(Image.FLIP_TOP_BOTTOM))
    out = Image.new("RGBA", (size, size))
    for y in range(0, size, h):
        for x in range(0, size, w):
            out.paste(tiles[(y // h) % 2], (x, y))
    return out


def socket_back(size=256):
    """The frame's dark stone behind an orb's lower part, a little past its rim, darker towards
    the glass (its shadow): where the art round an orb and the orb's rim don't quite meet (the
    frame's ends were drawn for Roth's orbs), the orb looks set in the stone, not in a hole.
    0.5.8 filled it flat dark: "a gap underneath the health". Nothing above the orb's middle:
    there it would ring the glass."""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = im.load()
    st = stone(size).load()
    k = SOCKET / size
    for j in range(size):
        y = SOCKET / 2 - (j + 0.5) * k
        lower = max(0.0, min(1.0, (-y - 10) / 20))  # from 10 below the centre, full by 30 below
        if lower <= 0:
            continue
        for i in range(size):
            x = (i + 0.5) * k - SOCKET / 2
            r = math.hypot(x, y)
            edge = max(0.0, min(1.0, (SOCKET_R - r) / 2))
            a = lower * edge
            if a > 0:
                sr, sg, sb, _ = st[i, j]
                lit = 0.45 + 0.55 * max(0.0, min(1.0, (r - 71) / 14))  # in the orb's shadow by its rim
                px[i, j] = (int(sr * lit), int(sg * lit), int(sb * lit), int(a * 255 + 0.5))
    return im


# The target card's bars (Target.lua BAR_W, HEALTH_H, POWER_H), rounded (0.5.11: "too boxy"):
# each drawn at its own size into its texture, so its ends come out round when stretched there.
BARS = {"Health": (148, 18), "Power": (148, 11)}
BAR_RIM_PAD = 2.5   # the rim's texture reaches this far round the bar (Target.lua RIM_PAD)
BAR_RIM_W = 1.6     # the rim, a hair off the bar's edge
BRASS_TOP, BRASS_BOTTOM = (240, 205, 120), (110, 78, 34)


def capsule(w, h):
    """Distance inside a w x h capsule (centred, display units)."""
    r = h / 2

    def d(x, y):
        return r - math.hypot(max(abs(x) - (w / 2 - r), 0.0), y)
    return d


def bar_image(w, h, pad, paint, tw=256, th=64):
    """A tw x th texture standing for a (w + 2 pad) x (h + 2 pad) area round a w x h bar:
    paint(x, y, v, pix) -> (r, g, b, a) per texel, x, y from the bar's centre, v from its top (0-1)."""
    im = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    px = im.load()
    W, H = w + 2 * pad, h + 2 * pad
    pix = max(W / tw, H / th)
    for j in range(th):
        y = H / 2 - (j + 0.5) * H / th
        for i in range(tw):
            x = (i + 0.5) * W / tw - W / 2
            c = paint(x, y, 0.5 - y / h, pix)
            if c:
                px[i, j] = c
    return im


def bar_shape(w, h):
    """The bar: white (tinted in game), its ends round. Its fill and its dark track."""
    d = capsule(w, h)

    def paint(x, y, v, pix):
        a = max(0.0, min(1.0, d(x, y) / pix + 0.5))
        return (255, 255, 255, int(a * 255 + 0.5)) if a > 0 else None
    return bar_image(w, h, 0, paint, th=32)


def bar_fill(w, h, filling=16):
    """The bar's fill: a band through Roth's liquid (its filling 16, the mana's), its shape;
    brightness 0.55-1 (tinted in game). A flat fill looked "very inorganic" (0.5.13)."""
    src = load("orb_filling%d" % filling)
    l, t, r, b = src.split()[3].getbbox()
    bw = r - l
    bh = bw * h / w * 2.2
    cy = (t + b) / 2
    lum = src.crop((l, int(cy - bh / 2), r, int(cy + bh / 2))).resize((256, 32), Image.LANCZOS).convert("L")
    lo, hi = min(lum.getdata()), max(lum.getdata())
    lp = lum.load()
    d = capsule(w, h)

    def paint(x, y, v, pix):
        a = max(0.0, min(1.0, d(x, y) / pix + 0.5))
        if a <= 0:
            return None
        i = min(255, max(0, int((x + w / 2) / w * 256)))
        j = min(31, max(0, int(v * 32)))
        c = int(255 * (0.40 + 0.60 * (lp[i, j] - lo) / max(1, hi - lo)))
        return (c, c, c, int(a * 255 + 0.5))
    return bar_image(w, h, 0, paint, th=32)


def bar_gloss(w, h):
    """Glass over a bar: light over its top half, a thin bright line near its top, a little
    shade along its bottom; its shape."""
    d = capsule(w, h)

    def paint(x, y, v, pix):
        cov = max(0.0, min(1.0, d(x, y) / pix + 0.5))
        if cov <= 0:
            return None
        light = 0.28 * max(0.0, 1 - v / 0.48) ** 1.6
        line = 0.38 * math.exp(-((v - 0.13) / 0.052) ** 2) * min(1.0, d(x, y) / 2.0)  # not round the ends
        shade = 0.40 * max(0.0, (v - 0.53) / 0.47) ** 1.4
        white = min(1.0, light + line)
        a = white + shade * (1 - white)
        if a <= 0:
            return None
        c = int(255 * white / a)
        return (c, c, c, int(a * cov * 255 + 0.5))
    return bar_image(w, h, 0, paint, th=32)


def bar_rim(w, h):
    """A brass rim round a bar, a hair off its edge: light along its top, dark along its bottom,
    grained like the frame's metal (its stone's brightness), not a flat gradient (0.5.13)."""
    gap = 0.4
    grain = stone(256).convert("L").load()

    def paint(x, y, v, pix):
        r = h / 2 + gap
        dist = math.hypot(max(abs(x) - (w / 2 - h / 2), 0.0), y) - r   # outside the bar + gap
        a = max(0.0, min(1.0, dist / pix + 0.5)) * max(0.0, min(1.0, (BAR_RIM_W - dist) / pix + 0.5))
        if a <= 0:
            return None
        t = max(0.0, min(1.0, v))
        g = grain[int((x + w / 2 + BAR_RIM_PAD) * 255 / (w + 2 * BAR_RIM_PAD)) % 256, int((t * 40) % 256)] / 255
        k = 1.0 + 0.6 * (g - 0.15)
        col = tuple(min(255, int((BRASS_TOP[c] + (BRASS_BOTTOM[c] - BRASS_TOP[c]) * t) * k)) for c in range(3))
        return col + (int(a * 255 + 0.5),)
    return bar_image(w, h, BAR_RIM_PAD, paint)


def write(name, im):
    w, h = im.size
    data = im.tobytes("raw", "BGRA")  # rows top first
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    with open(os.path.join(OUT, name + ".tga"), "wb") as f:
        f.write(header)
        f.write(data)
    print("wrote", name, w, "x", h)


def load(name):
    return Image.open(os.path.join(SRC, name + ".tga")).convert("RGBA")


def load_modern(name):
    return Image.open(os.path.join(MODERN, name + ".tga")).convert("RGBA")


def widen_and_lower_console(base):
    """Give the spell rows six more units and lower the console four, leaving both wells fixed.

    The shift fades out before the engraved wells, so their painted edges and the orb seats
    retain their original positions. Transform narrow strips to keep the relief and slot edges
    sharp at texture resolution.
    """
    w, h = base.size
    sx, sy = w / 788, h / 202
    out = base.copy()
    left, right = round(w / 2 - 240 * sx), round(w / 2 + 240 * sx)

    def source_x_and_y(x):
        hud_x = (x - w / 2) / sx
        distance = abs(hud_x)
        if distance <= 220:
            weight = 1.0
        elif distance >= 240:
            weight = 0.0
        else:
            t = (240 - distance) / 20
            weight = t * t * (3 - 2 * t)
        source_x = x - hud_x * (3 / 220) * sx * weight
        return source_x, 4 * sy * weight

    for x0 in range(left, right, 4):
        x1 = min(x0 + 4, right)
        sx0, dy0 = source_x_and_y(x0)
        sx1, dy1 = source_x_and_y(x1)
        quad = (sx0, -dy0, sx0, h - dy0, sx1, h - dy1, sx1, -dy1)
        strip = base.transform((x1 - x0, h), Image.Transform.QUAD, quad, Image.Resampling.BICUBIC)
        out.paste(strip, (x0, 0))
    return out


def compact_console(base):
    """Lower the rail and tracking slots while keeping the feet, wells and orb seats fixed.

    The rail moves as one piece, retaining the exact aperture and divider heights.
    Only the empty panel beneath it is compressed; the upright tips ease into the
    lower rail. Work in the final cropped texture's HUD coordinates so the runtime
    slot centers and the generated pixels have the same origin and scale.
    """
    import numpy as np

    w, h = base.size
    fw, fh, _, _ = PLACES["Frame"]
    source = np.asarray(base, dtype=np.float64)
    out = source.copy()
    rows = np.arange(h, dtype=np.float64)
    # Source heights, from the bottom: protect both engraved wells through y=40,
    # move the complete rail/slot band uniformly, and retain the finial tips.
    tip_start = fh - base.getchannel("A").getbbox()[1] * fh / h - 2
    heights = np.array([fh, tip_start, 106.0, 75.0, 40.0, 0.0])
    shifts = np.array([0.0, 0.0, FRAME_CONSOLE_DROP, FRAME_CONSOLE_DROP, 0.0, 0.0])
    source_rows = (fh - heights) * h / fh
    for x in range(w):
        distance = abs((x + 0.5) * fw / w - fw / 2)
        if distance >= 240:
            continue
        weight = max(0.0, min(1.0, (240 - distance) / 13))
        weight = weight * weight * (3 - 2 * weight)
        target_rows = source_rows + shifts * h / fh * weight
        sample = np.interp(rows, target_rows, source_rows)
        lower = np.clip(np.floor(sample).astype(int), 0, h - 1)
        upper = np.minimum(lower + 1, h - 1)
        blend = (sample - lower)[:, None]
        # Resample premultiplied colors so the newly exposed transparent edge
        # keeps its original dark rim instead of acquiring a pale fringe.
        column = source[:, x].copy()
        column[:, :3] *= column[:, 3:4] / 255
        mixed = column[lower] * (1 - blend) + column[upper] * blend
        mixed[:, :3] = np.divide(mixed[:, :3] * 255, mixed[:, 3:4],
                                 out=np.zeros_like(mixed[:, :3]), where=mixed[:, 3:4] > 0)
        out[:, x] = mixed
    return Image.fromarray(np.clip(np.rint(out), 0, 255).astype("uint8"))


def finish_frame_edges(base):
    """Remove the source's exterior shadow and mirror the finished left ornament.

    Only transparency connected to the outside is cleaned. The enclosed tracking
    apertures retain their original alpha, and the dark shading inside the carved
    metal stays intact. Mirror after every warp so the two ends match pixel for pixel.
    """
    alpha = base.getchannel("A")
    outside = alpha.point(lambda value: 255 if value >= 192 else 0)
    for corner in ((0, 0), (base.width - 1, 0), (0, base.height - 1),
                   (base.width - 1, base.height - 1)):
        if outside.getpixel(corner) == 0:
            ImageDraw.floodfill(outside, corner, 128)
    outside = outside.point(lambda value: 255 if value == 128 else 0)
    edge_band = outside.filter(ImageFilter.MaxFilter(5))
    clean = alpha.filter(ImageFilter.GaussianBlur(0.45)).point(
        lambda value: max(0, min(255, round((value - 96) * 255 / 159))))
    result = base.copy()
    result.putalpha(Image.composite(clean, alpha, edge_band))
    half = result.crop((0, 0, result.width // 2, result.height))
    result.paste(half.transpose(Image.Transpose.FLIP_LEFT_RIGHT), (result.width // 2, 0))
    return result


def restore_circular_seats(console, native):
    """Keep the circle and its painted bevel independent of the lowered console.

    Both images have the same cropped pixel coordinates. Copy the original seat
    without translating or resampling it; feather only the adjacent solid plate.
    The tracking apertures, corner wells and lower baseline belong to the console.
    """
    import numpy as np

    w, h = console.size
    fw, fh, _, _ = PLACES["Frame"]
    x = (np.arange(w) + 0.5) * fw / w - fw / 2
    # Cropping removes rows, not their original world-space positions.
    y = fh - (np.arange(h) + 0.5) * fh / FRAME_TEX_SIZE[1]
    radius = np.hypot(np.abs(x)[None, :] - FRAME_ORB_X, y[:, None] - ORB_Y)

    def smooth(value):
        value = np.clip(value, 0, 1)
        return value * value * (3 - 2 * value)

    # The complete native circle edge stays inside the fully protected band.
    # Fade toward the console beyond the bevel; never bring its old XP slot back.
    weight = 1 - smooth((radius - FRAME_CUT - 2) / 6)
    guard = smooth((np.abs(x)[None, :] - 225.5) / 3)
    final_y = (h - np.arange(h) - 0.5) * fh / h
    guard = guard * smooth((final_y[:, None] - 40) / 8)
    # Keep the cleaned terminal above the junction in its current position.
    weight *= guard * (1 - smooth((final_y[:, None] - 100) / 8))
    mask = Image.fromarray(np.rint(weight * 255).astype("uint8"))
    out = Image.composite(native, console, mask)
    # One analytic circle defines the entire inner contour, including the part
    # passing the XP rails and terminal. The rail can never push it inward.
    circle = np.clip((radius - (FRAME_CUT - 0.6)) / 0.5, 0, 1)
    alpha = np.asarray(out.getchannel("A"), dtype=np.float64)
    alpha *= 1 - guard * (1 - circle)
    out.putalpha(Image.fromarray(np.rint(alpha).astype("uint8")))
    return out


def make_frames(only=None):
    """Regenerate frame variants, or one named variant for a visual review."""
    for src, dst, xp_half_width in (("actionbar_2_1", "Frame1", 222),
                                    ("actionbar_2_0", "Frame0", None),
                                    ("actionbar_2_2", "Frame2", 215)):
        if only and only not in (dst, dst + "Charcoal"):
            continue
        frame_orbs = orbs(FRAME_ORB_X)
        detailed = crisp_resize(load(src), FRAME_TEX_SIZE, 85)
        frame = seat(socket(frame_finish(brass(detailed, FRAME_GAIN), frame_orbs, FRAME_CUT),
                            PLACES["Frame"], FRAME_CUT, frame_orbs),
                     PLACES["Frame"], inner_bottom=44, centers=frame_orbs, radius=FRAME_CUT)
        surface = frame_surface(frame, frame_orbs, FRAME_CUT)
        if xp_half_width:
            surface = extend_xp_window(surface, xp_half_width)
        detailed_ends = engraved_frame_ends(surface)
        finished = graded_frame(detailed_ends)
        variants = ((dst, finished), (dst + "Charcoal", charcoal_frame(detailed_ends)))
        for name, variant in variants:
            if only and only != name:
                continue
            native = straight_frame_edges(frame_corner_sockets(variant))
            native = trim_upper_ornament(native, int(dst[-1]), native=True)
            variant = straight_frame_edges(frame_corner_sockets(widen_and_lower_console(variant)))
            variant = trim_upper_ornament(variant, int(dst[-1]))
            if not only or only == name:
                # Remove the transparent bottom pad from the asset itself. Runtime UV cropping
                # is fragile because SetTexture resets texcoords when the XP frame variant changes.
                cropped = variant.crop((0, 0, variant.width, variant.height - FRAME_BOTTOM_CROP))
                native = native.crop((0, 0, native.width, native.height - FRAME_BOTTOM_CROP))
                frame = restore_circular_seats(compact_console(cropped), native)
                write(name, finish_frame_edges(frame))
    if only is None or only.endswith("Modern"):
        make_modern_frames()


def fit_modern_cavities(base):
    """Fit smooth original-sized openings and draw one antialiased Modern rim per orb."""
    original = Image.open(os.path.join(OUT, "Frame1Charcoal.tga")).convert("RGBA")
    source = np.asarray(base, dtype=np.float64)
    reference = np.asarray(original.getchannel("A"), dtype=np.float64)
    height, width = source.shape[:2]
    fw, fh, _, _ = PLACES["Frame"]
    modern_y = -1  # Sphere.lua paintArt: retain the Modern-only frame alignment
    original_center_y = fh - (fh - ORB_Y) * FRAME_TEX_SIZE[1] / height

    def sample_alpha(pixels, x, y):
        valid = (x >= 0) & (x <= width - 1) & (y >= 0) & (y <= height - 1)
        x, y = np.clip(x, 0, width - 1), np.clip(y, 0, height - 1)
        ix, iy = np.floor(x).astype(int), np.floor(y).astype(int)
        jx, jy = np.minimum(ix + 1, width - 1), np.minimum(iy + 1, height - 1)
        fx, fy = x - ix, y - iy
        return ((1 - fy) * ((1 - fx) * pixels[iy, ix] + fx * pixels[iy, jx])
                + fy * ((1 - fx) * pixels[jy, ix] + fx * pixels[jy, jx])) * valid

    # Fit one continuous ellipse to the original rendered curve. Its engraved edge's raster
    # noise must not become the new line: only the proportions are measured from those pixels.
    angles = np.linspace(0, math.radians(130), 261)
    radii = np.linspace(82, 100, 721)
    rx = -np.cos(angles)[:, None] * radii
    ry = -np.sin(angles)[:, None] * radii
    alpha = sample_alpha(reference, (FRAME_ORB_X + rx + fw / 2) * width / fw - 0.5,
                         (fh - original_center_y - ry) * height / fh - 0.5)
    hit = alpha >= 127.5
    edge = radii[np.argmax(hit, axis=1)]
    valid = np.any(hit, axis=1)
    ex, ey = -edge[valid] * np.cos(angles[valid]), -edge[valid] * np.sin(angles[valid])
    a, b, c = np.linalg.lstsq(np.column_stack((ey * ey, ey, np.ones_like(ey))), ex * ex, rcond=None)[0]
    center_y = original_center_y - b / (2 * a)
    radius_x = math.sqrt(c - b * b / (4 * a))
    radius_y = math.sqrt(-(c - b * b / (4 * a)) / a)

    xx, yy = np.meshgrid(np.arange(width), np.arange(height))
    x = (xx + 0.5) * fw / width - fw / 2
    y = fh + modern_y - (yy + 0.5) * fh / height
    # These envelopes cap the stroke where the painted finials end, without inheriting any
    # jagged rim pixels. The line and its coverage are rasterized afresh at 4x supersampling.
    ref_support = np.asarray(original.getchannel("A").filter(ImageFilter.MaxFilter(15)), dtype=np.float64)
    support = sample_alpha(ref_support, xx, yy - modern_y * height / fh)
    support = np.minimum(support, np.asarray(base.getchannel("A").filter(ImageFilter.MaxFilter(15))))
    result = source.copy()
    wells = np.hypot(np.abs(x) - 241, y - 29) <= 16
    luminance = source[:, :, :3] @ np.array([0.2126, 0.7152, 0.0722])
    gray = luminance[:, :, None] * np.array([0.96, 1.0, 1.05])
    result[:, :, :3][wells] = gray[wells]

    for side in (-1, 1):
        center_x = side * FRAME_ORB_X

        def distance(px, py):
            u, v = (px - center_x) / radius_x, (py - center_y) / radius_y
            rho = np.hypot(u, v)
            gradient = np.hypot(u / radius_x, v / radius_y) / np.maximum(rho, 1e-9)
            return (rho - 1) / np.maximum(gradient, 1e-9)

        d = distance(x, y)
        coverage = np.zeros_like(d)
        stroke = np.zeros_like(d)
        for sy in range(4):
            for sx in range(4):
                sub_x = (xx + (sx + 0.5) / 4) * fw / width - fw / 2
                sub_y = fh + modern_y - (yy + (sy + 0.5) / 4) * fh / height
                sub_d = distance(sub_x, sub_y)
                coverage += (sub_d >= 0) / 16
                stroke += ((sub_d >= 0.08) & (sub_d <= 0.72)) / 16
        well = np.hypot(x - side * 241, y - 29)
        material = ((side * x > 225) & (d > 2) & (d < 8) & (well > 17)
                    & (source[:, :, 3] > 250) & (np.max(source[:, :, :3], axis=2) < 95)
                    & (np.min(source[:, :, :3], axis=2) > 20))
        body = np.median(source[:, :, :3][material], axis=0)
        paint = np.clip((3.5 - d) / 2, 0, 1) * np.clip((well - 14) / 2, 0, 1)
        rgb = result[:, :, :3] * (1 - paint[:, :, None]) + body * paint[:, :, None]
        line = np.divide(stroke, coverage, out=np.zeros_like(stroke), where=coverage > 0)
        rgb = rgb * (1 - line[:, :, None]) + np.array([100, 111, 120]) * line[:, :, None]
        affected = (side * x > 225) & (y > 5) & (d <= 3.5)
        result[:, :, :3][affected] = rgb[affected]
        result[:, :, 3][affected] = (coverage * support)[affected]

    return Image.fromarray(np.clip(np.rint(result), 0, 255).astype("uint8"))


MODERN_SIDE_CUT = 8  # remove the redundant 437..444 / 1603..1610 px side rims
MODERN_FRAME_W = 788 * (2048 - 2 * MODERN_SIDE_CUT) / 2048


def compact_modern_sides(base):
    """Remove only the two redundant console rims; translate whole cavities, never warp them."""
    parts = (base.crop((0, 0, 437, 500)), base.crop((445, 0, 1603, 500)),
             base.crop((1611, 0, 2048, 500)))
    out = Image.new("RGBA", (2048 - 2 * MODERN_SIDE_CUT, 500))
    x = 0
    for part in parts:
        out.paste(part, (x, 0))
        x += part.width
    return out


def modern_panel_details(base):
    """Neutral stone-gray trim and an octagonal lattice, in Bars.lua's frame units.

    Keep the supplied master as the geometry source: this pass changes its line colors,
    then paints only the panel behind the two action rows. Cavity pixels retain their shape.
    """
    pixels = np.array(base).astype(np.float32)
    rgb = pixels[:, :, :3]
    bright = rgb.max(axis=2)
    neutral = np.clip(1 - (rgb.max(axis=2) - rgb.min(axis=2)) / 35, 0, 1)
    amount = np.clip((bright - 38) / 35, 0, 1) * neutral
    gray = rgb.mean(axis=2) * 0.69
    for channel, tint in enumerate((1.02, 1.01, 0.96)):
        rgb[:, :, channel] += (gray * tint - rgb[:, :, channel]) * amount
    base = Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8))

    # Work at twice the exported resolution, then downsample the shared intersections.
    # Cell centers and sizes are exactly Bars.lua's. Chamfers continue from each slot's
    # border into the vertical AND horizontal gutters, including their four-way joins.
    ss = 2
    w, h = base.size
    yy, xx = np.mgrid[:h * ss, :w * ss]
    x = (xx + 0.5) / (w * ss) * MODERN_FRAME_W - MODERN_FRAME_W / 2
    y = (1 - (yy + 0.5) / (h * ss)) * 202 - 1
    size, gap, row_gap = 31.36, 3, 3.5
    width = 13 * size + 12 * gap
    left, bottom = -width / 2 - gap / 2, 7.5 - row_gap / 2
    pitch_x, pitch_y = size + gap, size + row_gap
    u, v = (x - left) % pitch_x, (y - bottom) % pitch_y
    dx, dy = np.minimum(u, pitch_x - u) - gap / 2, np.minimum(v, pitch_y - v) - row_gap / 2
    diagonal = (dx + dy - 3.5 / 45 * size) / math.sqrt(2)
    distance = np.minimum(np.minimum(dx, dy), diagonal)
    mask = (x >= left) & (x <= left + 13 * pitch_x) & (y >= bottom) & (y <= bottom + 2 * pitch_y)
    # A dark joint runs between adjoining tiles; broad diagonal facets meet the chamfers.
    seam = np.minimum(np.minimum(u, pitch_x - u), np.minimum(v, pitch_y - v))
    shade = 53 + 18 * np.clip(-distance / 2.2, 0, 1)
    shade += 8 * np.where(v > pitch_y / 2, -1, 1) * np.clip(-distance / 2, 0, 1)
    shade *= 0.48 + 0.52 * np.clip(seam / 0.45, 0, 1)
    corner_x, corner_y = np.minimum(u, pitch_x - u), np.minimum(v, pitch_y - v)
    diagonal_edge = np.abs(corner_x - corner_y)
    corners = (corner_x < 4.5) & (corner_y < 4.5) & (distance < 0)
    # Two carved diagonal ridges form the reference's X-shaped corner intersections.
    shade += corners * (23 * np.exp(-((diagonal_edge - 0.65) / 0.3) ** 2)
                        - 16 * np.exp(-(diagonal_edge / 0.22) ** 2))
    # The wells are visible behind empty slots too: soft stone, darkened below the bevel.
    well = 19 + 8 * np.exp(-((u / pitch_x - 0.42) ** 2 + (v / pitch_y - 0.55) ** 2) * 5)
    well *= 1 - 0.65 * np.exp(-np.maximum(distance, 0) / 1.5)
    k = size / 45
    edge, band, line = (BEZEL_MODERN[n] * k for n in ("edge", "band", "line"))
    ridge = 78 + 12 * np.where(v > pitch_y / 2, -1, 1)
    well = np.where(distance < edge + band + line, 12, well)
    well = np.where((distance >= edge) & (distance < edge + band), ridge, well)
    shade = np.where(distance >= 0, well, shade)
    # A restrained translucent outline outside each existing solid slot bevel.
    outer_trim = (distance >= -1.15 * k) & (distance <= -0.6 * k)
    shade = np.where(outer_trim, shade * 0.88 + 128 * 0.12, shade)
    overlay = np.zeros((h * ss, w * ss, 4), dtype=np.uint8)
    for channel, tint in enumerate((1.02, 1.01, 0.96)):
        overlay[:, :, channel] = np.clip(shade * tint, 0, 255)
    overlay[:, :, 3] = mask * 255
    base.alpha_composite(Image.fromarray(overlay).resize(base.size, Image.Resampling.LANCZOS))
    return base


def make_modern_frames(preserve_master=False):
    """Derive matching modern console layouts from the supplied one-rail master."""
    master = load_modern("Frame1")
    if preserve_master and master.size != (2048, 500):
        raise ValueError("Modern variants require a finished 2048x500 Frame1 master")
    if master.width != 2048:
        master = master.resize((2048, round(master.height * 2048 / master.width)), Image.Resampling.LANCZOS)
    bottom = master.getchannel("A").getbbox()[3]
    # The master already matches the console's horizontal geometry. Drop its export padding,
    # preserving source pixels and aligning the lower metal edge with the shared HUD origin.
    # A supplied 2048x500 runtime master is already aligned and hand-finished. Keep that
    # artwork intact; only uncropped export canvases need the cavity-fitting pass.
    base = master.copy() if master.size == (2048, 500) else fit_modern_cavities(master.crop((0, bottom - 500, 2048, bottom)))

    # XP and reputation are drawn behind the frame. Open only the dark recesses, keeping
    # the painted rail and its dividers opaque so the bars show through the new master.
    if not preserve_master:
        pixels = np.array(base)
        aperture = pixels[291:311, 445:1603]
        aperture[:, :, 3][np.max(aperture[:, :, :3], axis=2) < 40] = 0
        base = Image.fromarray(pixels)

    # The 0-slot layout keeps the outer trim and fills the rail opening with the same
    # dark panel material sampled immediately below it.
    no_xp = base.copy()
    panel_strip = base.crop((445, 328, 1603, 363))
    no_xp.paste(panel_strip, (445, 287))

    # Preserve the original rail at the XP slot and add its twin 23 pixels above for
    # reputation. Paste alpha too, so the upper slot opens through the old top trim.
    two_xp = base.copy()
    rail = base.crop((445, 222, 1603, 316))
    two_xp.paste(rail, (445, 199))
    for name, image in (("Frame0Modern", no_xp), ("Frame1Modern", base), ("Frame2Modern", two_xp)):
        if preserve_master and name == "Frame1Modern":
            continue
        image = modern_panel_details(compact_modern_sides(image))
        write(name, image)


def make_map_glass():
    write("GlassMap", glass(ball, sphere, (-1.0, 1.0, 1.0), shine=MAP_SHINE,
                            gloss=MAP_GLOSS, rim=MAP_RIM, edge_light=MAP_EDGE_LIGHT,
                            outline=GLASS_OUTLINE))


def make_glass():
    """Regenerate the map and outer split glass without touching their backing textures."""
    make_map_glass()
    make_piece_glass()


def make_piece_glass():
    for side, bounds in pieces().items():
        name = side.capitalize()
        write("Glass" + name, glass(piece(side), piece_height(side), bounds,
                                    near_seam=seam(side), shine=PIECE_SHINE,
                                    gloss=PIECE_GLOSS, outline=GLASS_OUTLINE,
                                    rim=MANA_TOP_RIM if side == "mana" else 1.0,
                                    surface_glow=MANA_TOP_GLOW if side == "mana" else 0.0,
                                    bridge=side == "mana", seam_lower_dim=OUTER_SEAM_LOWER_DIM))


# The target's sphere (Sphere.lua TARGET, experimental) floats at the top of the screen: no shadow to
# sit it on the frame (0.5.469, the player's: "Having shadow on target frame doesn't make sense, at
# least the level of player spheres"), and "a little more highlight around the edges": its own glass,
# without the lower edge shadow, its lower half keeping more of its light (TARGET_LOWER_FADE), light
# round its whole rim (TARGET_EDGE_LIGHT).
# 0.5.473, the player's: "reduce the highlight of target sphere a little" (shine 0.60, edge light 0.30, and
# the pieces' window reflection, PIECE_GLOSS 0.52, before)
TARGET_SHINE = 0.48
TARGET_EDGE_LIGHT = 0.24
TARGET_GLOSS = 0.42
TARGET_LOWER_FADE = 0.55


def make_target_glass():
    # whole, for a target without power (Sphere.lua S.TargetSpherePower)
    write("GlassTargetWhole", glass(ball, sphere, (-1.0, 1.0, 1.0), shine=TARGET_SHINE, gloss=TARGET_GLOSS,
                                    outline=GLASS_OUTLINE, shade=False, lower_fade=TARGET_LOWER_FADE,
                                    halo=TARGET_EDGE_LIGHT))
    for side, bounds in pieces().items():
        write("GlassTarget" + side.capitalize(), glass(piece(side), piece_height(side), bounds,
                                                         near_seam=seam(side), shine=TARGET_SHINE,
                                                         gloss=TARGET_GLOSS, outline=GLASS_OUTLINE, shade=False,
                                                         rim=MANA_TOP_RIM if side == "mana" else 1.0,
                                                         surface_glow=MANA_TOP_GLOW if side == "mana" else 0.0,
                                                         bridge=side == "mana", lower_fade=TARGET_LOWER_FADE,
                                                         halo=TARGET_EDGE_LIGHT))


def make_whole_glass():
    write("GlassWhole", glass(ball, sphere, (-1.0, 1.0, 1.0), shine=PIECE_SHINE, gloss=PIECE_GLOSS,
                              outline=GLASS_OUTLINE))


def make_whole_shade():
    whole = (-1.0, 1.0, 1.0)
    write("LiquidShadeWhole", liquid_shade("health", whole, d=ball))


def make_piece_shades():
    for side, bounds in pieces().items():
        write("LiquidShade" + side.capitalize(), liquid_shade(side, bounds))


def make_bottom_shade():
    write("OrbBottomShade", bottom_shade())


def make_pet_bowl():
    write("PetBowl", pet_bowl())


def make_whole_health():
    """Full left health glass when a pet-free player uses the embedded sphere for power."""
    whole = (-1.0, 1.0, 1.0)
    mask = shape_mask(ball, whole)
    write("FillWhole", white_alpha_image(mask))
    write("MaskWhole", mask)
    make_whole_shade()
    make_whole_glass()
    # OrbBack without the pinch where health and mana meet at the top (0.5.346, the player's: "there
    # is an opening there which should only happen when health and mana spheres exist"): the
    # same backing everywhere else (OrbBack itself is the player's, kept as it is)
    write("OrbBackWhole", dark_back(load("orb_back2"), opening=False))


def level_rest_halo():
    """A soft circular glow following the small engraved level well."""
    size = 128
    pixels = []
    for y in range(size):
        for x in range(size):
            radius = math.hypot(x - 63.5, y - 63.5) / 64
            fine = math.exp(-0.5 * ((radius - 0.81) / 0.045) ** 2)
            soft = math.exp(-0.5 * ((radius - 0.81) / 0.09) ** 2)
            alpha = round(min(255, 105 * fine + 70 * soft))
            pixels.append((255, 213, 125, alpha))
    out = Image.new("RGBA", (size, size))
    out.putdata(pixels)
    return out


# The liquids' slosh (0.5.442): one soft edge between nothing above and liquid below, `span` units
# tall (Sphere.lua SLOSH_EDGE_SPAN), soft over `soft` of them. Sphere.lua tilts it by texture
# coordinates, clamped past its ends: the mask on a liquid's body (full tilt), or the liquid
# climbing a wall (one-sided).
SLOSH_EDGE = {"w": 4, "h": 64, "span": 32.0, "soft": 1.0}


def slosh_edge():
    w, h, span, soft = SLOSH_EDGE["w"], SLOSH_EDGE["h"], SLOSH_EDGE["span"], SLOSH_EDGE["soft"]
    im = Image.new("RGBA", (w, h))
    px = im.load()
    for y in range(h):
        below = ((y + 0.5) - h / 2) / (h / span)  # units under the edge
        a = round(255 * smoothstep(-soft / 2, soft / 2, below))
        for x in range(w):
            px[x, y] = (255, 255, 255, a)
    return im


# A crack in the glass (0.5.457, Sphere.lua CRACK): one line along u, across v its section: a thin
# bright core where the broken glass catches the light, on its lit side (v over 0.5, the image's
# lower rows) a faint light off the fracture's face, on the other a dark shade. Sphere.lua tones
# each line by vertex colour and alpha. 0.5.458 darkened both sides and every line ("too bright ...
# the edges can be darker"), which was "still too dark" (0.5.460: back to these, toned down there).
# Its first and last columns are empty: Sphere.lua maps the lit columns between them onto each
# segment of a crack by texture coordinates (CLAMP: past either end, the empty column), so a line
# keeps its width at any angle and grows or draws back by its coordinates alone; it turns v round
# so the lit side faces the glass's light (upper left). 16 rows: at 32 a thin line was shrunk past
# 2 texels a pixel and broke into dashes (0.5.459).
CRACK_LINE = {"w": 64, "h": 16, "core": 0.05, "core_alpha": 0.95,
              "light": 0.16, "light_alpha": 0.30, "shade": 0.26, "shade_alpha": 0.50}


def crack_line():
    w, h = CRACK_LINE["w"], CRACK_LINE["h"]
    im = Image.new("RGBA", (w, h))
    px = im.load()
    for y in range(h):
        v = (y + 0.5) / h - 0.5  # 0 at the line; over 0 the lit side
        d = abs(v)
        core = 1 - smoothstep(CRACK_LINE["core"] * 0.4, CRACK_LINE["core"] * 1.5, d)
        if v > 0:
            side = (1 - smoothstep(0, CRACK_LINE["light"], d)) * CRACK_LINE["light_alpha"]
            shade = 236
        else:
            side = (1 - smoothstep(CRACK_LINE["shade"] * 0.3, CRACK_LINE["shade"], d)) * CRACK_LINE["shade_alpha"]
            shade = 10
        a = core * CRACK_LINE["core_alpha"] + (1 - core) * side
        c = round(242 * core + shade * (1 - core))
        for x in range(1, w - 1):
            px[x, y] = (c, c, min(255, c + 6), round(255 * a))
    return im


# Where the blow landed (Sphere.lua CRACK impact): a small crushed spot, frosted light in chips round
# the point, darker grit between them; round, its outer ring of texels empty (Sphere.lua grows and
# shrinks it by texture coordinates, CLAMP).
CRACK_IMPACT = {"size": 64, "reach": 0.40, "chips": 22, "frost_alpha": 0.50, "seed": 4571}


def crack_impact():
    n, reach = CRACK_IMPACT["size"], CRACK_IMPACT["reach"]
    rng = random.Random(CRACK_IMPACT["seed"])
    chips = [(rng.uniform(0, 2 * math.pi), rng.uniform(0.15, 1.0), rng.uniform(0.08, 0.22), rng.random())
             for _ in range(CRACK_IMPACT["chips"])]
    im = Image.new("RGBA", (n, n))
    px = im.load()
    for y in range(1, n - 1):
        for x in range(1, n - 1):
            dx, dy = (x + 0.5) / n - 0.5, (y + 0.5) / n - 0.5
            r = math.hypot(dx, dy) / reach
            if r >= 1:
                continue
            angle = math.atan2(dy, dx)
            # chips: wedges round the point, each out to its own reach, lit or dark
            lit, dark = 0.0, 0.0
            for a0, length, width, kind in chips:
                turn = abs((angle - a0 + math.pi) % (2 * math.pi) - math.pi)
                if turn < width and r < length:
                    edge = (1 - turn / width) * (1 - r / length)
                    if kind < 0.65:
                        lit = max(lit, edge)
                    else:
                        dark = max(dark, edge)
            frost = (1 - smoothstep(0.0, 1.0, r)) * CRACK_IMPACT["frost_alpha"]
            core = 1 - smoothstep(0.0, 0.18, r)
            a = min(1.0, max(frost * 0.6 + lit * 0.7 + core * 0.9, dark * 0.6))
            light = min(1.0, (frost * 0.6 + lit * 0.7 + core * 0.9) / max(a, 1e-6)) if a > 0 else 0
            c = round(14 + 228 * light)
            px[x, y] = (c, c, min(255, c + 6), round(255 * a))
    return im


def menu_latency_ring():
    """Keep the outer edge beside the menu well; remove the old highlight's inner glow."""
    size = 128  # four texture pixels per unit at the 32-unit display size
    pixels = []
    for y in range(size):
        for x in range(size):
            radius = math.hypot(x - 63.5, y - 63.5) / 4
            inner = max(0.0, min(1.0, (radius - 14.0) / 0.4 + 0.5))
            outer = max(0.0, min(1.0, (15.3 - radius) / 0.4 + 0.5))
            pixels.append((255, 255, 255, round(255 * inner * outer)))
    out = Image.new("RGBA", (size, size))
    out.putdata(pixels)
    return out


# The frames round Spheres' buttons (0.5.436, the player's pick from a mockup of four looks: "D,
# but add the texture that game frames have"): one bevel for the round ones (HubFrame: docked hubs,
# the menu ring's discs, the mail and target level badges) and the square ones (SlotFrame: every
# action button's). Across its edge it is Blizzard's action button frame (UI-HUD-ActionBar-IconFrame,
# per 45 units of button: a dark edge 0.5, the band 1.5, a dark line 0.5, a shadow 3.5 falling in),
# in the HUD's brass, made as Blizzard's bronze frames are (the minimap header's buttons,
# ui-hud-minimap-tracking-button): a bright ridge along the band lit from above, its shine varying
# along it, and a fine grain.
BEZEL = {"edge": 0.5, "band": 1.5, "line": 0.5, "shadow": 3.5, "light": 100, "seed": 7,
         "rim": (40, 26, 13), "dark": (58, 39, 21), "brass": (172, 132, 78), "shine": (255, 238, 196),
         "line_rgb": (24, 15, 8),
         "ridge_at": 0.34, "ridge_width": 0.15, "groove_at": 0.78, "groove": 0.35, "vary": 0.45}
BEZEL_MODERN = dict(BEZEL, edge=0.45, band=1.8, line=0.45, shadow=3,
                    rim=(16, 16, 14), dark=(68, 67, 61), brass=(106, 105, 99),
                    shine=(130, 129, 120), line_rgb=(12, 12, 10), ridge_width=0.35,
                    groove=0.12, vary=0.08)
# The round one: 36 units across (Art.lua RING_SIZE), its inner line on the dark disc's edge (13.95).
HUB_FRAME = {"units": 36, "outer": 16.0, "size": 128}
# The square one: Blizzard's frame's 46 x 45 over a 45-unit button (Art.lua SizeAction), its corners
# cut as Blizzard's.
SLOT_FRAME = {"w": 46, "h": 45, "chamfer": 3.5, "size": 256}


def _smooth(t):
    return t * t * (3 - 2 * t)


def _value_noise(seed):
    rng = random.Random(seed)
    grid = {}

    def at(ix, iy):
        key = (ix, iy)
        if key not in grid:
            grid[key] = rng.random() * 2 - 1
        return grid[key]

    def noise(x, y):
        ix, iy = math.floor(x), math.floor(y)
        fx, fy = _smooth(x - ix), _smooth(y - iy)
        a = at(ix, iy) + (at(ix + 1, iy) - at(ix, iy)) * fx
        b = at(ix, iy + 1) + (at(ix + 1, iy + 1) - at(ix, iy + 1)) * fx
        return a + (b - a) * fy
    return noise


def bezel_sample(d, k, normal, ux, uy, shine_noise, grain_noise, palette=BEZEL):
    """One sample `d` units in from the outer edge (k: the button's size / 45), the edge facing
    `normal` degrees (0 right, 90 up): straight RGBA, alpha 0-1, or None."""
    edge, band, line, shadow = (palette[n] * k for n in ("edge", "band", "line", "shadow"))
    if d < 0:
        return None
    if d < edge:
        return palette["rim"] + (1.0,)
    light = 0.5 + 0.5 * math.cos(math.radians(normal - palette["light"]))
    if d < edge + band:
        t = (d - edge) / band
        base = [palette["dark"][i] + (palette["brass"][i] - palette["dark"][i]) * (0.25 + 0.75 * light) for i in range(3)]
        # the ridge's crisp shine, brightest facing the light and coming and going along the band
        ridge = math.exp(-((t - palette["ridge_at"]) / palette["ridge_width"]) ** 2)
        vary = max(0.0, 1 + palette["vary"] * shine_noise(ux / 3.2, uy / 3.2))
        amount = max(0.0, min(1.0, ridge * (0.12 + 0.88 * light ** 1.4) * vary))
        col = [base[i] + (palette["shine"][i] - base[i]) * amount for i in range(3)]
        # a groove before the inner line, and the band falling away into it
        groove = 1 - palette["groove"] * math.exp(-((t - palette["groove_at"]) / 0.12) ** 2)
        fall = (1 - 0.25 * _smooth(max(0.0, min(1.0, (t - 0.5) / 0.5)))) * groove
        grain = 1 + 0.07 * grain_noise(ux * 3.1, uy * 3.1)
        return tuple(max(0.0, min(255.0, c * fall * grain)) for c in col) + (1.0,)
    if d < edge + band + line:
        return palette["line_rgb"] + (0.92,)
    if d < edge + band + line + shadow:
        e = (d - edge - band - line) / shadow
        return (0, 0, 0, 0.46 * (1 - e) ** 1.7)
    return None


def _bezel_image(width, height, sample_at, ss=4):
    out = Image.new("RGBA", (width, height))
    pixels = []
    for y in range(height):
        for x in range(width):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(ss):
                for sx in range(ss):
                    v = sample_at(x + (sx + 0.5) / ss, y + (sy + 0.5) / ss)
                    if v:
                        a = v[3]
                        acc[0] += v[0] * a; acc[1] += v[1] * a; acc[2] += v[2] * a; acc[3] += a
            n = ss * ss
            if acc[3] > 0:
                pixels.append((round(acc[0] / acc[3]), round(acc[1] / acc[3]), round(acc[2] / acc[3]),
                               round(255 * acc[3] / n)))
            else:
                pixels.append((0, 0, 0, 0))
    out.putdata(pixels)
    return out


def hub_frame(modern=False):
    size, units = HUB_FRAME["size"], HUB_FRAME["units"]
    px_per_unit = size / units
    k = units / 45
    palette = BEZEL_MODERN if modern else BEZEL
    shine, grain = _value_noise(BEZEL["seed"]), _value_noise(BEZEL["seed"] + 1)
    c = size / 2

    def at(x, y):
        ux, uy = (x - c) / px_per_unit, (c - y) / px_per_unit
        r = math.hypot(ux, uy)
        return bezel_sample(HUB_FRAME["outer"] - r, k, math.degrees(math.atan2(uy, ux)), ux, uy, shine, grain, palette)
    return _bezel_image(size, size, at)


def slot_frame(modern=False):
    size, w, h, cut = SLOT_FRAME["size"], SLOT_FRAME["w"], SLOT_FRAME["h"], SLOT_FRAME["chamfer"]
    if modern:
        w = h = 48  # 45-unit square plus room for its translucent outer trim
    shine, grain = _value_noise(BEZEL["seed"] + 2), _value_noise(BEZEL["seed"] + 3)
    root2 = math.sqrt(2)
    palette = BEZEL_MODERN if modern else BEZEL

    def at(x, y):
        ux, uy = x / size * w, y / size * h  # y down
        if modern:
            ux, uy = ux - 1.5, uy - 1.5
        inner_w, inner_h = (45, 45) if modern else (w, h)
        sides = ((ux, 180), (inner_w - ux, 0), (uy, 90), (inner_h - uy, 270),
                 ((ux + uy - cut) / root2, 135), ((inner_w - ux + uy - cut) / root2, 45),
                 ((ux + inner_h - uy - cut) / root2, 225), ((inner_w - ux + inner_h - uy - cut) / root2, 315))
        d, normal = min(sides)
        if modern and -1.15 <= d <= -0.6:
            return (128, 127, 119, 0.28)
        return bezel_sample(d, 1.0, normal, ux, -uy, shine, grain, palette)
    return _bezel_image(size, size, at)


def modern_slot_mask():
    size, ss = SLOT_FRAME["size"], 4
    yy, xx = np.mgrid[:size * ss, :size * ss]
    x, y = (xx + 0.5) / (size * ss) * 45, (yy + 0.5) / (size * ss) * 45
    dx, dy = np.minimum(x, 45 - x), np.minimum(y, 45 - y)
    mask = ((dx + dy >= SLOT_FRAME["chamfer"]) * 255).astype(np.uint8)
    alpha = Image.fromarray(mask).resize((size, size), Image.Resampling.LANCZOS)
    image = Image.new("RGBA", (size, size), "white")
    image.putalpha(alpha)
    return image


def main():
    os.makedirs(OUT, exist_ok=True)
    write("MenuLatencyRing", menu_latency_ring())
    write("SloshEdge", slosh_edge())
    write("CrackLine", crack_line())
    write("CrackImpact", crack_impact())
    write("CrackCavity", crack_cavity())
    write("HubFrame", hub_frame())
    write("SlotFrame", slot_frame())
    write("HubFrameModern", hub_frame(modern=True))
    write("SlotFrameModern", slot_frame(modern=True))
    write("SlotMaskModern", modern_slot_mask())
    write("LevelRestHalo", level_rest_halo())
    write("OrbBack", dark_back(load("orb_back2")))
    make_bottom_shade()
    write("OrbSocket", socket_back())
    for name, (w, h) in BARS.items():
        write("BarShape" + name, bar_shape(w, h))
        write("BarFill" + name, bar_fill(w, h))
        write("BarGloss" + name, bar_gloss(w, h))
        write("BarRim" + name, bar_rim(w, h))
    write("FluidFlow", fluid_flow())
    write("MaskMap", map_mask())
    write("MapDissolve", map_dissolve())
    for i in range(1, len(MAP_CLOUDS) + 1):
        write("MapCloud%d" % i, map_cloud(i))
    write("MapTendrils", map_tendrils())
    make_glass()
    make_whole_health()
    make_liquids()
    for side, bounds in pieces().items():
        name = side.capitalize()
        d = piece(side)
        write("Mask" + name, shape_mask(d, bounds, near_seam=seam(side)))
        print("  %s = { %.4f, %.4f, %.4f }, -- x0, x1, top (ball radii): Sphere.lua PIECES" % ((side,) + bounds))
    write_statues(say=True)
    make_frames()
    write("Bottom", bottom_art())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    output = parser.add_mutually_exclusive_group()
    output.add_argument("--frames-only", action="store_true", help="regenerate Roth, Charcoal and Modern frame variants")
    output.add_argument("--modern-only", action="store_true", help="regenerate Modern frames and statues from tools/modern")
    output.add_argument("--modern-variants-only", action="store_true", help="generate Modern Frame0/Frame2 without writing Frame1")
    output.add_argument("--shade-only", action="store_true", help="regenerate OrbBottomShade only")
    output.add_argument("--glass-only", action="store_true", help="regenerate the three glass overlays only")
    output.add_argument("--map-glass-only", action="store_true", help="regenerate the minimap's glass only")
    output.add_argument("--pet-glass-only", action="store_true", help="regenerate the embedded sphere glass only")
    output.add_argument("--target-only", action="store_true", help="regenerate the target sphere's cavity mask and glass only")
    output.add_argument("--pet-bowl-only", action="store_true", help="regenerate the embedded sphere cavity only")
    output.add_argument("--pet-shadow-only", action="store_true", help="regenerate the embedded liquid's outer contact shadows only")
    output.add_argument("--whole-health-only", action="store_true", help="regenerate the full left health glass and backing only")
    output.add_argument("--statues-only", action="store_true", help="regenerate legacy and Modern statues, including see-through head variants")
    output.add_argument("--halo-only", action="store_true", help="regenerate the circular level rest halo only")
    output.add_argument("--menu-ring-only", action="store_true", help="regenerate the Game Menu latency ring only")
    output.add_argument("--slosh-edge-only", action="store_true", help="regenerate the liquids' slosh edge only")
    output.add_argument("--crack-only", action="store_true", help="regenerate the glass crack's line, impact and cavity mask only")
    output.add_argument("--frames-bezel-only", action="store_true",
                        help="regenerate brass and Modern gray bevel frames, round hubs and square buttons")
    output.add_argument("--map-clouds-only", action="store_true", help="regenerate the inset map's backing, fade and smoke rings only")
    output.add_argument("--liquids-only", action="store_true", help="regenerate the plain fills, the liquids' moving layers, their shade and the mana glint")
    args = parser.parse_args()
    if args.frames_only:
        make_frames()
    elif args.modern_only:
        make_modern_frames()
        make_modern_statues()
    elif args.modern_variants_only:
        make_modern_frames(preserve_master=True)
    elif args.shade_only:
        make_bottom_shade()
    elif args.glass_only:
        make_glass()
    elif args.map_glass_only:
        make_map_glass()
    elif args.target_only:
        write("TargetCavity", target_cavity())
        make_target_glass()
    elif args.pet_glass_only:
        make_pet_glass()
    elif args.pet_bowl_only:
        make_pet_bowl()
    elif args.pet_shadow_only:
        make_pet_contact_shadows()
    elif args.whole_health_only:
        make_whole_health()
    elif args.statues_only:
        write_statues()
    elif args.halo_only:
        write("LevelRestHalo", level_rest_halo())
    elif args.frames_bezel_only:
        write("HubFrame", hub_frame())
        write("SlotFrame", slot_frame())
        write("HubFrameModern", hub_frame(modern=True))
        write("SlotFrameModern", slot_frame(modern=True))
        write("SlotMaskModern", modern_slot_mask())
    elif args.menu_ring_only:
        write("MenuLatencyRing", menu_latency_ring())
    elif args.slosh_edge_only:
        write("SloshEdge", slosh_edge())
    elif args.crack_only:
        write("CrackLine", crack_line())
        write("CrackImpact", crack_impact())
        write("CrackCavity", crack_cavity())
    elif args.map_clouds_only:
        write("MaskMap", map_mask())
        write("MapDissolve", map_dissolve())
        for i in range(1, len(MAP_CLOUDS) + 1):
            write("MapCloud%d" % i, map_cloud(i))
        write("MapTendrils", map_tendrils())
    elif args.liquids_only:
        make_liquids()
    else:
        main()
