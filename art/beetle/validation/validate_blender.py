"""Validate the saved model and render the actual game GLB, without rebuilding it.

Run from the repository root with Blender --background --python this_file.
The .blend and .glb are read only; reports and the final preview are refreshed.
"""

import hashlib
import json
import math
from datetime import datetime, timezone
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree


ART = Path(__file__).resolve().parents[1]
ROOT = ART.parents[1]
BLEND = ART / "beetle.blend"
GLB = ROOT / "resources/models/beetle/beetle.glb"
REPORT = ART / "validation/blender_validation.json"
EXPECTED = {
    "WingShell", "Abdomen", "Thorax", "Head", "Arm_L", "Arm_R",
    "Leg_Middle_L", "Leg_Middle_R", "Leg_Rear_L", "Leg_Rear_R",
}
errors = []


def check(condition, message):
    if not condition:
        errors.append(message)


def coordinates(obj):
    return [obj.matrix_world @ v.co for v in obj.data.vertices]


bpy.ops.wm.open_mainfile(filepath=str(BLEND))
collection = bpy.data.collections["Beetle_Model"]
objects = {o.name: o for o in collection.objects if o.type == "MESH"}
check(set(objects) == EXPECTED, "Unexpected source mesh names")
source = {}
mesh_reports = {}
for name, obj in objects.items():
    mesh = obj.data
    mesh.calc_loop_triangles()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    stats = {
        "vertices": len(mesh.vertices),
        "triangles": len(mesh.loop_triangles),
        "non_manifold_edges": sum(not e.is_manifold for e in bm.edges),
        "inconsistent_winding_edges": sum(not e.is_contiguous for e in bm.edges),
        "loose_vertices": sum(not v.link_faces for v in bm.verts),
        "zero_area_triangles": sum(t.area < 1e-10 for t in mesh.loop_triangles),
        "signed_volume": bm.calc_volume(signed=True),
        "finite_coordinates": all(math.isfinite(c) for v in mesh.vertices for c in v.co),
        "neutral_rotation": all(abs(a) < 1e-7 for a in obj.rotation_euler),
        "unit_scale": all(abs(s - 1) < 1e-7 for s in obj.scale),
    }
    bm.free()
    for key in ("non_manifold_edges", "inconsistent_winding_edges", "loose_vertices", "zero_area_triangles"):
        check(stats[key] == 0, f"{name}: {key} = {stats[key]}")
    for key in ("finite_coordinates", "neutral_rotation", "unit_scale"):
        check(stats[key], f"{name}: {key} failed")
    check(stats["signed_volume"] > 0, f"{name}: normals are not outward")
    check(obj.parent and obj.parent.name == "Beetle", f"{name}: unexpected parent")
    source[name] = {"coordinates": coordinates(obj), "pivot": obj.matrix_world.translation.copy(), "triangles": stats["triangles"]}
    mesh_reports[name] = stats

wing = objects["WingShell"].data
uv = wing.uv_layers.active.data
uv_areas = []
for triangle in wing.loop_triangles:
    if wing.polygons[triangle.polygon_index].material_index == 0:
        a, b, c = [uv[i].uv for i in triangle.loops]
        uv_areas.append((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
check(all(a > 1e-10 for a in uv_areas), "Wing image UV has flipped or zero-area triangles")
texture = bpy.data.images.get("wing_basecolor")
packed_texture = bool(texture and texture.packed_file and tuple(texture.size) == (1024, 1024))
check(packed_texture, "Wing texture missing or not packed at 1024 x 1024")
check(sum(v["vertices"] for v in mesh_reports.values()) <= 1000, "Source vertex budget exceeded")

# Replace only the in-memory model with the deliverable GLB. Retain the studio.
# No save operation is performed on either source model.
for obj in list(collection.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(GLB))
imported = set(bpy.data.objects) - before
game_meshes = {o.name: o for o in imported if o.type == "MESH"}
bpy.context.view_layer.update()
check(set(game_meshes) == EXPECTED, "Unexpected exported mesh names")
check(all(o.type in {"MESH", "EMPTY"} for o in imported), "GLB includes presentation objects")
comparison = {}
for name, obj in game_meshes.items():
    if name not in source:
        continue
    original = source[name]
    actual = coordinates(obj)
    distances = []
    for a, b in ((original["coordinates"], actual), (actual, original["coordinates"])):
        tree = KDTree(len(a))
        for index, point in enumerate(a):
            tree.insert(point, index)
        tree.balance()
        distances.extend(tree.find(point)[2] for point in b)
    obj.data.calc_loop_triangles()
    comparison[name] = {
        "maximum_vertex_distance": max(distances),
        "pivot_distance": (obj.matrix_world.translation - original["pivot"]).length,
        "triangles_match": len(obj.data.loop_triangles) == original["triangles"],
    }
    check(max(distances) < 1e-5, f"{name}: exported geometry differs from .blend")
    check(comparison[name]["pivot_distance"] < 1e-5, f"{name}: exported pivot differs from .blend")
    check(comparison[name]["triangles_match"], f"{name}: exported triangle count differs")

report = {
    "checked_at_utc": datetime.now(timezone.utc).isoformat(),
    "blender_version": bpy.app.version_string,
    "source_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (BLEND, GLB)},
    "passed": not errors,
    "errors": errors,
    "source_meshes": mesh_reports,
    "wing_uv_positive_area": all(a > 1e-10 for a in uv_areas),
    "wing_texture_packed": packed_texture,
    "export_matches_source": comparison,
    "preview_source": "resources/models/beetle/beetle.glb",
}
REPORT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
if errors:
    raise RuntimeError("; ".join(errors))

scene = bpy.context.scene
camera = scene.camera
camera.location = (4.8, 5.7, 5.6)
camera.rotation_euler = (Vector((0, 0.06, 0.42)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.ortho_scale = 4.25
scene.cycles.samples = 64
scene.render.resolution_x = 1400
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.render.filepath = str(ART / "preview/beetle_final.png")
bpy.ops.render.render(write_still=True)
print("BEETLE_FINAL_VALIDATION_PASSED " + str(REPORT))
