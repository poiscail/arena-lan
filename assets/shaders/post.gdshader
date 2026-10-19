// Post-traitement de l'écran : couleurs (contraste, saturation), vignette, grain léger,
// et aberration chromatique rouge quand on prend des dégâts.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float contrast = 1.08;
uniform float saturation = 1.12;
uniform float vignette = 0.35;
uniform float grain = 0.025;
uniform float damage = 0.0;  // 0..1

float rand(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - vec2(0.5);
	// Aberration chromatique (dégâts) : les canaux rouge et bleu se décalent vers les bords
	float ca = damage * 0.006;
	vec3 col;
	col.r = texture(screen_tex, uv + d * ca).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - d * ca).b;
	// Contraste et saturation
	col = (col - 0.5) * contrast + 0.5;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation);
	// Vignette
	float v = smoothstep(0.85, 0.25, length(d * vec2(1.0, 0.85)));
	col *= mix(1.0, v, vignette);
	// Grain
	col += (rand(uv * 731.0 + fract(TIME * 13.0)) - 0.5) * grain;
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
