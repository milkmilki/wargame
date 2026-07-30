class_name ActionCandidate
extends RefCounted
## 可解释的 AI 候选行动。

enum Kind {
	NONE,
	HOLD,
	REINFORCE,
	MERGE,
	ATTACK,
	RETREAT,
	CREATE_ARMY,
	DISBAND_ARMY,
}

var kind: int = Kind.NONE
var target_city: int = -1
var target_edge_a: int = -1
var target_edge_b: int = -1
var score: float = -INF
var minimum_commit_days: int = 10
var reason: String = ""


static func make(
	action_kind: int,
	action_score: float,
	action_reason: String,
	city_id: int = -1
) -> ActionCandidate:
	var candidate := ActionCandidate.new()
	candidate.kind = action_kind
	candidate.score = action_score
	candidate.reason = action_reason
	candidate.target_city = city_id
	return candidate
