import Cocoa

final class DraggableFile: NSImageView {
	private var mouseDownEvent: NSEvent!

	var fileUrl: URL! {
		didSet {
			image = NSImage(byReferencing: fileUrl)
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		isEditable = false
		unregisterDraggedTypes()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func mouseDown(with event: NSEvent) {
		mouseDownEvent = event
	}

	override func mouseDragged(with event: NSEvent) {
		let mouseDownPoint = mouseDownEvent.locationInWindow

		guard let image = self.image else {
			return
		}

		let size = CGSize(width: 96, height: 96 * (image.size.height / image.size.width))

		let draggingItem = NSDraggingItem(pasteboardWriter: fileUrl as NSURL)
		let draggingFrameOrigin = convert(mouseDownPoint, from: nil)
		let draggingImage = image.resizing(to: size)
		let draggingFrame = CGRect(origin: draggingFrameOrigin, size: draggingImage.size)
			.offsetBy(dx: -draggingImage.size.width / 2, dy: -draggingImage.size.height / 2)

		draggingItem.draggingFrame = draggingFrame

		draggingItem.imageComponentsProvider = {
			let component = NSDraggingImageComponent(key: .icon)
			component.contents = image
			component.frame = CGRect(origin: .zero, size: draggingFrame.size)
			return [component]
		}

		beginDraggingSession(with: [draggingItem], event: mouseDownEvent, source: self)
	}
}

extension DraggableFile: NSDraggingSource {
	func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
		return .copy
	}
}
