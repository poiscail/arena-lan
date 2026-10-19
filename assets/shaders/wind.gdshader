// Arbres qui bougent avec le vent : le haut de l'arbre oscille, le pied reste fixe.
// Garde la couleur (et la texture éventuelle) du matériau d'origine.
shader_type spatial;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform float strength = 0.06;  // amplitude, dans les unités du modèle
uniform float speed = 1.4;
uniform float model_height = 1.5;  // hauteur du modèle (avant mise à l'échelle)

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = clamp(VERTEX.y / model_height, 0.0, 1.0);
	float bend = h * h;
	// Décalage différent pour chaque arbre selon sa position
	float phase = origin.x * 0.37 + origin.z * 0.23;
	float sway = sin(TIME * speed + phase) + 0.4 * sin(TIME * speed * 2.3 + phase * 1.7);
	VERTEX.x += sway * strength * bend;
	VERTEX.z += cos(TIME * speed * 0.8 + phase) * strength * 0.5 * bend;
}

void fragment() {
	vec4 c = albedo;
	if (use_texture) {
		c *= texture(albedo_texture, UV);
	}
	ALBEDO = c.rgb;
	ROUGHNESS = 0.9;
}
