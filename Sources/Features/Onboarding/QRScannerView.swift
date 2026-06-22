import SwiftUI
import AVFoundation

/// Full-screen camera QR scanner presented as a sheet during onboarding. Reports the first
/// decoded QR string via ``onScan`` and dismisses itself. Camera-permission states are handled
/// inline so the user is never dropped onto a black screen with no explanation.
struct QRScannerSheet: View {
    var onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Scan QR Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch status {
        case .authorized:
            scanner
        case .notDetermined:
            Color.black.ignoresSafeArea()
                .overlay { ProgressView().tint(.white) }
                .task {
                    let granted = await AVCaptureDevice.requestAccess(for: .video)
                    status = granted ? .authorized : .denied
                }
        default:
            deniedView
        }
    }

    private var scanner: some View {
        CameraView { code in
            onScan(code)
            dismiss()
        }
        .ignoresSafeArea()
        .overlay { reticle }
        .overlay(alignment: .bottom) {
            Text("Open User → Add a Device on your Baby Buddy site, then point your camera at the QR code.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding()
                .background(.black.opacity(0.5), in: .rect(cornerRadius: 12))
                .padding()
        }
    }

    private var reticle: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(.white.opacity(0.9), lineWidth: 3)
            .frame(width: 220, height: 220)
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label("Camera Access Needed", systemImage: "camera.fill")
        } description: {
            Text("Allow camera access in Settings to scan your Baby Buddy login QR code, or enter your server details manually.")
        } actions: {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(url) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// `AVFoundation` capture session that emits the string value of the first QR code it sees.
private struct CameraView: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {
        controller.onScan = onScan
    }
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.kurtisguy.BabyBuddy.qr-scan")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didScan,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue
        else { return }
        didScan = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onScan?(value)
    }
}
