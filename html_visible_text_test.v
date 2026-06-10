module vmail_mime

fn test_parse_html_skips_script_and_style_text_like_jsoup() {
	raw := 'Subject: HTML visible text\r\nContent-Type: text/html; charset=UTF-8\r\n\r\n<html><body><script>alert(1)</script><style>.hidden{}</style><p>Visible body</p></body></html>\r\n'
	msg := parse(raw)!
	assert msg.text == 'Visible body'
	assert msg.attachments.len == 0
}

fn test_parse_html_collapses_entity_and_literal_nbsp_like_jsoup() {
	nbsp := [u8(0xc2), 0xa0].bytestr()
	raw := 'Subject: HTML spaces\r\nContent-Type: text/html; charset=UTF-8\r\n\r\n<p>A&nbsp;&nbsp;' +
		nbsp + 'B</p>\r\n'
	msg := parse(raw)!
	assert msg.text == 'A B'
	assert msg.attachments.len == 0
}
