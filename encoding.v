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
	if key in ['iso-8859-2', 'iso8859-2', 'latin2', 'latin-2', 'csisolatin2'] {
		return decode_iso_8859_2_bytes(bytes)
	}
	if key in ['windows-1250', 'windows1250', 'cp1250'] {
		return decode_windows1250_bytes(bytes)
	}
	if key in ['iso-8859-15', 'iso8859-15', 'latin9', 'latin-9'] {
		return decode_iso_8859_15_bytes(bytes)
	}
	if key in ['windows-1252', 'cp1252'] {
		return decode_windows1252_bytes(bytes)
	}
	if key in ['windows-1251', 'windows1251', 'cp1251'] {
		return decode_windows1251_bytes(bytes)
	}
	if key in ['iso-8859-5', 'iso8859-5', 'cyrillic', 'csisolatincyrillic'] {
		return decode_iso_8859_5_bytes(bytes)
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

fn decode_latin1_bytes(bytes []u8) string {
	mut out := []u8{}
	for b in bytes {
		append_utf8_codepoint(mut out, int(b))
	}
	return out.bytestr()
}

fn decode_iso_8859_2_bytes(bytes []u8) string {
	mut out := []u8{}
	for b in bytes {
		append_utf8_codepoint(mut out, iso_8859_2_codepoint(b))
	}
	return out.bytestr()
}

fn iso_8859_2_codepoint(value u8) int {
	match value {
		0xa1 { return 0x0104 }
		0xa2 { return 0x02d8 }
		0xa3 { return 0x0141 }
		0xa5 { return 0x013d }
		0xa6 { return 0x015a }
		0xa9 { return 0x0160 }
		0xaa { return 0x015e }
		0xab { return 0x0164 }
		0xac { return 0x0179 }
		0xae { return 0x017d }
		0xaf { return 0x017b }
		0xb1 { return 0x0105 }
		0xb2 { return 0x02db }
		0xb3 { return 0x0142 }
		0xb5 { return 0x013e }
		0xb6 { return 0x015b }
		0xb7 { return 0x02c7 }
		0xb9 { return 0x0161 }
		0xba { return 0x015f }
		0xbb { return 0x0165 }
		0xbc { return 0x017a }
		0xbd { return 0x02dd }
		0xbe { return 0x017e }
		0xbf { return 0x017c }
		0xc0 { return 0x0154 }
		0xc3 { return 0x0102 }
		0xc5 { return 0x0139 }
		0xc6 { return 0x0106 }
		0xc8 { return 0x010c }
		0xca { return 0x0118 }
		0xcc { return 0x011a }
		0xcf { return 0x010e }
		0xd0 { return 0x0110 }
		0xd1 { return 0x0143 }
		0xd2 { return 0x0147 }
		0xd5 { return 0x0150 }
		0xd8 { return 0x0158 }
		0xd9 { return 0x016e }
		0xdb { return 0x0170 }
		0xde { return 0x0162 }
		0xe0 { return 0x0155 }
		0xe3 { return 0x0103 }
		0xe5 { return 0x013a }
		0xe6 { return 0x0107 }
		0xe8 { return 0x010d }
		0xea { return 0x0119 }
		0xec { return 0x011b }
		0xef { return 0x010f }
		0xf0 { return 0x0111 }
		0xf1 { return 0x0144 }
		0xf2 { return 0x0148 }
		0xf5 { return 0x0151 }
		0xf8 { return 0x0159 }
		0xf9 { return 0x016f }
		0xfb { return 0x0171 }
		0xfe { return 0x0163 }
		0xff { return 0x02d9 }
		else { return int(value) }
	}
}

fn decode_windows1250_bytes(bytes []u8) string {
	mut out := []u8{}
	for b in bytes {
		append_utf8_codepoint(mut out, windows1250_codepoint(b))
	}
	return out.bytestr()
}

fn windows1250_codepoint(value u8) int {
	match value {
		0x80 {
			return 0x20ac
		}
		0x82 {
			return 0x201a
		}
		0x84 {
			return 0x201e
		}
		0x85 {
			return 0x2026
		}
		0x86 {
			return 0x2020
		}
		0x87 {
			return 0x2021
		}
		0x89 {
			return 0x2030
		}
		0x8a {
			return 0x0160
		}
		0x8b {
			return 0x2039
		}
		0x8c {
			return 0x015a
		}
		0x8d {
			return 0x0164
		}
		0x8e {
			return 0x017d
		}
		0x8f {
			return 0x0179
		}
		0x91 {
			return 0x2018
		}
		0x92 {
			return 0x2019
		}
		0x93 {
			return 0x201c
		}
		0x94 {
			return 0x201d
		}
		0x95 {
			return 0x2022
		}
		0x96 {
			return 0x2013
		}
		0x97 {
			return 0x2014
		}
		0x99 {
			return 0x2122
		}
		0x9a {
			return 0x0161
		}
		0x9b {
			return 0x203a
		}
		0x9c {
			return 0x015b
		}
		0x9d {
			return 0x0165
		}
		0x9e {
			return 0x017e
		}
		0x9f {
			return 0x017a
		}
		0xa1 {
			return 0x02c7
		}
		0xa5 {
			return 0x0104
		}
		0xa6, 0xa9, 0xab, 0xac, 0xae, 0xb1, 0xb5, 0xb6, 0xb7, 0xbb {
			return int(value)
		}
		0xb9 {
			return 0x0105
		}
		0xbc {
			return 0x013d
		}
		0xbe {
			return 0x013e
		}
		else {
			return iso_8859_2_codepoint(value)
		}
	}
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

fn decode_windows1251_bytes(bytes []u8) string {
	mut out := []u8{}
	for b in bytes {
		append_utf8_codepoint(mut out, windows1251_codepoint(b))
	}
	return out.bytestr()
}

fn windows1251_codepoint(value u8) int {
	if value >= 0xc0 {
		return 0x0410 + int(value - 0xc0)
	}
	return match value {
		0xa8 { 0x0401 }
		0xb8 { 0x0451 }
		0x80 { 0x0402 }
		0x81 { 0x0403 }
		0x82 { 0x201a }
		0x83 { 0x0453 }
		0x84 { 0x201e }
		0x85 { 0x2026 }
		0x86 { 0x2020 }
		0x87 { 0x2021 }
		0x88 { 0x20ac }
		0x89 { 0x2030 }
		0x8a { 0x0409 }
		0x8b { 0x2039 }
		0x8c { 0x040a }
		0x8d { 0x040c }
		0x8e { 0x040b }
		0x8f { 0x040f }
		0x90 { 0x0452 }
		0x91 { 0x2018 }
		0x92 { 0x2019 }
		0x93 { 0x201c }
		0x94 { 0x201d }
		0x95 { 0x2022 }
		0x96 { 0x2013 }
		0x97 { 0x2014 }
		0x99 { 0x2122 }
		0x9a { 0x0459 }
		0x9b { 0x203a }
		0x9c { 0x045a }
		0x9d { 0x045c }
		0x9e { 0x045b }
		0x9f { 0x045f }
		0xaa { 0x0404 }
		0xaf { 0x0407 }
		0xb2 { 0x0406 }
		0xb3 { 0x0456 }
		0xba { 0x0454 }
		0xbf { 0x0457 }
		else { int(value) }
	}
}

fn decode_iso_8859_5_bytes(bytes []u8) string {
	mut out := []u8{}
	for b in bytes {
		append_utf8_codepoint(mut out, iso_8859_5_codepoint(b))
	}
	return out.bytestr()
}

fn iso_8859_5_codepoint(value u8) int {
	if value >= 0xa1 && value <= 0xac {
		return 0x0401 + int(value - 0xa1)
	}
	if value >= 0xae && value <= 0xef {
		return 0x040e + int(value - 0xae)
	}
	if value == 0xf0 {
		return 0x2116
	}
	if value >= 0xf1 && value <= 0xfc {
		return 0x0451 + int(value - 0xf1)
	}
	return match value {
		0xfd { 0x00a7 }
		0xfe { 0x045e }
		0xff { 0x045f }
		else { int(value) }
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
