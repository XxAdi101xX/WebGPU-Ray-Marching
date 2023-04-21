@group(0) @binding(0)
var output_buffer: texture_storage_2d<rgba8unorm, write>;

@group(0) @binding(1)
var<uniform> application_data: ApplicationData;

@group(0) @binding(2)
var<storage, read> light_data: LightData;

@group(1) @binding(0)
var<storage, read> objects: ObjectData;

// CPU/GPU structs
struct ApplicationData {
    camera_position: vec3<f32>,
    light_count: f32,
    camera_forward: vec3<f32>,
    sphere_count: f32,
    camera_right: vec3<f32>,
    padding1: f32,
    camera_up: vec3<f32>,
    padding2: f32,
}

struct Light {
    position: vec3<f32>,
    padding: f32,
}

struct LightData {
    lights: array<Light>,
}

struct Sphere {
    center: vec3<f32>,
    radius: f32,
    color: vec3<f32>,
    padding: f32,
}

struct ObjectData {
    spheres: array<Sphere>
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

    let pixel_color : vec3<f32> = ray_march_opaque_primatives(&ray);

    textureStore(output_buffer, screen_pos, vec4<f32>(pixel_color, 1.0));
}

fn ray_march_opaque_primatives(ray: ptr<function,Ray>) -> vec3<f32> {
    var color: vec3<f32> = vec3(0.0, 0.0, 0.0);
    var total_distance_marched: f32 = 0.0;

    for (var step: u32 = 0; step < max_steps; step++) {
        let marched_position: vec3<f32> = (*ray).origin + (*ray).direction * total_distance_marched;
        var closest_primative_color: vec3<f32> = vec3(0.0, 0.0, 0.0); // Defaulted to black for background

        let normal = calculate_normal(marched_position, (*ray).direction, &closest_primative_color);
        let distance_marched: f32 = closest_distance_in_scene(marched_position, (*ray).direction, &closest_primative_color);
        
        if (distance_marched < epsilon) {
            const enable_lighting: bool = true; // Disable to reduce computational cost
            if (enable_lighting) {
                let reflection_direction: vec3<f32> = reflect((*ray).direction, normal);
                calculate_phong_lighting(marched_position, normal, reflection_direction, &color);
            } else {
                color = closest_primative_color;
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
    closest_primative_color: ptr<function, vec3<f32>>
) -> f32 {
    var distance: f32;
    var closest_distance: f32 = 9999.0;
    for (var i: u32 = 0; i < u32(application_data.sphere_count); i++) {
        distance = signed_dst_to_sphere(marched_position, ray_direction, i);
        
        if (distance < closest_distance) {
            // Noise to distort the sphere: https://michaelwalczyk.com/blog-ray-marching.html
            let displacement: f32 = sin(5.0 * marched_position.x) * sin(5.0 * marched_position.y) * sin(5.0 * marched_position.z) * 0.25;
            closest_distance = distance + displacement;
            *closest_primative_color = objects.spheres[i].color;
        }
    }

    // Torus
    distance = signed_dst_to_torus(marched_position, vec3(0.0, 0.0, 0.0), vec2(1.0, 0.6));
    if (distance < closest_distance) {
        closest_distance = distance;
        *closest_primative_color = vec3(0.0, 1.0, 0.0);
    }

    // Plane
    /*
    distance = signed_dst_to_plane(marched_position, vec3(0.0, 0.0, 1.0), 0.0);
    if (distance < closest_distance) {
        closest_distance = distance;
        // set color here, defaulted to closest sphere colour
    }*/

    return closest_distance;
}

fn calculate_normal(
    marched_position: vec3<f32>,
    ray_direction: vec3<f32>, 
    closest_primative_color: ptr<function, vec3<f32>>
) -> vec3<f32> {
    const small_step: vec3<f32> = vec3(epsilon, 0.0, 0.0);

    let gradient_x: f32 = closest_distance_in_scene(marched_position + small_step.xyy, ray_direction, closest_primative_color) - closest_distance_in_scene(marched_position - small_step.xyy, ray_direction, closest_primative_color);
    let gradient_y: f32 = closest_distance_in_scene(marched_position + small_step.yxy, ray_direction, closest_primative_color) - closest_distance_in_scene(marched_position - small_step.yxy, ray_direction, closest_primative_color);
    let gradient_z: f32 = closest_distance_in_scene(marched_position + small_step.yyx, ray_direction, closest_primative_color) - closest_distance_in_scene(marched_position - small_step.yyx, ray_direction, closest_primative_color);

    let normal: vec3<f32> = vec3(gradient_x, gradient_y, gradient_z);

    return normalize(normal);
}   

fn compute_diffuse(normal: vec3<f32>, light_position: vec3<f32>) -> vec3<f32> {
    const material_diffuse_coefficient: vec3<f32> = vec3(0.6, 0.6, 0.7); // TODO: this should be integrated into the material struct
    let n_dot_l: f32 = dot(normal, light_position);

    return clamp(n_dot_l * material_diffuse_coefficient, vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(1.0, 1.0, 1.0));
}

fn compute_specular(light_direction: vec3<f32>, reflection_direction: vec3<f32>) -> vec3<f32> {
    const specular_intensity: f32 = 0.5; // TODO add this to material
    const shininess_coefficient: f32 = 4.0; // TODO add this to material, have this be max(mat.shininess, 4.0);

    return vec3(specular_intensity * pow(max(dot(reflection_direction, light_direction), 0.0), 4.0));
}

fn ambient_light() -> vec3<f32> {
	return vec3(0.1, 0.1, 0.1);
}

fn light_attenuation(distance_to_light: f32) -> f32 {
    return 1.0 / pow(distance_to_light, 2.0);
}

fn calculate_phong_lighting(
    position: vec3<f32>,
    normal: vec3<f32>,
    reflection_direction: vec3<f32>,
    color: ptr<function, vec3<f32>>
) {
    for (var lightIndex: u32 = 0; lightIndex < u32(application_data.light_count); lightIndex++) {
        var light_direction: vec3<f32> = light_data.lights[lightIndex].position - position;
        let light_distance: f32 = length(light_direction);
        light_direction /= light_distance;

        const current_light_color = vec3(1.0, 0.0, 1.0); // TODO: put this as part of lights struct
        let light_color: vec3<f32> = current_light_color;// * light_attenuation(light_distance); // TODO add attenuation
        let light_visiblity: f32 = 1.0;

        // #if CAST_VOLUME_SHADOW_ON_OPAQUES
        // if(!IsColorInsignificant(lightColor))
        // {
        //     const float shadowMarchSize = 0.65f * MARCH_MULTIPLIER;
        //     lightVisiblity = GetLightVisiblity(position, lightDirection, lightDistance, MAX_OPAQUE_SHADOW_MARCH_STEPS, shadowMarchSize); 
        // }
        // #endif
        
        let specular_color: vec3<f32> = light_color * light_visiblity * compute_specular(light_direction, reflection_direction);
        let diffuse_color: vec3<f32> = light_color * light_visiblity * compute_diffuse(normal, light_direction);
        *color += specular_color + diffuse_color;
    }

    const material_ambient_component: vec3<f32> = vec3(1.0, 1.0, 1.0); // TODO: should this be part of material
    *color += ambient_light() * material_ambient_component;
}

// Signed distance functions
fn signed_dst_to_sphere(
    marched_position: vec3<f32>,
    ray_direction: vec3<f32>,
    sphere_index: u32
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

// TODO: add plane data on the CPU side
fn signed_dst_to_plane(
    marched_position: vec3<f32>,
    normal: vec3<f32>,
    h: f32
) -> f32 {
    return dot(marched_position, normal) + h;
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