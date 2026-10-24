// Neige au sol : couche blanche irrégulière (bruit) qui laisse voir le sol par endroits,
// avec quelques paillettes qui brillent.
shader_type spatial;
render_mode specular_schlick_ggx, cull_back;

uniform vec2 clear_band = vec2(0.0, 0.0);  // bande sans neige le long de X (ruisseau) : |z| < x, fondu sur y
uniform float brightness = 1.0;

varying vec3 world;

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

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz;
	float n = noise(p * 0.12) * 0.55 + noise(p * 0.45) * 0.3 + noise(p * 1.8) * 0.15;
	float cover = smoothstep(0.3, 0.55, n);
	if (clear_band.x > 0.0) {
		cover *= smoothstep(clear_band.x, clear_band.x + clear_band.y, abs(p.y));
	}
	if (cover < 0.01) {
		discard;
	}
	float sparkle = step(0.997, hash(floor(p * 40.0)));
	ALBEDO = vec3(0.86, 0.89, 0.94) * brightness;
	ROUGHNESS = mix(0.8, 0.2, sparkle);
	SPECULAR = mix(0.3, 1.0, sparkle);
	ALPHA = cover * 0.96;
}
