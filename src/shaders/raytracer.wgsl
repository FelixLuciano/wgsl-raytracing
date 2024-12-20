const THREAD_COUNT = 16;
const RAY_TMIN = 0.0001;
const RAY_TMAX = 100.0;
const PI = 3.1415927f;
const FRAC_1_PI = 0.31830987f;
const FRAC_2_PI = 1.5707964f;

@group(0) @binding(0)  
  var<storage, read_write> fb : array<vec4f>;

@group(0) @binding(1)
  var<storage, read_write> rtfb : array<vec4f>;

@group(1) @binding(0)
  var<storage, read_write> uniforms : array<f32>;

@group(2) @binding(0)
  var<storage, read_write> spheresb : array<sphere>;

@group(2) @binding(1)
  var<storage, read_write> quadsb : array<quad>;

@group(2) @binding(2)
  var<storage, read_write> boxesb : array<box>;

@group(2) @binding(3)
  var<storage, read_write> trianglesb : array<triangle>;

@group(2) @binding(4)
  var<storage, read_write> meshb : array<mesh>;

struct ray {
  origin : vec3f,
  direction : vec3f,
};

struct sphere {
  transform : vec4f,
  color : vec4f,
  material : vec4f,
};

struct quad {
  Q : vec4f,
  u : vec4f,
  v : vec4f,
  color : vec4f,
  material : vec4f,
};

struct box {
  center : vec4f,
  radius : vec4f,
  rotation: vec4f,
  color : vec4f,
  material : vec4f,
};

struct triangle {
  v0 : vec4f,
  v1 : vec4f,
  v2 : vec4f,
};

struct mesh {
  transform : vec4f,
  scale : vec4f,
  rotation : vec4f,
  color : vec4f,
  material : vec4f,
  min : vec4f,
  max : vec4f,
  show_bb : f32,
  start : f32,
  end : f32,
};

struct material_behaviour {
  scatter : bool,
  direction : vec3f,
};

struct camera {
  origin : vec3f,
  lower_left_corner : vec3f,
  horizontal : vec3f,
  vertical : vec3f,
  u : vec3f,
  v : vec3f,
  w : vec3f,
  lens_radius : f32,
};

struct hit_record {
  t : f32,
  p : vec3f,
  normal : vec3f,
  object_color : vec4f,
  object_material : vec4f,
  frontface : bool,
  hit_anything : bool,
};

fn ray_at(r: ray, t: f32) -> vec3f
{
  return r.origin + t * r.direction;
}

fn get_ray(cam: camera, uv: vec2f, rng_state: ptr<function, u32>) -> ray
{
  var rd = cam.lens_radius * rng_next_vec3_in_unit_disk(rng_state);
  var offset = cam.u * rd.x + cam.v * rd.y;
  return ray(cam.origin + offset, normalize(cam.lower_left_corner + uv.x * cam.horizontal + uv.y * cam.vertical - cam.origin - offset));
}

fn get_camera(lookfrom: vec3f, lookat: vec3f, vup: vec3f, vfov: f32, aspect_ratio: f32, aperture: f32, focus_dist: f32) -> camera
{
  var camera = camera();
  camera.lens_radius = aperture / 2.0;

  var theta = degrees_to_radians(vfov);
  var h = tan(theta / 2.0);
  var w = aspect_ratio * h;

  camera.origin = lookfrom;
  camera.w = normalize(lookfrom - lookat);
  camera.u = normalize(cross(vup, camera.w));
  camera.v = cross(camera.u, camera.w);

  camera.lower_left_corner = camera.origin - w * focus_dist * camera.u - h * focus_dist * camera.v - focus_dist * camera.w;
  camera.horizontal = 2.0 * w * focus_dist * camera.u;
  camera.vertical = 2.0 * h * focus_dist * camera.v;

  return camera;
}

fn envoriment_color(direction: vec3f, color1: vec3f, color2: vec3f) -> vec3f
{
  var unit_direction = normalize(direction);
  var t = 0.5 * (unit_direction.y + 1.0);
  var col = (1.0 - t) * color1 + t * color2;

  var sun_direction = normalize(vec3(uniforms[13], uniforms[14], uniforms[15]));
  var sun_color = int_to_rgb(i32(uniforms[17]));
  var sun_intensity = uniforms[16];
  var sun_size = uniforms[18];

  var sun = clamp(dot(sun_direction, unit_direction), 0.0, 1.0);
  col += sun_color * max(0, (pow(sun, sun_size) * sun_intensity));

  return col;
}

// TODO
fn check_ray_collision(r: ray, max: f32) -> hit_record
{
  var spheresCount = i32(uniforms[19]);
  var quadsCount = i32(uniforms[20]);
  var boxesCount = i32(uniforms[21]);
  var trianglesCount = i32(uniforms[22]);
  var meshCount = i32(uniforms[27]);

  var ray_t = RAY_TMAX;
  var record = hit_record(ray_t, vec3f(0.0), vec3f(0.0), vec4f(0.0), vec4f(0.0), false, false);
  var closest = record;

  // check for collision in each sphere
  for (var index = 0; index < spheresCount; index++)
  {
    var sphere = spheresb[index];

    hit_sphere(sphere.transform.xyz, sphere.transform.w, r, &record, ray_t);

    if(record.hit_anything && record.t < closest.t )
    {
      record.object_color = sphere.color;
      record.object_material = sphere.material;
      ray_t = record.t;
      closest = record;
    }
  }

  return closest;
}

fn lambertian(normal : vec3f, absorption: f32, random_sphere: vec3f, rng_state: ptr<function, u32>) -> material_behaviour
{
  var direction = normal + random_sphere;
  
  if (length(direction) < 0.001) {
    direction = normal;
  }

  return material_behaviour(true, normalize(direction));
}

// TODO
fn metal(normal : vec3f, direction: vec3f, fuzz: f32, random_sphere: vec3f) -> material_behaviour
{
  var reflection = normalize(reflect(direction, normal) + (fuzz * random_sphere));

  return material_behaviour(true, reflection);
}

// TODO (when smoothness < 0.0)
fn dielectric(normal : vec3f, r_direction: vec3f, refraction_index: f32, frontface: bool, random_sphere: vec3f, fuzz: f32, rng_state: ptr<function, u32>) -> material_behaviour
{
  return material_behaviour(false, vec3f(0.0));
}

fn emmisive(color: vec3f, light: f32) -> material_behaviour
{
  return material_behaviour(false, color * light);
}

// TODO
fn trace(r: ray, rng_state: ptr<function, u32>) -> vec3f
{
  var maxbounces = i32(uniforms[2]);
  var light = vec3f(0.0);
  var color = vec3f(1.0);
  var r_ = r;
  var rng_float = rng_next_float(rng_state);
  var rng_sphere = rng_next_vec3_in_unit_sphere(rng_state);
  var backgroundcolor1 = int_to_rgb(i32(uniforms[11]));
  var backgroundcolor2 = int_to_rgb(i32(uniforms[12]));
  var behaviour = material_behaviour(true, vec3f(0.0));

  for (var j = 0; j < maxbounces; j = j + 1)
  {
    var colision = check_ray_collision(r_, RAY_TMAX);

    if(!colision.hit_anything)
    {
      light += color * envoriment_color(r_.direction, backgroundcolor1, backgroundcolor2);

      break;
    }

    // Get the material properties
    var smoothness = colision.object_material.x;
    var absorption = colision.object_material.y;
    var specular = colision.object_material.z;
    var emission = colision.object_material.w;
    var obj_color = colision.object_color.xyz;
    var ray_origin = colision.p + colision.normal * 0.001;

    if (emission > 0.0)
    {
      var emissive_color = emmisive(obj_color, emission);

      light += color * emissive_color.direction;

      break;
    }

    if (smoothness >= 0.0 && specular > rng_float)
    {
        behaviour = metal(colision.normal, r_.direction, absorption, rng_sphere);
    }
    else if (smoothness >= 0.0)
    {
      behaviour = lambertian(colision.normal, absorption, rng_sphere, rng_state);
      color *= colision.object_color.xyz * (1.0 - absorption);
    }
    else
    {
      behaviour = dielectric(colision.normal, r_.direction, specular, colision.frontface, rng_sphere, absorption, rng_state);
      color *= colision.object_color.xyz * (1.0 - absorption);
      ray_origin = colision.p - colision.normal * 0.001;
    }

    if (!behaviour.scatter) 
    {
      break;
    }

    r_ = ray(ray_origin, behaviour.direction);
  }

  return light;
}

// TODO
@compute @workgroup_size(THREAD_COUNT, THREAD_COUNT, 1)
fn render(@builtin(global_invocation_id) id : vec3u)
{
    var rez = uniforms[1];
    var time = u32(uniforms[0]);

    // init_rng (random number generator) we pass the pixel position, resolution and frame
    var rng_state = init_rng(vec2(id.x, id.y), vec2(u32(rez)), time);

    // Get uv
    var fragCoord = vec2f(f32(id.x), f32(id.y));
    var uv = (fragCoord + sample_square(&rng_state)) / vec2(rez);

    // Camera
    var lookfrom = vec3(uniforms[7], uniforms[8], uniforms[9]);
    var lookat = vec3(uniforms[23], uniforms[24], uniforms[25]);

    // Get camera
    var cam = get_camera(lookfrom, lookat, vec3(0.0, 1.0, 0.0), uniforms[10], 1.0, uniforms[6], uniforms[5]);
    var samples_per_pixel = i32(uniforms[4]);

    var color = vec3(0.0);

    // Steps:
    // 1. Loop for each sample per pixel
    for (var sample_index = 0; sample_index < samples_per_pixel; sample_index++) {
      // 2. Get ray
      var ray = get_ray(cam, uv, &rng_state);

      // 3. Call trace function
      color += trace(ray, &rng_state);
    }

    // 4. Average the color
    color /= f32(samples_per_pixel);

    var color_out = vec4(linear_to_gamma(color), 1.0);
    var map_fb = mapfb(id.xy, rez);

    // 5. Accumulate the color
    var should_accumulate = uniforms[3];
    var accumulated_color = rtfb[map_fb] * should_accumulate + color_out;

    // Set the color to the framebuffer
    rtfb[map_fb] = accumulated_color;
    fb[map_fb] = accumulated_color / accumulated_color.w;
}