module vmail_mime

import encoding.base64

fn decode_transfer_body(body string, encoding string) []u8 {
	match encoding.trim_space().to_lower() {
		'base64' {
			return base64.decode(compact_base64_body(body))
		}
		'quoted-printable' {
			return decode_quoted_printable(body)
		}
		else {
			return body.trim_right('\r\n').bytes()
		}
	}
}

fn compact_base64_body(body string) string {
	mut out := []u8{}
	for ch in body.bytes() {
		if ch == ` ` || ch == `\t` || ch == `\r` || ch == `\n` {
			continue
		}
		out << ch
	}
	return out.bytestr()
}

fn decode_rfc2047_header(value string) string {
	mut out := ''
	for i := 0; i < value.len; {
		if i + 2 < value.len && value[i] == `=` && value[i + 1] == `?` {
			rest := value[i + 2..]
			if rest.contains('?=') {
				token := rest.all_before('?=')
				parts := token.split('?')
				if parts.len >= 3 {
					encoding := parts[1].to_upper()
					charset := parts[0]
					payload := parts[2..].join('?')
					out += if encoding == 'B' {
						decode_charset_bytes(base64.decode(payload), charset)
					} else if encoding == 'Q' {
						decode_charset_bytes(decode_quoted_printable(payload.replace('_', ' ')),
							charset)
					} else {
						payload
					}
					next := token.len + 4
					i += next + rfc2047_adjacent_space(value[i + next..])
					continue
				}
			}
		}
		out += value[i].ascii_str()
		i++
	}
	return out.trim_space()
}

fn rfc2047_adjacent_space(value string) int {
	mut i := 0
	for i < value.len && value[i] in [` `, `\t`, `\r`, `\n`] {
		i++
	}
	if i > 0 && i + 1 < value.len && value[i] == `=` && value[i + 1] == `?` {
		return i
	}
	return 0
}

fn decode_rfc2231_value(value string) string {
	if first := value.index("'") {
		if second_offset := value[first + 1..].index("'") {
			second := first + 1 + second_offset
			if first > 0 && second < value.len - 1 {
				charset := value[..first]
				return decode_charset_bytes(percent_decode_bytes(value[second + 1..]), charset)
			}
		}
	}
	return value
}

fn percent_decode(value string) string {
	return percent_decode_bytes(value).bytestr()
}

fn percent_decode_bytes(value string) []u8 {
	mut bytes := []u8{}
	for i := 0; i < value.len; {
		if value[i] == `%` && i + 2 < value.len && is_hex(value[i + 1]) && is_hex(value[i + 2]) {
			bytes << u8(hex_value(value[i + 1]) * 16 + hex_value(value[i + 2]))
			i += 3
			continue
		}
		bytes << value[i]
		i++
	}
	return bytes
}

fn decode_text_bytes(bytes []u8, content_type string) string {
	return decode_charset_bytes(bytes, mime_charset(content_type))
}

fn mime_charset(content_type string) string {
	for part in split_mime_header(content_type) {
		if !part.contains('=') {
			continue
		}
		key := part.all_before('=').trim_space().to_lower()
		if key == 'charset' {
			return unquote_mime_value(part.all_after('=').trim_space())
		}
	}
	return 'utf-8'
}

fn decode_charset_bytes(bytes []u8, charset string) string {
	key := charset.trim_space().to_lower().replace('_', '-')
	if key in ['', 'utf-8', 'utf8', 'us-ascii', 'ascii'] {
		return bytes.bytestr()
	}
	if key in ['iso-8859-1', 'latin1', 'latin-1'] {
		return decode_latin1_bytes(bytes)
	}
	if key in ['iso-8859-15', 'iso8859-15', 'latin9', 'latin-9'] {
		return decode_iso_8859_15_bytes(bytes)
	}
	if key in ['windows-1252', 'cp1252'] {
		return decode_windows1252_bytes(bytes)
	}
	return bytes.bytestr()
}

fn decode_latin1_bytes(bytes []u8) string {
	mut out := []u8{}
	for b in bytes {
		append_utf8_codepoint(mut out, int(b))
	}
	return out.bytestr()
}

fn decode_iso_8859_15_bytes(bytes []u8) string {
	mut out := []u8{}
	for b in bytes {
		append_utf8_codepoint(mut out, iso_8859_15_codepoint(b))
	}
	return out.bytestr()
}

fn iso_8859_15_codepoint(value u8) int {
	match value {
		0xa4 { return 0x20ac }
		0xa6 { return 0x0160 }
		0xa8 { return 0x0161 }
		0xb4 { return 0x017d }
		0xb8 { return 0x017e }
		0xbc { return 0x0152 }
		0xbd { return 0x0153 }
		0xbe { return 0x0178 }
		else { return int(value) }
	}
}

fn decode_windows1252_bytes(bytes []u8) string {
	mut out := []u8{}
	for b in bytes {
		append_utf8_codepoint(mut out, windows1252_codepoint(b))
	}
	return out.bytestr()
}

fn windows1252_codepoint(value u8) int {
	match value {
		0x80 { return 0x20ac }
		0x82 { return 0x201a }
		0x83 { return 0x0192 }
		0x84 { return 0x201e }
		0x85 { return 0x2026 }
		0x86 { return 0x2020 }
		0x87 { return 0x2021 }
		0x88 { return 0x02c6 }
		0x89 { return 0x2030 }
		0x8a { return 0x0160 }
		0x8b { return 0x2039 }
		0x8c { return 0x0152 }
		0x8e { return 0x017d }
		0x91 { return 0x2018 }
		0x92 { return 0x2019 }
		0x93 { return 0x201c }
		0x94 { return 0x201d }
		0x95 { return 0x2022 }
		0x96 { return 0x2013 }
		0x97 { return 0x2014 }
		0x98 { return 0x02dc }
		0x99 { return 0x2122 }
		0x9a { return 0x0161 }
		0x9b { return 0x203a }
		0x9c { return 0x0153 }
		0x9e { return 0x017e }
		0x9f { return 0x0178 }
		else { return int(value) }
	}
}

fn append_utf8_codepoint(mut out []u8, code int) {
	if code <= 0x7f {
		out << u8(code)
		return
	}
	if code <= 0x7ff {
		out << u8(0xc0 | (code >> 6))
		out << u8(0x80 | (code & 0x3f))
		return
	}
	if code <= 0xffff {
		out << u8(0xe0 | (code >> 12))
		out << u8(0x80 | ((code >> 6) & 0x3f))
		out << u8(0x80 | (code & 0x3f))
		return
	}
	if code <= 0x10ffff {
		out << u8(0xf0 | (code >> 18))
		out << u8(0x80 | ((code >> 12) & 0x3f))
		out << u8(0x80 | ((code >> 6) & 0x3f))
		out << u8(0x80 | (code & 0x3f))
	}
}

fn decode_quoted_printable(value string) []u8 {
	mut bytes := []u8{}
	for i := 0; i < value.len; {
		if value[i] == `=` {
			if i + 1 < value.len && value[i + 1] == `\n` {
				i += 2
				continue
			}
			if i + 2 < value.len && value[i + 1] == `\r` && value[i + 2] == `\n` {
				i += 3
				continue
			}
			if i + 2 < value.len && is_hex(value[i + 1]) && is_hex(value[i + 2]) {
				bytes << u8(hex_value(value[i + 1]) * 16 + hex_value(value[i + 2]))
				i += 3
				continue
			}
		}
		bytes << value[i]
		i++
	}
	return bytes
}

fn is_hex(ch u8) bool {
	return (ch >= `0` && ch <= `9`) || (ch >= `a` && ch <= `f`) || (ch >= `A` && ch <= `F`)
}

fn hex_value(ch u8) int {
	if ch >= `0` && ch <= `9` {
		return int(ch - `0`)
	}
	if ch >= `a` && ch <= `f` {
		return int(ch - `a`) + 10
	}
	if ch >= `A` && ch <= `F` {
		return int(ch - `A`) + 10
	}
	return 0
}
