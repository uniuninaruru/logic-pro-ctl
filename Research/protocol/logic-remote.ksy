# Logic Remote application frame (Logic Pro 12.3.1 / 6682), from STATIC analysis only.
# See Research/static-analysis/SA-REMOTE-FRAME-001.md. Documentation-grade: this file has
# NOT been compiled with the Kaitai Struct compiler and has not been checked against
# traffic from a real Logic. The Swift parser (RemoteFrame.swift) is the tested reference.
#
# Not expressible here, and so described in the document instead:
#   - a compressed flag without a "MAZP" header is passed through unchanged by Logic
#   - the payload objects themselves (property list / JSON / NSKeyedArchiver archive)
meta:
  id: logic_remote_frame
  title: Logic Remote application frame
  endian: be
  license: CC0-1.0
seq:
  - id: tag
    type: u1
    doc: |
      bit 7 = the payload is a MAZP container; bits 0-6 = format
      (1 property list, 4 JSON, 2 keyed archive; Logic sends any other value to the keyed unarchiver)
  - id: payload_compressed
    type: mazp
    if: is_compressed
    size-eos: true
  - id: payload_plain
    size-eos: true
    if: not is_compressed
instances:
  is_compressed:
    value: (tag & 0x80) != 0
  format:
    value: tag & 0x7f
    enum: format
types:
  mazp:
    seq:
      - id: magic
        contents: "MAZP"
      - id: header_length
        type: u2
        doc: offset of the zlib stream from the start of the container (Logic writes 10)
      - id: uncompressed_length
        type: u4
        doc: |
          Logic allocates this much without an upper bound and does not check the real size.
          Writers use compress2 at level 9 and only compress payloads over 1024 bytes
          when the result is smaller.
      - id: extra_header
        size: header_length - 10
      - id: body
        size-eos: true
        process: zlib
enums:
  format:
    1: property_list
    2: keyed_archive
    4: json
