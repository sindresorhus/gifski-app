import Cocoa
import UserNotifications
import Fabric
import Crashlytics

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
	lazy var mainWindowController = MainWindowController()

	private var finishedLaunchingCompletions: [() -> Void] = []

	// Possible workaround for crashing bug because of Crashlytics swizzling.
	var notificationCenter: AnyObject? = {
		if #available(macOS 10.14, *) {
			return UNUserNotificationCenter.current()
		} else {
			return nil
		}
	}()

	func applicationWillFinishLaunching(_ notification: Notification) {
		UserDefaults.standard.register(defaults: [
			"NSApplicationCrashOnExceptions": true,
			"NSFullScreenMenuItemEverywhere": false
		])
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		if #available(macOS 10.14, *) {
			(notificationCenter as? UNUserNotificationCenter)?.requestAuthorization { _, _ in }
		}

		#if !DEBUG
			Fabric.with([Crashlytics.self])
		#endif

		mainWindowController.showWindow(self)

		NSApp.isAutomaticCustomizeTouchBarMenuItemEnabled = true
		NSApp.servicesProvider = self

		// Start conversion if there is already a url
		runFinishedLaunchingCompletions()
	}

	/// Returns `nil` if it should not continue.
	func extractSharedVideoUrlIfAny(from url: URL) -> URL? {
		guard url.host == "shareExtension" else {
			return url
		}

		guard
			let path = url.queryDictionary["path"],
			let appGroupShareVideoUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Shared.videoShareGroupIdentifier)?.appendingPathComponent(path)
		else {
			NSAlert.showModal(
				for: mainWindowController.window,
				message: "Could not retrieve the shared video."
			)
			return nil
		}

		return appGroupShareVideoUrl
	}

	func application(_ application: NSApplication, open urls: [URL]) {
		guard
			urls.count == 1,
			let videoUrl = urls.first
		else {
			NSAlert.showModal(
				for: mainWindowController.window,
				message: "Gifski can only convert a single file at the time."
			)
			return
		}

		guard let videoUrl2 = extractSharedVideoUrlIfAny(from: videoUrl) else {
			return
		}

		// Start video conversion on launch
		onFinishedLaunching { [weak self] in
			self?.mainWindowController.convert(videoUrl2)
		}
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		if mainWindowController.isConverting {
			let response = NSAlert.showModal(
				for: mainWindowController.window,
				message: "Do you want to continue converting?",
				informativeText: "Gifski is currently converting a video. If you quit, the conversion will be cancelled.",
				buttonTitles: [
					"Continue",
					"Quit"
				]
			)

			if response == .alertFirstButtonReturn {
				return .terminateCancel
			}
		}

		return .terminateNow
	}

	func application(_ application: NSApplication, willPresentError error: Error) -> Error {
		Crashlytics.recordNonFatalError(error: error)
		return error
	}

	private func runFinishedLaunchingCompletions() {
		for completion in finishedLaunchingCompletions {
			completion()
		}
	}

	private func onFinishedLaunching(_ completion: @escaping () -> Void) {
		finishedLaunchingCompletions.append(completion)
	}
}

extension AppDelegate {
	/// This is called from NSApp as a service resolver
	@objc
	func convertToGif(_ pasteboard: NSPasteboard, userData: String, error: NSErrorPointer) {
		guard let url = pasteboard.fileURLs().first else {
			return
		}

		mainWindowController.convert(url)
	}
}
