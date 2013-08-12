// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of types;

/**
 * A flat type mask is a type mask that has been flatten to contain a
 * base type.
 */
class FlatTypeMask implements TypeMask {

  static const int EMPTY    = 0;
  static const int EXACT    = 1;
  static const int SUBCLASS = 2;
  static const int SUBTYPE  = 3;

  final DartType base;
  final int flags;

  FlatTypeMask(DartType base, int kind, bool isNullable)
      : this.internal(base, (kind << 1) | (isNullable ? 1 : 0));

  FlatTypeMask.empty()
      : this.internal(null, (EMPTY << 1) | 1);
  FlatTypeMask.exact(DartType base)
      : this.internal(base, (EXACT << 1) | 1);
  FlatTypeMask.subclass(DartType base)
      : this.internal(base, (SUBCLASS << 1) | 1);
  FlatTypeMask.subtype(DartType base)
      : this.internal(base, (SUBTYPE << 1) | 1);

  FlatTypeMask.nonNullEmpty()
      : this.internal(null, EMPTY << 1);
  FlatTypeMask.nonNullExact(DartType base)
      : this.internal(base, EXACT << 1);
  FlatTypeMask.nonNullSubclass(DartType base)
      : this.internal(base, SUBCLASS << 1);
  FlatTypeMask.nonNullSubtype(DartType base)
      : this.internal(base, SUBTYPE << 1);

  FlatTypeMask.internal(DartType base, this.flags)
      : this.base = transformBase(base) {
    assert(base == null || !(isExact && base.isDynamic));
  }

  // TODO(kasperl): We temporarily transform the base to be the raw
  // variant of the type. Long term, we're going to keep the class
  // element corresponding to the type in the mask instead.
  static DartType transformBase(DartType base) {
    if (base == null) {
      return null;
    } else if (base.kind != TypeKind.INTERFACE) {
      assert(base.kind == TypeKind.INTERFACE);
      return null;
    } else {
      assert(!base.isMalformed);
      return base.asRaw();
    }
  }

  bool get isEmpty => (flags >> 1) == EMPTY;
  bool get isExact => (flags >> 1) == EXACT;
  bool get isNullable => (flags & 1) != 0;

  bool get isUnion => false;
  bool get isContainer => false;
  bool get isForwarding => false;
  bool get isElement => false;

  // TODO(kasperl): Get rid of these. They should not be a visible
  // part of the implementation because they make it hard to add
  // proper union types if we ever want to.
  bool get isSubclass => (flags >> 1) == SUBCLASS;
  bool get isSubtype => (flags >> 1) == SUBTYPE;

  TypeMask nullable() {
    return isNullable ? this : new FlatTypeMask.internal(base, flags | 1);
  }

  TypeMask nonNullable() {
    return isNullable ? new FlatTypeMask.internal(base, flags & ~1) : this;
  }

  TypeMask simplify(Compiler compiler) => this;

  bool contains(DartType type, Compiler compiler) {
    if (isEmpty) {
      return false;
    } else if (identical(base.element, type.element)) {
      return true;
    } else if (isExact) {
      return false;
    } else if (isSubclass) {
      return isSubclassOf(type, base, compiler);
    } else {
      assert(isSubtype);
      return isSubtypeOf(type, base, compiler);
    }
  }

  bool containsOnlyInt(Compiler compiler) {
    return base.element == compiler.intClass
        || base.element == compiler.backend.intImplementation;
  }

  bool containsOnlyDouble(Compiler compiler) {
    return base.element == compiler.doubleClass
        || base.element == compiler.backend.doubleImplementation;
  }

  bool containsOnlyNum(Compiler compiler) {
    return base.element == compiler.numClass
        || base.element == compiler.backend.numImplementation;
  }

  bool containsOnlyNull(Compiler compiler) {
    return base.element == compiler.nullClass
        || base.element == compiler.backend.nullImplementation;
  }

  bool containsOnlyBool(Compiler compiler) {
    return base.element == compiler.boolClass
        || base.element == compiler.backend.boolImplementation;
  }

  bool containsOnlyString(Compiler compiler) {
    return base.element == compiler.stringClass
        || base.element == compiler.backend.stringImplementation;
  }

  bool containsOnly(ClassElement cls) {
    return base.element == cls;
  }

  bool satisfies(ClassElement cls, Compiler compiler) {
    if (isEmpty) return false;
    return base.element == cls
        || isSubtypeOf(base, cls.computeType(compiler).asRaw(), compiler);
  }

  /**
   * Returns the [ClassElement] if this type represents a single class,
   * otherwise returns `null`.  This method is conservative.
   */
  ClassElement singleClass(Compiler compiler) {
    if (isEmpty) return null;
    if (isNullable) return null;  // It is Null and some other class.
    ClassElement element = base.element;
    if (isExact) {
      return element;
    } else if (isSubclass) {
      return compiler.world.hasAnySubclass(element) ? null : element;
    } else {
      assert(isSubtype);
      return null;
    }
  }

  /**
   * Returns whether or not this type mask contains all types.
   */
  bool containsAll(Compiler compiler) {
    if (isEmpty || isExact) return false;
    return identical(base.element, compiler.objectClass)
        || identical(base.element, compiler.dynamicClass);
  }

  TypeMask union(TypeMask other, Compiler compiler) {
    assert(other != null);
    if (other is! FlatTypeMask) return other.union(this, compiler);
    FlatTypeMask flatOther = other;
    if (isEmpty) {
      return isNullable ? flatOther.nullable() : flatOther;
    } else if (flatOther.isEmpty) {
      return flatOther.isNullable ? nullable() : this;
    } else if (base == flatOther.base) {
      return unionSame(flatOther, compiler);
    } else if (isSubclassOf(flatOther.base, base, compiler)) {
      return unionSubclass(flatOther, compiler);
    } else if (isSubclassOf(base, flatOther.base, compiler)) {
      return flatOther.unionSubclass(this, compiler);
    } else if (isSubtypeOf(flatOther.base, base, compiler)) {
      return unionSubtype(flatOther, compiler);
    } else if (isSubtypeOf(base, flatOther.base, compiler)) {
      return flatOther.unionSubtype(this, compiler);
    } else {
      return new UnionTypeMask._(<FlatTypeMask>[this, flatOther]);
    }
  }

  TypeMask unionSame(FlatTypeMask other, Compiler compiler) {
    assert(base == other.base);
    // The two masks share the base type, so we must chose the least
    // constraining kind (the highest) of the two. If either one of
    // the masks are nullable the result should be nullable too.
    int combined = (flags > other.flags)
        ? flags | (other.flags & 1)
        : other.flags | (flags & 1);
    if (flags == combined) {
      return this;
    } else if (other.flags == combined) {
      return other;
    } else {
      return new FlatTypeMask.internal(base, combined);
    }
  }

  TypeMask unionSubclass(FlatTypeMask other, Compiler compiler) {
    assert(isSubclassOf(other.base, base, compiler));
    int combined;
    if (isExact && other.isExact) {
      // Since the other mask is a subclass of this mask, we need the
      // resulting union to be a subclass too. If either one of the
      // masks are nullable the result should be nullable too.
      combined = (SUBCLASS << 1) | ((flags | other.flags) & 1);
    } else {
      // Both masks are at least subclass masks, so we pick the least
      // constraining kind (the highest) of the two. If either one of
      // the masks are nullable the result should be nullable too.
      combined = (flags > other.flags)
          ? flags | (other.flags & 1)
          : other.flags | (flags & 1);
    }
    return (flags != combined)
        ? new FlatTypeMask.internal(base, combined)
        : this;
  }

  TypeMask unionSubtype(FlatTypeMask other, Compiler compiler) {
    assert(isSubtypeOf(other.base, base, compiler));
    // Since the other mask is a subtype of this mask, we need the
    // resulting union to be a subtype too. If either one of the masks
    // are nullable the result should be nullable too.
    int combined = (SUBTYPE << 1) | ((flags | other.flags) & 1);
    return (flags != combined)
        ? new FlatTypeMask.internal(base, combined)
        : this;
  }

  TypeMask intersection(TypeMask other, Compiler compiler) {
    assert(other != null);
    if (other is! FlatTypeMask) return other.intersection(this, compiler);
    FlatTypeMask flatOther = other;
    if (isEmpty) {
      return flatOther.isNullable ? this : nonNullable();
    } else if (flatOther.isEmpty) {
      return isNullable ? flatOther : other.nonNullable();
    } else if (base == flatOther.base) {
      return intersectionSame(flatOther, compiler);
    } else if (isSubclassOf(flatOther.base, base, compiler)) {
      return intersectionSubclass(flatOther, compiler);
    } else if (isSubclassOf(base, flatOther.base, compiler)) {
      return flatOther.intersectionSubclass(this, compiler);
    } else if (isSubtypeOf(flatOther.base, base, compiler)) {
      return intersectionSubtype(flatOther, compiler);
    } else if (isSubtypeOf(base, flatOther.base, compiler)) {
      return flatOther.intersectionSubtype(this, compiler);
    } else {
      return intersectionDisjoint(flatOther, compiler);
    }
  }

  TypeMask intersectionSame(FlatTypeMask other, Compiler compiler) {
    assert(base == other.base);
    // The two masks share the base type, so we must chose the most
    // constraining kind (the lowest) of the two. Only if both masks
    // are nullable, will the result be nullable too.
    int combined = (flags < other.flags)
        ? flags & ((other.flags & 1) | ~1)
        : other.flags & ((flags & 1) | ~1);
    if (flags == combined) {
      return this;
    } else if (other.flags == combined) {
      return other;
    } else {
      return new FlatTypeMask.internal(base, combined);
    }
  }

  TypeMask intersectionSubclass(FlatTypeMask other, Compiler compiler) {
    assert(isSubclassOf(other.base, base, compiler));
    // If this mask isn't at least a subclass mask, then the
    // intersection with the other mask is empty.
    if (isExact) return intersectionEmpty(other);
    // Only the other mask puts constraints on the intersection mask,
    // so base the combined flags on the other mask. Only if both
    // masks are nullable, will the result be nullable too.
    int combined = other.flags & ((flags & 1) | ~1);
    if (other.flags == combined) {
      return other;
    } else {
      return new FlatTypeMask.internal(other.base, combined);
    }
  }

  TypeMask intersectionSubtype(FlatTypeMask other, Compiler compiler) {
    assert(isSubtypeOf(other.base, base, compiler));
    if (!isSubtype) return intersectionHelper(other, compiler);
    // Only the other mask puts constraints on the intersection mask,
    // so base the combined flags on the other mask. Only if both
    // masks are nullable, will the result be nullable too.
    int combined = other.flags & ((flags & 1) | ~1);
    if (other.flags == combined) {
      return other;
    } else {
      return new FlatTypeMask.internal(other.base, combined);
    }
  }

  TypeMask intersectionDisjoint(FlatTypeMask other, Compiler compiler) {
    assert(base != other.base);
    assert(!isSubtypeOf(base, other.base, compiler));
    assert(!isSubtypeOf(other.base, base, compiler));
    return intersectionHelper(other, compiler);
  }

  TypeMask intersectionHelper(FlatTypeMask other, Compiler compiler) {
    assert(base != other.base);
    assert(!isSubclassOf(base, other.base, compiler));
    assert(!isSubclassOf(other.base, base, compiler));
    // If one of the masks are exact or if both of them are subclass
    // masks, then the intersection is empty.
    if (isExact || other.isExact) return intersectionEmpty(other);
    if (isSubclass && other.isSubclass) return intersectionEmpty(other);
    assert(isSubtype || other.isSubtype);
    int kind = (isSubclass || other.isSubclass) ? SUBCLASS : SUBTYPE;
    // Compute the set of classes that are contained in both type masks.
    Set<ClassElement> common = commonContainedClasses(this, other, compiler);
    if (common == null || common.isEmpty) return intersectionEmpty(other);
    // Narrow down the candidates by only looking at common classes
    // that do not have a superclass or supertype that will be a
    // better candidate.
    Iterable<ClassElement> candidates = common.where((ClassElement each) {
      bool containsSuperclass = common.contains(each.supertype.element);
      // If the superclass is also a candidate, then we don't want to
      // deal with this class. If we're only looking for a subclass we
      // know we don't have to look at the list of interfaces because
      // they can never be in the common set.
      if (containsSuperclass || kind == SUBCLASS) return !containsSuperclass;
      // Run through the direct supertypes of the class. If the common
      // set contains the direct supertype of the class, we ignore the
      // the class because the supertype is a better candidate.
      for (Link link = each.interfaces; !link.isEmpty; link = link.tail) {
        if (common.contains(link.head.element)) return false;
      }
      return true;
    });
    // Run through the list of candidates and compute the union. The
    // result will only be nullable if both masks are nullable.
    int combined = (kind << 1) | (flags & other.flags & 1);
    TypeMask result;
    for (ClassElement each in candidates) {
      TypeMask mask = new FlatTypeMask.internal(each.rawType, combined);
      result = (result == null) ? mask : result.union(mask, compiler);
    }
    return result;
  }

  TypeMask intersectionEmpty(FlatTypeMask other) {
    return new TypeMask(null, EMPTY, isNullable && other.isNullable);
  }

  Iterable<ClassElement> containedClasses(Compiler compiler) {
    Iterable<ClassElement> self = [ base.element ];
    if (isExact) {
      return self;
    } else {
      Set<ClassElement> subset = containedSubset(this, compiler);
      return (subset == null) ? self : [ self, subset ].expand((x) => x);
    }
  }

  /**
   * Returns whether [element] will be the one used at runtime when being
   * invoked on an instance of [cls]. [selector] is used to ensure library
   * privacy is taken into account.
   */
  static bool hasElementIn(ClassElement cls,
                           Selector selector,
                           Element element,
                           Compiler compiler) {
    // Use [:implementation:] of [element]
    // because our function set only stores declarations.
    Element result = findMatchIn(cls, selector, compiler);
    return result == null
        ? false
        : result.implementation == element.implementation;
  }

  static Element findMatchIn(ClassElement cls,
                             Selector selector,
                             Compiler compiler) {
    // Use the [:implementation] of [cls] in case the found [element]
    // is in the patch class.
    return cls.implementation.lookupSelector(selector, compiler);
  }

  /**
   * Returns whether [element] is a potential target when being
   * invoked on this type mask. [selector] is used to ensure library
   * privacy is taken into account.
   */
  bool canHit(Element element, Selector selector, Compiler compiler) {
    assert(element.name == selector.name);
    if (isEmpty) {
      if (!isNullable) return false;
      return hasElementIn(
          compiler.backend.nullImplementation, selector, element, compiler);
    }

    // TODO(kasperl): Can't we just avoid creating typed selectors
    // based of function types?
    Element self = base.element;
    if (self.isTypedef()) {
      // A typedef is a function type that doesn't have any
      // user-defined members.
      return false;
    }

    ClassElement other = element.getEnclosingClass();
    if (compiler.backend.isNullImplementation(other)) {
      return isNullable;
    } else if (isExact) {
      return hasElementIn(self, selector, element, compiler);
    } else if (isSubclass) {
      return hasElementIn(self, selector, element, compiler)
          || other.isSubclassOf(self)
          || compiler.world.hasAnySubclassThatMixes(self, other);
    } else {
      assert(isSubtype);
      bool result = hasElementIn(self, selector, element, compiler)
          || other.implementsInterface(self)
          || compiler.world.hasAnySubclassThatImplements(other, base)
          || compiler.world.hasAnySubclassOfMixinUseThatImplements(other, base);
      if (result) return true;
      // If the class is used as a mixin, we have to check if the element
      // can be hit from any of the mixin applications.
      Iterable<ClassElement> mixinUses = compiler.world.mixinUses[self];
      if (mixinUses == null) return false;
      return mixinUses.any((mixinApplication) =>
           hasElementIn(mixinApplication, selector, element, compiler)
        || other.isSubclassOf(mixinApplication)
        || compiler.world.hasAnySubclassThatMixes(mixinApplication, other));
    }
  }

  /**
   * Returns whether a [selector] call on an instance of [cls]
   * will hit a method at runtime, and not go through [noSuchMethod].
   */
  static bool hasConcreteMatch(ClassElement cls,
                               Selector selector,
                               Compiler compiler) {
    Element element = findMatchIn(cls, selector, compiler);
    if (element == null) return false;

    if (element.isAbstract(compiler)) {
      ClassElement enclosingClass = element.getEnclosingClass();
      return hasConcreteMatch(enclosingClass.superclass, selector, compiler);
    }
    return selector.appliesUntyped(element, compiler);
  }

  /**
   * Returns whether a [selector] call will hit a method at runtime,
   * and not go through [noSuchMethod].
   */
  bool willHit(Selector selector, Compiler compiler) {
    Element cls;
    if (isEmpty) {
      if (!isNullable) return false;
      cls = compiler.backend.nullImplementation;
    } else {
      cls = base.element;
    }

    if (!cls.isAbstract(compiler)) {
      return hasConcreteMatch(cls, selector, compiler);
    }

    Set<ClassElement> subtypesToCheck;
    if (isExact) {
      return false;
    } else if (isSubtype) {
      subtypesToCheck = compiler.world.subtypesOf(cls);
    } else {
      assert(isSubclass);
      subtypesToCheck = compiler.world.subclassesOf(cls);
    }

    return subtypesToCheck != null
        && subtypesToCheck.every((ClassElement cls) {
              return cls.isAbstract(compiler)
                ? true
                : hasConcreteMatch(cls, selector, compiler);
           });
  }

  Element locateSingleElement(Selector selector, Compiler compiler) {
    if (isEmpty) return null;
    Iterable<Element> targets = compiler.world.allFunctions.filter(selector);
    if (targets.length != 1) return null;
    Element result = targets.first;
    ClassElement enclosing = result.getEnclosingClass();
    // We only return the found element if it is guaranteed to be
    // implemented on the exact receiver type. It could be found in a
    // subclass or in an inheritance-wise unrelated class in case of
    // subtype selectors.
    ClassElement cls = base.element;
    return (cls.isSubclassOf(enclosing)) ? result : null;
  }

  bool operator ==(var other) {
    if (other is !FlatTypeMask) return false;
    FlatTypeMask otherMask = other;
    return (flags == otherMask.flags) && (base == otherMask.base);
  }

  int get hashCode {
    return (base == null ? 0 : base.hashCode) + 31 * flags.hashCode;
  }

  String toString() {
    if (isEmpty) return isNullable ? '[null]' : '[empty]';
    StringBuffer buffer = new StringBuffer();
    if (isNullable) buffer.write('null|');
    if (isExact) buffer.write('exact=');
    if (isSubclass) buffer.write('subclass=');
    if (isSubtype) buffer.write('subtype=');
    buffer.write(base.element.name.slowToString());
    return "[$buffer]";
  }

  static bool isSubclassOf(DartType x, DartType y, Compiler compiler) {
    ClassElement xElement = x.element;
    ClassElement yElement = y.element;
    Set<ClassElement> subclasses = compiler.world.subclassesOf(yElement);
    return (subclasses != null) ? subclasses.contains(xElement) : false;
  }

  static bool isSubtypeOf(DartType x, DartType y, Compiler compiler) {
    ClassElement xElement = x.element;
    ClassElement yElement = y.element;
    Set<ClassElement> subtypes = compiler.world.subtypesOf(yElement);
    return (subtypes != null) ? subtypes.contains(xElement) : false;
  }

  static Set<ClassElement> commonContainedClasses(FlatTypeMask x,
                                                  FlatTypeMask y,
                                                  Compiler compiler) {
    Set<ClassElement> xSubset = containedSubset(x, compiler);
    if (xSubset == null) return null;
    Set<ClassElement> ySubset = containedSubset(y, compiler);
    if (ySubset == null) return null;
    Set<ClassElement> smallSet, largeSet;
    if (xSubset.length <= ySubset.length) {
      smallSet = xSubset;
      largeSet = ySubset;
    } else {
      smallSet = ySubset;
      largeSet = xSubset;
    }
    var result = smallSet.where((ClassElement each) => largeSet.contains(each));
    return result.toSet();
  }

  static Set<ClassElement> containedSubset(FlatTypeMask x, Compiler compiler) {
    ClassElement element = x.base.element;
    if (x.isExact) {
      return null;
    } else if (x.isSubclass) {
      return compiler.world.subclassesOf(element);
    } else {
      assert(x.isSubtype);
      return compiler.world.subtypesOf(element);
    }
  }
}
