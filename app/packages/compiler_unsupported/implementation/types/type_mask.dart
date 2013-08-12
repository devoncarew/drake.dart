// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of types;

/**
 * A type mask represents a set of contained classes, but the
 * operations on it are not guaranteed to be precise and they may
 * yield conservative answers that contain too many classes.
 */
abstract class TypeMask {
  factory TypeMask(DartType base, int kind, bool isNullable)
      => new FlatTypeMask(base, kind, isNullable);

  factory TypeMask.empty() => new FlatTypeMask.empty();

  factory TypeMask.exact(DartType base) => new FlatTypeMask.exact(base);
  factory TypeMask.subclass(DartType base) => new FlatTypeMask.subclass(base);
  factory TypeMask.subtype(DartType base) => new FlatTypeMask.subtype(base);

  factory TypeMask.nonNullEmpty()
      => new FlatTypeMask.nonNullEmpty();
  factory TypeMask.nonNullExact(DartType base)
      => new FlatTypeMask.nonNullExact(base);
  factory TypeMask.nonNullSubclass(DartType base)
      => new FlatTypeMask.nonNullSubclass(base);
  factory TypeMask.nonNullSubtype(DartType base)
      => new FlatTypeMask.nonNullSubtype(base);

  factory TypeMask.unionOf(Iterable<TypeMask> masks, Compiler compiler) {
    return UnionTypeMask.unionOf(masks, compiler);
  }

  /**
   * Returns a nullable variant of [this] type mask.
   */
  TypeMask nullable();

  /**
   * Returns a non-nullable variant of [this] type mask.
   */
  TypeMask nonNullable();

  TypeMask simplify(Compiler compiler);

  bool get isEmpty;
  bool get isNullable;
  bool get isExact;

  bool get isUnion;
  bool get isContainer;
  bool get isForwarding;
  bool get isElement;

  bool containsOnlyInt(Compiler compiler);
  bool containsOnlyDouble(Compiler compiler);
  bool containsOnlyNum(Compiler compiler);
  bool containsOnlyNull(Compiler compiler);
  bool containsOnlyBool(Compiler compiler);
  bool containsOnlyString(Compiler compiler);
  bool containsOnly(ClassElement element);
  
  /**
   * Returns whether this type mask is an instance of [cls].
   */
  bool satisfies(ClassElement cls, Compiler compiler);

  /**
   * Returns whether or not this type mask contains the given type.
   */
  bool contains(DartType type, Compiler compiler);

  /**
   * Returns whether or not this type mask contains all types.
   */
  bool containsAll(Compiler compiler);

  /**
   * Returns the [ClassElement] if this type represents a single class,
   * otherwise returns `null`.  This method is conservative.
   */
  ClassElement singleClass(Compiler compiler);

  /**
   * Returns the classes this type mask can be.
   */
  Iterable<ClassElement> containedClasses(Compiler compiler);

  /**
   * Returns a type mask representing the union of [this] and [other].
   */
  TypeMask union(TypeMask other, Compiler compiler);

  /**
   * Returns a type mask representing the intersection of [this] and [other].
   */
  TypeMask intersection(TypeMask other, Compiler compiler);

  /**
   * Returns whether a [selector] call will hit a method at runtime,
   * and not go through [noSuchMethod].
   */
  bool willHit(Selector selector, Compiler compiler);

  /**
   * Returns whether [element] is a potential target when being
   * invoked on this type mask. [selector] is used to ensure library
   * privacy is taken into account.
   */
  bool canHit(Element element, Selector selector, Compiler compiler);

  /**
   * Returns the [element] that is known to always be hit at runtime
   * on this mask. Returns null if there is none.
   */
  Element locateSingleElement(Selector selector, Compiler compiler);
}
