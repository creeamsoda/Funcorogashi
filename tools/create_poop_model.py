"""Build a compact low-poly coiled-tube poop model for Godot."""

import json
import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art" / "poop"
GAME = ROOT / "resources" / "models" / "poop"
ART.mkdir(parents=True, exist_ok=True)
GAME.mkdir(parents=True, exist_ok=True)
(ART / ".gdignore").write_text("", encoding="utf-8")

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for collection in list(bpy.data.collections):
    if collection.name != "Collection":
        bpy.data.collections.remove(collection)
model_collection = bpy.data.collections.get("Collection")
model_collection.name = "Poop_Model"
presentation = bpy.data.collections.new("Presentation_Not_Exported")
bpy.context.scene.collection.children.link(presentation)

# Sweep one long, tapered tube around a conical helix. Its lower end makes an
# extra horizontal curl at ground level before the tube winds upward.
path_steps = 32
radial_segments = 12
turns = 3.1
lower_horizontal_turns = 0.35
lower_horizontal_fraction = 0.12
rise_start_u = 0.094  # about 0.6 revolution from the bottom end
total_angle = math.tau * turns
path_radius_start = 0.25
tube_radius_start = 0.23
bottom_center_z = 0.18
top_center_z = 1.195
vertices = []
faces = []
centers = []

def smoothstep01(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def orbit_radius_at(u):
    # Keep the cut lower end slightly out from center, then ease into the base coil.
    start_inset = 0.45 + 0.55 * smoothstep01(u / 0.14)
    return path_radius_start * (1 - u) ** 1.12 * start_inset


def tube_radius_at(u):
    # Let the lower end taper in toward the center, then thicken smoothly into
    # the base coil. Upper turns are 10% thicker, easing out before the tip.
    lower_taper = 0.75 + 0.25 * smoothstep01(u / 0.16)
    upper_turns = smoothstep01((u - 0.30) / 0.12) * (1.0 - smoothstep01((u - 0.88) / 0.12))
    return 0.005 + tube_radius_start * (1 - u) ** 0.65 * lower_taper * (1.0 + 0.10 * upper_turns)


def angle_at(u):
    lower_curl = lower_horizontal_turns * smoothstep01(u / lower_horizontal_fraction)
    return math.tau * (turns * u + lower_curl)


for step in range(path_steps):
    u = step / (path_steps - 1)
    angle = angle_at(u)
    orbit_radius = orbit_radius_at(u)
    tube_radius = tube_radius_at(u)
    # The pitch tightens upward so the narrowing turns tuck together.
    rise_u = max(0.0, (u - rise_start_u) / (1.0 - rise_start_u))
    # Increase the early vertical climb after the lower 0.6 turn, while
    # preserving the same final height and the slope at the tip.
    z_progress = 2.5 * rise_u**2 - 2.0 * rise_u**3 + 0.5 * rise_u**4
    # Lower the upper two passes together to close their visible gaps, then
    # ease back into the tip so the overall height and pointed finish remain.
    upper_overlap = 0.075 * smoothstep01((u - 0.30) / 0.20) * (1.0 - smoothstep01((u - 0.72) / 0.25))
    # Compress only the top third vertically: the spiral footprint stays fixed,
    # while the tip drops to about 80% of its current height and the upper gaps close.
    top_drop = 0.20 * top_center_z * smoothstep01((u - 2.0 / 3.0) / (1.0 / 3.0))
    # Ease the final ~one turn upward more gently, lowering its end slightly
    # and bringing the upper coil closer to the tier below it.
    upper_slope_trim = 0.04 * top_center_z * smoothstep01((u - 0.65) / 0.35)
    upper_turn_drop = 0.035 * top_center_z * smoothstep01((u - 0.62) / 0.15) * (1.0 - smoothstep01((u - 0.88) / 0.12))
    # Flatten the band 1–1.5 turns below the tip, then recover that height over
    # the final half turn so the apex rises more sharply without changing height.
    middle_turn_relief = 0.035 * top_center_z * smoothstep01((u - 0.50) / 0.20)
    tip_half_lift = 0.035 * top_center_z * smoothstep01((u - 0.82) / 0.18)
    z = bottom_center_z + (top_center_z - bottom_center_z) * z_progress - upper_overlap - top_drop - upper_slope_trim - upper_turn_drop - middle_turn_relief + tip_half_lift
    center = Vector((orbit_radius * math.cos(angle), orbit_radius * math.sin(angle), z))
    centers.append(center)

for step, center in enumerate(centers):
    u = step / (path_steps - 1)
    angle = angle_at(u)
    tube_radius = tube_radius_at(u)
    tangent = (centers[min(step + 1, path_steps - 1)] - centers[max(step - 1, 0)]).normalized()
    normal = tangent.cross(Vector((0, 0, 1))).normalized()
    binormal = tangent.cross(normal).normalized()
    for side in range(radial_segments):
        around = math.tau * side / radial_segments
        point = center + tube_radius * (math.cos(around) * normal + math.sin(around) * binormal)
        vertices.append((1.32 * point.x, 1.32 * point.y, point.z))

for ring in range(path_steps - 1):
    for side in range(radial_segments):
        a = ring * radial_segments + side
        b = ring * radial_segments + (side + 1) % radial_segments
        faces.append((a, b, b + radial_segments, a + radial_segments))
faces.append(tuple(reversed(range(radial_segments))))
faces.append(tuple((path_steps - 1) * radial_segments + side for side in range(radial_segments)))

mesh = bpy.data.meshes.new("Poop_LowPoly_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
bm = bmesh.new()
bm.from_mesh(mesh)
# Slice the underside against the ground plane and cap the cut with a flat face.
bmesh.ops.bisect_plane(
    bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
    plane_co=(0, 0, 0), plane_no=(0, 0, 1), dist=1e-6,
    clear_inner=True, clear_outer=False,
)
cut_boundary = [edge for edge in bm.edges if edge.is_boundary]
if cut_boundary:
    bmesh.ops.holes_fill(bm, edges=cut_boundary, sides=0)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(mesh)
bm.free()
obj = bpy.data.objects.new("Poop_LowPoly", mesh)
model_collection.objects.link(obj)
obj["description"] = "One continuous tapered tube with a horizontal ground curl, then 2.73 rising turns"
obj["target_dimensions"] = "1.0 wide x 1.2 tall"
obj["toon_ready"] = True
for polygon in mesh.polygons:
    polygon.use_smooth = True

mat = bpy.data.materials.new("Poop_Toon_Base")
mat.diffuse_color = (0.28, 0.105, 0.035, 1)
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.28, 0.105, 0.035, 1)
bsdf.inputs["Roughness"].default_value = 0.82
mesh.materials.append(mat)

# Studio preview setup is kept separate from the exported game model.
def studio_object(obj):
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    presentation.objects.link(obj)

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 900
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.view_settings.view_transform = "AgX"
scene.world.color = (0.16, 0.16, 0.16)
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, 0))
ground = bpy.context.object
ground.name = "Studio_Ground"
ground_mat = bpy.data.materials.new("Studio_Ground_Material")
ground_mat.diffuse_color = (0.66, 0.72, 0.75, 1)
ground.data.materials.append(ground_mat)
studio_object(ground)

for name, location, power, size in [
    ("Key", (-3, -4, 6), 650, 4), ("Fill", (4, -1, 3), 350, 3), ("Rim", (0, 4, 5), 450, 3),
]:
    light_data = bpy.data.lights.new(name, "AREA")
    light_data.energy = power
    light_data.shape = "DISK"
    light_data.size = size
    light = bpy.data.objects.new(name, light_data)
    presentation.objects.link(light)
    light.location = location
    light.rotation_euler = (Vector((0, 0, 0.58)) - light.location).to_track_quat("-Z", "Y").to_euler()

camera_data = bpy.data.cameras.new("Preview_Camera")
camera = bpy.data.objects.new("Preview_Camera", camera_data)
presentation.objects.link(camera)
camera_data.type = "ORTHO"
camera.location = (3.1, -4.2, 3.1)
camera.rotation_euler = (Vector((0, 0, 0.60)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera_data.ortho_scale = 1.85
scene.camera = camera
scene.render.filepath = str(ART / "poop_preview.png")

bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
for item in presentation.objects:
    item.hide_set(True)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.shading.type = "MATERIAL"
            area.spaces.active.region_3d.view_distance = 2.8
            area.spaces.active.region_3d.view_location = (0, 0, 0.6)

bpy.ops.wm.save_as_mainfile(filepath=str(ART / "poop.blend"))
bpy.ops.render.render(write_still=True)
bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.export_scene.gltf(
    filepath=str(GAME / "poop.glb"), export_format="GLB", use_selection=True,
    export_apply=True, export_yup=True, export_materials="EXPORT",
)
mesh.calc_loop_triangles()
stats = {
    "vertices": len(mesh.vertices), "triangles": len(mesh.loop_triangles),
    "path_steps": path_steps, "radial_segments": radial_segments,
    "dimensions": {axis: round(float(getattr(obj.dimensions, axis)), 4) for axis in "xyz"},
    "materials": [mat.name],
}
(ART / "model_stats.json").write_text(json.dumps(stats, indent=2) + "\n", encoding="utf-8")
print("POOP_MODEL_STATS " + json.dumps(stats))
