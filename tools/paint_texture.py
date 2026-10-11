#!/usr/bin/env python3
"""Usage: python tools/paint_texture.py <model.glb> <albedo.png> <out.png> [options]  (the hand-painted pass for a character's albedo; --help for options)

Derives a hand-painted albedo from a generated (Meshy) one: big soft
value shapes, no fibre noise or speckle, a quieter pattern, painted-in
occlusion and light. The source texture is never written.

The Wanderer (v3) is made with:
    python tools/paint_texture.py assets/models/wanderer/wanderer_v3.glb
        assets/models/wanderer/wanderer_v3_bound_output.png
        assets/models/wanderer/wanderer_v3_painted.png
        --blender "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
        --lift-target 0.30,0.32,0.36 --accent-color 0.70,0.66,0.56
        --accent-above 0.7 --accent-area 0.0005
        --pin-dark 0.06,0.06,0.07 --boot-color 0.42,0.30,0.20
and his sword with:
    python tools/paint_texture.py assets/models/wanderer/sword.glb
        assets/models/wanderer/sword_0.jpg assets/models/wanderer/sword_painted.png
        --image-space --target-mean 0.50,0.49,0.46

Generated atlases are thousands of tiny UV islands, so an image-space
blur mixes unrelated islands and shows as seams on the model. The
default pass works on the mesh surface instead:
  1. each vertex's colour is its triangles' texture colour, averaged;
  2. vertices sharing a position are welded, so smoothing crosses seams;
  3. a neighbour median removes speckle;
  4. two smoothing scales split big shapes from the pattern, and the
     pattern keeps --detail of its contrast;
  5. regions are recoloured: the lighter slate (the cloak) lifted to
     --lift-target, large pale patches (above --accent-above: the
     Wanderer's collar, not his hem pattern) to --accent-color, small
     ones smoothed away, the dark hood interior pinned to --pin-dark,
     the boots (non-slate, below --boot-below, near each foot's axis)
     to --boot-color with the sole a little darker;
  6. ambient occlusion baked in Blender (tools/bake_ao_blender.py),
     smoothed and normalised, multiplied in at --ao-strength, and a
     top-down --gradient (lighter at the head, darker at the hem);
  7. the result is painted back into the same UV layout at --size,
     continuous (or posterised to --levels over the on-model range),
     and padded so islands don't bleed under mipmaps.

--image-space is for low-poly props whose islands are few and large
(the sword): a median and a light blur on the image, kept inside the
islands by padding, then scaled to --target-mean.

Needs numpy, scipy and Pillow (and Blender for --blender). All UV-mapped
primitives in the glb are assumed to share the one albedo texture.
"""
import argparse
import json
import os
import struct
import subprocess
import tempfile

import numpy as np
import scipy.sparse as sparse
import scipy.sparse.csgraph as csgraph
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.spatial import cKDTree

LUMA = np.array([0.299, 0.587, 0.114])


def load_glb(path):
    """Positions, UVs and triangles of every UV-mapped primitive, merged."""
    data = open(path, "rb").read()
    json_length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + json_length])
    bin_start = 20 + json_length + 8

    def accessor(index):
        acc = gltf["accessors"][index]
        view = gltf["bufferViews"][acc["bufferView"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
        dtype = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[acc["componentType"]]
        offset = bin_start + view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        values = np.frombuffer(data, dtype, acc["count"] * width, offset)
        return values.reshape(-1, width) if width > 1 else values

    positions, uvs, triangles = [], [], []
    base = 0
    for mesh in gltf["meshes"]:
        for primitive in mesh["primitives"]:
            attributes = primitive["attributes"]
            if "TEXCOORD_0" not in attributes or "indices" not in primitive:
                continue
            pos = accessor(attributes["POSITION"]).astype(np.float64)
            positions.append(pos)
            uvs.append(accessor(attributes["TEXCOORD_0"]).astype(np.float64))
            triangles.append(accessor(primitive["indices"]).reshape(-1, 3).astype(np.int64) + base)
            base += len(pos)
    return np.concatenate(positions), np.concatenate(uvs), np.concatenate(triangles)


def bilinear(image, uv):
    h, w = image.shape[:2]
    x = np.clip(uv[:, 0] * w - 0.5, 0, w - 1.001)
    y = np.clip(uv[:, 1] * h - 0.5, 0, h - 1.001)
    x0 = x.astype(int)
    y0 = y.astype(int)
    fx = (x - x0)[:, None]
    fy = (y - y0)[:, None]
    return (image[y0, x0] * (1 - fx) * (1 - fy) + image[y0, x0 + 1] * fx * (1 - fy)
            + image[y0 + 1, x0] * (1 - fx) * fy + image[y0 + 1, x0 + 1] * fx * fy)


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)


def colour_arg(text):
    values = [float(v) for v in text.split(",")]
    if len(values) != 3:
        raise argparse.ArgumentTypeError("expected r,g,b")
    return np.array(values)


def raster_uv(uv, triangles, colours, size):
    """Vertex colours interpolated into the UV layout: image and coverage."""
    image = np.zeros((size, size, 3))
    covered = np.zeros((size, size), bool)
    points = uv * size
    for tri in triangles:
        p = points[tri]
        x0, y0 = np.maximum(np.floor(p.min(0)).astype(int), 0)
        x1, y1 = np.minimum(np.ceil(p.max(0)).astype(int), size - 1)
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        e0 = p[1] - p[0]
        e1 = p[2] - p[0]
        den = e0[0] * e1[1] - e1[0] * e0[1]
        if abs(den) < 1e-12:
            continue
        dx = xs - p[0, 0]
        dy = ys - p[0, 1]
        b1 = (dx * e1[1] - e1[0] * dy) / den
        b2 = (e0[0] * dy - dx * e0[1]) / den
        b0 = 1 - b1 - b2
        # Conservative by about half a texel, so thin islands have no holes.
        slack = 0.7 / max(abs(den) ** 0.5, 1e-6)
        inside = (b0 >= -slack) & (b1 >= -slack) & (b2 >= -slack)
        if not inside.any():
            continue
        colour = b0[..., None] * colours[tri[0]] + b1[..., None] * colours[tri[1]] + b2[..., None] * colours[tri[2]]
        rows = (ys[inside] - 0.5).astype(int)
        cols = (xs[inside] - 0.5).astype(int)
        image[rows, cols] = colour[inside]
        covered[rows, cols] = True
    return image, covered


def uv_coverage(uv, triangles, size):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    for tri in uv[triangles] * size:
        draw.polygon([tuple(p) for p in tri], fill=255)
    return np.asarray(mask) > 0


def pad(image, covered, px):
    """Each uncovered texel takes its nearest covered one, up to px away."""
    distance, (iy, ix) = ndimage.distance_transform_edt(~covered, return_indices=True)
    out = image[iy, ix]
    out[distance > px] = image[covered].mean(0)
    return out


def save(image, path):
    out = (np.clip(image, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(out).save(path)
    return out.astype(np.float64) / 255


def mean_rgb(colours, weights):
    return np.round((colours * weights[:, None]).sum(0) / max(weights.sum(), 1e-12), 3)


def image_space(args):
    source = np.asarray(Image.open(args.albedo).convert("RGB")).astype(np.float64) / 255
    _, uv, triangles = load_glb(args.model)
    covered = uv_coverage(uv, triangles, source.shape[0])
    # Padding first keeps the median inside each island at its edges.
    image = pad(source, covered, 10 ** 6)
    image = np.stack([ndimage.median_filter(image[..., c], size=args.median) for c in range(3)], -1)
    image = ndimage.gaussian_filter(image, sigma=(args.blur, args.blur, 0))
    image = np.asarray(Image.fromarray((np.clip(image, 0, 1) * 255).astype(np.uint8)).resize(
        (args.size, args.size), Image.LANCZOS)).astype(np.float64) / 255
    small_covered = uv_coverage(uv, triangles, args.size)
    before = image[small_covered].mean(0)
    if args.target_mean is not None:
        # Only texels lighter than --keep-dark are lifted (the blade, not
        # the grip), each channel by whatever reaches the target average.
        weight = smoothstep(args.keep_dark, args.keep_dark + 0.2, image @ LUMA)[..., None]
        lift = (args.target_mean - before) / np.maximum((image * weight)[small_covered].mean(0), 1e-4)
        image = image * (1 + weight * lift)
    out = save(pad(np.clip(image, 0, 1), small_covered, args.pad), args.out)
    print("mean rgb on the model: before %s, after %s" % (
        np.round(source[covered].mean(0), 3), np.round(out[small_covered].mean(0), 3)))


def bake_ao(args, positions, welded, count):
    """Per-welded-vertex AO from Blender, or None without --blender."""
    if not args.blender:
        return None
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bake_ao_blender.py")
    with tempfile.TemporaryDirectory() as scratch:
        out = os.path.join(scratch, "ao.npy")
        subprocess.run([args.blender, "-b", "--factory-startup", "--python", script, "--",
                        os.path.abspath(args.model), out, str(args.ao_samples), str(args.ao_distance)],
                       check=True, stdout=subprocess.DEVNULL)
        rows = np.load(out)
    distance, nearest = cKDTree(rows[:, :3]).query(positions)
    if distance.max() > 1e-4 * np.ptp(positions, 0).max():
        raise SystemExit("bake_ao_blender's vertices don't match the glb's (off by %.6f)" % distance.max())
    total = np.bincount(welded, rows[nearest, 3], count)
    return total / np.maximum(np.bincount(welded, minlength=count), 1)


def mesh_space(args):
    positions, uv, triangles = load_glb(args.model)
    source = np.asarray(Image.open(args.albedo).convert("RGB")).astype(np.float64) / 255

    # 1. Triangle colour from seven samples, then area-weighted per vertex.
    weights = np.array([[1, 0, 0], [0, 1, 0], [0, 0, 1], [.5, .5, 0], [0, .5, .5], [.5, 0, .5], [1 / 3, 1 / 3, 1 / 3]])
    samples = np.einsum("sk,tkc->tsc", weights, uv[triangles]).reshape(-1, 2)
    tri_colour = bilinear(source, samples).reshape(len(triangles), len(weights), 3).mean(1)
    corners = positions[triangles]
    area = 0.5 * np.linalg.norm(np.cross(corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0]), axis=1)

    # 2. Weld by position.
    key = np.round(positions / (np.ptp(positions, 0).max() * 1e-5)).astype(np.int64)
    _, welded = np.unique(key, axis=0, return_inverse=True)
    welded = welded.ravel()
    count = welded.max() + 1
    wtri = welded[triangles]
    colour_sum = np.zeros((count, 3))
    area_sum = np.zeros(count)
    for k in range(3):
        np.add.at(colour_sum, wtri[:, k], tri_colour * area[:, None])
        np.add.at(area_sum, wtri[:, k], area)
    colour = colour_sum / np.maximum(area_sum, 1e-12)[:, None]
    vertex_area = area_sum / 3
    height = np.zeros(count)
    height[welded] = positions[:, 1]
    height = (height - height.min()) / max(np.ptp(height), 1e-12)
    ground = np.zeros((count, 2))
    ground[welded] = positions[:, [0, 2]]

    edges = np.concatenate([wtri[:, [0, 1]], wtri[:, [1, 2]], wtri[:, [2, 0]]])
    edges = np.unique(np.sort(edges, axis=1), axis=0)
    edges = np.concatenate([edges, edges[:, ::-1]])
    edges = edges[np.argsort(edges[:, 0], kind="stable")]
    degree = np.bincount(edges[:, 0], minlength=count)
    start = np.concatenate([[0], np.cumsum(degree)[:-1]])
    neighbours = np.full((count, degree.max() + 1), -1)
    neighbours[:, 0] = np.arange(count)
    neighbours[edges[:, 0], np.arange(len(edges)) - start[edges[:, 0]] + 1] = edges[:, 1]
    valid = neighbours >= 0
    safe = np.where(valid, neighbours, 0)
    valid_count = valid.sum(1)

    def smooth(values, passes):
        values = values.copy()
        mask = valid if values.ndim == 1 else valid[..., None]
        norm = valid_count if values.ndim == 1 else valid_count[:, None]
        for _ in range(passes):
            values = 0.5 * values + 0.5 * np.where(mask, values[safe], 0).sum(1) / norm
        return values

    # 3. Speckle: median of the vertex and its neighbours.
    stack = colour[safe]
    stack[~valid] = np.nan
    colour = np.nanmedian(stack, axis=1)
    original = colour.copy()

    # 4. Two scales; the pattern keeps args.detail of its contrast.
    detail = smooth(colour, args.detail_passes)
    base = smooth(detail, args.base_passes - args.detail_passes)
    painted = base + args.detail * (detail - base)

    # 5. Regions, judged on the colours before any recolouring.
    pale = detail @ LUMA > args.accent_luma
    pale_edges = edges[pale[edges[:, 0]] & pale[edges[:, 1]]]
    graph = sparse.coo_matrix((np.ones(len(pale_edges)), (pale_edges[:, 0], pale_edges[:, 1])), shape=(count, count))
    _, patch = csgraph.connected_components(graph, directed=False)
    patch_area = np.bincount(patch, weights=vertex_area * pale, minlength=patch.max() + 1)
    accent = pale & (patch_area[patch] > args.accent_area * vertex_area.sum()) & (height > args.accent_above)
    print("pale accents: %d large patches kept, %d small ones smoothed away" % (
        len(np.unique(patch[accent])), len(np.unique(patch[pale & ~accent]))))
    dark = (original @ LUMA < args.pin_dark_luma) & (height > args.pin_dark_above)
    painted_luma = painted @ LUMA
    slate = (painted[:, 2] - painted[:, 0] > args.slate_blue) & ~accent & ~dark
    cloak = slate & (painted_luma > args.lift_luma)
    # Boots: the leather below --boot-below near either foot's vertical
    # axis (the cloak's hem hangs further out; the trousers are slate).
    feet = height < 0.05
    axes = [ground[feet & (np.sign(ground[:, 0]) == side)].mean(0) for side in (-1, 1)
            if (feet & (np.sign(ground[:, 0]) == side)).any()]
    to_foot = np.min([np.linalg.norm(ground - axis, axis=1) for axis in axes], axis=0)
    # Pale is the cloak's hem pattern where it hangs among the boots.
    boot = (height < args.boot_below) & (to_foot < args.boot_radius) & ~slate & ~pale & ~dark
    sole = boot & (height < args.sole_below)
    regions = {"cloak (slate above %.2f)" % args.lift_luma: cloak, "inner clothes (slate below)": slate & ~cloak,
               "large pale patches": accent, "hood interior": dark, "boots": boot, "  of which the sole": sole,
               "whole model": np.ones(count, bool)}
    before = {name: mean_rgb(original, vertex_area * mask) for name, mask in regions.items()}

    # 6. Painted-in occlusion and light, before the recolours, so their
    # targets are the averages that end up on the model.
    shade = 1 + args.gradient * (2 * height - 1)
    ao = bake_ao(args, positions, welded, count)
    if ao is not None:
        ao = smooth(ao, args.ao_passes)
        ao = np.clip(ao / max(np.percentile(ao, args.ao_open_percentile), 1e-4), 0, 1)
        occlusion = 1 - args.ao_strength * (1 - ao)
        print("ao: shading factor median %.3f, 10th percentile %.3f" % (np.median(occlusion), np.percentile(occlusion, 10)))
        shade = shade * occlusion
    painted = painted * shade[:, None]
    if args.lift_target is not None:
        # A soft ramp across the threshold, so the lift leaves no edge.
        ramp = slate * smoothstep(args.lift_luma - 0.04, args.lift_luma + 0.04, painted_luma)
        gain = args.lift_target / np.maximum(mean_rgb(painted, vertex_area * cloak), 1e-4)
        painted = painted * (1 + ramp[:, None] * (gain - 1))
    if args.boot_color is not None and boot.any():
        # Per-channel gain to the target average, the sole shaded under
        # it, feathered at the boot tops like the accents.
        boot_shade = np.where(sole, args.sole_shade, 1.0)
        gain = args.boot_color / np.maximum(mean_rgb(painted * boot_shade[:, None], vertex_area * boot), 1e-4)
        target = painted * gain * boot_shade[:, None]
        weight = np.clip(np.maximum(smooth(boot.astype(np.float64), args.accent_feather), boot * 1.0) * 2, 0, 1)
        weight = weight * (height < args.boot_below + 0.05) * ~slate * ~pale
        painted = painted + weight[:, None] * (target - painted)
    if args.accent_color is not None:
        accent_luma = (detail[accent] @ LUMA) * shade[accent]
        relative = accent_luma / max(np.average(accent_luma, weights=vertex_area[accent]), 1e-4)
        # Feathered over a few rings of neighbours, so the edge is soft.
        weight = np.maximum(smooth(accent.astype(np.float64), args.accent_feather), accent * 1.0)
        weight = np.clip(weight * 2, 0, 1)
        cream = np.tile(args.accent_color, (count, 1))
        cream[accent] = args.accent_color * relative[:, None]
        painted = painted + weight[:, None] * (cream - painted)
    if args.pin_dark is not None:
        painted[dark] = args.pin_dark
    painted = np.clip(painted, 0, 1)

    # 7. Back into the UV layout, padded.
    image, covered = raster_uv(uv, triangles, painted[welded], args.size)
    if args.levels > 0:
        luma = image @ LUMA
        low, high = np.percentile(luma[covered], [1, 99])
        step = (high - low) / args.levels
        level = np.clip(np.floor((luma - low) / step), 0, args.levels - 1)
        image = np.clip(image * ((low + (level + 0.5) * step) / np.maximum(luma, 1e-4))[..., None], 0, 1)
        print("cut-offs between levels: " + ", ".join("%.3f" % (low + i * step) for i in range(1, args.levels)))
    save(pad(image, covered, args.pad), args.out)

    print("mean rgb by region, before -> after (area-weighted, on the mesh):")
    for name, mask in regions.items():
        print("  %-30s %5.1f%%  %s -> %s" % (name, 100 * vertex_area[mask].sum() / vertex_area.sum(),
                                            before[name], mean_rgb(painted, vertex_area * mask)))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("model")
    parser.add_argument("albedo")
    parser.add_argument("out")
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--levels", type=int, default=0, help="posterise to this many levels; 0 keeps values continuous")
    parser.add_argument("--pad", type=int, default=8)
    parser.add_argument("--detail", type=float, default=0.3, help="pattern contrast kept (0.3 = cut by 70%%)")
    parser.add_argument("--base-passes", type=int, default=40, help="smoothing passes for the big shapes")
    parser.add_argument("--detail-passes", type=int, default=4, help="smoothing passes for the pattern scale")
    parser.add_argument("--accent-luma", type=float, default=0.42, help="luminance a pale accent needs")
    parser.add_argument("--accent-area", type=float, default=0.004, help="share of the surface a pale patch needs to stay")
    parser.add_argument("--accent-above", type=float, default=0.0, help="share of the model's height a pale patch must sit above")
    parser.add_argument("--accent-feather", type=int, default=4, help="smoothing passes that soften the accents' edges")
    parser.add_argument("--accent-color", type=colour_arg, help="recolour the large pale patches (r,g,b)")
    parser.add_argument("--slate-blue", type=float, default=0.02, help="blue over red that makes a colour slate")
    parser.add_argument("--lift-luma", type=float, default=0.20, help="slate above this luminance is the cloak")
    parser.add_argument("--lift-target", type=colour_arg, help="the cloak's average after the lift (r,g,b)")
    parser.add_argument("--pin-dark", type=colour_arg, help="colour for the dark region at the top (hood interior)")
    parser.add_argument("--pin-dark-luma", type=float, default=0.12)
    parser.add_argument("--pin-dark-above", type=float, default=0.85, help="share of the model's height it sits above")
    parser.add_argument("--boot-color", type=colour_arg, help="recolour the boots to this average (r,g,b)")
    parser.add_argument("--boot-below", type=float, default=0.27, help="share of the model's height the boots reach to")
    parser.add_argument("--boot-radius", type=float, default=0.15, help="metres from a foot's vertical axis that count as boot")
    parser.add_argument("--sole-below", type=float, default=0.03, help="share of the model's height that is sole")
    parser.add_argument("--sole-shade", type=float, default=0.9, help="the sole's value against the rest of the boot")
    parser.add_argument("--blender", help="Blender executable; bakes ambient occlusion when given")
    parser.add_argument("--ao-strength", type=float, default=0.35)
    parser.add_argument("--ao-distance", type=float, default=0.08, help="occlusion distance in metres")
    parser.add_argument("--ao-samples", type=int, default=64)
    parser.add_argument("--ao-passes", type=int, default=12, help="smoothing passes over the baked AO")
    parser.add_argument("--ao-open-percentile", type=float, default=90, help="AO percentile that counts as fully open")
    parser.add_argument("--gradient", type=float, default=0.1, help="top-down light: +this at the head, -this at the feet")
    parser.add_argument("--image-space", action="store_true", help="image-space denoise for props with few, large islands")
    parser.add_argument("--median", type=int, default=5, help="--image-space median size, source pixels")
    parser.add_argument("--blur", type=float, default=1.0, help="--image-space blur sigma, source pixels")
    parser.add_argument("--keep-dark", type=float, default=0.15, help="--image-space: luminance below which --target-mean leaves texels as they are")
    parser.add_argument("--target-mean", type=colour_arg, help="--image-space: scale to this on-model average (r,g,b)")
    args = parser.parse_args()
    if args.image_space:
        image_space(args)
    else:
        mesh_space(args)


if __name__ == "__main__":
    main()
