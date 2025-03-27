//
//  ContentView.swift
//  ImageEditingIOS
//
//  Created by Fachri Febrian on 27/03/2025.
//

import SwiftUI
import MetalKit

class ImageEditorViewModel: ObservableObject {
    @Published var originalImage: UIImage?
    @Published var processedImage: UIImage?
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    
    init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        
        let library = device.makeDefaultLibrary()!
        let kernelFunction = library.makeFunction(name: "image_processing_kernel")!
        self.pipelineState = try! device.makeComputePipelineState(function: kernelFunction)
    }
    
    func applyFilter(brightness: Float, contrast: Float, saturation: Float) {
        guard let image = originalImage, let cgImage = image.cgImage else { return }
        
        let textureLoader = MTKTextureLoader(device: device)
        guard let inputTexture = try? textureLoader.newTexture(cgImage: cgImage, options: nil) else { return }
        
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: inputTexture.width,
            height: inputTexture.height,
            mipmapped: false
        )
        outputDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let outputTexture = device.makeTexture(descriptor: outputDescriptor),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setTexture(inputTexture, index: 0)
        commandEncoder.setTexture(outputTexture, index: 1)
        
        var parameters = SIMD3<Float>(brightness, contrast, saturation)
        commandEncoder.setBytes(&parameters, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
        
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (inputTexture.width + 15) / 16,
            height: (inputTexture.height + 15) / 16,
            depth: 1
        )
        
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        commandEncoder.endEncoding()
        
        commandBuffer.addCompletedHandler {[weak self] _ in
            DispatchQueue.main.async { [weak self]  in
                self?.processedImage = self?.textureToUIImage(texture: outputTexture)
            }
        }
        
        commandBuffer.commit()
    }
    
    private func textureToUIImage(texture: MTLTexture) -> UIImage? {
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let totalBytes = bytesPerRow * height
        
        var rawData = [UInt8](repeating: 0, count: totalBytes)
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(&rawData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )
        
        guard let cgImage = context?.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    func resetFilter() {
        processedImage = originalImage
    }
}

// SwiftUI View
struct ContentView: View {
    @StateObject private var viewModel = ImageEditorViewModel()
    @State private var showImagePicker = false
    @State private var brightness: Float = 0.0
    @State private var contrast: Float = 1.0
    @State private var saturation: Float = 1.0
    
    var body: some View {
        VStack {
            if let image = viewModel.processedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text("Select an image to edit")
                    .foregroundColor(.gray)
            }
            
            VStack {
                VStack {
                    Text("Brightness: \(brightness, specifier: "%.2f")")
                    Slider(value: $brightness, in: -1...1)
                        .onChange(of: brightness) { _ in applyFilters() }
                    
                }
                VStack {
                    Text("Contrast: \(contrast, specifier: "%.2f")")
                    Slider(value: $contrast, in: 0.5...2)
                        .onChange(of: contrast) { _ in applyFilters() }
                    
                }
                VStack {
                    Text("Saturation: \(saturation, specifier: "%.2f")")
                    Slider(value: $saturation, in: 0...2)
                        .onChange(of: saturation) { _ in applyFilters() }
                    
                }
            }
            .padding()
            
            HStack {
                Button("Choose Image") {
                    showImagePicker = true
                }
                .padding()
                
                Button("Reset Filters") {
                    resetFilters()
                }
                .padding()
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $viewModel.originalImage)
        }
        .onChange(of: viewModel.originalImage) { _ in applyFilters() }
    }
    
    func applyFilters() {
        viewModel.applyFilter(
            brightness: brightness,
            contrast: contrast,
            saturation: saturation
        )
    }
    
    func resetFilters() {
        brightness = 0.0
        contrast = 1.0
        saturation = 1.0
        viewModel.resetFilter()
    }
}

// Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) private var presentationMode
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: ImagePicker
        
        init(parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let selectedImage = info[.originalImage] as? UIImage {
                parent.image = selectedImage
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}

#Preview {
    ContentView()
}
