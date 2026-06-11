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
		'uuencode', 'x-uuencode', 'x-uue', 'uue' {
			return decode_uuencoded(body)
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

fn decode_uuencoded(body string) []u8 {
	normalized := body.replace('\r\n', '\n').replace('\r', '\n')
	lines := normalized.split('\n')
	mut out := []u8{}
	mut started := false
	mut saw_begin := false
	mut decoded_line := false
	for line in lines {
		clean := line.trim_space()
		if !started {
			if clean.starts_with('begin ') {
				started = true
				saw_begin = true
			}
			continue
		}
		if clean == 'end' {
			break
		}
		decoded_line = append_uuencoded_line(line, mut out) || decoded_line
	}
	if !saw_begin {
		for line in lines {
			clean := line.trim_space()
			if clean == '' || clean == 'end' || clean.starts_with('begin ') {
				continue
			}
			decoded_line = append_uuencoded_line(line, mut out) || decoded_line
		}
	}
	if !decoded_line {
		return body.trim_right('\r\n').bytes()
	}
	return out
}

fn append_uuencoded_line(line string, mut out []u8) bool {
	if line.len == 0 {
		return false
	}
	mut remaining := int(uuencoded_value(line[0]))
	if remaining == 0 {
		return true
	}
	for pos := 1; remaining > 0 && pos < line.len; pos += 4 {
		c0 := uuencoded_value_at(line, pos)
		c1 := uuencoded_value_at(line, pos + 1)
		c2 := uuencoded_value_at(line, pos + 2)
		c3 := uuencoded_value_at(line, pos + 3)
		decoded := [
			u8((c0 << 2) | (c1 >> 4)),
			u8(((c1 & 0x0f) << 4) | (c2 >> 2)),
			u8(((c2 & 0x03) << 6) | c3),
		]
		for byte in decoded {
			if remaining <= 0 {
				break
			}
			out << byte
			remaining--
		}
	}
	return true
}

fn uuencoded_value_at(line string, index int) u32 {
	if index >= line.len {
		return 0
	}
	return uuencoded_value(line[index])
}

fn uuencoded_value(ch u8) u32 {
	if ch == `\`` {
		return 0
	}
	mut value := int(ch) - 32
	if value < 0 {
		value = 0
	}
	return u32(value & 0x3f)
}

fn decode_rfc2047_header(value string) string {
	mut out := ''
	for i := 0; i < value.len; {
		if i + 2 < value.len && value[i] == `=` && value[i + 1] == `?` {
			start := i + 2
			if charset_end_offset := value[start..].index('?') {
				charset_end := start + charset_end_offset
				encoding_start := charset_end + 1
				if encoding_end_offset := value[encoding_start..].index('?') {
					encoding_end := encoding_start + encoding_end_offset
					payload_start := encoding_end + 1
					if payload_end_offset := value[payload_start..].index('?=') {
						payload_end := payload_start + payload_end_offset
						charset := value[start..charset_end]
						encoding := value[encoding_start..encoding_end].to_upper()
						payload := value[payload_start..payload_end]
						out += if encoding == 'B' {
							decode_charset_bytes(base64.decode(payload), charset)
						} else if encoding == 'Q' {
							decode_charset_bytes(decode_quoted_printable(payload.replace('_', ' ')),
								charset)
						} else {
							payload
						}
						next := payload_end + 2
						i = next + rfc2047_adjacent_space(value[next..])
						continue
					}
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
	found, charset, payload := rfc2231_extended_value(value)
	if found {
		bytes := percent_decode_bytes(payload)
		if charset != '' {
			return decode_charset_bytes(bytes, charset)
		}
		return bytes.bytestr()
	}
	return value
}

fn rfc2231_extended_value(value string) (bool, string, string) {
	if first := value.index("'") {
		if second_offset := value[first + 1..].index("'") {
			second := first + 1 + second_offset
			return true, value[..first], value[second + 1..]
		}
	}
	return false, '', value
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
	for part in split_mime_header(strip_mime_comments(content_type)) {
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
	if key in ['iso-8859-2', 'iso8859-2', 'latin2', 'latin-2', 'csisolatin2'] {
		return decode_iso_8859_2_bytes(bytes)
	}
	if key in ['windows-1250', 'windows1250', 'cp1250'] {
		return decode_windows1250_bytes(bytes)
	}
	if key in ['iso-8859-15', 'iso8859-15', 'latin9', 'latin-9'] {
		return decode_iso_8859_15_bytes(bytes)
	}
	if key in ['iso-8859-9', 'iso8859-9', 'latin5', 'latin-5', 'csisolatin5', 'l5'] {
		return decode_iso_8859_9_bytes(bytes)
	}
	if key in ['windows-1252', 'cp1252'] {
		return decode_windows1252_bytes(bytes)
	}
	if key in ['windows-1254', 'windows1254', 'cp1254'] {
		return decode_windows1254_bytes(bytes)
	}
	if key in ['windows-1251', 'windows1251', 'cp1251'] {
		return decode_windows1251_bytes(bytes)
	}
	if key in ['iso-8859-5', 'iso8859-5', 'cyrillic', 'csisolatincyrillic'] {
		return decode_iso_8859_5_bytes(bytes)
	}
	if key in ['iso-8859-7', 'iso8859-7', 'greek', 'csisolatingreek'] {
		return decode_iso_8859_7_bytes(bytes)
	}
	if key in ['windows-1253', 'windows1253', 'cp1253'] {
		return decode_windows1253_bytes(bytes)
	}
	if key in ['iso-8859-8', 'iso8859-8', 'hebrew', 'csisolatinhebrew'] {
		return decode_iso_8859_8_bytes(bytes)
	}
	if key in ['windows-1255', 'windows1255', 'cp1255'] {
		return decode_windows1255_bytes(bytes)
	}
	if key in ['koi8-r', 'koi8r', 'cskoi8r'] {
		return decode_koi8_r_bytes(bytes)
	}
	if key in ['utf-16', 'utf16'] {
		return decode_utf16_bytes(bytes, 'auto')
	}
	if key in ['utf-16be', 'utf16be'] {
		return decode_utf16_bytes(bytes, 'be')
	}
	if key in ['utf-16le', 'utf16le'] {
		return decode_utf16_bytes(bytes, 'le')
	}
	return bytes.bytestr()
}

fn decode_utf16_bytes(bytes []u8, mode string) string {
	if bytes.len < 2 {
		return ''
	}
	mut start := 0
	mut endian := mode
	if bytes.len >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff {
		start = 2
		endian = 'be'
	} else if bytes.len >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe {
		start = 2
		endian = 'le'
	} else if endian == 'auto' {
		endian = 'be'
	}
	mut out := []u8{}
	mut i := start
	for i + 1 < bytes.len {
		unit := utf16_unit(bytes, i, endian)
		i += 2
		if unit >= 0xd800 && unit <= 0xdbff && i + 1 < bytes.len {
			next := utf16_unit(bytes, i, endian)
			if next >= 0xdc00 && next <= 0xdfff {
				i += 2
				code := 0x10000 + ((unit - 0xd800) * 1024) + (next - 0xdc00)
				append_utf8_codepoint(mut out, code)
				continue
			}
		}
		if unit >= 0xdc00 && unit <= 0xdfff {
			continue
		}
		append_utf8_codepoint(mut out, unit)
	}
	return out.bytestr()
}

fn utf16_unit(bytes []u8, offset int, endian string) int {
	if endian == 'le' {
		return int(bytes[offset]) + (int(bytes[offset + 1]) * 256)
	}
	return (int(bytes[offset]) * 256) + int(bytes[offset + 1])
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
