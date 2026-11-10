class_name ReputationLog
extends RefCounted
## Stub of the reputation_event log (CAPTURE.md). Every capture choice logs one event with
## a severity and an atrocity flag. Nothing reads the log yet: the diplomacy and
## reputation tasks will turn it into opinion changes.

## Each event: {"type", "actor", "victim", "severity", "atrocity", plus extra keys
## ("city", "cell") from the caller}. Oldest first.
var events: Array[Dictionary] = []


func log_event(type: String, actor: int, victim: int, severity: int, atrocity: bool,
		extra := {}) -> Dictionary:
	var event := {"type": type, "actor": actor, "victim": victim,
			"severity": severity, "atrocity": atrocity}
	event.merge(extra)
	events.append(event)
	print("reputation_event: %s" % [event])
	return event


## Number of events of `type` ("" counts all).
func count(type := "") -> int:
	if type == "":
		return events.size()
	return events.filter(func(e: Dictionary) -> bool: return e.type == type).size()


## Events flagged atrocity, for `actor` (-1 = any actor).
func atrocities(actor := -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if e.atrocity and (actor < 0 or e.actor == actor):
			out.append(e)
	return out
