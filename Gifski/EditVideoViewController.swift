import Cocoa
import AVKit

final class EditVideoViewController: NSViewController {
	enum PredefinedSizeItem {
		case custom
		case spacer
		case dimensions(ResizableDimensions)

		var resizableDimensions: ResizableDimensions? {
			switch self {
			case let .dimensions(resizableDimensions):
				return resizableDimensions
			default:
				return nil
			}
		}
	}

	@IBOutlet private var estimatedSizeLabel: NSTextField!
	@IBOutlet private var frameRateSlider: NSSlider!
	@IBOutlet private var frameRateLabel: NSTextField!
	@IBOutlet private var qualitySlider: NSSlider!

	@IBOutlet private var widthTextField: IntTextField!
	@IBOutlet private var heightTextField: IntTextField!
	@IBOutlet private var predefinedSizesDropdown: MenuPopUpButton!
	@IBOutlet private var dimensionsTypeDropdown: MenuPopUpButton!
	@IBOutlet private var cancelButton: NSButton!
	@IBOutlet private var playerViewWrapper: NSView!

	var inputUrl: URL!
	var asset: AVURLAsset!
	var videoMetadata: AVURLAsset.VideoMetadata!

	private var estimateWorkItem: DispatchWorkItem?
	private var gifData: Data?
	private var framesWritten: Int64 = 0
	private var dataSize: Int64 = 0

	private var resizableDimensions: ResizableDimensions!
	private var predefinedSizes: [PredefinedSizeItem]!
	private let formatter = ByteCountFormatter()
	private var playerViewController: TrimmingAVPlayerViewController!

	private var timeRange: ClosedRange<Double>? {
		return playerViewController?.timeRange
	}

	private let tooltip = Tooltip(
		identifier: "savePanelArrowKeys",
		text: "Press the arrow up/down keys to change the value by 1. Hold the Option key meanwhile to change it by 10.",
		showOnlyOnce: true,
		maxWidth: 300
	)

	convenience init(inputUrl: URL, asset: AVURLAsset, videoMetadata: AVURLAsset.VideoMetadata) {
		self.init()

		self.inputUrl = inputUrl
		self.asset = asset
		self.videoMetadata = videoMetadata
	}

	@IBAction private func convert(_ sender: Any) {
		let conversion = Gifski.Conversion(
			video: inputUrl,
			timeRange: timeRange,
			quality: defaults[.outputQuality],
			dimensions: resizableDimensions.changed(dimensionsType: .pixels).currentDimensions.value,
			frameRate: frameRateSlider.integerValue
		)

		if let gifData = gifData {
			let convert = ConversionViewController(conversion, gifData)
			push(viewController: convert)
		} else {
			let convert = ConversionViewController(conversion, nil)
			push(viewController: convert)
		}
	}

	@IBAction private func cancel(_ sender: Any) {
		let videoDropController = VideoDropViewController()
		push(viewController: videoDropController)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		formatter.zeroPadsFractionDigits = true
		setUpDimensions()
		setUpDropdowns()
		setUpSliders()
		setUpWidthAndHeightTextFields()
		setUpDropView()
		setUpTrimmingView()
	}

	override func viewDidAppear() {
		super.viewDidAppear()

		dimensionsTypeDropdown.nextKeyView = frameRateSlider
		widthTextField.nextKeyView = heightTextField
		heightTextField.nextKeyView = dimensionsTypeDropdown
		qualitySlider.nextKeyView = cancelButton

		tooltip.show(from: widthTextField, preferredEdge: .maxX)
		predefinedSizesDropdown.focus()
	}

	private func setUpDimensions() {
		let minimumScale: CGFloat = 0.01
		let maximumScale: CGFloat = 1
		let dimensions = Dimensions(type: .pixels, value: videoMetadata.dimensions)

		resizableDimensions = ResizableDimensions(
			dimensions: dimensions,
			minimumScale: minimumScale,
			maximumScale: maximumScale
		)

		var pixelCommonSizes: [CGFloat] = [
			960,
			800,
			640,
			500,
			480,
			320,
			256,
			200,
			160,
			128,
			80,
			64
		]

		if !pixelCommonSizes.contains(dimensions.value.width) {
			pixelCommonSizes.append(dimensions.value.width)
			pixelCommonSizes.sort(by: >)
		}

		let pixelDimensions = pixelCommonSizes.map { width -> CGSize in
			let ratio = width / dimensions.value.width
			let height = dimensions.value.height * ratio
			return CGSize(width: width, height: height)
		}

		let predefinedPixelDimensions = pixelDimensions
			.filter { resizableDimensions.validate(newSize: $0) }
			.map { resizableDimensions.resized(to: $0) }

		let percentCommonSizes: [CGFloat] = [
			50,
			33,
			25,
			20
		]

		let predefinedPercentDimensions = percentCommonSizes
			.map {
				resizableDimensions.changed(dimensionsType: .percent)
					.resized(to: CGSize(width: $0, height: $0))
			}

		predefinedSizes = [.custom]
		predefinedSizes.append(.spacer)
		predefinedSizes.append(contentsOf: predefinedPixelDimensions.map { .dimensions($0) })
		predefinedSizes.append(.spacer)
		predefinedSizes.append(contentsOf: predefinedPercentDimensions.map { .dimensions($0) })
	}

	private func setUpDropdowns() {
		predefinedSizesDropdown.removeAllItems()

		for size in predefinedSizes {
			switch size {
			case .custom:
				predefinedSizesDropdown.addItem(withTitle: "Custom")
			case .spacer:
				predefinedSizesDropdown.menu?.addItem(NSMenuItem.separator())
			case let .dimensions(dimensions):
				predefinedSizesDropdown.addItem(withTitle: "\(dimensions)")
			}
		}

		predefinedSizesDropdown.onMenuWillOpen = { [weak self] in
			self?.predefinedSizesDropdown.item(at: 0)?.title = "Custom"
		}

		predefinedSizesDropdown.onMenuDidClose = { [weak self] selectedIndex in
			guard let self = self else {
				return
			}

			let oldOrNewSelectedIndex = selectedIndex ?? self.predefinedSizesDropdown.indexOfSelectedItem
			if let size = self.predefinedSizes?[safe: oldOrNewSelectedIndex], case .custom = size {
				// We don't care if it's newly selected index or not, if it's custom, set its size
				self.updateSelectedItemAsCustomWithSize()
			} else if let index = selectedIndex, let size = self.predefinedSizes?[safe: index],
				case .dimensions(let dimensions) = size {
				// But we care if it's newly selected index for dimensions, we don't want to recalculate
				// if we don't have to
				self.resizableDimensions.change(dimensionsType: dimensions.currentDimensions.type)
				self.resizableDimensions.resize(to: dimensions.currentDimensions.value)
				self.dimensionsUpdated()
			}
		}

		dimensionsTypeDropdown.removeAllItems()
		dimensionsTypeDropdown.addItems(withTitles: DimensionsType.allCases.map { $0.rawValue })

		dimensionsTypeDropdown.onMenuDidClose = { [weak self] selectedIndex in
			guard
				let self = self,
				let index = selectedIndex,
				let item = self.dimensionsTypeDropdown.item(at: index),
				let dimensionsType = DimensionsType(rawValue: item.title)
			else {
				return
			}

			self.resizableDimensions.change(dimensionsType: dimensionsType)
			self.dimensionsUpdated()
			self.updateTextFieldsMinMax()
		}

		if resizableDimensions.currentDimensions.value.width > 640 {
			predefinedSizesDropdown.selectItem(at: 3)
		} else {
			predefinedSizesDropdown.selectItem(at: 2)
		}

		dimensionsUpdated()
	}

	private func setUpSliders() {
		frameRateSlider.onAction = { [weak self] _ in
			guard let self = self else {
				return
			}

			let frameRate = self.frameRateSlider.integerValue
			self.frameRateLabel.stringValue = "\(frameRate)"
			self.estimateFileSize()
		}

		qualitySlider.onAction = { [weak self] _ in
			guard let self = self else {
				return
			}

			defaults[.outputQuality] = self.qualitySlider.doubleValue
			self.estimateFileSize()
		}

		frameRateSlider.maxValue = videoMetadata.frameRate.clamped(to: 5...30)
		frameRateSlider.doubleValue = defaultFrameRate(inputFrameRate: videoMetadata.frameRate)
		frameRateSlider.triggerAction()

		qualitySlider.doubleValue = defaults[.outputQuality]
		qualitySlider.triggerAction()
	}

	private func setUpWidthAndHeightTextFields() {
		widthTextField.onBlur = { [weak self] width in
			self?.resizableDimensions.resize(usingWidth: CGFloat(width))
			self?.dimensionsUpdated()
		}

		widthTextField.onValueChange = { [weak self] width in
			guard let self = self else {
				return
			}

			self.resizableDimensions.resize(usingWidth: CGFloat(width))
			self.dimensionsUpdated()
		}

		heightTextField.onBlur = { [weak self] height in
			self?.resizableDimensions.resize(usingHeight: CGFloat(height))
			self?.dimensionsUpdated()
		}

		heightTextField.onValueChange = { [weak self] height in
			guard let self = self else {
				return
			}

			self.resizableDimensions.resize(usingHeight: CGFloat(height))
			self.dimensionsUpdated()
		}

		updateTextFieldsMinMax()
	}

	private func setUpDropView() {
		let videoDropController = VideoDropViewController(dropLabelIsHidden: true)
		add(childController: videoDropController)
	}

	private func setUpTrimmingView() {
		playerViewController = TrimmingAVPlayerViewController(asset: asset) { [weak self] _ in
			self?.estimateFileSize()
		}
		add(childController: playerViewController, to: playerViewWrapper)
	}

	private func updateTextFieldsMinMax() {
		let widthMinMax = resizableDimensions.widthMinMax
		let heightMinMax = resizableDimensions.heightMinMax
		widthTextField.minMax = Int(widthMinMax.lowerBound)...Int(widthMinMax.upperBound)
		heightTextField.minMax = Int(heightMinMax.lowerBound)...Int(heightMinMax.upperBound)
	}

	private func dimensionsUpdated() {
		updateDimensionsDisplay()
		estimateFileSize()
		selectPredefinedSizeBasedOnCurrentDimensions()
	}

	private func estimateFileSize() {
		// Cancle old estimate
		estimateWorkItem?.cancel()
		self.gifData = nil
		self.dataSize = 0
		self.framesWritten = 0

		let conversion = Gifski.Conversion(
			video: inputUrl,
			timeRange: timeRange,
			quality: defaults[.outputQuality],
			dimensions: resizableDimensions.changed(dimensionsType: .pixels).currentDimensions.value,
			frameRate: frameRateSlider.integerValue
		)

		let duration: Double = {
			if let timeRange = self.timeRange {
				return timeRange.upperBound - timeRange.lowerBound
			} else {
				return videoMetadata.duration
			}
		}()
		let frameCount = duration * frameRateSlider.doubleValue

		estimatedSizeLabel.textColor = NSColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0)
		estimatedSizeLabel.stringValue = "Starting Estimation..."
		estimateWorkItem = DispatchWorkItem {
			print("Total: \(frameCount)")

			Gifski.setOnNewFrame { framesWritten in
				DispatchQueue.main.sync {
					self.estimatedSizeLabel.textColor = NSColor(red: 0.11, green: 0.37, blue: 0.13, alpha: 1.0)
				}

				if self.dataSize == 0 {
					return
				}

				self.framesWritten = framesWritten
				DispatchQueue.main.sync {
					self.estimatedSizeLabel.stringValue = "Estimated size: " + self.formatter.string(fromByteCount: Int64(self.dataSize * (Int64(frameCount) / Int64(framesWritten))))
				}
			}
			Gifski.setWriteCallback { size in
				self.dataSize += Int64(size)
			}
			Gifski.run(conversion) { result in
				do {
					let data = try result.get()
					self.gifData = data
				} catch {
					self.presentError(error, modalFor: self.view.window)
				}
			}
		}
		guard let workItem = estimateWorkItem else {
			// This should never happen as we define estimateWorkItem above
			return
		}
		DispatchQueue.main.async(execute: workItem)
	}

	private func updateDimensionsDisplay() {
		widthTextField.stringValue = String(format: "%.0f", resizableDimensions.currentDimensions.value.width)
		heightTextField.stringValue = String(format: "%.0f", resizableDimensions.currentDimensions.value.height)
		dimensionsTypeDropdown.selectItem(withTitle: resizableDimensions.currentDimensions.type.rawValue)
	}

	private func selectPredefinedSizeBasedOnCurrentDimensions() {
		// First reset the state
		predefinedSizesDropdown.selectItem(at: NSNotFound)

		// Check if we can select predefined option that has the same dimensions settings
		if let index = predefinedSizes.firstIndex(where: { $0.resizableDimensions?.currentDimensions == resizableDimensions.currentDimensions }) {
			predefinedSizesDropdown.selectItem(at: index)
		} else {
			updateSelectedItemAsCustomWithSize()
		}
	}

	private func updateSelectedItemAsCustomWithSize() {
		let newType: DimensionsType = resizableDimensions.currentDimensions.type == .percent ? .pixels : .percent
		let resizableDimensions = self.resizableDimensions.changed(dimensionsType: newType)
		let selectedCustomTitle = "Custom - \(resizableDimensions.currentDimensions)"
		predefinedSizesDropdown.item(at: 0)?.title = selectedCustomTitle
		predefinedSizesDropdown.selectItem(at: 0)
	}

	private func defaultFrameRate(inputFrameRate frameRate: Double) -> Double {
		let defaultFrameRate = frameRate >= 24 ? frameRate / 2 : frameRate
		return defaultFrameRate.clamped(to: 5...30)
	}
}
