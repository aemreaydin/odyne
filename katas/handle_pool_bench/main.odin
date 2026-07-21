package main

// Tutor-run measurement for lesson m03-02: the generational handle pool.
// Four axes from the lesson's Performance notes, all on 32 B Entity payloads
// (same shape as the m03-01 baseline, so resolve numbers compare directly):
//   (a) add / remove / churn ns-per-op — vs the m02-03 pool and the heap
//   (b) resolve ns/visit, storage order and shuffled — vs m03-01 (0.41 / 1.61)
//   (c) resolve with ~half the handles stale — prices the failed-check branch
//   (d) full iteration (slice) at high and low occupancy — the packed payoff
//
// Every timed read loop accumulates a data-dependent sum, checked against an
// expected value: correctness, and it stops -o:speed from eliding the loop
// (m02-01 lesson). Carry the RATIOS, not the ns — the ~8 MB working set is
// cache-flattered.
//
// Run:  odin run katas/handle_pool_bench -o:speed

import "core:fmt"
import "core:mem"
import "core:time"
import hp "../handle_pool"
import pool "../pool"

N :: 100_000
PASSES :: 50
LOW :: N / 10 // low-occupancy live count (10%)

Entity :: struct {
	value: u64,
	pos:   [3]f32,
	flags: u32,
	id:    u64,
}
#assert(size_of(Entity) == 32)

xorshift :: proc(s: ^u64) -> u64 {
	x := s^
	x ~= x << 13
	x ~= x >> 7
	x ~= x << 17
	s^ = x
	return x
}

entity_for :: proc(i: int) -> Entity {
	return Entity{value = u64(i) * 0x9E3779B1 + 1, flags = u32(i), id = u64(i)}
}

per_visit :: proc(start: time.Tick, visits: int) -> f64 {
	return f64(time.duration_nanoseconds(time.tick_since(start))) / f64(visits)
}

main :: proc() {
	hpp: hp.Handle_Pool(Entity)
	hp.init(&hpp, N)
	defer hp.destroy(&hpp)

	hs := make([]hp.Handle, N)
	defer delete(hs)

	// expected sum of all live values (for the correctness/anti-elision checks)
	expected_full: u64
	for i in 0 ..< N {
		expected_full += entity_for(i).value
	}

	// shuffled visit order shared by the random-access resolve case
	order := make([]int, N)
	defer delete(order)
	for i in 0 ..< N {
		order[i] = i
	}
	seed: u64 = 0x9E3779B97F4A7C15
	for i := N - 1; i > 0; i -= 1 {
		j := int(xorshift(&seed) % u64(i + 1))
		order[i], order[j] = order[j], order[i]
	}

	// ─────────────────────────── phase R: reads (full pool) ───────────────────
	for i in 0 ..< N {
		hs[i], _ = hp.add(&hpp, entity_for(i))
	}

	// (b) resolve in storage order
	sum_b: u64
	t := time.tick_now()
	for _ in 0 ..< PASSES {
		for h in hs {
			ptr, _ := hp.get_ptr(&hpp, h)
			if ptr != nil {
				sum_b += ptr.value
			}
		}
	}
	ns_b := per_visit(t, N * PASSES)

	// (b) resolve shuffled
	sum_bs: u64
	t = time.tick_now()
	for _ in 0 ..< PASSES {
		for i in order {
			ptr, _ := hp.get_ptr(&hpp, hs[i])
			if ptr != nil {
				sum_bs += ptr.value
			}
		}
	}
	ns_bs := per_visit(t, N * PASSES)

	// (c) stale-mix: ~half the handles bumped one generation → must fail the check
	mixed := make([]hp.Handle, N)
	defer delete(mixed)
	expected_mixed: u64
	mseed: u64 = 0xD1B54A32D192ED03
	for i in 0 ..< N {
		if xorshift(&mseed) & 1 == 0 {
			mixed[i] = hs[i] // live
			expected_mixed += entity_for(i).value
		} else {
			mixed[i] = hp.Handle(u64(hs[i]) + 0x1_0000_0000) // gen+1 → stale
		}
	}
	sum_c: u64
	t = time.tick_now()
	for _ in 0 ..< PASSES {
		for h in mixed {
			ptr, _ := hp.get_ptr(&hpp, h)
			if ptr != nil {
				sum_c += ptr.value
			}
		}
	}
	ns_c := per_visit(t, N * PASSES)

	// (d) iteration at high occupancy (all N live) — plain dense slice walk
	sum_dh: u64
	t = time.tick_now()
	for _ in 0 ..< PASSES {
		for &e in hp.slice(&hpp) {
			sum_dh += e.value
		}
	}
	ns_dh := per_visit(t, N * PASSES)

	// (d) iteration at low occupancy — drop down to LOW live, walk again
	for i in LOW ..< N {
		hp.remove(&hpp, hs[i])
	}
	sum_dl: u64
	t = time.tick_now()
	for _ in 0 ..< PASSES {
		for &e in hp.slice(&hpp) {
			sum_dl += e.value
		}
	}
	ns_dl := per_visit(t, LOW * PASSES)

	// ─────────────────────── phase A: add / remove / churn ────────────────────
	hp.clear(&hpp)
	fill_start := time.tick_now()
	for i in 0 ..< N {
		hs[i], _ = hp.add(&hpp, entity_for(i))
	}
	hp_add := per_visit(fill_start, N)

	drain_start := time.tick_now()
	for i in 0 ..< N {
		hp.remove(&hpp, hs[i])
	}
	hp_remove := per_visit(drain_start, N)

	hp.clear(&hpp)
	csum: u64
	ent := entity_for(7)
	churn_start := time.tick_now()
	for _ in 0 ..< N {
		h, _ := hp.add(&hpp, ent)
		csum += u64(h)
		hp.remove(&hpp, h)
	}
	hp_churn := per_visit(churn_start, N)

	// m02-03 pool churn (32 B blocks), same machine/run
	backing := make([]byte, (N + 16) * size_of(Entity))
	defer delete(backing)
	bp: pool.Pool
	pool.init(&bp, backing, size_of(Entity), 8)
	pa := pool.allocator(&bp)
	pcsum: uintptr
	pool_start := time.tick_now()
	for _ in 0 ..< N {
		b, _ := mem.alloc_bytes(size_of(Entity), 8, pa)
		pcsum += uintptr(raw_data(b))
		mem.free_bytes(b, pa)
	}
	pool_churn := per_visit(pool_start, N)

	// heap new/free churn of the same size
	hcsum: uintptr
	heap_start := time.tick_now()
	for _ in 0 ..< N {
		b, _ := mem.alloc_bytes(size_of(Entity), 8)
		hcsum += uintptr(raw_data(b))
		mem.free_bytes(b)
	}
	heap_churn := per_visit(heap_start, N)

	ok :=
		sum_b == expected_full * PASSES &&
		sum_bs == expected_full * PASSES &&
		sum_c == expected_mixed * PASSES &&
		sum_dh == expected_full * PASSES &&
		sum_dl > 0 &&
		csum > 0 &&
		pcsum > 0 &&
		hcsum > 0

	fmt.printfln("N=%d  passes=%d  entity=%dB  sums OK: %v", N, PASSES, size_of(Entity), ok)
	fmt.println("── (a) lifecycle ───────────────────────────────────")
	fmt.printfln("hp add            : %6.2f ns/op    (pool 11.5 baseline)", hp_add)
	fmt.printfln("hp remove         : %6.2f ns/op    (pool  4.5 baseline)", hp_remove)
	fmt.printfln("hp add+remove     : %6.2f ns/cycle", hp_churn)
	fmt.printfln("pool alloc+free   : %6.2f ns/cycle", pool_churn)
	fmt.printfln("heap alloc+free   : %6.2f ns/cycle", heap_churn)
	fmt.printfln("  hp vs pool churn: %.2fx   hp vs heap churn: %.2fx", pool_churn / hp_churn, heap_churn / hp_churn)
	fmt.println("── (b/c) resolve ───────────────────────────────────")
	fmt.printfln("resolve in-order  : %6.2f ns/visit (m03-01: 0.41)", ns_b)
	fmt.printfln("resolve shuffled  : %6.2f ns/visit (m03-01: 1.61)", ns_bs)
	fmt.printfln("resolve ~50%% stale: %6.2f ns/visit", ns_c)
	fmt.println("── (d) iteration ───────────────────────────────────")
	fmt.printfln("iterate  high occ : %6.2f ns/visit (%d live)", ns_dh, N)
	fmt.printfln("iterate  low  occ : %6.2f ns/visit (%d live)", ns_dl, LOW)
}
