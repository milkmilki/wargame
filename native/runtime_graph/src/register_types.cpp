#include "register_types.hpp"
#include "runtime_graph.hpp"
#include "atlas_display.hpp"

#include <godot_cpp/godot.hpp>

void initialize_runtime_graph(godot::ModuleInitializationLevel level) {
    if (level == godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
        godot::ClassDB::register_class<godot::NativeGraphSnapshot>();
        godot::ClassDB::register_class<godot::NativeAtlasDisplay>();
    }
}

void uninitialize_runtime_graph(godot::ModuleInitializationLevel level) {
    // All snapshots are RefCounted; the extension owns no global world state.
}

extern "C" {
GDExtensionBool GDE_EXPORT runtime_graph_library_init(
        GDExtensionInterfaceGetProcAddress get_proc_address,
        GDExtensionClassLibraryPtr library,
        GDExtensionInitialization *initialization) {
    godot::GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize_runtime_graph);
    init.register_terminator(uninitialize_runtime_graph);
    init.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
}
