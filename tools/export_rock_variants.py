"""Export the edited rock objects from art/rock/rock_variants.blend."""

import json
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art" / "rock"
GAME = ROOT / "resources" / "models" / "rock"
SOURCE = ART / "rock_variants.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
exports = (
    ("Potato_Rock", "rock.glb", "model_stats.json"),
    ("Rock_Camel", "rock_camel.glb", "model_stats_camel.json"),
    ("Rock_Asymmetric", "rock_asymmetric.glb", "model_stats_asymmetric.json"),
)
temp_collection = bpy.data.collections.new("Export_Temporary")
bpy.context.scene.collection.children.link(temp_collection)

for object_name, filename, stats_name in exports:
    source = bpy.data.objects[object_name]
    export_object = source.copy()
    export_object.data = source.data.copy()
    export_object.name = source.name
    export_object.location.x = 0.0
    export_object.location.y = 0.0
    temp_collection.objects.link(export_object)

    bpy.ops.object.select_all(action="DESELECT")
    export_object.select_set(True)
    bpy.context.view_layer.objects.active = export_object
    bpy.ops.export_scene.gltf(
        filepath=str(GAME / filename),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
    )

    side_counts = [len(poly.vertices) for poly in source.data.polygons]
    stats = {
        "model_vertices": len(source.data.vertices),
        "polygon_faces": len(side_counts),
        "faces_with_5_or_more_sides": sum(1 for sides in side_counts if sides >= 5),
        "triangles": sum(max(0, sides - 2) for sides in side_counts),
        "mesh_objects": 1,
        "materials": len(source.data.materials),
        "dimensions": [round(float(v), 3) for v in source.dimensions],
        "coordinate_system": {
            "blender_up": "+Z",
            "blender_forward": "+Y",
            "godot_up": "+Y",
            "godot_forward": "-Z",
        },
    }
    (ART / stats_name).write_text(json.dumps(stats, indent=2), encoding="utf-8")
    bpy.data.objects.remove(export_object, do_unlink=True)

# Refresh the comparison preview from the edited scene without saving over it.
scene = bpy.context.scene
scene.render.filepath = str(ART / "rock_variants_preview.png")
bpy.ops.render.render(write_still=True)
