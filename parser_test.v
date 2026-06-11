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

fn test_parse_multipart_attachment_container_preserved_like_javamail() {
	raw := 'Subject: Outer\r\nContent-Type: multipart/mixed; boundary=outer\r\n\r\n--outer\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nBody\r\n--outer\r\nContent-Type: multipart/mixed; boundary=inner\r\nContent-Disposition: attachment; filename=bundle.eml\r\n\r\n--inner\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nNested body\r\n--inner\r\nContent-Type: text/plain; name=inner.txt\r\nContent-Disposition: attachment; filename=inner.txt\r\n\r\nInner file\r\n--inner--\r\n--outer--\r\n'
	msg := parse(raw)!
	assert msg.text == 'Body'
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == 'bundle.eml'
	assert msg.attachments[0].mime_type == 'multipart/mixed'
	payload := msg.attachments[0].bytes.bytestr()
	assert payload.contains('--inner')
	assert payload.contains('inner.txt')
}

fn test_parse_html_numeric_entities_like_javamail_jsoup() {
	raw := 'Subject: HTML numeric entities\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n<p>Total &#8364;42 and hex &#x20AC;7 &apos;ok&apos;</p>\r\n'
	msg := parse(raw)!
	euro := [u8(0xe2), 0x82, 0xac].bytestr()
	assert msg.text == "Total ${euro}42 and hex ${euro}7 'ok'"
	assert msg.attachments.len == 0
}

fn test_parse_inline_text_plain_with_filename_is_body_like_javamail() {
	raw := 'Subject: Inline note\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=UTF-8; name="note.txt"\r\nContent-Disposition: inline; filename="note.txt"\r\n\r\nInline note body\r\n--b1--\r\n'
	msg := parse(raw)!
	assert msg.text == 'Inline note body'
	assert msg.attachments.len == 0
}

fn test_parse_inline_disposition_param_named_attachment_stays_body_like_javamail() {
	raw := 'Subject: Inline note\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=UTF-8; name="note.txt"\r\nContent-Disposition: inline; filename="note.txt"; comment="not an attachment"\r\n\r\nInline note body\r\n--b1--\r\n'
	msg := parse(raw)!
	assert msg.text == 'Inline note body'
	assert msg.attachments.len == 0
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

fn test_parse_quoted_parameter_escapes_semicolon_and_quote() {
	escaped_quote := [u8(`\\`), u8(`"`)].bytestr()
	encoded_name := 'quarterly ' + escaped_quote + 'Q1; final' + escaped_quote + '.pdf'
	raw :=
		'Subject: Quoted filename\r\nContent-Type: multipart/mixed; boundary="outer"\r\n\r\n--outer\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nBody\r\n--outer\r\nContent-Type: application/pdf\r\nContent-Disposition: attachment; filename="' +
		encoded_name + '"\r\nContent-Transfer-Encoding: base64\r\n\r\nUERG\r\n--outer--\r\n'
	msg := parse(raw)!
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == 'quarterly "Q1; final".pdf'
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

fn test_parse_turkish_charsets_like_javamail() {
	raw := 'Subject: =?ISO-8859-9?Q?=DDstanbul_=D0=DD=DE_=F0=FD=FE?=\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=latin5\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n=DDstanbul =D0=DD=DE =F0=FD=FE\r\n--b1\r\nContent-Type: application/pdf; name*=ISO-8859-9\'\'turk%E7e%20%D0%DD%DE.pdf\r\nContent-Disposition: attachment; filename*=ISO-8859-9\'\'turk%E7e%20%D0%DD%DE.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\nUERG\r\n--b1--\r\n'
	expected := turkish_istanbul_letters()
	msg := parse(raw)!
	assert msg.subject == expected
	assert msg.text == expected
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == turkish_file_pdf()
	assert msg.attachments[0].bytes.bytestr() == 'PDF'
	assert decode_charset_bytes([u8(0xd0), 0xdd, 0xde, 0x20, 0xf0, 0xfd, 0xfe], 'csisolatin5') == turkish_letter_sample()
	assert decode_charset_bytes([u8(0x93), 0xdd, 0x94, 0xfd], 'cp1254') == [
		u8(0xe2),
		0x80,
		0x9c,
		0xc4,
		0xb0,
		0xe2,
		0x80,
		0x9d,
		0xc4,
		0xb1,
	].bytestr()
}

fn test_parse_iso_8859_7_subject_body_and_attachment_name() {
	raw := 'Subject: =?ISO-8859-7?Q?=CA=E1=EB=E7=EC=DD=F1=E1_=EA=FC=F3=EC=E5?=\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=greek\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n=CA=E1=EB=E7=EC=DD=F1=E1 =EA=FC=F3=EC=E5\r\n--b1\r\nContent-Type: application/pdf; name*=ISO-8859-7\'\'%E1%F1%F7%E5%DF%EF.pdf\r\nContent-Disposition: attachment; filename*=ISO-8859-7\'\'%E1%F1%F7%E5%DF%EF.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\nUERG\r\n--b1--\r\n'
	expected := greek_good_morning_world()
	attachment_name := greek_file_pdf()
	msg := parse(raw)!
	assert msg.subject == expected
	assert msg.text == expected
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == attachment_name
	assert msg.attachments[0].bytes.bytestr() == 'PDF'
	assert decode_charset_bytes([u8(0xca), 0xe1, 0xeb, 0xe7, 0xec], 'csisolatingreek') == expected[..10]

	cp1253_raw := 'Subject: =?windows-1253?Q?=CA=E1=EB=E7=EC=DD=F1=E1_=EA=FC=F3=EC=E5?=\r\nContent-Type: multipart/mixed; boundary="b2"\r\n\r\n--b2\r\nContent-Type: text/plain; charset=cp1253\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n=CA=E1=EB=E7=EC=DD=F1=E1 =EA=FC=F3=EC=E5\r\n--b2\r\nContent-Type: application/pdf; name*=windows-1253\'\'%E1%F1%F7%E5%DF%EF.pdf\r\nContent-Disposition: attachment; filename*=windows-1253\'\'%E1%F1%F7%E5%DF%EF.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\nUERG\r\n--b2--\r\n'
	cp1253_msg := parse(cp1253_raw)!
	assert cp1253_msg.subject == expected
	assert cp1253_msg.text == expected
	assert cp1253_msg.attachments[0].name == attachment_name
	assert decode_charset_bytes([u8(0x93), 0xca, 0xe1, 0x94], 'cp1253') == [
		u8(0xe2),
		0x80,
		0x9c,
		0xce,
		0x9a,
		0xce,
		0xb1,
		0xe2,
		0x80,
		0x9d,
	].bytestr()
}

fn test_parse_cyrillic_charsets_like_javamail() {
	raw := 'Subject: =?windows-1251?Q?=CF=F0=E8=E2=E5=F2_=EC=E8=F0?=\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=windows-1251\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n=CF=F0=E8=E2=E5=F2 =EC=E8=F0\r\n--b1\r\nContent-Type: application/pdf; name*=cp1251\'\'%F4%E0%E9%EB.pdf\r\nContent-Disposition: attachment; filename*=cp1251\'\'%F4%E0%E9%EB.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\nUERG\r\n--b1--\r\n'
	expected := russian_privet_mir()
	attachment_name := russian_file_pdf()
	assert decode_rfc2047_header('=?windows-1251?Q?=CF=F0=E8=E2=E5=F2_=EC=E8=F0?=') == expected
	msg := parse(raw)!
	assert msg.subject == expected
	assert msg.text == expected
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == attachment_name
	assert msg.attachments[0].bytes.bytestr() == 'PDF'
	assert decode_charset_bytes([u8(0xbf), 0xe0, 0xd8, 0xd2, 0xd5, 0xe2], 'ISO-8859-5') == russian_privet()

	koi8_raw := 'Subject: =?KOI8-R?Q?=F0=D2=C9=D7=C5=D4_=CD=C9=D2?=\r\nContent-Type: multipart/mixed; boundary="b2"\r\n\r\n--b2\r\nContent-Type: text/plain; charset=KOI8-R\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n=F0=D2=C9=D7=C5=D4 =CD=C9=D2\r\n--b2\r\nContent-Type: application/pdf; name*=KOI8-R\'\'%C6%C1%CA%CC.pdf\r\nContent-Disposition: attachment; filename*=KOI8-R\'\'%C6%C1%CA%CC.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\nUERG\r\n--b2--\r\n'
	koi8_msg := parse(koi8_raw)!
	assert koi8_msg.subject == expected
	assert koi8_msg.text == expected
	assert koi8_msg.attachments[0].name == attachment_name
}

fn test_parse_utf16_text_body_charsets_like_javamail() {
	euro := [u8(0xe2), 0x82, 0xac].bytestr()
	utf16le_body := [u8(0xff), 0xfe, 0x55, 0x00, 0x54, 0x00, 0x46, 0x00, 0x31, 0x00, 0x36, 0x00,
		0x20, 0x00, 0xac, 0x20]
	raw_auto :=
		'Subject: UTF16 auto\r\nContent-Type: text/plain; charset=UTF-16\r\nContent-Transfer-Encoding: base64\r\n\r\n' +
		base64.encode(utf16le_body) + '\r\n'
	auto_msg := parse(raw_auto)!
	assert auto_msg.text == 'UTF16 ' + euro

	utf16be_body := [u8(0x00), 0x42, 0x00, 0x45, 0x00, 0x20, 0x20, 0xac]
	raw_be :=
		'Subject: UTF16 BE\r\nContent-Type: text/plain; charset=UTF-16BE\r\nContent-Transfer-Encoding: base64\r\n\r\n' +
		base64.encode(utf16be_body) + '\r\n'
	be_msg := parse(raw_be)!
	assert be_msg.text == 'BE ' + euro

	utf16le_alias_body := [u8(0x4c), 0x00, 0x45, 0x00, 0x20, 0x00, 0xac, 0x20]
	assert decode_charset_bytes(utf16le_alias_body, 'utf16le') == 'LE ' + euro
}

fn russian_privet() string {
	return [
		u8(0xd0),
		0x9f,
		0xd1,
		0x80,
		0xd0,
		0xb8,
		0xd0,
		0xb2,
		0xd0,
		0xb5,
		0xd1,
		0x82,
	].bytestr()
}

fn russian_privet_mir() string {
	return russian_privet() + ' ' + [u8(0xd0), 0xbc, 0xd0, 0xb8, 0xd1, 0x80].bytestr()
}

fn russian_file_pdf() string {
	return [
		u8(0xd1),
		0x84,
		0xd0,
		0xb0,
		0xd0,
		0xb9,
		0xd0,
		0xbb,
		0x2e,
		0x70,
		0x64,
		0x66,
	].bytestr()
}

fn greek_good_morning_world() string {
	return [
		u8(0xce),
		0x9a,
		0xce,
		0xb1,
		0xce,
		0xbb,
		0xce,
		0xb7,
		0xce,
		0xbc,
		0xce,
		0xad,
		0xcf,
		0x81,
		0xce,
		0xb1,
		0x20,
		0xce,
		0xba,
		0xcf,
		0x8c,
		0xcf,
		0x83,
		0xce,
		0xbc,
		0xce,
		0xb5,
	].bytestr()
}

fn greek_file_pdf() string {
	return [
		u8(0xce),
		0xb1,
		0xcf,
		0x81,
		0xcf,
		0x87,
		0xce,
		0xb5,
		0xce,
		0xaf,
		0xce,
		0xbf,
		0x2e,
		0x70,
		0x64,
		0x66,
	].bytestr()
}

fn turkish_istanbul_letters() string {
	return [u8(0xc4), 0xb0, 0x73, 0x74, 0x61, 0x6e, 0x62, 0x75, 0x6c, 0x20].bytestr() +
		turkish_letter_sample()
}

fn turkish_letter_sample() string {
	return [
		u8(0xc4),
		0x9e,
		0xc4,
		0xb0,
		0xc5,
		0x9e,
		0x20,
		0xc4,
		0x9f,
		0xc4,
		0xb1,
		0xc5,
		0x9f,
	].bytestr()
}

fn turkish_file_pdf() string {
	return [
		u8(0x74),
		0x75,
		0x72,
		0x6b,
		0xc3,
		0xa7,
		0x65,
		0x20,
		0xc4,
		0x9e,
		0xc4,
		0xb0,
		0xc5,
		0x9e,
		0x2e,
		0x70,
		0x64,
		0x66,
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

fn test_parse_mime_header_comments_like_javamail() {
	raw := 'Subject: CFWS sample\r\nContent-Type: multipart/mixed (scanner); boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain (scanner); charset=UTF-8\r\nContent-Transfer-Encoding: quoted-printable (scanner)\r\n\r\nHello=20CFWS\r\n--b1\r\nContent-Type: application/octet-stream (scanner); name="scan (1).bin"\r\nContent-Disposition: attachment (scanner); filename="scan (1).bin"\r\nContent-Transfer-Encoding: base64 (scanner)\r\n\r\nQUJD\r\n--b1--\r\n'
	msg := parse(raw)!
	assert msg.text == 'Hello CFWS'
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == 'scan (1).bin'
	assert msg.attachments[0].mime_type == 'application/octet-stream'
	assert msg.attachments[0].bytes.bytestr() == 'ABC'
}

fn test_parse_uuencoded_attachment_like_javamail() {
	raw := 'Subject: UU sample\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nBody\r\n--b1\r\nContent-Type: text/plain; name="abc.txt"\r\nContent-Disposition: attachment; filename="abc.txt"\r\nContent-Transfer-Encoding: uuencode\r\n\r\nbegin 644 abc.txt\r\n#04)#\r\n`\r\nend\r\n--b1--\r\n'
	msg := parse(raw)!
	assert msg.text == 'Body'
	assert msg.attachments.len == 1
	assert msg.attachments[0].name == 'abc.txt'
	assert msg.attachments[0].mime_type == 'text/plain'
	assert msg.attachments[0].bytes.bytestr() == 'ABC'
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

fn test_parse_inline_message_rfc822_with_filename_recurses_like_javamail() {
	nested := 'Subject: Forwarded inner\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nInner body\r\n'
	raw :=
		'Subject: Outer\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: message/rfc822; name="forwarded.eml"\r\nContent-Disposition: inline; filename="forwarded.eml"\r\nContent-Transfer-Encoding: base64\r\n\r\n' +
		base64.encode(nested.bytes()) + '\r\n--b1--\r\n'
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
	assert mail_date_stamp('21 Feb 2018 15:11:01 +0100') == '2018-02-21 14:11:01'
	assert mail_date_stamp('Wed, 21 Feb 2018 15:11:01 GMT') == '2018-02-21 15:11:01'
	assert mail_date_stamp('bad date') == ''
}
