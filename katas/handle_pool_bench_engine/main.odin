package main

// Tutor-run measurement for lesson m03-03: the graduated handle pool in engine:core.
// Re-runs m03-02's axes against the engine package (no-regression check), through TWO
// instantiations — the ready-made hp.Handle and a caller-distinct handle type — to price
// the distinct-type tax (expected: zero; `distinct` changes the type, not the code).
//
// Baselines (m03-02 kata, same machine): add 4.5 / remove 3.0 / churn 3.9 ns;
// resolve 1.08 in-order / 3.8 shuffled / 4.2 half-stale ns/visit; iterate 0.30 / 0.24.
// Entity stays 32 B — the kata's `id` filler field became the embedded handle — so
// per-visit numbers compare directly. Sums are checked (correctness + anti-elision).
//
// Run:  odin run katas/handle_pool_bench_engine -o:speed -collection:engine=engine

import "core:fmt"
import "core:time"
import hp "engine:core/containers/handle_pool"

N :: 100_000
PASSES :: 50
LOW :: N / 10 // low-occupancy live count (10%)

Bench_Handle :: distinct u64 // the caller-distinct variant

Entity_Shared :: struct {
	value:  u64,
	pos:    [3]f32,
	flags:  u32,
	handle: hp.Handle,
}

Entity_Distinct :: struct {
	value:  u64,
	pos:    [3]f32,
	flags:  u32,
	handle: Bench_Handle,
}

#assert(size_of(Entity_Shared) == 32)
#assert(size_of(Entity_Distinct) == 32)

xorshift :: proc(s: ^u64) -> u64 {
	x := s^
	x ~= x << 13
	x ~= x >> 7
	x ~= x << 17
	s^ = x
	return x
}

per_visit :: proc(start: time.Tick, visits: int) -> f64 {
	return f64(time.duration_nanoseconds(time.tick_since(start))) / f64(visits)
}

value_for :: proc(i: int) -> u64 {
	return u64(i) * 0x9E3779B1 + 1
}

bench :: proc($T: typeid, $HT: typeid, label: string) {
	pool: hp.Handle_Pool(T, HT)
	hp.init(&pool, N)
	defer hp.destroy(&pool)

	hs := make([]HT, N)
	defer delete(hs)

	expected_full: u64
	for i in 0 ..< N {
		expected_full += value_for(i)
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

	// ─── reads (full pool) ────────────────────────────────────────────────────
	for i in 0 ..< N {
		e: T
		e.value = value_for(i)
		e.flags = u32(i)
		hs[i], _ = hp.add(&pool, e)
	}

	sum_b: u64
	t := time.tick_now()
	for _ in 0 ..< PASSES {
		for h in hs {
			ptr, _ := hp.get_ptr(&pool, h)
			if ptr != nil {
				sum_b += ptr.value
			}
		}
	}
	ns_b := per_visit(t, N * PASSES)

	sum_bs: u64
	t = time.tick_now()
	for _ in 0 ..< PASSES {
		for i in order {
			ptr, _ := hp.get_ptr(&pool, hs[i])
			if ptr != nil {
				sum_bs += ptr.value
			}
		}
	}
	ns_bs := per_visit(t, N * PASSES)

	// stale-mix: ~half the handles bumped one generation → must fail the check
	mixed := make([]HT, N)
	defer delete(mixed)
	expected_mixed: u64
	mseed: u64 = 0xD1B54A32D192ED03
	for i in 0 ..< N {
		if xorshift(&mseed) & 1 == 0 {
			mixed[i] = hs[i] // live
			expected_mixed += value_for(i)
		} else {
			mixed[i] = HT(u64(hs[i]) + 0x1_0000_0000) // gen+1 → stale
		}
	}
	sum_c: u64
	t = time.tick_now()
	for _ in 0 ..< PASSES {
		for h in mixed {
			ptr, _ := hp.get_ptr(&pool, h)
			if ptr != nil {
				sum_c += ptr.value
			}
		}
	}
	ns_c := per_visit(t, N * PASSES)

	// iteration at high occupancy (all N live) — plain dense slice walk
	sum_dh: u64
	t = time.tick_now()
	for _ in 0 ..< PASSES {
		for &e in hp.slice(&pool) {
			sum_dh += e.value
		}
	}
	ns_dh := per_visit(t, N * PASSES)

	// iteration at low occupancy — drop down to LOW live, walk again
	for i in LOW ..< N {
		hp.remove(&pool, hs[i])
	}
	sum_dl: u64
	t = time.tick_now()
	for _ in 0 ..< PASSES {
		for &e in hp.slice(&pool) {
			sum_dl += e.value
		}
	}
	ns_dl := per_visit(t, LOW * PASSES)

	// ─── lifecycle: add / remove / churn ──────────────────────────────────────
	hp.clear(&pool)
	fill_start := time.tick_now()
	for i in 0 ..< N {
		e: T
		e.value = value_for(i)
		hs[i], _ = hp.add(&pool, e)
	}
	ns_add := per_visit(fill_start, N)

	drain_start := time.tick_now()
	for i in 0 ..< N {
		hp.remove(&pool, hs[i])
	}
	ns_remove := per_visit(drain_start, N)

	hp.clear(&pool)
	csum: u64
	ent: T
	ent.value = value_for(7)
	churn_start := time.tick_now()
	for _ in 0 ..< N {
		h, _ := hp.add(&pool, ent)
		csum += u64(h)
		hp.remove(&pool, h)
	}
	ns_churn := per_visit(churn_start, N)

	ok :=
		sum_b == expected_full * PASSES &&
		sum_bs == expected_full * PASSES &&
		sum_c == expected_mixed * PASSES &&
		sum_dh == expected_full * PASSES &&
		sum_dl > 0 &&
		csum > 0

	fmt.printfln("── %s  (sums OK: %v) ──────────────────", label, ok)
	fmt.printfln("add               : %6.2f ns/op    (kata 4.5)", ns_add)
	fmt.printfln("remove            : %6.2f ns/op    (kata 3.0)", ns_remove)
	fmt.printfln("add+remove churn  : %6.2f ns/cycle (kata 3.9)", ns_churn)
	fmt.printfln("resolve in-order  : %6.2f ns/visit (kata 1.08)", ns_b)
	fmt.printfln("resolve shuffled  : %6.2f ns/visit (kata 3.8)", ns_bs)
	fmt.printfln("resolve ~50%% stale: %6.2f ns/visit (kata 4.2)", ns_c)
	fmt.printfln("iterate  high occ : %6.2f ns/visit (kata 0.30)", ns_dh)
	fmt.printfln("iterate  low  occ : %6.2f ns/visit (kata 0.24)", ns_dl)
}

main :: proc() {
	fmt.printfln("N=%d  passes=%d  entity=32B", N, PASSES)
	bench(Entity_Shared, hp.Handle, "shared hp.Handle")
	bench(Entity_Distinct, Bench_Handle, "distinct Bench_Handle")
}
