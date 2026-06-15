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

## Vive locked baseline

These Vive controls are confirmed working and should not be changed while
debugging the remaining Vive buttons:

| Feature | Binding | Vive result |
|---|---|---|
| XR locomotion | left stick direct `primary` vector polling | Working |
| BancoIFU polarimeter | `right_stick_x` direct `primary.x` polling | Working |
| BancoIFU FM1 | `right_stick_y` direct `primary.y` polling | Working |

## BancoIFU active mapping

This is the short list to keep updated while validating the current
`BancoIFU.glb` controls. It only covers the controls used by BancoIFU in
`models/models.yaml`.

| BancoIFU feature | YAML binding | Meta Quest physical/OpenXR | Pico physical/OpenXR | Vive XR Elite physical/OpenXR |
|---|---|---|---|---|
| Filtered view `view1` | `left_ax_button` | left X -> `/user/hand/left/input/x/click` | left X -> `/user/hand/left/input/x/click` | unresolved; left trigger test did not work |
| Polarimeter motion | `right_stick_x` | right thumbstick X -> `/user/hand/right/input/thumbstick` | right thumbstick X -> `/user/hand/right/input/thumbstick` | right thumbstick X -> `/user/hand/right/input/thumbstick` |
| FM1 motion | `right_stick_y` | right thumbstick Y -> `/user/hand/right/input/thumbstick` | right thumbstick Y -> `/user/hand/right/input/thumbstick` | right thumbstick Y -> `/user/hand/right/input/thumbstick` |
| Reset BancoIFU controls | `right_stick_click` | right thumbstick click -> `/user/hand/right/input/thumbstick/click` | right thumbstick click -> `/user/hand/right/input/thumbstick/click` | right thumbstick click -> `/user/hand/right/input/thumbstick/click` |
| AR/VR toggle | code-level `left_by_button` | left Y -> `/user/hand/left/input/y/click` | left Y -> `/user/hand/left/input/y/click` | unresolved; right trigger test did not work |

## Vive button test history

This table only tracks Vive button mapping attempts that affect BancoIFU or the
AR/VR toggle. Sticks are intentionally out of scope here.

| Step | Button mapping tested | Vive result | Conclusion |
|---|---|---|---|
| 1 | Existing YAML mapping: `view1` uses `left_ax_button`; AR/VR uses `left_by_button`; reset uses `right_stick_click` | `right_stick_click` reset worked; `view1` and AR/VR buttons did not work | Stick-click button path is valid; X/Y style buttons still unresolved |
| 2 | Added broad fallback where `select_button` could satisfy A/X-style bindings | Left trigger activated `view1` | Too broad; `select_button`/trigger must not feed `left_ax_button` |
| 3 | Removed `select_button` from A/X-style bindings and removed trigger as AR/VR toggle | `right_stick_click` reset worked; other buttons still did not work | Better baseline for buttons, but X/Y/A/B still unresolved |
| 4 | Added event-based logical mapping for X/Y/A/B button press events | Reported as no improvement; current state should be rolled back or isolated | Event-based mapping needs a smaller diagnostic pass |
| 5 | Vive-only temporary mapping: left trigger feeds `left_ax_button`; right trigger feeds AR/VR toggle | Sticks worked; no button or trigger action was heard | Sticks are locked as baseline; remaining Vive button input needs a separate diagnostic path |
| 6 | Read Vive logcat after button test | Runtime sees physical controllers as `/interaction_profiles/htc/vive_focus3_controller`, but `xrSuggestInteractionProfileBindings` returned `XR_ERROR_PATH_UNSUPPORTED` for that profile | Focus3 profile was being rejected; remove unsupported Focus3 paths and retest buttons |
| 7 | Pruned the Focus3 profile and changed squeeze bindings from `click` to `value` | Regression: left stick, left trigger, and trigger hand feedback stopped working | Reverted. The hand feedback depends on `trigger_click`/`trigger`, so this broke a working trigger path |
| 8 | Clean debug export with no explicit `xr/openxr/default_action_map` | Regression: no sticks and no trigger hand feedback | Pin `xr/openxr/default_action_map` explicitly and retest clean debug export |

Next Vive-only button test should change one thing at a time and should not
touch stick polling or project action-map settings.
