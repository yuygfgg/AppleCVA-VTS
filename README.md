# AppleCVA VTS Source

macOS VTube Studio tracking source based on AppleCVA face tracking.

## Usage

Calibration is required before the app connects to VTube Studio or injects tracking parameters. Start the app, keep a neutral expression, look straight at the camera, and press `Calibrate First` button or `c` key.

The app injects available default VTS tracking parameters and, by default, creates full ARKit-style aliases plus a small set of derived `ACVA...` custom parameters.

### GUI Settings

All runtime settings are configured in the right-side panel and are saved for the next launch:

| Setting                        | Purpose                                                                                                                                                                                                                                   |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Host / Port                    | VTube Studio websocket target.                                                                                                                                                                                                            |
| Inject custom parameters       | Enable derived `ACVA...` custom parameter creation and injection.                                                                                                                                                                         |
| Include ARKit aliases          | Create ARKit-style custom aliases when VTS does not expose matching defaults.                                                                                                                                                             |
| Fill raw ACVA blendshapes      | Use remaining VTS custom slots for raw `ACVA...` blendshape channels.                                                                                                                                                                     |
| Backend                        | Switch between auto, full, and lite AppleCVA backend modes. Auto is the default: it uses full when full tracks a face and uses lite only when full returns zero tracked faces. Changing backend restarts tracking and clears calibration. |
| Use One Euro filter            | Toggle smoothing for preview and emitted VTS data.                                                                                                                                                                                        |
| Min cutoff / Beta / Derivative | Tune the One Euro filter parameters live.                                                                                                                                                                                                 |
| Preview toggles                | Mirror preview, camera visibility, landmark Y flip, and source-origin handling.                                                                                                                                                           |

### One Euro Tuning

1. Set `Beta` to `0`.
2. Move slowly and watch the preview and VTube Studio model. Lower `Min cutoff` until slow movement and idle tracking no longer jitter. At this stage, fast movement will usually feel very delayed; ignore that for now.
3. Keep that `Min cutoff` value fixed. Move quickly, then slowly raise `Beta` until fast movement no longer feels delayed and the model follows your motion closely.
4. Stop as soon as the motion feels responsive. Too much `Beta` brings fast-motion noise back.

`Derivative` is an advanced One Euro parameter. Leave it at the default unless `Beta` feels unstable even after tuning. If `Beta` reacts too nervously, raise `Derivative` slightly; if `Beta` feels slow to engage, lower it slightly.

### Preview Controls

The app window must be focused. Shortcuts are ignored while editing Host or Port.

| Key | Action                                                              |
| --- | ------------------------------------------------------------------- |
| `x` | Toggle mirrored preview and overlay.                                |
| `p` | Toggle camera preview visibility while keeping overlay/status text. |
| `y` | Toggle landmark Y-axis flip within the detected landmark bounds.    |
| `b` | Toggle face rectangle and landmark coordinate origin handling.      |
| `e` | Toggle One Euro Filter smoothing for both preview and emitted data. |
| `c` | Calibrate neutral pose.                                             |

## Build

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

This builds `build/AppleCVA VTS Source.app`. To use a specific signing identity, configure with `-DAPPLECVA_CODESIGN_IDENTITY="Developer ID Application: ..."`.

## Package App

Build a local release zip containing the `.app` bundle:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release --parallel
cmake --build build --config Release --target package
```

## License

This project is licensed under the [GPL-3.0](./LICENSE) license, or any later version.
