@group(0) @binding(0)
var color_buffer: texture_storage_2d<rgba8unorm, write>;

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
    cameraPosition: vec3<f32>,
    padding1: f32,
    cameraForward: vec3<f32>,
    padding2: f32,
    cameraRight: vec3<f32>,
    padding3: f32,
    cameraUp: vec3<f32>,
    sphereCount: f32,
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

@compute @workgroup_size(64,1,1)
fn main(@builtin(global_invocation_id) GlobalInvocationID : vec3<u32>) {
    const epsilon: f32 = 0.001;
    const maxDistance: f32 = 9999;
    const maxSteps: u32 = 32;

    let screen_size: vec2<u32> = textureDimensions(color_buffer);
    let screen_pos : vec2<i32> = vec2<i32>(i32(GlobalInvocationID.x), i32(GlobalInvocationID.y));
    let horizontal_coefficient: f32 = (f32(screen_pos.x) - f32(screen_size.x) / 2) / f32(screen_size.x);
    let vertical_coefficient: f32 = (f32(screen_pos.y) - f32(screen_size.y) / 2) / f32(screen_size.x);

    var mySphere: Sphere;
    mySphere.center = vec3<f32>(3.0, 0.0, 0.0);
    mySphere.radius = 1.0;

    var myRay: Ray;
    myRay.direction = normalize(application_data.cameraForward + horizontal_coefficient * application_data.cameraRight + vertical_coefficient * application_data.cameraUp);
    myRay.origin = application_data.cameraPosition;

    let pixel_color : vec3<f32> = ray_color(&myRay);

    textureStore(color_buffer, screen_pos, vec4<f32>(pixel_color, 1.0));
}

fn ray_color(ray: ptr<function,Ray>) -> vec3<f32> {
    const epsilon: f32 = 0.01;
    const maxDistance: f32 = 9999;
    const maxSteps: u32 = 32;

    var color: vec3<f32> = vec3(0.0, 0.0, 0.0);
    var totalDistanceMarched: f32 = 0.0;
    for (var step: u32 = 0; step < maxSteps; step++) {
        var i: i32 = 0;
        var distanceMarched: f32 = distance_to_scene(ray, &i);
        
        if (distanceMarched < epsilon) {
            color = objects.spheres[i].color;
            break; 
        }
        
        if (totalDistanceMarched > maxDistance) {
            break;
        }
        totalDistanceMarched += distanceMarched;
        
        (*ray).origin += (*ray).direction * distanceMarched;
    }
    return color;
}

fn distance_to_scene(
    ray: ptr<function,Ray>, 
    closest_sphere_index: ptr<function,i32>) -> f32 {

    var closest_distance: f32 = 9999;
    for (var i: i32 = 0; i < i32(application_data.sphereCount); i++) {

        var distance: f32 = distance_to_sphere(ray, i);
        
        if (distance < closest_distance) {
            closest_distance = distance;
            *closest_sphere_index = i;
        }
    }
    return closest_distance;
}

fn distance_to_sphere(
    ray: ptr<function,Ray>, 
    sphere_index: i32) -> f32 {

    let rayToSphere: vec3<f32> = objects.spheres[sphere_index].center - (*ray).origin;
    if (dot(rayToSphere, (*ray).direction) < 0) {
        return 9999;
    }
    else {
        return length(rayToSphere) - objects.spheres[sphere_index].radius;
    }
    
}