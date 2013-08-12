// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library elements;


import 'modelx.dart';
import '../tree/tree.dart';
import '../util/util.dart';
import '../resolution/resolution.dart';

import '../dart2jslib.dart' show InterfaceType,
                                 DartType,
                                 TypeVariableType,
                                 TypedefType,
                                 MessageKind,
                                 DiagnosticListener,
                                 Script,
                                 FunctionType,
                                 SourceString,
                                 Selector,
                                 Constant,
                                 Compiler;

import '../dart_types.dart';

import '../scanner/scannerlib.dart' show Token,
                                         isUserDefinableOperator,
                                         isMinusOperator;

const int STATE_NOT_STARTED = 0;
const int STATE_STARTED = 1;
const int STATE_DONE = 2;

class ElementCategory {
  /**
   * Represents things that we don't expect to find when looking in a
   * scope.
   */
  static const int NONE = 0;

  /** Field, parameter, or variable. */
  static const int VARIABLE = 1;

  /** Function, method, or foreign function. */
  static const int FUNCTION = 2;

  static const int CLASS = 4;

  static const int PREFIX = 8;

  /** Constructor or factory. */
  static const int FACTORY = 16;

  static const int ALIAS = 32;

  static const int SUPER = 64;

  /** Type variable */
  static const int TYPE_VARIABLE = 128;

  static const int IMPLIES_TYPE = CLASS | ALIAS | TYPE_VARIABLE;
}

class ElementKind {
  final String id;
  final int category;

  const ElementKind(String this.id, this.category);

  static const ElementKind VARIABLE =
      const ElementKind('variable', ElementCategory.VARIABLE);
  static const ElementKind PARAMETER =
      const ElementKind('parameter', ElementCategory.VARIABLE);
  // Parameters in constructors that directly initialize fields. For example:
  // [:A(this.field):].
  static const ElementKind FIELD_PARAMETER =
      const ElementKind('field_parameter', ElementCategory.VARIABLE);
  static const ElementKind FUNCTION =
      const ElementKind('function', ElementCategory.FUNCTION);
  static const ElementKind CLASS =
      const ElementKind('class', ElementCategory.CLASS);
  static const ElementKind GENERATIVE_CONSTRUCTOR =
      const ElementKind('generative_constructor', ElementCategory.FACTORY);
  static const ElementKind FIELD =
      const ElementKind('field', ElementCategory.VARIABLE);
  static const ElementKind VARIABLE_LIST =
      const ElementKind('variable_list', ElementCategory.NONE);
  static const ElementKind FIELD_LIST =
      const ElementKind('field_list', ElementCategory.NONE);
  static const ElementKind GENERATIVE_CONSTRUCTOR_BODY =
      const ElementKind('generative_constructor_body', ElementCategory.NONE);
  static const ElementKind COMPILATION_UNIT =
      const ElementKind('compilation_unit', ElementCategory.NONE);
  static const ElementKind GETTER =
      const ElementKind('getter', ElementCategory.NONE);
  static const ElementKind SETTER =
      const ElementKind('setter', ElementCategory.NONE);
  static const ElementKind TYPE_VARIABLE =
      const ElementKind('type_variable', ElementCategory.TYPE_VARIABLE);
  static const ElementKind ABSTRACT_FIELD =
      const ElementKind('abstract_field', ElementCategory.VARIABLE);
  static const ElementKind LIBRARY =
      const ElementKind('library', ElementCategory.NONE);
  static const ElementKind PREFIX =
      const ElementKind('prefix', ElementCategory.PREFIX);
  static const ElementKind TYPEDEF =
      const ElementKind('typedef', ElementCategory.ALIAS);

  static const ElementKind STATEMENT =
      const ElementKind('statement', ElementCategory.NONE);
  static const ElementKind LABEL =
      const ElementKind('label', ElementCategory.NONE);
  static const ElementKind VOID =
      const ElementKind('void', ElementCategory.NONE);

  static const ElementKind AMBIGUOUS =
      const ElementKind('ambiguous', ElementCategory.NONE);
  static const ElementKind ERROR =
      const ElementKind('error', ElementCategory.NONE);
  static const ElementKind MALFORMED_TYPE =
      const ElementKind('malformed', ElementCategory.NONE);

  toString() => id;
}

/**
 * A declared element of a program.
 *
 * The declared elements of a program include classes, methods,
 * fields, variables, parameters, etc.
 *
 * Sometimes it makes sense to construct "synthetic" elements that
 * have not been declared anywhere in a program, for example, there
 * are elements corresponding to "dynamic", "null", and unresolved
 * references.
 *
 * Elements are distinct from types ([DartType]). For example, there
 * is one declaration of the class List, but several related types,
 * for example, List, List<int>, List<String>, etc.
 *
 * Elements are distinct from AST nodes ([Node]), and there normally is a
 * one-to-one correspondence between an AST node and an element
 * (except that not all kinds of AST nodes have an associated
 * element).
 *
 * AST nodes represent precisely what is written in source code, for
 * example, when a user writes "class MyClass {}", the corresponding
 * AST node does not have a superclass. On the other hand, the
 * corresponding element (once fully resolved) will record the
 * information about the implicit superclass as defined by the
 * language semantics.
 *
 * Generally, the contents of a method are represented as AST nodes
 * without additional elements, but things like local functions, local
 * variables, and labels have a corresponding element.
 *
 * We generally say that scanning, parsing, resolution, and type
 * checking comprise the "front-end" of the compiler. The "back-end"
 * includes things like SSA graph construction, optimizations, and
 * code generation.
 *
 * The front-end data structures are designed to be reusable by
 * several back-ends.  For example, we may want to support emitting
 * minified Dart and JavaScript code in one go.  Also, we're planning
 * on adding an incremental compilation server that should be able to
 * reuse elements between compilations.  So to keep things simple, it
 * is best if the backends avoid setting state directly in elements.
 * It is better to keep such state in a table on the side.
 */
abstract class Element implements Spannable {
  SourceString get name;
  ElementKind get kind;
  Modifiers get modifiers;
  Element get enclosingElement;
  Link<MetadataAnnotation> get metadata;

  Node parseNode(DiagnosticListener listener);
  DartType computeType(Compiler compiler);

  bool isFunction();
  bool isConstructor();
  bool isClosure();
  bool isMember();
  bool isInstanceMember();

  bool isFactoryConstructor();
  bool isGenerativeConstructor();
  bool isGenerativeConstructorBody();
  bool isCompilationUnit();
  bool isClass();
  bool isPrefix();
  bool isVariable();
  bool isParameter();
  bool isStatement();
  bool isTypedef();
  bool isTypeVariable();
  bool isField();
  bool isFieldParameter();
  bool isAbstractField();
  bool isGetter();
  bool isSetter();
  bool isAccessor();
  bool isLibrary();
  bool isErroneous();
  bool isAmbiguous();

  bool isTopLevel();
  bool isAssignable();
  bool isNative();

  bool impliesType();

  Token position();

  CompilationUnitElement getCompilationUnit();
  LibraryElement getLibrary();
  LibraryElement getImplementationLibrary();
  ClassElement getEnclosingClass();
  Element getEnclosingClassOrCompilationUnit();
  Element getEnclosingMember();
  Element getOutermostEnclosingMemberOrTopLevel();

  FunctionElement asFunctionElement();

  bool get isPatched;
  bool get isPatch;
  bool get isImplementation;
  bool get isDeclaration;
  bool get isSynthesized;
  bool get isForwardingConstructor;
  bool get isMixinApplication;

  Element get implementation;
  Element get declaration;
  Element get patch;
  Element get origin;

  bool hasFixedBackendName();
  String fixedBackendName();

  bool isAbstract(Compiler compiler);
  bool isForeign(Compiler compiler);

  void addMetadata(MetadataAnnotation annotation);
  void setNative(String name);
  void setFixedBackendName(String name);

  Scope buildScope();

  /// If the element is a forwarding constructor, [targetConstructor] holds
  /// the generative constructor that the forwarding constructor points to
  /// (possibly via other forwarding constructors).
  FunctionElement get targetConstructor;

  void diagnose(Element context, DiagnosticListener listener);
}

class Elements {
  static bool isUnresolved(Element e) {
    return e == null || e.isErroneous();
  }
  static bool isErroneousElement(Element e) => e != null && e.isErroneous();

  static bool isClass(Element e) => e != null && e.kind == ElementKind.CLASS;
  static bool isTypedef(Element e) {
    return e != null && e.kind == ElementKind.TYPEDEF;
  }

  static bool isLocal(Element element) {
    return !Elements.isUnresolved(element)
            && !element.isInstanceMember()
            && !isStaticOrTopLevelField(element)
            && !isStaticOrTopLevelFunction(element)
            && (identical(element.kind, ElementKind.VARIABLE) ||
                identical(element.kind, ElementKind.PARAMETER) ||
                identical(element.kind, ElementKind.FUNCTION));
  }

  static bool isInstanceField(Element element) {
    return !Elements.isUnresolved(element)
           && element.isInstanceMember()
           && (identical(element.kind, ElementKind.FIELD)
               || identical(element.kind, ElementKind.GETTER)
               || identical(element.kind, ElementKind.SETTER));
  }

  static bool isStaticOrTopLevel(Element element) {
    // TODO(ager): This should not be necessary when patch support has
    // been reworked.
    if (!Elements.isUnresolved(element)
        && element.modifiers.isStatic()) {
      return true;
    }
    return !Elements.isUnresolved(element)
           && !element.isInstanceMember()
           && !element.isPrefix()
           && element.enclosingElement != null
           && (element.enclosingElement.kind == ElementKind.CLASS ||
               element.enclosingElement.kind == ElementKind.COMPILATION_UNIT ||
               element.enclosingElement.kind == ElementKind.LIBRARY);
  }

  static bool isInStaticContext(Element element) {
    if (isUnresolved(element)) return true;
    if (element.enclosingElement.isClosure()) {
      var closureClass = element.enclosingElement;
      element = closureClass.methodElement;
    }
    Element outer = element.getOutermostEnclosingMemberOrTopLevel();
    if (isUnresolved(outer)) return true;
    if (outer.isTopLevel()) return true;
    if (outer.isGenerativeConstructor()) return false;
    if (outer.isInstanceMember()) return false;
    return true;
  }

  static bool isStaticOrTopLevelField(Element element) {
    return isStaticOrTopLevel(element)
           && (identical(element.kind, ElementKind.FIELD)
               || identical(element.kind, ElementKind.GETTER)
               || identical(element.kind, ElementKind.SETTER));
  }

  static bool isStaticOrTopLevelFunction(Element element) {
    return isStaticOrTopLevel(element)
           && (identical(element.kind, ElementKind.FUNCTION));
  }

  static bool isInstanceMethod(Element element) {
    return !Elements.isUnresolved(element)
           && element.isInstanceMember()
           && (identical(element.kind, ElementKind.FUNCTION));
  }

  static bool isInstanceSend(Send send, TreeElements elements) {
    Element element = elements[send];
    if (element == null) return !isClosureSend(send, element);
    return isInstanceMethod(element) || isInstanceField(element);
  }

  static bool isClosureSend(Send send, Element element) {
    if (send.isPropertyAccess) return false;
    if (send.receiver != null) return false;
    Node selector = send.selector;
    // this().
    if (selector.isThis()) return true;
    // (o)() or foo()().
    if (element == null && selector.asIdentifier() == null) return true;
    if (element == null) return false;
    // foo() with foo a local or a parameter.
    return isLocal(element);
  }

  static SourceString reconstructConstructorNameSourceString(Element element) {
    if (element.name == const SourceString('')) {
      return element.getEnclosingClass().name;
    } else {
      return new SourceString(reconstructConstructorName(element));
    }
  }
  
  // TODO(johnniwinther): Remove this method.
  static String reconstructConstructorName(Element element) {
    String className = element.getEnclosingClass().name.slowToString();
    if (element.name == const SourceString('')) {
      return className;
    } else {
      return '$className\$${element.name.slowToString()}';
    }
  }

  /**
   * Map an operator-name to a valid Dart identifier.
   *
   * For non-operator names, this metod just returns its input.
   *
   * The results returned from this method are guaranteed to be valid
   * JavaScript identifers, except it may include reserved words for
   * non-operator names.
   */
  static SourceString operatorNameToIdentifier(SourceString name) {
    if (name == null) return null;
    String value = name.stringValue;
    if (value == null) {
      return name;
    } else if (identical(value, '==')) {
      return const SourceString(r'operator$eq');
    } else if (identical(value, '~')) {
      return const SourceString(r'operator$not');
    } else if (identical(value, '[]')) {
      return const SourceString(r'operator$index');
    } else if (identical(value, '[]=')) {
      return const SourceString(r'operator$indexSet');
    } else if (identical(value, '*')) {
      return const SourceString(r'operator$mul');
    } else if (identical(value, '/')) {
      return const SourceString(r'operator$div');
    } else if (identical(value, '%')) {
      return const SourceString(r'operator$mod');
    } else if (identical(value, '~/')) {
      return const SourceString(r'operator$tdiv');
    } else if (identical(value, '+')) {
      return const SourceString(r'operator$add');
    } else if (identical(value, '<<')) {
      return const SourceString(r'operator$shl');
    } else if (identical(value, '>>')) {
      return const SourceString(r'operator$shr');
    } else if (identical(value, '>=')) {
      return const SourceString(r'operator$ge');
    } else if (identical(value, '>')) {
      return const SourceString(r'operator$gt');
    } else if (identical(value, '<=')) {
      return const SourceString(r'operator$le');
    } else if (identical(value, '<')) {
      return const SourceString(r'operator$lt');
    } else if (identical(value, '&')) {
      return const SourceString(r'operator$and');
    } else if (identical(value, '^')) {
      return const SourceString(r'operator$xor');
    } else if (identical(value, '|')) {
      return const SourceString(r'operator$or');
    } else if (identical(value, '-')) {
      return const SourceString(r'operator$sub');
    } else if (identical(value, 'unary-')) {
      return const SourceString(r'operator$negate');
    } else {
      return name;
    }
  }

  static SourceString constructOperatorNameOrNull(SourceString op,
                                                  bool isUnary) {
    String value = op.stringValue;
    if (isMinusOperator(value)) {
      return isUnary ? const SourceString('unary-') : op;
    } else if (isUserDefinableOperator(value)) {
      return op;
    } else {
      return null;
    }
  }

  static SourceString constructOperatorName(SourceString op, bool isUnary) {
    SourceString operatorName = constructOperatorNameOrNull(op, isUnary);
    if (operatorName == null) throw 'Unhandled operator: ${op.slowToString()}';
    else return operatorName;
  }

  static SourceString mapToUserOperatorOrNull(SourceString op) {
    String value = op.stringValue;

    if (identical(value, '!=')) return const SourceString('==');
    if (identical(value, '*=')) return const SourceString('*');
    if (identical(value, '/=')) return const SourceString('/');
    if (identical(value, '%=')) return const SourceString('%');
    if (identical(value, '~/=')) return const SourceString('~/');
    if (identical(value, '+=')) return const SourceString('+');
    if (identical(value, '-=')) return const SourceString('-');
    if (identical(value, '<<=')) return const SourceString('<<');
    if (identical(value, '>>=')) return const SourceString('>>');
    if (identical(value, '&=')) return const SourceString('&');
    if (identical(value, '^=')) return const SourceString('^');
    if (identical(value, '|=')) return const SourceString('|');

    return null;
  }

  static SourceString mapToUserOperator(SourceString op) {
    SourceString userOperator = mapToUserOperatorOrNull(op);
    if (userOperator == null) throw 'Unhandled operator: ${op.slowToString()}';
    else return userOperator;
  }

  static bool isNumberOrStringSupertype(Element element, Compiler compiler) {
    LibraryElement coreLibrary = compiler.coreLibrary;
    return (element == coreLibrary.find(const SourceString('Comparable')));
  }

  static bool isStringOnlySupertype(Element element, Compiler compiler) {
    LibraryElement coreLibrary = compiler.coreLibrary;
    return element == coreLibrary.find(const SourceString('Pattern'));
  }

  static bool isListSupertype(Element element, Compiler compiler) {
    LibraryElement coreLibrary = compiler.coreLibrary;
    return element == coreLibrary.find(const SourceString('Iterable'));
  }

  /// A `compareTo` function that places [Element]s in a consistent order based
  /// on the source code order.
  static int compareByPosition(Element a, Element b) {
    int r = a.getLibrary().compareTo(b.getLibrary());
    if (r != 0) return r;
    r = a.getCompilationUnit().compareTo(b.getCompilationUnit());
    if (r != 0) return r;
    Token positionA = a.position();
    Token positionB = b.position();
    int offsetA = positionA == null ? -1 : positionA.charOffset;
    int offsetB = positionB == null ? -1 : positionB.charOffset;
    r = offsetA.compareTo(offsetB);
    if (r != 0) return r;
    r = a.name.slowToString().compareTo(b.name.slowToString());
    if (r != 0) return r;
    // Same file, position and name.  If this happens, we should find out why
    // and make the order total and independent of hashCode.
    return a.hashCode.compareTo(b.hashCode);
  }

  static List<Element> sortedByPosition(Iterable<Element> elements) {
    return elements.toList()..sort(compareByPosition);
  }

  static bool isFixedListConstructorCall(Element element,
                                         Send node,
                                         Compiler compiler) {
    return element == compiler.unnamedListConstructor
        && node.isCall
        && !node.arguments.isEmpty
        && node.arguments.tail.isEmpty;
  }

  static bool isGrowableListConstructorCall(Element element,
                                            Send node,
                                            Compiler compiler) {
    return element == compiler.unnamedListConstructor
        && node.isCall
        && node.arguments.isEmpty;
  }

  static bool isFilledListConstructorCall(Element element,
                                          Send node,
                                          Compiler compiler) {
    return element == compiler.filledListConstructor
        && node.isCall
        && !node.arguments.isEmpty
        && !node.arguments.tail.isEmpty
        && node.arguments.tail.tail.isEmpty;
  }

  static bool switchStatementHasContinue(SwitchStatement node,
                                         TreeElements elements) {
    for (SwitchCase switchCase in node.cases) {
      for (Node labelOrCase in switchCase.labelsAndCases) {
        Node label = labelOrCase.asLabel();
        if (label != null) {
          LabelElement labelElement = elements[label];
          if (labelElement != null && labelElement.isContinueTarget) {
            return true;
          }
        }
      }
    }
    return false;
  }

  static bool switchStatementHasDefault(SwitchStatement node) {
    for (SwitchCase switchCase in node.cases) {
      if (switchCase.isDefaultCase) return true;
    }
    return false;
  }

  static bool isUnusedLabel(LabeledStatement node, TreeElements elements) {
    Node body = node.statement;
    TargetElement element = elements[body];
    // Labeled statements with no element on the body have no breaks.
    // A different target statement only happens if the body is itself
    // a break or continue for a different target. In that case, this
    // label is also always unused.
    return element == null || element.statement != body;
  }
}

abstract class ErroneousElement extends Element implements FunctionElement {
  MessageKind get messageKind;
  Map get messageArguments;
}

abstract class AmbiguousElement extends Element {
  MessageKind get messageKind;
  Map get messageArguments;
  Element get existingElement;
  Element get newElement;
}

// TODO(kasperl): This probably shouldn't be called an element. It's
// just an interface shared by classes and libraries.
abstract class ScopeContainerElement {
  Element localLookup(SourceString elementName);

  void forEachLocalMember(f(Element element));
}

abstract class CompilationUnitElement extends Element {
  Script get script;
  PartOf get partTag;

  void forEachLocalMember(f(Element element));
  void addMember(Element element, DiagnosticListener listener);
  void setPartOf(PartOf tag, DiagnosticListener listener);
  bool get hasMembers;

  int compareTo(CompilationUnitElement other);
}

abstract class LibraryElement extends Element implements ScopeContainerElement {
  /**
   * The canonical uri for this library.
   *
   * For user libraries the canonical uri is the script uri. For platform
   * libraries the canonical uri is of the form [:dart:x:].
   */
  Uri get canonicalUri;
  CompilationUnitElement get entryCompilationUnit;
  Link<CompilationUnitElement> get compilationUnits;
  Link<LibraryTag> get tags;
  LibraryName get libraryTag;
  Link<Element> get exports;

  /**
   * [:true:] if this library is part of the platform, that is its canonical
   * uri has the scheme 'dart'.
   */
  bool get isPlatformLibrary;

  /**
   * [:true:] if this library is a platform library whose path starts with
   * an underscore.
   */
  bool get isInternalLibrary;
  bool get canUseNative;
  bool get exportsHandled;

  // TODO(kasperl): We should try to get rid of these.
  void set canUseNative(bool value);
  void set libraryTag(LibraryName value);

  LibraryElement get implementation;

  void addCompilationUnit(CompilationUnitElement element);
  void addTag(LibraryTag tag, DiagnosticListener listener);
  void addImport(Element element, Import import, DiagnosticListener listener);

  /// Record which element an import or export tag resolved to.
  /// (Belongs on builder object).
  void recordResolvedTag(LibraryDependency tag, LibraryElement library);

  /// Return the library element corresponding to an import or export.
  LibraryElement getLibraryFromTag(LibraryDependency tag);

  void addMember(Element element, DiagnosticListener listener);
  void addToScope(Element element, DiagnosticListener listener);

  // TODO(kasperl): Get rid of this method.
  Iterable<Element> getNonPrivateElementsInScope();

  void setExports(Iterable<Element> exportedElements);

  Element find(SourceString elementName);
  Element findLocal(SourceString elementName);
  void forEachExport(f(Element element));

  bool hasLibraryName();
  String getLibraryOrScriptName();

  int compareTo(LibraryElement other);
}

abstract class PrefixElement extends Element {
  Map<SourceString, Element> get imported;
  Element lookupLocalMember(SourceString memberName);
}

abstract class TypedefElement extends Element
    implements TypeDeclarationElement {
  TypedefType get rawType;
  DartType get alias;
  FunctionSignature get functionSignature;
  Link<DartType> get typeVariables;

  bool get isResolved;

  // TODO(kasperl): Try to get rid of these setters.
  void set alias(DartType value);
  void set functionSignature(FunctionSignature value);
}

abstract class VariableElement extends Element {
  VariableListElement get variables;

  // TODO(kasperl): Try to get rid of this.
  Expression get cachedNode;
}

abstract class FieldParameterElement extends VariableElement {
  VariableElement get fieldElement;
}

abstract class VariableListElement extends Element {
  DartType get type;
  FunctionSignature get functionSignature;

  // TODO(kasperl): Try to get rid of this.
  void set type(DartType value);
}

/**
 * A synthetic element which holds a getter and/or a setter.
 *
 * This element unifies handling of fields and getters/setters.  When
 * looking at code like "foo.x", we don't have to look for both a
 * field named "x", a getter named "x", and a setter named "x=".
 */
abstract class AbstractFieldElement extends Element {
  FunctionElement get getter;
  FunctionElement get setter;
}

abstract class FunctionSignature {
  DartType get returnType;
  Link<Element> get requiredParameters;
  Link<Element> get optionalParameters;

  int get requiredParameterCount;
  int get optionalParameterCount;
  bool get optionalParametersAreNamed;
  Element get firstOptionalParameter;

  int get parameterCount;
  List<Element> get orderedOptionalParameters;

  void forEachParameter(void function(Element parameter));
  void forEachRequiredParameter(void function(Element parameter));
  void forEachOptionalParameter(void function(Element parameter));

  void orderedForEachParameter(void function(Element parameter));

  bool isCompatibleWith(FunctionSignature constructorSignature);
}

abstract class FunctionElement extends Element {
  FunctionExpression get cachedNode;
  DartType get type;
  FunctionSignature get functionSignature;
  FunctionElement get redirectionTarget;
  FunctionElement get defaultImplementation;

  FunctionElement get patch;
  FunctionElement get origin;

  bool get isRedirectingFactory;

  /**
   * Compute the type of the target of a redirecting constructor or factory
   * for an instantiation site with type [:newType:].
   *
   * TODO(karlklose): get rid of this method and resolve the target type
   * during resolution when we correctly resolve chains of redirections.
   */
  InterfaceType computeTargetType(Compiler compiler,
                                  InterfaceType newType);

  // TODO(kasperl): These are bit fishy. Do we really need them?
  void set patch(FunctionElement value);
  void set origin(FunctionElement value);
  void set defaultImplementation(FunctionElement value);

  void setPatch(FunctionElement patchElement);
  FunctionSignature computeSignature(Compiler compiler);
  int requiredParameterCount(Compiler compiler);
  int optionalParameterCount(Compiler compiler);
  int parameterCount(Compiler compiler);

  FunctionExpression parseNode(DiagnosticListener listener);
}

abstract class ConstructorBodyElement extends FunctionElement {
  FunctionElement get constructor;
}

/**
 * [TypeDeclarationElement] defines the common interface for class/interface
 * declarations and typedefs.
 */
abstract class TypeDeclarationElement extends Element {
  GenericType get rawType;

  /**
   * The type variables declared on this declaration. The type variables are not
   * available until the type of the element has been computed through
   * [computeType].
   */
  Link<DartType> get typeVariables;
}

abstract class ClassElement extends TypeDeclarationElement
    implements ScopeContainerElement {
  int get id;

  InterfaceType get rawType;
  InterfaceType get thisType;

  ClassElement get superclass;

  DartType get supertype;
  Link<DartType> get allSupertypes;
  Link<DartType> get interfaces;

  bool get hasConstructor;
  Link<Element> get constructors;

  ClassElement get patch;
  ClassElement get origin;
  ClassElement get declaration;
  ClassElement get implementation;

  int get supertypeLoadState;
  int get resolutionState;
  SourceString get nativeTagInfo;

  bool get isMixinApplication;
  bool get hasBackendMembers;
  bool get hasLocalScopeMembers;

  // TODO(kasperl): These are bit fishy. Do we really need them?
  void set thisType(InterfaceType value);
  void set supertype(DartType value);
  void set allSupertypes(Link<DartType> value);
  void set interfaces(Link<DartType> value);
  void set patch(ClassElement value);
  void set origin(ClassElement value);
  void set supertypeLoadState(int value);
  void set resolutionState(int value);
  void set nativeTagInfo(SourceString value);

  bool isObject(Compiler compiler);
  bool isSubclassOf(ClassElement cls);
  bool implementsInterface(ClassElement intrface);
  bool isShadowedByField(Element fieldMember);

  ClassElement ensureResolved(Compiler compiler);

  void addMember(Element element, DiagnosticListener listener);
  void addToScope(Element element, DiagnosticListener listener);

  /**
   * Add a synthetic nullary constructor if there are no other
   * constructors.
   */
  void addDefaultConstructorIfNeeded(Compiler compiler);

  void addBackendMember(Element element);
  void reverseBackendMembers();

  Element lookupMember(SourceString memberName);
  Element lookupSelector(Selector selector, Compiler compiler);
  Element lookupSuperSelector(Selector selector, Compiler compiler);

  Element lookupLocalMember(SourceString memberName);
  Element lookupBackendMember(SourceString memberName);
  Element lookupSuperMember(SourceString memberName);

  Element lookupSuperMemberInLibrary(SourceString memberName,
                                     LibraryElement library);

  Element lookupSuperInterfaceMember(SourceString memberName,
                                     LibraryElement fromLibrary);

  Element validateConstructorLookupResults(Selector selector,
                                           Element result,
                                           Element noMatch(Element));

  Element lookupConstructor(Selector selector, [Element noMatch(Element)]);
  Element lookupFactoryConstructor(Selector selector,
                                   [Element noMatch(Element)]);

  void forEachMember(void f(ClassElement enclosingClass, Element member),
                     {includeBackendMembers: false,
                      includeSuperAndInjectedMembers: false});

  void forEachInstanceField(void f(ClassElement enclosingClass, Element field),
                            {includeSuperAndInjectedMembers: false});

  /// Similar to [forEachInstanceField] but visits static fields.
  void forEachStaticField(void f(ClassElement enclosingClass, Element field));

  void forEachBackendMember(void f(Element member));
}

abstract class MixinApplicationElement extends ClassElement {
  ClassElement get mixin;
  void set mixin(ClassElement value);
  void addConstructor(FunctionElement constructor);
}

abstract class LabelElement extends Element {
  Label get label;
  String get labelName;
  TargetElement get target;

  bool get isTarget;
  bool get isBreakTarget;
  bool get isContinueTarget;

  void setBreakTarget();
  void setContinueTarget();
}

abstract class TargetElement extends Element {
  Node get statement;
  int get nestingLevel;
  Link<LabelElement> get labels;

  bool get isTarget;
  bool get isBreakTarget;
  bool get isContinueTarget;
  bool get isSwitch;

  // TODO(kasperl): Try to get rid of these.
  void set isBreakTarget(bool value);
  void set isContinueTarget(bool value);

  LabelElement addLabel(Label label, String labelName);
}

abstract class TypeVariableElement extends Element {
  TypeVariableType get type;
  DartType get bound;

  // TODO(kasperl): Try to get rid of these.
  void set type(TypeVariableType value);
  void set bound(DartType value);
}

abstract class MetadataAnnotation implements Spannable {
  Constant get value;
  Element get annotatedElement;
  int get resolutionState;
  Token get beginToken;
  Token get endToken;

  // TODO(kasperl): Try to get rid of these.
  void set annotatedElement(Element value);
  void set resolutionState(int value);

  MetadataAnnotation ensureResolved(Compiler compiler);
}
