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

fn test_parse_adjacent_rfc2047_encoded_words() {
	msg :=
		parse('Subject: =?UTF-8?Q?Quarterly?= =?UTF-8?Q?_Report?=\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nBody\r\n')!
	assert msg.subject == 'Quarterly Report'
	assert decode_rfc2047_header('Prefix =?UTF-8?Q?Quarterly?= =?UTF-8?Q?_Report?= suffix') == 'Prefix Quarterly Report suffix'
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

fn test_parse_folded_rfc2231_continuation_decodes_charset_after_join() {
	raw := 'Subject: Folded filename\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nBody\r\n--b1\r\nContent-Type: application/pdf;\r\n\tname*0*=ISO-8859-1\'en\'wrong%20;\r\n\tname*1*=name.pdf\r\nContent-Disposition: attachment;\r\n\tfilename*0*=ISO-8859-1\'en\'caf;\r\n\tfilename*1*=%E9%20;\r\n\tfilename*2=report.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\nUERG\r\n--b1--\r\n'
	msg := parse(raw)!
	e_acute := [u8(0xc3), u8(0xa9)].bytestr()
	assert msg.text == 'Body'
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == 'caf' + e_acute + ' report.pdf'
	assert msg.attachments[0].bytes.bytestr() == 'PDF'
}

fn test_parse_filename_preferred_over_continued_content_type_name() {
	raw := 'Subject: Filename priority\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nBody\r\n--b1\r\nContent-Type: application/octet-stream; name*0*=UTF-8\'\'content%20; name*1*=type.bin\r\nContent-Disposition: attachment; filename="disposition.bin"\r\nContent-Transfer-Encoding: base64\r\n\r\nQUJD\r\n--b1--\r\n'
	msg := parse(raw)!
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == 'disposition.bin'
	assert msg.attachments[0].bytes.bytestr() == 'ABC'
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

fn test_parse_iso_8859_2_subject_body_and_attachment_name() {
	raw := 'Subject: =?ISO-8859-2?Q?Za=BF=F3=B3=E6_g=EA=B6l=B1_ja=BC=F1?=\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=ISO-8859-2\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nZa=BF=F3=B3=E6 g=EA=B6l=B1 ja=BC=F1\r\n--b1\r\nContent-Type: application/pdf; name*=ISO-8859-2\'\'cze%B6%E6.pdf\r\nContent-Disposition: attachment; filename*=ISO-8859-2\'\'cze%B6%E6.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\nUERG\r\n--b1--\r\n'
	expected := [
		u8(0x5a),
		0x61,
		0xc5,
		0xbc,
		0xc3,
		0xb3,
		0xc5,
		0x82,
		0xc4,
		0x87,
		0x20,
		0x67,
		0xc4,
		0x99,
		0xc5,
		0x9b,
		0x6c,
		0xc4,
		0x85,
		0x20,
		0x6a,
		0x61,
		0xc5,
		0xba,
		0xc5,
		0x84,
	].bytestr()
	attachment_name :=
		[u8(0x63), 0x7a, 0x65, 0xc5, 0x9b, 0xc4, 0x87, 0x2e, 0x70, 0x64, 0x66].bytestr()
	latin2_samples := [u8(0xc4), 0x84, 0xc5, 0x81, 0xc5, 0x9a, 0xc5, 0xb9].bytestr()
	msg := parse(raw)!
	assert msg.subject == expected
	assert msg.text == expected
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == attachment_name
	assert msg.attachments[0].bytes.bytestr() == 'PDF'
	assert decode_charset_bytes([u8(0xa1), 0xa3, 0xa6, 0xac], 'latin2') == latin2_samples
}

fn test_parse_windows1250_subject_body_attachment_and_aliases() {
	raw := 'Subject: =?windows-1250?Q?Za=BF=F3=B3=E6_g=EA=9Cl=B9_ja=9F=F1?=\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=windows1250\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nZa=BF=F3=B3=E6 g=EA=9Cl=B9 ja=9F=F1\r\n--b1\r\nContent-Type: application/pdf; name*=cp1250\'\'cze%9C%E6.pdf\r\nContent-Disposition: attachment; filename*=cp1250\'\'cze%9C%E6.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\nUERG\r\n--b1--\r\n'
	expected := [
		u8(0x5a),
		0x61,
		0xc5,
		0xbc,
		0xc3,
		0xb3,
		0xc5,
		0x82,
		0xc4,
		0x87,
		0x20,
		0x67,
		0xc4,
		0x99,
		0xc5,
		0x9b,
		0x6c,
		0xc4,
		0x85,
		0x20,
		0x6a,
		0x61,
		0xc5,
		0xba,
		0xc5,
		0x84,
	].bytestr()
	attachment_name :=
		[u8(0x63), 0x7a, 0x65, 0xc5, 0x9b, 0xc4, 0x87, 0x2e, 0x70, 0x64, 0x66].bytestr()
	cp1250_samples := decode_charset_bytes([u8(0x8c), 0x9c, 0x8f, 0x9f, 0x93, 0x48, 0x69, 0x94],
		'cp1250')
	msg := parse(raw)!
	assert msg.subject == expected
	assert msg.text == expected
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == attachment_name
	assert msg.attachments[0].bytes.bytestr() == 'PDF'
	assert cp1250_samples == [
		u8(0xc5),
		0x9a,
		0xc5,
		0x9b,
		0xc5,
		0xb9,
		0xc5,
		0xba,
		0xe2,
		0x80,
		0x9c,
		0x48,
		0x69,
		0xe2,
		0x80,
		0x9d,
	].bytestr()
}

fn test_parse_iso_8859_15_subject_body_and_attachment_name() {
	raw := 'Subject: =?ISO-8859-15?Q?Prix_=A4?=\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=ISO-8859-15\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nPrix =A4\r\n--b1\r\nContent-Type: application/pdf; name*=ISO-8859-15\'\'prix%20%A4.pdf\r\nContent-Disposition: attachment; filename*=ISO-8859-15\'\'prix%20%A4.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\nUERG\r\n--b1--\r\n'
	euro := [u8(0xe2), 0x82, 0xac].bytestr()
	msg := parse(raw)!
	assert msg.subject == 'Prix ' + euro
	assert msg.text == 'Prix ' + euro
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == 'prix ' + euro + '.pdf'
	assert msg.attachments[0].bytes.bytestr() == 'PDF'
	assert decode_charset_bytes([u8(0xa6), 0xa8, 0xb4, 0xb8, 0xbc, 0xbd, 0xbe], 'latin9') == [
		u8(0xc5),
		0xa0,
		0xc5,
		0xa1,
		0xc5,
		0xbd,
		0xc5,
		0xbe,
		0xc5,
		0x92,
		0xc5,
		0x93,
		0xc5,
		0xb8,
	].bytestr()
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
	assert mail_date_stamp('21 Feb 2018 15:11:01 +0100') == '2018-02-21 15:11:01'
	assert mail_date_stamp('Wed, 21 Feb 2018 15:11:01 GMT') == '2018-02-21 15:11:01'
	assert mail_date_stamp('bad date') == ''
}
