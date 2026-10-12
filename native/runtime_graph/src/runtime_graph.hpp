#ifndef WARGAME_RUNTIME_GRAPH_HPP
#define WARGAME_RUNTIME_GRAPH_HPP

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>

#include <cstdint>
#include <vector>

namespace godot {

// A successfully configured snapshot is immutable. Query scratch buffers are
// local to each call, so frozen graph data may be shared by worker threads.
class NativeGraphSnapshot : public RefCounted {
    GDCLASS(NativeGraphSnapshot, RefCounted)

    bool configured = false;
    std::vector<int32_t> offsets;
    std::vector<int32_t> targets;
    std::vector<int32_t> edge_ids;
    std::vector<int32_t> controls;
    // Five scalars per node: x, y, abs(x - 0.5), height, relief.
    std::vector<double> geometry;

protected:
    static void _bind_methods();

public:
    int64_t api_version() const;
    bool configure(const PackedInt32Array &p_offsets,
            const PackedInt32Array &p_targets, const PackedInt32Array &p_edge_ids,
            const PackedInt32Array &p_controls, const PackedFloat64Array &p_geometry);

    // These boundary helpers read plain model properties in one native call;
    // they never invoke script methods and must run while models are frozen.
    Dictionary pack_edge_inputs(const Array &edges, int64_t modes,
            const PackedFloat64Array &constants) const;
    Dictionary pack_owner_inputs(const Array &cities) const;

    // Read live administrative topology once, then compute each country's
    // zero/one-hop field. This boundary query does not use cached CSR topology.
    Dictionary query_administrative_fields(const Array &cities,
            const Dictionary &adjacency, const Dictionary &edge_lookup,
            const PackedInt32Array &nations, const PackedInt32Array &capitals,
            int64_t traffic_kind) const;

    Dictionary query_travel(int64_t start, const PackedFloat64Array &costs,
            const PackedByteArray &enabled, double horizon) const;

    Dictionary query_path(int64_t start, const PackedInt32Array &extra_origins,
            const PackedFloat64Array &costs, const PackedByteArray &enabled,
            const PackedByteArray &accessible, const PackedByteArray &blocked_nodes,
            const PackedByteArray &allowed_nodes, int64_t goal, int64_t exit_city,
            bool control_access, double forward_sign, const PackedInt32Array &ranks,
            bool supply) const;

    Dictionary query_trade(const PackedInt32Array &starts,
            const PackedInt64Array &costs, const PackedByteArray &enabled,
            const PackedByteArray &allowed, const PackedByteArray &forbidden,
            int64_t inf_cost) const;

    Dictionary query_connectivity(const PackedInt32Array &roots,
            const PackedInt32Array &neighbor_offsets,
            const PackedInt32Array &neighbor_targets,
            const PackedFloat64Array &values) const;

    Dictionary make_access_mask(const PackedInt32Array &owners,
            const Dictionary &permissions, const PackedInt32Array &live_controls) const;

    Dictionary patch_access_mask(const PackedByteArray &base,
            const PackedInt32Array &live_controls, int64_t goal, int64_t exit_city) const;

    Dictionary query_connectivity_filtered(const PackedInt32Array &roots,
            const PackedInt32Array &neighbor_offsets,
            const PackedInt32Array &neighbor_targets, const PackedByteArray &enabled,
            const PackedInt32Array &owners, int64_t nation,
            const Dictionary &values, double forward_sign) const;
};

} // namespace godot

#endif
