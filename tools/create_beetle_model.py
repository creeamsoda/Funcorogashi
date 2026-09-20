"""Build the reference beetle. Run with Blender --background --python this_file.

The game asset has no subdivision, bones, or dependency on the presentation scene.
All six limbs are rigid meshes whose local origins sit at their body attachment.
"""

import json
import math
from pathlib import Path
import struct

import bpy
import bmesh
import numpy as np
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art" / "beetle"
GAME = ROOT / "resources" / "models" / "beetle"
for directory in (ART, GAME, ART / "textures", ART / "preview"):
    directory.mkdir(parents=True, exist_ok=True)
(ART / ".gdignore").write_text("", encoding="utf-8")

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for datablock in list(bpy.data.collections):
    if datablock.name != "Collection":
        bpy.data.collections.remove(datablock)
model_collection = bpy.data.collections.get("Collection")
model_collection.name = "Beetle_Model"
studio = bpy.data.collections.new("Presentation_Not_Exported")
bpy.context.scene.collection.children.link(studio)
root = bpy.data.objects.new("Beetle", None)
model_collection.objects.link(root)
root["forward_blender"] = "+Y"
root["forward_godot"] = "-Z"
root["description"] = "Continuous paintable wing shell; six rigid limbs with root pivots."
model_objects = []


def material(name, color, roughness=0.62):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


shell_mat = material("Wing_Image", (0.60, 0.63, 0.65), 0.58)
body_mat = material("Body", (0.23, 0.26, 0.28))
limb_mat = material("Limbs", (0.14, 0.17, 0.19), 0.68)


def save_image(name, pixels, path):
    h, w = pixels.shape[:2]
    img = bpy.data.images.new(name, width=w, height=h, alpha=True)
    img.colorspace_settings.name = "sRGB"
    img.pixels.foreach_set(pixels.astype(np.float32).ravel())
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    return img


size = 1024
pixels = np.ones((size, size, 4), dtype=np.float32)
pixels[:, :, :3] = (0.68, 0.71, 0.73)
# Only a painted line: the mesh height and normals do not dip at the center.
pixels[:, size // 2 - 1:size // 2 + 1, :3] = (0.35, 0.39, 0.42)
shell_image = save_image("wing_basecolor", pixels, ART / "textures" / "wing_basecolor.png")
shell_image.pack()
tex = shell_mat.node_tree.nodes.new("ShaderNodeTexImage")
tex.name = "Replace_With_Your_Image"
tex.label = "Replace this image to paint both wings together"
tex.image = shell_image
tex.extension = "EXTEND"
tex.location = (-340, 40)
shell_mat.node_tree.links.new(tex.outputs["Color"], shell_mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
save_image("wing_paint_blank", np.ones((size, size, 4), dtype=np.float32), ART / "textures" / "wing_paint_blank.png")


def mesh_object(name, vertices, faces, materials, origin=(0, 0, 0), uv_kind="planar", face_materials=None):
    origin = Vector(origin)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata([Vector(v) - origin for v in vertices], [], faces)
    mesh.update()
    # Recalculate consistent outward normals on the closed surfaces.
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    model_collection.objects.link(obj)
    obj.parent = root
    obj.location = origin
    for mat in materials:
        mesh.materials.append(mat)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
        if face_materials:
            polygon.material_index = face_materials[polygon.index]
    uv = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        for loop_id in polygon.loop_indices:
            co = mesh.vertices[mesh.loops[loop_id].vertex_index].co + origin
            if uv_kind == "wing":
                # Shared undistorted XY projection, no mirrored or stacked wing islands.
                uv.data[loop_id].uv = (0.5 + co.x / 2.12, (co.y + 1.23) / 1.95)
            else:
                uv.data[loop_id].uv = (0.5 + co.x / 3.0, (co.y + 1.4) / 3.0)
    model_objects.append(obj)
    return obj


def signed_power(value, power):
    return math.copysign(abs(value) ** power, value)


def make_shell():
    segments = 32
    center_y = -0.27
    vertices = [(0, center_y, 0.96)]
    faces, material_ids = [], []
    radii = (0.28, 0.54, 0.76, 0.91, 1.0)
    for r in radii:
        for j in range(segments):
            theta = 2 * math.pi * j / segments
            y_unit = signed_power(math.sin(theta), 0.64)
            x = 0.94 * signed_power(math.cos(theta), 0.58) * (1 + 0.08 * y_unit)
            y = 0.85 * y_unit
            z = 0.44 + 0.52 * max(0, 1 - r ** 3) ** 0.64
            vertices.append((r * x, center_y + r * y, z))
    for j in range(segments):
        faces.append((0, 1 + j, 1 + (j + 1) % segments))
        material_ids.append(0)
    for k in range(len(radii) - 1):
        a = 1 + k * segments
        b = a + segments
        for j in range(segments):
            n = (j + 1) % segments
            faces.append((a + j, b + j, b + n, a + n))
            material_ids.append(0)
    perimeter = 1 + (len(radii) - 1) * segments
    lower = len(vertices)
    for j in range(segments):
        x, y, _ = vertices[perimeter + j]
        vertices.append((x * 0.88, center_y + (y - center_y) * 0.90, 0.28))
    bottom = len(vertices)
    vertices.append((0, center_y, 0.25))
    for j in range(segments):
        n = (j + 1) % segments
        faces.append((perimeter + j, lower + j, lower + n, perimeter + n))
        material_ids.append(1)
        faces.append((bottom, lower + n, lower + j))
        material_ids.append(1)
    shell = mesh_object("WingShell", vertices, faces, [shell_mat, body_mat], uv_kind="wing", face_materials=material_ids)
    shell["texture_note"] = "Both wings share one continuous XY UV projection. Center line is texture only."
    shell["uv_front"] = "Top of image (+V); no left-right mirror."
    return shell


def ellipsoid(name, center, radius, segments, rings, mat, exponent=1.0):
    vertices = [(center[0], center[1], center[2] + radius[2])]
    for i in range(1, rings):
        latitude = math.pi * i / rings
        for j in range(segments):
            longitude = 2 * math.pi * j / segments
            x = signed_power(math.sin(latitude) * math.cos(longitude), exponent)
            y = signed_power(math.sin(latitude) * math.sin(longitude), exponent)
            z = math.cos(latitude)
            vertices.append(tuple(center[k] + radius[k] * (x, y, z)[k] for k in range(3)))
    bottom = len(vertices)
    vertices.append((center[0], center[1], center[2] - radius[2]))
    faces = []
    for j in range(segments):
        n = (j + 1) % segments
        faces.append((0, 1 + j, 1 + n))
    for row in range(rings - 2):
        a = 1 + row * segments
        b = a + segments
        for j in range(segments):
            n = (j + 1) % segments
            faces.append((a + j, b + j, b + n, a + n))
    a = 1 + (rings - 2) * segments
    for j in range(segments):
        faces.append((bottom, a + (j + 1) % segments, a + j))
    return mesh_object(name, vertices, faces, [mat])


def limb(name, points, radii, sides=8, thickness_ratio=0.76):
    centers = [Vector(v) for v in points]
    vertices = []
    for i, p in enumerate(centers):
        if i == 0:
            tangent = (centers[1] - p).normalized()
        elif i == len(centers) - 1:
            tangent = (p - centers[i - 1]).normalized()
        else:
            tangent = (centers[i + 1] - centers[i - 1]).normalized()
        across = tangent.cross(Vector((0, 0, 1))).normalized()
        up = across.cross(tangent).normalized()
        for j in range(sides):
            angle = 2 * math.pi * j / sides
            vertices.append(p + radii[i] * (math.cos(angle) * across + thickness_ratio * math.sin(angle) * up))
    faces = []
    for row in range(len(points) - 1):
        for j in range(sides):
            n = (j + 1) % sides
            a, b = row * sides, (row + 1) * sides
            faces.append((a + j, b + j, b + n, a + n))
    # An ellipsoidal end cap preserves a substantial toe width and rounds off
    # the tip instead of tapering the entire final segment to a needle point.
    end_ring = len(vertices)
    end_radius = radii[-1]
    cap_factor = math.sqrt(0.5)
    for j in range(sides):
        angle = 2 * math.pi * j / sides
        vertices.append(centers[-1] + end_radius * cap_factor * (
            tangent + math.cos(angle) * across + thickness_ratio * math.sin(angle) * up
        ))
    tip = len(vertices)
    vertices.append(centers[-1] + end_radius * tangent)
    last_ring = (len(points) - 1) * sides
    for j in range(sides):
        n = (j + 1) % sides
        faces.append((last_ring + j, end_ring + j, end_ring + n, last_ring + n))
        faces.append((end_ring + j, tip, end_ring + n))
    # The attachment end is closed inside the body.
    faces.append(tuple(reversed(range(sides))))
    obj = mesh_object(name, vertices, faces, [limb_mat], origin=points[0])
    obj.rotation_mode = "XYZ"
    obj["animation"] = "Rotate this object at its root. Entire limb is rigid."
    obj["section_thickness_to_width"] = thickness_ratio
    obj["rounded_tip"] = True
    return obj


shell = make_shell()
ellipsoid("Abdomen", (0, -0.22, 0.38), (0.79, 0.88, 0.26), 16, 6, body_mat)
ellipsoid("Thorax", (0, 0.72, 0.49), (0.82, 0.47, 0.35), 24, 8, body_mat)
ellipsoid("Head", (0, 1.13, 0.46), (0.38, 0.34, 0.28), 20, 6, body_mat, exponent=0.86)
arm_points = [
    (0.62, 0.82, 0.43), (0.83, 0.89, 0.35), (1.00, 1.02, 0.25),
    (1.03, 1.16, 0.15), (0.98, 1.31, 0.09), (0.91, 1.46, 0.06),
]
middle_points = [
    (0.70, 0.15, 0.37), (0.96, -0.01, 0.32), (1.16, -0.25, 0.25),
    (1.29, -0.61, 0.11), (1.36, -0.83, 0.045),
]
rear_points = [
    (0.67, -0.40, 0.35), (0.93, -0.57, 0.29), (1.08, -0.77, 0.21),
    (1.15, -1.10, 0.10), (1.20, -1.28, 0.045),
]
def smooth_samples(points, radii, count):
    """Sample the authored curve with a small, fixed number of cross sections."""
    controls = np.array([(*p, r) for p, r in zip(points, radii)], dtype=float)
    result = []
    for t in np.linspace(0, len(controls) - 1, count):
        i = min(int(t), len(controls) - 2)
        f = t - i
        p0, p1, p2, p3 = [controls[min(max(k, 0), len(controls) - 1)] for k in (i - 1, i, i + 1, i + 2)]
        value = 0.5 * ((2*p1) + (-p0+p2)*f + (2*p0-5*p1+4*p2-p3)*f*f + (-p0+3*p1-3*p2+p3)*f*f*f)
        result.append(value)
    return [tuple(v[:3]) for v in result], [float(v[3]) for v in result]


arm_points, arm_radii = smooth_samples(arm_points, [0.105, 0.11, 0.105, 0.09, 0.07, 0.045], 8)
# Left/right are the beetle's own sides when facing forward (+Y in Blender).
for suffix, sign in (("L", -1), ("R", 1)):
    mirror = lambda points: [(sign * x, y, z) for x, y, z in points]
    limb("Arm_" + suffix, mirror(arm_points), arm_radii, thickness_ratio=0.32)
    limb("Leg_Middle_" + suffix, mirror(middle_points), [0.065, 0.058, 0.049, 0.042, 0.036])
    limb("Leg_Rear_" + suffix, mirror(rear_points), [0.064, 0.056, 0.049, 0.042, 0.036])


def line_pixels(canvas, uv_a, uv_b, color, width=1):
    a = np.array(uv_a) * (size - 1)
    b = np.array(uv_b) * (size - 1)
    steps = max(2, int(np.linalg.norm(b - a) * 2))
    xs = np.rint(np.linspace(a[0], b[0], steps)).astype(int)
    ys = np.rint(np.linspace(a[1], b[1], steps)).astype(int)
    for dx in range(-width + 1, width):
        for dy in range(-width + 1, width):
            canvas[np.clip(ys + dy, 0, size - 1), np.clip(xs + dx, 0, size - 1)] = color


# Transparent guide contains only the dorsal image surface, not the overlapping underside.
uv_pixels = np.zeros((size, size, 4), dtype=np.float32)
uv_data = shell.data.uv_layers.active.data
svg_lines = []
seen_edges = set()
for poly in shell.data.polygons:
    if poly.material_index != 0:
        continue
    loop_ids = list(poly.loop_indices)
    for k, loop_a in enumerate(loop_ids):
        loop_b = loop_ids[(k + 1) % len(loop_ids)]
        ua, ub = tuple(uv_data[loop_a].uv), tuple(uv_data[loop_b].uv)
        key = tuple(sorted((ua, ub)))
        if key in seen_edges:
            continue
        seen_edges.add(key)
        line_pixels(uv_pixels, ua, ub, (0.10, 0.42, 0.55, 0.85))
        svg_lines.append(f'<line x1="{ua[0]*size:.2f}" y1="{(1-ua[1])*size:.2f}" x2="{ub[0]*size:.2f}" y2="{(1-ub[1])*size:.2f}"/>')
save_image("wing_uv_guide", uv_pixels, ART / "textures" / "wing_uv_guide.png")
(ART / "textures" / "wing_uv_guide.svg").write_text(
    '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
    '<g fill="none" stroke="#1b6b8c" stroke-width="1">' + ''.join(svg_lines) + '</g></svg>', encoding="utf-8")


def mesh_stats(obj):
    obj.data.calc_loop_triangles()
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    report = {
        "vertices": len(obj.data.vertices), "triangles": len(obj.data.loop_triangles),
        "non_manifold_edges": sum(not edge.is_manifold for edge in bm.edges),
        "zero_area_faces": sum(face.calc_area() < 1e-10 for face in bm.faces),
        "pivot_blender": [round(v, 5) for v in obj.location],
    }
    bm.free()
    return report


objects_report = {obj.name: mesh_stats(obj) for obj in model_objects}
assert all(v["non_manifold_edges"] == 0 and v["zero_area_faces"] == 0 for v in objects_report.values())
assert sum(v["vertices"] for v in objects_report.values()) <= 1000
bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for obj in model_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = root
glb_path = GAME / "beetle.glb"
bpy.ops.export_scene.gltf(
    filepath=str(glb_path), export_format="GLB", use_selection=True,
    export_yup=True, export_apply=False, export_animations=False,
    export_texcoords=True, export_normals=True, export_tangents=False,
    export_materials="EXPORT", export_cameras=False, export_lights=False,
    export_extras=True,
)
data = glb_path.read_bytes()
json_length = struct.unpack_from("<I", data, 12)[0]
gltf = json.loads(data[20:20 + json_length])
gltf_vertex_count = sum(gltf["accessors"][p["attributes"]["POSITION"]]["count"] for mesh in gltf["meshes"] for p in mesh["primitives"])
gltf_triangle_count = sum(gltf["accessors"][p["indices"]]["count"] // 3 for mesh in gltf["meshes"] for p in mesh["primitives"])
assert gltf_vertex_count <= 1000, f"Exported GPU vertices exceed budget: {gltf_vertex_count}"
report = {
    "model_vertices": sum(v["vertices"] for v in objects_report.values()),
    "gltf_vertices": gltf_vertex_count, "triangles": gltf_triangle_count,
    "mesh_objects": len(model_objects), "materials": len(gltf["materials"]),
    "coordinate_system": {"blender_up": "+Z", "blender_forward": "+Y", "godot_up": "+Y", "godot_forward": "-Z"},
    "objects": objects_report,
}
(ART / "model_stats.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print("MODEL_STATS " + json.dumps(report))


# Presentation collection is never selected for export.
def to_studio(obj):
    for col in list(obj.users_collection):
        col.objects.unlink(obj)
    studio.objects.link(obj)


scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 40
scene.cycles.use_denoising = True
scene.render.resolution_x = 1100
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "AgX"
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.50, 0.54, 0.60, 1)
scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.45
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, 0))
floor = bpy.context.object
floor.name = "Studio_Ground"
floor.data.materials.append(material("Studio_Ground_Material", (0.72, 0.72, 0.69), 0.9))
to_studio(floor)


def area_light(name, location, energy, size_light):
    light = bpy.data.lights.new(name, "AREA")
    light.energy = energy
    light.shape = "DISK"
    light.size = size_light
    obj = bpy.data.objects.new(name, light)
    studio.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector((0, 0, 0.5)) - obj.location).to_track_quat("-Z", "Y").to_euler()


area_light("Key", (-3, -2, 6), 500, 5)
area_light("Fill", (4, 1, 4), 270, 4)
area_light("Rim", (-1, 5, 4), 400, 3)
camera_data = bpy.data.cameras.new("Preview_Camera")
camera = bpy.data.objects.new("Preview_Camera", camera_data)
studio.objects.link(camera)
camera_data.type = "ORTHO"
scene.camera = camera


def camera_view(location, target=(0, 0.08, 0.40), scale=4.0):
    camera.location = location
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.ortho_scale = scale


def render(filename):
    scene.render.filepath = str(ART / "preview" / filename)
    bpy.ops.render.render(write_still=True)


camera_view((3.8, -5.5, 7), scale=3.85)
render("beetle_preview.png")
camera_view((4.8, 5.7, 4.2), scale=3.70)
render("beetle_front_oblique.png")
camera_view((0, 0.08, 8), target=(0, 0.08, 0), scale=3.65)
render("beetle_top.png")
camera_view((8, 0.08, 0.60), target=(0, 0.08, 0.60), scale=3.50)
render("beetle_side.png")
camera_view((0, 8, 0.60), target=(0, 0, 0.60), scale=3.50)
render("beetle_front.png")

# Diagnostic wireframe on the same mesh, no geometry modifier.
wire_materials = []
for original in (shell_mat, body_mat, limb_mat):
    wire_mat = original.copy()
    wire_mat.name = "Diagnostic_" + original.name
    nodes = wire_mat.node_tree.nodes
    links = wire_mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    for link in list(bsdf.inputs["Base Color"].links):
        links.remove(link)
    wire = nodes.new("ShaderNodeWireframe")
    wire.inputs["Size"].default_value = 0.006
    mix = nodes.new("ShaderNodeMixRGB")
    mix.inputs[1].default_value = (0.58, 0.65, 0.67, 1)
    mix.inputs[2].default_value = (0.025, 0.05, 0.06, 1)
    links.new(wire.outputs["Fac"], mix.inputs[0])
    links.new(mix.outputs[0], bsdf.inputs["Base Color"])
    wire_materials.append(wire_mat)
saved_materials = {}
for obj in model_objects:
    saved_materials[obj.name] = list(obj.data.materials)
    for index, mat in enumerate(obj.data.materials):
        obj.data.materials[index] = wire_materials[(shell_mat, body_mat, limb_mat).index(mat)]
camera_view((3.8, -5.5, 7), scale=3.85)
render("beetle_wire.png")
for obj in model_objects:
    for index, mat in enumerate(saved_materials[obj.name]):
        obj.data.materials[index] = mat

# Rigid root rotation proof; restore the neutral pose before saving.
bpy.data.objects["Arm_L"].rotation_euler = (math.radians(12), 0, math.radians(-20))
bpy.data.objects["Arm_R"].rotation_euler = (math.radians(12), 0, math.radians(20))
camera_view((0, 0.08, 8), target=(0, 0.08, 0), scale=3.65)
render("beetle_arm_pose.png")
for name in ("Arm_L", "Arm_R"):
    bpy.data.objects[name].rotation_euler = (0, 0, 0)

# Save an uncluttered editable scene with a useful material viewport and packed texture.
camera_view((3.8, -5.5, 7), scale=3.85)
for obj in studio.objects:
    obj.hide_set(True)
bpy.ops.object.select_all(action="DESELECT")
shell.select_set(True)
bpy.context.view_layer.objects.active = shell
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == "VIEW_3D":
            space = area.spaces.active
            space.shading.type = "MATERIAL"
            space.overlay.show_floor = False
            space.overlay.show_axis_x = False
            space.overlay.show_axis_y = False
            space.region_3d.view_distance = 5.0
            space.region_3d.view_location = (0, 0.08, 0.4)
            space.region_3d.view_rotation = camera.rotation_euler.to_quaternion()
bpy.ops.wm.save_as_mainfile(filepath=str(ART / "beetle.blend"))
print("BEETLE_BUILD_COMPLETE")
