"""Build a low-poly potato-shaped cliff rock for the stage boundary."""

import json
import math
import random
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art" / "rock"
GAME = ROOT / "resources" / "models" / "rock"
ART.mkdir(parents=True, exist_ok=True)
GAME.mkdir(parents=True, exist_ok=True)
(ART / ".gdignore").write_text("", encoding="utf-8")

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for collection in list(bpy.data.collections):
    if collection.name != "Collection":
        bpy.data.collections.remove(collection)
model_collection = bpy.data.collections.get("Collection")
model_collection.name = "Rock_Model"
presentation = bpy.data.collections.new("Presentation_Not_Exported")
bpy.context.scene.collection.children.link(presentation)

# Start with a denser icosphere, then dissolve its small triangles into larger
# planar-ish rock plates. The stage wall can cover the simpler rear side.
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0)
rock = bpy.context.object
rock.name = "Potato_Rock"
rock.data.name = "Potato_Rock_Mesh"
rock.scale = (2.0, 0.9, 1.45)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

# Merge the regular starter triangles before adding the rock's coarse shape.
bm = bmesh.new()
bm.from_mesh(rock.data)
bm.normal_update()
# Join roughly half the triangle edges into larger polygon panels.
random.seed(31)
panel_edges = list(bm.edges)
random.shuffle(panel_edges)
for edge in panel_edges:
    if not edge.is_valid or len(edge.link_faces) != 2:
        continue
    midpoint = (edge.verts[0].co + edge.verts[1].co) * 0.5
    rear_lower = midpoint.y > 0.15 and midpoint.z < 0.45
    # Keep more panels on the playfield-facing front and crown. The rear lower
    # half is simplified more aggressively because the wall hides it.
    chance = 0.84 if rear_lower else 0.62
    max_outline = 12 if rear_lower else 7
    if random.random() < chance and sum(len(face.verts) for face in edge.link_faces) - 4 <= max_outline:
        bmesh.ops.dissolve_edges(bm, edges=[edge], use_verts=False)
bm.normal_update()
bm.to_mesh(rock.data)
bm.free()
rock.data.update()

# Make broad, strongly uneven shoulders and a broken crown.
random.seed(19)
for vertex in rock.data.vertices:
    p = vertex.co
    n = Vector((p.x * 0.7 + 0.17, p.y * 1.1 - 0.31, p.z * 0.9 + 0.23)).normalized()
    wobble = 1.0 + 0.14 * math.sin(n.x * 5.2 + n.y * 2.4) * math.cos(n.z * 4.3 - n.y * 1.8)
    wobble += random.uniform(-0.055, 0.055)
    p *= wobble
    if p.z < -0.58:
        p.z = -0.58 + (p.z + 0.58) * 0.18
    # Slightly broaden the lower shoulders and lean the crown off center.
    p.x += 0.10 * max(0.0, p.z) - 0.06 * max(0.0, -p.z)
    p.y += 0.045 * math.sin(p.x * 1.7)
rock.data.update()

colors = [
    (0.20, 0.22, 0.23, 1.0),
    (0.27, 0.29, 0.30, 1.0),
    (0.34, 0.35, 0.34, 1.0),
    (0.40, 0.39, 0.36, 1.0),
]
materials = []
for i, color in enumerate(colors):
    mat = bpy.data.materials.new(f"Stone_{i+1}")
    mat.diffuse_color = color
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = color
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.92
    materials.append(mat)
    rock.data.materials.append(mat)
for poly in rock.data.polygons:
    # Mostly dark stone with a few lighter planes to show the broad facets.
    z = poly.center.z
    selector = (poly.index * 37 + 11) % 17
    poly.material_index = 3 if z > 0.65 and selector < 3 else (2 if selector < 7 else (1 if selector < 14 else 0))
    poly.use_smooth = False

rock.location = (0, 0, 0.58)
rock.color = colors[1]

# Save statistics for the actual editable mesh.
stats = {
    "model_vertices": len(rock.data.vertices),
    "triangles": sum(max(0, len(poly.vertices) - 2) for poly in rock.data.polygons),
    "large_polygon_faces": len(rock.data.polygons),
    "mesh_objects": 1,
    "materials": len(materials),
    "dimensions": [round(float(v), 3) for v in rock.dimensions],
    "coordinate_system": {"blender_up": "+Z", "blender_forward": "+Y", "godot_up": "+Y", "godot_forward": "-Z"},
}
(ART / "model_stats.json").write_text(json.dumps(stats, indent=2), encoding="utf-8")

# Render-only setup lives outside the exported model collection.
def move_to_presentation(obj):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    presentation.objects.link(obj)

bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, 0))
ground = bpy.context.object
ground.name = "Preview_Ground"
move_to_presentation(ground)
ground_mat = bpy.data.materials.new("Preview_Ground_Material")
ground_mat.diffuse_color = (0.075, 0.09, 0.095, 1)
ground_mat.use_nodes = True
ground_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.075, 0.09, 0.095, 1)
ground.data.materials.append(ground_mat)

bpy.ops.object.camera_add(location=(4.8, -7.0, 4.2))
camera = bpy.context.object
camera.name = "Preview_Camera"
move_to_presentation(camera)
camera.rotation_euler = (Vector((0, 0, 0.65)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 6.0
bpy.context.scene.camera = camera

for name, loc, energy, size in [
    ("Key", (2.0, -4.0, 7.0), 520, 5.0),
    ("Fill", (-4.0, -1.0, 3.0), 190, 4.0),
    ("Rim", (1.0, 4.0, 5.0), 380, 3.0),
]:
    bpy.ops.object.light_add(type="AREA", location=loc)
    light = bpy.context.object
    light.name = f"Preview_{name}"
    move_to_presentation(light)
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    light.rotation_euler = (Vector((0, 0, 0.5)) - light.location).to_track_quat("-Z", "Y").to_euler()

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1000
scene.render.resolution_y = 850
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(ART / "rock_preview.png")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.16, 0.18, 0.19, 1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "Medium High Contrast"
scene.view_settings.exposure = 0
scene.view_settings.gamma = 1
bpy.ops.render.render(write_still=True)

# Export only the game model. Godot imports glTF with its expected Y-up conversion.
bpy.ops.object.select_all(action="DESELECT")
rock.select_set(True)
bpy.context.view_layer.objects.active = rock
bpy.ops.export_scene.gltf(filepath=str(GAME / "rock.glb"), export_format="GLB", use_selection=True, export_apply=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ART / "rock.blend"))
