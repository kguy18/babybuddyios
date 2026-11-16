import SwiftUI
import AVFoundation
import UIKit

/// Full-screen camera QR scanner presented during onboarding. Reports the first
/// decoded QR string via ``onScan`` and dismisses itself. The scanner keeps its own dark
/// treatment regardless of the system appearance. Camera-permission states are handled inline
/// so the user is never dropped onto a black screen with no explanation; a "manual entry"
/// fallback is always available.
struct QRScannerSheet: View {
    var onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var torchOn = false
    @State private var didSucceed = false
    @State private var scanLineDown = false

    /// Brand blue while hunting, success green once a code is read.
    private var reticleColor: Color { didSucceed ? BBColor.success : BBColor.brand }

    /// DEBUG: render the scanner chrome over a plain backdrop so the overlay can be verified
    /// in the Simulator, which has no camera. Never affects release builds or the decode path.
    private var previewMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["BB_SCANNER_PREVIEW"] == "1"
        #else
        false
        #endif
    }

    var body: some View {
        content
            .preferredColorScheme(.dark)
            .background(Color.black.ignoresSafeArea())
    }

    @ViewBuilder private var content: some View {
        if previewMode {
            scanner
        } else {
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
    }

    // MARK: Live scanner

    private var scanner: some View {
        FoldSplitView {
            VStack(spacing: 0) {
                scannerHeader
                ScrollView {
                    VStack(spacing: 24) {
                        instructions
                        manualEntryButton
                    }
                    .padding(24)
                }
            }
        } main: { split in
            ZStack {
                cameraLayer
                if split {
                    reticle
                } else {
                    VStack(spacing: 0) {
                        scannerHeader
                        ScrollView {
                            VStack(spacing: 24) {
                                reticle
                                instructions
                                manualEntryButton
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 24)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var cameraLayer: some View {
        if previewMode {
            Color.black.ignoresSafeArea()
        } else {
            CameraView(torchOn: torchOn, onScan: handleDecode)
                .ignoresSafeArea()
        }
    }

    private var instructions: some View {
        VStack(spacing: 6) {
            Text("Point at the QR code")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Open User → Add a Device on your Baby Buddy site to show your login code.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var reticle: some View {
        ZStack {
            ReticleCorners(cornerLength: 34, radius: 20)
                .stroke(reticleColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .animation(.easeInOut(duration: 0.25), value: didSucceed)

            if didSucceed {
                Image(systemName: "checkmark")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(BBColor.success)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                Rectangle()
                    .fill(BBColor.brand)
                    .frame(height: 2)
                    .padding(.horizontal, 14)
                    .offset(y: scanLineDown ? 92 : -92)
                    .shadow(color: BBColor.brand.opacity(0.8), radius: 6)
            }
        }
        .frame(width: 224, height: 224)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                scanLineDown = true
            }
        }
    }

    // MARK: Scanner controls

    private var scannerHeader: some View {
        HStack(spacing: 12) {
            circleButton(systemImage: "xmark", label: "Close scanner") { dismiss() }
            Text("Scan QR code")
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            circleButton(systemImage: "bolt.fill", label: "Flashlight", isActive: torchOn) { torchOn.toggle() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.black.opacity(0.6))
    }

    private var manualEntryButton: some View {
        Button { dismiss() } label: {
            Label("Enter details manually", systemImage: "keyboard")
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: BBRadius.control))
        }
        .buttonStyle(.plain)
    }

    private func circleButton(systemImage: String, label: LocalizedStringKey, isActive: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.medium))
                .foregroundStyle(isActive ? Color.black : .white)
                .frame(width: 44, height: 44)
                .background(isActive ? AnyShapeStyle(BBColor.brand) : AnyShapeStyle(.white.opacity(0.12)), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(systemImage == "bolt.fill" ? (isActive ? Text("On") : Text("Off")) : Text(""))
    }

    // MARK: Permission denied

    private var deniedView: some View {
        FoldSplitView {
            ScrollView {
                deniedExplanation.padding(24)
            }
        } main: { split in
            ScrollView {
                VStack(spacing: 24) {
                    if !split { deniedExplanation }
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Button("Open Settings") { UIApplication.shared.open(url) }
                            .buttonStyle(.bbPrimary)
                    }
                    manualEntryButton
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }
        }
    }

    private var deniedExplanation: some View {
        VStack(spacing: 16) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: "camera.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text("Camera Access Needed")
                .font(.title2.weight(.semibold))
            Text("Allow camera access in Settings to scan your Baby Buddy login QR code, or enter your server details manually.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    // MARK: Decode → success flash → dismiss

    /// On a successful read, flip the reticle corners to green with a checkmark, then dismiss.
    /// The decode itself (and the success haptic) happens unchanged in ``ScannerViewController``.
    private func handleDecode(_ code: String) {
        guard !didSucceed else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { didSucceed = true }
        torchOn = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            onScan(code)
            dismiss()
        }
    }
}

/// Brand-blue corner brackets for the scanner reticle — strokes only the four rounded corners.
private struct ReticleCorners: Shape {
    var cornerLength: CGFloat = 34
    var radius: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = cornerLength, r = radius

        // Top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + r + l))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r + l, y: rect.minY))

        // Top-right
        p.move(to: CGPoint(x: rect.maxX - r - l, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r + l))

        // Bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - r - l))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX - r - l, y: rect.maxY))

        // Bottom-left
        p.move(to: CGPoint(x: rect.minX + r + l, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r - l))

        return p
    }
}

/// `AVFoundation` capture session that emits the string value of the first QR code it sees.
private struct CameraView: UIViewControllerRepresentable {
    var torchOn: Bool
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {
        controller.onScan = onScan
        controller.setTorch(torchOn)
    }
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.kurtisguy.BabyBuddy.qr-scan")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var device: AVCaptureDevice?
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
        self.device = device
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

    /// Toggle the capture device's torch (no-op when there's no torch, e.g. the Simulator).
    func setTorch(_ on: Bool) {
        guard let device, device.hasTorch else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
            } catch {}
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setTorch(false)
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
