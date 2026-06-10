module vmail_mime

import time

pub fn parse(raw string) !Message {
	if raw.trim_space() == '' {
		return error('eml content is required')
	}
	headers_text, body := split_header_body(raw)
	headers := parse_headers(headers_text)
	date := header_value(headers, 'date')
	mut parsed := ParsedMessage{
		subject:    decode_rfc2047_header(header_value(headers, 'subject'))
		date:       date
		date_stamp: mail_date_stamp(date)
	}
	parse_part(headers, body, mut parsed)!
	return Message{
		subject:     parsed.subject
		date:        parsed.date
		date_stamp:  parsed.date_stamp
		text:        parsed.text
		attachments: parsed.attachments
	}
}

pub fn mail_date_stamp(value string) string {
	clean := value.trim_space()
	if clean == '' {
		return ''
	}
	parsed := time.parse_rfc2822(clean) or {
		time.parse_rfc2822(normalized_mail_date(clean)) or { return '' }
	}
	return parsed.format_ss()
}

fn normalized_mail_date(value string) string {
	fields := value.split(' ').filter(it != '')
	if fields.len >= 5 && fields[0].len > 0 && fields[0][0] >= `0` && fields[0][0] <= `9` {
		return 'Mon, ${fields.join(' ')}'
	}
	return value
}

fn parse_part(headers map[string]string, body string, mut parsed ParsedMessage) ! {
	content_type := header_value(headers, 'content-type')
	disposition := header_value(headers, 'content-disposition')
	transfer_encoding := header_value(headers, 'content-transfer-encoding').to_lower()
	mime_type := effective_part_mime_type(content_type, disposition)
	if mime_type.starts_with('multipart/') {
		boundary := mime_param(content_type, 'boundary')
		if boundary == '' {
			return
		}
		for part in split_multipart_body(body, boundary) {
			parse_multipart_child(mime_type, part, mut parsed)!
		}
		return
	}
	decoded := decode_transfer_body(body, transfer_encoding)
	is_attachment := is_attachment_disposition(disposition)
	decoded_filename := if is_attachment {
		decode_rfc2047_header(attachment_name(disposition, content_type))
	} else {
		''
	}
	if mime_type == 'message/rfc822' {
		if is_attachment {
			parsed.attachments << Attachment{
				name:      decoded_filename
				mime_type: 'message/rfc822'
				bytes:     decoded
			}
			return
		}
		nested_headers_text, nested_body := split_header_body(decoded.bytestr())
		parse_part(parse_headers(nested_headers_text), nested_body, mut parsed)!
		return
	}
	if is_attachment || (!mime_type.starts_with('text/') && decoded.len > 0) {
		parsed.attachments << Attachment{
			name:      decoded_filename
			mime_type: if mime_type == '' { 'application/octet-stream' } else { mime_type }
			bytes:     decoded
		}
		return
	}
	if parsed.text == '' {
		text := decode_text_bytes(decoded, content_type)
		if mime_type == 'text/plain' || mime_type == '' {
			parsed.text = text.trim_space()
		} else if mime_type == 'text/html' {
			parsed.text = html_to_text(text).trim_space()
		}
	}
}

fn split_header_body(raw string) (string, string) {
	normalized := normalize_mail_newlines(raw)
	if normalized.contains('\n\n') {
		return normalized.all_before('\n\n'), normalized.all_after('\n\n')
	}
	return normalized, ''
}

fn normalize_mail_newlines(value string) string {
	return value.replace('\r\n', '\n').replace('\r', '\n')
}

fn parse_headers(raw string) map[string]string {
	mut out := map[string]string{}
	mut current_key := ''
	for line in normalize_mail_newlines(raw).split('\n') {
		if line == '' {
			continue
		}
		if (line.starts_with(' ') || line.starts_with('\t')) && current_key != '' {
			out[current_key] = '${out[current_key]} ${line.trim_space()}'
			continue
		}
		if !line.contains(':') {
			continue
		}
		key := line.all_before(':').trim_space().to_lower()
		value := line.all_after(':').trim_space()
		if key != '' {
			out[key] = value
			current_key = key
		}
	}
	return out
}

fn header_value(headers map[string]string, key string) string {
	return headers[key.to_lower()] or { '' }
}

fn parse_multipart_child(parent_mime_type string, part string, mut parsed ParsedMessage) ! {
	part_headers_text, part_body := split_header_body(part)
	mut part_headers := parse_headers(part_headers_text)
	mut body := part_body
	if parent_mime_type == 'multipart/digest' && header_value(part_headers, 'content-type') == '' {
		if !has_mime_part_headers(part_headers) {
			part_headers = map[string]string{}
			body = part
		}
		part_headers['content-type'] = 'message/rfc822'
	}
	parse_part(part_headers, body, mut parsed)!
}

fn has_mime_part_headers(headers map[string]string) bool {
	for key, _ in headers {
		if key.starts_with('content-') {
			return true
		}
	}
	return false
}

fn effective_part_mime_type(content_type string, disposition string) string {
	base := mime_base(content_type)
	if base != '' {
		return base
	}
	if is_attachment_disposition(disposition) {
		return ''
	}
	return 'text/plain'
}

fn mime_base(value string) string {
	return value.all_before(';').trim_space().to_lower()
}

fn is_attachment_disposition(disposition string) bool {
	return mime_base(disposition) == 'attachment'
}

fn mime_param(value string, name string) string {
	needle := name.to_lower()
	parts := split_mime_header(value)
	if continued := mime_continued_param(parts, needle) {
		return continued
	}
	for part in parts {
		if !part.contains('=') {
			continue
		}
		key := part.all_before('=').trim_space().to_lower()
		if key == needle || key == '${needle}*' {
			return decode_rfc2231_value(unquote_mime_value(part.all_after('=').trim_space()))
		}
	}
	return ''
}

struct MimeParamSegment {
	encoded bool
	value   string
}

fn mime_continued_param(parts []string, needle string) ?string {
	mut segments := map[int]MimeParamSegment{}
	for part in parts {
		if !part.contains('=') {
			continue
		}
		key := part.all_before('=').trim_space().to_lower()
		if !key.starts_with('${needle}*') || key == '${needle}*' {
			continue
		}
		raw_index := key[needle.len + 1..]
		encoded := raw_index.ends_with('*')
		index_text := if encoded { raw_index[..raw_index.len - 1] } else { raw_index }
		index := mime_segment_index(index_text) or { continue }
		value := unquote_mime_value(part.all_after('=').trim_space())
		segments[index] = MimeParamSegment{
			encoded: encoded
			value:   value
		}
	}
	if 0 !in segments {
		return none
	}
	return decode_rfc2231_segments(segments)
}

fn decode_rfc2231_segments(segments map[int]MimeParamSegment) string {
	first := segments[0] or { return '' }
	mut charset := ''
	mut bytes := []u8{}
	if first.encoded {
		found, first_charset, payload := rfc2231_extended_value(first.value)
		charset = first_charset
		bytes << percent_decode_bytes(if found { payload } else { first.value })
	} else {
		bytes << first.value.bytes()
	}
	for i := 0; i < 128; i++ {
		if i == 0 {
			continue
		}
		segment := segments[i] or { break }
		if segment.encoded {
			bytes << percent_decode_bytes(segment.value)
		} else {
			bytes << segment.value.bytes()
		}
	}
	if charset != '' {
		return decode_charset_bytes(bytes, charset)
	}
	return bytes.bytestr()
}

fn mime_segment_index(value string) ?int {
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

fn split_mime_header(value string) []string {
	mut out := []string{}
	mut current := ''
	mut quoted := false
	mut escaped := false
	for i := 0; i < value.len; i++ {
		ch := value[i]
		if quoted && escaped {
			current += ch.ascii_str()
			escaped = false
			continue
		}
		if quoted && ch == `\\` {
			current += ch.ascii_str()
			escaped = true
			continue
		}
		if ch == `"` {
			quoted = !quoted
			current += ch.ascii_str()
			continue
		}
		if ch == `;` && !quoted {
			out << current
			current = ''
			continue
		}
		current += ch.ascii_str()
	}
	out << current
	return out
}

fn unquote_mime_value(value string) string {
	clean := value.trim_space()
	if clean.len >= 2 && clean.starts_with('"') && clean.ends_with('"') {
		return unescape_mime_quoted_string(clean[1..clean.len - 1])
	}
	return clean
}

fn unescape_mime_quoted_string(value string) string {
	mut out := []u8{}
	mut escaped := false
	for ch in value.bytes() {
		if escaped {
			out << ch
			escaped = false
			continue
		}
		if ch == `\\` {
			escaped = true
			continue
		}
		out << ch
	}
	if escaped {
		out << `\\`
	}
	return out.bytestr()
}

fn split_multipart_body(body string, boundary string) []string {
	delimiter := '--${boundary}'
	mut parts := []string{}
	mut current := ''
	mut in_part := false
	for line in normalize_mail_newlines(body).split('\n') {
		trimmed_line := line.trim_right(' \t')
		if trimmed_line == delimiter || trimmed_line == '${delimiter}--' {
			if in_part && current != '' {
				parts << current.trim_right('\n')
			}
			current = ''
			in_part = trimmed_line != '${delimiter}--'
			continue
		}
		if in_part {
			current += line + '\n'
		}
	}
	if in_part && current != '' {
		parts << current.trim_right('\n')
	}
	return parts
}

fn attachment_name(disposition string, content_type string) string {
	name := mime_param(disposition, 'filename')
	if name != '' {
		return name
	}
	return mime_param(content_type, 'name')
}
