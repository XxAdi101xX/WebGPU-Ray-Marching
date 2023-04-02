@group(0) @binding(0) var screen_sampler : sampler;
@group(0) @binding(1) var color_buffer : texture_2d<f32>;

@fragment
fn main(@location(0) TexCoord : vec2<f32>) -> @location(0) vec4<f32> {
  // Currently, this process processing fragment shader does not do anything more than sample the colour buffer at the fragment location
  return textureSample(color_buffer, screen_sampler, TexCoord);
}