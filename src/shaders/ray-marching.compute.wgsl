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

const epsilon: f32 = 0.001;
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
        let marched_position: vec3<f32> = (*ray).origin + (*ray).direction * total_distance_marched;
        var i: i32 = 0;
        var distance_marched: f32 = closest_distance_in_scene(marched_position, (*ray).direction, &i);
        
        if (distance_marched < epsilon) {
            const enable_lighting: bool = true;
            if (enable_lighting) {
                const intensity_multiplier: f32 = 1.4;
                let normal = calculate_normal(marched_position, (*ray).direction, &i);
                let light_position = vec3(-2.0, 0.0, 5.0);
                let direction_to_light = normalize(marched_position - light_position);
                let diffuse_intensity = max(0.0, dot(normal, direction_to_light)) * intensity_multiplier;
                color = objects.spheres[i].color * diffuse_intensity;
            } else {
                color = objects.spheres[i].color;
            }
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
    var distance: f32;
    var closest_distance: f32 = 9999.0;
    for (var i: i32 = 0; i < i32(application_data.sphere_count); i++) {
        distance = signed_dst_to_sphere(marched_position, ray_direction, i);
        
        if (distance < closest_distance) {
            // Noise to distort the sphere: https://michaelwalczyk.com/blog-ray-marching.html
            let displacement: f32 = sin(5.0 * marched_position.x) * sin(5.0 * marched_position.y) * sin(5.0 * marched_position.z) * 0.25;
            closest_distance = distance + displacement;
            *closest_sphere_index = i;
        }
    }

    // Torus
    distance = signed_dst_to_torus(marched_position, vec3(0.0, 0.0, 0.0), vec2(1.0, 0.6));
    if (distance < closest_distance) {
        closest_distance = distance;
        // set color here, defaulted to closest 
    }

    return closest_distance;
}

fn calculate_normal(
    marched_position: vec3<f32>,
    ray_direction: vec3<f32>, 
    closest_sphere_index: ptr<function,i32>
) -> vec3<f32> {
    const small_step: vec3<f32> = vec3(epsilon, 0.0, 0.0);

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

// TODO: add torus data on the CPU side
fn signed_dst_to_torus(
    marched_position: vec3<f32>,
    center: vec3<f32>,
    radii: vec2<f32>,
) -> f32 {
    let ray_to_torus: vec3<f32> = center - marched_position;

    let q: vec2<f32> = vec2(length(ray_to_torus.xz) - radii.x, marched_position.y);
    
    return length(q) - radii.y;
}

// TODO: currently not tested or used
// Mandelbulb distance estimation: http://blog.hvidtfeldts.net/index.php/2011/09/distance-estimated-3d-fractals-v-the-mandelbulb-different-de-approximations/
fn signed_dst_mandelbulb(marched_position: vec3<f32>) -> f32 {
    const power: f32 = 10.0; // This is configurable

    var z: vec3<f32> = marched_position;
	var r: f32 = 0.0;
	var dr: f32 = 1.0;
    var iterations: i32 = 0;

	for (var i = 0; i < 15 ; i++) {
        iterations = i;
		r = length(z);

		if (r>2) {
            break;
        }
        
		// convert to polar coordinates
		var theta: f32 = acos(z.z/r);
		var phi: f32 = atan2(z.y,z.x);
		dr = pow(r, power - 1.0) * power * dr + 1.0;

		// scale and rotate the point
		var zr: f32 = pow(r, power);
		theta = theta * power;
		phi = phi * power;
		
		// convert back to cartesian coordinates
		z = zr * vec3<f32>(sin(theta) * cos(phi), sin(phi)*sin(theta), cos(theta));
		z += marched_position;
	}
    var dst: f32 = 0.5 * log(r) * r / dr;
    return dst;
	//return vec2<f32>(iterations, dst * 1);
}