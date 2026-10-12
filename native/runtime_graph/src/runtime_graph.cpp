#include "runtime_graph.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/templates/sort_array.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <limits>
#include <unordered_map>
#include <unordered_set>
#include <utility>

namespace godot {
namespace {

constexpr double INFINITY_DISTANCE = std::numeric_limits<double>::infinity();

// GDScript scalar floats are doubles, including the global is_equal_approx.
// Preserve its asymmetric, strict comparison rather than an STL comparator.
bool equal_approx(double a, double b) {
    return Math::is_equal_approx(a, b);
}

Dictionary error_result(const char *message) {
    Dictionary result;
    result["error"] = String(message);
    return result;
}

template <typename T, typename Packed>
std::vector<T> copy_packed(const Packed &input) {
    if (input.is_empty()) return {};
    return std::vector<T>(input.ptr(), input.ptr() + input.size());
}

bool valid_csr(const PackedInt32Array &offsets,
        const PackedInt32Array &targets, int64_t nodes) {
    if (nodes < 0 || nodes > std::numeric_limits<int32_t>::max() ||
            offsets.size() != nodes + 1 || offsets[0] != 0 ||
            targets.size() > std::numeric_limits<int32_t>::max() ||
            offsets[nodes] != targets.size()) return false;
    for (int64_t i = 0; i < nodes; ++i) {
        if (offsets[i] < 0 || offsets[i] > offsets[i + 1]) return false;
    }
    for (int64_t i = 0; i < targets.size(); ++i) {
        if (targets[i] < 0 || targets[i] >= nodes) return false;
    }
    return true;
}

bool valid_costs(const PackedFloat64Array &costs, int64_t edges) {
    if (costs.size() != edges) return false;
    for (int64_t i = 0; i < edges; ++i) {
        if (!std::isfinite(costs[i]) || costs[i] < 0.0) return false;
    }
    return true;
}

bool valid_optional_mask(const PackedByteArray &mask, int64_t size) {
    return mask.is_empty() || mask.size() == size;
}

bool read_finite_float(Object *object, const StringName &name, double &value) {
    const Variant property = object->get(name);
    if (property.get_type() != Variant::FLOAT) return false;
    value = double(property);
    return std::isfinite(value);
}

// Pathfinding and TradeNetwork use this swap-based heap. In particular, equal
// entries do not bubble. std::priority_queue would change equal-key behavior.
template <typename Entry, typename Less>
void heap_push(std::vector<Entry> &heap, const Entry &entry, const Less &less) {
    heap.push_back(entry);
    size_t index = heap.size() - 1;
    while (index > 0) {
        const size_t parent = (index - 1) / 2;
        if (!less(heap[index], heap[parent])) break;
        std::swap(heap[index], heap[parent]);
        index = parent;
    }
}

template <typename Entry, typename Less>
Entry heap_pop(std::vector<Entry> &heap, const Less &less) {
    Entry result = heap[0];
    Entry tail = heap.back();
    heap.pop_back();
    if (heap.empty()) return result;
    heap[0] = tail;
    size_t index = 0;
    while (true) {
        const size_t left = index * 2 + 1;
        if (left >= heap.size()) break;
        const size_t right = left + 1;
        size_t child = left;
        if (right < heap.size() && less(heap[right], heap[left])) child = right;
        if (!less(heap[child], heap[index])) break;
        std::swap(heap[index], heap[child]);
        index = child;
    }
    return result;
}

struct FloatEntry {
    double distance;
    int32_t city;
};

bool travel_less(const FloatEntry &a, const FloatEntry &b) {
    return a.distance < b.distance ||
            (equal_approx(a.distance, b.distance) && a.city < b.city);
}

// ThreatField uses a hole-based heap and moves equal entries, unlike paths.
void travel_push(std::vector<FloatEntry> &heap, const FloatEntry &entry) {
    heap.push_back(entry);
    size_t index = heap.size() - 1;
    while (index > 0) {
        const size_t parent = (index - 1) / 2;
        if (travel_less(heap[parent], entry)) break;
        heap[index] = heap[parent];
        index = parent;
    }
    heap[index] = entry;
}

FloatEntry travel_pop(std::vector<FloatEntry> &heap) {
    const FloatEntry result = heap[0];
    const FloatEntry last = heap.back();
    heap.pop_back();
    if (heap.empty()) return result;
    size_t index = 0;
    while (true) {
        const size_t left = index * 2 + 1;
        if (left >= heap.size()) break;
        const size_t right = left + 1;
        size_t child = left;
        if (right < heap.size() && travel_less(heap[right], heap[left])) child = right;
        if (travel_less(last, heap[child])) break;
        heap[index] = heap[child];
        index = child;
    }
    heap[index] = last;
    return result;
}

using OrderKey = std::array<int64_t, 5>;

OrderKey city_key_in_frame(const std::vector<double> &geometry,
        int32_t city, double origin_x, double forward_sign) {
    const size_t base = size_t(city) * 5;
    const double oriented_x = Math::is_zero_approx(forward_sign) ?
            geometry[base + 2] : (geometry[base] - origin_x) * forward_sign;
    return {
        int64_t(std::round(oriented_x * 1000000.0)),
        int64_t(std::round(geometry[base + 1] * 1000000.0)),
        int64_t(std::round(geometry[base + 2] * 1000000.0)),
        int64_t(std::round(geometry[base + 3] * 1000000.0)),
        int64_t(std::round(geometry[base + 4] * 1000000.0)),
    };
}

struct SortedNeighbor {
    int32_t city;
    OrderKey key;
};

struct NeighborKeyLess {
    bool operator()(const SortedNeighbor &a, const SortedNeighbor &b) const {
        return a.key < b.key;
    }
};

class PathOrder {
    const std::vector<double> &geometry;
    const int32_t *ranks;
    mutable std::vector<OrderKey> keys;
    mutable std::vector<uint8_t> key_ready;
    double origin_x;
    double forward_sign;

    const OrderKey &key(int32_t city) const {
        if (!key_ready[city]) {
            keys[city] = city_key_in_frame(geometry, city, origin_x, forward_sign);
            key_ready[city] = 1;
        }
        return keys[city];
    }

public:
    PathOrder(const std::vector<double> &p_geometry, const PackedInt32Array &p_ranks,
            int32_t start, double sign) : geometry(p_geometry),
            ranks(p_ranks.is_empty() ? nullptr : p_ranks.ptr()),
            keys(p_ranks.is_empty() ? p_geometry.size() / 5 : 0),
            key_ready(keys.size(), 0), origin_x(p_geometry[size_t(start) * 5]),
            forward_sign(sign) {}

    bool city_less(int32_t a, int32_t b) const {
        return ranks ? ranks[a] < ranks[b] : key(a) < key(b);
    }

    bool operator()(const FloatEntry &a, const FloatEntry &b) const {
        if (!equal_approx(a.distance, b.distance)) return a.distance < b.distance;
        return city_less(a.city, b.city);
    }
};

// Vector3i(candidate, origin, city) truncates cost to signed 32 bits. Keep that
// baseline behavior even when a packed int64 distance exceeds INT32_MAX.
int32_t vector3i_cost(int64_t value) {
    const uint32_t bits = uint32_t(uint64_t(value));
    int32_t result;
    std::memcpy(&result, &bits, sizeof(result));
    return result;
}

int64_t integer_add(int64_t a, int64_t b) {
    const uint64_t bits = uint64_t(a) + uint64_t(b);
    int64_t result;
    std::memcpy(&result, &bits, sizeof(result));
    return result;
}

struct TradeEntry {
    int32_t cost;
    int32_t origin;
    int32_t city;
};

bool trade_less(const TradeEntry &a, const TradeEntry &b) {
    if (a.cost != b.cost) return a.cost < b.cost;
    if (a.origin != b.origin) return a.origin < b.origin;
    return a.city < b.city;
}

} // namespace

void NativeGraphSnapshot::_bind_methods() {
    ClassDB::bind_method(D_METHOD("query_key_order", "keys"),
            &NativeGraphSnapshot::query_key_order);
    ClassDB::bind_method(D_METHOD("api_version"), &NativeGraphSnapshot::api_version);
    ClassDB::bind_method(D_METHOD("configure", "offsets", "targets", "edge_ids", "controls", "node_geometry"),
            &NativeGraphSnapshot::configure);
    ClassDB::bind_method(D_METHOD("pack_edge_inputs", "edges", "modes", "constants"),
            &NativeGraphSnapshot::pack_edge_inputs);
    ClassDB::bind_method(D_METHOD("pack_owner_inputs", "cities"),
            &NativeGraphSnapshot::pack_owner_inputs);
    ClassDB::bind_method(D_METHOD("query_administrative_fields", "cities", "adjacency",
            "edge_lookup", "nations", "capitals", "traffic_kind"),
            &NativeGraphSnapshot::query_administrative_fields);
    ClassDB::bind_method(D_METHOD("query_travel", "start", "costs", "enabled", "horizon"),
            &NativeGraphSnapshot::query_travel);
    ClassDB::bind_method(D_METHOD("query_path", "start", "extra_origins", "costs", "enabled", "accessible",
            "blocked_nodes", "allowed_nodes", "goal", "exit_city", "control_access", "forward_sign", "ranks", "supply"),
            &NativeGraphSnapshot::query_path);
    ClassDB::bind_method(D_METHOD("query_trade", "starts", "costs", "enabled", "allowed", "forbidden", "inf_cost"),
            &NativeGraphSnapshot::query_trade);
    ClassDB::bind_method(D_METHOD("query_connectivity", "roots", "neighbor_offsets", "neighbor_targets", "values"),
            &NativeGraphSnapshot::query_connectivity);
    ClassDB::bind_method(D_METHOD("make_access_mask", "owners", "permissions", "live_controls"),
            &NativeGraphSnapshot::make_access_mask, DEFVAL(PackedInt32Array()));
    ClassDB::bind_method(D_METHOD("patch_access_mask", "base", "live_controls", "goal", "exit_city"),
            &NativeGraphSnapshot::patch_access_mask);
    ClassDB::bind_method(D_METHOD("query_connectivity_filtered", "roots", "neighbor_offsets", "neighbor_targets",
            "enabled", "owners", "nation", "values", "forward_sign"),
            &NativeGraphSnapshot::query_connectivity_filtered);
}

int64_t NativeGraphSnapshot::api_version() const { return 4; }

Dictionary NativeGraphSnapshot::query_key_order(const Array &input) const {
    if (input.size() > std::numeric_limits<int32_t>::max())
        return error_result("Too many integer sort keys.");
    std::vector<std::vector<int64_t>> keys;
    keys.reserve(input.size());
    for (int64_t index = 0; index < input.size(); ++index) {
        const Variant value = input[index];
        if (value.get_type() != Variant::ARRAY)
            return error_result("Integer sort keys must be arrays.");
        const Array row = value;
        std::vector<int64_t> key;
        key.reserve(row.size());
        for (int64_t field = 0; field < row.size(); ++field) {
            const Variant scalar = row[field];
            if (scalar.get_type() != Variant::INT)
                return error_result("Integer sort key fields must be integers.");
            key.push_back(int64_t(scalar));
        }
        keys.push_back(std::move(key));
    }
    PackedInt32Array order;
    order.resize(input.size());
    for (int64_t index = 0; index < input.size(); ++index) order[index] = int32_t(index);
    struct KeyLess {
        const std::vector<std::vector<int64_t>> *keys = nullptr;
        bool operator()(int32_t a, int32_t b) const { return (*keys)[a] < (*keys)[b]; }
    };
    // Array.sort_custom uses this introsort. STL sort or stable_sort would
    // change equal-key permutations and thus shared supply allocation order.
    SortArray<int32_t, KeyLess> sorter;
    sorter.compare.keys = &keys;
    if (!order.is_empty()) sorter.sort(order.ptrw(), order.size());
    Dictionary result;
    result["order"] = order;
    return result;
}

bool NativeGraphSnapshot::configure(const PackedInt32Array &p_offsets,
        const PackedInt32Array &p_targets, const PackedInt32Array &p_edge_ids,
        const PackedInt32Array &p_controls, const PackedFloat64Array &p_geometry) {
    if (configured || p_offsets.is_empty()) return false;
    const int64_t nodes = p_offsets.size() - 1;
    const int64_t edges = p_controls.size();
    if (!valid_csr(p_offsets, p_targets, nodes) || p_edge_ids.size() != p_targets.size() ||
            edges > std::numeric_limits<int32_t>::max() || p_geometry.size() != nodes * 5) return false;
    for (int64_t i = 0; i < p_edge_ids.size(); ++i) {
        if (p_edge_ids[i] < 0 || p_edge_ids[i] >= edges) return false;
    }
    for (int64_t i = 0; i < edges; ++i) {
        if (p_controls[i] < -1 || p_controls[i] >= nodes) return false;
    }
    for (int64_t i = 0; i < p_geometry.size(); ++i) {
        // Quantized lazy keys must fit int64 even after x-origin subtraction.
        if (!std::isfinite(p_geometry[i]) || std::abs(p_geometry[i]) > 1.0e12) return false;
    }
    offsets = copy_packed<int32_t>(p_offsets);
    targets = copy_packed<int32_t>(p_targets);
    edge_ids = copy_packed<int32_t>(p_edge_ids);
    controls = copy_packed<int32_t>(p_controls);
    geometry = copy_packed<double>(p_geometry);
    configured = true;
    return true;
}

Dictionary NativeGraphSnapshot::pack_edge_inputs(const Array &edges, int64_t modes,
        const PackedFloat64Array &constants) const {
    const int64_t count = controls.size();
    if (!configured || edges.size() != count || constants.size() != 5 || (modes & ~int64_t(15)))
        return error_result("Invalid edge packing arrays, modes or snapshot.");
    for (int64_t i = 0; i < constants.size(); ++i) {
        if (!std::isfinite(constants[i])) return error_result("Nonfinite edge packing constant.");
    }
    PackedByteArray enabled;
    PackedInt32Array live_controls;
    PackedFloat64Array path, danger, supply, travel;
    enabled.resize(count);
    live_controls.resize(count);
    if (modes & 1) path.resize(count);
    if (modes & 2) danger.resize(count);
    if (modes & 4) supply.resize(count);
    if (modes & 8) travel.resize(count);
    uint8_t *enabled_out = enabled.ptrw();
    int32_t *controls_out = live_controls.ptrw();
    double *path_out = path.ptrw(), *danger_out = danger.ptrw();
    double *supply_out = supply.ptrw(), *travel_out = travel.ptrw();
    const double *weights = constants.ptr();
    const StringName capacity_name("max_manpower"), distance_name("distance");
    const StringName precise_name("precise_distance"), danger_name("danger");
    const StringName travel_name("travel_time_multiplier"), loss_name("supply_loss_multiplier");
    const StringName control_name("control_city_id");
    const int64_t nodes = geometry.size() / 5;
    for (int64_t i = 0; i < count; ++i) {
        const Variant entry = edges[i];
        Object *edge = entry.get_type() == Variant::OBJECT ? static_cast<Object *>(entry) : nullptr;
        if (!edge) return error_result("Null or nonobject edge packing input.");
        const Variant capacity = edge->get(capacity_name);
        if (capacity.get_type() != Variant::INT) return error_result("Edge capacity must be an integer.");
        const bool open = int64_t(capacity) > 0;
        enabled_out[i] = open ? 1 : 0;
        const Variant control = edge->get(control_name);
        if (control.get_type() != Variant::INT) return error_result("Edge control city must be an integer.");
        const int64_t control_id = int64_t(control);
        // Atlas rejects any control outside the current city's bounds. Keep
        // the same inaccessible sentinel without narrowing an arbitrary int64.
        controls_out[i] = control_id >= 0 && control_id < nodes ? int32_t(control_id) : -1;
        if (!modes) continue;
        const Variant integer_distance = edge->get(distance_name);
        double precise = 0.0;
        if (integer_distance.get_type() != Variant::INT || !read_finite_float(edge, precise_name, precise))
            return error_result("Invalid edge distance property.");
        const int64_t legacy_distance = std::max(int64_t(integer_distance), int64_t(1));
        const double distance = precise >= 0.0 ? precise : double(legacy_distance);
        double travel_multiplier = 0.0, edge_danger = 0.0, loss_multiplier = 0.0;
        if ((modes & (1 | 2 | 8)) && !read_finite_float(edge, travel_name, travel_multiplier))
            return error_result("Invalid edge travel multiplier.");
        if ((modes & (2 | 4)) && !read_finite_float(edge, danger_name, edge_danger))
            return error_result("Invalid edge danger property.");
        if ((modes & 4) && !read_finite_float(edge, loss_name, loss_multiplier))
            return error_result("Invalid edge supply loss multiplier.");
        const double multiplier = std::max(travel_multiplier, 0.05);
        const double path_cost = distance * multiplier;
        if (modes & 1) {
            if (!std::isfinite(path_cost)) return error_result("Nonfinite packed path cost.");
            path_out[i] = path_cost;
        }
        if (modes & 2) {
            const double cost = path_cost + edge_danger * weights[0] * (precise >= 0.0 ? distance : 1.0);
            if (!std::isfinite(cost)) return error_result("Nonfinite packed danger cost.");
            danger_out[i] = cost;
        }
        if (modes & 4) {
            // Godot maxf selects the second argument on equality, so an IEEE
            // -0.0 loss multiplier becomes +0.0 before multiplication.
            const double cost = open ? weights[1] * distance * (loss_multiplier > 0.0 ? loss_multiplier : 0.0)
                    * (1.0 + weights[2] * std::clamp(edge_danger, 0.0, 1.0)) : 0.0;
            if (!std::isfinite(cost)) return error_result("Nonfinite packed supply cost.");
            supply_out[i] = cost;
        }
        if (modes & 8) {
            const double cost = precise >= 0.0 ? std::max(0.000001, distance * weights[3] * multiplier)
                    : std::max((weights[3] + double(legacy_distance - 1) * weights[4]) * multiplier, 1.0);
            if (!std::isfinite(cost)) return error_result("Nonfinite packed travel cost.");
            travel_out[i] = cost;
        }
    }
    Dictionary result;
    result["enabled"] = enabled;
    result["controls"] = live_controls;
    result["path"] = path;
    result["danger"] = danger;
    result["supply"] = supply;
    result["travel"] = travel;
    return result;
}

Dictionary NativeGraphSnapshot::pack_owner_inputs(const Array &cities) const {
    const int64_t count = geometry.size() / 5;
    if (!configured || cities.size() != count) return error_result("Invalid owner packing count or snapshot.");
    PackedInt32Array owners, unique;
    owners.resize(count);
    unique.resize(count);
    int32_t *owners_out = owners.ptrw(), *unique_out = unique.ptrw();
    int64_t unique_count = 0;
    std::unordered_set<int32_t> seen;
    seen.reserve(count);
    const StringName owner_name("owner_nation");
    for (int64_t i = 0; i < count; ++i) {
        const Variant entry = cities[i];
        Object *city = entry.get_type() == Variant::OBJECT ? static_cast<Object *>(entry) : nullptr;
        if (!city) return error_result("Null or nonobject owner packing input.");
        const Variant owner = city->get(owner_name);
        if (owner.get_type() != Variant::INT || int64_t(owner) < std::numeric_limits<int32_t>::min()
                || int64_t(owner) > std::numeric_limits<int32_t>::max())
            return error_result("City owner must be a signed 32-bit integer.");
        owners_out[i] = int32_t(int64_t(owner));
        if (seen.insert(owners_out[i]).second) unique_out[unique_count++] = owners_out[i];
    }
    unique.resize(unique_count);
    Dictionary result;
    result["owners"] = owners;
    result["unique"] = unique;
    return result;
}

Dictionary NativeGraphSnapshot::query_administrative_fields(const Array &cities,
        const Dictionary &adjacency, const Dictionary &edge_lookup,
        const PackedInt32Array &nations, const PackedInt32Array &capitals,
        int64_t traffic_kind) const {
    const int64_t nodes = cities.size();
    if (nodes > std::numeric_limits<int32_t>::max() || nations.size() != capitals.size())
        return error_result("Invalid administrative field array sizes.");
    std::vector<int64_t> owners(nodes);
    std::vector<uint8_t> traffic(nodes);
    const StringName owner_name("owner_nation"), kind_name("node_kind");
    const StringName capacity_name("max_manpower"), control_name("control_city_id");
    for (int64_t i = 0; i < nodes; ++i) {
        const Variant entry = cities[i];
        Object *city = entry.get_type() == Variant::OBJECT ? static_cast<Object *>(entry) : nullptr;
        if (!city) return error_result("Null or nonobject administrative city.");
        const Variant owner = city->get(owner_name), kind = city->get(kind_name);
        if (owner.get_type() != Variant::INT || kind.get_type() != Variant::INT)
            return error_result("Administrative city owner and node kind must be integers.");
        owners[i] = int64_t(owner);
        traffic[i] = int64_t(kind) == traffic_kind;
    }
    // Copy the actual directed adjacency in its original order. Reading this
    // live graph also observes direct edits without relying on road revisions.
    std::vector<int64_t> row_offsets{0};
    std::vector<int32_t> row_targets;
    std::vector<int64_t> control_owners;
    std::unordered_map<Object *, int64_t> edge_controls;
    for (int64_t from = 0; from < nodes; ++from) {
        const Variant neighbors_value = adjacency.get(from, Array());
        if (neighbors_value.get_type() != Variant::ARRAY)
            return error_result("Administrative adjacency rows must be arrays.");
        const Array neighbors = neighbors_value;
        for (int64_t index = 0; index < neighbors.size(); ++index) {
            const Variant neighbor = neighbors[index];
            if (neighbor.get_type() != Variant::INT || int64_t(neighbor) < 0 || int64_t(neighbor) >= nodes)
                return error_result("Invalid administrative adjacency target.");
            const int64_t to = int64_t(neighbor);
            const int64_t key = (std::min(from, to) << 32) | std::max(from, to);
            const Variant entry = edge_lookup.get(key, Variant());
            if (entry.get_type() == Variant::NIL) continue;
            Object *edge = entry.get_type() == Variant::OBJECT ? static_cast<Object *>(entry) : nullptr;
            if (!edge) return error_result("Nonobject administrative road.");
            auto cached = edge_controls.find(edge);
            if (cached == edge_controls.end()) {
                const Variant capacity = edge->get(capacity_name), control = edge->get(control_name);
                if (capacity.get_type() != Variant::INT || control.get_type() != Variant::INT)
                    return error_result("Administrative road capacity and control must be integers.");
                const int64_t control_id = int64_t(control);
                const int64_t owner = int64_t(capacity) > 0 && control_id >= 0 && control_id < nodes
                        && !traffic[control_id] ? owners[control_id] : -1;
                cached = edge_controls.emplace(edge, owner).first;
            }
            if (cached->second < 0) continue;
            row_targets.push_back(int32_t(to));
            control_owners.push_back(cached->second);
        }
        row_offsets.push_back(row_targets.size());
    }
    Dictionary fields;
    for (int64_t index = 0; index < nations.size(); ++index) {
        const int32_t nation = nations[index], capital = capitals[index];
        Dictionary field;
        if (nation >= 0 && capital >= 0 && capital < nodes && !traffic[capital] && owners[capital] == nation) {
            std::vector<int32_t> distance(nodes, -1), current{capital};
            distance[capital] = 0;
            int32_t level = 0;
            // Match the reference's two FIFO queues, including dictionary
            // insertion order. Traffic never counts as an administrative hop.
            while (!current.empty()) {
                std::vector<int32_t> next;
                for (size_t cursor = 0; cursor < current.size(); ++cursor) {
                    const int32_t node = current[cursor];
                    if (distance[node] != level) continue;
                    if (!traffic[node]) field[node] = level;
                    for (int64_t arc = row_offsets[node]; arc < row_offsets[node + 1]; ++arc) {
                        const int32_t neighbor = row_targets[arc];
                        if (control_owners[arc] != nation || (!traffic[neighbor] && owners[neighbor] != nation)) continue;
                        const int32_t candidate = level + (traffic[neighbor] ? 0 : 1);
                        if (distance[neighbor] >= 0 && distance[neighbor] <= candidate) continue;
                        distance[neighbor] = candidate;
                        if (candidate == level) current.push_back(neighbor);
                        else next.push_back(neighbor);
                    }
                }
                current = std::move(next);
                ++level;
            }
        }
        fields[nation] = field;
    }
    Dictionary result;
    result["fields"] = fields;
    return result;
}

Dictionary NativeGraphSnapshot::query_travel(int64_t start, const PackedFloat64Array &costs,
        const PackedByteArray &enabled, double horizon) const {
    const int64_t nodes = geometry.size() / 5;
    const int64_t edges = controls.size();
    if (!configured || start < 0 || start >= nodes || !valid_costs(costs, edges) ||
            enabled.size() != edges || std::isnan(horizon)) return error_result("Invalid travel query arrays or origin.");
    std::vector<double> dist(nodes, INFINITY_DISTANCE);
    std::vector<int32_t> insertion_order;
    insertion_order.reserve(nodes);
    insertion_order.push_back(int32_t(start));
    dist[start] = 0.0;
    std::vector<FloatEntry> heap;
    heap.reserve(nodes);
    travel_push(heap, {0.0, int32_t(start)});
    const double *weights = costs.ptr();
    const uint8_t *open = enabled.ptr();
    while (!heap.empty()) {
        const FloatEntry entry = travel_pop(heap);
        const int32_t u = entry.city;
        if (entry.distance > dist[u] + 0.0001 || entry.distance > horizon) continue;
        for (int32_t arc = offsets[u]; arc < offsets[u + 1]; ++arc) {
            const int32_t edge = edge_ids[arc];
            if (!open[edge]) continue;
            const int32_t v = targets[arc];
            const double nd = entry.distance + weights[edge];
            if (nd > horizon || !(nd < dist[v])) continue;
            if (dist[v] == INFINITY_DISTANCE) insertion_order.push_back(v);
            dist[v] = nd;
            travel_push(heap, {nd, v});
        }
    }
    Dictionary result;
    for (int32_t city : insertion_order) result[int64_t(city)] = dist[city];
    return result;
}

Dictionary NativeGraphSnapshot::query_path(int64_t start, const PackedInt32Array &extra_origins,
        const PackedFloat64Array &costs, const PackedByteArray &enabled,
        const PackedByteArray &accessible, const PackedByteArray &blocked_nodes,
        const PackedByteArray &allowed_nodes, int64_t goal, int64_t exit_city,
        bool control_access, double forward_sign, const PackedInt32Array &ranks,
        bool supply) const {
    const int64_t nodes = geometry.size() / 5;
    const int64_t edges = controls.size();
    if (!configured || start < 0 || start >= nodes || !valid_costs(costs, edges) ||
            enabled.size() != edges || accessible.size() != edges ||
            !valid_optional_mask(blocked_nodes, nodes) || !valid_optional_mask(allowed_nodes, nodes) ||
            (!ranks.is_empty() && ranks.size() != nodes) || goal < -1 || goal >= nodes ||
            exit_city < -1 || exit_city >= nodes || !std::isfinite(forward_sign) ||
            std::abs(forward_sign) > 1.0) return error_result("Invalid path query arrays or origin.");
    std::vector<double> dist(nodes, INFINITY_DISTANCE);
    std::vector<int32_t> prev(nodes, -1);
    std::vector<uint8_t> visited(nodes, 0);
    std::vector<int32_t> prev_order;
    prev_order.reserve(nodes);
    dist[start] = 0.0;
    PathOrder order(geometry, ranks, int32_t(start), forward_sign);
    std::vector<FloatEntry> heap;
    heap.reserve(nodes);
    heap.push_back({0.0, int32_t(start)});
    if (supply) {
        for (int64_t i = 0; i < extra_origins.size(); ++i) {
            const int32_t origin = extra_origins[i];
            if (origin < 0 || origin >= nodes || origin == start || dist[origin] == 0.0) continue;
            dist[origin] = 0.0;
            // The baseline appends zero-loss relays without re-heapifying.
            heap.push_back({0.0, origin});
        }
    }
    const double *weights = costs.ptr();
    const uint8_t *open = enabled.ptr();
    const uint8_t *access = accessible.ptr();
    const uint8_t *blocked = blocked_nodes.is_empty() ? nullptr : blocked_nodes.ptr();
    const uint8_t *allowed = allowed_nodes.is_empty() ? nullptr : allowed_nodes.ptr();
    while (!heap.empty()) {
        const FloatEntry entry = heap_pop(heap, order);
        const int32_t u = entry.city;
        if (visited[u] || entry.distance > dist[u] + 0.000001) continue;
        visited[u] = 1;
        for (int32_t arc = offsets[u]; arc < offsets[u + 1]; ++arc) {
            const int32_t v = targets[arc];
            const int32_t edge = edge_ids[arc];
            if (visited[v] || !open[edge]) continue;
            if (blocked && ((blocked[v] && v != goal) || (blocked[u] && u != start))) continue;
            if (allowed && ((!allowed[v] && (supply || v != goal)) ||
                    (!allowed[u] && (supply || u != start)))) continue;
            bool edge_access = access[edge] != 0;
            if (control_access && controls[edge] >= 0) {
                edge_access = edge_access || (goal >= 0 && controls[edge] == goal) ||
                        (!supply && exit_city >= 0 && controls[edge] == exit_city);
            }
            if (!edge_access) continue;
            const double nd = dist[u] + weights[edge];
            const bool improves = nd < dist[v];
            const bool improves_tie = equal_approx(nd, dist[v]) &&
                    (prev[v] < 0 || order.city_less(u, prev[v]));
            if (!improves && !improves_tie) continue;
            if (prev[v] < 0) prev_order.push_back(v);
            dist[v] = nd;
            prev[v] = u;
            heap_push(heap, {nd, v}, order);
        }
    }
    Dictionary result;
    if (supply) {
        PackedFloat64Array result_dist;
        PackedInt32Array result_prev;
        result_dist.resize(nodes);
        result_prev.resize(nodes);
        if (nodes) {
            std::copy(dist.begin(), dist.end(), result_dist.ptrw());
            std::copy(prev.begin(), prev.end(), result_prev.ptrw());
        }
        result["dist"] = result_dist;
        result["prev"] = result_prev;
    } else {
        Dictionary result_dist;
        Dictionary result_prev;
        for (int64_t i = 0; i < nodes; ++i) result_dist[i] = dist[i];
        for (int32_t city : prev_order) result_prev[int64_t(city)] = int64_t(prev[city]);
        result["dist"] = result_dist;
        result["prev"] = result_prev;
    }
    return result;
}

Dictionary NativeGraphSnapshot::query_trade(const PackedInt32Array &starts,
        const PackedInt64Array &costs, const PackedByteArray &enabled,
        const PackedByteArray &allowed, const PackedByteArray &forbidden,
        int64_t inf_cost) const {
    const int64_t nodes = geometry.size() / 5;
    const int64_t edges = controls.size();
    if (!configured || costs.size() != edges || enabled.size() != edges ||
            !valid_optional_mask(allowed, nodes) || !valid_optional_mask(forbidden, nodes) ||
            inf_cost <= 0) return error_result("Invalid trade query arrays.");
    for (int64_t i = 0; i < edges; ++i) {
        if (costs[i] < 0) return error_result("Negative trade edge cost.");
    }
    PackedInt64Array dist;
    PackedInt32Array prev;
    PackedInt32Array origin;
    dist.resize(nodes);
    prev.resize(nodes);
    origin.resize(nodes);
    dist.fill(inf_cost);
    prev.fill(-1);
    origin.fill(-1);
    int64_t *distances = dist.ptrw();
    int32_t *parents = prev.ptrw();
    int32_t *sources = origin.ptrw();
    std::vector<uint8_t> visited(nodes, 0);
    std::vector<TradeEntry> heap;
    heap.reserve(nodes);
    const uint8_t *node_access = allowed.is_empty() ? nullptr : allowed.ptr();
    const uint8_t *blocked = forbidden.is_empty() ? nullptr : forbidden.ptr();
    const uint8_t *open = enabled.ptr();
    const int64_t *weights = costs.ptr();
    for (int64_t i = 0; i < starts.size(); ++i) {
        const int32_t start = starts[i];
        if (start < 0 || start >= nodes || (node_access && !node_access[start]) ||
                (blocked && blocked[start])) continue;
        distances[start] = 0;
        sources[start] = start;
        heap_push(heap, TradeEntry{0, start, start}, trade_less);
    }
    while (!heap.empty()) {
        const TradeEntry entry = heap_pop(heap, trade_less);
        const int32_t u = entry.city;
        const int64_t known_cost = entry.cost;
        if (visited[u] || known_cost != distances[u] || entry.origin != sources[u]) continue;
        visited[u] = 1;
        for (int32_t arc = offsets[u]; arc < offsets[u + 1]; ++arc) {
            const int32_t v = targets[arc];
            const int32_t edge = edge_ids[arc];
            if (visited[v] || (node_access && !node_access[v]) ||
                    (blocked && blocked[v]) || !open[edge]) continue;
            const int64_t candidate = integer_add(known_cost, weights[edge]);
            const int32_t candidate_origin = sources[u];
            const bool improves = candidate < distances[v];
            const bool tie_improves = candidate == distances[v] &&
                    (sources[v] < 0 || candidate_origin < sources[v] ||
                    (candidate_origin == sources[v] && (parents[v] < 0 || u < parents[v])));
            if (!improves && !tie_improves) continue;
            distances[v] = candidate;
            parents[v] = u;
            sources[v] = candidate_origin;
            heap_push(heap, TradeEntry{vector3i_cost(candidate), candidate_origin, v}, trade_less);
        }
    }
    Dictionary result;
    result["dist"] = dist;
    result["prev"] = prev;
    result["origin"] = origin;
    return result;
}

Dictionary NativeGraphSnapshot::query_connectivity(const PackedInt32Array &roots,
        const PackedInt32Array &neighbor_offsets, const PackedInt32Array &neighbor_targets,
        const PackedFloat64Array &values) const {
    const int64_t nodes = geometry.size() / 5;
    if (!configured || !valid_csr(neighbor_offsets, neighbor_targets, nodes) || values.size() != nodes)
        return error_result("Invalid connectivity query arrays.");
    for (int64_t i = 0; i < nodes; ++i) {
        if (!std::isfinite(values[i])) return error_result("Nonfinite connectivity value.");
    }
    for (int64_t i = 0; i < roots.size(); ++i) {
        if (roots[i] < 0 || roots[i] >= nodes) return error_result("Invalid connectivity root.");
    }
    const int32_t *adj_offsets = neighbor_offsets.ptr();
    const int32_t *adj_targets = neighbor_targets.ptr();
    const double *node_values = values.ptr();
    std::vector<int32_t> disc(nodes, 0), low(nodes, 0), parent(nodes, -1), child_count(nodes, 0);
    std::vector<double> subtree(nodes, 0.0), articulation(nodes, 0.0);
    std::vector<uint8_t> articulation_seen(nodes, 0);
    std::vector<int32_t> discover_order, articulation_order;
    std::vector<std::pair<int64_t, double>> bridges;
    discover_order.reserve(nodes);
    articulation_order.reserve(nodes);
    int32_t time = 0;
    struct Frame { int32_t city; int32_t arc; };
    std::vector<Frame> stack;
    stack.reserve(nodes);
    const auto discover = [&](int32_t city) {
        disc[city] = ++time;
        low[city] = time;
        subtree[city] = node_values[city];
        discover_order.push_back(city);
    };
    const auto record_articulation = [&](int32_t city, double value, bool add) {
        if (!articulation_seen[city]) {
            articulation_seen[city] = 1;
            articulation_order.push_back(city);
        }
        articulation[city] = add ? articulation[city] + value : value;
    };
    for (int64_t i = 0; i < roots.size(); ++i) {
        const int32_t root = roots[i];
        if (disc[root]) continue;
        parent[root] = -1;
        child_count[root] = 0;
        discover(root);
        stack.push_back({root, adj_offsets[root]});
        while (!stack.empty()) {
            Frame &frame = stack.back();
            const int32_t u = frame.city;
            if (frame.arc < adj_offsets[u + 1]) {
                const int32_t v = adj_targets[frame.arc++];
                if (v == parent[u]) continue;
                if (!disc[v]) {
                    parent[v] = u;
                    ++child_count[u];
                    child_count[v] = 0;
                    discover(v);
                    stack.push_back({v, adj_offsets[v]});
                } else {
                    low[u] = std::min(low[u], disc[v]);
                }
                continue;
            }
            stack.pop_back();
            const int32_t p = parent[u];
            if (p == -1) {
                if (child_count[u] > 1) record_articulation(u, subtree[u] - node_values[u], false);
                continue;
            }
            subtree[p] = subtree[p] + subtree[u];
            low[p] = std::min(low[p], low[u]);
            if (low[u] > disc[p]) {
                const int64_t key = (int64_t(std::min(p, u)) << 32) | int64_t(std::max(p, u));
                bridges.emplace_back(key, subtree[u]);
            }
            if (parent[p] != -1 && low[u] >= disc[p]) record_articulation(p, subtree[u], true);
        }
    }
    Dictionary result_disc, result_low, result_subtree, result_articulation, result_bridges;
    for (int32_t city : discover_order) {
        result_disc[int64_t(city)] = int64_t(disc[city]);
        result_low[int64_t(city)] = int64_t(low[city]);
        result_subtree[int64_t(city)] = subtree[city];
    }
    for (int32_t city : articulation_order) result_articulation[int64_t(city)] = articulation[city];
    for (const auto &bridge : bridges) result_bridges[bridge.first] = bridge.second;
    Dictionary result;
    result["disc"] = result_disc;
    result["low"] = result_low;
    result["subtree"] = result_subtree;
    result["articulation"] = result_articulation;
    result["bridges"] = result_bridges;
    return result;
}

Dictionary NativeGraphSnapshot::make_access_mask(const PackedInt32Array &owners,
        const Dictionary &permissions, const PackedInt32Array &live_controls) const {
    const int64_t nodes = geometry.size() / 5;
    if (!configured || owners.size() != nodes ||
            (!live_controls.is_empty() && live_controls.size() != int64_t(controls.size())))
        return error_result("Invalid access-mask owner array.");
    PackedByteArray mask;
    mask.resize(controls.size());
    uint8_t *result_mask = mask.ptrw();
    const int32_t *node_owners = owners.ptr();
    std::unordered_map<int32_t, uint8_t> owner_access;
    owner_access.reserve(permissions.size());
    for (size_t edge = 0; edge < controls.size(); ++edge) {
        const int32_t control = live_controls.is_empty() ? controls[edge] : live_controls[edge];
        if (control < 0 || control >= nodes) {
            result_mask[edge] = 0;
            continue;
        }
        const int32_t owner = node_owners[control];
        const auto found = owner_access.find(owner);
        if (found != owner_access.end()) {
            result_mask[edge] = found->second;
            continue;
        }
        const Variant permitted = permissions.get(int64_t(owner), false);
        if (permitted.get_type() != Variant::BOOL)
            return error_result("Access-mask permissions must contain bool values.");
        const uint8_t value = bool(permitted) ? 1 : 0;
        owner_access.emplace(owner, value);
        result_mask[edge] = value;
    }
    Dictionary result;
    result["mask"] = mask;
    return result;
}

Dictionary NativeGraphSnapshot::patch_access_mask(const PackedByteArray &base,
        const PackedInt32Array &live_controls, int64_t goal, int64_t exit_city) const {
    if (!configured || base.size() != int64_t(controls.size()) || live_controls.size() != base.size())
        return error_result("Invalid access-mask patch arrays.");
    PackedByteArray mask = base;
    uint8_t *result_mask = mask.ptrw();
    const int32_t *current_controls = live_controls.ptr();
    const int64_t nodes = geometry.size() / 5;
    for (int64_t edge = 0; edge < mask.size(); ++edge) {
        const int32_t control = current_controls[edge];
        if (control >= 0 && control < nodes && (control == goal || control == exit_city)) result_mask[edge] = 1;
    }
    Dictionary result;
    result["mask"] = mask;
    return result;
}

Dictionary NativeGraphSnapshot::query_connectivity_filtered(const PackedInt32Array &roots,
        const PackedInt32Array &neighbor_offsets, const PackedInt32Array &neighbor_targets,
        const PackedByteArray &enabled, const PackedInt32Array &owners, int64_t nation,
        const Dictionary &values, double forward_sign) const {
    const int64_t nodes = geometry.size() / 5;
    if (!configured || !valid_csr(neighbor_offsets, neighbor_targets, nodes) ||
            enabled.size() != neighbor_targets.size() || owners.size() != nodes ||
            nation < 0 || nation > std::numeric_limits<int32_t>::max() ||
            !std::isfinite(forward_sign) || std::abs(forward_sign) > 1.0)
        return error_result("Invalid filtered connectivity query arrays.");
    for (int64_t i = 0; i < roots.size(); ++i) {
        if (roots[i] < 0 || roots[i] >= nodes || owners[roots[i]] != nation)
            return error_result("Invalid filtered connectivity root.");
    }
    const int32_t *source_offsets = neighbor_offsets.ptr();
    const int32_t *source_targets = neighbor_targets.ptr();
    const uint8_t *open = enabled.ptr();
    const int32_t *node_owners = owners.ptr();
    std::vector<int32_t> filtered_offsets;
    std::vector<int32_t> filtered_targets;
    filtered_offsets.reserve(nodes + 1);
    filtered_offsets.push_back(0);
    filtered_targets.reserve(neighbor_targets.size());
    PackedFloat64Array packed_values;
    packed_values.resize(nodes);
    packed_values.fill(0.0);
    double *node_values = packed_values.ptrw();
    std::vector<SortedNeighbor> neighbors;
    SortArray<SortedNeighbor, NeighborKeyLess> sorter;
    for (int64_t city = 0; city < nodes; ++city) {
        if (node_owners[city] == nation) {
            const Variant raw_value = values.get(city, 0.0);
            if (raw_value.get_type() != Variant::FLOAT && raw_value.get_type() != Variant::INT)
                return error_result("Filtered connectivity values must be numeric.");
            const double value = double(raw_value);
            if (!std::isfinite(value)) return error_result("Nonfinite filtered connectivity value.");
            node_values[city] = value;
            neighbors.clear();
            for (int32_t arc = source_offsets[city]; arc < source_offsets[city + 1]; ++arc) {
                const int32_t neighbor = source_targets[arc];
                if (!open[arc] || node_owners[neighbor] != nation) continue;
                neighbors.push_back({neighbor, city_key_in_frame(geometry, neighbor,
                        geometry[size_t(city) * 5], forward_sign)});
            }
            // Array.sort_custom uses Godot's introsort, including its equal-key
            // permutations. Neither std::sort nor stable_sort reproduces it.
            sorter.sort(neighbors.data(), int64_t(neighbors.size()));
            for (const SortedNeighbor &neighbor : neighbors) filtered_targets.push_back(neighbor.city);
        }
        filtered_offsets.push_back(int32_t(filtered_targets.size()));
    }
    PackedInt32Array packed_offsets;
    PackedInt32Array packed_targets;
    packed_offsets.resize(filtered_offsets.size());
    packed_targets.resize(filtered_targets.size());
    std::copy(filtered_offsets.begin(), filtered_offsets.end(), packed_offsets.ptrw());
    if (!filtered_targets.empty())
        std::copy(filtered_targets.begin(), filtered_targets.end(), packed_targets.ptrw());
    return query_connectivity(roots, packed_offsets, packed_targets, packed_values);
}

} // namespace godot
