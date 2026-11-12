import FirebaseCore
import FirebaseMessaging
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Same channel name as Android's `MainActivity.kt` and Dart's
  /// `ScreenSecurityService`.
  private var screenSecurityChannel: FlutterMethodChannel?

  /// Opaque black window above everything (alerts, the video surface, any
  /// native view) while the screen is recorded / mirrored / AirPlayed.
  private var captureShieldWindow: UIWindow?

  /// Makes protected screens render black in screenshots / recordings.
  private let screenProtector = ScreenProtector()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Dart also calls `Firebase.initializeApp()`; FlutterFire reuses the
    // default app configured here (from GoogleService-Info.plist).
    // Without the plist in the bundle `configure()` raises an uncaught
    // NSException (instant launch crash) — skip Firebase instead.
    if FirebaseApp.app() == nil {
      if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
        FirebaseApp.configure()
      } else {
        NSLog("[Firebase] GoogleService-Info.plist missing — push disabled")
      }
    }
    // Lets firebase_messaging / flutter_local_notifications present
    // notifications while the app is in the foreground and handle taps.
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    GeneratedPluginRegistrant.register(with: self)
    setUpScreenSecurity()
    setUpStorage()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Hands the APNs token to FCM (needed for an FCM token on iOS), then lets
  /// the plugins see it too.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    if FirebaseApp.app() != nil {
      Messaging.messaging().apnsToken = deviceToken
    }
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  /// iOS can't block screenshots the way Android's FLAG_SECURE does, so the
  /// app detects capture instead: screen recording / mirroring
  /// (`UIScreen.isCaptured`) and screenshots, reported to Dart, which covers
  /// protected content and warns the student.
  private func setUpScreenSecurity() {
    // Through the plugin registrar rather than `window.rootViewController`,
    // which isn't guaranteed to be a FlutterViewController this early.
    guard let registrar = self.registrar(forPlugin: "ScreenSecurity") else { return }
    let channel = FlutterMethodChannel(
      name: "com.itaaleem.app/screen_security",
      binaryMessenger: registrar.messenger()
    )
    screenSecurityChannel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "isCaptured":
        result(UIScreen.main.isCaptured)
      case "enableSecure", "protectOn":
        self?.screenProtector.protectOn(controller: self?.flutterViewController())
        result(nil)
      case "setShieldEnabled":
        self?.screenProtector.isEnabled = (call.arguments as? Bool) ?? false
        result(nil)
      case "disableSecure", "protectOff":
        self?.screenProtector.protectOff()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    NotificationCenter.default.addObserver(
      forName: UIApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.screenProtector.protectOff()
    }

    NotificationCenter.default.addObserver(
      forName: UIScreen.capturedDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.captureStateChanged()
    }

    // Recording can start/stop while the app is backgrounded — re-check on
    // the way back (and on launch) so the shield is never stale.
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.captureStateChanged()
    }
    DispatchQueue.main.async { [weak self] in
      self?.captureStateChanged()
    }

    NotificationCenter.default.addObserver(
      forName: UIApplication.userDidTakeScreenshotNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.screenSecurityChannel?.invokeMethod("onScreenshot", arguments: nil)
    }
  }

  /// `excludeFromBackup(path)`: the downloaded lessons stay on this device
  /// only — never in iCloud / iTunes backups (Android: data_extraction_rules).
  private func setUpStorage() {
    guard let registrar = self.registrar(forPlugin: "Storage") else { return }
    let channel = FlutterMethodChannel(
      name: "com.itaaleem.app/storage",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup", let path = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      var url = URL(fileURLWithPath: path, isDirectory: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      do {
        try url.setResourceValues(values)
        result(true)
      } catch {
        result(FlutterError(code: "exclude_failed", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func flutterViewController() -> FlutterViewController? {
    if let vc = window?.rootViewController as? FlutterViewController { return vc }
    return UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .compactMap { $0.rootViewController as? FlutterViewController }
      .first
  }

  private func captureStateChanged() {
    let captured = UIScreen.main.isCaptured
    if captured {
      showCaptureShield()
    } else {
      hideCaptureShield()
    }
    screenSecurityChannel?.invokeMethod("onCaptureChanged", arguments: captured)
  }

  private func showCaptureShield() {
    if captureShieldWindow != nil { return }
    let shield: UIWindow
    if let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive })
      ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
      shield = UIWindow(windowScene: scene)
    } else {
      shield = UIWindow(frame: UIScreen.main.bounds)
    }
    shield.windowLevel = UIWindow.Level.alert + 1
    shield.backgroundColor = .black
    shield.rootViewController = CaptureShieldViewController()
    shield.isHidden = false
    captureShieldWindow = shield
  }

  private func hideCaptureShield() {
    captureShieldWindow?.isHidden = true
    captureShieldWindow = nil
  }
}

/// Hides the Flutter UI from screenshots, screen recordings and AirPlay with
/// the secure-text-field canvas: the private canvas view that a
/// `UITextField(isSecureTextEntry: true)` draws into is rendered black in any
/// capture but normally on the device's own screen.
///
/// The canvas is taken out of its text field and used as a standalone
/// container that becomes the FlutterViewController's root view, with the
/// FlutterView inside it. Nothing that contains the container (window,
/// window layer, transition views) is ever moved into it, so the hierarchy
/// can't form a cycle (the build 41 crash). Off by default; only runs while
/// the server flag `ios_screenshot_shield` is true. Any failed step leaves
/// the hierarchy untouched (detection-only behaviour, as in build 39).
final class ScreenProtector {
  /// Mirrors `ios_screenshot_shield`; false until Dart says otherwise.
  var isEnabled = false {
    didSet { if !isEnabled { protectOff() } }
  }

  private var field: UITextField?
  private var container: UIView?
  private weak var controller: UIViewController?
  private weak var flutterView: UIView?
  private var savedFrame: CGRect = .zero
  private var savedMask: UIView.AutoresizingMask = []

  var isActive: Bool { container != nil }

  func protectOn(controller: UIViewController?) {
    guard isEnabled, !isActive else { return }
    guard let controller = controller,
          let flutterView = controller.viewIfLoaded,
          let host = flutterView.superview else {
      NSLog("[ScreenProtector] no FlutterViewController view in a window — skipped")
      return
    }

    let field = UITextField()
    field.isSecureTextEntry = true
    field.isUserInteractionEnabled = false
    field.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    field.layoutIfNeeded()
    guard let canvas = Self.findCanvas(in: field) else {
      NSLog("[ScreenProtector] secure canvas view not found on iOS \(UIDevice.current.systemVersion) — protection off")
      return
    }

    canvas.removeFromSuperview()
    canvas.subviews.forEach { $0.removeFromSuperview() }
    canvas.transform = .identity
    canvas.layer.transform = CATransform3DIdentity
    canvas.isUserInteractionEnabled = true
    canvas.backgroundColor = .clear
    canvas.clipsToBounds = false
    canvas.frame = flutterView.frame
    canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    savedFrame = flutterView.frame
    savedMask = flutterView.autoresizingMask
    let index = host.subviews.firstIndex(of: flutterView) ?? host.subviews.count

    host.insertSubview(canvas, at: index)
    canvas.addSubview(flutterView)
    flutterView.transform = .identity
    flutterView.frame = canvas.bounds
    flutterView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    controller.view = canvas

    self.field = field
    self.container = canvas
    self.controller = controller
    self.flutterView = flutterView

    guard Self.isAcyclic(canvas), flutterView.superview === canvas else {
      assertionFailure("[ScreenProtector] view hierarchy cycle")
      NSLog("[ScreenProtector] hierarchy check failed — rolling back")
      protectOff()
      return
    }
    canvas.setNeedsLayout()
  }

  /// Puts the FlutterView back exactly where it was. Safe to call any time.
  func protectOff() {
    guard let container = container else { return }
    if let flutterView = flutterView {
      if let host = container.superview {
        let index = host.subviews.firstIndex(of: container) ?? host.subviews.count
        host.insertSubview(flutterView, at: index)
      } else {
        flutterView.removeFromSuperview()
      }
      flutterView.autoresizingMask = savedMask
      flutterView.frame = container.superview != nil ? container.frame : savedFrame
      controller?.view = flutterView
      flutterView.setNeedsLayout()
    }
    container.removeFromSuperview()
    self.container = nil
    self.field = nil
    self.controller = nil
    self.flutterView = nil
  }

  /// The private canvas class: `_UITextLayoutCanvasView` (iOS 15+) or
  /// `_UITextFieldCanvasView` (older). Matched by name, never by index.
  private static func findCanvas(in root: UIView, depth: Int = 0) -> UIView? {
    for sub in root.subviews {
      let name = NSStringFromClass(type(of: sub))
      if name.contains("CanvasView") || name.contains("LayoutCanvas") { return sub }
      if depth < 3, let found = findCanvas(in: sub, depth: depth + 1) { return found }
    }
    return nil
  }

  /// No view may be its own ancestor.
  private static func isAcyclic(_ view: UIView) -> Bool {
    var seen = Set<ObjectIdentifier>()
    var current: UIView? = view
    while let v = current {
      if !seen.insert(ObjectIdentifier(v)).inserted { return false }
      current = v.superview
    }
    return true
  }
}

/// The black screen with the notice, centered, in white.
private final class CaptureShieldViewController: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black

    let icon = UIImageView(image: UIImage(systemName: "lock.fill"))
    icon.tintColor = .white
    icon.contentMode = .scaleAspectFit
    icon.translatesAutoresizingMaskIntoConstraints = false

    let title = UILabel()
    title.text = "تسجيل الشاشة غير مسموح"
    title.font = UIFont(name: "Cairo-Bold", size: 22) ?? .boldSystemFont(ofSize: 22)
    title.textColor = .white
    title.textAlignment = .center
    title.numberOfLines = 0

    let subtitle = UILabel()
    subtitle.text = "يرجى إيقاف التسجيل للمتابعة"
    subtitle.font = UIFont(name: "Cairo-Regular", size: 16) ?? .systemFont(ofSize: 16)
    subtitle.textColor = UIColor.white.withAlphaComponent(0.75)
    subtitle.textAlignment = .center
    subtitle.numberOfLines = 0

    let stack = UIStackView(arrangedSubviews: [icon, title, subtitle])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)

    NSLayoutConstraint.activate([
      icon.widthAnchor.constraint(equalToConstant: 72),
      icon.heightAnchor.constraint(equalToConstant: 72),
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
    ])
  }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
  override var prefersStatusBarHidden: Bool { true }
}
