import Cocoa

final class DraggableFile: NSImageView, NSDraggingSource {
	var mouseDownEvent: NSEvent?

	var fileUrl: URL? {
		didSet {
			if let url = fileUrl {
				image = NSWorkspace.shared.icon(forFile: url.path)
			}
		}
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		isEditable = false
		
		unregisterDraggedTypes()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
	}

	func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
		return .copy
	}

	override func mouseDown(with theEvent: NSEvent) {
		mouseDownEvent = theEvent
	}

	override func mouseDragged(with event: NSEvent) {
		let mouseDown = mouseDownEvent!.locationInWindow
		let dragPoint = event.locationInWindow
		let dragDistance = hypot(mouseDown.x - dragPoint.x, mouseDown.y - dragPoint.y)

		if dragDistance < 3 {
			return
		}

		guard let image = self.image else {
			return
		}

		let draggingItem = NSDraggingItem(pasteboardWriter: fileUrl! as NSURL)
		let draggingFrameOrigin = convert(mouseDown, from: nil)
		let draggingFrame = NSRect(origin: draggingFrameOrigin, size: image.size).offsetBy(dx: -image.size.width / 2, dy: -image.size.height / 2)
		
		draggingItem.draggingFrame = draggingFrame
		
		draggingItem.imageComponentsProvider = {
			let component = NSDraggingImageComponent(key: NSDraggingItem.ImageComponentKey.icon)
			
			component.contents = image
			component.frame = NSRect(origin: NSPoint(), size: draggingFrame.size)
			return [component]
		}
		
		beginDraggingSession(with: [draggingItem], event: mouseDownEvent!, source: self)
	}
}
