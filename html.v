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
	mut out := []u8{}
	mut i := 0
	for i < value.len {
		if value[i] == `&` {
			if end := html_entity_end(value, i + 1) {
				entity := value[i + 1..end]
				if decoded := decode_html_entity(entity) {
					out << decoded.bytes()
					i = end + 1
					continue
				}
			}
		}
		out << value[i]
		i++
	}
	return out.bytestr()
}

fn html_entity_end(value string, start int) ?int {
	mut i := start
	for i < value.len && i - start <= 32 {
		if value[i] == `;` {
			return i
		}
		i++
	}
	return none
}

fn decode_html_entity(entity string) ?string {
	match entity {
		'nbsp' { return ' ' }
		'amp' { return '&' }
		'lt' { return '<' }
		'gt' { return '>' }
		'quot' { return '"' }
		'apos' { return "'" }
		else {}
	}

	if entity.starts_with('#x') || entity.starts_with('#X') {
		return html_entity_codepoint_text(parse_html_hex_entity(entity[2..])?)
	}
	if entity.starts_with('#') {
		return html_entity_codepoint_text(parse_html_decimal_entity(entity[1..])?)
	}
	return none
}

fn parse_html_hex_entity(value string) ?int {
	if value == '' {
		return none
	}
	mut out := 0
	for ch in value.bytes() {
		if !is_hex(ch) {
			return none
		}
		out = out * 16 + hex_value(ch)
	}
	return out
}

fn parse_html_decimal_entity(value string) ?int {
	if value == '' {
		return none
	}
	mut out := 0
	for ch in value.bytes() {
		if ch < `0` || ch > `9` {
			return none
		}
		out = out * 10 + int(ch - `0`)
	}
	return out
}

fn html_entity_codepoint_text(code int) ?string {
	if code < 0 || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff) {
		return none
	}
	mut out := []u8{}
	append_utf8_codepoint(mut out, code)
	return out.bytestr()
}
