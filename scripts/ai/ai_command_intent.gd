class_name AiCommandIntent
extends RefCounted
## 一个 AI 决策批次内的不可变军事命令意图。

var nation_id: int
var sequence: int
var army: Army
var candidate: ActionCandidate
var prepared_path: Array[int]
var path_prevalidated: bool
## 同一事务的命令必须全部实际提交成功，调用方才提交其状态 payload。
## -1 表示普通独立命令。
var transaction_id: int = -1


static func make(
	source_army: Army,
	action: ActionCandidate,
	nation_sequence: int,
	path: Array[int],
	has_validated_path: bool,
	command_transaction_id: int = -1
) -> AiCommandIntent:
	var intent := AiCommandIntent.new()
	intent.nation_id = source_army.owner_nation
	intent.sequence = nation_sequence
	intent.army = source_army
	intent.candidate = action
	intent.prepared_path = path.duplicate()
	intent.path_prevalidated = has_validated_path
	intent.transaction_id = command_transaction_id
	return intent
