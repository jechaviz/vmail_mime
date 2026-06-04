module vmail_mime

fn test_parse_plain_text_quoted_printable() {
	msg :=
		parse('Subject: =?UTF-8?Q?Hello_from_EML?=\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nLine one=0ALine two\r\n')!
	assert msg.subject == 'Hello from EML'
	assert msg.text.contains('Line one')
	assert msg.text.contains('Line two')
	assert msg.attachments.len == 0
}

fn test_parse_nested_multipart_and_encoded_attachment_name() {
	raw := 'Subject: Nested sample\r\nContent-Type: multipart/mixed; boundary="outer"\r\n\r\n--outer\r\nContent-Type: multipart/alternative; boundary="inner"\r\n\r\n--inner\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n<p>Please &amp; review</p>\r\n--inner--\r\n--outer\r\nContent-Type: text/plain; name*=UTF-8\'\'report%20final.txt\r\nContent-Disposition: attachment; filename="=?UTF-8?Q?report_final.txt?="\r\nContent-Transfer-Encoding: base64\r\n\r\nYXR0YWNobWVudCBib2R5\r\n--outer--\r\n'
	msg := parse(raw)!
	assert msg.subject == 'Nested sample'
	assert msg.text == 'Please & review'
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == 'report final.txt'
	assert msg.attachments[0].mime_type == 'text/plain'
	assert msg.attachments[0].bytes.bytestr() == 'attachment body'
}
