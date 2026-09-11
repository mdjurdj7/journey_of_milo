shader_type canvas_item;
// Applied to Enemy's VisualRoot (see enemy.tscn) - a CanvasGroup, not a
// plain Node2D. A CanvasGroup renders every child (however many separate
// Polygon2D/Sprite2D pieces a given creature's silhouette is actually
// built from - a real EnemyData.visual_scene, or the plain fallback
// octagon) into ONE isolated, pre-composited alpha buffer BEFORE this
// shader ever runs, and SCREEN_TEXTURE inside a CanvasGroup's own
// material reads THAT buffer specifically (not the framebuffer at
// large) - this is what makes the outline below trace the creature's
// actual silhouette AS A WHOLE, with no seams at internal piece
// boundaries, and with zero per-enemy setup: every enemy gets this for
// free just by existing under the shared VisualRoot, regardless of how
// many pieces or what kind of node its own art turns out to be.
//
// Off by default (rim_intensity 0.0) - see enemy.gd's own set_snap_
// highlight(), which is the only thing that ever changes it, toggling
// between 0.0 and rim_intensity's own configured value. Nothing here
// decides WHEN to show a rim, only HOW.
//
// SOFTENED (2026-08-26, "hard white sticker" fix) - the original version
// took a MAX over the ring samples: any transparent pixel with silhouette
// ANYWHERE within rim_thickness_px was outline_alpha = 1.0, full stop -
// a step function, not a gradient, which is exactly what read as a die-
// cut edge regardless of how low rim_intensity or rim_color's own alpha
// went. Switched to an AVERAGE (see rim_falloff's own doc) - a pixel
// right at the edge (most of the ring still overlaps the shape) reads
// strong, a pixel near the outer edge of the ring (only a sliver of the
// ring overlaps) reads faint, with real gradation between - a feather,
// not a boundary. Directional weighting (rim_directional_amount/rim_
// light_direction) is layered on the SAME averaging pass, not a second
// technique, so the "cheap to do" bar in the brief that asked for this
// was about extending the existing sampling loop with one more term per
// sample (a dot product), not adding new sampling infrastructure.

uniform vec4 rim_color : source_color = vec4(0.88, 0.84, 0.74, 0.55);
// Alpha is the "reduced alpha" lever the brief specifically asked for -
// even at outline_alpha/rim_intensity = 1.0 (dead center of the rim, at
// full strength), the highlighted pixel is only ever a 55/45 blend
// toward this color, never fully opaque - "light catching an edge," not
// a drawn, opaque line. RGB nudged warmer/softer from the original
// (0.96, 0.93, 0.86) - still not literally white, but this pass's own
// brief flagged the original as reading too close to it in practice.
uniform float rim_thickness_px : hint_range(0.0, 24.0) = 1.5;
// Cut from 4.0 to a near-hairline width, per the brief's own "closer to
// a hairline than the current band" - this is also the ring-sample
// radius the averaging below reads distance from, so a thinner value
// here also means the soft-falloff zone (see rim_falloff) sits tighter
// against the actual edge instead of spreading into a wider halo.
uniform float rim_intensity : hint_range(0.0, 1.0) = 0.0;
uniform bool outline_only = false;
// Added 2026-08-26 (armed-card z-order fix) - a SECOND material instance
// (enemy.gd's rim_highlight_overlay, a separate CanvasGroup duplicating
// the same visual_scene geometry, NOT a second use of visual_container's
// own material) sets this true so its own output is JUST the rim glow,
// fully transparent everywhere else - including over the creature's own
// solid body, which normally shows through unchanged (see fragment()'s
// own note on why: base.a is 1.0 there, so rim_mix is already 0 in
// EITHER mode). That's what makes it safe to elevate ONLY this overlay's
// z_index above an armed card while set_snap_highlight() is active,
// leaving visual_container itself - the actual creature sprite - always
// under the card, same as any non-highlighted enemy. false (default)
// keeps visual_container's own live material behaving exactly as before
// - the two never need to differ in any other parameter.
uniform float rim_falloff : hint_range(0.1, 4.0) = 1.6;
// Applied as pow(outline_alpha, rim_falloff) AFTER the ring average
// below - the average alone already turns the old hard step into a
// gradient (a pixel where roughly half the ring overlaps the shape lands
// near 0.5, not a binary 0 or 1), but this exponent is the dedicated
// "how gradual" dial the brief asked to keep tunable on its own: values
// above 1.0 push the curve DOWN in the middle of its range (a narrower,
// more sharply-cut-off band), values below 1.0 push it UP (a wider,
// softer-reading spread). 1.0 would leave the raw averaged gradient
// untouched.
uniform float rim_directional_amount : hint_range(0.0, 1.0) = 0.6;
// 0.0 = every ring sample counts equally (the old uniform-all-around
// rim, just now soft-edged instead of hard-edged) - the brief's own
// fallback if directionality "complicates the shader meaningfully." It
// doesn't: this is one extra dot product per existing sample, no new
// texture reads, so it's implemented rather than skipped, but kept as
// its own dial (not hardcoded to 1.0) specifically so it CAN be dialed
// back to that uniform fallback from the Inspector with no shader edit,
// if a fully-directional rim ever reads as too uneven in a real fight.
uniform vec2 rim_light_direction = vec2(0.35, 1.0);
// The direction, in screen space (+Y is DOWN), a ring sample has to
// point to count as "fully lit" at rim_directional_amount = 1.0 - NOT
// the direction light comes FROM, but the direction FROM a lit rim
// pixel TOWARD the silhouette's own bulk. (0.35, 1.0) points mostly
// downward with a rightward lean, which is what makes pixels sitting
// ABOVE and to the LEFT of the silhouette (whose own shape-ward look
// direction points down-and-right, matching this vector) read as the
// "lit" side - "stronger on top and one side," per the brief. Left
// unnormalized as a plain vec2 (normalized in fragment() below) so this
// stays simple to eyeball-retune in the Inspector without also having
// to keep its length equal to 1 by hand.
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
// Godot 4.7 removed the old implicit SCREEN_TEXTURE built-in - this
// explicit declaration (the engine's own suggested fix, confirmed via a
// headless load of this exact shader) is what makes fragment()'s own
// SCREEN_TEXTURE reads below resolve to this CanvasGroup's own pre-
// composited buffer again, same meaning as before, just spelled out.

const float TWO_PI = 6.283185307;
const int RIM_SAMPLES = 12;
// A ring of sample points at rim_thickness_px, not a box/cross
// kernel - traces a round edge cleanly regardless of which direction
// the silhouette's own edge happens to run, without the "thicker on
// diagonals" artifact a small square kernel would show at this radius.

void fragment() {
	vec4 base = texture(SCREEN_TEXTURE, SCREEN_UV);
	float outline_alpha = 0.0;
	if (rim_intensity > 0.0) {
		vec2 light_dir = normalize(rim_light_direction);
		float weighted_sum = 0.0;
		float weight_total = 0.0;
		for (int i = 0; i < RIM_SAMPLES; i++) {
			float angle = float(i) / float(RIM_SAMPLES) * TWO_PI;
			vec2 dir = vec2(cos(angle), sin(angle));
			vec2 offset = dir * rim_thickness_px * SCREEN_PIXEL_SIZE;
			float sample_alpha = texture(SCREEN_TEXTURE, SCREEN_UV + offset).a;
			// mix(1.0, ..., 0.0) at rim_directional_amount = 0 collapses
			// every sample's weight to 1.0 - the plain, uniform average,
			// no directional bias at all.
			float directional_weight = mix(1.0, max(dot(dir, light_dir), 0.0), rim_directional_amount);
			weighted_sum += sample_alpha * directional_weight;
			weight_total += directional_weight;
		}
		// AVERAGE, not max (see this shader's own 2026-08-26 header note
		// on why that's the actual fix for the hard-edge complaint) -
		// weight_total, not RIM_SAMPLES, is the correct divisor once
		// directional weighting makes each sample's contribution unequal;
		// the max() guards the fully-directional, shadow-side case where
		// nearly every weight could round to ~0.
		outline_alpha = weighted_sum / max(weight_total, 0.001);
		outline_alpha = pow(outline_alpha, rim_falloff);
	}
	// Only draws in the TRANSPARENT margin just outside the silhouette's
	// own edge ((1.0 - base.a) term) - the creature's own fill is never
	// tinted, only the halo around it.
	float rim_mix = outline_alpha * rim_intensity * (1.0 - base.a);
	if (outline_only) {
		// The whole point of this mode (see its own uniform doc) - no
		// base creature pixels at all, just the rim glow's own alpha, so
		// this can be drawn as an independent, elevatable layer with
		// nothing else in it to accidentally show above something that
		// should stay hidden behind an armed card.
		COLOR = vec4(rim_color.rgb, rim_mix * rim_color.a);
	} else {
		COLOR = mix(base, vec4(rim_color.rgb, rim_color.a), rim_mix);
	}
}
