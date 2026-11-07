#!/usr/bin/env swift
import Foundation
import Vision
import ImageIO
import CoreVideo

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func loadImage(_ path: String) -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fail("无法读取图片：\(path)")
    }
    return image
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fail("无法创建输出：\(path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fail("写入失败：\(path)")
    }
}

func median(_ samples: [Int]) -> Int {
    let sorted = samples.sorted()
    let mid = sorted.count / 2
    if sorted.count % 2 == 1 {
        return sorted[mid]
    }
    return (sorted[mid - 1] + sorted[mid]) / 2
}

func smoothAlpha(_ residual: Int, _ low: Int, _ high: Int) -> UInt8 {
    let clamped = min(max(Double(residual - low) / Double(high - low), 0), 1)
    let eased = clamped * clamped * (3 - 2 * clamped)
    return UInt8((eased * 255).rounded())
}

func foregroundMask(for image: CGImage) -> (UnsafeMutablePointer<UInt8>, Int) {
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
        try handler.perform([request])
    } catch {
        fail("前景分割失败：\(error)")
    }
    guard let observation = request.results?.first as? VNInstanceMaskObservation else {
        fail("没有生成前景掩码")
    }

    let buffer: CVPixelBuffer
    do {
        buffer = try observation.generateScaledMaskForImage(
            forInstances: observation.allInstances,
            from: handler
        )
    } catch {
        fail("生成原尺寸掩码失败：\(error)")
    }

    let format = CVPixelBufferGetPixelFormatType(buffer)
    guard format == kCVPixelFormatType_OneComponent32Float else {
        fail("意外的掩码格式：\(format)")
    }

    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else {
        fail("掩码缓冲不可读")
    }
    let maskWidth = CVPixelBufferGetWidth(buffer)
    let maskHeight = CVPixelBufferGetHeight(buffer)
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    guard maskWidth == image.width && maskHeight == image.height else {
        fail("掩码尺寸与图片不一致：\(maskWidth)x\(maskHeight)")
    }
    let stride = rowBytes / MemoryLayout<Float>.size
    let floats = base.assumingMemoryBound(to: Float.self)
    let copy = UnsafeMutablePointer<UInt8>.allocate(capacity: maskWidth * maskHeight)
    for y in 0..<maskHeight {
        for x in 0..<maskWidth {
            let value = floats[y * stride + x]
            let clamped = min(max(value, 0), 1)
            copy[y * maskWidth + x] = UInt8((clamped * 255).rounded())
        }
    }
    return (copy, maskWidth)
}

func rgbBuffer(for image: CGImage) -> (UnsafeMutablePointer<UInt8>, Int) {
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    let capacity = bytesPerRow * height
    let data = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
    guard let context = CGContext(
        data: data,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fail("无法创建 RGB 上下文")
    }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (data, bytesPerRow)
}

func compose(input: String, output: String) {
    let image = loadImage(input)
    let width = image.width
    let height = image.height
    let (mask, maskRow) = foregroundMask(for: image)
    defer { mask.deallocate() }

    let (rgb, rgbRow) = rgbBuffer(for: image)
    defer { rgb.deallocate() }

    let out = UnsafeMutablePointer<UInt8>.allocate(capacity: rgbRow * height)

    for y in 0..<height {
        var reds = [Int]()
        var greens = [Int]()
        var blues = [Int]()
        for x in [0, 1, 2, max(0, width - 3), max(0, width - 2), max(0, width - 1)] {
            let offset = y * rgbRow + x * 4
            reds.append(Int(rgb[offset]))
            greens.append(Int(rgb[offset + 1]))
            blues.append(Int(rgb[offset + 2]))
        }
        let backgroundRed = median(reds)
        let backgroundGreen = median(greens)
        let backgroundBlue = median(blues)

        for x in 0..<width {
            let source = y * rgbRow + x * 4
            let target = source
            let red = Int(rgb[source])
            let green = Int(rgb[source + 1])
            let blue = Int(rgb[source + 2])
            let residual = max(
                abs(red - backgroundRed),
                max(abs(green - backgroundGreen), abs(blue - backgroundBlue))
            )
            let difference = smoothAlpha(residual, 18, 34)
            let vision = Int(mask[y * maskRow + x])
            let alpha = max(vision, Int(difference))

            out[target] = UInt8(red * alpha / 255)
            out[target + 1] = UInt8(green * alpha / 255)
            out[target + 2] = UInt8(blue * alpha / 255)
            out[target + 3] = UInt8(alpha)
        }
    }

    guard let context = CGContext(
        data: out,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: rgbRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fail("无法创建输出上下文")
    }
    guard let result = context.makeImage() else {
        fail("输出图像生成失败")
    }
    writePNG(result, to: output)
    out.deallocate()
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fail("用法：swift tools/cutout.swift <输入图片> <输出图片>")
}

compose(input: arguments[1], output: arguments[2])
print("完成 \(arguments[2])")
