module vmail_mime

pub struct Attachment {
pub:
	name      string
	mime_type string
	bytes     []u8
}

pub struct Message {
pub:
	subject     string
	text        string
	attachments []Attachment
}

struct ParsedMessage {
mut:
	subject     string
	text        string
	attachments []Attachment
}
