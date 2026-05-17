import ARKit
import UIKit
import simd

struct IntrinsicsSample {
    let timestamp: TimeInterval
    let width: Int
    let height: Int
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float
    let rows: [[Float]]
    let trackingState: String

    var horizontalFovDegrees: Float {
        guard fx > 0 else { return 0 }
        return 2.0 * atan(Float(width) / (2.0 * fx)) * 180.0 / .pi
    }

    var verticalFovDegrees: Float {
        guard fy > 0 else { return 0 }
        return 2.0 * atan(Float(height) / (2.0 * fy)) * 180.0 / .pi
    }

    func report() -> String {
        let matrixText = rows.map {
            String(format: "[%10.4f %10.4f %10.4f]", $0[0], $0[1], $0[2])
        }.joined(separator: "\n")
        return """
            ARKit FaceTracking intrinsics
            time: \(String(format: "%.4f", timestamp))
            resolution: \(width)x\(height)
            fx/fy/cx/cy: \(String(format: "%.4f %.4f %.4f %.4f", fx, fy, cx, cy))
            fov x/y: \(String(format: "%.3f %.3f", horizontalFovDegrees, verticalFovDegrees)) deg
            K:
            \(matrixText)
            tracking: \(trackingState)
            """
    }
}

final class IntrinsicsViewController: UIViewController, ARSessionDelegate {
    private let arSession = ARSession()
    private let textView = UITextView()
    private let copyButton = UIButton(type: .system)

    private var currentReport = "Waiting for ARKit FaceTracking intrinsics..."
    private var lastUIUpdate = Date.distantPast

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureUI()
        arSession.delegate = self
        startARKitFaceTracking()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arSession.pause()
    }

    private func configureUI() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = UIColor(white: 0.04, alpha: 1.0)
        textView.textColor = .white
        textView.font = UIFont.monospacedSystemFont(
            ofSize: 13,
            weight: .regular
        )
        textView.isEditable = false
        textView.alwaysBounceVertical = true
        textView.text = currentReport
        view.addSubview(textView)

        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.setTitle("Copy", for: .normal)
        copyButton.addTarget(
            self,
            action: #selector(copyReport),
            for: .touchUpInside
        )
        view.addSubview(copyButton)

        NSLayoutConstraint.activate([
            copyButton.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 12
            ),
            copyButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 8
            ),
            textView.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor
            ),
            textView.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor
            ),
            textView.topAnchor.constraint(
                equalTo: copyButton.bottomAnchor,
                constant: 8
            ),
            textView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor
            ),
        ])
    }

    @objc private func copyReport() {
        UIPasteboard.general.string = currentReport
        copyButton.setTitle("Copied", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.copyButton.setTitle("Copy", for: .normal)
        }
    }

    private func startARKitFaceTracking() {
        guard ARFaceTrackingConfiguration.isSupported else {
            updateText("ARKit FaceTracking is not supported on this device.")
            return
        }

        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = false
        arSession.run(
            configuration,
            options: [.resetTracking, .removeExistingAnchors]
        )
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let sample = sampleFromFrame(frame)
        updateText(sample.report(), throttled: true)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        updateText("ARKit session failed: \(error.localizedDescription)")
    }

    private func sampleFromFrame(_ frame: ARFrame) -> IntrinsicsSample {
        let matrix = frame.camera.intrinsics
        let rows = [
            [matrix.columns.0.x, matrix.columns.1.x, matrix.columns.2.x],
            [matrix.columns.0.y, matrix.columns.1.y, matrix.columns.2.y],
            [matrix.columns.0.z, matrix.columns.1.z, matrix.columns.2.z],
        ]
        return IntrinsicsSample(
            timestamp: frame.timestamp,
            width: Int(frame.camera.imageResolution.width),
            height: Int(frame.camera.imageResolution.height),
            fx: matrix.columns.0.x,
            fy: matrix.columns.1.y,
            cx: matrix.columns.2.x,
            cy: matrix.columns.2.y,
            rows: rows,
            trackingState: trackingStateText(frame.camera.trackingState)
        )
    }

    private func trackingStateText(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal:
            return "normal"
        case .notAvailable:
            return "not available"
        case .limited(let reason):
            return "limited \(reason)"
        }
    }

    private func updateText(_ text: String, throttled: Bool = false) {
        DispatchQueue.main.async {
            let now = Date()
            if throttled && now.timeIntervalSince(self.lastUIUpdate) < 0.25 {
                return
            }
            self.lastUIUpdate = now
            self.currentReport = text
            self.textView.text = text
        }
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = IntrinsicsViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
