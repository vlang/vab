module main

import gg
import gx

const points = [f32(200.0), 200.0, 200.0, 100.0, 400.0, 100.0, 400.0, 300.0]

struct App {
mut:
	gg &gg.Context = unsafe { nil }
	i u8
}

fn main() {
	mut app := &App{}
	app.gg = gg.new_context(
		bg_color: gx.rgb(174, 198, 255)
		width: 768
		height: 1024
		window_title: 'Curve'
		frame_fn: frame
		user_data: app
		sample_count: 4 // higher quality curves
	)
	app.gg.run()
}

fn frame(mut app App) {
	app.gg.begin()
	o := app.i++ % 256
	app.gg.draw_cubic_bezier(points, gx.rgb(o, 255 - o, 255))
	app.gg.end()
}
