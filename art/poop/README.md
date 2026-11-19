# Low-poly poop model

`poop.blend` is the editable Blender project. `../..` is the repository root; the game-ready model is `../../resources/models/poop/poop.glb`.

- One continuous tapered tube with a horizontal ground-level curl, continuing into a 2.73-turn rising coil.
- Upper turns overlap more closely; the underside is cut flat at the ground plane.
- The lower cut end reaches the ground slightly out from the coil center, and the upper turns are 10% thicker except at the tip.
- The upper third is compressed to close gaps, lowering the tip to about 80% of the previous height.
- A single closed mesh with about 780 triangles, softly shaded, approximately 1.0 wide × 0.91 tall.
- Includes a simple brown base material. The geometry is ready for a toon material in Godot.
- `poop_preview.png` is a studio preview; presentation objects are excluded from the GLB.

Regenerate from the repository root with Blender 5.2:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python tools/create_poop_model.py
```
