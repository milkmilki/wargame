#include "atlas_mesh.hpp"
#include "../third_party/cdt/CDT.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <numeric>
#include <stdexcept>
#include <unordered_map>
#include <vector>

namespace godot {
namespace {
constexpr double PI = 3.14159265358979323846;
using Point = CDT::V2d<double>;
using Face = std::array<uint32_t, 3>;
uint64_t edge_key(uint32_t a, uint32_t b) {
    return (uint64_t(std::min(a, b)) << 32) | std::max(a, b);
}
Dictionary failure(const String &message) { Dictionary out; out["error"] = message; return out; }
struct Shore { uint32_t a, b; uint8_t left, right, axis; };
struct EdgeFaces { int first = -1, second = -1; };
struct Sets {
    std::vector<int> parent;
    explicit Sets(size_t size) : parent(size) { std::iota(parent.begin(), parent.end(), 0); }
    int root(int id) {
        while (parent[id] != id) { parent[id] = parent[parent[id]]; id = parent[id]; }
        return id;
    }
    void join(int a, int b) {
        a = root(a); b = root(b); parent[std::max(a, b)] = std::min(a, b);
    }
};
void connect_cells(std::vector<std::vector<int>> &adj, int a, int b) {
    if (a != b) { adj[a].push_back(b); adj[b].push_back(a); }
}
void unique(std::vector<int> &row) {
    std::sort(row.begin(), row.end()); row.erase(std::unique(row.begin(), row.end()), row.end());
}
void pack_rows(std::vector<std::vector<int>> &rows, Dictionary &out, const char *start_name, const char *adj_name) {
    PackedInt32Array starts, neighbors;
    for (auto &row : rows) {
        unique(row); starts.push_back(neighbors.size());
        for (int id : row) neighbors.push_back(id);
    }
    starts.push_back(neighbors.size()); out[start_name] = starts; out[adj_name] = neighbors;
}
}

void NativeAtlasMesh::_bind_methods() {
    ClassDB::bind_method(D_METHOD("api_version"), &NativeAtlasMesh::api_version);
    ClassDB::bind_method(D_METHOD("partition_water", "width", "height", "water"), &NativeAtlasMesh::partition_water);
    ClassDB::bind_method(D_METHOD("build_mesh", "partition", "samples"), &NativeAtlasMesh::build_mesh);
}

Dictionary NativeAtlasMesh::partition_water(int64_t w, int64_t h, const PackedByteArray &water) const {
    if (w < 4 || h < 2 || w > 36000 || h > 18000 || w * h > 64000000 || water.size() != w * h)
        return failure("Invalid coastline raster dimensions.");
    const auto *values = water.ptr();
    for (int64_t k = 0; k < water.size(); ++k)
        if (values[k] > 2) return failure("Unknown coastline water class.");
    for (int x = 1; x < w; ++x)
        if (values[x] != values[0] || values[(h - 1) * w + x] != values[(h - 1) * w])
            return failure("Coastline polar rows must each have a single class.");
    // Grid corners are periodic. Polar rows are uniform, so no constraint
    // endpoint lies at the stereographic projection's south-pole singularity.
    std::vector<Shore> raw;
    std::unordered_map<uint32_t, int> degree, outgoing[2];
    auto add = [&](uint32_t a, uint32_t b, int left, int right, int axis) {
        if (left == right) return;
        outgoing[axis][a] = int(raw.size());
        raw.push_back({a, b, uint8_t(left), uint8_t(right), uint8_t(axis)});
        ++degree[a]; ++degree[b];
    };
    for (int y = 1; y < h; ++y)
        for (int x = 0; x < w; ++x)
            add(y * w + x, y * w + (x + 1) % w, values[(y - 1) * w + x], values[y * w + x], 0);
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x)
            add(y * w + x, (y + 1) * w + x, values[y * w + x], values[y * w + (x + w - 1) % w], 1);
    PackedFloat64Array coords;
    PackedInt32Array edges;
    PackedByteArray sides;
    std::unordered_map<uint32_t, int> vertex;
    auto point = [&](uint32_t corner) {
        auto found = vertex.find(corner);
        if (found != vertex.end()) return found->second;
        const int x = corner % w, y = corner / w;
        const double lon = double(x) / double(w) * 2 * PI - PI;
        const double radius = std::tan(PI * double(y) / (2 * double(h)));
        const int id = int(coords.size() / 2);
        coords.push_back(radius * std::cos(lon));
        coords.push_back(x == 0 ? 0.0 : radius * std::sin(lon));
        vertex.emplace(corner, id); return id;
    };
    std::vector<uint8_t> used(raw.size());
    for (size_t i = 0; i < raw.size(); ++i) {
        if (used[i]) continue;
        Shore edge = raw[i]; used[i] = 1;
        const int limit = std::max(1, int(edge.axis == 0 ? w / 360 : h / 180));
        // Merge only straight unbranched runs; never remove a corner or a
        // three-class junction. The cap bounds chord error on parallels.
        for (int count = 1; count < limit && degree[edge.b] == 2; ++count) {
            auto next = outgoing[edge.axis].find(edge.b);
            if (next == outgoing[edge.axis].end() || used[next->second]) break;
            const Shore &candidate = raw[next->second];
            if (edge.left != candidate.left || edge.right != candidate.right || candidate.b == edge.a) break;
            used[next->second] = 1; edge.b = candidate.b;
        }
        edges.push_back(point(edge.a)); edges.push_back(point(edge.b));
        sides.push_back(edge.left); sides.push_back(edge.right);
    }
    Dictionary out;
    out["format"] = "atlas-coastline-partition-v1";
    out["coords"] = coords; out["edges"] = edges; out["sides"] = sides;
    out["south_kind"] = int(values[(h - 1) * w]); out["north_kind"] = int(values[0]);
    out["source_width"] = w; out["source_height"] = h;
    return out;
}

Dictionary NativeAtlasMesh::build_mesh(const Dictionary &partition, const PackedFloat32Array &samples) const {
    return build_mesh_with_clearance(partition, samples, 0);
}

Dictionary NativeAtlasMesh::build_mesh_with_clearance(const Dictionary &partition, const PackedFloat32Array &samples, int attempt) const {
    if (String(partition.get("format", String())) != "atlas-coastline-partition-v1" ||
            partition.get("coords", Variant()).get_type() != Variant::PACKED_FLOAT64_ARRAY ||
            partition.get("edges", Variant()).get_type() != Variant::PACKED_INT32_ARRAY ||
            partition.get("sides", Variant()).get_type() != Variant::PACKED_BYTE_ARRAY)
        return failure("Invalid coastline partition format.");
    const PackedFloat64Array coords = partition["coords"];
    const PackedInt32Array input_edges = partition["edges"];
    const PackedByteArray sides = partition["sides"];
    const int south = partition.get("south_kind", -1);
    if (coords.size() % 2 || input_edges.size() % 2 || sides.size() != input_edges.size() ||
            samples.size() % 3 || samples.size() < 12 || south < 0 || south > 2)
        return failure("Invalid coastline mesh buffers.");
    std::vector<Point> points;
    std::vector<int> sample_indices;
    std::vector<CDT::Edge> constraints;
    for (int64_t i = 0; i < coords.size(); i += 2) {
        if (!std::isfinite(coords[i]) || !std::isfinite(coords[i + 1]) ||
                std::abs(coords[i]) > 1e6 || std::abs(coords[i + 1]) > 1e6)
            return failure("Nonfinite or out-of-range coastline coordinate.");
        points.emplace_back(coords[i], coords[i + 1]);
    }
    for (int64_t i = 0; i < input_edges.size(); i += 2) {
        const int a = input_edges[i], b = input_edges[i + 1];
        if (a < 0 || b < 0 || a == b || a >= int(points.size()) || b >= int(points.size()) ||
                sides[i] > 2 || sides[i + 1] > 2 || sides[i] == sides[i + 1])
            return failure("Invalid coastline constraint edge.");
        constraints.emplace_back(a, b);
    }
    for (int64_t i = 0; i < samples.size(); i += 3) {
        double x = samples[i], y = samples[i + 1], z = samples[i + 2];
        const double norm = std::sqrt(x * x + y * y + z * z);
        if (!std::isfinite(norm) || std::abs(norm - 1) > .001)
            return failure("Coastline samples must be unit sphere points.");
        x /= norm; y /= norm; z /= norm;
        if (1 + z < 1e-9) continue;
        points.emplace_back(x / (1 + z), y / (1 + z));
        sample_indices.push_back(int(i / 3));
    }
    try {
        const auto duplicates = CDT::RemoveDuplicatesAndRemapEdges(points, constraints);
        std::vector<uint8_t> sampled(points.size(), 0);
        std::vector<uint8_t> boundary(points.size(), 0);
        for (size_t i = 0; i < size_t(coords.size() / 2); ++i) boundary[duplicates.mapping[i]] = 1;
        for (size_t i = size_t(coords.size() / 2); i < duplicates.mapping.size(); ++i)
            sampled[duplicates.mapping[i]] = 1;
        struct Tag { uint32_t a, b; int left, right; };
        std::unordered_map<uint64_t, Tag> tags;
        for (int64_t i = 0; i < input_edges.size(); i += 2) {
            const uint32_t a = uint32_t(duplicates.mapping[input_edges[i]]);
            const uint32_t b = uint32_t(duplicates.mapping[input_edges[i + 1]]);
            if (a == b) return failure("Collapsed coastline constraint.");
            tags.emplace(edge_key(a, b), Tag{a, b, sides[i], sides[i + 1]});
        }
        CDT::Triangulation<double> cdt(CDT::VertexInsertionOrder::Auto);
        cdt.insertVertices(points);
        // Greedy nearest-point lookup needs the ordinary spherical Delaunay
        // graph. Constraint insertion can remove its edges, so retain that
        // graph separately, without exposing it to land/sea routing.
        const uint32_t offset = uint32_t(cdt.vertices.size() - points.size());
        std::vector<std::vector<int>> geometric(points.size() + 1);
        const int geometric_pole = int(points.size());
        for (const auto &face : cdt.triangles)
            for (int e = 0; e < 3; ++e) {
                const uint32_t a = face.vertices[e], b = face.vertices[(e + 1) % 3];
                if (a >= offset && b >= offset) connect_cells(geometric, a - offset, b - offset);
                else if (a >= offset) connect_cells(geometric, a - offset, geometric_pole);
                else if (b >= offset) connect_cells(geometric, b - offset, geometric_pole);
            }
        cdt.insertEdges(constraints); cdt.eraseSuperTriangle();
        const uint32_t pole = uint32_t(cdt.vertices.size());
        if (pole != points.size()) return failure("Unexpected coastline intersection vertex.");
        std::vector<Face> faces;
        for (const auto &face : cdt.triangles)
            faces.push_back({face.vertices[0], face.vertices[1], face.vertices[2]});
        if (faces.empty()) return failure("Insufficient samples for a sphere mesh.");
        std::unordered_map<uint64_t, EdgeFaces> edge_faces;
        auto index_face = [&](int t) {
            for (int e = 0; e < 3; ++e) {
                auto &entry = edge_faces[edge_key(faces[t][e], faces[t][(e + 1) % 3])];
                if (entry.first < 0) entry.first = t;
                else if (entry.second < 0) entry.second = t;
                else throw std::runtime_error("Nonmanifold coastline triangulation.");
            }
        };
        for (int t = 0; t < int(faces.size()); ++t) index_face(t);
        const int finite_faces = int(faces.size());
        std::vector<Face> cap;
        for (int t = 0; t < finite_faces; ++t)
            for (int e = 0; e < 3; ++e) {
                const uint32_t a = faces[t][e], b = faces[t][(e + 1) % 3];
                if (edge_faces.at(edge_key(a, b)).second < 0) cap.push_back({b, a, pole});
            }
        for (const auto &face : cap) { faces.push_back(face); index_face(int(faces.size()) - 1); }
        auto constraint_tag = [&](uint32_t a, uint32_t b) -> const Tag * {
            auto direct = tags.find(edge_key(a, b));
            if (direct != tags.end()) return &direct->second;
            const auto pieces = cdt.pieceToOriginals.find(CDT::Edge(a, b));
            if (pieces != cdt.pieceToOriginals.end())
                for (const auto &original : pieces->second) {
                    auto found = tags.find(edge_key(original.v1(), original.v2()));
                    if (found != tags.end()) return &found->second;
                }
            return nullptr;
        };
        std::vector<int> kind(faces.size(), -1), queue;
        auto seed = [&](int t, int value) {
            if (kind[t] >= 0 && kind[t] != value) throw std::runtime_error("Conflicting coastline face classes.");
            if (kind[t] < 0) { kind[t] = value; queue.push_back(t); }
        };
        for (int t = 0; t < int(faces.size()); ++t) {
            if (t >= finite_faces) { seed(t, south); continue; }
            for (int e = 0; e < 3; ++e) {
                const Tag *tag = constraint_tag(faces[t][e], faces[t][(e + 1) % 3]);
                if (!tag) continue;
                const Point &a = cdt.vertices[tag->a], &b = cdt.vertices[tag->b];
                const Point &c = cdt.vertices[faces[t][(e + 2) % 3]];
                const double side = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
                seed(t, side > 0 ? tag->left : tag->right);
            }
        }
        for (size_t cursor = 0; cursor < queue.size(); ++cursor) {
            const int t = queue[cursor];
            for (int e = 0; e < 3; ++e) {
                const uint32_t a = faces[t][e], b = faces[t][(e + 1) % 3];
                if (constraint_tag(a, b)) continue;
                const auto &entry = edge_faces.at(edge_key(a, b));
                const int next = entry.first == t ? entry.second : entry.first;
                if (next < 0) throw std::runtime_error("Open spherical coastline mesh.");
                seed(next, kind[t]);
            }
        }
        for (int value : kind) if (value < 0) return failure("Unclassified coastline component.");
        // Split by connected triangle fan, not just by class: diagonal pixels
        // must not acquire a zero-width land bridge or water passage.
        Sets fans(faces.size() * 3);
        auto corner = [&](int t, uint32_t id) {
            for (int e = 0; e < 3; ++e) if (faces[t][e] == id) return t * 3 + e;
            throw std::runtime_error("Missing shared mesh vertex.");
        };
        for (int t = 0; t < int(faces.size()); ++t)
            for (int e = 0; e < 3; ++e) {
                const uint32_t a = faces[t][e], b = faces[t][(e + 1) % 3];
                const auto &entry = edge_faces.at(edge_key(a, b));
                const int next = entry.first == t ? entry.second : entry.first;
                if (next >= 0 && kind[t] == kind[next]) {
                    fans.join(t * 3 + e, corner(next, a));
                    fans.join(t * 3 + (e + 1) % 3, corner(next, b));
                }
            }
        PackedFloat32Array xyz;
        PackedByteArray water, settlement_sample;
        PackedInt32Array triangles;
        std::unordered_map<int, int> cell_of_fan;
        std::vector<std::vector<int>> cells_of_point(pole + 1);
        for (int t = 0; t < int(faces.size()); ++t)
            for (int e = 0; e < 3; ++e) {
                const int root = fans.root(t * 3 + e);
                auto found = cell_of_fan.find(root);
                if (found == cell_of_fan.end()) {
                    const uint32_t id = faces[t][e]; const int cell = int(water.size());
                    if (id == pole) { xyz.push_back(0); xyz.push_back(0); xyz.push_back(-1); }
                    else {
                        const auto &p = cdt.vertices[id]; const double r2 = p.x * p.x + p.y * p.y;
                        xyz.push_back(float(2 * p.x / (1 + r2))); xyz.push_back(float(2 * p.y / (1 + r2)));
                        xyz.push_back(float((1 - r2) / (1 + r2)));
                    }
                    water.push_back(kind[t]); settlement_sample.push_back(id == pole ? 0 : sampled[id]);
                    cells_of_point[id].push_back(cell);
                    found = cell_of_fan.emplace(root, cell).first;
                }
                triangles.push_back(found->second);
            }
        // Stereographic straight edges and rendered great-circle edges differ
        // slightly. A sample only metres from a coast can fall inside this
        // discrepancy lens. Reject that interior sample and retriangulate;
        // never move/drop a coastline constraint or publish an inverted face.
        std::vector<uint8_t> rejected_points(points.size(), 0);
        int bad_faces = 0;
        bool boundary_only = false;
        for (int64_t t = 0; t < triangles.size(); t += 3) {
            const int a = 3 * triangles[t], b = 3 * triangles[t + 1], c = 3 * triangles[t + 2];
            const double ax = xyz[a], ay = xyz[a + 1], az = xyz[a + 2];
            const double bx = xyz[b], by = xyz[b + 1], bz = xyz[b + 2];
            const double cx = xyz[c], cy = xyz[c + 1], cz = xyz[c + 2];
            const double volume = ax * (by * cz - bz * cy) + ay * (bz * cx - bx * cz) + az * (bx * cy - by * cx);
            if (!(volume > 0)) {
                ++bad_faces;
                bool removable = false;
                for (int e = 0; e < 3; ++e) {
                    const uint32_t point = faces[size_t(t / 3)][e];
                    // Coast vertices are always retained, including an exact
                    // duplicate of a supplied sampling point.
                    if (point < pole && sampled[point] && !boundary[point]) {
                        rejected_points[point] = 1; removable = true;
                    }
                }
                boundary_only = boundary_only || !removable;
            }
        }
        if (bad_faces) {
            if (boundary_only || attempt >= 3) return failure("Cannot embed coastline constraints on the sphere without inverted faces.");
            std::vector<uint8_t> rejected_samples(samples.size() / 3, 0);
            for (size_t i = 0; i < sample_indices.size(); ++i)
                if (rejected_points[duplicates.mapping[size_t(coords.size() / 2) + i]]) rejected_samples[sample_indices[i]] = 1;
            PackedFloat32Array filtered;
            int removed = 0;
            for (int64_t i = 0; i < samples.size(); i += 3) {
                if (rejected_samples[i / 3]) { ++removed; continue; }
                filtered.push_back(samples[i]); filtered.push_back(samples[i + 1]); filtered.push_back(samples[i + 2]);
            }
            if (!removed) return failure("Cannot resolve coastal sample clearance.");
            Dictionary repaired = build_mesh_with_clearance(partition, filtered, attempt + 1);
            if (!repaired.has("error")) {
                repaired["base_sample_count"] = samples.size() / 3;
                repaired["boundary_sample_rejections"] = int(repaired.get("boundary_sample_rejections", 0)) + removed;
            }
            return repaired;
        }
        std::vector<std::vector<int>> adj(water.size());
        PackedInt32Array shore_edges;
        for (int t = 0; t < int(faces.size()); ++t)
            for (int e = 0; e < 3; ++e) {
                const int a = triangles[t * 3 + e], b = triangles[t * 3 + (e + 1) % 3];
                connect_cells(adj, a, b);
                const uint32_t pa = faces[t][e], pb = faces[t][(e + 1) % 3];
                const auto &entry = edge_faces.at(edge_key(pa, pb));
                const int next = entry.first == t ? entry.second : entry.first;
                if (next <= t || kind[t] == kind[next]) continue;
                const int other_a = triangles[corner(next, pa)], other_b = triangles[corner(next, pb)];
                connect_cells(adj, a, other_a); connect_cells(adj, b, other_b);
                shore_edges.push_back(a); shore_edges.push_back(b);
                shore_edges.push_back(other_a); shore_edges.push_back(other_b);
            }
        // Each geometric point uses a stable representative fan for lookup.
        // Duplicate coordinates do not create a barrier or a travel shortcut.
        std::vector<std::vector<int>> lookup(water.size());
        for (uint32_t point = 0; point <= pole; ++point) {
            unique(geometric[point]);
            std::vector<int> row;
            for (int neighbor : geometric[point])
                if (!cells_of_point[neighbor].empty()) row.push_back(cells_of_point[neighbor][0]);
            unique(row); for (int cell : cells_of_point[point]) lookup[cell] = row;
        }
        Dictionary out;
        out["xyz"] = xyz; out["water"] = water; out["triangles"] = triangles;
        out["coast_edges"] = shore_edges; out["n"] = water.size();
        out["settlement_sample"] = settlement_sample; out["base_sample_count"] = samples.size() / 3;
        out["boundary_sample_rejections"] = 0;
        pack_rows(adj, out, "adj_start", "adj"); pack_rows(lookup, out, "lookup_adj_start", "lookup_adj");
        out["model"] = "atlas-coastline-mesh-v1";
        return out;
    } catch (const std::exception &exception) {
        return failure(String("Coastline triangulation failed: ") + String::utf8(exception.what()));
    }
}
}
