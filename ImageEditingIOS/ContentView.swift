//
//  ContentView.swift
//  ImageEditingIOS
//
//  Created by Fachri Febrian on 27/03/2025.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import MetalKit

class ImageEditorViewModel: ObservableObject {
    @Published var originalImage: UIImage?
    @Published var processedImage: UIImage?
    private let context = CIContext(options: [CIContextOption.useSoftwareRenderer: false])
    private let device = MTLCreateSystemDefaultDevice()!
    private let commandQueue: MTLCommandQueue
    private let filter = CIFilter.colorControls()
    
    init() {
        self.commandQueue = device.makeCommandQueue()!
    }
    
    
    func applyFilter(brightness: Float, contrast: Float, saturation: Float) {
        guard let image = originalImage, let cgImage = image.cgImage else { return }
        
        let ciImage = CIImage(cgImage: cgImage)
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(brightness, forKey: kCIInputBrightnessKey)
        filter.setValue(contrast, forKey: kCIInputContrastKey)
        filter.setValue(saturation, forKey: kCIInputSaturationKey)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if let outputImage = self.filter.outputImage {
                let commandBuffer = self.commandQueue.makeCommandBuffer()
                
                // Convert CIImage to Metal texture
                let texture = self.createMetalTexture(from: outputImage)
                
                // Process with Metal (optional custom shader)
                if let commandBuffer = commandBuffer {
                    commandBuffer.commit()
                    commandBuffer.waitUntilCompleted()
                }
                
                if let cgImageResult = self.context.createCGImage(outputImage, from: outputImage.extent) {
                    let newImage = UIImage(cgImage: cgImageResult)
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.processedImage = newImage
                    }
                }
            }
        }
    }
    
    private func createMetalTexture(from ciImage: CIImage) -> MTLTexture? {
        let ciContext = CIContext(mtlDevice: device)
        let width = Int(ciImage.extent.width)
        let height = Int(ciImage.extent.height)
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else { return nil }
        
        ciContext.render(ciImage, to: texture, commandBuffer: nil, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
        
        return texture
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
                        .onChange(of: brightness) { _ in applyFilters() }
                    
                }
                VStack {
                    Text("Saturation: \(saturation, specifier: "%.2f")")
                    Slider(value: $saturation, in: 0...2)
                        .onChange(of: brightness) { _ in applyFilters() }
                    
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
