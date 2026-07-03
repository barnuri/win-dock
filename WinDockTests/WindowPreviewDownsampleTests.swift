import XCTest
import CoreGraphics
@testable import WinDock

@MainActor
final class WindowPreviewDownsampleTests: XCTestCase {

    private func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    func testWideImageIsDownsampledPreservingAspectRatio() {
        let image = makeImage(width: 2200, height: 1100)

        let result = WindowPreviewView.downsampled(image)

        XCTAssertEqual(result.width, WindowPreviewView.maxPreviewPixelWidth)
        XCTAssertEqual(result.height, 220)
    }

    func testSmallImageIsReturnedUnchanged() {
        let image = makeImage(width: 400, height: 300)

        let result = WindowPreviewView.downsampled(image)

        XCTAssertTrue(result === image, "Images at or under the max width must pass through untouched")
    }

    func testExactMaxWidthIsReturnedUnchanged() {
        let image = makeImage(width: WindowPreviewView.maxPreviewPixelWidth, height: 300)

        let result = WindowPreviewView.downsampled(image)

        XCTAssertTrue(result === image)
    }
}
