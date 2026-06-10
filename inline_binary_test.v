module vmail_mime

fn test_parse_inline_binary_stream_does_not_keep_filename_like_javamail() {
	raw := 'Subject: Inline binary\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nBody\r\n--b1\r\nContent-Type: image/png; name="logo.png"\r\nContent-Disposition: inline; filename="logo.png"\r\nContent-Transfer-Encoding: base64\r\n\r\niVBORw0KGgo=\r\n--b1--\r\n'
	msg := parse(raw)!
	assert msg.text == 'Body'
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == ''
	assert msg.attachments[0].mime_type == 'image/png'
	assert msg.attachments[0].bytes == [u8(0x89), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
}
