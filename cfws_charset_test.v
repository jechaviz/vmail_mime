module vmail_mime

fn test_parse_charset_parameter_comments_like_javamail() {
	raw := 'Subject: Charset CFWS\r\nContent-Type: text/plain; charset=ISO-8859-1 (scanner)\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nOl=E1\r\n'
	msg := parse(raw)!
	assert msg.text == [u8(0x4f), 0x6c, 0xc3, 0xa1].bytestr()
	assert msg.attachments.len == 0
}
