package testbed

import "core:fmt"
import "engine:game"

main :: proc() {
	fmt.println(game.boot())
}

