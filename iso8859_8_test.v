module vmail_mime

fn test_parse_iso_8859_8_subject_body_and_attachment_name() {
	raw := 'Subject: =?ISO-8859-8?Q?=F9=EC=E5=ED?=\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=ISO-8859-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n=F9=EC=E5=ED\r\n--b1\r\nContent-Type: application/pdf; name*=ISO-8859-8\'\'%F9%EC%E5%ED.pdf\r\nContent-Disposition: attachment; filename*=ISO-8859-8\'\'%F9%EC%E5%ED.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\nUERG\r\n--b1--\r\n'
	expected := hebrew_shalom()
	msg := parse(raw)!
	assert msg.subject == expected
	assert msg.text == expected
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == expected + '.pdf'
	assert msg.attachments[0].bytes.bytestr() == 'PDF'
	assert decode_charset_bytes([u8(0xf9), 0xec, 0xe5, 0xed], 'hebrew') == expected
	assert decode_charset_bytes([u8(0xaa), 0xba, 0xdf, 0xfd, 0xfe], 'csisolatinhebrew') == [
		u8(0xc3),
		0x97,
		0xc3,
		0xb7,
		0xe2,
		0x80,
		0x97,
		0xe2,
		0x80,
		0x8e,
		0xe2,
		0x80,
		0x8f,
	].bytestr()
}

fn hebrew_shalom() string {
	return [
		u8(0xd7),
		0xa9,
		0xd7,
		0x9c,
		0xd7,
		0x95,
		0xd7,
		0x9d,
	].bytestr()
}
