class_name CommandResult
extends RefCounted
## Structured outcome for company business commands, so the AI and the UI
## receive identical validation instead of bare bools.

var ok: bool = false
var code: StringName = &"ok"
var message: String = ""
var payload: Variant = null


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
	return result
