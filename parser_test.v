module vmail_mime

import encoding.base64

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

fn test_parse_rfc2231_continued_attachment_name() {
	raw := 'Subject: Continued filename\r\nContent-Type: multipart/mixed; boundary="outer"\r\n\r\n--outer\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nBody\r\n--outer\r\nContent-Type: application/pdf; name*0*=UTF-8\'\'quarterly%20; name*1*=%E2%82%AC%20; name*2=report.pdf\r\nContent-Disposition: attachment; filename*0*=UTF-8\'\'quarterly%20; filename*1*=%E2%82%AC%20; filename*2=report.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\nUERG\r\n--outer--\r\n'
	msg := parse(raw)!
	euro := [u8(0xe2), u8(0x82), u8(0xac)].bytestr()
	assert msg.text == 'Body'
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == 'quarterly ' + euro + ' report.pdf'
	assert msg.attachments[0].mime_type == 'application/pdf'
	assert msg.attachments[0].bytes.bytestr() == 'PDF'
}

fn test_parse_rfc2231_language_attachment_name() {
	raw := 'Subject: Language filename\r\nContent-Type: multipart/mixed; boundary="outer"\r\n\r\n--outer\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nBody\r\n--outer\r\nContent-Type: application/pdf; name*=UTF-8\'en\'%E2%82%AC%20rates.pdf\r\nContent-Disposition: attachment; filename*=UTF-8\'en\'%E2%82%AC%20rates.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\nUERG\r\n--outer--\r\n'
	msg := parse(raw)!
	euro := [u8(0xe2), u8(0x82), u8(0xac)].bytestr()
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == euro + ' rates.pdf'
	assert msg.attachments[0].mime_type == 'application/pdf'
	assert msg.attachments[0].bytes.bytestr() == 'PDF'
}

fn test_parse_latin1_and_windows1252_charsets() {
	raw := 'Subject: =?ISO-8859-1?Q?Ol=E1_Se=F1or?=\r\nContent-Type: multipart/mixed; boundary="outer"\r\n\r\n--outer\r\nContent-Type: text/plain; charset=ISO-8859-1\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nOl=E1 Se=F1or\r\n--outer\r\nContent-Type: application/pdf; name*=ISO-8859-1\'\'caf%E9.pdf\r\nContent-Disposition: attachment; filename*=ISO-8859-1\'\'caf%E9.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\nUERG\r\n--outer--\r\n'
	msg := parse(raw)!
	assert msg.subject == [u8(0x4f), 0x6c, 0xc3, 0xa1, 0x20, 0x53, 0x65, 0xc3, 0xb1, 0x6f, 0x72].bytestr()
	assert msg.text == msg.subject
	assert msg.attachments[0].name == [u8(0x63), 0x61, 0x66, 0xc3, 0xa9, 0x2e, 0x70, 0x64, 0x66].bytestr()
	cp1252 := decode_charset_bytes([u8(0x93), 0x48, 0x69, 0x94], 'windows-1252')
	assert cp1252 == [u8(0xe2), 0x80, 0x9c, 0x48, 0x69, 0xe2, 0x80, 0x9d].bytestr()
}

fn test_parse_multipart_boundary_and_base64_whitespace() {
	raw := 'Subject: Whitespace sample\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1 \t\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nBody\r\n--b1  \t\r\nContent-Type: application/octet-stream; name="ws.bin"\r\nContent-Disposition: attachment; filename="ws.bin"\r\nContent-Transfer-Encoding: base64\r\n\r\nQU JD\tRA==\r\n--b1-- \t\r\n'
	msg := parse(raw)!
	assert msg.text == 'Body'
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == 'ws.bin'
	assert msg.attachments[0].bytes.bytestr() == 'ABCD'
}

fn test_parse_message_rfc822_attachment_preserves_eml_file() {
	forwarded := 'Subject: Forwarded inner\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nInner body\r\n'
	raw :=
		'Subject: Outer\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nOuter body\r\n--b1\r\nContent-Type: message/rfc822; name="forwarded.eml"\r\nContent-Disposition: attachment; filename="forwarded.eml"\r\nContent-Transfer-Encoding: base64\r\n\r\n' +
		base64.encode(forwarded.bytes()) + '\r\n--b1--\r\n'
	msg := parse(raw)!
	assert msg.text == 'Outer body'
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == 'forwarded.eml'
	assert msg.attachments[0].mime_type == 'message/rfc822'
	assert msg.attachments[0].bytes.bytestr() == forwarded
}

fn test_parse_inline_message_rfc822_recurses_decoded_body() {
	nested := 'Subject: Forwarded inner\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nInner body\r\n'
	raw :=
		'Subject: Outer\r\nContent-Type: message/rfc822\r\nContent-Transfer-Encoding: base64\r\n\r\n' +
		base64.encode(nested.bytes()) + '\r\n'
	msg := parse(raw)!
	assert msg.subject == 'Outer'
	assert msg.text == 'Inner body'
	assert msg.attachments.len == 0
}

fn test_parse_rfc2822_date_stamp() {
	raw := 'Date: Tue, 02 Jan 2024 03:04:05 +0000\r\nSubject: Dated message\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nBody\r\n'
	msg := parse(raw)!
	assert msg.date == 'Tue, 02 Jan 2024 03:04:05 +0000'
	assert msg.date_stamp == '2024-01-02 03:04:05'
	assert mail_date_stamp('bad date') == ''
}
