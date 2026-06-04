module vmail_mime

import encoding.base64

fn decode_transfer_body(body string, encoding string) []u8 {
	match encoding.trim_space().to_lower() {
		'base64' {
			return base64.decode(body.replace('\r', '').replace('\n', '').trim_space())
		}
		'quoted-printable' {
			return decode_quoted_printable(body)
		}
		else {
			return body.trim_right('\r\n').bytes()
		}
	}
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
					payload := parts[2..].join('?')
					out += if encoding == 'B' {
						base64.decode_str(payload)
					} else if encoding == 'Q' {
						decode_quoted_printable(payload.replace('_', ' ')).bytestr()
					} else {
						payload
					}
					i += token.len + 4
					continue
				}
			}
		}
		out += value[i].ascii_str()
		i++
	}
	return out.trim_space()
}

fn decode_rfc2231_value(value string) string {
	if value.contains("''") {
		return percent_decode(value.all_after("''"))
	}
	return value
}

fn percent_decode(value string) string {
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
	return bytes.bytestr()
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
