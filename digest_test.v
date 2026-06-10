module vmail_mime

fn test_parse_multipart_digest_defaults_children_to_message_rfc822_like_javamail() {
	nested := 'Subject: Inner digest\r\n\r\nDigest body\r\n'
	raw :=
		'Subject: Digest wrapper\r\nContent-Type: multipart/digest; boundary="digest"\r\n\r\n--digest\r\n' +
		nested + '--digest--\r\n'
	msg := parse(raw)!
	assert msg.subject == 'Digest wrapper'
	assert msg.text == 'Digest body'
	assert msg.attachments.len == 0
}
