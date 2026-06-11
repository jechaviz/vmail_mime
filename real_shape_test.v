module vmail_mime

fn test_parse_teedy_shape_multipart_alternative_and_pdf_attachments() {
	msg := parse(teedy_shape_eml_for_mime_test())!
	assert msg.subject == 'subject here'
	assert msg.date_stamp == '2018-02-21 14:11:01'
	assert msg.text == 'content here\neven *html* *content*'
	assert msg.attachments.len == 2
	assert msg.attachments[0].name == '14_UNHCR_nd.pdf'
	assert msg.attachments[0].mime_type == 'application/pdf'
	assert msg.attachments[0].bytes.bytestr().starts_with('%PDF-')
	assert msg.attachments[1].name == 'refugee status determination.pdf'
	assert msg.attachments[1].mime_type == 'application/pdf'
	assert msg.attachments[1].bytes.bytestr().starts_with('%PDF-')
}

fn teedy_shape_eml_for_mime_test() string {
	return 'MIME-Version: 1.0\r\nDate: Wed, 21 Feb 2018 15:11:01 +0100\r\nSubject: subject here\r\nFrom: Benjamin <benjamin.gam@gmail.com>\r\nTo: Benjamin <benjamin.gam@gmail.com>\r\nContent-Type: multipart/mixed; boundary="outer"\r\n\r\n--outer\r\nContent-Type: multipart/alternative; boundary="inner"\r\n\r\n--inner\r\nContent-Type: text/plain; charset="UTF-8"\r\n\r\ncontent here\r\neven *html* *content*\r\n\r\n--inner\r\nContent-Type: text/html; charset="UTF-8"\r\n\r\n<div dir="ltr">content here<div>even <b>html</b> <i>content</i></div></div>\r\n\r\n--inner--\r\n--outer\r\nContent-Type: application/pdf; name="14_UNHCR_nd.pdf"\r\nContent-Disposition: attachment; filename="14_UNHCR_nd.pdf"\r\nContent-Transfer-Encoding: base64\r\n\r\nJVBERi0K\r\n--outer\r\nContent-Type: application/pdf; name="refugee status determination.pdf"\r\nContent-Disposition: attachment; filename="refugee status determination.pdf"\r\nContent-Transfer-Encoding: base64\r\n\r\nJVBERi0K\r\n--outer--\r\n'
}
