# Gaea integration

This directory vendors Gaea `v2.0.0-beta6` at commit
`00f1d167f66e0945457bf5003aba084e9ec4d1b8`.

Upstream: <https://github.com/gaea-godot/gaea>

The game uses `GaeaGenerator`, `GaeaGraph`, `GaeaGrid`, and a custom
`GaeaRenderer` subclass to build the continuous strategic terrain mesh.
Simulation state remains authoritative; Gaea is a view-only generation
dependency.
