@group(0) @binding(0)
var output_buffer: texture_storage_2d<rgba8unorm, write>;

@group(0) @binding(1)
var<uniform> application_data: ApplicationData;

@group(0) @binding(2)
var<storage, read> light_data: LightData;

@group(1) @binding(0)
var<storage, read> objects: ObjectData;

/* CPU/GPU structs */
struct ApplicationData
{
    camera_position: vec3<f32>,
    light_count: f32,
    camera_forward: vec3<f32>,
    sphere_count: f32,
    camera_right: vec3<f32>,
    time: f32,
    camera_up: vec3<f32>,
    padding1: f32,
}

struct Light
{
    position: vec3<f32>,
    padding: f32,
}

struct LightData
{
    lights: array<Light>,
}

struct Sphere
{
    center: vec3<f32>,
    radius: f32,
    color: vec3<f32>,
    padding: f32,
}

struct ObjectData
{
    spheres: array<Sphere>
}

/* GPU only struct */
struct Ray
{
    direction: vec3<f32>,
    padding1: f32,
    origin: vec3<f32>,
    padding2: f32
}

/* General ray marching constants */
const EPSILON: f32 = 0.001;
const MAX_DISTANCE: f32 = 9999.0;
const MAX_RAY_MARCHING_STEPS: u32 = 32;

const ABSORPTION_COEFFICIENT: f32 = 0.5; // TODO should be part of material
const ABSORPTION_CUTOFF: f32 = 0.25; // 0.01;
const MARCH_MULTIPLIER: f32 = 1.8; // 1.0;
const MAX_VOLUME_MARCH_STEPS: u32 = 20;
const MAX_VOLUME_LIGHT_MARCH_STEPS: u32 = 4; // 25;
const MAX_OPAQUE_SHADOW_MARCH_STEPS: u32 = 10; // 25;
const UNIFORM_FOG_DENSITY: bool = false;

@compute @workgroup_size(64,1,1)
fn main(@builtin(global_invocation_id) GlobalInvocationID : vec3<u32>)
{
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

fn ray_march(ray: ptr<function,Ray>) -> vec3<f32>
{
    var primitive_hit = false;
    var opaque_primitive_color: vec3<f32> = vec3(0.0);
    var total_distance_marched: f32 = 0.0;
    var closest_primitive_color: vec3<f32> = vec3(0.0); // Defaulted to black for background
    var opaque_volume_marched_position: vec3<f32> = vec3(0.0);

    // Ray march opaque volume
    for (var step: u32 = 0; step < MAX_RAY_MARCHING_STEPS; step++)
    {
        opaque_volume_marched_position = (*ray).origin + (*ray).direction * total_distance_marched;

        var distance_marched: f32 = closest_distance_in_scene(opaque_volume_marched_position, (*ray).direction, &closest_primitive_color);
        
        if (distance_marched < EPSILON)
        {
            primitive_hit = true;
            break; 
        }

        if (total_distance_marched > MAX_DISTANCE)
        {
            break;
        }
        total_distance_marched += distance_marched;
    }

    // Ray march non-opaque volume; core concepts from https://wallisc.github.io/rendering/2020/05/02/Volumetric-Rendering-Part-1.html
    var volume_depth: f32 = intersect_volume((*ray).origin, (*ray).direction, total_distance_marched);
    var opaque_visibility: f32 = 1.0;
    var volumetric_color: vec3<f32> = vec3(0.0);
    if (volume_depth > 0.0)
    {
        const volume_albedo: vec3<f32> = vec3(0.8);
        const march_size: f32 = 0.6f * MARCH_MULTIPLIER;
        var distance_in_volume: f32 = 0.0;
        var signed_distance: f32 = 0.0;
        for (var i: u32 = 0; i < MAX_VOLUME_MARCH_STEPS; i++)
        {
            volume_depth += max(march_size, signed_distance);
            if (volume_depth > total_distance_marched || opaque_visibility < ABSORPTION_CUTOFF)
            {
                break;
            }
            
            let position: vec3<f32> = (*ray).origin + volume_depth * (*ray).direction;

            signed_distance = signed_distance_volumetric_glob(position);

            // We are within the volume if the signed_distance is less than 0
			if (signed_distance < 0.0)
            {
                distance_in_volume += march_size;
                let previous_opaque_visibility: f32 = opaque_visibility;
                opaque_visibility *= beer_lambert(ABSORPTION_COEFFICIENT * fog_density(position, signed_distance), march_size);
                let absorptionFromMarch: f32 = previous_opaque_visibility - opaque_visibility;
                
                // For simplicity, we will simulate single scattering of light rays as we march along the ray and use that intersection point as the light intersection
                for (var lightIndex: u32 = 0; lightIndex < u32(application_data.light_count); lightIndex++)
    			{
                    var light_direction: vec3<f32> = light_data.lights[lightIndex].position - position;
                    let light_distance: f32 = length(light_direction);
                    light_direction /= light_distance;

                    const current_light_color: vec3<f32> = vec3(1.0, 0.0, 0.0); // TODO: put this as part of lights struct
                    let light_color: vec3<f32> = current_light_color;// * light_attenuation(light_distance); // TODO add attenuation
                    let light_visiblity: f32 = 1.0;

                    if (is_color_insignificant(light_color)) {
                        continue;
                    }
                    
                    const light_march_size: f32 = 0.65f * MARCH_MULTIPLIER;
                    let light_visibility: f32 = calculate_light_visibility(position, (*ray).direction, light_distance, MAX_VOLUME_LIGHT_MARCH_STEPS, light_march_size); 
                    volumetric_color += absorptionFromMarch * light_visibility * volume_albedo * light_color;
                }
                volumetric_color += absorptionFromMarch * volume_albedo * ambient_light();
            }
        }
    }

    // Calculate opaque primitive lighting
    if (primitive_hit) {
        const enable_lighting: bool = true; // Disable to reduce computational cost
        if (enable_lighting)
        {
            var unused: vec3<f32>; // We don't care about colour when we want the normal
            let normal = calculate_normal(opaque_volume_marched_position, (*ray).direction, &unused);
            let reflection_direction: vec3<f32> = reflect((*ray).direction, normal);
            calculate_phong_lighting(opaque_volume_marched_position, normal, reflection_direction, closest_primitive_color, &opaque_primitive_color);
        }
        else
        {
            opaque_primitive_color = closest_primitive_color;
        }
    }

    volumetric_color = clamp(volumetric_color, vec3(0.0), vec3(1.0));
    return min(volumetric_color, vec3(1.0)) + opaque_visibility * opaque_primitive_color;
}

// Lowering dentisty based on how lose we are to an edge for softer effects near edge
fn fog_density(position: vec3<f32>, sdf_distance: f32) -> f32
{
    const max_sdf_multiplier: f32 = 1.0;
    let inside_sdf: bool = sdf_distance < 0.0;
    let sdf_multiplier: f32 = select(0.0, min(abs(sdf_distance), max_sdf_multiplier), inside_sdf); // false, true, condition

    if (UNIFORM_FOG_DENSITY) {
        return sdf_multiplier;
    }
    return sdf_multiplier * abs(fbm_4(position / 6.0) + 0.5);
}

// Used to calculate the absorption of light along a path based on the material absorption coefficient and the distance travelled
fn beer_lambert(absorption: f32, distance_travelled: f32) -> f32
{
    return exp(-absorption * distance_travelled);
}

fn calculate_light_visibility(ray_origin: vec3<f32>, ray_direction: vec3<f32>, maxT: f32, max_steps: u32, march_size: f32) -> f32
{
    var t: f32 = 0.0;
    var visibility: f32 = 1.0;
    var signed_distance: f32 = 0.0;
    for (var i: u32 = 0; i < max_steps; i++)
    {                       
        t += max(march_size, signed_distance);
        if (t > maxT || visibility < ABSORPTION_CUTOFF){
            break;
        }

        let marched_position: vec3<f32> = ray_origin + t * ray_direction;

        signed_distance = signed_distance_volumetric_glob(marched_position);
        if (signed_distance < 0.0)
        {
            visibility *= beer_lambert(ABSORPTION_COEFFICIENT * fog_density(marched_position, signed_distance), march_size);
        }
    }
    return visibility;
}


fn luminance(color: vec3<f32>) -> f32
{
    return (color.r * 0.3) + (color.g * 0.59) + (color.b * 0.11);
}

fn is_color_insignificant(color: vec3<f32>) -> bool
{
    const minValue: f32 = 0.009;
    return luminance(color) < minValue;
}

fn calculate_normal(
    marched_position: vec3<f32>,
    ray_direction: vec3<f32>, 
    closest_primitive_color: ptr<function, vec3<f32>>
) -> vec3<f32> {
    const small_step: vec3<f32> = vec3(EPSILON, 0.0, 0.0);

    let gradient_x: f32 = closest_distance_in_scene(marched_position + small_step.xyy, ray_direction, closest_primitive_color) - closest_distance_in_scene(marched_position - small_step.xyy, ray_direction, closest_primitive_color);
    let gradient_y: f32 = closest_distance_in_scene(marched_position + small_step.yxy, ray_direction, closest_primitive_color) - closest_distance_in_scene(marched_position - small_step.yxy, ray_direction, closest_primitive_color);
    let gradient_z: f32 = closest_distance_in_scene(marched_position + small_step.yyx, ray_direction, closest_primitive_color) - closest_distance_in_scene(marched_position - small_step.yyx, ray_direction, closest_primitive_color);

    let normal: vec3<f32> = vec3(gradient_x, gradient_y, gradient_z);

    return normalize(normal);
}

/* Lighting related methods */
fn compute_diffuse(normal: vec3<f32>, light_position: vec3<f32>, input_color: vec3<f32>) -> vec3<f32>
{
    let material_diffuse: vec3<f32> = input_color; // TODO: this should be integrated into the material struct
    let n_dot_l: f32 = dot(normal, light_position);

    return clamp(n_dot_l * material_diffuse, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn compute_specular(light_direction: vec3<f32>, reflection_direction: vec3<f32>) -> vec3<f32>
{
    const specular_intensity: f32 = 0.5; // TODO add this to material
    const shininess_coefficient: f32 = 4.0; // TODO add this to material, have this be max(mat.shininess, 4.0);

    return vec3(specular_intensity * pow(max(dot(reflection_direction, light_direction), 0.0), 4.0));
}

fn ambient_light() -> vec3<f32>
{
	return vec3(0.1, 0.1, 0.1);
}

fn light_attenuation(distance_to_light: f32) -> f32
{
    return 1.0 / pow(distance_to_light, 2.0);
}

fn calculate_phong_lighting(
    position: vec3<f32>,
    normal: vec3<f32>,
    reflection_direction: vec3<f32>,
    input_color: vec3<f32>,
    output_color: ptr<function, vec3<f32>>
) {
    for (var lightIndex: u32 = 0; lightIndex < u32(application_data.light_count); lightIndex++)
    {
        var light_direction: vec3<f32> = light_data.lights[lightIndex].position - position;
        let light_distance: f32 = length(light_direction);
        light_direction /= light_distance;

        const current_light_color = vec3(1.0, 0.0, 0.0); // TODO: put this as part of lights struct
        let light_color: vec3<f32> = current_light_color;// * light_attenuation(light_distance); // TODO add attenuation
        var light_visibility: f32 = 1.0;

        // TODO test and enable this check
        // if (!is_color_insignificant(light_color))
        // {
        //     const shadow_march_size: f32 = 0.65f * MARCH_MULTIPLIER;
        //     light_visibility = calculate_light_visibility(position, light_direction, light_distance, MAX_OPAQUE_SHADOW_MARCH_STEPS, shadow_march_size); 
        // }
        
        let specular_color: vec3<f32> = light_color * light_visibility * compute_specular(light_direction, reflection_direction);
        let diffuse_color: vec3<f32> = light_color * light_visibility * compute_diffuse(normal, light_direction, input_color);
        *output_color += specular_color + diffuse_color;
    }

    *output_color += ambient_light() * input_color;
}

/* Loop through all primitives and find closest primitive */
fn closest_distance_in_scene(
    marched_position: vec3<f32>,  // Position along ray marched so far
    ray_direction: vec3<f32>, 
    closest_primitive_color: ptr<function, vec3<f32>>
) -> f32 {
    var distance: f32;
    var closest_distance: f32 = 9999.0;

    // Spheres from CPU side
    // for (var i: u32 = 0; i < u32(application_data.sphere_count); i++)
    // {
    //     distance = signed_dst_to_sphere(marched_position, ray_direction, i);
        
    //     if (distance < closest_distance)
    //     {
    //         // Noise to distort the sphere: https://michaelwalczyk.com/blog-ray-marching.html
    //         let displacement: f32 = sin(5.0 * marched_position.x) * sin(5.0 * marched_position.y) * sin(5.0 * marched_position.z) * 0.25;
    //         closest_distance = distance + displacement;
    //         *closest_primitive_color = objects.spheres[i].color;
    //     }
    // }

    // Torus
    distance = signed_dst_to_torus(marched_position, vec3(0.0, 0.0, 0.0), vec2(1.0, 0.6));
    if (distance < closest_distance)
    {
        closest_distance = distance;
        *closest_primitive_color = vec3(0.0, 1.0, 0.0);
    }

    // distance = signed_distance_volumetric_glob(marched_position);
    // if (distance < closest_distance)
    // {
    //     closest_distance = distance;
    //     *closest_primitive_color = vec3(0.8);
    // }

    // Plane
    // distance = signed_dst_to_plane(marched_position, vec3(0.0, 0.0, 1.0), 0.0);
    // if (distance < closest_distance) {
    //     closest_distance = distance;
    //     *closest_primitive_color = vec3(0.0, 0.0, 1.0);
    // }

    return closest_distance;
}

/* Primitive signed distance functions */
// Note that spheres are defined on the CPU
fn signed_dst_to_sphere(
    marched_position: vec3<f32>,
    ray_direction: vec3<f32>,
    sphere_index: u32
) -> f32 {
    let ray_to_sphere: vec3<f32> = objects.spheres[sphere_index].center - marched_position;

    // Ignore spheres behind the current marched position
    if (dot(ray_to_sphere, ray_direction) < 0)
    {
        return 9999.0;
    }
    
    return length(ray_to_sphere) - objects.spheres[sphere_index].radius;
}

// This sdf is mainly used for GPU defined spheres to allow for quick GPU side iteration
fn signed_dst_to_custom_sphere(
    marched_position: vec3<f32>,
    center: vec3<f32>,
    radius: f32
) -> f32 {
    let ray_to_sphere: vec3<f32> = center - marched_position;
    
    return length(ray_to_sphere) - radius;
}

// Note that torus is only defined on the GPU side
fn signed_dst_to_torus(
    marched_position: vec3<f32>,
    center: vec3<f32>,
    radii: vec2<f32>,
) -> f32 {
    let ray_to_torus: vec3<f32> = center - marched_position;

    let q: vec2<f32> = vec2(length(ray_to_torus.xz) - radii.x, marched_position.y);
    
    return length(q) - radii.y;
}

// Note that plane is only defined on the GPU side
fn signed_dst_to_plane(
    marched_position: vec3<f32>,
    normal: vec3<f32>,
    h: f32
) -> f32 {
    let signed_dst =
        (marched_position.x * normal.x + marched_position.y * normal.y + marched_position.z * normal.z + h) 
        / sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.x);
    return signed_dst;
}

// TODO: currently not tested or used
// Mandelbulb distance estimation: http://blog.hvidtfeldts.net/index.php/2011/09/distance-estimated-3d-fractals-v-the-mandelbulb-different-de-approximations/
fn signed_dst_mandelbulb(marched_position: vec3<f32>) -> f32
{
    const power: f32 = 10.0; // This is configurable

    var z: vec3<f32> = marched_position;
	var r: f32 = 0.0;
	var dr: f32 = 1.0;
    var iterations: i32 = 0;

	for (var i = 0; i < 15 ; i++)
    {
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

// Taken from https://iquilezles.org/articles/distfunctions
fn signed_distance_smooth_union(d1: f32, d2: f32 , k: f32) -> f32
{
    let h: f32 = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return mix(d2, d1, h) - k * h * (1.0 - h); 
}

// Taken from https://wallisc.github.io/rendering/2020/05/02/Volumetric-Rendering-Part-1.html
fn signed_distance_volumetric_glob(marched_position: vec3<f32>) -> f32
{
    let fbm_coord: vec3<f32> = (marched_position + 2.0 * vec3(application_data.time, 0.0, application_data.time)) / 1.5f;
    var signed_distance: f32 = signed_dst_to_custom_sphere(marched_position, vec3(-8.0, 2.0 + 20.0 * sin(application_data.time), -1), 5.6);
    signed_distance = signed_distance_smooth_union(signed_distance, signed_dst_to_custom_sphere(marched_position, vec3(8.0, 8.0 + 12.0 * cos(application_data.time), 3), 5.6), 3.0);
    signed_distance = signed_distance_smooth_union(signed_distance, signed_dst_to_custom_sphere(marched_position, vec3(5.0 * sin(application_data.time), 3.0, 0), 8.0), 3.0) + 7.0 * fbm_4(fbm_coord / 3.2);
    return signed_distance;
}

fn intersect_volume(ray_origin: vec3<f32>, ray_direction: vec3<f32>, max_t: f32) -> f32
{
	const precis: f32 = 0.5; 
    var t: f32 = 0.0;
    for (var i: u32 = 0; i < MAX_RAY_MARCHING_STEPS; i++)
    {
	    let result: f32 = signed_distance_volumetric_glob(ray_origin + ray_direction * t);
        if (result < precis || t > max_t)
        {
            break;
        }
        t += result;
    }

    if (t >= max_t) {
        return -1.0;
    }
    return t;
}

// Hash function taken from Inigo Quilez's Rainforest ShaderToy: https://www.shadertoy.com/view/4ttSWf
fn hash1(n: f32) -> f32
{
    return fract(n * 17.0 * fract(n * 0.3183099));
}

// Generic noise function taken from Inigo Quilez's Rainforest ShaderToy: https://www.shadertoy.com/view/4ttSWf
fn noise(x: vec3<f32>) -> f32
{
    let p: vec3<f32> = floor(x);
    let w: vec3<f32> = fract(x);
    
    let u: vec3<f32> = w*w*w*(w*(w*6.0-15.0)+10.0);
    
    let n: f32 = p.x + 317.0*p.y + 157.0*p.z;
    
    let a: f32 = hash1(n+0.0);
    let b: f32 = hash1(n+1.0);
    let c: f32 = hash1(n+317.0);
    let d: f32 = hash1(n+318.0);
    let e: f32 = hash1(n+157.0);
	let f: f32 = hash1(n+158.0);
    let g: f32 = hash1(n+474.0);
    let h: f32 = hash1(n+475.0);

    let k0: f32 =   a;
    let k1: f32 =   b - a;
    let k2: f32 =   c - a;
    let k3: f32 =   e - a;
    let k4: f32 =   a - b - c + d;
    let k5: f32 =   a - c - e + g;
    let k6: f32 =   a - b - e + f;
    let k7: f32 = - a + b + c - d + e - f - g + h;

    return -1.0 + 2.0 * (k0 + k1*u.x + k2*u.y + k3*u.z + k4*u.x*u.y + k5*u.y*u.z + k6*u.z*u.x + k7*u.x*u.y*u.z);
}

const m3 = mat3x3<f32> (
    vec3(0.00,  0.80,  0.60),
    vec3(-0.80,  0.36, -0.48),
    vec3(-0.60, -0.48,  0.64)
);

// Fractional brownian motion taken from Inigo Quilez's Rainforest ShaderToy: https://www.shadertoy.com/view/4ttSWf
fn fbm_4(x_in: vec3<f32>) -> f32
{
    const f: f32 = 2.0;
    const s: f32 = 0.5;
    var a: f32 = 0.0;
    var b: f32 = 0.5;
    var x: vec3<f32> = x_in;
    for (var i = 0; i < 4; i++)
    {
        let n: f32 = noise(x);
        a += b*n;
        b *= s;
        x = f*m3*x;
    }

	return a;
}
