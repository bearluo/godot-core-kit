shader_type canvas_item;
// KitTransition.MASK 遮罩:灰度图越暗越早被遮住。公式与 KitTransition.mask_alpha 一致,改一处要同步另一处。

uniform sampler2D mask : hint_default_white;
uniform float progress = 0.0;
uniform float smoothness = 0.05;
uniform bool invert = false;
uniform vec4 cover_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	float m = texture(mask, UV).r;
	if (invert) {
		m = 1.0 - m;
	}
	float s = max(smoothness, 0.0001);
	float a = smoothstep(m - s, m + s, mix(-s, 1.0 + s, progress));
	COLOR = vec4(cover_color.rgb, cover_color.a * a);
}
