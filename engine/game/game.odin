package game

import "core:fmt"
import "engine:core"
import "engine:platform"
import "engine:render"

boot :: proc() -> string {
	return fmt.tprintf(
		"odyne %s | platform: %s | render: %s | game: stub",
		core.version(),
		platform.info(),
		render.info(),
	)
}
