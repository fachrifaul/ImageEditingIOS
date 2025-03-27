//
//  image_processing_kernel.metal
//  ImageEditingIOS
//
//  Created by Fachri Febrian on 27/03/2025.
//

#include <metal_stdlib>
using namespace metal;

kernel void image_processing_kernel(texture2d<float, access::read> inputTexture [[ texture(0) ]],
                                    texture2d<float, access::write> outputTexture [[ texture(1) ]],
                                    constant float3 &params [[ buffer(0) ]],
                                    uint2 gid [[ thread_position_in_grid ]]) {
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) return;
    
    float4 color = inputTexture.read(gid);
    
    // Apply brightness
    color.rgb += params.x;
    
    // Apply contrast
    color.rgb = ((color.rgb - 0.5) * params.y) + 0.5;
    
    // Apply saturation
    float luminance = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    color.rgb = mix(float3(luminance), color.rgb, params.z);
    
    outputTexture.write(color, gid);
}


