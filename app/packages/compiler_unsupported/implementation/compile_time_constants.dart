// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of dart2js;

/**
 * The [ConstantHandler] keeps track of compile-time constants,
 * initializations of global and static fields, and default values of
 * optional parameters.
 */
class ConstantHandler extends CompilerTask {
  final ConstantSystem constantSystem;
  final bool isMetadata;

  /**
   * Contains the initial value of fields. Must contain all static and global
   * initializations of const fields. May contain eagerly compiled values for
   * statics and instance fields.
   */
  final Map<VariableElement, Constant> initialVariableValues;

  /** Set of all registered compiled constants. */
  final Set<Constant> compiledConstants;

  /** The set of variable elements that are in the process of being computed. */
  final Set<VariableElement> pendingVariables;

  /** Caches the statics where the initial value cannot be eagerly compiled. */
  final Set<VariableElement> lazyStatics;

  /** Caches the createRuntimeType function if registered. */
  Element createRuntimeTypeFunction = null;

  /** Caches the setRuntimeTypeInfo function if registered. */
  Element setRuntimeTypeInfoFunction = null;

  ConstantHandler(Compiler compiler, this.constantSystem,
                  { bool this.isMetadata: false })
      : initialVariableValues = new Map<VariableElement, dynamic>(),
        compiledConstants = new Set<Constant>(),
        pendingVariables = new Set<VariableElement>(),
        lazyStatics = new Set<VariableElement>(),
        super(compiler);

  String get name => 'ConstantHandler';

  void registerCompileTimeConstant(Constant constant, TreeElements elements) {
    registerInstantiatedType(constant.computeType(compiler), elements);
    if (constant.isFunction()) {
      FunctionConstant function = constant;
      registerGetOfStaticFunction(function.element);
    } else if (constant.isInterceptor()) {
      // An interceptor constant references the class's prototype chain.
      InterceptorConstant interceptor = constant;
      registerInstantiatedType(interceptor.dispatchedType, elements);
    }
    compiledConstants.add(constant);
  }

  void registerInstantiatedType(DartType type, TreeElements elements) {
    if (isMetadata) {
      compiler.backend.registerMetadataInstantiatedType(type, elements);
      return;
    }
    compiler.enqueuer.codegen.registerInstantiatedType(type, elements);
    if (type is InterfaceType &&
        !type.isRaw &&
        compiler.backend.classNeedsRti(type.element)) {
      registerSetRuntimeTypeInfoFunction();
    }
  }

  void registerStaticUse(Element element) {
    if (isMetadata) {
      compiler.backend.registerMetadataStaticUse(element);
      return;
    }
    compiler.analyzeElement(element.declaration);
    compiler.enqueuer.codegen.registerStaticUse(element);
  }

  void registerGetOfStaticFunction(FunctionElement element) {
    if (isMetadata) {
      compiler.backend.registerMetadataGetOfStaticFunction(element);
      return;
    }
    compiler.analyzeElement(element.declaration);
    compiler.enqueuer.codegen.registerGetOfStaticFunction(element);
  }

  void registerStringInstance(TreeElements elements) {
    registerInstantiatedType(compiler.stringClass.rawType, elements);
  }

  void registerSetRuntimeTypeInfoFunction() {
    if (setRuntimeTypeInfoFunction != null) return;
    SourceString helperName = const SourceString('setRuntimeTypeInfo');
    setRuntimeTypeInfoFunction = compiler.findHelper(helperName);
    registerStaticUse(setRuntimeTypeInfoFunction);
  }

  void registerCreateRuntimeTypeFunction() {
    if (createRuntimeTypeFunction != null) return;
    SourceString helperName = const SourceString('createRuntimeType');
    createRuntimeTypeFunction = compiler.findHelper(helperName);
    registerStaticUse(createRuntimeTypeFunction);
  }

  /**
   * Compiles the initial value of the given field and stores it in an internal
   * map. Returns the initial value (a constant) if it can be computed
   * statically. Returns [:null:] if the variable must be initialized lazily.
   *
   * [work] must contain a [VariableElement] refering to a global or
   * static field.
   */
  Constant compileWorkItem(CodegenWorkItem work) {
    return measure(() {
      assert(work.element.kind == ElementKind.FIELD
             || work.element.kind == ElementKind.PARAMETER
             || work.element.kind == ElementKind.FIELD_PARAMETER);
      VariableElement element = work.element;
      // Shortcut if it has already been compiled.
      Constant result = initialVariableValues[element];
      if (result != null) return result;
      if (lazyStatics.contains(element)) return null;
      result = compileVariableWithDefinitions(element, work.resolutionTree);
      assert(pendingVariables.isEmpty);
      return result;
    });
  }

  /**
   * Returns a compile-time constant, or reports an error if the element is not
   * a compile-time constant.
   */
  Constant compileConstant(VariableElement element) {
    return compileVariable(element, isConst: true);
  }

  /**
   * Returns the a compile-time constant if the variable could be compiled
   * eagerly. Otherwise returns `null`.
   */
  Constant compileVariable(VariableElement element, {bool isConst: false}) {
    return measure(() {
      if (initialVariableValues.containsKey(element)) {
        Constant result = initialVariableValues[element];
        return result;
      }
      return compiler.withCurrentElement(element, () {
        TreeElements definitions = compiler.analyzeElement(element.declaration);
        Constant constant = compileVariableWithDefinitions(
            element, definitions, isConst: isConst);
        return constant;
      });
    });
  }

  /**
   * Returns the a compile-time constant if the variable could be compiled
   * eagerly. If the variable needs to be initialized lazily returns `null`.
   * If the variable is `const` but cannot be compiled eagerly reports an
   * error.
   */
  Constant compileVariableWithDefinitions(VariableElement element,
                                          TreeElements definitions,
                                          {bool isConst: false}) {
    return measure(() {
      // Initializers for parameters must be const.
      isConst = isConst || element.modifiers.isConst()
          || !Elements.isStaticOrTopLevel(element);
      if (!isConst && lazyStatics.contains(element)) return null;

      Node node = element.parseNode(compiler);
      if (pendingVariables.contains(element)) {
        if (isConst) {
          MessageKind kind = MessageKind.CYCLIC_COMPILE_TIME_CONSTANTS;
          compiler.reportError(node,
                               new CompileTimeConstantError(kind));
        } else {
          lazyStatics.add(element);
          return null;
        }
      }
      pendingVariables.add(element);

      SendSet assignment = node.asSendSet();
      Constant value;
      if (assignment == null) {
        // No initial value.
        value = new NullConstant();
      } else {
        Node right = assignment.arguments.head;
        value =
            compileNodeWithDefinitions(right, definitions, isConst: isConst);
        if (compiler.enableTypeAssertions
            && value != null
            && element.isField()) {
          DartType elementType = element.computeType(compiler);
          DartType constantType = value.computeType(compiler);
          if (elementType.isMalformed || constantType.isMalformed ||
              !constantSystem.isSubtype(compiler, constantType, elementType)) {
            if (isConst) {
              compiler.reportError(node, new CompileTimeConstantError(
                  MessageKind.NOT_ASSIGNABLE,
                  {'fromType': constantType, 'toType': elementType}));
            } else {
              // If the field can be lazily initialized, we will throw
              // the exception at runtime.
              value = null;
            }
          }
        }
      }
      if (value != null) {
        initialVariableValues[element] = value;
      } else {
        assert(!isConst);
        lazyStatics.add(element);
      }
      pendingVariables.remove(element);
      return value;
    });
  }

  Constant compileNodeWithDefinitions(Node node,
                                      TreeElements definitions,
                                      {bool isConst: false}) {
    return measure(() {
      assert(node != null);
      CompileTimeConstantEvaluator evaluator = new CompileTimeConstantEvaluator(
          this, definitions, compiler, isConst: isConst);
      return evaluator.evaluate(node);
    });
  }

  /** Attempts to compile a constant expression. Returns null if not possible */
  Constant tryCompileNodeWithDefinitions(Node node, TreeElements definitions) {
    return measure(() {
      assert(node != null);
      try {
        TryCompileTimeConstantEvaluator evaluator =
            new TryCompileTimeConstantEvaluator(this, definitions, compiler);
        return evaluator.evaluate(node);
      } on CompileTimeConstantError catch (exn) {
        return null;
      }
    });
  }

  /**
   * Returns an [Iterable] of static non final fields that need to be
   * initialized. The fields list must be evaluated in order since they might
   * depend on each other.
   */
  Iterable<VariableElement> getStaticNonFinalFieldsForEmission() {
    return initialVariableValues.keys.where((element) {
      return element.kind == ElementKind.FIELD
          && !element.isInstanceMember()
          && !element.modifiers.isFinal()
          // The const fields are all either emitted elsewhere or inlined.
          && !element.modifiers.isConst();
    });
  }

  /**
   * Returns an [Iterable] of static const fields that need to be initialized.
   * The fields must be evaluated in order since they might depend on each
   * other.
   */
  Iterable<VariableElement> getStaticFinalFieldsForEmission() {
    return initialVariableValues.keys.where((element) {
      return element.kind == ElementKind.FIELD
          && !element.isInstanceMember()
          && element.modifiers.isFinal();
    });
  }

  List<VariableElement> getLazilyInitializedFieldsForEmission() {
    return new List<VariableElement>.from(lazyStatics);
  }

  /**
   * Returns a list of constants topologically sorted so that dependencies
   * appear before the dependent constant.  [preSortCompare] is a comparator
   * function that gives the constants a consistent order prior to the
   * topological sort which gives the constants an ordering that is less
   * sensitive to perturbations in the source code.
   */
  List<Constant> getConstantsForEmission([preSortCompare]) {
    // We must emit dependencies before their uses.
    Set<Constant> seenConstants = new Set<Constant>();
    List<Constant> result = new List<Constant>();

    void addConstant(Constant constant) {
      if (!seenConstants.contains(constant)) {
        constant.getDependencies().forEach(addConstant);
        assert(!seenConstants.contains(constant));
        result.add(constant);
        seenConstants.add(constant);
      }
    }

    List<Constant> sorted = compiledConstants.toList();
    if (preSortCompare != null) {
      sorted.sort(preSortCompare);
    }
    sorted.forEach(addConstant);
    return result;
  }

  Constant getInitialValueFor(VariableElement element) {
    Constant initialValue = initialVariableValues[element];
    if (initialValue == null) {
      compiler.internalError("No initial value for given element",
                             element: element);
    }
    return initialValue;
  }
}

class CompileTimeConstantEvaluator extends Visitor {
  bool isEvaluatingConstant;
  final ConstantHandler handler;
  final TreeElements elements;
  final Compiler compiler;

  CompileTimeConstantEvaluator(this.handler,
                               this.elements,
                               this.compiler,
                               {bool isConst: false})
      : this.isEvaluatingConstant = isConst;

  ConstantSystem get constantSystem => handler.constantSystem;

  Constant evaluate(Node node) {
    return node.accept(this);
  }

  Constant evaluateConstant(Node node) {
    bool oldIsEvaluatingConstant = isEvaluatingConstant;
    isEvaluatingConstant = true;
    Constant result = node.accept(this);
    isEvaluatingConstant = oldIsEvaluatingConstant;
    assert(result != null);
    return result;
  }

  Constant visitNode(Node node) {
    return signalNotCompileTimeConstant(node);
  }

  Constant visitLiteralBool(LiteralBool node) {
    handler.registerInstantiatedType(compiler.boolClass.rawType, elements);
    return constantSystem.createBool(node.value);
  }

  Constant visitLiteralDouble(LiteralDouble node) {
    handler.registerInstantiatedType(compiler.doubleClass.rawType, elements);
    return constantSystem.createDouble(node.value);
  }

  Constant visitLiteralInt(LiteralInt node) {
    handler.registerInstantiatedType(compiler.intClass.rawType, elements);
    return constantSystem.createInt(node.value);
  }

  Constant visitLiteralList(LiteralList node) {
    if (!node.isConst())  {
      return signalNotCompileTimeConstant(node);
    }
    List<Constant> arguments = <Constant>[];
    for (Link<Node> link = node.elements.nodes;
         !link.isEmpty;
         link = link.tail) {
      arguments.add(evaluateConstant(link.head));
    }
    DartType type = elements.getType(node);
    handler.registerInstantiatedType(type, elements);
    Constant constant = new ListConstant(type, arguments);
    handler.registerCompileTimeConstant(constant, elements);
    return constant;
  }

  Constant visitLiteralMap(LiteralMap node) {
    if (!node.isConst()) {
      return signalNotCompileTimeConstant(node);
    }
    List<StringConstant> keys = <StringConstant>[];
    Map<StringConstant, Constant> map = new Map<StringConstant, Constant>();
    for (Link<Node> link = node.entries.nodes;
         !link.isEmpty;
         link = link.tail) {
      LiteralMapEntry entry = link.head;
      Constant key = evaluateConstant(entry.key);
      if (!key.isString() || entry.key.asStringNode() == null) {
        MessageKind kind = MessageKind.KEY_NOT_A_STRING_LITERAL;
        compiler.reportError(entry.key, new ResolutionError(kind));
      }
      StringConstant keyConstant = key;
      if (!map.containsKey(key)) keys.add(key);
      map[key] = evaluateConstant(entry.value);
    }
    List<Constant> values = <Constant>[];
    Constant protoValue = null;
    for (StringConstant key in keys) {
      if (key.value == MapConstant.PROTO_PROPERTY) {
        protoValue = map[key];
      } else {
        values.add(map[key]);
      }
    }
    bool hasProtoKey = (protoValue != null);
    InterfaceType sourceType = elements.getType(node);
    Link<DartType> arguments =
        new Link<DartType>.fromList([compiler.stringClass.rawType]);
    DartType keysType = new InterfaceType(compiler.listClass, arguments);
    ListConstant keysList = new ListConstant(keysType, keys);
    handler.registerCompileTimeConstant(keysList, elements);
    SourceString className = hasProtoKey
                             ? MapConstant.DART_PROTO_CLASS
                             : MapConstant.DART_CLASS;
    ClassElement classElement = compiler.jsHelperLibrary.find(className);
    classElement.ensureResolved(compiler);
    Link<DartType> typeArgument = sourceType.typeArguments.tail;
    InterfaceType type = new InterfaceType(classElement, typeArgument);
    handler.registerInstantiatedType(type, elements);
    Constant constant = new MapConstant(type, keysList, values, protoValue);
    handler.registerCompileTimeConstant(constant, elements);
    return constant;
  }

  Constant visitLiteralNull(LiteralNull node) {
    return constantSystem.createNull();
  }

  Constant visitLiteralString(LiteralString node) {
    handler.registerStringInstance(elements);
    return constantSystem.createString(node.dartString, node);
  }

  Constant visitStringJuxtaposition(StringJuxtaposition node) {
    StringConstant left = evaluate(node.first);
    StringConstant right = evaluate(node.second);
    if (left == null || right == null) return null;
    handler.registerStringInstance(elements);
    return constantSystem.createString(
        new DartString.concat(left.value, right.value), node);
  }

  Constant visitStringInterpolation(StringInterpolation node) {
    StringConstant initialString = evaluate(node.string);
    if (initialString == null) return null;
    DartString accumulator = initialString.value;
    for (StringInterpolationPart part in node.parts) {
      Constant expression = evaluate(part.expression);
      DartString expressionString;
      if (expression == null) {
        return signalNotCompileTimeConstant(part.expression);
      } else if (expression.isNum() || expression.isBool()) {
        PrimitiveConstant primitive = expression;
        expressionString = new DartString.literal(primitive.value.toString());
      } else if (expression.isString()) {
        PrimitiveConstant primitive = expression;
        expressionString = primitive.value;
      } else {
        return signalNotCompileTimeConstant(part.expression);
      }
      accumulator = new DartString.concat(accumulator, expressionString);
      StringConstant partString = evaluate(part.string);
      if (partString == null) return null;
      accumulator = new DartString.concat(accumulator, partString.value);
    };
    handler.registerStringInstance(elements);
    return constantSystem.createString(accumulator, node);
  }

  Constant makeTypeConstant(Element element) {
    DartType elementType = element.computeType(compiler).asRaw();
    compiler.backend.registerTypeLiteral(element, elements);
    DartType constantType =
        compiler.backend.typeImplementation.computeType(compiler);
    Constant constant = new TypeConstant(elementType, constantType);
    // If we use a type literal in a constant, the compile time
    // constant emitter will generate a call to the createRuntimeType
    // helper so we register a use of that.
    handler.registerCreateRuntimeTypeFunction();
    handler.registerCompileTimeConstant(constant, elements);
    return constant;
  }

  // TODO(floitsch): provide better error-messages.
  Constant visitSend(Send send) {
    Element element = elements[send];
    if (send.isPropertyAccess) {
      if (Elements.isStaticOrTopLevelFunction(element)) {
        Constant constant = new FunctionConstant(element);
        handler.registerCompileTimeConstant(constant, elements);
        return constant;
      } else if (Elements.isStaticOrTopLevelField(element)) {
        Constant result;
        if (element.modifiers.isConst()) {
          result = handler.compileConstant(element);
        } else if (element.modifiers.isFinal() && !isEvaluatingConstant) {
          result = handler.compileVariable(element);
        }
        if (result != null) return result;
      } else if (Elements.isClass(element) || Elements.isTypedef(element)) {
        return makeTypeConstant(element);
      } else if (send.receiver != null) {
        // Fall through to error handling.
      } else if (!Elements.isUnresolved(element)
                 && element.isVariable()
                 && element.modifiers.isConst()) {
        Constant result = handler.compileConstant(element);
        if (result != null) return result;
      }
      return signalNotCompileTimeConstant(send);
    } else if (send.isCall) {
      if (identical(element, compiler.identicalFunction)
          && send.argumentCount() == 2) {
        Constant left = evaluate(send.argumentsNode.nodes.head);
        Constant right = evaluate(send.argumentsNode.nodes.tail.head);
        Constant result = constantSystem.identity.fold(left, right);
        if (result != null) return result;
      } else if (Elements.isClass(element) || Elements.isTypedef(element)) {
        return makeTypeConstant(element);
      }
      return signalNotCompileTimeConstant(send);
    } else if (send.isPrefix) {
      assert(send.isOperator);
      Constant receiverConstant = evaluate(send.receiver);
      if (receiverConstant == null) return null;
      Operator op = send.selector;
      Constant folded;
      switch (op.source.stringValue) {
        case "!":
          folded = constantSystem.not.fold(receiverConstant);
          break;
        case "-":
          folded = constantSystem.negate.fold(receiverConstant);
          break;
        case "~":
          folded = constantSystem.bitNot.fold(receiverConstant);
          break;
        default:
          compiler.internalError("Unexpected operator.", node: op);
          break;
      }
      if (folded == null) return signalNotCompileTimeConstant(send);
      return folded;
    } else if (send.isOperator && !send.isPostfix) {
      assert(send.argumentCount() == 1);
      Constant left = evaluate(send.receiver);
      Constant right = evaluate(send.argumentsNode.nodes.head);
      if (left == null || right == null) return null;
      Operator op = send.selector.asOperator();
      Constant folded = null;
      switch (op.source.stringValue) {
        case "+":
          folded = constantSystem.add.fold(left, right);
          break;
        case "-":
          folded = constantSystem.subtract.fold(left, right);
          break;
        case "*":
          folded = constantSystem.multiply.fold(left, right);
          break;
        case "/":
          folded = constantSystem.divide.fold(left, right);
          break;
        case "%":
          folded = constantSystem.modulo.fold(left, right);
          break;
        case "~/":
          folded = constantSystem.truncatingDivide.fold(left, right);
          break;
        case "|":
          folded = constantSystem.bitOr.fold(left, right);
          break;
        case "&":
          folded = constantSystem.bitAnd.fold(left, right);
          break;
        case "^":
          folded = constantSystem.bitXor.fold(left, right);
          break;
        case "||":
          folded = constantSystem.booleanOr.fold(left, right);
          break;
        case "&&":
          folded = constantSystem.booleanAnd.fold(left, right);
          break;
        case "<<":
          folded = constantSystem.shiftLeft.fold(left, right);
          break;
        case ">>":
          folded = constantSystem.shiftRight.fold(left, right);
          break;
        case "<":
          folded = constantSystem.less.fold(left, right);
          break;
        case "<=":
          folded = constantSystem.lessEqual.fold(left, right);
          break;
        case ">":
          folded = constantSystem.greater.fold(left, right);
          break;
        case ">=":
          folded = constantSystem.greaterEqual.fold(left, right);
          break;
        case "==":
          if (left.isPrimitive() && right.isPrimitive()) {
            folded = constantSystem.equal.fold(left, right);
          }
          break;
        case "===":
          folded = constantSystem.identity.fold(left, right);
          break;
        case "!=":
          if (left.isPrimitive() && right.isPrimitive()) {
            BoolConstant areEquals = constantSystem.equal.fold(left, right);
            if (areEquals == null) {
              folded = null;
            } else {
              folded = areEquals.negate();
            }
          }
          break;
        case "!==":
          BoolConstant areIdentical =
              constantSystem.identity.fold(left, right);
          if (areIdentical == null) {
            folded = null;
          } else {
            folded = areIdentical.negate();
          }
          break;
      }
      if (folded == null) return signalNotCompileTimeConstant(send);
      return folded;
    }
    return signalNotCompileTimeConstant(send);
  }

  Constant visitSendSet(SendSet node) {
    return signalNotCompileTimeConstant(node);
  }

  /**
   * Returns the list of constants that are passed to the static function.
   *
   * Invariant: [target] must be an implementation element.
   */
  List<Constant> evaluateArgumentsToConstructor(Node node,
                                                Selector selector,
                                                Link<Node> arguments,
                                                FunctionElement target) {
    assert(invariant(node, target.isImplementation));
    List<Constant> compiledArguments = <Constant>[];

    Function compileArgument = evaluateConstant;
    Function compileConstant = handler.compileConstant;
    bool succeeded = selector.addArgumentsToList(arguments,
                                                 compiledArguments,
                                                 target,
                                                 compileArgument,
                                                 compileConstant,
                                                 compiler);
    if (!succeeded) {
      MessageKind kind = MessageKind.INVALID_ARGUMENTS;
      compiler.reportError(node,
          new CompileTimeConstantError(kind, {'methodName': target.name}));
    }
    return compiledArguments;
  }

  Constant visitNewExpression(NewExpression node) {
    if (!node.isConst()) {
      return signalNotCompileTimeConstant(node);
    }

    Send send = node.send;
    FunctionElement constructor = elements[send];
    // TODO(ahe): This is nasty: we must eagerly analyze the
    // constructor to ensure the redirectionTarget has been computed
    // correctly.  Find a way to avoid this.
    compiler.analyzeElement(constructor.declaration);

    InterfaceType type = elements.getType(node);
    if ( constructor.isRedirectingFactory) {
      type = constructor.computeTargetType(compiler, type);
    }

    constructor = constructor.redirectionTarget;
    ClassElement classElement = constructor.getEnclosingClass();
    // The constructor must be an implementation to ensure that field
    // initializers are handled correctly.
    constructor = constructor.implementation;
    assert(invariant(node, constructor.isImplementation));

    Selector selector = elements.getSelector(send);
    List<Constant> arguments = evaluateArgumentsToConstructor(
        node, selector, send.arguments, constructor);
    ConstructorEvaluator evaluator =
        new ConstructorEvaluator(node, constructor, handler, compiler);
    evaluator.evaluateConstructorFieldValues(arguments);
    List<Constant> jsNewArguments = evaluator.buildJsNewArguments(classElement);

    handler.registerInstantiatedType(type, elements);
    Constant constant = new ConstructedConstant(type, jsNewArguments);
    handler.registerCompileTimeConstant(constant, elements);
    return constant;
  }

  Constant visitParenthesizedExpression(ParenthesizedExpression node) {
    return node.expression.accept(this);
  }

  error(Node node) {
    // TODO(floitsch): get the list of constants that are currently compiled
    // and present some kind of stack-trace.
    MessageKind kind = MessageKind.NOT_A_COMPILE_TIME_CONSTANT;
    compiler.reportError(node, new CompileTimeConstantError(kind));
  }

  Constant signalNotCompileTimeConstant(Node node) {
    if (isEvaluatingConstant) {
      error(node);
    }
    // Else we don't need to do anything. The final handler is only
    // optimistically trying to compile constants. So it is normal that we
    // sometimes see non-compile time constants.
    // Simply return [:null:] which is used to propagate a failing
    // compile-time compilation.
    return null;
  }
}

class TryCompileTimeConstantEvaluator extends CompileTimeConstantEvaluator {
  TryCompileTimeConstantEvaluator(ConstantHandler handler,
                                  TreeElements elements,
                                  Compiler compiler)
      : super(handler, elements, compiler, isConst: true);

  error(Node node) {
    // Just fail without reporting it anywhere.
    throw new CompileTimeConstantError(
        MessageKind.NOT_A_COMPILE_TIME_CONSTANT);
  }
}

class ConstructorEvaluator extends CompileTimeConstantEvaluator {
  final FunctionElement constructor;
  final Map<Element, Constant> definitions;
  final Map<Element, Constant> fieldValues;

  /**
   * Documentation wanted -- johnniwinther
   *
   * Invariant: [constructor] must be an implementation element.
   */
  ConstructorEvaluator(Node node,
                       FunctionElement constructor,
                       ConstantHandler handler,
                       Compiler compiler)
      : this.constructor = constructor,
        this.definitions = new Map<Element, Constant>(),
        this.fieldValues = new Map<Element, Constant>(),
        super(handler,
              compiler.resolver.resolveMethodElement(constructor.declaration),
              compiler,
              isConst: true) {
    assert(invariant(node, constructor.isImplementation));
  }

  Constant visitSend(Send send) {
    Element element = elements[send];
    if (Elements.isLocal(element)) {
      Constant constant = definitions[element];
      if (constant == null) {
        compiler.internalError("Local variable without value", node: send);
      }
      return constant;
    }
    return super.visitSend(send);
  }

  void potentiallyCheckType(Node node, Element element, Constant constant) {
    if (compiler.enableTypeAssertions) {
      DartType elementType = element.computeType(compiler);
      DartType constantType = constant.computeType(compiler);
      // TODO(ngeoffray): Handle type parameters.
      if (elementType.element.isTypeVariable()) return;
      if (elementType.isMalformed || constantType.isMalformed ||
          !constantSystem.isSubtype(compiler, constantType, elementType)) {
        compiler.reportError(node, new CompileTimeConstantError(
            MessageKind.NOT_ASSIGNABLE,
            {'fromType': elementType, 'toType': constantType}));
      }
    }
  }

  void updateFieldValue(Node node, Element element, Constant constant) {
    potentiallyCheckType(node, element, constant);
    fieldValues[element] = constant;
  }

  /**
   * Given the arguments (a list of constants) assigns them to the parameters,
   * updating the definitions map. If the constructor has field-initializer
   * parameters (like [:this.x:]), also updates the [fieldValues] map.
   */
  void assignArgumentsToParameters(List<Constant> arguments) {
    // Assign arguments to parameters.
    FunctionSignature parameters = constructor.computeSignature(compiler);
    int index = 0;
    parameters.orderedForEachParameter((Element parameter) {
      Constant argument = arguments[index++];
      Node node = parameter.parseNode(compiler);
      potentiallyCheckType(node, parameter, argument);
      definitions[parameter] = argument;
      if (parameter.kind == ElementKind.FIELD_PARAMETER) {
        FieldParameterElement fieldParameterElement = parameter;
        updateFieldValue(node, fieldParameterElement.fieldElement, argument);
      }
    });
  }

  void evaluateSuperOrRedirectSend(Node currentNode,
                                   Selector selector,
                                   Link<Node> arguments,
                                   FunctionElement targetConstructor) {
    List<Constant> compiledArguments = evaluateArgumentsToConstructor(
        currentNode, selector, arguments, targetConstructor);

    ConstructorEvaluator evaluator = new ConstructorEvaluator(
        currentNode, targetConstructor, handler, compiler);
    evaluator.evaluateConstructorFieldValues(compiledArguments);
    // Copy over the fieldValues from the super/redirect-constructor.
    // No need to go through [updateFieldValue] because the
    // assignments have already been checked in checked mode.
    evaluator.fieldValues.forEach((key, value) => fieldValues[key] = value);
  }

  /**
   * Runs through the initializers of the given [constructor] and updates
   * the [fieldValues] map.
   */
  void evaluateConstructorInitializers() {
    FunctionExpression functionNode = constructor.parseNode(compiler);
    NodeList initializerList = functionNode.initializers;

    bool foundSuperOrRedirect = false;

    if (initializerList != null) {
      for (Link<Node> link = initializerList.nodes;
           !link.isEmpty;
           link = link.tail) {
        assert(link.head is Send);
        if (link.head is !SendSet) {
          // A super initializer or constructor redirection.
          Send call = link.head;
          FunctionElement targetConstructor = elements[call];
          Selector selector = elements.getSelector(call);
          Link<Node> arguments = call.arguments;
          evaluateSuperOrRedirectSend(
              call, selector, arguments, targetConstructor);
          foundSuperOrRedirect = true;
        } else {
          // A field initializer.
          SendSet init = link.head;
          Link<Node> initArguments = init.arguments;
          assert(!initArguments.isEmpty && initArguments.tail.isEmpty);
          Constant fieldValue = evaluate(initArguments.head);
          updateFieldValue(init, elements[init], fieldValue);
        }
      }
    }

    if (!foundSuperOrRedirect) {
      // No super initializer found. Try to find the default constructor if
      // the class is not Object.
      ClassElement enclosingClass = constructor.getEnclosingClass();
      ClassElement superClass = enclosingClass.superclass;
      if (enclosingClass != compiler.objectClass) {
        assert(superClass != null);
        assert(superClass.resolutionState == STATE_DONE);

        Selector selector =
            new Selector.callDefaultConstructor(enclosingClass.getLibrary());

        FunctionElement targetConstructor =
            superClass.lookupConstructor(selector);
        if (targetConstructor == null) {
          compiler.internalError("no default constructor available",
                                 node: functionNode);
        }

        evaluateSuperOrRedirectSend(functionNode,
                                    selector,
                                    const Link<Node>(),
                                    targetConstructor);
      }
    }
  }

  /**
   * Simulates the execution of the [constructor] with the given
   * [arguments] to obtain the field values that need to be passed to the
   * native JavaScript constructor.
   */
  void evaluateConstructorFieldValues(List<Constant> arguments) {
    compiler.withCurrentElement(constructor, () {
      assignArgumentsToParameters(arguments);
      evaluateConstructorInitializers();
    });
  }

  List<Constant> buildJsNewArguments(ClassElement classElement) {
    List<Constant> jsNewArguments = <Constant>[];
    classElement.implementation.forEachInstanceField(
        (ClassElement enclosing, Element field) {
          Constant fieldValue = fieldValues[field];
          if (fieldValue == null) {
            // Use the default value.
            fieldValue = handler.compileConstant(field);
          }
          jsNewArguments.add(fieldValue);
        },
        includeSuperAndInjectedMembers: true);
    return jsNewArguments;
  }
}
