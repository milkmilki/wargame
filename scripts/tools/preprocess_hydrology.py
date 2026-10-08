"""Build seed-independent vector drainage from a floating-point DEM.

Offline dependencies only: numpy, scipy, numba, Pillow. Godot reads the JSON.
No observed rivers, climate, or population data are used. Geometry is D8 on the
source DEM, with bounded simplification; province rasterization happens later.
"""
from __future__ import annotations

import argparse
import hashlib
import heapq
import json
import math
import time
from pathlib import Path

import numpy as np
from numba import njit
from PIL import Image
from scipy import ndimage, sparse

VERSION = "vector_drainage_v3"
MAX_FILL_METRES = 30.0
MIN_BASIN_MEAN_RADIUS = 0.004 # projected map-height units
MIN_CHANNEL_AREA = 8.0  # equivalent 256x256 projected cells
OFFSETS = ((-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1))


@njit(cache=True)
def priority_flood(dem, roots, sea):
    height, width = dem.shape
    z = dem.ravel()
    seen = sea.copy()
    filled = z.copy()
    parent = np.full(z.size, -1, np.int32)
    heap = [(0.0, np.int64(0))]
    heap.pop()
    for i in range(z.size):
        y, x = i // width, i % width
        seed = roots[i] or x == 0 or y == 0 or x == width - 1 or y == height - 1
        if seen[i] and not seed:
            for dy, dx in OFFSETS:
                yy, xx = y + dy, x + dx
                if 0 <= yy < height and 0 <= xx < width and not sea[yy * width + xx]:
                    seed = True
                    break
        if seed:
            seen[i] = True
            heapq.heappush(heap, (np.float64(z[i]), np.int64(i)))
    while heap:
        level, i = heapq.heappop(heap)
        y, x = i // width, i % width
        for dy, dx in OFFSETS:
            yy, xx = y + dy, x + dx
            if not (0 <= yy < height and 0 <= xx < width):
                continue
            j = yy * width + xx
            if seen[j]:
                continue
            seen[j] = True
            filled[j] = max(z[j], level)
            parent[j] = i
            heapq.heappush(heap, (np.float64(filled[j]), np.int64(j)))
    return filled, parent


@njit(cache=True)
def receivers(dem, filled, parent, roots, sea, aspect):
    height, width = dem.shape
    z = dem.ravel()
    downstream = parent.copy()
    dx_scale = aspect * height / width
    for i in range(z.size):
        if sea[i] or roots[i]:
            downstream[i] = -1
            continue
        y, x = i // width, i % width
        best = 0.0
        for dy, dx in OFFSETS:
            yy, xx = y + dy, x + dx
            if 0 <= yy < height and 0 <= xx < width:
                j = yy * width + xx
                slope = (filled[i] - filled[j]) / math.sqrt(dy * dy + (dx * dx_scale) ** 2)
                if slope > best:
                    best = slope
                    downstream[i] = j
    degree = np.zeros(z.size, np.uint8)
    for j in downstream:
        if j >= 0:
            degree[j] += 1
    order = np.empty(z.size, np.int32)
    tail = 0
    for i in range(z.size):
        if degree[i] == 0:
            order[tail] = i
            tail += 1
    head = 0
    area = (~sea).astype(np.float64) * (aspect * 65536.0 / z.size)
    while head < tail:
        i = order[head]
        head += 1
        j = downstream[i]
        if j >= 0:
            area[j] += area[i]
            degree[j] -= 1
            if degree[j] == 0:
                order[tail] = j
                tail += 1
    if tail != z.size:
        raise ValueError("Drainage cycle")
    return downstream, order, area


def ocean_mask(dem):
    # Large enclosed water (Black Sea/Caspian) must terminate rivers even if
    # its strait is unresolved. Isolated negative DEM spikes inside a valley
    # are handled by depression conditioning, not invented ocean outlets.
    labels, _ = ndimage.label(dem <= 0, np.ones((3, 3)))
    coast = np.unique(np.concatenate((labels[0], labels[-1], labels[:, 0], labels[:, -1])))
    areas = np.bincount(labels.ravel())
    water = areas >= max(16, 4 * dem.size / 65536)
    water[coast] = True
    water[0] = False
    return water[labels].ravel()


def drainage(dem, aspect):
    sea = ocean_mask(dem)
    roots = np.zeros(dem.size, bool)
    filled, parent = priority_flood(dem, roots, sea)
    labels, count = ndimage.label((filled.reshape(dem.shape) - dem) > 0.01, np.ones((3, 3)))
    if count:
        ids = np.arange(1, count + 1)
        rise = ndimage.mean(filled.reshape(dem.shape) - dem, labels, ids)
        radius = ndimage.mean(ndimage.distance_transform_edt(labels > 0, sampling=(1.0 / dem.shape[0], aspect / dem.shape[1])), labels, ids)
        areas = np.bincount(labels.ravel())[1:]
        retained = ids[(rise > MAX_FILL_METRES) & (areas >= max(16, 4 * dem.size / 65536)) & (radius >= MIN_BASIN_MEAN_RADIUS)]
        for point in ndimage.minimum_position(dem, labels, retained):
            roots[np.ravel_multi_index(point, dem.shape)] = True
        # Repeat with real closed-basin floors as outlets, instead of filling
        # them to sea level. Nested small DEM pits may still be conditioned.
        if len(retained):
            filled, parent = priority_flood(dem, roots, sea)
    downstream, order, area = receivers(dem, filled, parent, roots, sea, aspect)
    return downstream, order, area, roots, filled


@njit(cache=True)
def catchment_owners(downstream, order, channel_owner):
    owner = channel_owner.copy()
    for i in order[::-1]:
        if owner[i] < 0 and downstream[i] >= 0:
            owner[i] = owner[downstream[i]]
    return owner


def simplify(points, tolerance):
    """RDP with a metric tolerance and exact endpoint/junction preservation."""
    keep = np.zeros(len(points), bool)
    keep[[0, -1]] = True
    pending = [(0, len(points) - 1)]
    while pending:
        first, last = pending.pop()
        if last <= first + 1:
            continue
        delta = points[last] - points[first]
        v = points[first + 1:last] - points[first]
        t = np.clip((v @ delta) / max(float(delta @ delta), 1e-20), 0, 1)
        distances = np.sum((v - t[:, None] * delta) ** 2, axis=1)
        k = int(np.argmax(distances))
        if distances[k] > tolerance * tolerance:
            mid = first + 1 + k
            keep[mid] = True
            pending.extend(((first, mid), (mid, last)))
    return points[keep]


def vector_network(dem, aspect, downstream, order, area, roots, ports=()):
    height, width = dem.shape
    sea = ocean_mask(dem)
    active = (area >= MIN_CHANNEL_AREA) & (downstream >= 0) & ~sea
    for port in ports:
        node = port["node"]
        while downstream[node] >= 0:
            active[node] = True
            node = int(downstream[node])
    upstream = np.bincount(downstream[active], minlength=dem.size)
    starts = np.flatnonzero(active & (upstream != 1))
    start_ids = {int(node): i for i, node in enumerate(starts)}
    owner = np.full(dem.size, -1, np.int32)
    reaches = []
    for river_id, start in enumerate(starts):
        nodes = [int(start)]
        node = int(start)
        while active[node]:
            owner[node] = river_id
            node = int(downstream[node])
            nodes.append(node)
            if node in start_ids:
                break
        p = np.array([((i % width + 0.5) / width * aspect, (i // width + 0.5) / height) for i in nodes])
        # 0.7 source pixels: eliminate grid stairs without moving the channel
        # to another valley. Topology endpoints are never independently moved.
        p = simplify(p, 0.7 / height)
        p[:, 0] /= aspect
        end = nodes[-1]
        kind = "junction" if end in start_ids else ("sea" if sea[end] else ("basin" if roots[end] else "crop"))
        # The junction's area already includes OTHER branches. Using it here
        # makes all incoming reaches appear equally large and picks the wrong
        # headwater when tracing the main stem upstream.
        reaches.append({"id": river_id, "points": p.tolist(), "downstream_id": start_ids.get(end, -1), "terminal_kind": kind, "catchment_area": float(area[nodes[-2]]), "source_height_m": float(dem.ravel()[start]), "mouth_height_m": float(dem.ravel()[end])})
    owner = catchment_owners(downstream, order, owner)
    # Sparse projected area contributed by each climate cell to each reach.
    # Climate and boundary-flow policy remain runtime inputs, not baked rain.
    yy, xx = np.indices(dem.shape, dtype=np.int32)
    cells = ((yy * 256 // height) * 256 + xx * 256 // width).ravel()
    valid = (owner >= 0) & ~sea
    weights = sparse.coo_matrix((np.full(np.count_nonzero(valid), aspect * 65536.0 / dem.size, np.float32), (owner[valid], cells[valid])), shape=(len(reaches), 65536)).tocsr()
    for i, reach in enumerate(reaches):
        begin, end = weights.indptr[i:i + 2]
        reach["climate_cells"] = weights.indices[begin:end].tolist()
        reach["climate_areas"] = np.round(weights.data[begin:end], 7).tolist()
    return reaches, owner


def load_cached_terrain(cache, bbox, zoom, width):
    from generate_china_surface_texture import mercator_position
    west, south, east, north = bbox
    left, top = mercator_position(west, north, zoom)
    right, bottom = mercator_position(east, south, zoom)
    aspect = (right - left) / (bottom - top)
    height = round(width / aspect)
    x = np.floor(left + (np.arange(width) + 0.5) / width * (right - left)).astype(int)
    y = np.floor(top + (np.arange(height) + 0.5) / height * (bottom - top)).astype(int)
    dem = np.empty((height, width), np.float32)
    digest = hashlib.sha256()
    for ty in np.unique(y // 256):
        iy = np.flatnonzero(y // 256 == ty)
        for tx in np.unique(x // 256):
            ix = np.flatnonzero(x // 256 == tx)
            path = cache / "terrarium" / str(zoom) / str(tx) / f"{ty}.png"
            digest.update(path.read_bytes())
            a = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
            z = a[:, :, 0] * 256 + a[:, :, 1] + a[:, :, 2] / 256 - 32768
            dem[np.ix_(iy, ix)] = z[np.ix_(y[iy] % 256, x[ix] % 256)]
    return dem, aspect, digest.hexdigest()


def boundary_inlets(dem, downstream):
    """One estimate per distinct inward-draining boundary catchment.

    A port needs a local valley and a long path into the interior. This excludes
    an arbitrary wet border and short coastal outlets. Discharge is an explicit
    gameplay assumption, never a measurement of the missing catchment.
    """
    height, width = dem.shape
    radius = max(2, round(height * 0.0015))
    sides = [np.arange(width), (height - 1) * width + np.arange(width),
             np.arange(height) * width, np.arange(height) * width + width - 1]
    sea = ocean_mask(dem)
    by_terminal = {}
    for side in sides:
        profile = dem.ravel()[side]
        candidates = np.flatnonzero(profile == ndimage.minimum_filter1d(profile, 2 * radius + 1, mode="nearest"))
        for offset in candidates:
            if offset < radius or offset >= len(side) - radius:
                continue
            node = int(side[offset])
            if sea[node]:
                continue
            prominence = min(float(profile[offset-radius:offset].max()), float(profile[offset+1:offset+radius+1].max())) - float(profile[offset])
            if prominence < 2:
                continue
            cursor, length, inset = node, 0, 0
            while downstream[cursor] >= 0:
                cursor = int(downstream[cursor])
                yy, xx = divmod(cursor, width)
                inset = max(inset, min(yy, xx, height - 1 - yy, width - 1 - xx))
                length += 1
            if inset < height * 0.025 or length < height * 0.12:
                continue
            candidate = {"node": node, "point": [(node % width + 0.5) / width, (node // width + 0.5) / height], "valley_prominence_m": prominence, "estimated_flow": 256.0}
            if cursor not in by_terminal or prominence > by_terminal[cursor]["valley_prominence_m"]:
                by_terminal[cursor] = candidate
    return list(by_terminal.values())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--tile-cache", type=Path)
    source.add_argument("--dem", type=Path, help="Float metres .npy, north at row 0")
    parser.add_argument("--bbox", type=float, nargs=4, required=True)
    parser.add_argument("--width", type=int, default=8192)
    parser.add_argument("--zoom", type=int, default=7)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--diagnostics", type=Path)
    args = parser.parse_args()
    started = time.perf_counter()
    west, south, east, north = args.bbox
    aspect = math.radians(east - west) / (math.asinh(math.tan(math.radians(north))) - math.asinh(math.tan(math.radians(south))))
    if args.tile_cache:
        dem, aspect, source_hash = load_cached_terrain(args.tile_cache, args.bbox, args.zoom, args.width)
    else:
        dem = np.load(args.dem).astype(np.float32)
        source_hash = hashlib.sha256(args.dem.read_bytes()).hexdigest()
    if not np.isfinite(dem).all():
        raise ValueError("DEM contains missing or non-finite heights")
    print(f"DEM {dem.shape}, {time.perf_counter() - started:.1f}s", flush=True)
    downstream, order, area, roots, filled = drainage(dem, aspect)
    print(f"Drainage: {roots.sum()} retained basins, {time.perf_counter() - started:.1f}s", flush=True)
    ports = boundary_inlets(dem, downstream)
    reaches, owner = vector_network(dem, aspect, downstream, order, area, roots, ports)
    for port in ports:
        port["reach_id"] = int(owner[port.pop("node")])
    result = {"format": "terrain-vector-drainage", "version": 1, "algorithm": VERSION, "projection": "web_mercator", "bbox_wgs84": args.bbox, "dem_size": [dem.shape[1], dem.shape[0]], "source_sha256": source_hash, "climate_size": [256, 256], "basin_count": int(roots.sum()), "max_fill_metres": MAX_FILL_METRES, "min_channel_area": MIN_CHANNEL_AREA, "reaches": reaches, "boundary_inlets": ports}
    result["network_id"] = hashlib.sha256(json.dumps(result, separators=(",", ":")).encode()).hexdigest()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, separators=(",", ":")), encoding="utf-8")
    if args.diagnostics:
        np.savez_compressed(args.diagnostics, dem=dem, downstream=downstream, area=area, roots=roots, filled=filled, owner=owner)
    print(f"VECTOR_HYDROLOGY_OK reaches={len(reaches)} elapsed={time.perf_counter() - started:.2f}s output={args.output}", flush=True)


if __name__ == "__main__":
    main()
