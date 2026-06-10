module vmail_mime

fn test_parse_multipart_attachment_container_preserved_like_javamail() {
	raw := 'Subject: Outer\r\nContent-Type: multipart/mixed; boundary=outer\r\n\r\n--outer\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nBody\r\n--outer\r\nContent-Type: multipart/mixed; boundary=inner\r\nContent-Disposition: attachment; filename=bundle.eml\r\n\r\n--inner\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nNested body\r\n--inner\r\nContent-Type: text/plain; name=inner.txt\r\nContent-Disposition: attachment; filename=inner.txt\r\n\r\nInner file\r\n--inner--\r\n--outer--\r\n'
	msg := parse(raw)!
	assert msg.text == 'Body'
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == 'bundle.eml'
	assert msg.attachments[0].mime_type == 'multipart/mixed'
	assert msg.attachments[0].bytes.bytestr().contains('--inner')
	assert msg.attachments[0].bytes.bytestr().contains('inner.txt')
}
