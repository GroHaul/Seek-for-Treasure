"""
Seek for Treasure: the 12 Pets treasures, modeled procedurally in Blender (GDD §13.3).

Run headless (no Blender UI needed):
    blender -b --factory-startup -P tools/blender/build_treasures.py -- <out_dir> [preview_dir]

Style ("Sunny Toybox"): chunky low-poly toys built from rounded primitives, big
friendly eyes, flat colors, each standing on a disc in its rarity color. Every
treasure is ONE mesh with ONE material whose colors come from a shared 8x8 palette
texture (each face's UVs point at its color's cell), so Roblox imports each one
as a single MeshPart and mutation tints still work.

Outputs:
    <out_dir>/pets_treasures.glb   all 12 objects, named like Config's `model` field
    <out_dir>/pets_palette.png     the palette texture (also embedded in the GLB)
    <preview_dir>/<Name>.png       one 512x512 render per treasure (optional)

Original designs only: no existing characters, brands or reference-game art.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

# ------------------------------------------------------------------ palette

PALETTE_HEX = {
    "ink": "1D2340", "black": "17182A", "white": "FFFFFF", "cream": "FFF4DF", "eyeShine": "FFFFFF",
    "pink": "FF9EB5", "rose": "FF6B8B", "coral": "FF6B6B", "blush": "FFB3C4",
    "grey": "C9CED8", "greyLight": "E4E7EE", "greyDark": "8E94A6", "slate": "6B7287", "sand": "D9C7A5",
    "sun": "FFD23F", "gold": "FFC23A", "goldDeep": "E89A1C", "orange": "FF8A2B", "orangeDeep": "E8601C",
    "flame": "FFB43B", "toast": "D99A4E", "toastDark": "A8662C", "crust": "F2C27A", "butter": "FFE680",
    "leaf": "5BD66B", "leafDark": "2E9E4A", "leafLight": "9BEA7E",
    "sky": "49B6FF", "skyLight": "A6DEFF", "blue": "3A7BD5", "navy": "22306E", "midnight": "2B2F6B",
    "grape": "8E5CFF", "lavender": "C7B3FF", "violet": "5A2E9E", "purple": "7B3FE4", "magenta": "E05AD0",
    "cloud": "F2F5FB", "storm": "A3AABB", "stormDark": "5C6478", "water": "7FD1FF",
    "crystalBlue": "8FE3FF", "crystalPurple": "B48CFF", "starYellow": "FFF27A",
    # rarity disc colors (Config/Rarities)
    "r1": "B8C0CC", "r2": "5BD66B", "r3": "49A8FF", "r4": "A25CFF", "r5": "FFB52E",
    "r6": "FF3E7A", "r7": "FFF3B0", "r8": "6EF2FF", "r9": "7B2FFF", "r10": "2A2140",
}
GRID = 8
CELL_PX = 32
COLOR_INDEX = {name: i for i, name in enumerate(PALETTE_HEX)}
assert len(COLOR_INDEX) <= GRID * GRID


def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def make_palette(path):
    size = GRID * CELL_PX
    image = bpy.data.images.new("SFT_Palette", size, size, alpha=False)
    # unused cells are bright magenta, so a UV mistake shows up instead of hiding
    pixels = [1.0, 0.0, 1.0, 1.0] * (size * size)
    for name, index in COLOR_INDEX.items():
        r, g, b = hex_rgb(PALETTE_HEX[name])
        col, row = index % GRID, index // GRID
        for y in range(row * CELL_PX, (row + 1) * CELL_PX):
            for x in range(col * CELL_PX, (col + 1) * CELL_PX):
                o = (y * size + x) * 4
                pixels[o:o + 4] = (r, g, b, 1.0)
    image.pixels = pixels
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    return image


def cell_uv(color):
    index = COLOR_INDEX[color]
    col, row = index % GRID, index // GRID
    return ((col + 0.5) / GRID, (row + 0.5) / GRID)


# ------------------------------------------------------------------ mesh building

class Builder:
    """Collects primitives into one bmesh; every face gets its color's UV."""

    def __init__(self):
        # no UV layer here: the parts bring theirs ("UVMap"), so the mesh ends up
        # with exactly ONE UV set. Roblox reads only TEXCOORD_0; a second, empty
        # set made every face sample one palette corner (2026-11-08).
        self.bm = bmesh.new()

    def _add(self, temp, color, smooth):
        uv = temp.loops.layers.uv.get("UVMap") or temp.loops.layers.uv.new("UVMap")
        u, v = cell_uv(color)
        for face in temp.faces:
            face.smooth = smooth
            for loop in face.loops:
                loop[uv].uv = (u, v)
        mesh = bpy.data.meshes.new("tmp")
        temp.to_mesh(mesh)
        temp.free()
        self.bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)

    @staticmethod
    def _matrix(center, rot, scale=(1, 1, 1)):
        r = Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
        return Matrix.Translation(Vector(center)) @ r @ Matrix.Diagonal((*scale, 1.0))

    def ell(self, color, center, radii, rot=(0, 0, 0), seg=(14, 9), smooth=True):
        temp = bmesh.new()
        bmesh.ops.create_uvsphere(temp, u_segments=seg[0], v_segments=seg[1], radius=1.0, matrix=self._matrix(center, rot, radii))
        self._add(temp, color, smooth)

    def ball(self, color, center, r, seg=(12, 8), smooth=True):
        self.ell(color, center, (r, r, r), seg=seg, smooth=smooth)

    def ico(self, color, center, r, sub=1, scale=(1, 1, 1), rot=(0, 0, 0), smooth=False):
        temp = bmesh.new()
        bmesh.ops.create_icosphere(temp, subdivisions=sub, radius=r, matrix=self._matrix(center, rot, scale))
        self._add(temp, color, smooth)

    def cone(self, color, base, r1, r2, h, rot=(0, 0, 0), segs=8, smooth=False):
        """Cone/frustum standing on `base`, axis +Z rotated by `rot` (degrees)."""
        temp = bmesh.new()
        m = self._matrix(base, rot) @ Matrix.Translation((0, 0, h / 2))
        bmesh.ops.create_cone(temp, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h, matrix=m)
        self._add(temp, color, smooth)

    def cyl(self, color, base, r, h, rot=(0, 0, 0), segs=12, smooth=True):
        self.cone(color, base, r, r, h, rot=rot, segs=segs, smooth=smooth)

    def box(self, color, center, size, bevel=0.0, rot=(0, 0, 0)):
        temp = bmesh.new()
        bmesh.ops.create_cube(temp, size=1.0, matrix=self._matrix(center, rot, size))
        if bevel > 0:
            bmesh.ops.bevel(temp, geom=list(temp.edges), offset=bevel, segments=2, affect="EDGES", profile=0.5)
        self._add(temp, color, bevel > 0)

    def torus(self, color, center, major, minor, rot=(0, 0, 0), seg=(24, 8)):
        temp = bmesh.new()
        m = self._matrix(center, rot)
        rings = []
        for i in range(seg[0]):
            a = 2 * math.pi * i / seg[0]
            ring = []
            for j in range(seg[1]):
                b = 2 * math.pi * j / seg[1]
                p = Vector(((major + minor * math.cos(b)) * math.cos(a), (major + minor * math.cos(b)) * math.sin(a), minor * math.sin(b)))
                ring.append(temp.verts.new(m @ p))
            rings.append(ring)
        for i in range(seg[0]):
            for j in range(seg[1]):
                a, b = rings[i], rings[(i + 1) % seg[0]]
                temp.faces.new((a[j], b[j], b[(j + 1) % seg[1]], a[(j + 1) % seg[1]]))
        bmesh.ops.recalc_face_normals(temp, faces=list(temp.faces))
        self._add(temp, color, True)

    def eyes(self, y, z, spacing, r, color="black"):
        """A pair of round eyes with a white shine, looking toward -Y."""
        for sx in (-1, 1):
            x = sx * spacing
            self.ell(color, (x, y, z), (r, r * 0.7, r * 1.15))
            self.ball("eyeShine", (x - r * 0.3, y - r * 0.6, z + r * 0.4), r * 0.33, seg=(8, 6))

    def base(self, rarity):
        self.cyl(f"r{rarity}", (0, 0, 0), 0.44, 0.07, segs=28)
        self.cyl("white", (0, 0, 0.07), 0.40, 0.012, segs=28, smooth=False)

    def finish(self, name):
        mesh = bpy.data.meshes.new(name)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        self.bm.to_mesh(mesh)
        self.bm.free()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


# ------------------------------------------------------------------ the 12 treasures
# Units: about 1.0 tall including the disc; facing -Y; disc top at z = 0.08.

def dust_bunny(b):
    b.base(1)
    b.ell("grey", (0, 0, 0.40), (0.34, 0.32, 0.30))
    for i in range(10):  # soft round puffs around the edge (not over the face): a dust-ball outline
        a = 2 * math.pi * i / 10
        if math.sin(a) < -0.5:
            continue
        b.ball("greyLight", (0.29 * math.cos(a), 0.27 * math.sin(a), 0.40 + 0.08 * math.sin(3 * a)), 0.11)
    b.ball("greyLight", (0, 0.02, 0.64), 0.13)
    for sx in (-1, 1):
        b.ell("grey", (sx * 0.12, 0.02, 0.82), (0.07, 0.05, 0.19), rot=(0, sx * 12, 0))
        b.ell("pink", (sx * 0.125, -0.025, 0.83), (0.04, 0.02, 0.13), rot=(0, sx * 12, 0))
        b.ell("white", (sx * 0.13, -0.2, 0.11), (0.08, 0.1, 0.05))
        b.ell("blush", (sx * 0.2, -0.25, 0.4), (0.05, 0.02, 0.03))
    b.eyes(-0.29, 0.47, 0.1, 0.05)
    b.ball("pink", (0, -0.32, 0.4), 0.03)


def pebble_pup(b):
    b.base(1)
    b.ell("sand", (0, 0.06, 0.31), (0.25, 0.31, 0.21))
    for p, r in (((0.17, 0.02, 0.42), 0.07), ((-0.14, 0.16, 0.44), 0.08), ((0.05, 0.27, 0.43), 0.06), ((-0.2, -0.04, 0.33), 0.06)):
        b.ell("slate", p, (r, r, r * 0.6))
    for sx in (-1, 1):
        for y in (-0.1, 0.22):
            b.ell("sand", (sx * 0.14, y, 0.12), (0.07, 0.07, 0.1))
    b.ell("sand", (0, -0.2, 0.58), (0.23, 0.21, 0.21))
    b.ell("cream", (0, -0.38, 0.53), (0.11, 0.08, 0.08))
    b.ball("black", (0, -0.46, 0.56), 0.035)
    for sx in (-1, 1):
        b.ell("slate", (sx * 0.22, -0.16, 0.56), (0.06, 0.09, 0.16), rot=(0, sx * -18, 0))
    b.ell("slate", (0.09, -0.26, 0.72), (0.06, 0.05, 0.03))
    b.eyes(-0.37, 0.63, 0.09, 0.045)
    b.ell("sand", (0, 0.37, 0.42), (0.04, 0.04, 0.09), rot=(-35, 0, 0))


def sprout_kitten(b):
    b.base(2)
    b.ell("leaf", (0, 0.06, 0.3), (0.21, 0.21, 0.23))
    b.ell("cream", (0, -0.09, 0.28), (0.13, 0.1, 0.16))
    b.ell("leaf", (0, -0.07, 0.6), (0.23, 0.2, 0.19))
    for x in (-0.07, 0.0, 0.07):
        b.ell("leafDark", (x, -0.03, 0.78), (0.02, 0.07, 0.015), rot=(25, 0, 0))
    for y in (0.0, 0.1, 0.2):
        b.ell("leafDark", (0, y, 0.52), (0.13, 0.025, 0.02))
    for sx in (-1, 1):
        b.cone("leaf", (sx * 0.13, -0.05, 0.73), 0.08, 0.0, 0.16, rot=(0, sx * 18, 0), segs=6)
        b.cone("pink", (sx * 0.13, -0.08, 0.74), 0.045, 0.0, 0.11, rot=(0, sx * 18, 0), segs=6)
        b.ell("cream", (sx * 0.08, -0.17, 0.09), (0.06, 0.07, 0.05))
    b.eyes(-0.25, 0.63, 0.09, 0.05)
    b.ball("pink", (0, -0.27, 0.58), 0.025)
    for i, p in enumerate(((0.17, 0.2, 0.14), (0.24, 0.17, 0.27), (0.25, 0.08, 0.39), (0.21, 0.0, 0.47))):
        b.ball("leafDark" if i == 3 else "leaf", p, 0.05)
    b.cyl("leafDark", (0, -0.04, 0.78), 0.016, 0.16, segs=6)
    for sx in (-1, 1):
        b.ell("leafLight", (sx * 0.07, -0.04, 0.95), (0.075, 0.03, 0.035), rot=(0, sx * -20, 0))


def puddle_duckling(b):
    b.base(2)
    b.ell("water", (0, 0, 0.085), (0.38, 0.33, 0.02))
    b.ell("sun", (0, 0.05, 0.27), (0.19, 0.23, 0.17))
    b.ell("sun", (0, -0.09, 0.5), (0.16, 0.15, 0.15))
    b.ell("orange", (0, -0.26, 0.47), (0.07, 0.06, 0.028))
    for sx in (-1, 1):
        b.ell("gold", (sx * 0.19, 0.07, 0.3), (0.04, 0.12, 0.08), rot=(10, 0, 0))
        b.ell("orange", (sx * 0.08, -0.12, 0.1), (0.06, 0.08, 0.02))
    b.cone("gold", (0, 0.25, 0.32), 0.06, 0.0, 0.12, rot=(-60, 0, 0), segs=6)
    b.eyes(-0.22, 0.55, 0.07, 0.035)
    for p, r in (((-0.11, -0.05, 0.92), 0.12), ((0.11, -0.05, 0.92), 0.12), ((0.0, -0.05, 0.99), 0.13), ((0.0, 0.03, 0.9), 0.11)):
        b.ico("cloud", p, r, sub=2, smooth=True)
    b.ell("skyLight", (0, -0.05, 0.84), (0.2, 0.1, 0.04))
    for p in ((-0.06, -0.1, 0.76), (0.05, -0.1, 0.72)):
        b.ell("sky", p, (0.022, 0.022, 0.035))


def toasty_corgi(b):
    b.base(3)
    b.box("toast", (0, 0.1, 0.27), (0.34, 0.5, 0.26), bevel=0.07)
    b.ell("crust", (0, 0.1, 0.4), (0.17, 0.25, 0.07))
    b.box("butter", (0, 0.1, 0.47), (0.12, 0.12, 0.04), bevel=0.012)
    for sx in (-1, 1):
        for y in (-0.08, 0.28):
            b.ell("toastDark", (sx * 0.12, y, 0.09), (0.06, 0.06, 0.07))
    b.ell("toast", (0, -0.22, 0.48), (0.19, 0.17, 0.17))
    b.ell("white", (0, -0.35, 0.43), (0.1, 0.07, 0.08))
    b.ball("black", (0, -0.42, 0.46), 0.03)
    for sx in (-1, 1):
        b.cone("toast", (sx * 0.11, -0.18, 0.6), 0.075, 0.01, 0.18, rot=(0, sx * 14, 0), segs=6)
        b.cone("pink", (sx * 0.11, -0.21, 0.62), 0.04, 0.0, 0.12, rot=(0, sx * 14, 0), segs=6)
    b.eyes(-0.34, 0.52, 0.08, 0.035)
    b.ball("toastDark", (0, 0.37, 0.36), 0.06)


def ember_fox(b):
    b.base(4)
    b.ell("orange", (0, 0.04, 0.3), (0.19, 0.2, 0.24))
    b.ell("cream", (0, -0.1, 0.33), (0.12, 0.08, 0.16))
    b.ell("orange", (0, -0.08, 0.6), (0.2, 0.18, 0.17))
    b.ell("cream", (0, -0.24, 0.55), (0.08, 0.08, 0.06))
    b.ball("black", (0, -0.31, 0.57), 0.028)
    for sx in (-1, 1):
        b.cone("orange", (sx * 0.12, -0.06, 0.72), 0.07, 0.0, 0.19, rot=(0, sx * 14, 0), segs=6)
        b.cone("slate", (sx * 0.145, -0.06, 0.84), 0.028, 0.0, 0.07, rot=(0, sx * 14, 0), segs=6)
        b.ell("slate", (sx * 0.08, -0.14, 0.07), (0.05, 0.06, 0.05))
    b.eyes(-0.23, 0.64, 0.075, 0.035)
    # faceted flame tail, deep orange at the root to yellow at the tip
    b.cone("orangeDeep", (0.04, 0.2, 0.1), 0.14, 0.09, 0.22, rot=(-20, 10, 0), segs=6)
    b.cone("orange", (0.06, 0.26, 0.28), 0.11, 0.05, 0.24, rot=(-5, 12, 0), segs=6)
    b.cone("flame", (0.07, 0.27, 0.48), 0.07, 0.0, 0.24, rot=(8, 10, 0), segs=6)
    b.cone("flame", (0.15, 0.25, 0.36), 0.04, 0.0, 0.16, rot=(0, 40, 0), segs=5)
    b.cone("sun", (-0.04, 0.27, 0.38), 0.035, 0.0, 0.14, rot=(0, -35, 0), segs=5)


def storm_pony(b):
    b.base(5)
    b.ell("storm", (0, 0.06, 0.42), (0.2, 0.3, 0.19))
    for sx in (-1, 1):
        for y in (-0.12, 0.24):
            b.cyl("storm", (sx * 0.11, y, 0.11), 0.06, 0.24, segs=10)
            b.box("sun", (sx * 0.11, y - 0.01, 0.105), (0.13, 0.13, 0.07), bevel=0.015)
    b.ell("storm", (0, -0.2, 0.6), (0.1, 0.1, 0.15), rot=(-25, 0, 0))
    b.ell("storm", (0, -0.31, 0.76), (0.12, 0.17, 0.12), rot=(-15, 0, 0))
    b.ell("greyLight", (0, -0.45, 0.72), (0.09, 0.08, 0.08))
    for sx in (-1, 1):
        b.cone("storm", (sx * 0.06, -0.24, 0.85), 0.04, 0.0, 0.1, rot=(0, sx * 10, 0), segs=5)
        b.ball("black", (sx * 0.035, -0.52, 0.73), 0.012)
    b.eyes(-0.43, 0.8, 0.075, 0.03)
    for p, r in (((0, -0.24, 0.89), 0.08), ((0, -0.15, 0.82), 0.1), ((0, -0.06, 0.72), 0.09), ((0.06, -0.12, 0.76), 0.07), ((-0.06, -0.12, 0.76), 0.07)):
        b.ico("stormDark", p, r, sub=2, smooth=True)
    for p, r in (((0, 0.36, 0.52), 0.1), ((0, 0.43, 0.42), 0.08), ((0.04, 0.4, 0.33), 0.06)):
        b.ico("stormDark", p, r, sub=2, smooth=True)
    # a little lightning bolt on each flank
    for sx in (-1, 1):
        b.box("sun", (sx * 0.2, 0.0, 0.47), (0.02, 0.05, 0.09), rot=(0, 0, 0))
        b.box("sun", (sx * 0.2, 0.04, 0.41), (0.02, 0.05, 0.09), rot=(30, 0, 0))


def crystal_dragonling(b):
    b.base(6)
    b.ell("lavender", (0, 0.05, 0.31), (0.22, 0.28, 0.2))
    b.ell("cream", (0, -0.08, 0.28), (0.14, 0.12, 0.14))
    for sx in (-1, 1):
        for y in (-0.08, 0.2):
            b.ell("lavender", (sx * 0.14, y, 0.1), (0.07, 0.07, 0.09))
            b.ball("cream", (sx * 0.14, y - 0.06, 0.05), 0.025, seg=(8, 6))
    b.ell("lavender", (0, -0.2, 0.58), (0.22, 0.2, 0.19))
    b.ell("lavender", (0, -0.37, 0.53), (0.12, 0.09, 0.08))
    for sx in (-1, 1):
        b.ball("violet", (sx * 0.04, -0.45, 0.56), 0.012)
        b.cone("cream", (sx * 0.1, -0.13, 0.74), 0.04, 0.0, 0.12, rot=(-15, sx * 20, 0), segs=5)
        # stubby faceted crystal wings
        b.cone("crystalBlue", (sx * 0.17, 0.1, 0.45), 0.13, 0.0, 0.03, rot=(0, sx * 70, sx * 20), segs=3)
    b.eyes(-0.36, 0.62, 0.09, 0.045)
    for p, h, c in (((0, -0.1, 0.76), 0.14, "crystalPurple"), ((0, 0.02, 0.48), 0.16, "purple"), ((0, 0.15, 0.48), 0.14, "crystalBlue"), ((0, 0.27, 0.42), 0.11, "crystalPurple")):
        b.cone(c, p, 0.055, 0.0, h, rot=(20, 0, 0), segs=4)
    b.cone("lavender", (0, 0.3, 0.24), 0.09, 0.02, 0.26, rot=(-70, 0, 0), segs=8, smooth=True)
    b.cone("crystalBlue", (0, 0.53, 0.18), 0.04, 0.0, 0.1, rot=(-70, 0, 0), segs=4)


def halo_owl(b):
    b.base(7)
    b.ell("white", (0, 0, 0.37), (0.25, 0.22, 0.29))
    b.ell("cream", (0, -0.15, 0.47), (0.18, 0.07, 0.15))
    for sx in (-1, 1):
        b.ell("gold", (sx * 0.08, -0.2, 0.5), (0.075, 0.03, 0.075))
        b.ball("black", (sx * 0.08, -0.225, 0.5), 0.042)
        b.ball("eyeShine", (sx * 0.08 - 0.015, -0.255, 0.515), 0.014, seg=(8, 6))
        b.ell("white", (sx * 0.24, 0.02, 0.36), (0.05, 0.15, 0.2), rot=(0, sx * -10, 0))
        b.ell("gold", (sx * 0.25, 0.04, 0.2), (0.045, 0.09, 0.06))
        b.ell("sun", (sx * 0.07, -0.11, 0.09), (0.05, 0.06, 0.03))
        b.cone("white", (sx * 0.12, -0.03, 0.62), 0.05, 0.0, 0.1, rot=(0, sx * 25, 0), segs=5)
    b.cone("sun", (0, -0.24, 0.44), 0.03, 0.0, 0.07, rot=(160, 0, 0), segs=5)
    b.cyl("gold", (0, 0.04, 0.63), 0.012, 0.2, segs=6)
    b.torus("gold", (0, 0.04, 0.86), 0.16, 0.026, rot=(0, 0, 0))


def starlight_stag(b):
    b.base(8)
    b.ell("midnight", (0, 0.06, 0.43), (0.16, 0.28, 0.16))
    b.ell("cream", (0, 0.04, 0.35), (0.11, 0.2, 0.08))
    for p in ((0.08, 0.0, 0.57), (-0.06, 0.14, 0.58), (0.03, 0.24, 0.55), (-0.08, -0.08, 0.55)):
        b.ball("cream", p, 0.022, seg=(8, 6))
    for sx in (-1, 1):
        for y in (-0.1, 0.22):
            b.cyl("midnight", (sx * 0.09, y, 0.08), 0.045, 0.3, segs=10)
            b.cyl("cream", (sx * 0.09, y, 0.075), 0.05, 0.05, segs=10)
    b.ell("midnight", (0, -0.17, 0.58), (0.08, 0.08, 0.13), rot=(-25, 0, 0))
    b.ell("midnight", (0, -0.23, 0.74), (0.11, 0.15, 0.11), rot=(-10, 0, 0))
    b.ell("cream", (0, -0.36, 0.71), (0.07, 0.07, 0.06))
    b.ball("black", (0, -0.42, 0.73), 0.022)
    for sx in (-1, 1):
        b.ell("midnight", (sx * 0.12, -0.18, 0.82), (0.07, 0.025, 0.035), rot=(0, sx * -25, 0))
        # constellation antlers: thin glowing lines joining star dots
        b.cyl("skyLight", (sx * 0.05, -0.2, 0.82), 0.012, 0.16, rot=(0, sx * 12, 0), segs=5)
        b.cyl("skyLight", (sx * 0.08, -0.2, 0.92), 0.01, 0.1, rot=(0, sx * 55, 0), segs=5)
        for p, r in (((sx * 0.085, -0.2, 0.98), 0.03), ((sx * 0.16, -0.2, 0.97), 0.024), ((sx * 0.06, -0.2, 0.86), 0.02)):
            b.ico("starYellow", p, r, sub=1)
    b.eyes(-0.33, 0.78, 0.065, 0.03)
    b.ell("white", (0, 0.34, 0.5), (0.035, 0.04, 0.05))


def galaxy_axolotl(b):
    b.base(9)
    b.ell("purple", (0, 0.08, 0.24), (0.18, 0.31, 0.15))
    b.ell("pink", (0, 0.0, 0.17), (0.13, 0.23, 0.08))
    b.ell("magenta", (0, -0.2, 0.38), (0.25, 0.18, 0.16))
    b.ell("purple", (0, 0.42, 0.24), (0.04, 0.2, 0.1))
    for sx in (-1, 1):
        for y in (-0.06, 0.24):
            b.ell("pink", (sx * 0.17, y, 0.1), (0.06, 0.07, 0.04))
        for k, z in enumerate((0.48, 0.4, 0.32)):
            tilt = 30 - 25 * k
            b.ell("magenta", (sx * 0.27, -0.17, z), (0.08, 0.025, 0.025), rot=(0, sx * -tilt, 0))
            b.ico("starYellow", (sx * 0.35, -0.17, z + 0.035 * (1 - k)), 0.035, sub=1)
    for p in ((0.06, 0.05, 0.38), (-0.08, 0.15, 0.37), (0.1, 0.25, 0.33), (-0.12, -0.25, 0.5), (0.13, -0.15, 0.51), (0.0, 0.3, 0.36)):
        b.ico("white", p, 0.016, sub=1)
    b.ell("violet", (0, -0.36, 0.33), (0.08, 0.02, 0.018))
    b.eyes(-0.34, 0.43, 0.11, 0.04)


def eclipse_griffin(b):
    b.base(10)
    # the left (viewer's right) half sun-gold, the right half night-violet
    for sx, c in ((-1, "gold"), (1, "violet")):
        b.ell(c, (sx * 0.06, 0.07, 0.32), (0.13, 0.26, 0.19))
        b.ell(c, (sx * 0.06, -0.2, 0.6), (0.13, 0.17, 0.17))
        b.ell(c, (sx * 0.21, 0.12, 0.47), (0.04, 0.18, 0.13), rot=(-25, sx * -15, 0))
        b.cone(c, (sx * 0.1, -0.15, 0.73), 0.05, 0.0, 0.12, rot=(0, sx * 25, 0), segs=5)
        for y in (-0.06, 0.22):
            b.ell(c, (sx * 0.12, y, 0.1), (0.06, 0.06, 0.09))
    b.ell("cream", (0, -0.16, 0.42), (0.11, 0.08, 0.12))
    b.cone("sun", (0, -0.34, 0.6), 0.05, 0.0, 0.12, rot=(105, 0, 0), segs=6)
    b.eyes(-0.33, 0.66, 0.08, 0.04)
    b.cyl("goldDeep", (0.0, 0.3, 0.3), 0.018, 0.22, rot=(-60, 0, 0), segs=6)
    b.ico("violet", (0.0, 0.48, 0.42), 0.06, sub=1, smooth=True)
    # eclipse ring: a dark disc with a glowing gold rim behind the head
    b.cyl("ink", (0, 0.02, 0.66), 0.2, 0.02, rot=(90, 0, 0), segs=24)
    b.torus("gold", (0, 0.0, 0.66), 0.21, 0.025, rot=(90, 0, 0))


TREASURES = [
    ("DustBunny", dust_bunny),
    ("PebblePup", pebble_pup),
    ("SproutKitten", sprout_kitten),
    ("PuddleDuckling", puddle_duckling),
    ("ToastyCorgi", toasty_corgi),
    ("EmberFox", ember_fox),
    ("StormPony", storm_pony),
    ("CrystalDragonling", crystal_dragonling),
    ("HaloOwl", halo_owl),
    ("StarlightStag", starlight_stag),
    ("GalaxyAxolotl", galaxy_axolotl),
    ("EclipseGriffin", eclipse_griffin),
]


# ------------------------------------------------------------------ material, previews, export

def make_material(image):
    mat = bpy.data.materials.new("SFT_Treasure")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.55
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def render_previews(objects, preview_dir):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = 512
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 55
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = (1.35, -2.1, 1.25)
    direction = Vector((0, 0, 0.47)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    for obj in objects:
        for other in objects:
            other.hide_render = other is not obj
        scene.render.filepath = os.path.join(preview_dir, obj.name + ".png")
        bpy.ops.render.render(write_still=True)
    for obj in objects:
        obj.hide_render = False
    bpy.data.objects.remove(cam)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.abspath(argv[0] if argv else "assets/models")
    preview_dir = os.path.abspath(argv[1]) if len(argv) > 1 else None
    os.makedirs(out_dir, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    image = make_palette(os.path.join(out_dir, "pets_palette.png"))
    material = make_material(image)

    objects = []
    for name, build in TREASURES:
        builder = Builder()
        build(builder)
        obj = builder.finish(name)
        obj.data.materials.append(material)
        objects.append(obj)
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        dims = obj.dimensions
        print(f"[treasure] {name}: {tris} tris, {dims.x:.2f} x {dims.y:.2f} x {dims.z:.2f}")

    if preview_dir:
        os.makedirs(preview_dir, exist_ok=True)
        render_previews(objects, preview_dir)

    path = os.path.join(out_dir, "pets_treasures.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True)
    print(f"[treasure] exported {path}")


main()
