#ifndef WARGAME_ATLAS_DISPLAY_HPP
#define WARGAME_ATLAS_DISPLAY_HPP
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {
// Pure presentation kernels. Inputs and scratch buffers are per-call; no live
// model, rendering resource or global world cache crosses this boundary.
class NativeAtlasDisplay : public RefCounted {
    GDCLASS(NativeAtlasDisplay, RefCounted)
protected:
    static void _bind_methods();
public:
    int64_t api_version() const { return 1; }
    Dictionary paint_labels(const Dictionary &input) const;
    Dictionary edge_field(const PackedInt32Array &labels, int64_t w, int64_t h) const;
    Dictionary label_field(const PackedInt32Array &regions, const PackedInt32Array &ownership, int64_t w, int64_t h) const;
    Dictionary label_rays(const Dictionary &field, int64_t polity, int64_t cell, double max_length, const Array &hole) const;
    Dictionary fit_label(const Dictionary &rays, const Array &sizes, int64_t text_length) const;
    Array label_tiles(const PackedInt32Array &labels, int64_t w, int64_t h, int64_t tile, const PackedInt32Array &ids) const;
    Array region_tiles(const PackedInt32Array &provinces, int64_t regions, int64_t w, int64_t h, int64_t tile) const;
};
}
#endif
