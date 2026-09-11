shader_type canvas_item;

uniform vec4 top_color : source_color = vec4(0.55, 0.6, 0.65, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.18, 0.2, 0.26, 1.0);
uniform float height = 120.0;

varying vec2 local_pos;

void vertex() {
    local_pos = VERTEX;
}

void fragment() {
    float t = clamp(-local_pos.y / height, 0.0, 1.0);
    COLOR = mix(bottom_color, top_color, t);
}
