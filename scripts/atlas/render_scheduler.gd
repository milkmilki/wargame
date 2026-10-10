extends Node
## One numerical worker; GPU resources and scene publication stay on the main thread.
const FRAME_BUDGET_USEC := 4000
const LODS := [.5,.70710678,1.,1.3,1.35,1.8,2.,2.82842712,3.,3.325,4.,5.65685425,5.7,8.]
var versions := {}
var worker := Thread.new()
var mutex := Mutex.new()
var wake := Semaphore.new()
var jobs: Array = []
var results: Array = []
var publishing: Array = []
var running := false
var closing := false
var active_jobs := 0
var serial := 0
var cache_budget := 256*1024*1024
var cache_bytes := 0
var cache := {}
var uploads := 0
var stale_results := 0
var max_publish_usec := 0
var profile: Array = []
var geometry_pending := {}
var geometry_users := {}

func release_geometry(key: String) -> void:
	geometry_users[key] = maxi(0,int(geometry_users.get(key,0))-1)
	if cache.has(key): cache[key].pinned = geometry_users[key]>0
	trim()

func _ready() -> void:
	worker.start(work)

static func choose_lod(zoom_value: float,current: int = -1) -> int:
	if current>=0:
		var lo: float = 0. if current==0 else sqrt(LODS[current-1]*LODS[current])*.95
		var hi: float = INF if current==LODS.size()-1 else sqrt(LODS[current]*LODS[current+1])*1.05
		if zoom_value>=lo and zoom_value<=hi: return current
	var best := 0; var distance := INF
	for i in range(LODS.size()):
		var d := absf(log(maxf(.01,zoom_value)/LODS[i]))
		if d<distance: best = i; distance = d
	return best

func invalidate(domain: String) -> int:
	versions[domain] = int(versions.get(domain,0))+1
	mutex.lock()
	var previous := jobs.size(); jobs = jobs.filter(func(job): return job.domain!=domain)
	active_jobs -= previous-jobs.size(); mutex.unlock()
	return versions[domain]

func submit(domain: String,calculate: Callable,publish: Callable,priority: int = 0,tag: String = "") -> void:
	serial += 1
	var job := {"domain":domain,"version":versions.get(domain,0),"calculate":calculate,"publish":publish,"priority":priority,"serial":serial,"tag":tag}
	mutex.lock(); jobs.append(job); active_jobs += 1; mutex.unlock(); wake.post()

func cancel_queued(domain: String,keep: Dictionary) -> Array:
	var removed: Array = []
	mutex.lock()
	jobs = jobs.filter(func(job):
		if job.domain==domain and not job.tag.is_empty() and not keep.has(job.tag): removed.append(job.tag); return false
		return true)
	active_jobs -= removed.size(); mutex.unlock(); return removed

func enqueue(publish: Callable,priority: int = 0,domain: String = "view") -> void:
	serial += 1
	publishing.append({"domain":domain,"version":versions.get(domain,0),"publish":publish,"priority":priority,"serial":serial,"direct":true})

func work() -> void:
	while true:
		wake.wait(); mutex.lock()
		if closing: mutex.unlock(); return
		if jobs.is_empty(): mutex.unlock(); continue
		jobs.sort_custom(func(a,b): return a.serial<b.serial if a.priority==b.priority else a.priority<b.priority)
		var job: Dictionary = jobs.pop_front(); mutex.unlock()
		var begin := Time.get_ticks_usec(); job.value = job.calculate.call(); job.compute_usec = Time.get_ticks_usec()-begin; job.erase("calculate")
		mutex.lock(); results.append(job); active_jobs -= 1; mutex.unlock()

func _process(_delta: float) -> void:
	mutex.lock(); publishing.append_array(results); results.clear(); mutex.unlock()
	publishing.sort_custom(func(a,b): return a.serial<b.serial if a.priority==b.priority else a.priority<b.priority)
	var start := Time.get_ticks_usec()
	while not publishing.is_empty() and Time.get_ticks_usec()-start<FRAME_BUDGET_USEC:
		var job: Dictionary = publishing.pop_front()
		if job.version!=versions.get(job.domain,0): stale_results += 1; continue
		var begin := Time.get_ticks_usec()
		if job.get("direct",false): job.publish.call()
		else: job.publish.call(job.value)
		max_publish_usec = maxi(max_publish_usec,Time.get_ticks_usec()-begin); uploads += 1
		profile.append({"domain":job.domain,"compute_usec":job.get("compute_usec",0),"publish_usec":Time.get_ticks_usec()-begin})
		if profile.size()>2000: profile.pop_front()

func pending() -> bool:
	mutex.lock(); var count := active_jobs+results.size(); mutex.unlock()
	return count>0 or not publishing.is_empty()

func remember(key: String,value: Variant,bytes: int,pinned: bool = false) -> void:
	forget(key); cache[key] = {"value":value,"bytes":bytes,"used":Time.get_ticks_usec(),"pinned":pinned}; cache_bytes += bytes
	trim()

func touch(key: String) -> Variant:
	if not cache.has(key): return null
	cache[key].used = Time.get_ticks_usec(); return cache[key].value

func forget(key: String) -> void:
	if cache.has(key): cache_bytes -= cache[key].bytes; cache.erase(key)

func trim() -> void:
	while cache_bytes>cache_budget:
		var oldest := ""; var stamp := 9223372036854775807
		for key in cache:
			if not cache[key].pinned and cache[key].used<stamp: oldest = key; stamp = cache[key].used
		if oldest.is_empty(): break
		forget(oldest)

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	if not worker.is_started(): return
	mutex.lock(); closing = true; jobs.clear(); mutex.unlock(); wake.post(); worker.wait_to_finish()

func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE: shutdown()
