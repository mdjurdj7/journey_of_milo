#!/usr/bin/env python3
"""Usage: python tools/darken_part.py <model.glb> <albedo> <out> [--target 0.58] [--percentile 90] [--grow 3]

Darkens one part of a model in its colour map, and nothing else: the
part is the connected piece of mesh (vertices welded by position) that
holds the model's highest point. Its triangles' UV islands are
rasterised into a mask, grown by --grow texels so the seams don't keep a
bright rim, and the texels under it are scaled - one factor, hue kept -
so their --percentile luminance lands on --target. The source map is
never written.

The value rule it serves (05_REGION_01 §8): dry sand (0.74, 0.70, 0.60)
is the brightest large surface, and props stay darker - a step below is
about 0.58, exposed stone's value. That is the albedo; check the frame.
A face turned to the sun renders brighter than its map, against sand
that renders darker (the floor 3 field: stone x1.09, sand x0.89), so a
part may need a lower --target to land a step below the sand on screen.

Floor 3's grindstone, whose stone wheel came out brighter than the sand
(rendered: wheel p90 0.81 on sand 0.62; at --target 0.58 still level
with it; at 0.49 a step below):
    python tools/darken_part.py
        "assets/models/props/glassbone grindstone/grindstone.glb"
        "assets/models/props/glassbone grindstone/grindstone_0.jpg"
        "assets/models/props/glassbone grindstone/grindstone_valued.png"
        --target 0.49
"""
import argparse
import json
import struct

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

LUMA = np.array([0.2126, 0.7152, 0.0722])


def read_glb(path):
    data = open(path, "rb").read()
    length = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + length])
    binary = 20 + length + 8
    prim = doc["meshes"][0]["primitives"][0]

    def accessor(index, width):
        acc = doc["accessors"][index]
        view = doc["bufferViews"][acc["bufferView"]]
        start = binary + view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        dtype = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[acc["componentType"]]
        count = acc["count"] * width
        values = np.frombuffer(data[start:start + count * np.dtype(dtype).itemsize], dtype)
        return values.reshape(-1, width) if width > 1 else values

    positions = accessor(prim["attributes"]["POSITION"], 3)
    uvs = accessor(prim["attributes"]["TEXCOORD_0"], 2)
    triangles = accessor(prim["indices"], 1).reshape(-1, 3)
    return positions, uvs, triangles


def top_part(positions, triangles):
    """Triangle indices of the welded piece holding the highest vertex."""
    _, welded = np.unique(np.round(positions, 4), axis=0, return_inverse=True)
    welded = welded.ravel()
    corners = welded[triangles]
    rows = np.concatenate([corners[:, 0], corners[:, 1], corners[:, 2]])
    cols = np.concatenate([corners[:, 1], corners[:, 2], corners[:, 0]])
    size = welded.max() + 1
    graph = coo_matrix((np.ones(len(rows)), (rows, cols)), shape=(size, size))
    _, labels = connected_components(graph, directed=False)
    top = labels[welded[np.argmax(positions[:, 1])]]
    return np.flatnonzero(labels[corners[:, 0]] == top)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("model")
    parser.add_argument("albedo")
    parser.add_argument("out")
    parser.add_argument("--target", type=float, default=0.58, help="luminance the part's --percentile lands on")
    parser.add_argument("--percentile", type=float, default=90.0)
    parser.add_argument("--grow", type=int, default=3, help="texels the mask is grown by")
    args = parser.parse_args()

    positions, uvs, triangles = read_glb(args.model)
    part = top_part(positions, triangles)
    source = Image.open(args.albedo).convert("RGB")
    width, height = source.size
    mask_image = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(mask_image)
    for tri in triangles[part]:
        draw.polygon([(float(uvs[i][0]) * width, float(uvs[i][1]) * height) for i in tri], fill=255)
    if args.grow > 0:
        mask_image = mask_image.filter(ImageFilter.MaxFilter(2 * args.grow + 1))
    mask = np.asarray(mask_image) > 127
    pixels = np.asarray(source).astype(np.float64) / 255.0
    luma = pixels[mask] @ LUMA
    before = np.percentile(luma, args.percentile)
    factor = min(1.0, args.target / max(before, 1e-6))
    pixels[mask] *= factor
    Image.fromarray(np.clip(pixels * 255.0 + 0.5, 0, 255).astype(np.uint8)).save(args.out, quality=95)
    after = np.percentile(pixels[mask] @ LUMA, args.percentile)
    print("%d triangles, %.1f%% of the map; p%g luminance %.3f -> %.3f (x%.3f), mean %.3f -> %.3f"
          % (len(part), 100.0 * mask.mean(), args.percentile, before, after, factor, luma.mean(), (pixels[mask] @ LUMA).mean()))


if __name__ == "__main__":
    main()
