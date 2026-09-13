extends RefCounted
## Shared action ids / Chinese labels for remote-player right-click menu.

enum Action {
	HEADER = 0,
	VIEW = 1,
	INVITE = 2,
	TRADE = 3,
	WHISPER = 4,
	FOLLOW = 5,
}


static func item_defs() -> Array:
	## Ordered menu rows after the disabled name header.
	return [
		{"id": Action.VIEW, "text": "查看"},
		{"id": Action.INVITE, "text": "邀请组队"},
		{"id": Action.TRADE, "text": "交易"},
		{"id": Action.WHISPER, "text": "密语"},
		{"id": Action.FOLLOW, "text": "跟随"},
	]


static func label_for(action_id: int) -> String:
	for d in item_defs():
		if int(d.get("id", -1)) == action_id:
			return str(d.get("text", ""))
	return ""
