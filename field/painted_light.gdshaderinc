// The painted look's light (wanderer_painted.gdshader): the light wrapped
// past the terminator and the shadows on the surface eased. Included by
// the painted shader and by the passes laid over a painted body
// (stork_sac.gdshader, underfoot_cover.gdshader), so a pass lights
// exactly as the body under it - at these defaults, which every painted
// enemy keeps; the Wanderer sets his own on his material.

// How far the light wraps past the terminator: 0 is plain Lambert, 1
// lights everything but the exact back. Scaled so a surface facing the
// light is fully lit at any wrap.
uniform float wrap : hint_range(0.0, 1.0) = 0.6;

// How much of a shadow lands on him: 1 is as dark as anywhere else, 0
// none. Every shadow on him at once (his own and anything else's) -
// light() only sees them combined.
uniform float self_shadow_strength : hint_range(0.0, 1.0) = 0.5;

void light() {
	float lit = max((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0);
	float shadow = mix(1.0, ATTENUATION, self_shadow_strength);
	DIFFUSE_LIGHT += LIGHT_COLOR * shadow * lit / PI;
}
