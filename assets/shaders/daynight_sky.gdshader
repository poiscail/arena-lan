// Ciel du cycle jour/nuit : mélange le ciel photographique de jour et le ciel étoilé de nuit,
// avec une lueur orangée à l'horizon du côté du soleil au lever et au coucher.
shader_type sky;

uniform sampler2D day_sky : filter_linear, repeat_enable;
uniform sampler2D night_sky : source_color, filter_linear, repeat_enable;
uniform float day = 1.0;          // 0 nuit noire, 1 plein jour
uniform float warm = 0.0;         // force de la lueur du lever / coucher
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);

void sky() {
	vec3 d = texture(day_sky, SKY_COORDS).rgb;
	vec3 n = texture(night_sky, SKY_COORDS).rgb;
	// Le soleil dessiné dans la photo reste haut : on l'efface quand le vrai soleil descend
	d = min(d, vec3(mix(1000.0, 1.3, max(warm, 1.0 - day))));
	vec2 flat_sun = normalize(sun_dir.xz + vec2(1e-4));
	float toward = max(dot(normalize(EYEDIR.xz + vec2(1e-4)), flat_sun), 0.0);
	float horizon = 1.0 - clamp(abs(EYEDIR.y) * 2.2, 0.0, 1.0);
	float glow = warm * horizon * (0.25 + 0.75 * toward * toward);
	d = mix(d, d * vec3(1.7, 0.8, 0.45) + vec3(0.5, 0.18, 0.05), glow);
	COLOR = mix(n, d * mix(0.3, 1.0, day), smoothstep(0.0, 0.45, day));
}
