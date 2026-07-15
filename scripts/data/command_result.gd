class_name CommandResult
extends RefCounted
## Structured outcome shared by player UI, managers, and rival AI. Domain
## managers keep authority; this value adds explainable command metadata.

var ok: bool = false
var code: StringName = &"ok"
var message: String = ""
var payload: Variant = null

var estimated_cost: float = 0.0
var actual_cost: float = 0.0
var explanation: String = ""
var permission_category: StringName = &"recommend"
var reversible: bool = false
var undo_token: String = ""
var idempotency_key: String = ""
var duplicate: bool = false
var actor_kind: StringName = &"player"
var actor_id: String = ""
var executed_at: int = -1
var metadata: Dictionary = {}


static func good(result_payload: Variant = null) -> CommandResult:
	var result := CommandResult.new()
	result.ok = true
	result.payload = result_payload
	return result


static func fail(fail_code: StringName, fail_message: String = "") -> CommandResult:
	var result := CommandResult.new()
	result.ok = false
	result.code = fail_code
	result.message = fail_message
	result.explanation = fail_message
	return result


func with_command_metadata(values: Dictionary) -> CommandResult:
	estimated_cost = float(values.get("estimated_cost", estimated_cost))
	actual_cost = float(values.get("actual_cost", actual_cost))
	explanation = str(values.get("explanation", explanation))
	permission_category = StringName(values.get("permission_category", permission_category))
	reversible = bool(values.get("reversible", reversible))
	undo_token = str(values.get("undo_token", undo_token))
	idempotency_key = str(values.get("idempotency_key", idempotency_key))
	duplicate = bool(values.get("duplicate", duplicate))
	actor_kind = StringName(values.get("actor_kind", actor_kind))
	actor_id = str(values.get("actor_id", actor_id))
	executed_at = int(values.get("executed_at", executed_at))
	var saved_metadata: Variant = values.get("metadata", metadata)
	if saved_metadata is Dictionary:
		metadata = saved_metadata.duplicate(true)
	return self


func as_dictionary() -> Dictionary:
	return {
		"ok": ok,
		"code": code,
		"message": message,
		"payload": payload,
		"estimated_cost": estimated_cost,
		"actual_cost": actual_cost,
		"explanation": explanation,
		"permission_category": permission_category,
		"reversible": reversible,
		"undo_token": undo_token,
		"idempotency_key": idempotency_key,
		"duplicate": duplicate,
		"actor_kind": actor_kind,
		"actor_id": actor_id,
		"executed_at": executed_at,
		"metadata": metadata.duplicate(true),
	}
