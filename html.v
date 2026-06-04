module vmail_mime

import strings

fn html_to_text(value string) string {
	mut out := strings.new_builder(value.len)
	mut in_tag := false
	for i := 0; i < value.len; i++ {
		ch := value[i]
		if ch == `<` {
			in_tag = true
			if out.len > 0 {
				out.write_u8(` `)
			}
			continue
		}
		if ch == `>` {
			in_tag = false
			continue
		}
		if !in_tag {
			out.write_u8(ch)
		}
	}
	return decode_html_entities(out.str()).replace_each(['  ', ' ']).trim_space()
}

fn decode_html_entities(value string) string {
	return value.replace('&nbsp;', ' ').replace('&amp;', '&').replace('&lt;', '<').replace('&gt;',
		'>').replace('&quot;', '"').replace('&#39;', "'")
}
