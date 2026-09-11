shader_type canvas_item;
// Shared by every textured silhouette element that wants internal value
// variation instead of a single flat tint (Art Direction Bible §7: dark
// areas should retain a relationship with the palette, not read as
// uniform) - one .gdshader resource, a fresh ShaderMaterial per instance
// so top_color/bottom_color can differ per element (see field_room.gd's
// _apply_vertical_shade()). A gradient multiply only - no lighting model,
// no normals, no rim.

uniform vec4 top_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 bottom_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Where the opaque content actually sits within the texture's own UV.y
// span (2026-09-01, overhang-contrast pass) - most callers' textures fill
// their own UV space edge-to-edge, so the 0.0/1.0 defaults make the remap
// below a no-op and reproduce the original full-texture ramp exactly. A
// texture with real transparent padding (e.g. treasure_overhang.png,
// opaque only across UV.y ~0.017-0.476) would otherwise only ever receive
// the fraction of the top_color/bottom_color swing that falls within its
// own opaque band - see field_room.gd's own _apply_vertical_shade() for
// where non-default bounds get passed in.
uniform float content_uv_top : hint_range(0.0, 1.0) = 0.0;
uniform float content_uv_bottom : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// UV.y runs 0 (top of the sprite, its crest) to 1 (bottom, its base) -
	// mix(top_color, bottom_color, UV.y) lands top_color at the crest and
	// bottom_color at the base, a lit-top/shadowed-base read. Remapped
	// through content_uv_top/content_uv_bottom first so the full color
	// swing always lands across the opaque content, not the padded texture.
	float t = clamp((UV.y - content_uv_top) / max(content_uv_bottom - content_uv_top, 0.0001), 0.0, 1.0);
	vec4 gradient = mix(top_color, bottom_color, t);
	// COLOR going into fragment() already carries the node's modulate (see
	// _apply_vertical_shade()'s own doc for why modulate is left holding
	// only alpha, never RGB, once this shader is attached) - multiplying
	// it in here reproduces the engine's own default texture*modulate
	// behavior before the gradient is layered on top of it. Alpha comes
	// from the texture (and modulate's alpha) only - the gradient's own
	// alpha channel is never read.
	COLOR = vec4(tex.rgb * COLOR.rgb * gradient.rgb, tex.a * COLOR.a);
}
