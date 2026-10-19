// Eau animée : vagues sur les sommets, reflets selon l'angle de vue (Fresnel), écume claire sur les crêtes.
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.03, 0.18, 0.28, 0.92);
uniform vec4 shallow_color : source_color = vec4(0.12, 0.42, 0.5, 0.85);
uniform vec4 foam_color : source_color = vec4(0.85, 0.92, 0.95, 1.0);
uniform float wave_height = 0.12;
uniform float wave_speed = 1.0;
uniform float wave_scale = 0.35;

varying float crest;

float waves(vec2 p, float t) {
	return sin(p.x * wave_scale + t) * 0.5
		+ sin(p.y * wave_scale * 1.3 + t * 1.2) * 0.35
		+ sin((p.x + p.y) * wave_scale * 2.1 + t * 1.7) * 0.15;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float h = waves(world.xz, t);
	VERTEX.y += h * wave_height;
	crest = h;
	// Normale approchée à partir de la pente des vagues
	float e = 0.5;
	float hx = waves(world.xz + vec2(e, 0.0), t) - waves(world.xz - vec2(e, 0.0), t);
	float hz = waves(world.xz + vec2(0.0, e), t) - waves(world.xz - vec2(0.0, e), t);
	NORMAL = normalize(vec3(-hx * wave_height * 2.0, 1.0, -hz * wave_height * 2.0));
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec4 base = mix(shallow_color, deep_color, 0.6 + 0.4 * fresnel);
	float foam = smoothstep(0.62, 0.95, crest);
	ALBEDO = mix(base.rgb, foam_color.rgb, foam * 0.6);
	ALPHA = mix(base.a, 1.0, foam * 0.5);
	ROUGHNESS = 0.08;
	METALLIC = 0.1;
	SPECULAR = 0.7;
}
