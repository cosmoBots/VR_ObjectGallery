# OpenXR control mapping

This project uses logical control names in `models/models.yaml`. Godot maps those
logical names to OpenXR actions, and `openxr_action_map.tres` maps those actions
to the physical controls exposed by each headset profile.

## Project logical controls

| YAML / code binding | Godot OpenXR action | Meta Quest profile | Pico 4 profile | Vive Focus 3 / XR Elite profile |
|---|---|---|---|---|
| `left_stick_x/y` | `primary` left | left thumbstick | left thumbstick | left thumbstick |
| `right_stick_x/y` | `primary` right | right thumbstick | right thumbstick | right thumbstick |
| `left_stick_click` | `primary_click` left | left thumbstick click | left thumbstick click | left thumbstick click |
| `right_stick_click` | `primary_click` right | right thumbstick click | right thumbstick click | right thumbstick click |
| `left_trigger_click` | `trigger_click` left | left trigger | left trigger | left trigger |
| `right_trigger_click` | `trigger_click` right | right trigger | right trigger | right trigger |
| `left_ax_button` | `ax_button` left | X click | X click | X click |
| `right_ax_button` | `ax_button` right | A click | A click | A click |
| `left_by_button` | `by_button` left | Y click | Y click | Y click |
| `right_by_button` | `by_button` right | B click | B click | B click |
| `left_secondary_x/y` | `secondary` left | not bound | not bound | not bound |
| `right_secondary_x/y` | `secondary` right | not bound | not bound | not bound |
| `left_secondary_click` | `secondary_click` left | not bound | not bound | not bound |
| `right_secondary_click` | `secondary_click` right | not bound | not bound | not bound |

Note: in OpenXR, A is normally on the right controller. The left-side equivalent
is X. Therefore a YAML binding named `left_ax_button` maps to X, while
`right_ax_button` maps to A.

## Vive controls exposed in the action map

The Vive XR Elite build currently uses the Khronos loader and the action map
contains the `/interaction_profiles/htc/vive_focus3_controller` profile.

Physical controls on the Vive controllers:

| Controller | Physical controls |
|---|---|
| Left | menu, X, Y, grip, trigger, stick |
| Right | logo/system, A, B, grip, trigger, stick |

| Godot OpenXR action | Vive physical path |
|---|---|
| `default_pose` | left/right `aim/pose` |
| `aim_pose` | left/right `aim/pose` |
| `grip_pose` | left/right `grip/pose` |
| `palm_pose` | left/right `grip_surface/pose` |
| `menu_button` | left menu |
| `select_button` | right logo/system |
| `ax_button` | left X, right A |
| `by_button` | left Y, right B |
| `trigger` | left/right trigger value |
| `trigger_click` | left/right trigger click |
| `trigger_touch` | left/right trigger touch |
| `grip` | left/right grip |
| `grip_click` | left/right grip click |
| `primary` | left/right stick |
| `primary_click` | left/right stick click |
| `primary_touch` | left/right stick touch |
| `secondary_touch` | left/right `thumbrest/touch` |
| `haptic` | left/right `output/haptic` |

## Current YAML usage

`models/models.yaml` currently uses:

| Model feature | Binding |
|---|---|
| Banco IFU filtered view `view1` | `left_ax_button` |
| Banco IFU polarimeter control | `right_stick_x` |
| Banco IFU FM1 control | `right_stick_y` |
| Banco IFU control reset | `right_stick_click` |
| XR locomotion | left stick, handled in `main.gd` |
| AR/VR toggle | `left_by_button`, handled in `main.gd` |
