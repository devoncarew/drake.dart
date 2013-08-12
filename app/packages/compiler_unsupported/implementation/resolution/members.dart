// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of resolution;

abstract class TreeElements {
  Element get currentElement;
  Set<Node> get superUses;

  /// A set of additional dependencies.  See [registerDependency] below.
  Set<Element> get otherDependencies;

  Element operator[](Node node);
  Selector getSelector(Send send);
  Selector getGetterSelectorInComplexSendSet(SendSet node);
  Selector getOperatorSelectorInComplexSendSet(SendSet node);
  DartType getType(Node node);
  void setSelector(Node node, Selector selector);
  void setGetterSelectorInComplexSendSet(SendSet node, Selector selector);
  void setOperatorSelectorInComplexSendSet(SendSet node, Selector selector);
  Selector getIteratorSelector(ForIn node);
  Selector getMoveNextSelector(ForIn node);
  Selector getCurrentSelector(ForIn node);
  Selector setIteratorSelector(ForIn node, Selector selector);
  Selector setMoveNextSelector(ForIn node, Selector selector);
  Selector setCurrentSelector(ForIn node, Selector selector);

  /// Register additional dependencies required by [currentElement].
  /// For example, elements that are used by a backend.
  void registerDependency(Element element);
}

class TreeElementMapping implements TreeElements {
  final Element currentElement;
  final Map<Spannable, Selector> selectors =
      new LinkedHashMap<Spannable, Selector>();
  final Map<Node, DartType> types = new LinkedHashMap<Node, DartType>();
  final Set<Node> superUses = new LinkedHashSet<Node>();
  final Set<Element> otherDependencies = new LinkedHashSet<Element>();
  final int hashCode = ++hashCodeCounter;
  static int hashCodeCounter = 0;

  TreeElementMapping(this.currentElement);

  operator []=(Node node, Element element) {
    assert(invariant(node, () {
      FunctionExpression functionExpression = node.asFunctionExpression();
      if (functionExpression != null) {
        return !functionExpression.modifiers.isExternal();
      }
      return true;
    }));
    // TODO(johnniwinther): Simplify this invariant to use only declarations in
    // [TreeElements].
    assert(invariant(node, () {
      if (!element.isErroneous() && currentElement != null && element.isPatch) {
        return currentElement.getImplementationLibrary().isPatch;
      }
      return true;
    }));
    // TODO(ahe): Investigate why the invariant below doesn't hold.
    // assert(invariant(node,
    //                  getTreeElement(node) == element ||
    //                  getTreeElement(node) == null,
    //                  message: '${getTreeElement(node)}; $element'));

    setTreeElement(node, element);
  }

  operator [](Node node) => getTreeElement(node);

  void remove(Node node) {
    setTreeElement(node, null);
  }

  void setType(Node node, DartType type) {
    types[node] = type;
  }

  DartType getType(Node node) => types[node];

  void setSelector(Node node, Selector selector) {
    selectors[node] = selector;
  }

  Selector getSelector(Node node) {
    return selectors[node];
  }

  void setGetterSelectorInComplexSendSet(SendSet node, Selector selector) {
    selectors[node.selector] = selector;
  }

  Selector getGetterSelectorInComplexSendSet(SendSet node) {
    return selectors[node.selector];
  }

  void setOperatorSelectorInComplexSendSet(SendSet node, Selector selector) {
    selectors[node.assignmentOperator] = selector;
  }

  Selector getOperatorSelectorInComplexSendSet(SendSet node) {
    return selectors[node.assignmentOperator];
  }

  // The following methods set selectors on the "for in" node. Since
  // we're using three selectors, we need to use children of the node,
  // and we arbitrarily choose which ones.

  Selector setIteratorSelector(ForIn node, Selector selector) {
    selectors[node] = selector;
  }

  Selector getIteratorSelector(ForIn node) {
    return selectors[node];
  }

  Selector setMoveNextSelector(ForIn node, Selector selector) {
    selectors[node.forToken] = selector;
  }

  Selector getMoveNextSelector(ForIn node) {
    return selectors[node.forToken];
  }

  Selector setCurrentSelector(ForIn node, Selector selector) {
    selectors[node.inToken] = selector;
  }

  Selector getCurrentSelector(ForIn node) {
    return selectors[node.inToken];
  }

  void registerDependency(Element element) {
    otherDependencies.add(element.implementation);
  }

  String toString() => 'TreeElementMapping($currentElement)';
}

class ResolverTask extends CompilerTask {
  ResolverTask(Compiler compiler) : super(compiler);

  String get name => 'Resolver';

  TreeElements resolve(Element element) {
    return measure(() {
      if (Elements.isErroneousElement(element)) return null;

      for (MetadataAnnotation metadata in element.metadata) {
        metadata.ensureResolved(compiler);
      }

      ElementKind kind = element.kind;
      if (identical(kind, ElementKind.GENERATIVE_CONSTRUCTOR) ||
          identical(kind, ElementKind.FUNCTION) ||
          identical(kind, ElementKind.GETTER) ||
          identical(kind, ElementKind.SETTER)) {
        return resolveMethodElement(element);
      }

      if (identical(kind, ElementKind.FIELD)) return resolveField(element);

      if (identical(kind, ElementKind.PARAMETER) ||
          identical(kind, ElementKind.FIELD_PARAMETER)) {
        return resolveParameter(element);
      }
      if (element.isClass()) {
        ClassElement cls = element;
        cls.ensureResolved(compiler);
        return null;
      } else if (element.isTypedef()) {
        TypedefElement typdef = element;
        return resolveTypedef(typdef);
      } else if (element.isTypeVariable()) {
        element.computeType(compiler);
        return null;
      }

      compiler.unimplemented("resolve($element)",
                             node: element.parseNode(compiler));
    });
  }

  String constructorNameForDiagnostics(SourceString className,
                                       SourceString constructorName) {
    String classNameString = className.slowToString();
    String constructorNameString = constructorName.slowToString();
    return (constructorName == const SourceString(''))
        ? classNameString
        : "$classNameString.$constructorNameString";
   }

  void resolveRedirectingConstructor(InitializerResolver resolver,
                                     Node node,
                                     FunctionElement constructor,
                                     FunctionElement redirection) {
    Set<FunctionElement> seen = new Set<FunctionElement>();
    seen.add(constructor);
    while (redirection != null) {
      if (seen.contains(redirection)) {
        resolver.visitor.error(node, MessageKind.REDIRECTING_CONSTRUCTOR_CYCLE);
        return;
      }
      seen.add(redirection);

      if (redirection.isPatched) {
        checkMatchingPatchSignatures(constructor, redirection.patch);
        redirection = redirection.patch;
      }
      redirection = resolver.visitor.resolveConstructorRedirection(redirection);
    }
  }

  void checkMatchingPatchParameters(FunctionElement origin,
                                    Link<Element> originParameters,
                                    Link<Element> patchParameters) {
    while (!originParameters.isEmpty) {
      Element originParameter = originParameters.head;
      Element patchParameter = patchParameters.head;
      // Hack: Use unparser to test parameter equality. This only works because
      // we are restricting patch uses and the approach cannot be used
      // elsewhere.
      String originParameterText =
          originParameter.parseNode(compiler).toString();
      String patchParameterText =
          patchParameter.parseNode(compiler).toString();
      if (originParameterText != patchParameterText) {
        compiler.reportErrorCode(
            originParameter.parseNode(compiler),
            MessageKind.PATCH_PARAMETER_MISMATCH,
            {'methodName': origin.name,
             'originParameter': originParameterText,
             'patchParameter': patchParameterText});
        compiler.reportMessage(
            compiler.spanFromSpannable(patchParameter),
            MessageKind.PATCH_POINT_TO_PARAMETER.error(
                {'parameterName': patchParameter.name}),
            Diagnostic.INFO);
      }
      DartType originParameterType = originParameter.computeType(compiler);
      DartType patchParameterType = patchParameter.computeType(compiler);
      if (originParameterType != patchParameterType) {
        compiler.reportErrorCode(
            originParameter.parseNode(compiler),
            MessageKind.PATCH_PARAMETER_TYPE_MISMATCH,
            {'methodName': origin.name,
             'parameterName': originParameter.name,
             'originParameterType': originParameterType,
             'patchParameterType': patchParameterType});
        compiler.reportMessage(
            compiler.spanFromSpannable(patchParameter),
            MessageKind.PATCH_POINT_TO_PARAMETER.error(
                {'parameterName': patchParameter.name}),
            Diagnostic.INFO);
      }

      originParameters = originParameters.tail;
      patchParameters = patchParameters.tail;
    }
  }

  void checkMatchingPatchSignatures(FunctionElement origin,
                                    FunctionElement patch) {
    // TODO(johnniwinther): Show both origin and patch locations on errors.
    FunctionExpression originTree = compiler.withCurrentElement(origin, () {
      return origin.parseNode(compiler);
    });
    FunctionSignature originSignature = compiler.withCurrentElement(origin, () {
      return origin.computeSignature(compiler);
    });
    FunctionExpression patchTree = compiler.withCurrentElement(patch, () {
      return patch.parseNode(compiler);
    });
    FunctionSignature patchSignature = compiler.withCurrentElement(patch, () {
      return patch.computeSignature(compiler);
    });

    if (originSignature.returnType != patchSignature.returnType) {
      compiler.withCurrentElement(patch, () {
        Node errorNode =
            patchTree.returnType != null ? patchTree.returnType : patchTree;
        error(errorNode, MessageKind.PATCH_RETURN_TYPE_MISMATCH,
              {'methodName': origin.name,
               'originReturnType': originSignature.returnType,
               'patchReturnType': patchSignature.returnType});
      });
    }
    if (originSignature.requiredParameterCount !=
        patchSignature.requiredParameterCount) {
      compiler.withCurrentElement(patch, () {
        error(patchTree,
              MessageKind.PATCH_REQUIRED_PARAMETER_COUNT_MISMATCH,
              {'methodName': origin.name,
               'originParameterCount': originSignature.requiredParameterCount,
               'patchParameterCount': patchSignature.requiredParameterCount});
      });
    } else {
      checkMatchingPatchParameters(origin,
                                   originSignature.requiredParameters,
                                   patchSignature.requiredParameters);
    }
    if (originSignature.optionalParameterCount != 0 &&
        patchSignature.optionalParameterCount != 0) {
      if (originSignature.optionalParametersAreNamed !=
          patchSignature.optionalParametersAreNamed) {
        compiler.withCurrentElement(patch, () {
          error(patchTree,
                MessageKind.PATCH_OPTIONAL_PARAMETER_NAMED_MISMATCH,
                {'methodName': origin.name});
        });
      }
    }
    if (originSignature.optionalParameterCount !=
        patchSignature.optionalParameterCount) {
      compiler.withCurrentElement(patch, () {
        error(patchTree,
              MessageKind.PATCH_OPTIONAL_PARAMETER_COUNT_MISMATCH,
              {'methodName': origin.name,
               'originParameterCount': originSignature.optionalParameterCount,
               'patchParameterCount': patchSignature.optionalParameterCount});
      });
    } else {
      checkMatchingPatchParameters(origin,
                                   originSignature.optionalParameters,
                                   patchSignature.optionalParameters);
    }
  }

  TreeElements resolveMethodElement(FunctionElement element) {
    assert(invariant(element, element.isDeclaration));
    return compiler.withCurrentElement(element, () {
      bool isConstructor =
          identical(element.kind, ElementKind.GENERATIVE_CONSTRUCTOR);
      TreeElements elements =
          compiler.enqueuer.resolution.getCachedElements(element);
      if (elements != null) {
        assert(isConstructor);
        return elements;
      }
      if (element.isPatched) {
        checkMatchingPatchSignatures(element, element.patch);
        element = element.patch;
      }
      return compiler.withCurrentElement(element, () {
        FunctionExpression tree = element.parseNode(compiler);
        if (tree.modifiers.isExternal()) {
          error(tree, MessageKind.PATCH_EXTERNAL_WITHOUT_IMPLEMENTATION);
          return;
        }
        if (isConstructor) {
          if (tree.returnType != null) {
            error(tree, MessageKind.CONSTRUCTOR_WITH_RETURN_TYPE);
          }
        }
        ResolverVisitor visitor = visitorFor(element);
        visitor.useElement(tree, element);
        visitor.setupFunction(tree, element);

        if (isConstructor && !element.isForwardingConstructor) {
          // Even if there is no initializer list we still have to do the
          // resolution in case there is an implicit super constructor call.
          InitializerResolver resolver = new InitializerResolver(visitor);
          FunctionElement redirection =
              resolver.resolveInitializers(element, tree);
          if (redirection != null) {
            resolveRedirectingConstructor(resolver, tree, element, redirection);
          }
        } else if (element.isForwardingConstructor) {
          // Initializers will be checked on the original constructor.
        } else if (tree.initializers != null) {
          error(tree, MessageKind.FUNCTION_WITH_INITIALIZER);
        }
        visitBody(visitor, tree.body);

        // Get the resolution tree and check that the resolved
        // function doesn't use 'super' if it is mixed into another
        // class. This is the part of the 'super' mixin check that
        // happens when a function is resolved after the mixin
        // application has been performed.
        TreeElements resolutionTree = visitor.mapping;
        ClassElement enclosingClass = element.getEnclosingClass();
        if (enclosingClass != null) {
          Set<MixinApplicationElement> mixinUses =
              compiler.world.mixinUses[enclosingClass];
          if (mixinUses != null) {
            ClassElement mixin = enclosingClass;
            for (MixinApplicationElement mixinApplication in mixinUses) {
              checkMixinSuperUses(resolutionTree, mixinApplication, mixin);
            }
          }
        }
        return resolutionTree;
      });
    });
  }

  /// This method should only be used by this library (or tests of
  /// this library).
  ResolverVisitor visitorFor(Element element) {
    var mapping = new TreeElementMapping(element);
    return new ResolverVisitor(compiler, element, mapping);
  }

  void visitBody(ResolverVisitor visitor, Statement body) {
    if (!compiler.analyzeSignaturesOnly) {
      visitor.visit(body);
    }
  }

  TreeElements resolveField(VariableElement element) {
    Node tree = element.parseNode(compiler);
    if(element.modifiers.isStatic() && element.variables.isTopLevel()) {
      error(element.modifiers.getStatic(),
            MessageKind.TOP_LEVEL_VARIABLE_DECLARED_STATIC);
    }
    ResolverVisitor visitor = visitorFor(element);
    visitor.useElement(tree, element);

    // TODO(johnniwinther): Avoid analyzing initializers if
    // [Compiler.analyzeSignaturesOnly] is set.
    initializerDo(tree, visitor.visit);

    if (Elements.isStaticOrTopLevelField(element)) {
      if (tree.asSendSet() != null) {
        // TODO(ngeoffray): We could do better here by using the
        // constant handler to figure out if it's a lazy field or not.
        compiler.backend.registerLazyField(visitor.mapping);
      } else {
        compiler.enqueuer.resolution.registerInstantiatedClass(
            compiler.nullClass, visitor.mapping);
      }
    }

    // Perform various checks as side effect of "computing" the type.
    element.computeType(compiler);

    return visitor.mapping;
  }

  TreeElements resolveParameter(Element element) {
    Node tree = element.parseNode(compiler);
    ResolverVisitor visitor = visitorFor(element.enclosingElement);
    initializerDo(tree, visitor.visit);
    return visitor.mapping;
  }

  DartType resolveTypeAnnotation(Element element, TypeAnnotation annotation) {
    DartType type = resolveReturnType(element, annotation);
    if (type == compiler.types.voidType) {
      error(annotation, MessageKind.VOID_NOT_ALLOWED);
    }
    return type;
  }

  DartType resolveReturnType(Element element, TypeAnnotation annotation) {
    if (annotation == null) return compiler.types.dynamicType;
    DartType result = visitorFor(element).resolveTypeAnnotation(annotation);
    if (result == null) {
      // TODO(karklose): warning.
      return compiler.types.dynamicType;
    }
    return result;
  }

  /**
   * Load and resolve the supertypes of [cls].
   *
   * Warning: do not call this method directly. It should only be
   * called by [resolveClass] and [ClassSupertypeResolver].
   */
  void loadSupertypes(ClassElement cls, Spannable from) {
    compiler.withCurrentElement(cls, () => measure(() {
      if (cls.supertypeLoadState == STATE_DONE) return;
      if (cls.supertypeLoadState == STATE_STARTED) {
        compiler.reportErrorCode(from, MessageKind.CYCLIC_CLASS_HIERARCHY,
                                 {'className': cls.name});
        cls.supertypeLoadState = STATE_DONE;
        cls.allSupertypes = const Link<DartType>().prepend(
            compiler.objectClass.computeType(compiler));
        cls.supertype = cls.allSupertypes.head;
        return;
      }
      cls.supertypeLoadState = STATE_STARTED;
      compiler.withCurrentElement(cls, () {
        // TODO(ahe): Cache the node in cls.
        cls.parseNode(compiler).accept(
            new ClassSupertypeResolver(compiler, cls));
        if (cls.supertypeLoadState != STATE_DONE) {
          cls.supertypeLoadState = STATE_DONE;
        }
      });
    }));
  }

  // TODO(johnniwinther): Remove this queue when resolution has been split into
  // syntax and semantic resolution.
  ClassElement currentlyResolvedClass;
  Queue<ClassElement> pendingClassesToBeResolved = new Queue<ClassElement>();

  /**
   * Resolve the class [element].
   *
   * Before calling this method, [element] was constructed by the
   * scanner and most fields are null or empty. This method fills in
   * these fields and also ensure that the supertypes of [element] are
   * resolved.
   *
   * Warning: Do not call this method directly. Instead use
   * [:element.ensureResolved(compiler):].
   */
  void resolveClass(ClassElement element) {
    ClassElement previousResolvedClass = currentlyResolvedClass;
    currentlyResolvedClass = element;
    // TODO(johnniwinther): Store the mapping in the resolution enqueuer.
    TreeElementMapping mapping = new TreeElementMapping(element);
    resolveClassInternal(element, mapping);
    if (previousResolvedClass == null) {
      while (!pendingClassesToBeResolved.isEmpty) {
        pendingClassesToBeResolved.removeFirst().ensureResolved(compiler);
      }
    }
    currentlyResolvedClass = previousResolvedClass;
  }

  void _ensureClassWillBeResolved(ClassElement element) {
    if (currentlyResolvedClass == null) {
      element.ensureResolved(compiler);
    } else {
      pendingClassesToBeResolved.add(element);
    }
  }

  void resolveClassInternal(ClassElement element, TreeElementMapping mapping) {
    if (!element.isPatch) {
      compiler.withCurrentElement(element, () => measure(() {
        assert(element.resolutionState == STATE_NOT_STARTED);
        element.resolutionState = STATE_STARTED;
        Node tree = element.parseNode(compiler);
        loadSupertypes(element, tree);

        ClassResolverVisitor visitor =
            new ClassResolverVisitor(compiler, element, mapping);
        visitor.visit(tree);
        element.resolutionState = STATE_DONE;
        compiler.onClassResolved(element);
      }));
      if (element.isPatched) {
        // Ensure handling patch after origin.
        element.patch.ensureResolved(compiler);
      }
    } else { // Handle patch classes:
      element.resolutionState = STATE_STARTED;
      // Ensure handling origin before patch.
      element.origin.ensureResolved(compiler);
      // Ensure that the type is computed.
      element.computeType(compiler);
      // Copy class hiearchy from origin.
      element.supertype = element.origin.supertype;
      element.interfaces = element.origin.interfaces;
      element.allSupertypes = element.origin.allSupertypes;
      // Stepwise assignment to ensure invariant.
      element.supertypeLoadState = STATE_STARTED;
      element.supertypeLoadState = STATE_DONE;
      element.resolutionState = STATE_DONE;
      // TODO(johnniwinther): Check matching type variables and
      // empty extends/implements clauses.
    }
    for (MetadataAnnotation metadata in element.metadata) {
      metadata.ensureResolved(compiler);
    }
  }

  void checkClass(ClassElement element) {
    if (element.isMixinApplication) {
      checkMixinApplication(element);
    } else {
      checkClassMembers(element);
    }
  }

  void checkMixinApplication(MixinApplicationElement mixinApplication) {
    Modifiers modifiers = mixinApplication.modifiers;
    int illegalFlags = modifiers.flags & ~Modifiers.FLAG_ABSTRACT;
    if (illegalFlags != 0) {
      Modifiers illegalModifiers = new Modifiers.withFlags(null, illegalFlags);
      compiler.reportErrorCode(
          modifiers,
          MessageKind.ILLEGAL_MIXIN_APPLICATION_MODIFIERS,
          {'modifiers': illegalModifiers});
    }

    // In case of cyclic mixin applications, the mixin chain will have
    // been cut. If so, we have already reported the error to the
    // user so we just return from here.
    ClassElement mixin = mixinApplication.mixin;
    if (mixin == null) return;

    // Check that we're not trying to use Object as a mixin.
    if (mixin.superclass == null) {
      compiler.reportErrorCode(mixinApplication,
                               MessageKind.ILLEGAL_MIXIN_OBJECT);
      // Avoid reporting additional errors for the Object class.
      return;
    }

    // Check that the mixed in class has Object as its superclass.
    if (!mixin.superclass.isObject(compiler)) {
      compiler.reportErrorCode(mixin, MessageKind.ILLEGAL_MIXIN_SUPERCLASS);
    }

    // Check that the mixed in class doesn't have any constructors and
    // make sure we aren't mixing in methods that use 'super'.
    mixin.forEachLocalMember((Element member) {
      if (member.isGenerativeConstructor() && !member.isSynthesized) {
        compiler.reportErrorCode(member, MessageKind.ILLEGAL_MIXIN_CONSTRUCTOR);
      } else {
        // Get the resolution tree and check that the resolved member
        // doesn't use 'super'. This is the part of the 'super' mixin
        // check that happens when a function is resolved before the
        // mixin application has been performed.
        checkMixinSuperUses(
            compiler.enqueuer.resolution.resolvedElements[member],
            mixinApplication,
            mixin);
      }
    });
  }

  void checkMixinSuperUses(TreeElements resolutionTree,
                           MixinApplicationElement mixinApplication,
                           ClassElement mixin) {
    if (resolutionTree == null) return;
    Set<Node> superUses = resolutionTree.superUses;
    if (superUses.isEmpty) return;
    compiler.reportErrorCode(mixinApplication,
                             MessageKind.ILLEGAL_MIXIN_WITH_SUPER,
                             {'className': mixin.name});
    // Show the user the problematic uses of 'super' in the mixin.
    for (Node use in superUses) {
      CompilationError error = MessageKind.ILLEGAL_MIXIN_SUPER_USE.error();
      compiler.reportMessage(compiler.spanFromNode(use),
                             error, Diagnostic.INFO);
    }
  }

  void checkClassMembers(ClassElement cls) {
    assert(invariant(cls, cls.isDeclaration));
    if (cls.isObject(compiler)) return;
    // TODO(johnniwinther): Should this be done on the implementation element as
    // well?
    cls.forEachMember((holder, member) {
      compiler.withCurrentElement(member, () {
        // Perform various checks as side effect of "computing" the type.
        member.computeType(compiler);

        // Check modifiers.
        if (member.isFunction() && member.modifiers.isFinal()) {
          compiler.reportErrorCode(
              member, MessageKind.ILLEGAL_FINAL_METHOD_MODIFIER);
        }
        if (member.isConstructor()) {
          final mismatchedFlagsBits =
              member.modifiers.flags &
              (Modifiers.FLAG_STATIC | Modifiers.FLAG_ABSTRACT);
          if (mismatchedFlagsBits != 0) {
            final mismatchedFlags =
                new Modifiers.withFlags(null, mismatchedFlagsBits);
            compiler.reportErrorCode(
                member,
                MessageKind.ILLEGAL_CONSTRUCTOR_MODIFIERS,
                {'modifiers': mismatchedFlags});
          }
        }
        checkAbstractField(member);
        checkValidOverride(member, cls.lookupSuperMember(member.name));
        checkUserDefinableOperator(member);
      });
    });
  }

  void checkAbstractField(Element member) {
    // Only check for getters. The test can only fail if there is both a setter
    // and a getter with the same name, and we only need to check each abstract
    // field once, so we just ignore setters.
    if (!member.isGetter()) return;

    // Find the associated abstract field.
    ClassElement classElement = member.getEnclosingClass();
    Element lookupElement = classElement.lookupLocalMember(member.name);
    if (lookupElement == null) {
      compiler.internalErrorOnElement(member,
                                      "No abstract field for accessor");
    } else if (!identical(lookupElement.kind, ElementKind.ABSTRACT_FIELD)) {
       compiler.internalErrorOnElement(
           member, "Inaccessible abstract field for accessor");
    }
    AbstractFieldElement field = lookupElement;

    if (field.getter == null) return;
    if (field.setter == null) return;
    int getterFlags = field.getter.modifiers.flags | Modifiers.FLAG_ABSTRACT;
    int setterFlags = field.setter.modifiers.flags | Modifiers.FLAG_ABSTRACT;
    if (!identical(getterFlags, setterFlags)) {
      final mismatchedFlags =
        new Modifiers.withFlags(null, getterFlags ^ setterFlags);
      compiler.reportErrorCode(
          field.getter,
          MessageKind.GETTER_MISMATCH,
          {'modifiers': mismatchedFlags});
      compiler.reportErrorCode(
          field.setter,
          MessageKind.SETTER_MISMATCH,
          {'modifiers': mismatchedFlags});
    }
  }

  void checkUserDefinableOperator(Element member) {
    FunctionElement function = member.asFunctionElement();
    if (function == null) return;
    String value = member.name.stringValue;
    if (value == null) return;
    if (!(isUserDefinableOperator(value) || identical(value, 'unary-'))) return;

    bool isMinus = false;
    int requiredParameterCount;
    MessageKind messageKind;
    FunctionSignature signature = function.computeSignature(compiler);
    if (identical(value, 'unary-')) {
      isMinus = true;
      messageKind = MessageKind.MINUS_OPERATOR_BAD_ARITY;
      requiredParameterCount = 0;
    } else if (isMinusOperator(value)) {
      isMinus = true;
      messageKind = MessageKind.MINUS_OPERATOR_BAD_ARITY;
      requiredParameterCount = 1;
    } else if (isUnaryOperator(value)) {
      messageKind = MessageKind.UNARY_OPERATOR_BAD_ARITY;
      requiredParameterCount = 0;
    } else if (isBinaryOperator(value)) {
      messageKind = MessageKind.BINARY_OPERATOR_BAD_ARITY;
      requiredParameterCount = 1;
      if (identical(value, '==')) checkOverrideHashCode(member);
    } else if (isTernaryOperator(value)) {
      messageKind = MessageKind.TERNARY_OPERATOR_BAD_ARITY;
      requiredParameterCount = 2;
    } else {
      compiler.internalErrorOnElement(function,
          'Unexpected user defined operator $value');
    }
    checkArity(function, requiredParameterCount, messageKind, isMinus);
  }

  void checkOverrideHashCode(FunctionElement operatorEquals) {
    if (operatorEquals.isAbstract(compiler)) return;
    ClassElement cls = operatorEquals.getEnclosingClass();
    Element hashCodeImplementation =
        cls.lookupLocalMember(const SourceString('hashCode'));
    if (hashCodeImplementation != null) return;
    compiler.reportHint(
        operatorEquals, MessageKind.OVERRIDE_EQUALS_NOT_HASH_CODE,
        {'class': cls.name.slowToString()});
  }

  void checkArity(FunctionElement function,
                  int requiredParameterCount, MessageKind messageKind,
                  bool isMinus) {
    FunctionExpression node = function.parseNode(compiler);
    FunctionSignature signature = function.computeSignature(compiler);
    if (signature.requiredParameterCount != requiredParameterCount) {
      Node errorNode = node;
      if (node.parameters != null) {
        if (isMinus ||
            signature.requiredParameterCount < requiredParameterCount) {
          // If there are too few parameters, point to the whole parameter list.
          // For instance
          //
          //     int operator +() {}
          //                   ^^
          //
          //     int operator []=(value) {}
          //                     ^^^^^^^
          //
          // For operator -, always point the whole parameter list, like
          //
          //     int operator -(a, b) {}
          //                   ^^^^^^
          //
          // instead of
          //
          //     int operator -(a, b) {}
          //                       ^
          //
          // since the correction might not be to remove 'b' but instead to
          // remove 'a, b'.
          errorNode = node.parameters;
        } else {
          errorNode = node.parameters.nodes.skip(requiredParameterCount).head;
        }
      }
      compiler.reportErrorCode(
          errorNode, messageKind, {'operatorName': function.name});
    }
    if (signature.optionalParameterCount != 0) {
      Node errorNode =
          node.parameters.nodes.skip(signature.requiredParameterCount).head;
      if (signature.optionalParametersAreNamed) {
        compiler.reportErrorCode(
            errorNode,
            MessageKind.OPERATOR_NAMED_PARAMETERS,
            {'operatorName': function.name});
      } else {
        compiler.reportErrorCode(
            errorNode,
            MessageKind.OPERATOR_OPTIONAL_PARAMETERS,
            {'operatorName': function.name});
      }
    }
  }

  reportErrorWithContext(Element errorneousElement,
                         MessageKind errorMessage,
                         Element contextElement,
                         MessageKind contextMessage) {
    compiler.reportErrorCode(
        errorneousElement,
        errorMessage,
        {'memberName': contextElement.name,
         'className': contextElement.getEnclosingClass().name});
    compiler.reportMessage(
        compiler.spanFromElement(contextElement),
        contextMessage.error(),
        Diagnostic.INFO);
  }

  void checkValidOverride(Element member, Element superMember) {
    if (superMember == null) return;
    if (member.modifiers.isStatic()) {
      reportErrorWithContext(
          member, MessageKind.NO_STATIC_OVERRIDE,
          superMember, MessageKind.NO_STATIC_OVERRIDE_CONT);
    } else {
      FunctionElement superFunction = superMember.asFunctionElement();
      FunctionElement function = member.asFunctionElement();
      if (superFunction == null || superFunction.isAccessor()) {
        // Field or accessor in super.
        if (function != null && !function.isAccessor()) {
          // But a plain method in this class.
          reportErrorWithContext(
              member, MessageKind.CANNOT_OVERRIDE_FIELD_WITH_METHOD,
              superMember, MessageKind.CANNOT_OVERRIDE_FIELD_WITH_METHOD_CONT);
        }
      } else {
        // Instance method in super.
        if (function == null || function.isAccessor()) {
          // But a field (or accessor) in this class.
          reportErrorWithContext(
              member, MessageKind.CANNOT_OVERRIDE_METHOD_WITH_FIELD,
              superMember, MessageKind.CANNOT_OVERRIDE_METHOD_WITH_FIELD_CONT);
        } else {
          // Both are plain instance methods.
          if (superFunction.requiredParameterCount(compiler) !=
              function.requiredParameterCount(compiler)) {
          reportErrorWithContext(
              member,
              MessageKind.BAD_ARITY_OVERRIDE,
              superMember,
              MessageKind.BAD_ARITY_OVERRIDE_CONT);
          }
          // TODO(ahe): Check optional parameters.
        }
      }
    }
  }

  FunctionSignature resolveSignature(FunctionElement element) {
    return compiler.withCurrentElement(element, () {
      FunctionExpression node =
          compiler.parser.measure(() => element.parseNode(compiler));
      return measure(() => SignatureResolver.analyze(
          compiler, node.parameters, node.returnType, element));
    });
  }

  FunctionSignature resolveFunctionExpression(Element element,
                                              FunctionExpression node) {
    return measure(() => SignatureResolver.analyze(
      compiler, node.parameters, node.returnType, element));
  }

  TreeElements resolveTypedef(TypedefElementX element) {
    if (element.isResolved) return element.mapping;
    TreeElementMapping mapping = new TreeElementMapping(element);
    // TODO(johnniwinther): Store the mapping in the resolution enqueuer.
    element.mapping = mapping;
    return compiler.withCurrentElement(element, () {
      return measure(() {
        Typedef node =
          compiler.parser.measure(() => element.parseNode(compiler));
        TypedefResolverVisitor visitor =
          new TypedefResolverVisitor(compiler, element, mapping);
        visitor.visit(node);

        return mapping;
      });
    });
  }

  FunctionType computeFunctionType(Element element,
                                   FunctionSignature signature) {
    var parameterTypes = new LinkBuilder<DartType>();
    for (Element parameter in signature.requiredParameters) {
       parameterTypes.addLast(parameter.computeType(compiler));
    }
    var optionalParameterTypes = const Link<DartType>();
    var namedParameters = const Link<SourceString>();
    var namedParameterTypes = const Link<DartType>();
    if (signature.optionalParametersAreNamed) {
      var namedParametersBuilder = new LinkBuilder<SourceString>();
      var namedParameterTypesBuilder = new LinkBuilder<DartType>();
      for (Element parameter in signature.orderedOptionalParameters) {
        namedParametersBuilder.addLast(parameter.name);
        namedParameterTypesBuilder.addLast(parameter.computeType(compiler));
      }
      namedParameters = namedParametersBuilder.toLink();
      namedParameterTypes = namedParameterTypesBuilder.toLink();
    } else {
      var optionalParameterTypesBuilder = new LinkBuilder<DartType>();
      for (Element parameter in signature.optionalParameters) {
        optionalParameterTypesBuilder.addLast(parameter.computeType(compiler));
      }
      optionalParameterTypes = optionalParameterTypesBuilder.toLink();
    }
    return new FunctionType(element,
        signature.returnType,
        parameterTypes.toLink(),
        optionalParameterTypes,
        namedParameters,
        namedParameterTypes);
  }

  void resolveMetadataAnnotation(PartialMetadataAnnotation annotation) {
    compiler.withCurrentElement(annotation.annotatedElement, () => measure(() {
      assert(annotation.resolutionState == STATE_NOT_STARTED);
      annotation.resolutionState = STATE_STARTED;

      Node node = annotation.parseNode(compiler);
      Element annotatedElement = annotation.annotatedElement;
      Element context = annotatedElement.enclosingElement;
      if (context == null) {
        context = annotatedElement;
      }
      ResolverVisitor visitor = visitorFor(context);
      node.accept(visitor);
      annotation.value = compiler.metadataHandler.compileNodeWithDefinitions(
          node, visitor.mapping, isConst: true);

      annotation.resolutionState = STATE_DONE;
    }));
  }

  error(Node node, MessageKind kind, [arguments = const {}]) {
    ResolutionError message = new ResolutionError(kind, arguments);
    compiler.reportError(node, message);
  }
}

class InitializerResolver {
  final ResolverVisitor visitor;
  final Map<Element, Node> initialized;
  Link<Node> initializers;
  bool hasSuper;

  InitializerResolver(this.visitor)
    : initialized = new Map<Element, Node>(), hasSuper = false;

  error(Node node, MessageKind kind, [arguments = const {}]) {
    visitor.error(node, kind, arguments);
  }

  warning(Node node, MessageKind kind, [arguments = const {}]) {
    visitor.warning(node, kind, arguments);
  }

  bool isFieldInitializer(SendSet node) {
    if (node.selector.asIdentifier() == null) return false;
    if (node.receiver == null) return true;
    if (node.receiver.asIdentifier() == null) return false;
    return node.receiver.asIdentifier().isThis();
  }

  reportDuplicateInitializerError(Element field, Node init, Node existing) {
    visitor.compiler.reportError(
        init,
        new ResolutionError(MessageKind.DUPLICATE_INITIALIZER,
                            {'fieldName': field.name}));
    visitor.compiler.reportMessage(
        visitor.compiler.spanFromNode(existing),
        new ResolutionError(MessageKind.ALREADY_INITIALIZED,
                            {'fieldName': field.name}),
        Diagnostic.INFO);
  }

  void checkForDuplicateInitializers(Element field, Node init) {
    // [field] can be null if it could not be resolved.
    if (field == null) return;
    SourceString name = field.name;
    if (initialized.containsKey(field)) {
      reportDuplicateInitializerError(field, init, initialized[field]);
    } else if (field.modifiers.isFinal()) {
      Node fieldNode = field.parseNode(visitor.compiler).asSendSet();
      if (fieldNode != null) {
        reportDuplicateInitializerError(field, init, fieldNode);
      }
    }
    initialized[field] = init;
  }

  void resolveFieldInitializer(FunctionElement constructor, SendSet init) {
    // init is of the form [this.]field = value.
    final Node selector = init.selector;
    final SourceString name = selector.asIdentifier().source;
    // Lookup target field.
    Element target;
    if (isFieldInitializer(init)) {
      target = constructor.getEnclosingClass().lookupLocalMember(name);
      if (target == null) {
        error(selector, MessageKind.CANNOT_RESOLVE, {'name': name});
      } else if (target.kind != ElementKind.FIELD) {
        error(selector, MessageKind.NOT_A_FIELD, {'fieldName': name});
      } else if (!target.isInstanceMember()) {
        error(selector, MessageKind.INIT_STATIC_FIELD, {'fieldName': name});
      }
    } else {
      error(init, MessageKind.INVALID_RECEIVER_IN_INITIALIZER);
    }
    visitor.useElement(init, target);
    visitor.world.registerStaticUse(target);
    checkForDuplicateInitializers(target, init);
    // Resolve initializing value.
    visitor.visitInStaticContext(init.arguments.head);
  }

  ClassElement getSuperOrThisLookupTarget(FunctionElement constructor,
                                          bool isSuperCall,
                                          Node diagnosticNode) {
    ClassElement lookupTarget = constructor.getEnclosingClass();
    if (isSuperCall) {
      // Calculate correct lookup target and constructor name.
      if (identical(lookupTarget, visitor.compiler.objectClass)) {
        error(diagnosticNode, MessageKind.SUPER_INITIALIZER_IN_OBJECT);
      } else {
        return lookupTarget.supertype.element;
      }
    }
    return lookupTarget;
  }

  Element resolveSuperOrThisForSend(FunctionElement constructor,
                                    FunctionExpression functionNode,
                                    Send call) {
    // Resolve the selector and the arguments.
    ResolverTask resolver = visitor.compiler.resolver;
    visitor.inStaticContext(() {
      visitor.resolveSelector(call, null);
      visitor.resolveArguments(call.argumentsNode);
    });
    Selector selector = visitor.mapping.getSelector(call);
    bool isSuperCall = Initializers.isSuperConstructorCall(call);

    ClassElement lookupTarget = getSuperOrThisLookupTarget(constructor,
                                                           isSuperCall,
                                                           call);
    Selector constructorSelector =
        visitor.getRedirectingThisOrSuperConstructorSelector(call);
    FunctionElement calledConstructor =
        lookupTarget.lookupConstructor(constructorSelector);

    final bool isImplicitSuperCall = false;
    final SourceString className = lookupTarget.name;
    verifyThatConstructorMatchesCall(calledConstructor,
                                     selector,
                                     isImplicitSuperCall,
                                     call,
                                     className,
                                     constructorSelector);

    visitor.useElement(call, calledConstructor);
    visitor.world.registerStaticUse(calledConstructor);
    return calledConstructor;
  }

  void resolveImplicitSuperConstructorSend(FunctionElement constructor,
                                           FunctionExpression functionNode) {
    // If the class has a super resolve the implicit super call.
    ClassElement classElement = constructor.getEnclosingClass();
    ClassElement superClass = classElement.superclass;
    if (classElement != visitor.compiler.objectClass) {
      assert(superClass != null);
      assert(superClass.resolutionState == STATE_DONE);
      SourceString constructorName = const SourceString('');
      Selector callToMatch = new Selector.call(
          constructorName,
          classElement.getLibrary(),
          0);

      final bool isSuperCall = true;
      ClassElement lookupTarget = getSuperOrThisLookupTarget(constructor,
                                                             isSuperCall,
                                                             functionNode);
      Selector constructorSelector = new Selector.callDefaultConstructor(
          visitor.enclosingElement.getLibrary());
      Element calledConstructor = lookupTarget.lookupConstructor(
          constructorSelector);

      final SourceString className = lookupTarget.name;
      final bool isImplicitSuperCall = true;
      verifyThatConstructorMatchesCall(calledConstructor,
                                       callToMatch,
                                       isImplicitSuperCall,
                                       functionNode,
                                       className,
                                       constructorSelector);

      visitor.world.registerStaticUse(calledConstructor);
    }
  }

  void verifyThatConstructorMatchesCall(
      FunctionElement lookedupConstructor,
      Selector call,
      bool isImplicitSuperCall,
      Node diagnosticNode,
      SourceString className,
      Selector constructorSelector) {
    if (lookedupConstructor == null
        || !lookedupConstructor.isGenerativeConstructor()) {
      var fullConstructorName =
          visitor.compiler.resolver.constructorNameForDiagnostics(
              className,
              constructorSelector.name);
      MessageKind kind = isImplicitSuperCall
          ? MessageKind.CANNOT_RESOLVE_CONSTRUCTOR_FOR_IMPLICIT
          : MessageKind.CANNOT_RESOLVE_CONSTRUCTOR;
      error(diagnosticNode, kind, {'constructorName': fullConstructorName});
    } else {
      if (!call.applies(lookedupConstructor, visitor.compiler)) {
        MessageKind kind = isImplicitSuperCall
                           ? MessageKind.NO_MATCHING_CONSTRUCTOR_FOR_IMPLICIT
                           : MessageKind.NO_MATCHING_CONSTRUCTOR;
        error(diagnosticNode, kind);
      }
    }
  }

  FunctionElement resolveRedirection(FunctionElement constructor,
                                     FunctionExpression functionNode) {
    if (functionNode.initializers == null) return null;
    Link<Node> link = functionNode.initializers.nodes;
    if (!link.isEmpty && Initializers.isConstructorRedirect(link.head)) {
      return resolveSuperOrThisForSend(constructor, functionNode, link.head);
    }
    return null;
  }

  /**
   * Resolve all initializers of this constructor. In the case of a redirecting
   * constructor, the resolved constructor's function element is returned.
   */
  FunctionElement resolveInitializers(FunctionElement constructor,
                                      FunctionExpression functionNode) {
    // Keep track of all "this.param" parameters specified for constructor so
    // that we can ensure that fields are initialized only once.
    FunctionSignature functionParameters =
        constructor.computeSignature(visitor.compiler);
    functionParameters.forEachParameter((Element element) {
      if (identical(element.kind, ElementKind.FIELD_PARAMETER)) {
        FieldParameterElement fieldParameter = element;
        checkForDuplicateInitializers(fieldParameter.fieldElement,
                                      element.parseNode(visitor.compiler));
      }
    });

    if (functionNode.initializers == null) {
      initializers = const Link<Node>();
    } else {
      initializers = functionNode.initializers.nodes;
    }
    FunctionElement result;
    bool resolvedSuper = false;
    for (Link<Node> link = initializers;
         !link.isEmpty;
         link = link.tail) {
      if (link.head.asSendSet() != null) {
        final SendSet init = link.head.asSendSet();
        resolveFieldInitializer(constructor, init);
      } else if (link.head.asSend() != null) {
        final Send call = link.head.asSend();
        if (Initializers.isSuperConstructorCall(call)) {
          if (resolvedSuper) {
            error(call, MessageKind.DUPLICATE_SUPER_INITIALIZER);
          }
          resolveSuperOrThisForSend(constructor, functionNode, call);
          resolvedSuper = true;
        } else if (Initializers.isConstructorRedirect(call)) {
          // Check that there is no body (Language specification 7.5.1).
          if (functionNode.hasBody()) {
            error(functionNode, MessageKind.REDIRECTING_CONSTRUCTOR_HAS_BODY);
          }
          // Check that there are no other initializers.
          if (!initializers.tail.isEmpty) {
            error(call, MessageKind.REDIRECTING_CONSTRUCTOR_HAS_INITIALIZER);
          }
          // Check that there are no field initializing parameters.
          Compiler compiler = visitor.compiler;
          FunctionSignature signature = constructor.computeSignature(compiler);
          signature.forEachParameter((Element parameter) {
            if (parameter.isFieldParameter()) {
              Node node = parameter.parseNode(compiler);
              error(node, MessageKind.INITIALIZING_FORMAL_NOT_ALLOWED);
            }
          });
          return resolveSuperOrThisForSend(constructor, functionNode, call);
        } else {
          visitor.error(call, MessageKind.CONSTRUCTOR_CALL_EXPECTED);
          return null;
        }
      } else {
        error(link.head, MessageKind.INVALID_INITIALIZER);
      }
    }
    if (!resolvedSuper) {
      resolveImplicitSuperConstructorSend(constructor, functionNode);
    }
    return null;  // If there was no redirection always return null.
  }
}

class CommonResolverVisitor<R> extends Visitor<R> {
  final Compiler compiler;

  CommonResolverVisitor(Compiler this.compiler);

  R visitNode(Node node) {
    cancel(node,
           'internal error: Unhandled node: ${node.getObjectDescription()}');
  }

  R visitEmptyStatement(Node node) => null;

  /** Convenience method for visiting nodes that may be null. */
  R visit(Node node) => (node == null) ? null : node.accept(this);

  void error(Node node, MessageKind kind, [Map arguments = const {}]) {
    ResolutionError message  = new ResolutionError(kind, arguments);
    compiler.reportError(node, message);
  }

  void warning(Node node, MessageKind kind, [Map arguments = const {}]) {
    ResolutionWarning message  = new ResolutionWarning(kind, arguments);
    compiler.reportWarning(node, message);
  }

  void cancel(Node node, String message) {
    compiler.cancel(message, node: node);
  }

  void internalError(Node node, String message) {
    compiler.internalError(message, node: node);
  }

  void unimplemented(Node node, String message) {
    compiler.unimplemented(message, node: node);
  }
}

abstract class LabelScope {
  LabelScope get outer;
  LabelElement lookup(String label);
}

class LabeledStatementLabelScope implements LabelScope {
  final LabelScope outer;
  final Map<String, LabelElement> labels;
  LabeledStatementLabelScope(this.outer, this.labels);
  LabelElement lookup(String labelName) {
    LabelElement label = labels[labelName];
    if (label != null) return label;
    return outer.lookup(labelName);
  }
}

class SwitchLabelScope implements LabelScope {
  final LabelScope outer;
  final Map<String, LabelElement> caseLabels;

  SwitchLabelScope(this.outer, this.caseLabels);

  LabelElement lookup(String labelName) {
    LabelElement result = caseLabels[labelName];
    if (result != null) return result;
    return outer.lookup(labelName);
  }
}

class EmptyLabelScope implements LabelScope {
  const EmptyLabelScope();
  LabelElement lookup(String label) => null;
  LabelScope get outer {
    throw 'internal error: empty label scope has no outer';
  }
}

class StatementScope {
  LabelScope labels;
  Link<TargetElement> breakTargetStack;
  Link<TargetElement> continueTargetStack;
  // Used to provide different numbers to statements if one is inside the other.
  // Can be used to make otherwise duplicate labels unique.
  int nestingLevel = 0;

  StatementScope()
      : labels = const EmptyLabelScope(),
        breakTargetStack = const Link<TargetElement>(),
        continueTargetStack = const Link<TargetElement>();

  LabelElement lookupLabel(String label) {
    return labels.lookup(label);
  }

  TargetElement currentBreakTarget() =>
    breakTargetStack.isEmpty ? null : breakTargetStack.head;

  TargetElement currentContinueTarget() =>
    continueTargetStack.isEmpty ? null : continueTargetStack.head;

  void enterLabelScope(Map<String, LabelElement> elements) {
    labels = new LabeledStatementLabelScope(labels, elements);
    nestingLevel++;
  }

  void exitLabelScope() {
    nestingLevel--;
    labels = labels.outer;
  }

  void enterLoop(TargetElement element) {
    breakTargetStack = breakTargetStack.prepend(element);
    continueTargetStack = continueTargetStack.prepend(element);
    nestingLevel++;
  }

  void exitLoop() {
    nestingLevel--;
    breakTargetStack = breakTargetStack.tail;
    continueTargetStack = continueTargetStack.tail;
  }

  void enterSwitch(TargetElement breakElement,
                   Map<String, LabelElement> continueElements) {
    breakTargetStack = breakTargetStack.prepend(breakElement);
    labels = new SwitchLabelScope(labels, continueElements);
    nestingLevel++;
  }

  void exitSwitch() {
    nestingLevel--;
    breakTargetStack = breakTargetStack.tail;
    labels = labels.outer;
  }
}

class TypeResolver {
  final Compiler compiler;

  TypeResolver(this.compiler);

  Element resolveTypeName(Scope scope,
                          SourceString prefixName,
                          Identifier typeName) {
    if (prefixName != null) {
      Element e = scope.lookup(prefixName);
      if (e != null) {
        if (identical(e.kind, ElementKind.PREFIX)) {
          // The receiver is a prefix. Lookup in the imported members.
          PrefixElement prefix = e;
          return prefix.lookupLocalMember(typeName.source);
        } else if (identical(e.kind, ElementKind.CLASS)) {
          // TODO(johnniwinther): Remove this case.
          // The receiver is the class part of a named constructor.
          return e;
        }
      } else {
        // The caller creates the ErroneousElement for the MalformedType.
        return null;
      }
    } else {
      String stringValue = typeName.source.stringValue;
      if (identical(stringValue, 'void')) {
        return compiler.types.voidType.element;
      } else if (identical(stringValue, 'dynamic')) {
        return compiler.dynamicClass;
      } else {
        return scope.lookup(typeName.source);
      }
    }
  }

  // TODO(johnniwinther): Change  [onFailure] and [whenResolved] to use boolean
  // flags instead of closures.
  DartType resolveTypeAnnotation(
      MappingVisitor visitor,
      TypeAnnotation node,
      {onFailure(Node node, MessageKind kind, [Map arguments])}) {
    if (onFailure == null) {
      onFailure = (n, k, [arguments]) {};
    }
    return resolveTypeAnnotationInContext(visitor, node, onFailure);
  }

  DartType resolveTypeAnnotationInContext(MappingVisitor visitor,
                                          TypeAnnotation node,
                                          onFailure) {
    Identifier typeName;
    SourceString prefixName;
    Send send = node.typeName.asSend();
    if (send != null) {
      // The type name is of the form [: prefix . identifier :].
      prefixName = send.receiver.asIdentifier().source;
      typeName = send.selector.asIdentifier();
    } else {
      typeName = node.typeName.asIdentifier();
    }

    Element element = resolveTypeName(visitor.scope, prefixName, typeName);
    DartType type;

    DartType reportFailureAndCreateType(MessageKind messageKind,
                                        Map messageArguments) {
      onFailure(node, messageKind, messageArguments);
      var erroneousElement = new ErroneousElementX(
          messageKind, messageArguments, typeName.source,
          visitor.enclosingElement);
      var arguments = new LinkBuilder<DartType>();
      resolveTypeArguments(
          visitor, node, null,
          onFailure, arguments);
      return new MalformedType(erroneousElement, null, arguments.toLink());
    }

    DartType checkNoTypeArguments(DartType type) {
      var arguments = new LinkBuilder<DartType>();
      bool hashTypeArgumentMismatch = resolveTypeArguments(
          visitor, node, const Link<DartType>(),
          onFailure, arguments);
      if (hashTypeArgumentMismatch) {
        type = new MalformedType(
            new ErroneousElementX(MessageKind.TYPE_ARGUMENT_COUNT_MISMATCH,
                {'type': node}, typeName.source, visitor.enclosingElement),
                type, arguments.toLink());
      }
      return type;
    }

    if (element == null) {
      type = reportFailureAndCreateType(
          MessageKind.CANNOT_RESOLVE_TYPE, {'typeName': node.typeName});
    } else if (element.isAmbiguous()) {
      AmbiguousElement ambiguous = element;
      type = reportFailureAndCreateType(
          ambiguous.messageKind, ambiguous.messageArguments);
      ambiguous.diagnose(visitor.mapping.currentElement, compiler);
    } else if (!element.impliesType()) {
      type = reportFailureAndCreateType(
          MessageKind.NOT_A_TYPE, {'node': node.typeName});
    } else {
      if (identical(element, compiler.types.voidType.element) ||
          identical(element, compiler.types.dynamicType.element)) {
        type = checkNoTypeArguments(element.computeType(compiler));
      } else if (element.isClass()) {
        ClassElement cls = element;
        compiler.resolver._ensureClassWillBeResolved(cls);
        element.computeType(compiler);
        var arguments = new LinkBuilder<DartType>();
        bool hashTypeArgumentMismatch = resolveTypeArguments(
            visitor, node, cls.typeVariables,
            onFailure, arguments);
        if (hashTypeArgumentMismatch) {
          type = new MalformedType(
              new ErroneousElementX(MessageKind.TYPE_ARGUMENT_COUNT_MISMATCH,
                  {'type': node}, typeName.source, visitor.enclosingElement),
              new InterfaceType.userProvidedBadType(cls.declaration,
                                                    arguments.toLink()));
        } else {
          if (arguments.isEmpty) {
            type = cls.rawType;
          } else {
            type = new InterfaceType(cls.declaration, arguments.toLink());
          }
        }
      } else if (element.isTypedef()) {
        TypedefElement typdef = element;
        // TODO(ahe): Should be [ensureResolved].
        compiler.resolveTypedef(typdef);
        var arguments = new LinkBuilder<DartType>();
        bool hashTypeArgumentMismatch = resolveTypeArguments(
            visitor, node, typdef.typeVariables,
            onFailure, arguments);
        if (hashTypeArgumentMismatch) {
          type = new MalformedType(
              new ErroneousElementX(MessageKind.TYPE_ARGUMENT_COUNT_MISMATCH,
                  {'type': node}, typeName.source, visitor.enclosingElement),
              new TypedefType.userProvidedBadType(typdef, arguments.toLink()));
        } else {
          if (arguments.isEmpty) {
            type = typdef.rawType;
          } else {
           type = new TypedefType(typdef, arguments.toLink());
          }
        }
      } else if (element.isTypeVariable()) {
        Element outer =
            visitor.enclosingElement.getOutermostEnclosingMemberOrTopLevel();
        bool isInFactoryConstructor =
            outer != null && outer.isFactoryConstructor();
        if (!outer.isClass() &&
            !outer.isTypedef() &&
            !isInFactoryConstructor &&
            Elements.isInStaticContext(visitor.enclosingElement)) {
          compiler.backend.registerThrowRuntimeError(visitor.mapping);
          compiler.reportWarning(node,
              MessageKind.TYPE_VARIABLE_WITHIN_STATIC_MEMBER.message(
                  {'typeVariableName': node}));
          type = new MalformedType(
              new ErroneousElementX(
                  MessageKind.TYPE_VARIABLE_WITHIN_STATIC_MEMBER,
                  {'typeVariableName': node},
                  typeName.source, visitor.enclosingElement),
                  element.computeType(compiler));
        } else {
          type = element.computeType(compiler);
        }
        type = checkNoTypeArguments(type);
      } else {
        compiler.cancel("unexpected element kind ${element.kind}",
                        node: node);
      }
    }
    visitor.useType(node, type);
    return type;
  }

  /**
   * Resolves the type arguments of [node] and adds these to [arguments].
   *
   * Returns [: true :] if the number of type arguments did not match the
   * number of type variables.
   */
  bool resolveTypeArguments(
      MappingVisitor visitor,
      TypeAnnotation node,
      Link<DartType> typeVariables,
      onFailure,
      LinkBuilder<DartType> arguments) {
    if (node.typeArguments == null) {
      return false;
    }
    bool typeArgumentCountMismatch = false;
    for (Link<Node> typeArguments = node.typeArguments.nodes;
         !typeArguments.isEmpty;
         typeArguments = typeArguments.tail) {
      if (typeVariables != null && typeVariables.isEmpty) {
        onFailure(typeArguments.head, MessageKind.ADDITIONAL_TYPE_ARGUMENT);
        typeArgumentCountMismatch = true;
      }
      DartType argType = resolveTypeAnnotationInContext(visitor,
                                                        typeArguments.head,
                                                        onFailure);
      arguments.addLast(argType);
      if (typeVariables != null && !typeVariables.isEmpty) {
        typeVariables = typeVariables.tail;
      }
    }
    if (typeVariables != null && !typeVariables.isEmpty) {
      onFailure(node.typeArguments, MessageKind.MISSING_TYPE_ARGUMENT);
      typeArgumentCountMismatch = true;
    }
    return typeArgumentCountMismatch;
  }
}

/**
 * Common supertype for resolver visitors that record resolutions in a
 * [TreeElements] mapping.
 */
abstract class MappingVisitor<T> extends CommonResolverVisitor<T> {
  final TreeElementMapping mapping;
  final TypeResolver typeResolver;
  /// The current enclosing element for the visited AST nodes.
  Element get enclosingElement;
  /// The current scope of the visitor.
  Scope get scope;

  MappingVisitor(Compiler compiler, TreeElementMapping this.mapping)
      : typeResolver = new TypeResolver(compiler),
        super(compiler);

  Element useElement(Node node, Element element) {
    if (element == null) return null;
    return mapping[node] = element;
  }

  DartType useType(TypeAnnotation annotation, DartType type) {
    if (type != null) {
      mapping.setType(annotation, type);
      useElement(annotation, type.element);
    }
    return type;
  }
}

/**
 * Core implementation of resolution.
 *
 * Do not subclass or instantiate this class outside this library
 * except for testing.
 */
class ResolverVisitor extends MappingVisitor<Element> {
  /**
   * The current enclosing element for the visited AST nodes.
   *
   * This field is updated when nested closures are visited.
   */
  Element enclosingElement;
  bool inInstanceContext;
  bool inCheckContext;
  bool inCatchBlock;
  Scope scope;
  ClassElement currentClass;
  ExpressionStatement currentExpressionStatement;
  bool typeRequired = false;
  bool sendIsMemberAccess = false;
  StatementScope statementScope;
  int allowedCategory = ElementCategory.VARIABLE | ElementCategory.FUNCTION
      | ElementCategory.IMPLIES_TYPE;

  // TODO(ahe): Find a way to share this with runtime implementation.
  static final RegExp symbolValidationPattern =
      new RegExp(r'^(?:[a-zA-Z$][a-zA-Z$0-9_]*\.)*(?:[a-zA-Z$][a-zA-Z$0-9_]*=?|'
                 r'-|'
                 r'unary-|'
                 r'\[\]=|'
                 r'~|'
                 r'==|'
                 r'\[\]|'
                 r'\*|'
                 r'/|'
                 r'%|'
                 r'~/|'
                 r'\+|'
                 r'<<|'
                 r'>>|'
                 r'>=|'
                 r'>|'
                 r'<=|'
                 r'<|'
                 r'&|'
                 r'\^|'
                 r'\|'
                 r')$');

  ResolverVisitor(Compiler compiler,
                  Element element,
                  TreeElementMapping mapping)
    : this.enclosingElement = element,
      // When the element is a field, we are actually resolving its
      // initial value, which should not have access to instance
      // fields.
      inInstanceContext = (element.isInstanceMember() && !element.isField())
          || element.isGenerativeConstructor(),
      this.currentClass = element.isMember() ? element.getEnclosingClass()
                                             : null,
      this.statementScope = new StatementScope(),
      scope = element.buildScope(),
      // The type annotations on a typedef do not imply type checks.
      // TODO(karlklose): clean this up (dartbug.com/8870).
      inCheckContext = compiler.enableTypeAssertions &&
          !element.isTypedef() &&
          (element.enclosingElement == null ||
           !element.enclosingElement.isTypedef()),
      inCatchBlock = false,
      super(compiler, mapping);

  ResolutionEnqueuer get world => compiler.enqueuer.resolution;

  Element lookup(Node node, SourceString name) {
    Element result = scope.lookup(name);
    if (!Elements.isUnresolved(result)) {
      if (!inInstanceContext && result.isInstanceMember()) {
        compiler.reportErrorCode(
            node, MessageKind.NO_INSTANCE_AVAILABLE, {'name': name});
        return new ErroneousElementX(MessageKind.NO_INSTANCE_AVAILABLE,
                                     {'name': name},
                                     name, enclosingElement);
      } else if (result.isAmbiguous()) {
        AmbiguousElement ambiguous = result;
        compiler.reportErrorCode(
            node, ambiguous.messageKind, ambiguous.messageArguments);
        ambiguous.diagnose(enclosingElement, compiler);
        return new ErroneousElementX(ambiguous.messageKind,
                                     ambiguous.messageArguments,
                                     name, enclosingElement);
      }
    }
    return result;
  }

  // Create, or reuse an already created, statement element for a statement.
  TargetElement getOrCreateTargetElement(Node statement) {
    TargetElement element = mapping[statement];
    if (element == null) {
      element = new TargetElementX(statement,
                                   statementScope.nestingLevel,
                                   enclosingElement);
      mapping[statement] = element;
    }
    return element;
  }

  doInCheckContext(action()) {
    bool wasInCheckContext = inCheckContext;
    inCheckContext = true;
    var result = action();
    inCheckContext = wasInCheckContext;
    return result;
  }

  inStaticContext(action()) {
    bool wasInstanceContext = inInstanceContext;
    inInstanceContext = false;
    var result = action();
    inInstanceContext = wasInstanceContext;
    return result;
  }

  visitInStaticContext(Node node) {
    inStaticContext(() => visit(node));
  }

  ErroneousElement warnAndCreateErroneousElement(Node node,
                                                 SourceString name,
                                                 MessageKind kind,
                                                 [Map arguments = const {}]) {
    ResolutionWarning warning = new ResolutionWarning(kind, arguments);
    compiler.reportWarning(node, warning);
    return new ErroneousElementX(kind, arguments, name, enclosingElement);
  }

  Element visitIdentifier(Identifier node) {
    if (node.isThis()) {
      if (!inInstanceContext) {
        error(node, MessageKind.NO_INSTANCE_AVAILABLE, {'name': node});
      }
      return null;
    } else if (node.isSuper()) {
      if (!inInstanceContext) error(node, MessageKind.NO_SUPER_IN_STATIC);
      if ((ElementCategory.SUPER & allowedCategory) == 0) {
        error(node, MessageKind.INVALID_USE_OF_SUPER);
      }
      return null;
    } else {
      Element element = lookup(node, node.source);
      if (element == null) {
        if (!inInstanceContext) {
          element = warnAndCreateErroneousElement(node, node.source,
                                                  MessageKind.CANNOT_RESOLVE,
                                                  {'name': node});
          compiler.backend.registerThrowNoSuchMethod(mapping);
        }
      } else if (element.isErroneous()) {
        // Use the erroneous element.
      } else {
        if ((element.kind.category & allowedCategory) == 0) {
          // TODO(ahe): Improve error message. Need UX input.
          error(node, MessageKind.GENERIC,
                {'text': "is not an expression $element"});
        }
      }
      if (!Elements.isUnresolved(element) && element.isClass()) {
        ClassElement classElement = element;
        classElement.ensureResolved(compiler);
      }
      return useElement(node, element);
    }
  }

  Element visitTypeAnnotation(TypeAnnotation node) {
    DartType type = resolveTypeAnnotation(node);
    if (type != null) {
      if (inCheckContext) {
        compiler.enqueuer.resolution.registerIsCheck(type, mapping);
      }
      return type.element;
    }
    return null;
  }

  Element defineElement(Node node, Element element,
                        {bool doAddToScope: true}) {
    compiler.ensure(element != null);
    mapping[node] = element;
    if (doAddToScope) {
      Element existing = scope.add(element);
      if (existing != element) {
        compiler.reportErrorCode(
            node, MessageKind.DUPLICATE_DEFINITION, {'name': node});
        compiler.reportMessage(
            compiler.spanFromSpannable(existing),
            MessageKind.EXISTING_DEFINITION.error({'name': node}),
            Diagnostic.INFO);
      }
    }
    return element;
  }

  bool isNamedConstructor(Send node) => node.receiver != null;

  Selector getRedirectingThisOrSuperConstructorSelector(Send node) {
    if (isNamedConstructor(node)) {
      SourceString constructorName = node.selector.asIdentifier().source;
      return new Selector.callConstructor(
          constructorName,
          enclosingElement.getLibrary());
    } else {
      return new Selector.callDefaultConstructor(
          enclosingElement.getLibrary());
    }
  }

  FunctionElement resolveConstructorRedirection(FunctionElement constructor) {
    FunctionExpression node = constructor.parseNode(compiler);

    // A synthetic constructor does not have a node.
    if (node == null) return null;
    if (node.initializers == null) return null;
    Link<Node> initializers = node.initializers.nodes;
    if (!initializers.isEmpty &&
        Initializers.isConstructorRedirect(initializers.head)) {
      Selector selector =
          getRedirectingThisOrSuperConstructorSelector(initializers.head);
      final ClassElement classElement = constructor.getEnclosingClass();
      return classElement.lookupConstructor(selector);
    }
    return null;
  }

  void setupFunction(FunctionExpression node, FunctionElement function) {
    Element enclosingElement = function.enclosingElement;
    if (node.modifiers.isStatic() &&
        enclosingElement.kind != ElementKind.CLASS) {
      compiler.reportErrorCode(node, MessageKind.ILLEGAL_STATIC);
    }

    scope = new MethodScope(scope, function);
    // Put the parameters in scope.
    FunctionSignature functionParameters =
        function.computeSignature(compiler);
    Link<Node> parameterNodes = (node.parameters == null)
        ? const Link<Node>() : node.parameters.nodes;
    functionParameters.forEachParameter((Element element) {
      if (element == functionParameters.optionalParameters.head) {
        NodeList nodes = parameterNodes.head;
        parameterNodes = nodes.nodes;
      }
      VariableDefinitions variableDefinitions = parameterNodes.head;
      Node parameterNode = variableDefinitions.definitions.nodes.head;
      initializerDo(parameterNode, (n) => n.accept(this));
      // Field parameters (this.x) are not visible inside the constructor. The
      // fields they reference are visible, but must be resolved independently.
      if (element.kind == ElementKind.FIELD_PARAMETER) {
        useElement(parameterNode, element);
      } else {
        defineElement(variableDefinitions.definitions.nodes.head, element);
      }
      parameterNodes = parameterNodes.tail;
    });
    if (inCheckContext) {
      functionParameters.forEachParameter((Element element) {
        compiler.enqueuer.resolution.registerIsCheck(
            element.computeType(compiler), mapping);
      });
    }
  }

  visitCascade(Cascade node) {
    visit(node.expression);
  }

  visitCascadeReceiver(CascadeReceiver node) {
    visit(node.expression);
  }

  Element visitClassNode(ClassNode node) {
    cancel(node, "shouldn't be called");
  }

  visitIn(Node node, Scope nestedScope) {
    Scope oldScope = scope;
    scope = nestedScope;
    Element element = visit(node);
    scope = oldScope;
    return element;
  }

  /**
   * Introduces new default targets for break and continue
   * before visiting the body of the loop
   */
  visitLoopBodyIn(Node loop, Node body, Scope bodyScope) {
    TargetElement element = getOrCreateTargetElement(loop);
    statementScope.enterLoop(element);
    visitIn(body, bodyScope);
    statementScope.exitLoop();
    if (!element.isTarget) {
      mapping.remove(loop);
    }
  }

  visitBlock(Block node) {
    visitIn(node.statements, new BlockScope(scope));
  }

  visitDoWhile(DoWhile node) {
    visitLoopBodyIn(node, node.body, new BlockScope(scope));
    visit(node.condition);
  }

  visitEmptyStatement(EmptyStatement node) { }

  visitExpressionStatement(ExpressionStatement node) {
    ExpressionStatement oldExpressionStatement = currentExpressionStatement;
    currentExpressionStatement = node;
    visit(node.expression);
    currentExpressionStatement = oldExpressionStatement;
  }

  visitFor(For node) {
    Scope blockScope = new BlockScope(scope);
    visitIn(node.initializer, blockScope);
    visitIn(node.condition, blockScope);
    visitIn(node.update, blockScope);
    visitLoopBodyIn(node, node.body, blockScope);
  }

  visitFunctionDeclaration(FunctionDeclaration node) {
    assert(node.function.name != null);
    visit(node.function);
    FunctionElement functionElement = mapping[node.function];
    // TODO(floitsch): this might lead to two errors complaining about
    // shadowing.
    defineElement(node, functionElement);
  }

  visitFunctionExpression(FunctionExpression node) {
    visit(node.returnType);
    SourceString name;
    if (node.name == null) {
      name = const SourceString("");
    } else {
      name = node.name.asIdentifier().source;
    }
    FunctionElement function = new FunctionElementX.node(
        name, node, ElementKind.FUNCTION, Modifiers.EMPTY,
        enclosingElement);
    Scope oldScope = scope; // The scope is modified by [setupFunction].
    setupFunction(node, function);
    defineElement(node, function, doAddToScope: node.name != null);

    Element previousEnclosingElement = enclosingElement;
    enclosingElement = function;
    // Run the body in a fresh statement scope.
    StatementScope oldStatementScope = statementScope;
    statementScope = new StatementScope();
    visit(node.body);
    statementScope = oldStatementScope;

    scope = oldScope;
    enclosingElement = previousEnclosingElement;

    world.registerClosurizedMember(function, mapping);
    world.registerInstantiatedClass(compiler.functionClass, mapping);
  }

  visitIf(If node) {
    visit(node.condition);
    visitIn(node.thenPart, new BlockScope(scope));
    visitIn(node.elsePart, new BlockScope(scope));
  }

  static bool isLogicalOperator(Identifier op) {
    String str = op.source.stringValue;
    return (identical(str, '&&') || str == '||' || str == '!');
  }

  Element resolveSend(Send node) {
    Selector selector = resolveSelector(node, null);
    if (node.isSuperCall) mapping.superUses.add(node);

    if (node.receiver == null) {
      // If this send is of the form "assert(expr);", then
      // this is an assertion.
      if (selector.isAssert()) {
        if (selector.argumentCount != 1) {
          error(node.selector,
                MessageKind.WRONG_NUMBER_OF_ARGUMENTS_FOR_ASSERT,
                {'argumentCount': selector.argumentCount});
        } else if (selector.namedArgumentCount != 0) {
          error(node.selector,
                MessageKind.ASSERT_IS_GIVEN_NAMED_ARGUMENTS,
                {'argumentCount': selector.namedArgumentCount});
        }
        return compiler.assertMethod;
      }

      return node.selector.accept(this);
    }

    var oldCategory = allowedCategory;
    allowedCategory |= ElementCategory.PREFIX | ElementCategory.SUPER;
    Element resolvedReceiver = visit(node.receiver);
    allowedCategory = oldCategory;

    Element target;
    SourceString name = node.selector.asIdentifier().source;
    if (identical(name.stringValue, 'this')) {
      // TODO(ahe): Why is this using GENERIC?
      error(node.selector, MessageKind.GENERIC,
            {'text': "expected an identifier"});
    } else if (node.isSuperCall) {
      if (node.isOperator) {
        if (isUserDefinableOperator(name.stringValue)) {
          name = selector.name;
        } else {
          error(node.selector, MessageKind.ILLEGAL_SUPER_SEND, {'name': name});
        }
      }
      if (!inInstanceContext) {
        error(node.receiver, MessageKind.NO_INSTANCE_AVAILABLE, {'name': name});
        return null;
      }
      if (currentClass.supertype == null) {
        // This is just to guard against internal errors, so no need
        // for a real error message.
        error(node.receiver, MessageKind.GENERIC,
              {'text': "Object has no superclass"});
      }
      // TODO(johnniwinther): Ensure correct behavior if currentClass is a
      // patch.
      target = currentClass.lookupSuperSelector(selector, compiler);
      // [target] may be null which means invoking noSuchMethod on
      // super.
      if (target == null) {
        target = warnAndCreateErroneousElement(
            node, name, MessageKind.NO_SUCH_SUPER_MEMBER,
            {'className': currentClass, 'memberName': name});
        // We still need to register the invocation, because we might
        // call [:super.noSuchMethod:] which calls
        // [JSInvocationMirror._invokeOn].
        world.registerDynamicInvocation(selector);
        compiler.backend.registerSuperNoSuchMethod(mapping);
      }
    } else if (Elements.isUnresolved(resolvedReceiver)) {
      return null;
    } else if (resolvedReceiver.isClass()) {
      ClassElement receiverClass = resolvedReceiver;
      receiverClass.ensureResolved(compiler);
      if (node.isOperator) {
        // When the resolved receiver is a class, we can have two cases:
        //  1) a static send: C.foo, or
        //  2) an operator send, where the receiver is a class literal: 'C + 1'.
        // The following code that looks up the selector on the resolved
        // receiver will treat the second as the invocation of a static operator
        // if the resolved receiver is not null.
        return null;
      }
      target = receiverClass.lookupLocalMember(name);
      if (target == null || target.isInstanceMember()) {
        compiler.backend.registerThrowNoSuchMethod(mapping);
        // TODO(johnniwinther): With the simplified [TreeElements] invariant,
        // try to resolve injected elements if [currentClass] is in the patch
        // library of [receiverClass].

        // TODO(karlklose): this should be reported by the caller of
        // [resolveSend] to select better warning messages for getters and
        // setters.
        MessageKind kind = (target == null)
            ? MessageKind.MEMBER_NOT_FOUND
            : MessageKind.MEMBER_NOT_STATIC;
        return warnAndCreateErroneousElement(node, name, kind,
                                             {'className': receiverClass.name,
                                              'memberName': name});
      }
    } else if (identical(resolvedReceiver.kind, ElementKind.PREFIX)) {
      PrefixElement prefix = resolvedReceiver;
      target = prefix.lookupLocalMember(name);
      if (Elements.isUnresolved(target)) {
        compiler.backend.registerThrowNoSuchMethod(mapping);
        return warnAndCreateErroneousElement(
            node, name, MessageKind.NO_SUCH_LIBRARY_MEMBER,
            {'libraryName': prefix.name, 'memberName': name});
      } else if (target.kind == ElementKind.CLASS) {
        ClassElement classElement = target;
        classElement.ensureResolved(compiler);
      }
    }
    return target;
  }

  static Selector computeSendSelector(Send node,
                                      LibraryElement library,
                                      Element element) {
    // First determine if this is part of an assignment.
    bool isSet = node.asSendSet() != null;

    if (node.isIndex) {
      return isSet ? new Selector.indexSet() : new Selector.index();
    }

    if (node.isOperator) {
      SourceString source = node.selector.asOperator().source;
      String string = source.stringValue;
      if (identical(string, '!') ||
          identical(string, '&&') || identical(string, '||') ||
          identical(string, 'is') || identical(string, 'as') ||
          identical(string, '===') || identical(string, '!==') ||
          identical(string, '?') ||
          identical(string, '>>>')) {
        return null;
      }
      if (!isUserDefinableOperator(source.stringValue)) {
        source = Elements.mapToUserOperator(source);
      }
      return node.arguments.isEmpty
          ? new Selector.unaryOperator(source)
          : new Selector.binaryOperator(source);
    }

    Identifier identifier = node.selector.asIdentifier();
    if (node.isPropertyAccess) {
      assert(!isSet);
      return new Selector.getter(identifier.source, library);
    } else if (isSet) {
      return new Selector.setter(identifier.source, library);
    }

    // Compute the arity and the list of named arguments.
    int arity = 0;
    List<SourceString> named = <SourceString>[];
    for (Link<Node> link = node.argumentsNode.nodes;
        !link.isEmpty;
        link = link.tail) {
      Expression argument = link.head;
      NamedArgument namedArgument = argument.asNamedArgument();
      if (namedArgument != null) {
        named.add(namedArgument.name.source);
      }
      arity++;
    }

    if (element != null && element.isConstructor()) {
      return new Selector.callConstructor(
          element.name, library, arity, named);
    }

    // If we're invoking a closure, we do not have an identifier.
    return (identifier == null)
        ? new Selector.callClosure(arity, named)
        : new Selector.call(identifier.source, library, arity, named);
  }

  Selector resolveSelector(Send node, Element element) {
    LibraryElement library = enclosingElement.getLibrary();
    Selector selector = computeSendSelector(node, library, element);
    if (selector != null) mapping.setSelector(node, selector);
    return selector;
  }

  void resolveArguments(NodeList list) {
    if (list == null) return;
    Map<SourceString, Node> seenNamedArguments = new Map<SourceString, Node>();
    for (Link<Node> link = list.nodes; !link.isEmpty; link = link.tail) {
      Expression argument = link.head;
      visit(argument);
      NamedArgument namedArgument = argument.asNamedArgument();
      if (namedArgument != null) {
        SourceString source = namedArgument.name.source;
        if (seenNamedArguments.containsKey(source)) {
          compiler.reportErrorCode(
              argument,
              MessageKind.DUPLICATE_DEFINITION,
              {'name': source});
          compiler.reportMessage(
              compiler.spanFromSpannable(seenNamedArguments[source]),
              MessageKind.EXISTING_DEFINITION.error({'name': source}),
              Diagnostic.INFO);
        } else {
          seenNamedArguments[source] = namedArgument;
        }
      } else if (!seenNamedArguments.isEmpty) {
        error(argument, MessageKind.INVALID_ARGUMENT_AFTER_NAMED);
      }
    }
  }

  visitSend(Send node) {
    bool oldSendIsMemberAccess = sendIsMemberAccess;
    sendIsMemberAccess = node.isPropertyAccess || node.isCall;
    Element target = resolveSend(node);
    sendIsMemberAccess = oldSendIsMemberAccess;

    if (target != null && target == compiler.mirrorSystemGetNameFunction) {
      compiler.reportHint(
          node.selector, MessageKind.STATIC_FUNCTION_BLOAT,
          {'class': compiler.mirrorSystemClass.name,
           'name': compiler.mirrorSystemGetNameFunction.name});
    }

    if (!Elements.isUnresolved(target)) {
      if (target.isAbstractField()) {
        AbstractFieldElement field = target;
        target = field.getter;
        if (target == null && !inInstanceContext) {
          compiler.backend.registerThrowNoSuchMethod(mapping);
          target =
              warnAndCreateErroneousElement(node.selector, field.name,
                                            MessageKind.CANNOT_RESOLVE_GETTER);
        }
      } else if (target.isTypeVariable()) {
        ClassElement cls = target.getEnclosingClass();
        assert(enclosingElement.getEnclosingClass() == cls);
        compiler.backend.registerClassUsingVariableExpression(cls);
        compiler.backend.registerTypeVariableExpression(mapping);
        // Set the type of the node to [Type] to mark this send as a
        // type variable expression.
        mapping.setType(node, compiler.typeClass.computeType(compiler));
        world.registerInstantiatedClass(compiler.typeClass, mapping);
      } else if (target.impliesType() && !sendIsMemberAccess) {
        // Set the type of the node to [Type] to mark this send as a
        // type literal.
        mapping.setType(node, compiler.typeClass.computeType(compiler));
        world.registerTypeLiteral(target, mapping);
      }
    }

    bool resolvedArguments = false;
    if (node.isOperator) {
      String operatorString = node.selector.asOperator().source.stringValue;
      if (operatorString == 'is') {
        DartType type =
            resolveTypeRequired(node.typeAnnotationFromIsCheckOrCast);
        if (type != null) {
          compiler.enqueuer.resolution.registerIsCheck(type, mapping);
        }
        resolvedArguments = true;
      } else if (operatorString == 'as') {
        DartType type = resolveTypeRequired(node.arguments.head);
        if (type != null) {
          compiler.enqueuer.resolution.registerAsCheck(type, mapping);
        }
        resolvedArguments = true;
      }
    }

    if (!resolvedArguments) {
      oldSendIsMemberAccess = sendIsMemberAccess;
      sendIsMemberAccess = false;
      resolveArguments(node.argumentsNode);
      sendIsMemberAccess = oldSendIsMemberAccess;
    }

    // If the selector is null, it means that we will not be generating
    // code for this as a send.
    Selector selector = mapping.getSelector(node);
    if (selector == null) return;

    if (node.isCall) {
      if (Elements.isUnresolved(target) ||
          target.isGetter() ||
          target.isField() ||
          Elements.isClosureSend(node, target)) {
        // If we don't know what we're calling or if we are calling a getter,
        // we need to register that fact that we may be calling a closure
        // with the same arguments.
        Selector call = new Selector.callClosureFrom(selector);
        world.registerDynamicInvocation(call);
      } else if (target.impliesType()) {
        // We call 'call()' on a Type instance returned from the reference to a
        // class or typedef literal. We do not need to register this call as a
        // dynamic invocation, because we statically know what the target is.
      } else if (!selector.applies(target, compiler)) {
        warnArgumentMismatch(node, target);
      }

      if (target != null &&
          target.isForeign(compiler) &&
          selector.name == const SourceString('JS')) {
        world.registerJsCall(node, this);
      }
    }

    // TODO(ngeoffray): Warn if target is null and the send is
    // unqualified.
    useElement(node, target);
    registerSend(selector, target);
    if (node.isPropertyAccess && Elements.isStaticOrTopLevelFunction(target)) {
      world.registerGetOfStaticFunction(target.declaration);
    }
    return node.isPropertyAccess ? target : null;
  }

  void warnArgumentMismatch(Send node, Element target) {
    compiler.backend.registerThrowNoSuchMethod(mapping);
    // TODO(karlklose): we can be more precise about the reason of the
    // mismatch.
    warning(node.argumentsNode, MessageKind.INVALID_ARGUMENTS,
            {'methodName': target.name});
  }

  /// Callback for native enqueuer to parse a type.  Returns [:null:] on error.
  DartType resolveTypeFromString(String typeName) {
    Element element = scope.lookup(new SourceString(typeName));
    if (element == null) return null;
    if (element is! ClassElement) return null;
    ClassElement cls = element;
    cls.ensureResolved(compiler);
    return cls.computeType(compiler);
  }

  visitSendSet(SendSet node) {
    bool oldSendIsMemberAccess = sendIsMemberAccess;
    sendIsMemberAccess = node.isPropertyAccess || node.isCall;
    Element target = resolveSend(node);
    sendIsMemberAccess = oldSendIsMemberAccess;
    Element setter = target;
    Element getter = target;
    SourceString operatorName = node.assignmentOperator.source;
    String source = operatorName.stringValue;
    bool isComplex = !identical(source, '=');
    if (!Elements.isUnresolved(target)) {
      if (target.isAbstractField()) {
        AbstractFieldElement field = target;
        setter = field.setter;
        getter = field.getter;
        if (setter == null && !inInstanceContext) {
          setter = warnAndCreateErroneousElement(
              node.selector, field.name, MessageKind.CANNOT_RESOLVE_SETTER);
          compiler.backend.registerThrowNoSuchMethod(mapping);
        }
        if (isComplex && getter == null && !inInstanceContext) {
          getter = warnAndCreateErroneousElement(
              node.selector, field.name, MessageKind.CANNOT_RESOLVE_GETTER);
          compiler.backend.registerThrowNoSuchMethod(mapping);
        }
      } else if (target.impliesType()) {
        compiler.backend.registerThrowNoSuchMethod(mapping);
      } else if (target.modifiers.isFinal() || target.modifiers.isConst()) {
        setter = warnAndCreateErroneousElement(
            node.selector, target.name, MessageKind.CANNOT_RESOLVE_SETTER);
        compiler.backend.registerThrowNoSuchMethod(mapping);
      }
    }

    visit(node.argumentsNode);

    // TODO(ngeoffray): Check if the target can be assigned.
    // TODO(ngeoffray): Warn if target is null and the send is
    // unqualified.

    Selector selector = mapping.getSelector(node);
    if (isComplex) {
      Selector getterSelector;
      if (selector.isSetter()) {
        getterSelector = new Selector.getterFrom(selector);
      } else {
        assert(selector.isIndexSet());
        getterSelector = new Selector.index();
      }
      registerSend(getterSelector, getter);
      mapping.setGetterSelectorInComplexSendSet(node, getterSelector);
      if (node.isSuperCall) {
        getter = currentClass.lookupSuperSelector(getterSelector, compiler);
        if (getter == null) {
          target = warnAndCreateErroneousElement(
              node, selector.name, MessageKind.NO_SUCH_SUPER_MEMBER,
              {'className': currentClass, 'memberName': selector.name});
          compiler.backend.registerSuperNoSuchMethod(mapping);
        }
      }
      useElement(node.selector, getter);

      // Make sure we include the + and - operators if we are using
      // the ++ and -- ones.  Also, if op= form is used, include op itself.
      void registerBinaryOperator(SourceString name) {
        Selector binop = new Selector.binaryOperator(name);
        world.registerDynamicInvocation(binop);
        mapping.setOperatorSelectorInComplexSendSet(node, binop);
      }
      if (identical(source, '++')) {
        registerBinaryOperator(const SourceString('+'));
      } else if (identical(source, '--')) {
        registerBinaryOperator(const SourceString('-'));
      } else if (source.endsWith('=')) {
        registerBinaryOperator(Elements.mapToUserOperator(operatorName));
      }
    }

    registerSend(selector, setter);
    return useElement(node, setter);
  }

  void registerSend(Selector selector, Element target) {
    if (target == null || target.isInstanceMember()) {
      if (selector.isGetter()) {
        world.registerDynamicGetter(selector);
      } else if (selector.isSetter()) {
        world.registerDynamicSetter(selector);
      } else {
        world.registerDynamicInvocation(selector);
      }
    } else if (Elements.isStaticOrTopLevel(target)) {
      // TODO(kasperl): It seems like we're not supposed to register
      // the use of classes. Wouldn't it be simpler if we just did?
      if (!target.isClass()) {
        // [target] might be the implementation element and only declaration
        // elements may be registered.
        world.registerStaticUse(target.declaration);
      }
    }
  }

  visitLiteralInt(LiteralInt node) {
    world.registerInstantiatedClass(compiler.intClass, mapping);
  }

  visitLiteralDouble(LiteralDouble node) {
    world.registerInstantiatedClass(compiler.doubleClass, mapping);
  }

  visitLiteralBool(LiteralBool node) {
    world.registerInstantiatedClass(compiler.boolClass, mapping);
  }

  visitLiteralString(LiteralString node) {
    world.registerInstantiatedClass(compiler.stringClass, mapping);
  }

  visitLiteralNull(LiteralNull node) {
    world.registerInstantiatedClass(compiler.nullClass, mapping);
  }

  visitStringJuxtaposition(StringJuxtaposition node) {
    world.registerInstantiatedClass(compiler.stringClass, mapping);
    node.visitChildren(this);
  }

  visitNodeList(NodeList node) {
    for (Link<Node> link = node.nodes; !link.isEmpty; link = link.tail) {
      visit(link.head);
    }
  }

  visitOperator(Operator node) {
    unimplemented(node, 'operator');
  }

  visitRethrow(Rethrow node) {
    if (!inCatchBlock) {
      error(node, MessageKind.THROW_WITHOUT_EXPRESSION);
    }
  }

  visitReturn(Return node) {
    if (node.isRedirectingFactoryBody) {
      handleRedirectingFactoryBody(node);
    } else {
      visit(node.expression);
    }
  }

  void handleRedirectingFactoryBody(Return node) {
    final isSymbolConstructor = enclosingElement == compiler.symbolConstructor;
    if (!enclosingElement.isFactoryConstructor()) {
      compiler.reportErrorCode(
          node, MessageKind.FACTORY_REDIRECTION_IN_NON_FACTORY);
      compiler.reportErrorCode(
          enclosingElement, MessageKind.MISSING_FACTORY_KEYWORD);
    }
    FunctionElement redirectionTarget = resolveRedirectingFactory(node);
    useElement(node.expression, redirectionTarget);
    FunctionElement constructor = enclosingElement;
    if (constructor.modifiers.isConst() &&
        !redirectionTarget.modifiers.isConst()) {
      error(node, MessageKind.CONSTRUCTOR_IS_NOT_CONST);
    }
    constructor.defaultImplementation = redirectionTarget;
    if (Elements.isUnresolved(redirectionTarget)) {
      compiler.backend.registerThrowNoSuchMethod(mapping);
      return;
    }

    // Check that the target constructor is type compatible with the
    // redirecting constructor.
    ClassElement targetClass = redirectionTarget.getEnclosingClass();
    InterfaceType type = mapping.getType(node.expression);
    FunctionType targetType = redirectionTarget.computeType(compiler)
        .subst(type.typeArguments, targetClass.typeVariables);
    FunctionType constructorType = constructor.computeType(compiler);
    if (!compiler.types.isSubtype(targetType, constructorType)) {
      warning(node, MessageKind.NOT_ASSIGNABLE,
              {'fromType': targetType, 'toType': constructorType});
    }

    FunctionSignature targetSignature =
        redirectionTarget.computeSignature(compiler);
    FunctionSignature constructorSignature =
        constructor.computeSignature(compiler);
    if (!targetSignature.isCompatibleWith(constructorSignature)) {
      compiler.backend.registerThrowNoSuchMethod(mapping);
    }

    // TODO(ahe): Check that this doesn't lead to a cycle.  For now,
    // just make sure that the redirection target isn't itself a
    // redirecting factory.
    { // This entire block is temporary code per the above TODO.
      FunctionElement targetImplementation = redirectionTarget.implementation;
      FunctionExpression function = targetImplementation.parseNode(compiler);
      if (function.body != null && function.body.asReturn() != null
          && function.body.asReturn().isRedirectingFactoryBody) {
        unimplemented(node.expression, 'redirecting to redirecting factory');
      }
    }
    world.registerStaticUse(redirectionTarget);
    world.registerInstantiatedClass(
        redirectionTarget.enclosingElement.declaration, mapping);
    if (isSymbolConstructor) {
      // Make sure that collection_dev.Symbol.validated is registered.
      assert(invariant(node, compiler.symbolValidatedConstructor != null));
      world.registerStaticUse(compiler.symbolValidatedConstructor);
    }
  }

  visitThrow(Throw node) {
    // We don't know ahead of time whether we will need the throw in a
    // statement context or an expression context, so we register both
    // here, even though we may not need ThrowExpression.
    compiler.backend.registerWrapException(mapping);
    compiler.backend.registerThrowExpression(mapping);
    visit(node.expression);
  }

  visitVariableDefinitions(VariableDefinitions node) {
    VariableDefinitionsVisitor visitor =
        new VariableDefinitionsVisitor(compiler, node, this,
                                       ElementKind.VARIABLE);
    // Ensure that we set the type of the [VariableListElement] since it depends
    // on the current scope. If the current scope is a [MethodScope] or
    // [BlockScope] it will not be available for the
    // [VariableListElement.computeType] method.
    if (node.type != null) {
      visitor.variables.type = resolveTypeAnnotation(node.type);
    } else {
      visitor.variables.type = compiler.types.dynamicType;
    }
    visitor.visit(node.definitions);
  }

  visitWhile(While node) {
    visit(node.condition);
    visitLoopBodyIn(node, node.body, new BlockScope(scope));
  }

  visitParenthesizedExpression(ParenthesizedExpression node) {
    bool oldSendIsMemberAccess = sendIsMemberAccess;
    sendIsMemberAccess = false;
    visit(node.expression);
    sendIsMemberAccess = oldSendIsMemberAccess;
  }

  visitNewExpression(NewExpression node) {
    Node selector = node.send.selector;
    FunctionElement constructor = resolveConstructor(node);
    final bool isSymbolConstructor = constructor == compiler.symbolConstructor;
    resolveSelector(node.send, constructor);
    resolveArguments(node.send.argumentsNode);
    useElement(node.send, constructor);
    if (Elements.isUnresolved(constructor)) return constructor;
    Selector callSelector = mapping.getSelector(node.send);
    if (!callSelector.applies(constructor, compiler)) {
      warnArgumentMismatch(node.send, constructor);
      compiler.backend.registerThrowNoSuchMethod(mapping);
    }

    // [constructor] might be the implementation element
    // and only declaration elements may be registered.
    world.registerStaticUse(constructor.declaration);
    ClassElement cls = constructor.getEnclosingClass();
    InterfaceType type = mapping.getType(node);
    if (node.isConst() && type.containsTypeVariables) {
      compiler.reportErrorCode(node.send.selector,
                               MessageKind.TYPE_VARIABLE_IN_CONSTANT);
    }
    world.registerInstantiatedType(type, mapping);
    if (constructor.isFactoryConstructor() && !type.typeArguments.isEmpty) {
      world.registerFactoryWithTypeArguments(mapping);
    }
    if (cls.isAbstract(compiler)) {
      compiler.backend.registerAbstractClassInstantiation(mapping);
    }

    if (isSymbolConstructor) {
      if (node.isConst()) {
        Node argumentNode = node.send.arguments.head;
        Constant name = compiler.metadataHandler.compileNodeWithDefinitions(
            argumentNode, mapping, isConst: true);
        if (!name.isString()) {
          DartType type = name.computeType(compiler);
          compiler.reportErrorCode(argumentNode, MessageKind.STRING_EXPECTED,
                                   {'type': type});
        } else {
          StringConstant stringConstant = name;
          String nameString = stringConstant.toDartString().slowToString();
          if (validateSymbol(argumentNode, nameString)) {
            world.registerConstSymbol(nameString, mapping);
          }
        }
      } else {
        compiler.reportHint(
            node.newToken, MessageKind.NON_CONST_BLOAT,
            {'name': compiler.symbolClass.name});
        world.registerNewSymbol(mapping);
      }
    }

    return null;
  }

  bool validateSymbol(Node node, String name) {
    if (name.isEmpty) return true;
    if (name.startsWith('_')) {
      compiler.reportErrorCode(node, MessageKind.PRIVATE_IDENTIFIER,
                               {'value': name});
      return false;
    }
    if (!symbolValidationPattern.hasMatch(name)) {
      compiler.reportErrorCode(node, MessageKind.INVALID_SYMBOL,
                               {'value': name});
      return false;
    }
    return true;
  }


  /**
   * Try to resolve the constructor that is referred to by [node].
   * Note: this function may return an ErroneousFunctionElement instead of
   * [null], if there is no corresponding constructor, class or library.
   */
  FunctionElement resolveConstructor(NewExpression node) {
    return node.accept(new ConstructorResolver(compiler, this));
  }

  FunctionElement resolveRedirectingFactory(Return node) {
    return node.accept(new ConstructorResolver(compiler, this));
  }

  DartType resolveTypeRequired(TypeAnnotation node) {
    bool old = typeRequired;
    typeRequired = true;
    DartType result = resolveTypeAnnotation(node);
    typeRequired = old;
    return result;
  }

  DartType resolveTypeAnnotation(TypeAnnotation node) {
    Function report = typeRequired ? error : warning;
    DartType type = typeResolver.resolveTypeAnnotation(
        this, node, onFailure: report);
    if (type == null) return null;
    if (inCheckContext) {
      compiler.enqueuer.resolution.registerIsCheck(type, mapping);
    }
    if (typeRequired || inCheckContext) {
      compiler.backend.registerRequiredType(type, enclosingElement);
    }
    return type;
  }

  visitModifiers(Modifiers node) {
    // TODO(ngeoffray): Implement this.
    unimplemented(node, 'modifiers');
  }

  visitLiteralList(LiteralList node) {
    NodeList arguments = node.typeArguments;
    DartType typeArgument;
    if (arguments != null) {
      Link<Node> nodes = arguments.nodes;
      if (nodes.isEmpty) {
        error(arguments, MessageKind.MISSING_TYPE_ARGUMENT);
      } else {
        typeArgument = resolveTypeRequired(nodes.head);
        for (nodes = nodes.tail; !nodes.isEmpty; nodes = nodes.tail) {
          error(nodes.head, MessageKind.ADDITIONAL_TYPE_ARGUMENT);
          resolveTypeRequired(nodes.head);
        }
      }
    }
    DartType listType;
    if (typeArgument != null) {
      if (node.isConst() && typeArgument.containsTypeVariables) {
        compiler.reportErrorCode(arguments.nodes.head,
            MessageKind.TYPE_VARIABLE_IN_CONSTANT);
      }
      listType = new InterfaceType(compiler.listClass,
                                   new Link<DartType>.fromList([typeArgument]));
    } else {
      compiler.listClass.computeType(compiler);
      listType = compiler.listClass.rawType;
    }
    mapping.setType(node, listType);
    world.registerInstantiatedType(listType, mapping);
    visit(node.elements);
  }

  visitConditional(Conditional node) {
    node.visitChildren(this);
  }

  visitStringInterpolation(StringInterpolation node) {
    world.registerInstantiatedClass(compiler.stringClass, mapping);
    compiler.backend.registerStringInterpolation(mapping);
    node.visitChildren(this);
  }

  visitStringInterpolationPart(StringInterpolationPart node) {
    registerImplicitInvocation(const SourceString('toString'), 0);
    node.visitChildren(this);
  }

  visitBreakStatement(BreakStatement node) {
    TargetElement target;
    if (node.target == null) {
      target = statementScope.currentBreakTarget();
      if (target == null) {
        error(node, MessageKind.NO_BREAK_TARGET);
        return;
      }
      target.isBreakTarget = true;
    } else {
      String labelName = node.target.source.slowToString();
      LabelElement label = statementScope.lookupLabel(labelName);
      if (label == null) {
        error(node.target, MessageKind.UNBOUND_LABEL, {'labelName': labelName});
        return;
      }
      target = label.target;
      if (!target.statement.isValidBreakTarget()) {
        error(node.target, MessageKind.INVALID_BREAK);
        return;
      }
      label.setBreakTarget();
      mapping[node.target] = label;
    }
    if (mapping[node] != null) {
      // TODO(ahe): I'm not sure why this node already has an element
      // that is different from target.  I will talk to Lasse and
      // figure out what is going on.
      mapping.remove(node);
    }
    mapping[node] = target;
  }

  visitContinueStatement(ContinueStatement node) {
    TargetElement target;
    if (node.target == null) {
      target = statementScope.currentContinueTarget();
      if (target == null) {
        error(node, MessageKind.NO_CONTINUE_TARGET);
        return;
      }
      target.isContinueTarget = true;
    } else {
      String labelName = node.target.source.slowToString();
      LabelElement label = statementScope.lookupLabel(labelName);
      if (label == null) {
        error(node.target, MessageKind.UNBOUND_LABEL, {'labelName': labelName});
        return;
      }
      target = label.target;
      if (!target.statement.isValidContinueTarget()) {
        error(node.target, MessageKind.INVALID_CONTINUE);
      }
      label.setContinueTarget();
      mapping[node.target] = label;
    }
    mapping[node] = target;
  }

  registerImplicitInvocation(SourceString name, int arity) {
    Selector selector = new Selector.call(name, null, arity);
    world.registerDynamicInvocation(selector);
  }

  visitForIn(ForIn node) {
    LibraryElement library = enclosingElement.getLibrary();
    mapping.setIteratorSelector(node, compiler.iteratorSelector);
    world.registerDynamicGetter(compiler.iteratorSelector);
    mapping.setCurrentSelector(node, compiler.currentSelector);
    world.registerDynamicGetter(compiler.currentSelector);
    mapping.setMoveNextSelector(node, compiler.moveNextSelector);
    world.registerDynamicInvocation(compiler.moveNextSelector);

    visit(node.expression);
    Scope blockScope = new BlockScope(scope);
    Node declaration = node.declaredIdentifier;
    visitIn(declaration, blockScope);

    Send send = declaration.asSend();
    VariableDefinitions variableDefinitions =
        declaration.asVariableDefinitions();
    Element loopVariable;
    Selector loopVariableSelector;
    if (send != null) {
      loopVariable = mapping[send];
      Identifier identifier = send.selector.asIdentifier();
      if (identifier == null) {
        compiler.reportErrorCode(send.selector, MessageKind.INVALID_FOR_IN);
      } else {
        loopVariableSelector = new Selector.setter(identifier.source, library);
      }
      if (send.receiver != null) {
        compiler.reportErrorCode(send.receiver, MessageKind.INVALID_FOR_IN);
      }
    } else if (variableDefinitions != null) {
      Link<Node> nodes = variableDefinitions.definitions.nodes;
      if (!nodes.tail.isEmpty) {
        compiler.reportErrorCode(nodes.tail.head, MessageKind.INVALID_FOR_IN);
      }
      Node first = nodes.head;
      Identifier identifier = first.asIdentifier();
      if (identifier == null) {
        compiler.reportErrorCode(first, MessageKind.INVALID_FOR_IN);
      } else {
        loopVariableSelector = new Selector.setter(identifier.source, library);
        loopVariable = mapping[identifier];
      }
    } else {
      compiler.reportErrorCode(declaration, MessageKind.INVALID_FOR_IN);
    }
    if (loopVariableSelector != null) {
      mapping.setSelector(declaration, loopVariableSelector);
      registerSend(loopVariableSelector, loopVariable);
    } else {
      // The selector may only be null if we reported an error.
      assert(invariant(declaration, compiler.compilationFailed));
    }
    if (loopVariable != null) {
      // loopVariable may be null if it could not be resolved.
      mapping[declaration] = loopVariable;
    }
    visitLoopBodyIn(node, node.body, blockScope);
  }

  visitLabel(Label node) {
    // Labels are handled by their containing statements/cases.
  }

  visitLabeledStatement(LabeledStatement node) {
    Statement body = node.statement;
    TargetElement targetElement = getOrCreateTargetElement(body);
    Map<String, LabelElement> labelElements = <String, LabelElement>{};
    for (Label label in node.labels) {
      String labelName = label.slowToString();
      if (labelElements.containsKey(labelName)) continue;
      LabelElement element = targetElement.addLabel(label, labelName);
      labelElements[labelName] = element;
    }
    statementScope.enterLabelScope(labelElements);
    visit(node.statement);
    statementScope.exitLabelScope();
    labelElements.forEach((String labelName, LabelElement element) {
      if (element.isTarget) {
        mapping[element.label] = element;
      } else {
        warning(element.label, MessageKind.UNUSED_LABEL,
                {'labelName': labelName});
      }
    });
    if (!targetElement.isTarget && identical(mapping[body], targetElement)) {
      // If the body is itself a break or continue for another target, it
      // might have updated its mapping to the target it actually does target.
      mapping.remove(body);
    }
  }

  visitLiteralMap(LiteralMap node) {
    NodeList arguments = node.typeArguments;
    DartType keyTypeArgument;
    DartType valueTypeArgument;
    if (arguments != null) {
      Link<Node> nodes = arguments.nodes;
      if (nodes.isEmpty) {
        error(arguments, MessageKind.MISSING_TYPE_ARGUMENT);
      } else {
        keyTypeArgument = resolveTypeRequired(nodes.head);
        nodes = nodes.tail;
        if (nodes.isEmpty) {
          error(arguments, MessageKind.MISSING_TYPE_ARGUMENT);
        } else {
          valueTypeArgument = resolveTypeRequired(nodes.head);
          for (nodes = nodes.tail; !nodes.isEmpty; nodes = nodes.tail) {
            error(nodes.head, MessageKind.ADDITIONAL_TYPE_ARGUMENT);
            resolveTypeRequired(nodes.head);
          }
        }
      }
    }
    DartType mapType;
    if (valueTypeArgument != null) {
      mapType = new InterfaceType(compiler.mapClass,
          new Link<DartType>.fromList([keyTypeArgument, valueTypeArgument]));
    } else {
      compiler.mapClass.computeType(compiler);
      mapType = compiler.mapClass.rawType;
    }
    if (node.isConst() && mapType.containsTypeVariables) {
      compiler.reportErrorCode(arguments,
          MessageKind.TYPE_VARIABLE_IN_CONSTANT);
    }
    mapping.setType(node, mapType);
    world.registerInstantiatedClass(compiler.mapClass, mapping);
    if (node.isConst()) {
      compiler.backend.registerConstantMap(mapping);
    }
    node.visitChildren(this);
  }

  visitLiteralMapEntry(LiteralMapEntry node) {
    node.visitChildren(this);
  }

  visitNamedArgument(NamedArgument node) {
    visit(node.expression);
  }

  visitSwitchStatement(SwitchStatement node) {
    node.expression.accept(this);

    TargetElement breakElement = getOrCreateTargetElement(node);
    Map<String, LabelElement> continueLabels = <String, LabelElement>{};
    Link<Node> cases = node.cases.nodes;
    while (!cases.isEmpty) {
      SwitchCase switchCase = cases.head;
      for (Node labelOrCase in switchCase.labelsAndCases) {
        if (labelOrCase is! Label) continue;
        Label label = labelOrCase;
        String labelName = label.slowToString();

        LabelElement existingElement = continueLabels[labelName];
        if (existingElement != null) {
          // It's an error if the same label occurs twice in the same switch.
          warning(label, MessageKind.DUPLICATE_LABEL, {'labelName': labelName});
          error(existingElement.label, MessageKind.EXISTING_LABEL,
                {'labelName': labelName});
        } else {
          // It's only a warning if it shadows another label.
          existingElement = statementScope.lookupLabel(labelName);
          if (existingElement != null) {
            warning(label, MessageKind.DUPLICATE_LABEL,
                    {'labelName': labelName});
            warning(existingElement.label,
                    MessageKind.EXISTING_LABEL, {'labelName': labelName});
          }
        }

        TargetElement targetElement = getOrCreateTargetElement(switchCase);
        LabelElement labelElement = targetElement.addLabel(label, labelName);
        mapping[label] = labelElement;
        continueLabels[labelName] = labelElement;
      }
      cases = cases.tail;
      // Test that only the last case, if any, is a default case.
      if (switchCase.defaultKeyword != null && !cases.isEmpty) {
        error(switchCase, MessageKind.INVALID_CASE_DEFAULT);
      }
    }

    statementScope.enterSwitch(breakElement, continueLabels);
    node.cases.accept(this);
    statementScope.exitSwitch();

    // Clean-up unused labels.
    continueLabels.forEach((String key, LabelElement label) {
      if (!label.isContinueTarget) {
        TargetElement targetElement = label.target;
        SwitchCase switchCase = targetElement.statement;
        mapping.remove(switchCase);
        mapping.remove(label.label);
      }
    });
    // TODO(ngeoffray): We should check here instead of the SSA backend if
    // there might be an error.
    compiler.backend.registerFallThroughError(mapping);
  }

  visitSwitchCase(SwitchCase node) {
    node.labelsAndCases.accept(this);
    visitIn(node.statements, new BlockScope(scope));
  }

  visitCaseMatch(CaseMatch node) {
    visit(node.expression);
  }

  visitTryStatement(TryStatement node) {
    visit(node.tryBlock);
    if (node.catchBlocks.isEmpty && node.finallyBlock == null) {
      // TODO(ngeoffray): The precise location is
      // node.getEndtoken.next. Adjust when issue #1581 is fixed.
      error(node, MessageKind.NO_CATCH_NOR_FINALLY);
    }
    visit(node.catchBlocks);
    visit(node.finallyBlock);
  }

  visitCatchBlock(CatchBlock node) {
    compiler.backend.registerCatchStatement(world, mapping);
    // Check that if catch part is present, then
    // it has one or two formal parameters.
    VariableDefinitions exceptionDefinition;
    VariableDefinitions stackTraceDefinition;
    if (node.formals != null) {
      Link<Node> formalsToProcess = node.formals.nodes;
      if (formalsToProcess.isEmpty) {
        error(node, MessageKind.EMPTY_CATCH_DECLARATION);
      } else {
        exceptionDefinition = formalsToProcess.head.asVariableDefinitions();
        formalsToProcess = formalsToProcess.tail;
        if (!formalsToProcess.isEmpty) {
          stackTraceDefinition = formalsToProcess.head.asVariableDefinitions();
          formalsToProcess = formalsToProcess.tail;
          if (!formalsToProcess.isEmpty) {
            for (Node extra in formalsToProcess) {
              error(extra, MessageKind.EXTRA_CATCH_DECLARATION);
            }
          }
          compiler.backend.registerStackTraceInCatch(mapping);
        }
      }

      // Check that the formals aren't optional and that they have no
      // modifiers or type.
      for (Link<Node> link = node.formals.nodes;
           !link.isEmpty;
           link = link.tail) {
        // If the formal parameter is a node list, it means that it is a
        // sequence of optional parameters.
        NodeList nodeList = link.head.asNodeList();
        if (nodeList != null) {
          error(nodeList, MessageKind.OPTIONAL_PARAMETER_IN_CATCH);
        } else {
          VariableDefinitions declaration = link.head;
          for (Node modifier in declaration.modifiers.nodes) {
            error(modifier, MessageKind.PARAMETER_WITH_MODIFIER_IN_CATCH);
          }
          TypeAnnotation type = declaration.type;
          if (type != null) {
            error(type, MessageKind.PARAMETER_WITH_TYPE_IN_CATCH);
          }
        }
      }
    }

    Scope blockScope = new BlockScope(scope);
    var wasTypeRequired = typeRequired;
    typeRequired = true;
    doInCheckContext(() => visitIn(node.type, blockScope));
    typeRequired = wasTypeRequired;
    visitIn(node.formals, blockScope);
    var oldInCatchBlock = inCatchBlock;
    inCatchBlock = true;
    visitIn(node.block, blockScope);
    inCatchBlock = oldInCatchBlock;

    if (node.type != null && exceptionDefinition != null) {
      DartType exceptionType = mapping.getType(node.type);
      Node exceptionVariable = exceptionDefinition.definitions.nodes.head;
      VariableElementX exceptionElement = mapping[exceptionVariable];
      exceptionElement.variables.type = exceptionType;
    }
    if (stackTraceDefinition != null) {
      Node stackTraceVariable = stackTraceDefinition.definitions.nodes.head;
      VariableElementX stackTraceElement = mapping[stackTraceVariable];
      world.registerInstantiatedClass(compiler.stackTraceClass, mapping);
      stackTraceElement.variables.type = compiler.stackTraceClass.rawType;
    }
  }

  visitTypedef(Typedef node) {
    unimplemented(node, 'typedef');
  }
}

class TypeDefinitionVisitor extends MappingVisitor<DartType> {
  Scope scope;
  final TypeDeclarationElement enclosingElement;
  TypeDeclarationElement get element => enclosingElement;

  TypeDefinitionVisitor(Compiler compiler,
                        TypeDeclarationElement element,
                        TreeElementMapping mapping)
      : this.enclosingElement = element,
        scope = Scope.buildEnclosingScope(element),
        super(compiler, mapping);

  void resolveTypeVariableBounds(NodeList node) {
    if (node == null) return;

    var nameSet = new Set<SourceString>();
    // Resolve the bounds of type variables.
    Link<DartType> typeLink = element.typeVariables;
    Link<Node> nodeLink = node.nodes;
    while (!nodeLink.isEmpty) {
      TypeVariableType typeVariable = typeLink.head;
      SourceString typeName = typeVariable.name;
      TypeVariable typeNode = nodeLink.head;
      if (nameSet.contains(typeName)) {
        error(typeNode, MessageKind.DUPLICATE_TYPE_VARIABLE_NAME,
              {'typeVariableName': typeName});
      }
      nameSet.add(typeName);

      TypeVariableElement variableElement = typeVariable.element;
      if (typeNode.bound != null) {
        DartType boundType = typeResolver.resolveTypeAnnotation(
            this, typeNode.bound, onFailure: warning);
        variableElement.bound = boundType;

        void checkTypeVariableBound() {
          Link<TypeVariableElement> seenTypeVariables =
              const Link<TypeVariableElement>();
          seenTypeVariables = seenTypeVariables.prepend(variableElement);
          DartType bound = boundType;
          while (bound.element.isTypeVariable()) {
            TypeVariableElement element = bound.element;
            if (seenTypeVariables.contains(element)) {
              if (identical(element, variableElement)) {
                // Only report an error on the checked type variable to avoid
                // generating multiple errors for the same cyclicity.
                warning(typeNode.name, MessageKind.CYCLIC_TYPE_VARIABLE,
                    {'typeVariableName': variableElement.name});
              }
              break;
            }
            seenTypeVariables = seenTypeVariables.prepend(element);
            bound = element.bound;
          }
        }
        compiler.enqueuer.resolution.addPostProcessAction(
            element, checkTypeVariableBound);
      } else {
        variableElement.bound = compiler.objectClass.computeType(compiler);
      }
      nodeLink = nodeLink.tail;
      typeLink = typeLink.tail;
    }
    assert(typeLink.isEmpty);
  }
}

class TypedefResolverVisitor extends TypeDefinitionVisitor {
  TypedefElement get element => enclosingElement;

  TypedefResolverVisitor(Compiler compiler,
                         TypedefElement typedefElement,
                         TreeElementMapping mapping)
      : super(compiler, typedefElement, mapping);

  visitTypedef(Typedef node) {
    TypedefType type = element.computeType(compiler);
    scope = new TypeDeclarationScope(scope, element);
    resolveTypeVariableBounds(node.typeParameters);

    element.functionSignature = SignatureResolver.analyze(
        compiler, node.formals, node.returnType, element);

    element.alias = compiler.computeFunctionType(
        element, element.functionSignature);

    // TODO(johnniwinther): Check for cyclic references in the typedef alias.
  }
}

/**
 * The implementation of [ResolverTask.resolveClass].
 *
 * This visitor has to be extra careful as it is building the basic
 * element information, and cannot safely look at other elements as
 * this may lead to cycles.
 *
 * This visitor can assume that the supertypes have already been
 * resolved, but it cannot call [ResolverTask.resolveClass] directly
 * or indirectly (through [ClassElement.ensureResolved]) for any other
 * types.
 */
class ClassResolverVisitor extends TypeDefinitionVisitor {
  ClassElement get element => enclosingElement;

  ClassResolverVisitor(Compiler compiler,
                       ClassElement classElement,
                       TreeElementMapping mapping)
    : super(compiler, classElement, mapping);

  DartType visitClassNode(ClassNode node) {
    compiler.ensure(element != null);
    compiler.ensure(element.resolutionState == STATE_STARTED);

    InterfaceType type = element.computeType(compiler);
    scope = new TypeDeclarationScope(scope, element);
    // TODO(ahe): It is not safe to call resolveTypeVariableBounds yet.
    // As a side-effect, this may get us back here trying to
    // resolve this class again.
    resolveTypeVariableBounds(node.typeParameters);

    // Setup the supertype for the element (if there is a cycle in the
    // class hierarchy, it has already been set to Object).
    if (element.supertype == null && node.superclass != null) {
      MixinApplication superMixin = node.superclass.asMixinApplication();
      if (superMixin != null) {
        DartType supertype = resolveSupertype(element, superMixin.superclass);
        Link<Node> link = superMixin.mixins.nodes;
        while (!link.isEmpty) {
          supertype = applyMixin(supertype, resolveType(link.head));
          link = link.tail;
        }
        element.supertype = supertype;
      } else {
        element.supertype = resolveSupertype(element, node.superclass);
      }
    }
    // If the super type isn't specified, we provide a default.  The language
    // specifies [Object] but the backend can pick a specific 'implementation'
    // of Object - the JavaScript backend chooses between Object and
    // Interceptor.
    if (element.supertype == null) {
      ClassElement superElement = compiler.backend.defaultSuperclass(element);
      // Avoid making the superclass (usually Object) extend itself.
      if (element != superElement) {
        if (superElement == null) {
          compiler.internalError(
              "Cannot resolve default superclass for $element",
              node: node);
        } else {
          superElement.ensureResolved(compiler);
        }
        element.supertype = superElement.computeType(compiler);
      }
    }

    assert(element.interfaces == null);
    element.interfaces = resolveInterfaces(node.interfaces, node.superclass);
    calculateAllSupertypes(element);

    element.addDefaultConstructorIfNeeded(compiler);
    return element.computeType(compiler);
  }

  DartType visitNamedMixinApplication(NamedMixinApplication node) {
    compiler.ensure(element != null);
    compiler.ensure(element.resolutionState == STATE_STARTED);

    InterfaceType type = element.computeType(compiler);
    scope = new TypeDeclarationScope(scope, element);
    resolveTypeVariableBounds(node.typeParameters);

    // Generate anonymous mixin application elements for the
    // intermediate mixin applications (excluding the last).
    DartType supertype = resolveSupertype(element, node.superclass);
    Link<Node> link = node.mixins.nodes;
    while (!link.tail.isEmpty) {
      supertype = applyMixin(supertype, resolveType(link.head));
      link = link.tail;
    }
    doApplyMixinTo(element, supertype, resolveType(link.head));
    return element.computeType(compiler);
  }

  DartType applyMixin(DartType supertype, DartType mixinType) {
    String superName = supertype.name.slowToString();
    String mixinName = mixinType.name.slowToString();
    ClassElement mixinApplication = new MixinApplicationElementX(
        new SourceString("${superName}_${mixinName}"),
        element.getCompilationUnit(),
        compiler.getNextFreeClassId(),
        element.parseNode(compiler),
        Modifiers.EMPTY);  // TODO(kasperl): Should this be abstract?
    doApplyMixinTo(mixinApplication, supertype, mixinType);
    mixinApplication.resolutionState = STATE_DONE;
    mixinApplication.supertypeLoadState = STATE_DONE;
    return mixinApplication.computeType(compiler);
  }

  bool isDefaultConstructor(FunctionElement constructor) {
    return constructor.name == const SourceString('') &&
        constructor.computeSignature(compiler).parameterCount == 0;
  }

  FunctionElement createForwardingConstructor(FunctionElement constructor,
                                              ClassElement target) {
    return new SynthesizedConstructorElementX.forwarding(constructor.name,
                                                         constructor,
                                                         target);
  }

  void doApplyMixinTo(MixinApplicationElement mixinApplication,
                      DartType supertype,
                      DartType mixinType) {
    Node node = mixinApplication.parseNode(compiler);

    if (mixinApplication.supertype != null) {
      // [supertype] is not null if there was a cycle.
      assert(invariant(node, compiler.compilationFailed));
      supertype = mixinApplication.supertype;
      assert(invariant(node, supertype.element == compiler.objectClass));
    } else {
      mixinApplication.supertype = supertype;
    }

    // Named mixin application may have an 'implements' clause.
    NamedMixinApplication namedMixinApplication =
        node.asNamedMixinApplication();
    Link<DartType> interfaces = (namedMixinApplication != null)
        ? resolveInterfaces(namedMixinApplication.interfaces,
                            namedMixinApplication.superclass)
        : const Link<DartType>();

    // The class that is the result of a mixin application implements
    // the interface of the class that was mixed in so always prepend
    // that to the interface list.
    interfaces = interfaces.prepend(mixinType);
    assert(mixinApplication.interfaces == null);
    mixinApplication.interfaces = interfaces;

    assert(mixinApplication.mixin == null);
    mixinApplication.mixin = resolveMixinFor(mixinApplication, mixinType);

    // Create forwarding constructors for constructor defined in the superclass
    // because they are now hidden by the mixin application.
    ClassElement superclass = supertype.element;
    superclass.forEachLocalMember((Element member) {
      if (!member.isConstructor()) return;
      if (member.isSynthesized && !member.isForwardingConstructor) return;
      if (isDefaultConstructor(member)) return;
      assert(invariant(node, !member.isFactoryConstructor(),
             message: 'mixins cannot have factory constructors'));
      // Skip forwarding constructors and use their target.
      FunctionElement constructor =
          member.isForwardingConstructor ? member.targetConstructor : member;
      assert(invariant(node, !constructor.isForwardingConstructor));
      FunctionElement forwarder =
          createForwardingConstructor(constructor, mixinApplication);
      mixinApplication.addConstructor(forwarder);
    });
    mixinApplication.addDefaultConstructorIfNeeded(compiler);
    calculateAllSupertypes(mixinApplication);
  }

  ClassElement resolveMixinFor(MixinApplicationElement mixinApplication,
                               DartType mixinType) {
    ClassElement mixin = mixinType.element;
    mixin.ensureResolved(compiler);

    // Check for cycles in the mixin chain.
    ClassElement previous = mixinApplication;  // For better error messages.
    ClassElement current = mixin;
    while (current != null && current.isMixinApplication) {
      MixinApplicationElement currentMixinApplication = current;
      if (currentMixinApplication == mixinApplication) {
        compiler.reportErrorCode(
            mixinApplication, MessageKind.ILLEGAL_MIXIN_CYCLE,
            {'mixinName1': current.name, 'mixinName2': previous.name});
        // We have found a cycle in the mixin chain. Return null as
        // the mixin for this application to avoid getting into
        // infinite recursion when traversing members.
        return null;
      }
      previous = current;
      current = currentMixinApplication.mixin;
    }
    compiler.world.registerMixinUse(mixinApplication, mixin);
    return mixin;
  }

  DartType resolveType(TypeAnnotation node) {
    // TODO(johnniwinther): Report errors/warnings on resolution failures.
    return typeResolver.resolveTypeAnnotation(this, node);
  }

  DartType resolveSupertype(ClassElement cls, TypeAnnotation superclass) {
    DartType supertype = typeResolver.resolveTypeAnnotation(
        this, superclass, onFailure: error);
    if (supertype != null) {
      if (identical(supertype.kind, TypeKind.MALFORMED_TYPE)) {
        // Error has already been reported.
        return null;
      } else if (!identical(supertype.kind, TypeKind.INTERFACE)) {
        // TODO(johnniwinther): Handle dynamic.
        error(superclass.typeName, MessageKind.CLASS_NAME_EXPECTED);
        return null;
      } else if (isBlackListed(supertype)) {
        error(superclass, MessageKind.CANNOT_EXTEND, {'type': supertype});
        return null;
      }
    }
    return supertype;
  }

  Link<DartType> resolveInterfaces(NodeList interfaces, Node superclass) {
    Link<DartType> result = const Link<DartType>();
    if (interfaces == null) return result;
    for (Link<Node> link = interfaces.nodes; !link.isEmpty; link = link.tail) {
      DartType interfaceType = typeResolver.resolveTypeAnnotation(
          this, link.head, onFailure: error);
      if (interfaceType != null) {
        if (identical(interfaceType.kind, TypeKind.MALFORMED_TYPE)) {
          // Error has already been reported.
        } else if (!identical(interfaceType.kind, TypeKind.INTERFACE)) {
          // TODO(johnniwinther): Handle dynamic.
          TypeAnnotation typeAnnotation = link.head;
          error(typeAnnotation.typeName, MessageKind.CLASS_NAME_EXPECTED);
        } else {
          if (interfaceType == element.supertype) {
            compiler.reportErrorCode(
                superclass,
                MessageKind.DUPLICATE_EXTENDS_IMPLEMENTS,
                {'type': interfaceType});
            compiler.reportErrorCode(
                link.head,
                MessageKind.DUPLICATE_EXTENDS_IMPLEMENTS,
                {'type': interfaceType});
          }
          if (result.contains(interfaceType)) {
            compiler.reportErrorCode(
                link.head,
                MessageKind.DUPLICATE_IMPLEMENTS,
                {'type': interfaceType});
          }
          result = result.prepend(interfaceType);
          if (isBlackListed(interfaceType)) {
            error(link.head, MessageKind.CANNOT_IMPLEMENT,
                  {'type': interfaceType});
          }
        }
      }
    }
    return result;
  }

  void calculateAllSupertypes(ClassElement cls) {
    // TODO(karlklose): Check if type arguments match, if a class
    // element occurs more than once in the supertypes.
    if (cls.allSupertypes != null) return;
    final DartType supertype = cls.supertype;
    if (supertype != null) {
      var allSupertypes = new LinkBuilder<DartType>();
      addAllSupertypes(allSupertypes, supertype);
      for (Link<DartType> interfaces = cls.interfaces;
           !interfaces.isEmpty;
           interfaces = interfaces.tail) {
        addAllSupertypes(allSupertypes, interfaces.head);
      }
      cls.allSupertypes = allSupertypes.toLink();
    } else {
      assert(identical(cls, compiler.objectClass));
      cls.allSupertypes = const Link<DartType>();
    }
 }

  /**
   * Adds [type] and all supertypes of [type] to [builder] while substituting
   * type variables.
   */
  void addAllSupertypes(LinkBuilder<DartType> builder, InterfaceType type) {
    builder.addLast(type);
    Link<DartType> typeArguments = type.typeArguments;
    ClassElement classElement = type.element;
    Link<DartType> typeVariables = classElement.typeVariables;
    Link<DartType> supertypes = classElement.allSupertypes;
    assert(invariant(element, supertypes != null,
        message: "Supertypes not computed on $classElement "
                 "during resolution of $element"));
    while (!supertypes.isEmpty) {
      DartType supertype = supertypes.head;
      builder.addLast(supertype.subst(typeArguments, typeVariables));
      supertypes = supertypes.tail;
    }
  }

  isBlackListed(DartType type) {
    LibraryElement lib = element.getLibrary();
    return
      !identical(lib, compiler.coreLibrary) &&
      !identical(lib, compiler.jsHelperLibrary) &&
      !identical(lib, compiler.interceptorsLibrary) &&
      (identical(type.element, compiler.dynamicClass) ||
       identical(type.element, compiler.boolClass) ||
       identical(type.element, compiler.numClass) ||
       identical(type.element, compiler.intClass) ||
       identical(type.element, compiler.doubleClass) ||
       identical(type.element, compiler.stringClass) ||
       identical(type.element, compiler.nullClass) ||
       identical(type.element, compiler.functionClass));
  }
}

class ClassSupertypeResolver extends CommonResolverVisitor {
  Scope context;
  ClassElement classElement;

  ClassSupertypeResolver(Compiler compiler, ClassElement cls)
    : context = Scope.buildEnclosingScope(cls),
      this.classElement = cls,
      super(compiler);

  void loadSupertype(ClassElement element, Node from) {
    compiler.resolver.loadSupertypes(element, from);
    element.ensureResolved(compiler);
  }

  void visitNodeList(NodeList node) {
    if (node != null) {
      for (Link<Node> link = node.nodes; !link.isEmpty; link = link.tail) {
        link.head.accept(this);
      }
    }
  }

  void visitClassNode(ClassNode node) {
    if (node.superclass == null) {
      if (!identical(classElement, compiler.objectClass)) {
        loadSupertype(compiler.objectClass, node);
      }
    } else {
      node.superclass.accept(this);
    }
    visitNodeList(node.interfaces);
  }

  void visitMixinApplication(MixinApplication node) {
    node.superclass.accept(this);
    visitNodeList(node.mixins);
  }

  void visitNamedMixinApplication(NamedMixinApplication node) {
    node.superclass.accept(this);
    visitNodeList(node.mixins);
    visitNodeList(node.interfaces);
  }

  void visitTypeAnnotation(TypeAnnotation node) {
    node.typeName.accept(this);
  }

  void visitIdentifier(Identifier node) {
    Element element = context.lookup(node.source);
    if (element == null) {
      error(node, MessageKind.CANNOT_RESOLVE_TYPE, {'typeName': node});
    } else if (!element.impliesType()) {
      error(node, MessageKind.NOT_A_TYPE, {'node': node});
    } else {
      if (element.isClass()) {
        loadSupertype(element, node);
      } else {
        compiler.reportErrorCode(node, MessageKind.CLASS_NAME_EXPECTED);
      }
    }
  }

  void visitSend(Send node) {
    Identifier prefix = node.receiver.asIdentifier();
    if (prefix == null) {
      error(node.receiver, MessageKind.NOT_A_PREFIX, {'node': node.receiver});
      return;
    }
    Element element = context.lookup(prefix.source);
    if (element == null || !identical(element.kind, ElementKind.PREFIX)) {
      error(node.receiver, MessageKind.NOT_A_PREFIX, {'node': node.receiver});
      return;
    }
    PrefixElement prefixElement = element;
    Identifier selector = node.selector.asIdentifier();
    var e = prefixElement.lookupLocalMember(selector.source);
    if (e == null || !e.impliesType()) {
      error(node.selector, MessageKind.CANNOT_RESOLVE_TYPE,
            {'typeName': node.selector});
      return;
    }
    loadSupertype(e, node);
  }
}

class VariableDefinitionsVisitor extends CommonResolverVisitor<SourceString> {
  VariableDefinitions definitions;
  ResolverVisitor resolver;
  ElementKind kind;
  VariableListElement variables;

  VariableDefinitionsVisitor(Compiler compiler,
                             this.definitions, this.resolver, this.kind)
      : super(compiler) {
    variables = new VariableListElementX.node(
        definitions, ElementKind.VARIABLE_LIST, resolver.enclosingElement);
  }

  SourceString visitSendSet(SendSet node) {
    assert(node.arguments.tail.isEmpty); // Sanity check
    resolver.visit(node.arguments.head);
    return visit(node.selector);
  }

  SourceString visitIdentifier(Identifier node) {
    // The variable is initialized to null.
    resolver.world.registerInstantiatedClass(compiler.nullClass,
                                             resolver.mapping);
    return node.source;
  }

  visitNodeList(NodeList node) {
    for (Link<Node> link = node.nodes; !link.isEmpty; link = link.tail) {
      SourceString name = visit(link.head);
      VariableElement element =
          new VariableElementX(name, variables, kind, link.head);
      resolver.defineElement(link.head, element);
    }
  }
}

/**
 * [SignatureResolver] resolves function signatures.
 */
class SignatureResolver extends CommonResolverVisitor<Element> {
  final Element enclosingElement;
  Link<Element> optionalParameters = const Link<Element>();
  int optionalParameterCount = 0;
  bool optionalParametersAreNamed = false;
  VariableDefinitions currentDefinitions;

  SignatureResolver(Compiler compiler, this.enclosingElement) : super(compiler);

  Element visitNodeList(NodeList node) {
    // This must be a list of optional arguments.
    String value = node.beginToken.stringValue;
    if ((!identical(value, '[')) && (!identical(value, '{'))) {
      internalError(node, "expected optional parameters");
    }
    optionalParametersAreNamed = (identical(value, '{'));
    LinkBuilder<Element> elements = analyzeNodes(node.nodes);
    optionalParameterCount = elements.length;
    optionalParameters = elements.toLink();
    return null;
  }

  Element visitVariableDefinitions(VariableDefinitions node) {
    Link<Node> definitions = node.definitions.nodes;
    if (definitions.isEmpty) {
      cancel(node, 'internal error: no parameter definition');
      return null;
    }
    if (!definitions.tail.isEmpty) {
      cancel(definitions.tail.head, 'internal error: extra definition');
      return null;
    }
    Node definition = definitions.head;
    if (definition is NodeList) {
      cancel(node, 'optional parameters are not implemented');
    }

    if (currentDefinitions != null) {
      cancel(node, 'function type parameters not supported');
    }
    currentDefinitions = node;
    Element element = definition.accept(this);
    currentDefinitions = null;
    return element;
  }

  Element visitIdentifier(Identifier node) {
    Element variables = new VariableListElementX.node(currentDefinitions,
        ElementKind.VARIABLE_LIST, enclosingElement);
    // Ensure a parameter is not typed 'void'.
    variables.computeType(compiler);
    return new VariableElementX(node.source, variables,
        ElementKind.PARAMETER, node);
  }

  SourceString getParameterName(Send node) {
    var identifier = node.selector.asIdentifier();
    if (identifier != null) {
      // Normal parameter: [:Type name:].
      return identifier.source;
    } else {
      // Function type parameter: [:void name(DartType arg):].
      var functionExpression = node.selector.asFunctionExpression();
      if (functionExpression != null &&
          functionExpression.name.asIdentifier() != null) {
        return functionExpression.name.asIdentifier().source;
      } else {
        cancel(node,
            'internal error: unimplemented receiver on parameter send');
      }
    }
  }

  // The only valid [Send] can be in constructors and must be of the form
  // [:this.x:] (where [:x:] represents an instance field).
  FieldParameterElement visitSend(Send node) {
    FieldParameterElement element;
    if (node.receiver.asIdentifier() == null ||
        !node.receiver.asIdentifier().isThis()) {
      error(node, MessageKind.INVALID_PARAMETER);
    } else if (!identical(enclosingElement.kind,
                          ElementKind.GENERATIVE_CONSTRUCTOR)) {
      error(node, MessageKind.INITIALIZING_FORMAL_NOT_ALLOWED);
    } else {
      SourceString name = getParameterName(node);
      Element fieldElement = currentClass.lookupLocalMember(name);
      if (fieldElement == null ||
          !identical(fieldElement.kind, ElementKind.FIELD)) {
        error(node, MessageKind.NOT_A_FIELD, {'fieldName': name});
      } else if (!fieldElement.isInstanceMember()) {
        error(node, MessageKind.NOT_INSTANCE_FIELD, {'fieldName': name});
      }
      Element variables = new VariableListElementX.node(currentDefinitions,
          ElementKind.VARIABLE_LIST, enclosingElement);
      element = new FieldParameterElementX(name, fieldElement, variables, node);
    }
    return element;
  }

  Element visitSendSet(SendSet node) {
    Element element;
    if (node.receiver != null) {
      element = visitSend(node);
    } else if (node.selector.asIdentifier() != null ||
               node.selector.asFunctionExpression() != null) {
      Element variables = new VariableListElementX.node(currentDefinitions,
          ElementKind.VARIABLE_LIST, enclosingElement);
      SourceString source = node.selector.asIdentifier() != null ?
          node.selector.asIdentifier().source :
          node.selector.asFunctionExpression().name.asIdentifier().source;
      element = new VariableElementX(source, variables,
          ElementKind.PARAMETER, node);
    }
    // Visit the value. The compile time constant handler will
    // make sure it's a compile time constant.
    resolveExpression(node.arguments.head);
    return element;
  }

  Element visitFunctionExpression(FunctionExpression node) {
    // This is a function typed parameter.
    // TODO(ahe): Resolve the function type.
    return visit(node.name);
  }

  LinkBuilder<Element> analyzeNodes(Link<Node> link) {
    LinkBuilder<Element> elements = new LinkBuilder<Element>();
    for (; !link.isEmpty; link = link.tail) {
      Element element = link.head.accept(this);
      if (element != null) {
        elements.addLast(element);
      } else {
        // If parameter is null, the current node should be the last,
        // and a list of optional named parameters.
        if (!link.tail.isEmpty || (link.head is !NodeList)) {
          internalError(link.head, "expected optional parameters");
        }
      }
    }
    return elements;
  }

  /**
   * Resolves formal parameters and return type to a [FunctionSignature].
   */
  static FunctionSignature analyze(Compiler compiler,
                                   NodeList formalParameters,
                                   Node returnNode,
                                   Element element) {
    SignatureResolver visitor = new SignatureResolver(compiler, element);
    Link<Element> parameters = const Link<Element>();
    int requiredParameterCount = 0;
    if (formalParameters == null) {
      if (!element.isGetter()) {
        compiler.reportErrorCode(element, MessageKind.MISSING_FORMALS);
      }
    } else {
      if (element.isGetter()) {
        if (!identical(formalParameters.getEndToken().next.stringValue,
                       // TODO(ahe): Remove the check for native keyword.
                       'native')) {
          if (compiler.rejectDeprecatedFeatures &&
              // TODO(ahe): Remove isPlatformLibrary check.
              !element.getLibrary().isPlatformLibrary) {
            compiler.reportErrorCode(formalParameters,
                                     MessageKind.EXTRA_FORMALS);
          } else {
            compiler.onDeprecatedFeature(formalParameters, 'getter parameters');
          }
        }
      }
      LinkBuilder<Element> parametersBuilder =
        visitor.analyzeNodes(formalParameters.nodes);
      requiredParameterCount  = parametersBuilder.length;
      parameters = parametersBuilder.toLink();
    }
    DartType returnType;
    if (element.isFactoryConstructor()) {
      returnType = element.getEnclosingClass().computeType(compiler);
      // Because there is no type annotation for the return type of
      // this element, we explicitly add one.
      if (compiler.enableTypeAssertions) {
        compiler.enqueuer.resolution.registerIsCheck(
            returnType, new TreeElementMapping(element));
      }
    } else {
      returnType = compiler.resolveReturnType(element, returnNode);
    }

    if (element.isSetter() && (requiredParameterCount != 1 ||
                               visitor.optionalParameterCount != 0)) {
      // If there are no formal parameters, we already reported an error above.
      if (formalParameters != null) {
        compiler.reportErrorCode(formalParameters,
                                 MessageKind.ILLEGAL_SETTER_FORMALS);
      }
    }
    if (element.isGetter() && (requiredParameterCount != 0
                               || visitor.optionalParameterCount != 0)) {
      compiler.reportErrorCode(formalParameters, MessageKind.EXTRA_FORMALS);
    }
    return new FunctionSignatureX(parameters,
                                  visitor.optionalParameters,
                                  requiredParameterCount,
                                  visitor.optionalParameterCount,
                                  visitor.optionalParametersAreNamed,
                                  returnType);
  }

  // TODO(ahe): This is temporary.
  void resolveExpression(Node node) {
    if (node == null) return;
    node.accept(new ResolverVisitor(compiler, enclosingElement,
                                    new TreeElementMapping(enclosingElement)));
  }

  // TODO(ahe): This is temporary.
  ClassElement get currentClass {
    return enclosingElement.isMember()
      ? enclosingElement.getEnclosingClass() : null;
  }
}

class ConstructorResolver extends CommonResolverVisitor<Element> {
  final ResolverVisitor resolver;
  bool inConstContext = false;
  DartType type;

  ConstructorResolver(Compiler compiler, this.resolver) : super(compiler);

  visitNode(Node node) {
    throw 'not supported';
  }

  failOrReturnErroneousElement(Element enclosing, Node diagnosticNode,
                               SourceString targetName, MessageKind kind,
                               Map arguments) {
    if (kind == MessageKind.CANNOT_FIND_CONSTRUCTOR) {
      compiler.backend.registerThrowNoSuchMethod(resolver.mapping);
    } else {
      compiler.backend.registerThrowRuntimeError(resolver.mapping);
    }
    if (inConstContext) {
      error(diagnosticNode, kind, arguments);
    } else {
      ResolutionWarning warning  = new ResolutionWarning(kind, arguments);
      compiler.reportWarning(diagnosticNode, warning);
      return new ErroneousElementX(kind, arguments, targetName, enclosing);
    }
  }

  Selector createConstructorSelector(SourceString constructorName) {
    return constructorName == const SourceString('')
        ? new Selector.callDefaultConstructor(
            resolver.enclosingElement.getLibrary())
        : new Selector.callConstructor(
            constructorName,
            resolver.enclosingElement.getLibrary());
  }

  // TODO(ngeoffray): method named lookup should not report errors.
  FunctionElement lookupConstructor(ClassElement cls,
                                    Node diagnosticNode,
                                    SourceString constructorName) {
    cls.ensureResolved(compiler);
    Selector selector = createConstructorSelector(constructorName);
    Element result = cls.lookupConstructor(selector);
    if (result == null) {
      String fullConstructorName =
          resolver.compiler.resolver.constructorNameForDiagnostics(
              cls.name,
              constructorName);
      return failOrReturnErroneousElement(
          cls,
          diagnosticNode,
          new SourceString(fullConstructorName),
          MessageKind.CANNOT_FIND_CONSTRUCTOR,
          {'constructorName': fullConstructorName});
    } else if (inConstContext && !result.modifiers.isConst()) {
      error(diagnosticNode, MessageKind.CONSTRUCTOR_IS_NOT_CONST);
    }
    return result;
  }

  visitNewExpression(NewExpression node) {
    inConstContext = node.isConst();
    Node selector = node.send.selector;
    Element e = visit(selector);
    return finishConstructorReference(e, node.send.selector, node);
  }

  /// Finishes resolution of a constructor reference and records the
  /// type of the constructed instance on [expression].
  FunctionElement finishConstructorReference(Element e,
                                             Node diagnosticNode,
                                             Node expression) {
    // Find the unnamed constructor if the reference resolved to a
    // class.
    if (!Elements.isUnresolved(e) && e.isClass()) {
      ClassElement cls = e;
      cls.ensureResolved(compiler);
      // The unnamed constructor may not exist, so [e] may become unresolved.
      e = lookupConstructor(cls, diagnosticNode, const SourceString(''));
    }
    if (type == null) {
      if (Elements.isUnresolved(e)) {
        type = compiler.dynamicClass.computeType(compiler);
      } else {
        type = e.getEnclosingClass().computeType(compiler).asRaw();
      }
    }
    resolver.mapping.setType(expression, type);
    return e;
  }

  visitTypeAnnotation(TypeAnnotation node) {
    assert(invariant(node, type == null));
    type = resolver.resolveTypeRequired(node);
    return resolver.mapping[node];
  }

  visitSend(Send node) {
    Element e = visit(node.receiver);
    if (Elements.isUnresolved(e)) return e;
    Identifier name = node.selector.asIdentifier();
    if (name == null) internalError(node.selector, 'unexpected node');

    if (identical(e.kind, ElementKind.CLASS)) {
      ClassElement cls = e;
      cls.ensureResolved(compiler);
      return lookupConstructor(cls, name, name.source);
    } else if (identical(e.kind, ElementKind.PREFIX)) {
      PrefixElement prefix = e;
      e = prefix.lookupLocalMember(name.source);
      if (e == null) {
        return failOrReturnErroneousElement(resolver.enclosingElement, name,
                                            name.source,
                                            MessageKind.CANNOT_RESOLVE,
                                            {'name': name});
      } else if (!identical(e.kind, ElementKind.CLASS)) {
        error(node, MessageKind.NOT_A_TYPE, {'node': name});
      }
    } else {
      internalError(node.receiver, 'unexpected element $e');
    }
    return e;
  }

  Element visitIdentifier(Identifier node) {
    SourceString name = node.source;
    Element e = resolver.lookup(node, name);
    // TODO(johnniwinther): Change errors to warnings, cf. 11.11.1.
    if (e == null) {
      return failOrReturnErroneousElement(resolver.enclosingElement, node, name,
                                          MessageKind.CANNOT_RESOLVE,
                                          {'name': name});
    } else if (e.isErroneous()) {
      return e;
    } else if (identical(e.kind, ElementKind.TYPEDEF)) {
      error(node, MessageKind.CANNOT_INSTANTIATE_TYPEDEF,
            {'typedefName': name});
    } else if (identical(e.kind, ElementKind.TYPE_VARIABLE)) {
      error(node, MessageKind.CANNOT_INSTANTIATE_TYPE_VARIABLE,
            {'typeVariableName': name});
    } else if (!identical(e.kind, ElementKind.CLASS)
        && !identical(e.kind, ElementKind.PREFIX)) {
      error(node, MessageKind.NOT_A_TYPE, {'node': name});
    }
    return e;
  }

  /// Assumed to be called by [resolveRedirectingFactory].
  Element visitReturn(Return node) {
    Node expression = node.expression;
    return finishConstructorReference(visit(expression),
                                      expression, expression);
  }
}
