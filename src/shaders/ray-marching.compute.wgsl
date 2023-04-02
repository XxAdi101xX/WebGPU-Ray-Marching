@group(0) @binding(0)
var output_buffer: texture_storage_2d<rgba8unorm, write>;

@group(0) @binding(1)
var<uniform> application_data: ApplicationData;

@group(1) @binding(0)
var<storage, read> objects: ObjectData;

// CPU/GPU structs
struct Sphere {
    center: vec3<f32>,
    radius: f32,
    color: vec3<f32>,
    padding: f32
}

struct ApplicationData {
    camera_position: vec3<f32>,
    padding1: f32,
    camera_forward: vec3<f32>,
    padding2: f32,
    camera_right: vec3<f32>,
    padding3: f32,
    camera_up: vec3<f32>,
    sphere_count: f32,
}

struct ObjectData {
    spheres: array<Sphere>,
}

// GPU only struct
struct Ray {
    direction: vec3<f32>,
    padding1: f32,
    origin: vec3<f32>,
    padding2: f32
}

const epsilon: f32 = 0.01;
const max_distance: f32 = 9999.0;
const max_steps: u32 = 32;

// Methods
@compute @workgroup_size(64,1,1)
fn main(@builtin(global_invocation_id) GlobalInvocationID : vec3<u32>) {
    let screen_size: vec2<u32> = textureDimensions(output_buffer);
    let screen_pos : vec2<i32> = vec2<i32>(i32(GlobalInvocationID.x), i32(GlobalInvocationID.y));
    let horizontal_coefficient: f32 = (f32(screen_pos.x) - f32(screen_size.x) / 2) / f32(screen_size.x);
    let vertical_coefficient: f32 = (f32(screen_pos.y) - f32(screen_size.y) / 2) / f32(screen_size.x);

    var ray: Ray;
    ray.direction = normalize(application_data.camera_forward + horizontal_coefficient * application_data.camera_right + vertical_coefficient * application_data.camera_up);
    ray.origin = application_data.camera_position;

    let pixel_color : vec3<f32> = ray_march(&ray);

    textureStore(output_buffer, screen_pos, vec4<f32>(pixel_color, 1.0));
}

fn ray_march(ray: ptr<function,Ray>) -> vec3<f32> {
    var color: vec3<f32> = vec3(0.0, 0.0, 0.0);
    var total_distance_marched: f32 = 0.0;

    for (var step: u32 = 0; step < max_steps; step++) {
        var i: i32 = 0;
        var distance_marched: f32 = closest_distance_in_scene((*ray).origin + (*ray).direction * total_distance_marched, (*ray).direction, &i);
        
        if (distance_marched < epsilon) {
            color = objects.spheres[i].color;
            break; 
        }
        
        if (total_distance_marched > max_distance) {
            break;
        }
        total_distance_marched += distance_marched;
    }

    return color;
}

fn closest_distance_in_scene(
    marched_position: vec3<f32>,  // Position along ray marched so far
    ray_direction: vec3<f32>, 
    closest_sphere_index: ptr<function,i32>
) -> f32 {
    var closest_distance: f32 = 9999.0;
    for (var i: i32 = 0; i < i32(application_data.sphere_count); i++) {

        var distance: f32 = signed_dst_to_sphere(marched_position, ray_direction, i);
        
        if (distance < closest_distance) {
            closest_distance = distance;
            *closest_sphere_index = i;
        }
    }

    return closest_distance;
}

fn calculate_normal(
    marched_position: vec3<f32>,
    ray_direction: vec3<f32>, 
    closest_sphere_index: ptr<function,i32>
) -> vec3<f32> {
    const small_step: vec3<f32> = vec3(0.001, 0.0, 0.0);

    let gradient_x: f32 = closest_distance_in_scene(marched_position + small_step.xyy, ray_direction, closest_sphere_index) - closest_distance_in_scene(marched_position - small_step.xyy, ray_direction, closest_sphere_index);
    let gradient_y: f32 = closest_distance_in_scene(marched_position + small_step.yxy, ray_direction, closest_sphere_index) - closest_distance_in_scene(marched_position - small_step.yxy, ray_direction, closest_sphere_index);
    let gradient_z: f32 = closest_distance_in_scene(marched_position + small_step.yyx, ray_direction, closest_sphere_index) - closest_distance_in_scene(marched_position - small_step.yyx, ray_direction, closest_sphere_index);

    let normal: vec3<f32> = vec3(gradient_x, gradient_y, gradient_z);

    return normalize(normal);
}

fn signed_dst_to_sphere(
    marched_position: vec3<f32>,
    ray_direction: vec3<f32>,
    sphere_index: i32
) -> f32 {
    let ray_to_sphere: vec3<f32> = objects.spheres[sphere_index].center - marched_position;

    // Ignore spheres behind the current marched position
    if (dot(ray_to_sphere, ray_direction) < 0) {
        return 9999.0;
    }
    
    return length(ray_to_sphere) - objects.spheres[sphere_index].radius;
}