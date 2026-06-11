module vmail_mime

import os

fn test_parse_real_teedy_test_mail_fixture() {
	fixture := real_teedy_test_mail_fixture_path()
	if fixture == '' {
		return
	}
	msg := parse(os.read_file(fixture)!)!
	assert msg.subject == 'subject here'
	assert msg.date_stamp == '2018-02-21 15:11:01'
	assert msg.text.contains('content here')
	assert msg.attachments.len == 2
	assert msg.attachments[0].name == '14_UNHCR_nd.pdf'
	assert msg.attachments[0].mime_type == 'application/pdf'
	assert msg.attachments[0].bytes.len == 251216
	assert msg.attachments[1].name == 'refugee status determination.pdf'
	assert msg.attachments[1].mime_type == 'application/pdf'
	assert msg.attachments[1].bytes.len == 279276
}

fn real_teedy_test_mail_fixture_path() string {
	rel := os.join_path('_refs', 'Teedy', 'docs-web', 'src', 'test', 'resources', 'file',
		'test_mail.eml')
	candidates := [
		os.join_path(os.dir(os.getwd()), rel),
		os.join_path('C:\\git\\v_projects', rel),
	]
	for candidate in candidates {
		if os.exists(candidate) {
			return candidate
		}
	}
	return ''
}
