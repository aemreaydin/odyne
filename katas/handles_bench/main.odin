package main

// Tutor-run measurement for lesson m03-01 (concept): the cost of *referencing* objects.
// Same N objects, same visits, reached five ways:
//   (a) dense    — iterate the owning system's array directly (its private view)
//   (b) handle   — resolve index+generation through a slot table, in storage order
//   (c) handle   — same resolve, shuffled visit order (real-world boundary crossings)
//   (d) pointers — chase pointers to individually heap-allocated objects, shuffled
//                  (the C++-habit object graph)
//   (e) map      — hash lookup per visit (Bitsquid's "STL method" analog), shuffled
// (c)/(d)/(e) share one shuffled visit order — same access pattern, different storage.
// All five sums must match: correctness check, and it keeps -o:speed from eliding
// the loops (m02-01 lesson: read data-dependent results or lose the loop).
//
// The resolve path here is bench-local scaffolding for the READ side only — the
// m03-02 kata designs the real thing (lifecycle, freelist, bit budget, API).
//
// Run:  odin run katas/handles_bench -o:speed

import "core:fmt"
import "core:time"

N :: 100_000
PASSES :: 50

Entity :: struct {
	value: u64,
	pos:   [3]f32,
	flags: u32,
	id:    u64,
}
#assert(size_of(Entity) == 32)

Slot :: struct {
	gen:       u32,
	dense_idx: u32,
}

Handle :: struct {
	idx: u32,
	gen: u32,
}

xorshift :: proc(s: ^u64) -> u64 {
	x := s^
	x ~= x << 13
	x ~= x >> 7
	x ~= x << 17
	s^ = x
	return x
}

per_visit :: proc(start: time.Tick) -> f64 {
	return f64(time.duration_nanoseconds(time.tick_since(start))) / f64(N * PASSES)
}

main :: proc() {
	// the owning system's storage: dense objects + slot table + the handles "out there"
	dense := make([]Entity, N)
	defer delete(dense)
	slots := make([]Slot, N)
	defer delete(slots)
	handles := make([]Handle, N)
	defer delete(handles)
	for i in 0 ..< N {
		dense[i] = Entity {
			value = u64(i) * 0x9E3779B1 + 1,
			flags = u32(i),
			id    = u64(i),
		}
		slots[i] = Slot {
			gen       = u32(i % 7 + 1),
			dense_idx = u32(i),
		}
		handles[i] = Handle {
			idx = u32(i),
			gen = u32(i % 7 + 1),
		}
	}

	// shuffled visit order, shared by the random-access cases
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

	// the C++-habit graph: one heap allocation per object
	ptrs := make([]^Entity, N)
	for i in 0 ..< N {
		ptrs[i] = new(Entity)
		ptrs[i]^ = dense[i]
	}
	defer {
		for p in ptrs {
			free(p)
		}
		delete(ptrs)
	}

	// the "STL method" analog
	m := make(map[u32]Entity, N)
	defer delete(m)
	for i in 0 ..< N {
		m[u32(i)] = dense[i]
	}

	// ── (a) dense: the system's own hot loop ────────────────────────────────
	sum_a: u64
	t := time.tick_now()
	for _ in 0 ..< PASSES {
		for &e in dense {
			sum_a += e.value
		}
	}
	ns_a := per_visit(t)

	// ── (b) handle resolve, storage order ───────────────────────────────────
	sum_b: u64
	t = time.tick_now()
	for _ in 0 ..< PASSES {
		for h in handles {
			s := slots[h.idx]
			if s.gen == h.gen {
				sum_b += dense[s.dense_idx].value
			}
		}
	}
	ns_b := per_visit(t)

	// ── (c) handle resolve, shuffled visit order ────────────────────────────
	sum_c: u64
	t = time.tick_now()
	for _ in 0 ..< PASSES {
		for i in order {
			h := handles[i]
			s := slots[h.idx]
			if s.gen == h.gen {
				sum_c += dense[s.dense_idx].value
			}
		}
	}
	ns_c := per_visit(t)

	// ── (d) pointer chase, shuffled visit order ─────────────────────────────
	sum_d: u64
	t = time.tick_now()
	for _ in 0 ..< PASSES {
		for i in order {
			sum_d += ptrs[i].value
		}
	}
	ns_d := per_visit(t)

	// ── (e) map lookup, shuffled visit order ────────────────────────────────
	sum_e: u64
	t = time.tick_now()
	for _ in 0 ..< PASSES {
		for i in order {
			e := m[u32(i)]
			sum_e += e.value
		}
	}
	ns_e := per_visit(t)

	ok := sum_a == sum_b && sum_a == sum_c && sum_a == sum_d && sum_a == sum_e
	fmt.printfln("N=%d  passes=%d  entity=%dB  sums equal: %v", N, PASSES, size_of(Entity), ok)
	fmt.printfln("(a) dense iteration          : %6.2f ns/visit", ns_a)
	fmt.printfln("(b) handle resolve, in order : %6.2f ns/visit  (%.1fx dense)", ns_b, ns_b / ns_a)
	fmt.printfln("(c) handle resolve, shuffled : %6.2f ns/visit  (%.1fx dense)", ns_c, ns_c / ns_a)
	fmt.printfln("(d) pointer chase,  shuffled : %6.2f ns/visit  (%.1fx dense)", ns_d, ns_d / ns_a)
	fmt.printfln("(e) map lookup,     shuffled : %6.2f ns/visit  (%.1fx dense)", ns_e, ns_e / ns_a)
}
