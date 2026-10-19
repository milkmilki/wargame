#ifndef WARGAME_ATLAS_MESH_HPP
#define WARGAME_ATLAS_MESH_HPP
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
namespace godot {
// Pure generation kernels; all boundary and triangulation scratch is per-call.
class NativeAtlasMesh : public RefCounted {
    GDCLASS(NativeAtlasMesh, RefCounted)
    Dictionary build_mesh_with_clearance(const Dictionary &partition, const PackedFloat32Array &samples, int attempt) const;
protected:
    static void _bind_methods();
public:
    int64_t api_version() const { return 1; }
    Dictionary partition_water(int64_t width, int64_t height, const PackedByteArray &water) const;
    Dictionary build_mesh(const Dictionary &partition, const PackedFloat32Array &samples) const;
};
}
#endif
