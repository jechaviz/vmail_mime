module vmail_mime

fn test_parse_windows1255_subject_body_and_attachment_name() {
	raw := 'Subject: =?windows-1255?Q?=F9=EC=E5=ED_=A4?=\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=windows-1255\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n=F9=EC=E5=ED =A4\r\n--b1\r\nContent-Type: application/pdf; name*=windows-1255\'\'%F9%EC%E5%ED%20%A4.pdf\r\nContent-Disposition: attachment; filename*=windows-1255\'\'%F9%EC%E5%ED%20%A4.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\nUERG\r\n--b1--\r\n'
	expected := hebrew_shalom_shekel()
	msg := parse(raw)!
	assert msg.subject == expected
	assert msg.text == expected
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == expected + '.pdf'
	assert msg.attachments[0].bytes.bytestr() == 'PDF'
	assert decode_charset_bytes([u8(0xf9), 0xec, 0xe5, 0xed, 0x20, 0xa4], 'cp1255') == expected
	assert decode_charset_bytes([u8(0x80), 0x93, 0xa4, 0xc0, 0xd4, 0xfd, 0xfe], 'windows1255') == [
		u8(0xe2),
		0x82,
		0xac,
		0xe2,
		0x80,
		0x9c,
		0xe2,
		0x82,
		0xaa,
		0xd6,
		0xb0,
		0xd7,
		0xb0,
		0xe2,
		0x80,
		0x8e,
		0xe2,
		0x80,
		0x8f,
	].bytestr()
}

fn hebrew_shalom_shekel() string {
	return [
		u8(0xd7),
		0xa9,
		0xd7,
		0x9c,
		0xd7,
		0x95,
		0xd7,
		0x9d,
		0x20,
		0xe2,
		0x82,
		0xaa,
	].bytestr()
}
