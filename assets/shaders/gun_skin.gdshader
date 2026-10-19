// Skins d'armes : motifs calculés dans le repère de l'arme (en mètres), donc le motif reste
// collé à l'arme et garde la même taille sur toutes les armes. Une partie de la couleur d'origine
// de chaque pièce est gardée (« detail ») pour qu'on distingue encore la crosse, le canon, etc.
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.2, 0.2, 0.2, 1.0);
uniform int pattern = 0;
uniform vec4 c1 : source_color = vec4(1.0);
uniform vec4 c2 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 c3 : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float scale = 8.0;
uniform float detail = 0.35;
uniform float metal = 0.2;
uniform float rough = 0.5;
uniform float emit = 0.0;
uniform float speed = 0.0;

varying vec3 lp;
varying vec3 ln;

float hash1(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash1(i), hash1(i + vec3(1, 0, 0)), f.x),
				mix(hash1(i + vec3(0, 1, 0)), hash1(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash1(i + vec3(0, 0, 1)), hash1(i + vec3(1, 0, 1)), f.x),
				mix(hash1(i + vec3(0, 1, 1)), hash1(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

// Projection 2D sur la face dominante (les armes low poly ont de grandes faces plates)
vec2 plane_uv(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.x > a.y && a.x > a.z) return p.zy;
	if (a.y > a.z) return p.xz;
	return p.xy;
}

// Distance au bord d'une cellule de Voronoï 2D + identifiant de la cellule
vec3 voronoi(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float md = 8.0;
	vec2 mid = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = vec2(hash1(vec3(n + g, 1.0)), hash1(vec3(n + g, 7.0)));
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mid = n + g;
			}
		}
	}
	return vec3(sqrt(md), mid);
}

void vertex() {
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lp = VERTEX * s;
	ln = NORMAL;
}

void fragment() {
	vec3 p = lp * scale;
	vec2 uv = plane_uv(lp, ln) * scale;
	float t = TIME * speed;
	vec3 col = c1.rgb;
	float em = 0.0;     // part de la couleur qui brille
	float m = metal;
	float r = rough;

	if (pattern == 0) {
		// Standard : couleur d'origine un peu éclaircie
		col = base_color.rgb * 1.3;
	} else if (pattern == 1) {
		col = c1.rgb;
	} else if (pattern == 2) {
		// Dégradé le long de l'arme
		float g = smoothstep(-0.32, 0.32, lp.x + (fbm(p) - 0.5) * 0.08);
		col = mix(c1.rgb, c2.rgb, g);
	} else if (pattern == 3 || pattern == 11) {
		// Tigre / zèbre : rayures déformées
		float w = pattern == 3 ? 0.9 : 0.55;
		float s = sin((lp.x * scale * 2.0 + fbm(p * 0.8) * 3.0 * w) * 3.0 + lp.y * scale * 2.5);
		col = mix(c1.rgb, c2.rgb, smoothstep(0.25, 0.45, s));
	} else if (pattern == 4) {
		// Camouflage forêt : taches organiques à 3 couleurs + sombre
		float n = fbm(p * 0.6);
		float n2 = fbm(p * 0.6 + vec3(13.0));
		col = c1.rgb;
		col = mix(col, c2.rgb, step(0.5, n));
		col = mix(col, c3.rgb, step(0.56, n2));
		col = mix(col, c3.rgb * 0.35, step(0.62, fbm(p * 0.9 + vec3(31.0))));
	} else if (pattern == 5) {
		// Camouflage numérique : pixels
		vec2 cell = floor(uv * 2.2);
		float n = noise3(vec3(cell * 0.35, 3.0)) + 0.5 * noise3(vec3(cell * 0.9, 9.0));
		col = n < 0.6 ? c1.rgb : (n < 0.85 ? c2.rgb : (n < 1.05 ? c3.rgb : c3.rgb * 0.45));
	} else if (pattern == 6) {
		// Hexagones avec joints (lumineux si emit > 0)
		vec2 h = uv * 1.6;
		vec2 a = mod(h, vec2(1.0, 1.732)) - vec2(0.5, 0.866);
		vec2 b = mod(h + vec2(0.5, 0.866), vec2(1.0, 1.732)) - vec2(0.5, 0.866);
		vec2 g = dot(a, a) < dot(b, b) ? a : b;
		vec2 q = abs(g);
		float d = max(q.x * 0.866 + q.y * 0.5, q.y);
		float edge = smoothstep(0.40, 0.46, d);
		col = mix(c1.rgb, c2.rgb, edge);
		em = edge;
		r = mix(r, 0.3, edge);
	} else if (pattern == 7) {
		// Fibre de carbone : tissage
		vec2 w = uv * 9.0;
		vec2 c = floor(w);
		vec2 f = fract(w);
		float dir = mod(c.x + c.y, 2.0);
		float s = dir < 0.5 ? sin(f.x * 3.1416) : sin(f.y * 3.1416);
		col = mix(c1.rgb, c2.rgb, s * 0.8);
		r = 0.25;
	} else if (pattern == 8) {
		// Acier de Damas : couches ondulées
		float v = sin(lp.x * scale * 6.0 + fbm(p * 1.5) * 9.0 + lp.y * scale * 3.0);
		float v2 = sin(lp.x * scale * 13.0 + fbm(p * 2.5) * 6.0);
		col = mix(c1.rgb, c2.rgb, clamp(smoothstep(-0.3, 0.5, v) * 0.9 + v2 * 0.15, 0.0, 1.0));
	} else if (pattern == 9) {
		// Marbre : veines fines
		float v = abs(sin(lp.x * scale * 1.5 + fbm(p * 1.2) * 8.0));
		float vein = 1.0 - smoothstep(0.0, 0.12, v);
		col = mix(c1.rgb * (0.92 + 0.08 * fbm(p * 3.0)), c2.rgb, vein);
		r = 0.15;
	} else if (pattern == 10) {
		// Écailles de dragon
		vec2 s = uv * 2.4;
		s.x += mod(floor(s.y), 2.0) * 0.5;
		vec2 f = fract(s) - vec2(0.5, 0.0);
		float d = length(f * vec2(1.0, 1.3));
		float rim = smoothstep(0.3, 0.55, d);
		col = mix(c1.rgb, c2.rgb, rim);
		col *= 0.75 + 0.35 * (1.0 - fract(s.y));
		em = rim * 0.4;
	} else if (pattern == 12) {
		// Léopard / jaguar : rosettes
		vec3 v = voronoi(uv * 1.6 + vec2(fbm(p) * 0.6));
		float spot = 1.0 - smoothstep(0.18, 0.3, v.x);
		float ring = smoothstep(0.12, 0.2, v.x) * (1.0 - smoothstep(0.3, 0.38, v.x));
		col = mix(c1.rgb, c3.rgb, spot);
		col = mix(col, c2.rgb, ring);
	} else if (pattern == 13) {
		// Bois : cernes
		float ring = fract(length(lp.yz * scale * 2.5) + fbm(p * vec3(0.3, 2.0, 2.0)) * 1.5 + lp.x * 0.8);
		col = mix(c1.rgb, c2.rgb, smoothstep(0.3, 0.9, ring));
		col *= 0.85 + 0.25 * noise3(vec3(lp.x * 2.0, lp.y * 120.0, lp.z * 120.0));
	} else if (pattern == 14) {
		// Métal brossé
		float s = noise3(vec3(lp.x * 3.0, lp.y * 260.0, lp.z * 260.0));
		col = c1.rgb * (0.85 + 0.25 * s);
	} else if (pattern == 15 || pattern == 24) {
		// Galaxie / matière noire : nébuleuse animée et étoiles
		vec3 q = p * 0.7 + vec3(t * 0.15, 0.0, t * 0.1);
		float n = fbm(q + fbm(q * 1.7) * 1.5);
		col = mix(c1.rgb, c2.rgb, smoothstep(0.35, 0.7, n));
		col = mix(col, c3.rgb, smoothstep(0.62, 0.85, fbm(q * 2.2 + vec3(5.0))));
		if (pattern == 24) {
			float sw = sin(atan(lp.y, lp.z) * 3.0 + length(lp.yz) * 60.0 - t * 2.0);
			col = mix(col, c3.rgb, smoothstep(0.7, 1.0, sw) * 0.6);
		}
		float star = step(0.985, hash1(floor(lp * 260.0)));
		star *= 0.5 + 0.5 * sin(TIME * 3.0 + hash1(floor(lp * 260.0) + vec3(4.0)) * 40.0);
		col += vec3(star);
		em = 0.35 + star;
		r = 0.25;
	} else if (pattern == 16) {
		// Lave : roche sombre et fissures brûlantes animées
		float n = fbm(p * 0.8 + vec3(0.0, t * 0.3, 0.0));
		float crack = 1.0 - smoothstep(0.0, 0.06, abs(n - 0.5));
		float heat = 0.6 + 0.4 * sin(t * 2.0 + n * 12.0);
		col = mix(c1.rgb * (0.6 + 0.6 * fbm(p * 2.0)), c2.rgb * heat, crack);
		em = crack * heat;
	} else if (pattern == 17) {
		// Grille néon avec impulsion qui parcourt l'arme
		vec2 g = abs(fract(uv * 1.2) - 0.5);
		float line = smoothstep(0.43, 0.48, max(g.x, g.y));
		float pulse = smoothstep(0.85, 1.0, sin(lp.x * 30.0 - TIME * 4.0 * max(speed, 0.5)));
		col = mix(c1.rgb, c2.rgb, line);
		em = line * (0.7 + pulse);
		r = 0.3;
	} else if (pattern == 18) {
		// Circuit imprimé
		vec2 g = uv * 2.5;
		vec2 c = floor(g);
		vec2 f = fract(g);
		float h = hash1(vec3(c, 2.0));
		float trace = h < 0.5 ? smoothstep(0.1, 0.0, abs(f.y - 0.5)) : smoothstep(0.1, 0.0, abs(f.x - 0.5));
		float pad = smoothstep(0.2, 0.1, length(f - 0.5)) * step(0.75, hash1(vec3(c, 5.0)));
		float lit = max(trace, pad);
		float pulse = 0.5 + 0.5 * sin(TIME * 3.0 - (c.x + c.y) * 0.7);
		col = mix(c1.rgb, c2.rgb, lit);
		em = lit * (0.4 + 0.8 * pulse);
	} else if (pattern == 19) {
		// Éclaboussures de peinture
		col = c1.rgb;
		col = mix(col, c2.rgb, step(0.62, fbm(p * 0.9 + vec3(3.0))));
		col = mix(col, c3.rgb, step(0.64, fbm(p * 1.1 + vec3(17.0))));
		col = mix(col, vec3(0.95), step(0.68, fbm(p * 1.4 + vec3(41.0))));
	} else if (pattern == 20) {
		// Bandes de course sur le dessus et les côtés
		float band = step(abs(abs(lp.z) - 0.012), 0.006) + step(abs(lp.y - 0.0), 0.005);
		col = mix(c1.rgb, c2.rgb, clamp(band, 0.0, 1.0));
		r = 0.2;
	} else if (pattern == 21) {
		// Holographique : la couleur change avec l'angle de vue
		float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float hue = fract(fres * 1.5 + lp.x * 3.0 + fbm(p) * 0.5 + TIME * 0.05);
		vec3 rgb = clamp(abs(mod(hue * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
		col = mix(c1.rgb, rgb, 0.85);
		em = 0.15;
		r = 0.15;
	} else if (pattern == 22) {
		// Cristal / diamant : facettes qui scintillent
		vec3 v = voronoi(uv * 2.2);
		float b = hash1(vec3(v.yz, 3.0));
		col = mix(c1.rgb, c2.rgb, b);
		float edge = 1.0 - smoothstep(0.0, 0.08, v.x);
		col = mix(col, c3.rgb, edge * 0.6);
		float sparkle = pow(max(0.0, sin(TIME * 2.0 + b * 30.0)), 24.0);
		em = 0.1 + sparkle * 0.8;
		r = 0.08;
	} else if (pattern == 23) {
		// Flammes : partent de l'arrière vers le canon
		float x = lp.x + 0.3;
		float n = fbm(vec3(lp.x * scale * 1.2 - TIME * 1.5 * max(speed, 0.4), lp.y * scale * 2.0, lp.z * scale * 2.0));
		float flame = smoothstep(0.0, 0.25, n * 0.9 - x * 1.4 + 0.25);
		col = mix(c1.rgb, mix(c3.rgb, c2.rgb, smoothstep(0.3, 0.9, flame)), flame);
		em = flame * 0.8;
	}

	// Garder un peu la différence entre les pièces (crosse, canon...)
	float lum = dot(base_color.rgb, vec3(0.299, 0.587, 0.114));
	float part = clamp(lum / 0.2, 0.45, 1.5);
	if (pattern != 0) {
		col *= mix(1.0, part, detail);
	}
	ALBEDO = clamp(col, 0.0, 1.0);
	METALLIC = m;
	ROUGHNESS = r;
	SPECULAR = 0.5 + 0.3 * (1.0 - r);
	EMISSION = col * em * emit;
}
