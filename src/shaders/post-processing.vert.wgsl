struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) TexCoord : vec2<f32>,
}

@vertex
fn main(@builtin(vertex_index) VertexIndex : u32) -> VertexOutput {
    // Rendering a full screen quad using one triangle (See https://www.saschawillems.de/blog/2016/08/13/vulkan-tutorial-on-rendering-a-fullscreen-quad-without-buffers/)
    var vertexOutput : VertexOutput;
    vertexOutput.TexCoord = vec2<f32>(f32((VertexIndex << 1) & 2), f32(VertexIndex & 2));
    vertexOutput.Position = vec4<f32>(vertexOutput.TexCoord * 2.0 + -1.0, 0.0, 1.0);
    
    return vertexOutput;
}