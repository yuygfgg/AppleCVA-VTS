# Camera Viewer

Opens the default camera, runs Vision face detection, feeds the detected face rectangles into AppleCVA, and draws the tracked face rectangle, landmarks, and the strongest blendshape values.

## Environment Variables

| Variable                                   | Default                    | Effect                                                                                      |
| ------------------------------------------ | -------------------------- | ------------------------------------------------------------------------------------------- |
| `APPLECVA_FULL_API`                        | unset                      | Use the dictionary-based full AppleCVA backend instead of the Lite backend.                 |
| `APPLECVA_VISION_INTERVAL`                 | `1` for Lite, `6` for Full | Run Vision face detection every N frames.                                                   |
| `APPLECVA_TRACE`                           | unset                      | Print AppleCVA wrapper trace logs to stderr.                                                |
| `APPLECVA_FULL_FACE_SMOOTHING`             | `0.25`                     | Full backend input face smoothing alpha. Valid range is `0.0` to `1.0`.                     |
| `APPLECVA_FULL_FACE_HOLD`                  | `15`                       | Full backend frames to keep the last valid detected face when Vision temporarily misses it. |
| `APPLECVA_FULL_NETWORK_FAILURE_MULTIPLIER` | `1.0`                      | Full backend network failure threshold multiplier.                                          |
| `APPLECVA_FULL_FAILURE_FOV_MODIFIER`       | `0.5`                      | Full backend failure FOV modifier.                                                          |
| `APPLECVA_FULL_NUM_TRACKED_FACES`          | `1`                        | Full backend maximum tracked face count.                                                    |

## Keyboard Shortcuts

The camera viewer window must be focused.

| Key | Action                                                                                                      |
| --- | ----------------------------------------------------------------------------------------------------------- |
| `x` | Toggle mirrored preview and overlay.                                                                        |
| `p` | Toggle camera preview visibility while keeping the overlay/status text.                                     |
| `y` | Toggle landmark Y-axis flip within the detected landmark bounds.                                            |
| `b` | Toggle face rectangle and landmark coordinate origin handling between top-left and bottom-left conventions. |
| `l` | Toggle whether low-confidence tracking results are used.                                                    |
| `e` | Toggle One Euro Filter smoothing for the displayed tracking result.                                         |

## Build & Run

```sh
make build/camera_viewer
./build/camera_viewer
```
