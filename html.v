module vmail_mime

import strings

fn html_to_text(value string) string {
	visible := strip_html_invisible_blocks(value)
	mut out := strings.new_builder(visible.len)
	mut in_tag := false
	for i := 0; i < visible.len; i++ {
		ch := visible[i]
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
	return normalize_html_text_space(decode_html_entities(out.str()))
}

fn strip_html_invisible_blocks(value string) string {
	mut out := strings.new_builder(value.len)
	lower := value.to_lower()
	mut i := 0
	for i < value.len {
		start, name := next_html_invisible_block(lower, i) or {
			out.write_string(value[i..])
			break
		}
		out.write_string(value[i..start])
		open_end := lower[start..].index('>') or {
			i = value.len
			break
		}
		content_start := start + open_end + 1
		close_marker := '</${name}'
		close_rel := lower[content_start..].index(close_marker) or {
			i = value.len
			break
		}
		close_start := content_start + close_rel
		close_end := lower[close_start..].index('>') or {
			i = value.len
			break
		}
		i = close_start + close_end + 1
		if out.len > 0 {
			out.write_u8(` `)
		}
	}
	return out.str()
}

fn next_html_invisible_block(lower string, offset int) ?(int, string) {
	mut best_start := -1
	mut best_name := ''
	for name in ['script', 'style'] {
		mut scan := offset
		for scan < lower.len {
			rel := lower[scan..].index('<${name}') or { break }
			start := scan + rel
			after := start + name.len + 1
			if after >= lower.len || lower[after] in [`>`, `/`, ` `, `\t`, `\r`, `\n`, 0x0c] {
				if best_start < 0 || start < best_start {
					best_start = start
					best_name = name
				}
				break
			}
			scan = after
		}
	}
	if best_start < 0 {
		return none
	}
	return best_start, best_name
}

fn normalize_html_text_space(value string) string {
	mut out := []u8{cap: value.len}
	mut pending_space := false
	mut i := 0
	for i < value.len {
		if value[i] <= 0x20 {
			if out.len > 0 {
				pending_space = true
			}
			i++
			continue
		}
		if i + 1 < value.len && value[i] == 0xc2 && value[i + 1] == 0xa0 {
			if out.len > 0 {
				pending_space = true
			}
			i += 2
			continue
		}
		if pending_space && out.len > 0 {
			out << ` `
		}
		pending_space = false
		out << value[i]
		i++
	}
	return out.bytestr()
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
