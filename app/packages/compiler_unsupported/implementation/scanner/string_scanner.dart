// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of scanner;

/**
 * Scanner that reads from a String and creates tokens that points to
 * substrings.
 */
class StringScanner extends ArrayBasedScanner<SourceString> {
  final String string;

  StringScanner(String this.string, {bool includeComments: false})
    : super(includeComments);

  int nextByte() => charAt(++byteOffset);

  int peek() => charAt(byteOffset + 1);

  int charAt(index)
      => (string.length > index) ? string.codeUnitAt(index) : $EOF;

  SourceString asciiString(int start, int offset) {
    return new SourceString.fromSubstring(string, start, byteOffset + offset);
  }

  SourceString utf8String(int start, int offset) {
    return new SourceString.fromSubstring(
        string, start, byteOffset + offset + 1);
  }

  void appendByteStringToken(PrecedenceInfo info, SourceString value) {
    // assert(kind != $a || keywords.get(value) == null);
    tail.next = new StringToken.fromSource(info, value, tokenStart);
    tail = tail.next;
  }

  void unmatchedBeginGroup(BeginGroupToken begin) {
    SourceString error = new SourceString('unmatched "${begin.stringValue}"');
    Token close =
        new StringToken.fromSource(BAD_INPUT_INFO, error, begin.charOffset);
    // We want to ensure that unmatched BeginGroupTokens are reported
    // as errors. However, the rest of the parser assume the groups
    // are well-balanced and will never look at the endGroup
    // token. This is a nice property that allows us to skip quickly
    // over correct code. By inserting an additional error token in
    // the stream, we can keep ignoring endGroup tokens.
    Token next =
        new StringToken.fromSource(BAD_INPUT_INFO, error, begin.charOffset);
    begin.endGroup = close;
    close.next = next;
    next.next = begin.next;
  }
}
