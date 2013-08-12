// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library mirrors;

import 'dart:async';

/**
 * The main interface for the whole mirror system.
 */
abstract class MirrorSystem {
  /**
   * Returns an unmodifiable map of all libraries in this mirror system.
   */
  Map<Uri, LibraryMirror> get libraries;

  /**
   * Returns an iterable of all libraries in the mirror system whose library
   * name is [libraryName].
   */
  Iterable<LibraryMirror> findLibrary(String libraryName) {
    return libraries.values.where(
        (library) => library.simpleName == libraryName);
  }

  /**
   * A mirror on the [:dynamic:] type.
   */
  TypeMirror get dynamicType;

  /**
   * A mirror on the [:void:] type.
   */
  TypeMirror get voidType;
}


/**
 * An entity in the mirror system.
 */
abstract class Mirror {
  static const String UNARY_MINUS = 'unary-';

  // TODO(johnniwinther): Do we need this on all mirrors?
  /**
   * Returns the mirror system which contains this mirror.
   */
  MirrorSystem get mirrors;
}

abstract class DeclarationMirror implements Mirror {
  /**
   * The simple name of the entity. The simple name is unique within the
   * scope of the entity declaration.
   *
   * The simple name is in most cases the declared single identifier name of
   * the entity, such as 'method' for a method [:void method() {...}:]. For an
   * unnamed constructor for [:class Foo:] the simple name is ''. For a
   * constructor for [:class Foo:] named 'named' the simple name is 'named'.
   * For a property [:foo:] the simple name of the getter method is 'foo' and
   * the simple name of the setter is 'foo='. For operators the simple name is
   * the operator itself, for example '+' for [:operator +:].
   *
   * The simple name for the unary minus operator is [UNARY_MINUS].
   */
  String get simpleName;

  /**
   * Returns the name of this entity qualified by is enclosing context. For
   * instance, the qualified name of a method 'method' in class 'Class' in
   * library 'library' is 'library.Class.method'.
   */
  String get qualifiedName;

  /**
   * The source location of this Dart language entity.
   */
  SourceLocation get location;

  /**
   * A mirror on the owner of this function. This is the declaration immediately
   * surrounding the reflectee.
   *
   * Note that for libraries, the owner will be [:null:].
   */
  DeclarationMirror get owner;

  /**
   * Is this declaration private?
   *
   * Note that for libraries, this will be [:false:].
   */
  bool get isPrivate;

  /**
   * Is this declaration top-level?
   *
   * This is defined to be equivalent to:
   *    [:mirror.owner != null && mirror.owner is LibraryMirror:]
   */
  bool get isTopLevel;

  /**
   * A list of the metadata associated with this declaration.
   */
  List<InstanceMirror> get metadata;

  /**
   * Looks up [name] in the scope of this declaration.
   *
   * [name] may be either a single identifier, like 'foo', or of the 
   * a prefixed identifier, like 'foo.bar', where 'foo' must be a prefix.
   * For methods and constructors, the scope includes the parameters. For
   * classes and typedefs, the scope includes the type variables.
   * For classes and class members, the scope includes inherited members.
   *
   * See also:
   *
   * * [Lexical Scope](https://www.dartlang.org/docs/dart-up-and-running/contents/ch02.html#ch02-lexical-scope)
   *   in Dart Up and Running.
   * * [Lexical Scoping](http://www.dartlang.org/docs/spec/latest/dart-language-specification.html#h.jb82efuudrc5)
   *   in the Dart Specification.
   */
  DeclarationMirror lookupInScope(String name);
}

abstract class ObjectMirror implements Mirror {
  /**
   * Invokes a getter and returns a mirror on the result. The getter
   * can be the implicit getter for a field or a user-defined getter
   * method.
   */
  InstanceMirror getField(String fieldName);
}

/**
 * An [InstanceMirror] reflects an instance of a Dart language object.
 */
abstract class InstanceMirror implements ObjectMirror {
  /**
   * A mirror on the type of the reflectee.
   */
  ClassMirror get type;

  /**
   * Does [reflectee] contain the instance reflected by this mirror?
   * This will always be true in the local case (reflecting instances
   * in the same isolate), but only true in the remote case if this
   * mirror reflects a simple value.
   *
   * A value is simple if one of the following holds:
   *  - the value is null
   *  - the value is of type [num]
   *  - the value is of type [bool]
   *  - the value is of type [String]
   */
  bool get hasReflectee;

  /**
   * If the [InstanceMirror] reflects an instance it is meaningful to
   * have a local reference to, we provide access to the actual
   * instance here.
   *
   * If you access [reflectee] when [hasReflectee] is false, an
   * exception is thrown.
   */
  get reflectee;
}

/**
 * Specialized [InstanceMirror] used for reflection on constant lists.
 */
abstract class ListInstanceMirror implements InstanceMirror {
  /**
   * Returns an instance mirror of the value at [index] or throws a [RangeError]
   * if the [index] is out of bounds.
   */
  InstanceMirror operator[](int index);

  /**
   * The number of elements in the list.
   */
  int get length;
}

/**
 * Specialized [InstanceMirror] used for reflection on constant maps.
 */
abstract class MapInstanceMirror implements InstanceMirror {
  /**
   * Returns a collection containing all the keys in the map.
   */
  Iterable<String> get keys;

  /**
   * Returns an instance mirror of the value for the given key or
   * null if key is not in the map.
   */
  InstanceMirror operator[](String key);

  /**
   * The number of {key, value} pairs in the map.
   */
  int get length;
}

/**
 * Specialized [InstanceMirror] used for reflection on type constants.
 */
abstract class TypeInstanceMirror implements InstanceMirror {
  /**
   * Returns the type mirror for the type represented by the reflected type
   * constant.
   */
  TypeMirror get representedType;
}

/**
 * Specialized [InstanceMirror] used for reflection on comments as metadata.
 */
abstract class CommentInstanceMirror implements InstanceMirror {
  /**
   * The comment text as written in the source text.
   */
  String get text;

  /**
   * The comment text without the start, end, and padding text.
   *
   * For example, if [text] is [: /** Comment text. */ :] then the [trimmedText]
   * is [: Comment text. :].
   */
  String get trimmedText;

  /**
   * Is [:true:] if this comment is a documentation comment.
   *
   * That is, that the comment is either enclosed in [: /** ... */ :] or starts
   * with [: /// :].
   */
  bool get isDocComment;
}

/**
 * Common interface for classes and libraries.
 */
abstract class ContainerMirror implements Mirror {

  /**
   * An immutable map from from names to mirrors for all members in this
   * container.
   */
  Map<String, MemberMirror> get members;
}

/**
 * A library.
 */
abstract class LibraryMirror implements ContainerMirror, DeclarationMirror {
  /**
   * An immutable map from from names to mirrors for all members in this
   * library.
   *
   * The members of a library are its top-level classes, functions, variables,
   * getters, and setters.
   */
  Map<String, MemberMirror> get members;

  /**
   * An immutable map from names to mirrors for all class
   * declarations in this library.
   */
  Map<String, ClassMirror> get classes;

  /**
   * An immutable map from names to mirrors for all function, getter,
   * and setter declarations in this library.
   */
  Map<String, MethodMirror> get functions;

  /**
   * An immutable map from names to mirrors for all getter
   * declarations in this library.
   */
  Map<String, MethodMirror> get getters;

  /**
   * An immutable map from names to mirrors for all setter
   * declarations in this library.
   */
  Map<String, MethodMirror> get setters;

  /**
   * An immutable map from names to mirrors for all variable
   * declarations in this library.
   */
  Map<String, VariableMirror> get variables;

  /**
   * Returns the canonical URI for this library.
   */
  Uri get uri;
}

/**
 * Common interface for classes, interfaces, typedefs and type variables.
 */
abstract class TypeMirror implements DeclarationMirror {
  /**
   * Returns the library in which this member resides.
   */
  LibraryMirror get library;

  /**
   * Is [:true:] iff this type is the [:Object:] type.
   */
  bool get isObject;

  /**
   * Is [:true:] iff this type is the [:dynamic:] type.
   */
  bool get isDynamic;

  /**
   * Is [:true:] iff this type is the void type.
   */
  bool get isVoid;

  /**
   * Is [:true:] iff this type is a type variable.
   */
  bool get isTypeVariable;

  /**
   * Is [:true:] iff this type is a typedef.
   */
  bool get isTypedef;

  /**
   * Is [:true:] iff this type is a function type.
   */
  bool get isFunction;
}

/**
 * A class or interface type.
 */
abstract class ClassMirror implements TypeMirror, ContainerMirror {
  /**
   * A mirror on the original declaration of this type.
   *
   * For most classes, they are their own original declaration.  For
   * generic classes, however, there is a distinction between the
   * original class declaration, which has unbound type variables, and
   * the instantiations of generic classes, which have bound type
   * variables.
   */
  ClassMirror get originalDeclaration;

  /**
   * Returns the super class of this type, or null if this type is [Object] or a
   * typedef.
   */
  ClassMirror get superclass;

  /**
   * Returns a list of the interfaces directly implemented by this type.
   */
  List<ClassMirror> get superinterfaces;

  /**
   * Is [:true:] iff this type is a class.
   */
  bool get isClass;

  /**
   * Is this the original declaration of this type?
   *
   * For most classes, they are their own original declaration.  For
   * generic classes, however, there is a distinction between the
   * original class declaration, which has unbound type variables, and
   * the instantiations of generic classes, which have bound type
   * variables.
   */
  bool get isOriginalDeclaration;

  /**
   * Is [:true:] if this class is declared abstract.
   */
  bool get isAbstract;

  /**
   * Returns a list of the type arguments for this type.
   */
  List<TypeMirror> get typeArguments;

  /**
   * Returns the list of type variables for this type.
   */
  List<TypeVariableMirror> get typeVariables;

  /**
   * An immutable map from from names to mirrors for all members of
   * this type.
   *
   * The members of a type are its methods, fields, getters, and
   * setters.  Note that constructors and type variables are not
   * considered to be members of a type.
   *
   * This does not include inherited members.
   */
  Map<String, MemberMirror> get members;

  /**
   * An immutable map from names to mirrors for all method,
   * declarations for this type.  This does not include getters and
   * setters.
   */
  Map<String, MethodMirror> get methods;

  /**
   * An immutable map from names to mirrors for all getter
   * declarations for this type.
   */
  Map<String, MethodMirror> get getters;

  /**
   * An immutable map from names to mirrors for all setter
   * declarations for this type.
   */
  Map<String, MethodMirror> get setters;

  /**
   * An immutable map from names to mirrors for all variable
   * declarations for this type.
   */
  Map<String, VariableMirror> get variables;

  /**
   * An immutable map from names to mirrors for all constructor
   * declarations for this type.
   */
  Map<String, MethodMirror> get constructors;
}

/**
 * A type parameter as declared on a generic type.
 */
abstract class TypeVariableMirror implements TypeMirror {
  /**
   * Returns the bound of the type parameter.
   */
  TypeMirror get upperBound;
}

/**
 * A function type.
 */
abstract class FunctionTypeMirror implements ClassMirror {
  /**
   * Returns the return type of this function type.
   */
  TypeMirror get returnType;

  /**
   * Returns the parameters for this function type.
   */
  List<ParameterMirror> get parameters;

  /**
   * Returns the call method for this function type.
   */
  MethodMirror get callMethod;
}

/**
 * A typedef.
 */
abstract class TypedefMirror implements ClassMirror {
  /**
   * The defining type for this typedef.
   *
   * For instance [:void f(int):] for a [:typedef void f(int):].
   */
  TypeMirror get value;
}

/**
 * A member of a type, i.e. a field, method or constructor.
 */
abstract class MemberMirror implements DeclarationMirror {
  /**
   * Is this member a constructor?
   */
  bool get isConstructor;

  /**
   * Is this member a variable?
   *
   * This is [:false:] for locals.
   */
  bool get isVariable;

  /**
   * Is this member a method?.
   *
   * This is [:false:] for constructors.
   */
  bool get isMethod;

  /**
   * Is this member declared static?
   */
  bool get isStatic;

  /**
   * Is this member a parameter?
   */
  bool get isParameter;
}

/**
 * A field.
 */
abstract class VariableMirror implements MemberMirror {

  /**
   * Returns true if this field is final.
   */
  bool get isFinal;

  /**
   * Returns true if this field is const.
   */
  bool get isConst;

  /**
   * Returns the type of this field.
   */
  TypeMirror get type;
}

/**
 * Common interface constructors and methods, including factories, getters and
 * setters.
 */
abstract class MethodMirror implements MemberMirror {
  /**
   * Returns the list of parameters for this method.
   */
  List<ParameterMirror> get parameters;

  /**
   * Returns the return type of this method.
   */
  TypeMirror get returnType;

  /**
   * Is the reflectee abstract?
   */
  bool get isAbstract;

  /**
   * Is the reflectee a regular function or method?
   *
   * A function or method is regular if it is not a getter, setter, or
   * constructor.  Note that operators, by this definition, are
   * regular methods.
   */
  bool get isRegularMethod;

  /**
   * Is the reflectee a const constructor?
   */
  bool get isConstConstructor;

  /**
   * Is the reflectee a generative constructor?
   */
  bool get isGenerativeConstructor;

  /**
   * Is the reflectee a redirecting constructor?
   */
  bool get isRedirectingConstructor;

  /**
   * Is the reflectee a factory constructor?
   */
  bool get isFactoryConstructor;

  /**
   * Is [:true:] if this method is a getter method.
   */
  bool get isGetter;

  /**
   * Is [:true:] if this method is a setter method.
   */
  bool get isSetter;

  /**
   * Is [:true:] if this method is an operator method.
   */
  bool get isOperator;
}

/**
 * A formal parameter.
 */
abstract class ParameterMirror implements VariableMirror {
  /**
   * Returns the type of this parameter.
   */
  TypeMirror get type;

  /**
   * Returns the default value for this parameter.
   */
  String get defaultValue;

  /**
   * Does this parameter have a default value?
   */
  bool get hasDefaultValue;

  /**
   * Is this parameter optional?
   */
  bool get isOptional;

  /**
   * Is this parameter named?
   */
  bool get isNamed;

  /**
   * Returns [:true:] iff this parameter is an initializing formal of a
   * constructor. That is, if it is of the form [:this.x:] where [:x:] is a
   * field.
   */
  bool get isInitializingFormal;

  /**
   * Returns the initialized field, if this parameter is an initializing formal.
   */
  VariableMirror get initializedField;
}

/**
 * A [SourceLocation] describes the span of an entity in Dart source code.
 * A [SourceLocation] with a non-zero [length] should be the minimum span that
 * encloses the declaration of the mirrored entity.
 */
abstract class SourceLocation {
  /**
   * The 1-based line number for this source location.
   *
   * A value of 0 means that the line number is unknown.
   */
  int get line;

  /**
   * The 1-based column number for this source location.
   *
   * A value of 0 means that the column number is unknown.
   */
  int get column;

  /**
   * The 0-based character offset into the [sourceText] where this source
   * location begins.
   *
   * A value of -1 means that the offset is unknown.
   */
  int get offset;

  /**
   * The number of characters in this source location.
   *
   * A value of 0 means that the [offset] is approximate.
   */
  int get length;

  /**
   * The text of the location span.
   */
  String get text;

  /**
   * Returns the URI where the source originated.
   */
  Uri get sourceUri;

  /**
   * Returns the text of this source.
   */
  String get sourceText;
}
