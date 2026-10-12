#pragma once

#include <godot_cpp/core/class_db.hpp>

void initialize_runtime_graph(godot::ModuleInitializationLevel level);
void uninitialize_runtime_graph(godot::ModuleInitializationLevel level);
