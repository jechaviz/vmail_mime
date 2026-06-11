module vmail_mime

fn test_parse_rfc2822_named_timezone_like_javamail() {
	raw := 'Date: Tue, 02 Jan 2024 03:04:05 PST\r\nSubject: Named zone\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nBody\r\n'
	msg := parse(raw)!
	assert msg.date == 'Tue, 02 Jan 2024 03:04:05 PST'
	assert msg.date_stamp == '2024-01-02 11:04:05'
	assert mail_date_stamp('21 Feb 2018 15:11:01 EDT') == '2018-02-21 19:11:01'
	assert mail_date_stamp('Wed, 21 Feb 2018 15:11:01 UT') == '2018-02-21 15:11:01'
}
