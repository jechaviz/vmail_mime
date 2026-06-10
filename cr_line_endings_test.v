module vmail_mime

fn test_parse_cr_only_line_endings_like_javamail() {
	raw := 'Subject: CR only\rContent-Type: multipart/mixed; boundary="b1"\r\r--b1\rContent-Type: text/plain; charset=UTF-8\r\rBody one\r--b1\rContent-Type: text/plain; name="note.txt"\rContent-Disposition: attachment; filename="note.txt"\rContent-Transfer-Encoding: base64\r\rQ1IgYXR0YWNobWVudA==\r--b1--\r'
	msg := parse(raw)!
	assert msg.subject == 'CR only'
	assert msg.text == 'Body one'
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == 'note.txt'
	assert msg.attachments[0].mime_type == 'text/plain'
	assert msg.attachments[0].bytes.bytestr() == 'CR attachment'
}
