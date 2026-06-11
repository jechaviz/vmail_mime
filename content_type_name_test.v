module vmail_mime

fn test_parse_binary_part_without_disposition_uses_content_type_name_like_javamail() {
	raw := 'Subject: CT name only\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nBody\r\n--b1\r\nContent-Type: application/pdf; name="ct-only.pdf"\r\nContent-Transfer-Encoding: base64\r\n\r\nUERG\r\n--b1--\r\n'
	msg := parse(raw)!
	assert msg.text == 'Body'
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == 'ct-only.pdf'
	assert msg.attachments[0].mime_type == 'application/pdf'
	assert msg.attachments[0].bytes.bytestr() == 'PDF'
}
