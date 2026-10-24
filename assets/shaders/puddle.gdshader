// Flaque d'eau : bord irrégulier (bruit), surface sombre et lisse qui reflète le ciel,
// petits ronds qui s'élargissent là où tombent les gouttes.
shader_type spatial;
render_mode specular_schlick_ggx, cull_back;

uniform float seed = 0.0;
uniform float ripple_scale = 3.0;   // nombre de cellules de gouttes par mètre (en UV × taille)
uniform vec2 size = vec2(2.0, 2.0);
uniform vec3 tint : source_color = vec3(0.02, 0.025, 0.03);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Pente de la surface due aux ronds de gouttes dans la cellule c
vec2 ripple(vec2 q, vec2 c, float t) {
	vec2 centre = c + vec2(hash(c + seed), hash(c.yx + seed * 1.3)) * 0.8 + 0.1;
	float phase = fract(t * 0.9 + hash(c * 1.7 + seed));
	vec2 d = q - centre;
	float r = length(d) + 1e-4;
	float front = phase * 0.6;
	float ring = smoothstep(0.08, 0.0, abs(r - front)) * (1.0 - phase);
	return d / r * cos((r - front) * 70.0) * ring;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float n = noise(UV * 3.0 + seed) * 0.6 + noise(UV * 7.0 + seed * 1.7) * 0.4;
	float edge = 1.0 - length(p) + (n - 0.5) * 0.8;
	float a = smoothstep(0.02, 0.22, edge);
	if (a < 0.01) {
		discard;
	}
	vec2 q = UV * size * ripple_scale;
	vec2 cell = floor(q);
	vec2 slope = vec2(0.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			slope += ripple(q, cell + vec2(float(x), float(y)), TIME);
		}
	}
	NORMAL_MAP = normalize(vec3(-slope * 0.35, 1.0)) * 0.5 + 0.5;
	ALBEDO = tint;
	ROUGHNESS = 0.04;
	METALLIC = 0.35;
	SPECULAR = 0.9;
	ALPHA = a * 0.88;
}
