// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of parser;

/**
 * An abstract string representation.
 */
abstract class ByteString extends IterableBase<int> implements SourceString {
  final List<int> bytes;
  final int offset;
  final int length;
  int _hashCode;

  ByteString(List<int> this.bytes, int this.offset, int this.length);

  String get charset;

  String slowToString() => new String.fromCharCodes(
      new Utf8Decoder(bytes, offset, length).decodeRest());

  String toString() => "ByteString(${slowToString()})";

  bool operator ==(other) {
    throw "should be overridden in subclass";
  }

  Iterator<int> get iterator => new Utf8Decoder(bytes, offset, length);

  int get hashCode {
    if (_hashCode == null) {
      _hashCode = computeHashCode();
    }
    return _hashCode;
  }

  int computeHashCode() {
    int code = 1;
    int end = offset + length;
    for (int i = offset; i < end; i++) {
      code += 19 * code + bytes[i];
    }
    return code;
  }

  printOn(StringBuffer sb) {
    sb.write(slowToString());
  }

  bool get isEmpty => length == 0;
  bool isPrivate() => !isEmpty && identical(bytes[offset], $_);

  String get stringValue => null;
}

/**
 * A string that consists purely of 7bit ASCII characters.
 */
class AsciiString extends ByteString {
  final String charset = "ASCII";

  AsciiString(List<int> bytes, int offset, int length)
    : super(bytes, offset, length);

  static AsciiString of(List<int> bytes, int offset, int length) {
    AsciiString string = new AsciiString(bytes, offset, length);
    return string;
  }

  Iterator<int> get iterator => new AsciiStringIterator(bytes);

  SourceString copyWithoutQuotes(int initial, int terminal) {
    return new AsciiString(bytes, offset + initial,
                           length - initial - terminal);
  }


  static AsciiString fromString(String string) {
    List<int> bytes = string.codeUnits;
    return AsciiString.of(bytes, 0, bytes.length);
  }
}


class AsciiStringIterator implements Iterator<int> {
  final List<int> bytes;
  int offset;
  final int end;
  int _current;

  AsciiStringIterator(List<int> bytes)
      : this.bytes = bytes, offset = 0, end = bytes.length;
  AsciiStringIterator.range(List<int> bytes, int from, int length)
      : this.bytes = bytes, offset = from, end = from + length;

  int get current => _current;
  bool moveNext() {
    if (offset < end) {
      _current = bytes[offset++];
      return true;
    }
    _current = null;
    return false;
  }
}


/**
 * A string that consists of characters that can be encoded as UTF-8.
 */
class Utf8String extends ByteString {
  final String charset = "UTF8";

  Utf8String(List<int> bytes, int offset, int length)
    : super(bytes, offset, length);

  static Utf8String of(List<int> bytes, int offset, int length) {
    return new Utf8String(bytes, offset, length);
  }

  static Utf8String fromString(String string) {
    throw "not implemented yet";
  }

  Iterator<int> get iterator => new Utf8Decoder(bytes, 0, length);

  SourceString copyWithoutQuotes(int initial, int terminal) {
    assert((){
      // Only allow dropping ASCII characters, to guarantee that
      // the resulting Utf8String is still valid.
      for (int i = 0; i < initial; i++) {
        if (bytes[offset + i] >= 0x80) return false;
      }
      for (int i = 0; i < terminal; i++) {
        if (bytes[offset + length - terminal + i] >= 0x80) return false;
      }
      return true;
    });
    // TODO(lrn): Check that first and last bytes use the same type of quotes.
    return new Utf8String(bytes, offset + initial,
                          length - initial - terminal);
  }
}

/**
 * A ByteString-valued token.
 */
class ByteStringToken extends Token {
  final ByteString value;

  ByteStringToken(PrecedenceInfo info, ByteString this.value, int charOffset)
    : super(info, charOffset);

  String toString() => value.toString();
}
