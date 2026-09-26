shader_type canvas_item;

// A card's art on its face (CardView's Art node), through the one shared
// battle/card_art_material.tres - tune it there and every card follows,
// live. Contrast first, then tint:
//   colour = mix(bone, art, art_contrast) * art_tint
// art_contrast pulls the art toward the card's own bone rather than
// toward grey, so dark art lifts toward the paper it's printed on and
// pale art barely moves. art_tint multiplies (white = off). At the
// defaults (1.0, white) the art is exactly as painted. COLOR arrives as
// the texture already sampled with the node's own filter (mipmapped) and
// its modulate, so the card's unplayable fade still applies on top.

uniform float art_contrast : hint_range(0.0, 1.0) = 1.0;
uniform vec4 art_tint : source_color = vec4(1.0);
// The card's field colour - CardView.field_color. Keep the two matched.
uniform vec4 bone : source_color = vec4(0.94, 0.91, 0.86, 1.0);

void fragment() {
	vec3 pulled = mix(bone.rgb, COLOR.rgb, art_contrast);
	COLOR.rgb = clamp(pulled * art_tint.rgb, 0.0, 1.0);
}
