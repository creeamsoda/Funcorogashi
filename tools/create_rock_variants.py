"""Create independently shaped low-poly wall rocks for the stage boundary."""

import json
import math
import random
from pathlib import Path

import bpy
import bmesh
from mathutils import Euler, Vector

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art" / "rock"
GAME = ROOT / "resources" / "models" / "rock"
SOURCE = ART / "rock.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
base = bpy.data.objects["Potato_Rock"]
model_collection = bpy.data.collections["Rock_Model"]


def dissolve_to_panels(mesh, seed, chance, max_sides=8):
    """Turn an icosphere into an irregular field of pentagon-plus stone planes."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.normal_update()
    rng = random.Random(seed)
    edges = list(bm.edges)
    rng.shuffle(edges)
    # First join small pairs of triangles into quads.
    for edge in edges:
        if not edge.is_valid or len(edge.link_faces) != 2 or rng.random() >= chance:
            continue
        merged_sides = sum(len(face.verts) for face in edge.link_faces) - 2
        if merged_sides <= max_sides:
            bmesh.ops.dissolve_edges(bm, edges=[edge], use_verts=False)
    # Then grow irregular pentagons and hexagons by joining neighboring panels.
    edges = list(bm.edges)
    rng.shuffle(edges)
    for edge in edges:
        if not edge.is_valid or len(edge.link_faces) != 2 or rng.random() >= 0.72:
            continue
        merged_sides = sum(len(face.verts) for face in edge.link_faces) - 2
        if 5 <= merged_sides <= max_sides:
            bmesh.ops.dissolve_edges(bm, edges=[edge], use_verts=False)
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def add_materials(mesh, seed, role):
    for material in base.data.materials:
        mesh.materials.append(material)
    rng = random.Random(seed + 900)
    for poly in mesh.polygons:
        if role == "camel" and -1.15 < poly.center.x < 0.08 and poly.center.z > 1.9:
            poly.material_index = 1
        elif poly.center.z > 2.2 and rng.random() < 0.18:
            poly.material_index = 3
        else:
            poly.material_index = rng.choices((0, 1, 2), weights=(0.20, 0.54, 0.26))[0]
        poly.use_smooth = False


def new_rock(name, seed, axes, rotation, role):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    # Rotate each seed before shaping, so panel boundaries and face patterns differ.
    rot = Euler(rotation, "XYZ").to_matrix()
    rng = random.Random(seed)
    for vertex in obj.data.vertices:
        direction = rot @ vertex.co
        normal = direction.normalized()
        crown_smooth = max(0.0, min(1.0, (normal.z - 0.18) / 0.72)) if role == "camel" else 0.0
        detail_factor = 1.0 - 0.72 * crown_smooth
        roughness = 1.0 + detail_factor * 0.075 * math.sin(normal.x * 5.3 + normal.y * 2.7) * math.cos(normal.z * 4.1 - normal.x)
        roughness += rng.uniform(-0.045, 0.045) * detail_factor
        direction *= roughness
        p = Vector((direction.x * axes[0], direction.y * axes[1], direction.z * axes[2]))
        z = p.z + axes[2]

        if role == "camel":
            # Form a broad shoulder and two wide, separated crown shelves.
            x = p.x
            distance_left = abs(x + 1.32)
            distance_right = abs(x - 1.32)

            def broad_peak(distance):
                if distance <= 0.58:
                    return 1.0
                if distance >= 1.15:
                    return 0.0
                t = (distance - 0.58) / (1.15 - 0.58)
                return 0.5 * (1.0 + math.cos(math.pi * t))

            peak = max(broad_peak(distance_left), broad_peak(distance_right))
            top = 2.40 + 0.44 * peak  # raise the saddle without sharpening the crowns
            local_top = axes[2] * (1.0 + math.sqrt(max(0.0, 1.0 - (x / axes[0]) ** 2)))
            fraction = max(0.0, min(1.0, z / max(0.2, local_top)))
            z = fraction * top
            # Keep the lower half lumpy rather than turning the body into a box.
            z += 0.10 * math.sin(x * 2.2 + normal.y) * max(0.0, 1.0 - z / 1.4)
            height_fraction = max(0.0, min(1.0, z / (2.0 * axes[2])))
            lower_flare = 1.27 - 0.18 * height_fraction
            vertex.co = (p.x * lower_flare, p.y, z)
        else:
            # Taller independent boulder. Its bulk grows on the left flank and
            # lower-right flank, with no inherited upper-right notch.
            left = math.exp(-(((p.x + 1.45) / 0.62) ** 2 + ((z - 1.20) / 0.76) ** 2))
            lower_right = math.exp(-(((p.x - 1.22) / 0.70) ** 2 + ((z - 0.48) / 0.54) ** 2))
            p.x += -0.70 * left + 0.82 * lower_right
            p.y -= 0.31 * (left + lower_right)
            z *= 1.04
            # Uneven crown, with several shoulders instead of one repeated notch.
            z += 0.10 * math.sin(p.x * 2.1 + normal.y * 1.7) * max(0.0, (z - 1.1) / 1.6)
            vertex.co = (p.x, p.y, z)

    # Place the actual mesh bottom on Z=0 and slightly flatten only the contact patch.
    min_z = min(v.co.z for v in obj.data.vertices)
    for vertex in obj.data.vertices:
        vertex.co.z -= min_z
        if vertex.co.z < 0.32:
            vertex.co.z = 0.0
        elif vertex.co.z < 0.48:
            vertex.co.z = (vertex.co.z - 0.32) * 0.25

    if role == "camel":
        # Soften the inner shoulder of the left hump where the crown meets the saddle.
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        inner_flank = [v for v in bm.verts if -1.25 < v.co.x < 0.08 and v.co.z > 1.85]
        if inner_flank:
            for factor in (0.62, 0.36):
                bmesh.ops.smooth_vert(
                    bm,
                    verts=inner_flank,
                    factor=factor,
                    use_axis_x=True,
                    use_axis_y=False,
                    use_axis_z=True,
                )
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.update()
    obj.location = (0, 0, 0)

    # Independent deterministic panel groupings make the two rocks visibly distinct.
    dissolve_to_panels(obj.data, seed + 17, chance=0.60 if role == "camel" else 0.66, max_sides=8)
    add_materials(obj.data, seed, role)
    # Ensure this asset belongs to the model collection, not the presentation scene.
    for collection in list(obj.users_collection):
        if collection != model_collection:
            collection.objects.unlink(obj)
    if model_collection not in obj.users_collection:
        model_collection.objects.link(obj)
    return obj


camel = new_rock("Rock_Camel", seed=43, axes=(2.08, 0.94, 1.43), rotation=(0.23, -0.17, 0.31), role="camel")
camel.location = (-4.45, 0, 0)
asymmetric = new_rock("Rock_Asymmetric", seed=118, axes=(2.03, 0.97, 1.15), rotation=(-0.19, 0.28, -0.43), role="asymmetric")
asymmetric.location = (4.45, 0, 0)


def export_model(obj, filename, stats_filename):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=str(GAME / filename), export_format="GLB", use_selection=True, export_apply=True)
    face_sizes = [len(poly.vertices) for poly in obj.data.polygons]
    stats = {
        "model_vertices": len(obj.data.vertices),
        "polygon_faces": len(face_sizes),
        "faces_with_5_or_more_sides": sum(1 for sides in face_sizes if sides >= 5),
        "triangles": sum(max(0, sides - 2) for sides in face_sizes),
        "mesh_objects": 1,
        "materials": len(obj.data.materials),
        "dimensions": [round(float(v), 3) for v in obj.dimensions],
        "coordinate_system": {"blender_up": "+Z", "blender_forward": "+Y", "godot_up": "+Y", "godot_forward": "-Z"},
    }
    (ART / stats_filename).write_text(json.dumps(stats, indent=2), encoding="utf-8")


export_model(camel, "rock_camel.glb", "model_stats_camel.json")
export_model(asymmetric, "rock_asymmetric.glb", "model_stats_asymmetric.json")

# Side-by-side preview with the original model in the middle.
base.location = (0, 0, 0.58)
scene = bpy.context.scene
camera = bpy.data.objects.get("Preview_Camera")
camera.location = (0, -17.5, 7.2)
camera.rotation_euler = (Vector((0, 0, 1.45)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 14.8
scene.camera = camera
for light_name in ("Preview_Key", "Preview_Fill", "Preview_Rim"):
    light = bpy.data.objects.get(light_name)
    if light:
        light.data.energy *= 1.7
        light.data.size = 7.0
scene.render.resolution_x = 1500
scene.render.resolution_y = 820
scene.render.resolution_percentage = 100
scene.render.filepath = str(ART / "rock_variants_preview.png")
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ART / "rock_variants.blend"))
