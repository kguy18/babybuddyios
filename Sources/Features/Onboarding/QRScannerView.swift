import SwiftUI
import AVFoundation
import UIKit

/// Full-bleed camera QR scanner presented as a sheet during onboarding. Reports the first
/// decoded QR string via ``onScan`` and dismisses itself. The scanner keeps its own dark
/// treatment regardless of the system appearance. Camera-permission states are handled inline
/// so the user is never dropped onto a black screen with no explanation; a "manual entry"
/// fallback is always visible.
struct QRScannerSheet: View {
    var onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss
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
        ZStack {
            cameraLayer
            reticleBlock
            chrome
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

    /// Reticle + helper copy, centered as a block slightly above true center.
    private var reticleBlock: some View {
        VStack(spacing: 30) {
            reticle
            VStack(spacing: 6) {
                Text("Point at the QR code")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Open User → Add a Device on your Baby Buddy site to show your login code.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
        }
        .offset(y: -24)
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
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                scanLineDown = true
            }
        }
    }

    // MARK: Chrome (top bar + manual-entry fallback)

    private var chrome: some View {
        VStack {
            HStack {
                circleButton(systemImage: "xmark") { dismiss() }
                Spacer()
                Text("Scan QR code")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                circleButton(systemImage: "bolt.fill", isActive: torchOn) { torchOn.toggle() }
            }
            Spacer()
            Button { dismiss() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard")
                    Text("Enter details manually")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func circleButton(systemImage: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(isActive ? Color.black : .white)
                .frame(width: 38, height: 38)
                .background(isActive ? AnyShapeStyle(BBColor.brand) : AnyShapeStyle(.white.opacity(0.12)), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Permission denied

    private var deniedView: some View {
        ContentUnavailableView {
            Label("Camera Access Needed", systemImage: "camera.fill")
        } description: {
            Text("Allow camera access in Settings to scan your Baby Buddy login QR code, or enter your server details manually.")
        } actions: {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(url) }
                    .buttonStyle(.borderedProminent)
                    .tint(BBColor.primary)
            }
            Button("Enter details manually") { dismiss() }
                .foregroundStyle(BBColor.brandAccent)
        }
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
