shader_type canvas_item;


void fragment() {
	vec4 color = texture(TEXTURE, UV);

	if (color.r == 0.0) {
		color.a = 0.0;
	} 

	COLOR = color;
}

