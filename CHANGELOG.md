# Change Log

All notable changes to this project will be documented in this file.

## Unreleased

## [0.11.0][] - 2026-11-22

### Added

- Optional `level:` keyword argument on `PDF::Core::Stream#compress!` to configure
  zlib compression level without emitting it into PDF `DecodeParms`
  Jason Lee
- `PDF::Core::ObjectStore#page_object_ids` to fetch all page object identifiers
  in one pass
  Jason Lee, [#11](https://github.com/jlsync/pdf-core/pull/11)
- Serialization benchmark script in `benchmark/serialization.rb`
  Jason Lee, [#1](https://github.com/jlsync/pdf-core/pull/1)

### Changed

- Minimum Ruby version is 3.3; updated CI and development dependencies
  (`prawn-dev` `~> 0.7.0`, `pdf-reader` `~> 2.16`, `pdf-inspector` `~> 1.3`)
  Jason Lee, [#4](https://github.com/jlsync/pdf-core/pull/4),
  [#5](https://github.com/jlsync/pdf-core/pull/5)
- Optimized number serialization (`real`, `real_params`, `append_real`,
  `append_pdf_float`) with bounded cache-first Float memoization, precomputed
  small integer tables, and regex-free trailing-zero stripping; wound back
  scaled-integer fast paths superseded by cache-first lookup on Ruby 4.0
  Jason Lee, [#1](https://github.com/jlsync/pdf-core/pull/1),
  [#3](https://github.com/jlsync/pdf-core/pull/3),
  [#7](https://github.com/jlsync/pdf-core/pull/7),
  [#8](https://github.com/jlsync/pdf-core/pull/8),
  [#10](https://github.com/jlsync/pdf-core/pull/10),
  [#12](https://github.com/jlsync/pdf-core/pull/12)
- Reduced allocations and dispatch overhead in `pdf_object` / `append_pdf_object`
  (direct buffer appends, bounded PDF name cache with ASCII fast path, direct
  UTF-16BE hex encoding, single-entry dictionary fast path, literal string
  escape fast path, and simplified `case` dispatch for Ruby 4.0 YJIT)
  Jason Lee, [#2](https://github.com/jlsync/pdf-core/pull/2),
  [#3](https://github.com/jlsync/pdf-core/pull/3),
  [#6](https://github.com/jlsync/pdf-core/pull/6),
  [#12](https://github.com/jlsync/pdf-core/pull/12)
- Reduced allocations and redundant dispatch in text rendering (`Text` state
  setters, reused `content_line_buffer`, direct buffer streaming in
  `add_text_content`) and graphics state copying (`GraphicState#share_or_dup`)
  Jason Lee, [#3](https://github.com/jlsync/pdf-core/pull/3),
  [#6](https://github.com/jlsync/pdf-core/pull/6),
  [#11](https://github.com/jlsync/pdf-core/pull/11),
  [#12](https://github.com/jlsync/pdf-core/pull/12)
- Optimized `Stream` and `Renderer` appends (ASCII-first encoding checks,
  single-pass `append_line`, `Stream#write_to`, avoiding redundant stream copies
  and empty `DecodeParms` allocations), `Page` resource/font lookups,
  `Reference#object`, and `ObjectStore#push`
  Jason Lee, [#2](https://github.com/jlsync/pdf-core/pull/2),
  [#3](https://github.com/jlsync/pdf-core/pull/3),
  [#12](https://github.com/jlsync/pdf-core/pull/12)
- Avoided quadratic page tree flattening in
  `DocumentState#populate_pages_from_store`
  Jason Lee, [#11](https://github.com/jlsync/pdf-core/pull/11)
- Resurrected lost specs and fixed documentation/README typos
  Alexander Mankuta, Jose Luis Duran, Markus Napp

### Fixed

- Correctly handle multibyte-encoded string in streams
  Alexander Mankuta
- Preserve caller string isolation and encodings in `Stream#<<` and
  `Stream#filtered_stream` snapshots
  Jason Lee, [#1](https://github.com/jlsync/pdf-core/pull/1)
- Preserve signed zeroes (`0.0` vs `-0.0`), non-Float numerics, and `NaN` in
  `real()` caching
  Jason Lee, [#10](https://github.com/jlsync/pdf-core/pull/10)
- Resolve `Page#content` and `Page#dictionary` directly against `ObjectStore`
  and return isolated string copies from `Reference#to_s` and the bounded symbol
  cache
  Jason Lee, [#2](https://github.com/jlsync/pdf-core/pull/2)

## [0.10.0][] - 2024-03-05

### Changed

- Dropped Ruby 2.6
  Alexander Mankuta
- Improved serialization stability of PDF dicts
  Alexander Mankuta
- Relaxed requirements for rendering output. Not it only needs to support single
  #<< method.
  Alexander Mankuta
- CI improvememnts
  Peter Goldstein
- Reduced memory allocations and enhanced performance
  Thomas Leitner
- Updated documentation
  Alexander Mankuta

### Fixed

- Implemented `get_page_objects` method
  Thomas Leitner
- Document corruption in text operations on exception in user code
  Peter Goldstein
- Serialisation of literal strings and Time
  Thomas Leitner

## [0.9.0][] - 2020-10-24

## Changed

- Increased precision of real numbers to 5
  Alexander Mankuta
- Dropped 2.3 & 2.4 Ruby support
  Alexander Mankuta
- Updated code style
  Alexander Mankuta

## [0.8.1][] - 2018-04-28

### Fixed

- Make sure stamp streams are writable
  Alexander Mankuta
- Handle text rendering from frozen strings
  Alexander Mankuta

## [0.8.0][] - 2018-04-27

### Changed

- Minimum Ruby version is 2.3
  Alexander Mankuta
- Trailing fraction zeroes are removed from numbers
  Alexander Mankuta

## [0.7.0][] - 2017-03-03

### Changed

- *Breaking change*: `PDF::Core::PdfObject` method has been renamed to
  `PDF::Core::pdf_object`
  Alexander Mankuta

### Added

- Support for horizontal scaling
  Tom Sullivan, [#26](https://github.com/prawnpdf/pdf-core/pull/26)
- Support for character spacing
  Tom Sullivan, [#27](https://github.com/prawnpdf/pdf-core/pull/27)
- Support for crops, bleeds, trims, and art box
  Alexander Mankuta


## [0.6.1][] - 2016-02-21

### Fixed

- Fixed regex "/u over UTF-8 string" warning on Ruby 2
  Takahiro Yoshimura, [#21](https://github.com/prawnpdf/pdf-core/pull/21)


## [0.6.0][] - 2015-07-15

### Added

- A trailer can be assigned to DocumentState
  Robert Bousquet, [#16](https://github.com/prawnpdf/pdf-core/pull/16)

[0.11.0]: https://github.com/jlsync/pdf-core/compare/0.10.0...0.11.0
[0.10.0]: https://github.com/prawnpdf/pdf-core/compare/0.9.0...0.10.0
[0.9.0]: https://github.com/prawnpdf/pdf-core/compare/0.8.1...0.9.0
[0.8.1]: https://github.com/prawnpdf/pdf-core/compare/0.8.0...0.8.1
[0.8.0]: https://github.com/prawnpdf/pdf-core/compare/0.7.0...0.8.0
[0.7.0]: https://github.com/prawnpdf/pdf-core/compare/0.6.1...0.7.0
[0.6.1]: https://github.com/prawnpdf/pdf-core/compare/0.6.0...0.6.1
[0.6.0]: https://github.com/prawnpdf/pdf-core/compare/0.5.1...0.6.0
