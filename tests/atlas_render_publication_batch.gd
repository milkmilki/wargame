extends SceneTree
## Main-thread resource uploads are interruptible while visible revisions remain
## atomic: obsolete partial uploads must never commit over a newer version.
const Scheduler = preload("res://scripts/atlas/render_scheduler.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1; printerr("RENDER_BATCH_FAIL ",message)
func run():
	var scheduler := Scheduler.new(); root.add_child(scheduler); scheduler.set_process(false)
	if not scheduler.has_method("enqueue_batch"):
		check(false, "publication supports interruptible batches with a final atomic commit")
		root.remove_child(scheduler); scheduler.free(); finish(); return
	scheduler.set("frame_budget_usec",2500)
	var displayed := {"revision":1,"values":[-1]}
	var committed: Array[int] = []
	var prepared: Array = []
	var executed: Array = []
	var steps: Array[Callable] = []
	for i in range(8):
		steps.append(func():
			OS.delay_usec(1500)
			prepared.append(i); executed.append(i))
	scheduler.call("enqueue_batch",steps,func(): displayed.revision = 2; displayed.values = prepared.duplicate(); committed.append(2),0,"political","first")
	check(scheduler.pending(), "an unstarted batch is included in pending publication work")
	scheduler._process(0.)
	check(not executed.is_empty() and executed.size() < 8, "one frame executes useful upload work and yields before finishing the full batch")
	check(displayed.revision == 1 and displayed.values == [-1], "partially uploaded political resources retain the old visible revision")
	var frames := 1
	while scheduler.pending() and frames < 32:
		scheduler._process(0.); frames += 1
	check(not scheduler.pending() and frames > 1, "a batch finishes over multiple bounded publication passes")
	check(executed == range(8), "upload steps preserve their data dependencies and execute exactly once")
	check(displayed.revision == 2 and displayed.values == range(8), "the completed batch publishes all resources together")
	# Cancel after actual upload work has begun; keep the previous visible map.
	prepared.clear(); executed.clear(); steps.clear()
	for i in range(8):
		steps.append(func(): OS.delay_usec(1500); prepared.append(i); executed.append(i))
	scheduler.call("enqueue_batch",steps,func(): displayed.revision = 3; displayed.values = prepared.duplicate(); committed.append(3),0,"political","cancelled")
	scheduler._process(0.)
	var partial := executed.size()
	check(partial > 0 and partial < 8, "the cancellation fixture reaches a real partially prepared batch")
	check(displayed.revision == 2, "an interrupted newer batch does not reveal partial resources")
	scheduler.invalidate("political")
	var newest_values: Array = []
	var newest_steps: Array[Callable] = [func(): newest_values.append(90),func(): newest_values.append(91)]
	scheduler.call("enqueue_batch",newest_steps,func(): displayed.revision = 4; displayed.values = newest_values.duplicate(); committed.append(4),0,"political","latest")
	frames = 0
	while scheduler.pending() and frames < 32:
		scheduler._process(0.); frames += 1
	check(not scheduler.pending(), "invalidated partial uploads cannot keep rendering pending forever")
	check(executed.size() == partial, "obsolete resource steps stop after invalidation")
	check(displayed.revision == 4 and displayed.values == [90,91], "the latest batch wins without an obsolete intermediate commit")
	check(committed == [2,4], "the cancelled revision never becomes visible even briefly")
	# A step itself may discover a new requested version. Validate before commit
	# as well as before dispatch so this cannot expose a stale map.
	var cancelled_commit := {"calls":0}
	var reentrant_steps: Array[Callable] = [func(): scheduler.invalidate("political")]
	scheduler.call("enqueue_batch",reentrant_steps,func(): cancelled_commit.calls += 1,0,"political","reentrant")
	for i in range(4): scheduler._process(0.)
	check(cancelled_commit.calls == 0, "invalidation during the final upload prevents its stale commit")
	var empty_calls := {"calls":0}
	scheduler.call("enqueue_batch",[] as Array[Callable],func(): empty_calls.calls += 1,0,"empty","empty")
	for i in range(4): scheduler._process(0.)
	check(empty_calls.calls == 1, "a revision requiring no uploads still commits exactly once")
	root.remove_child(scheduler); scheduler.free(); finish()
func finish():
	print("ATLAS_RENDER_PUBLICATION_BATCH checks=",checks," failures=",failures)
	quit(1 if failures else 0)
