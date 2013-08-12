// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of ssa;

class BailoutInfo {
  int instructionId;
  int bailoutId;
  BailoutInfo(this.instructionId, this.bailoutId);
}

/**
 * Keeps track of the execution environment for instructions. An
 * execution environment contains the SSA instructions that are live.
 */
class Environment {
  final Set<HInstruction> lives;
  final List<HBasicBlock> loopMarkers;
  Environment() : lives = new Set<HInstruction>(),
                  loopMarkers = new List<HBasicBlock>();
  Environment.from(Environment other)
    : lives = new Set<HInstruction>.from(other.lives),
      loopMarkers = new List<HBasicBlock>.from(other.loopMarkers);

  void remove(HInstruction instruction) {
    lives.remove(instruction);
  }

  void add(HInstruction instruction) {
    // If the instruction is a check, we add its checked input
    // instead. This allows sharing the same environment between
    // different type guards.
    //
    // Also, we don't need to add code motion invariant instructions
    // in the live set (because we generate them at use-site), except
    // for parameters that are not 'this', which is always passed as
    // the receiver.
    if (instruction is HCheck) {
      HCheck check = instruction;
      add(check.checkedInput);
    } else if (!instruction.isCodeMotionInvariant()
               || (instruction is HParameterValue && instruction is !HThis)) {
      lives.add(instruction);
    } else {
      for (int i = 0, len = instruction.inputs.length; i < len; i++) {
        add(instruction.inputs[i]);
      }
    }
  }

  void addAll(Environment other) {
    lives.addAll(other.lives);
  }

  bool get isEmpty => lives.isEmpty && loopMarkers.isEmpty;
}


/**
 * Visits the graph in dominator order and inserts TypeGuards in places where
 * we consider the guard to be of value. This phase also does type
 * propagation to help find valuable type guards.
 */
class SsaTypeGuardInserter extends SsaNonSpeculativeTypePropagator
    implements OptimizationPhase {
  final String name = 'SsaTypeGuardInserter';
  final CodegenWorkItem work;
  bool calledInLoop = false;
  bool isRecursiveMethod = false;
  bool hasInsertedChecks = false;
  int stateId = 1;
  Map<HInstruction, HType> savedTypes = new Map<HInstruction, HType>();

  SsaTypeGuardInserter(compiler, this.work) : super(compiler);

  void visitGraph(HGraph graph) {
    // Run the speculative type propagator. This does in-place
    // update of the type of the instructions, and saves the
    // previous types in the [savedTypes] map.
    SsaTypePropagator propagator =
        new SsaSpeculativeTypePropagator(compiler, savedTypes);
    propagator.visitGraph(graph);

    // Put back the original types in the instructions, and save the
    // speculated types in [savedTypes].
    Map<HInstruction, HType> speculativeTypes = new Map<HInstruction, HType>();

    savedTypes.forEach((HInstruction instruction, HType type) {
      speculativeTypes[instruction] = instruction.instructionType;
      instruction.instructionType = type;
    });
    savedTypes = speculativeTypes;

    // Propagate types again, and insert type guards in the graph.
    isRecursiveMethod = graph.isRecursiveMethod;
    calledInLoop = graph.calledInLoop;
    work.guards = <HTypeGuard>[];
    visitDominatorTree(graph);

    // We need to disable the guards, and therefore re-run a
    // non-speculative type propagator that will not use the
    // speculated types.
    work.guards.forEach((HTypeGuard guard) { guard.disable(); });

    propagator = new SsaNonSpeculativeTypePropagator(compiler);
    propagator.visitGraph(graph);
  }

  // Primitive types that are not null are valuable. These include
  // indexable arrays.
  bool typeValuable(HType type) {
    return type.isPrimitive(compiler) && !type.isNull();
  }

  bool get hasTypeGuards => work.guards.length != 0;

  bool isUsedWithIncompatibleSelector(HInstruction instruction,
                                      HType speculativeType) {
    for (HInstruction user in instruction.usedBy) {
      if (user is HCheck
          && isUsedWithIncompatibleSelector(user, speculativeType)) {
        return true;
      } else if (user.selector != null
                 && user.getDartReceiver(compiler) == instruction
                 && !speculativeType.computeMask(compiler).willHit(
                        user.selector, compiler)) {
        return true;
      }
    }
    return false;
  }

  bool typeGuardWouldBeValuable(HInstruction instruction,
                                HType speculativeType) {
    // If the type itself is not valuable, do not generate a guard for it.
    if (!typeValuable(speculativeType)) return false;

    // Do not insert a type guard if the instruction has a type
    // annotation that disagrees with the speculated type.
    Element source = instruction.sourceElement;
    if (source != null) {
      DartType sourceType = source.computeType(compiler);
      if (!sourceType.isMalformed && !sourceType.isDynamic &&
          sourceType.kind == TypeKind.INTERFACE) {
        TypeMask sourceMask = new TypeMask.subtype(sourceType);
        TypeMask speculatedMask = speculativeType.computeMask(compiler);
        if (sourceMask.intersection(speculatedMask, compiler).isEmpty) {
          return false;
        }
      }
    }

    // Do not insert a type guard if one of the calls on it will hit
    // [NoSuchMethodError].
    if (isUsedWithIncompatibleSelector(instruction, speculativeType)) {
      return false;
    }

    // Insert type guards for recursive methods.
    if (isRecursiveMethod) return true;

    // Insert type guards if there are uses in loops.
    bool isNested(HBasicBlock inner, HBasicBlock outer) {
      if (identical(inner, outer)) return false;
      if (outer == null) return true;
      while (inner != null) {
        if (identical(inner, outer)) return true;
        inner = inner.parentLoopHeader;
      }
      return false;
    }

    // If the instruction is not in a loop then the header will be null.
    HBasicBlock currentLoopHeader = instruction.block.enclosingLoopHeader;
    for (HInstruction user in instruction.usedBy) {
      HBasicBlock userLoopHeader = user.block.enclosingLoopHeader;
      if (isNested(userLoopHeader, currentLoopHeader)) return true;
    }

    bool isIndexOperatorOnIndexablePrimitive(instruction) {
      return instruction is HIndex
          || (instruction is HInvokeDynamicMethod
              && instruction.isIndexOperatorOnIndexablePrimitive(compiler));
    }

    // To speed up computations on values loaded from arrays, we
    // insert type guards for builtin array indexing operations in
    // nested loops. Since this can blow up code size quite
    // significantly, we only do it if type guards have already been
    // inserted for this method. The code size price for an additional
    // type guard is much smaller than the first one that causes the
    // generation of a bailout method.
    if (hasTypeGuards
        && isIndexOperatorOnIndexablePrimitive(instruction)) {
      HBasicBlock loopHeader = instruction.block.enclosingLoopHeader;
      if (loopHeader != null && loopHeader.parentLoopHeader != null) {
        return true;
      }
    }

    // If the instruction is used by a phi where a guard would be
    // valuable, put the guard on that instruction.
    for (HInstruction user in instruction.usedBy) {
      if (user is HPhi
          && user.block.id > instruction.id
          && typeGuardWouldBeValuable(user, speculativeType)) {
        return true;
      }
    }

    // Insert type guards if the method is likely to be called in a
    // loop.
    return calledInLoop;
  }

  HInstruction computeFirstDominatingUserWithSelector(
      HInstruction instruction) {
    // TODO(ngeoffray): We currently only look at the instruction's
    // block, so that we know it will be executed. We should lift this
    // limitation.

    // For a parameter, we look at the first block that contains
    // user instructions.
    HBasicBlock userMustBeInBlock = instruction is HParameterValue
        ? instruction.block.successors[0]
        : instruction.block;

    HInstruction firstUser;
    for (HInstruction user in instruction.usedBy) {
      if (user.block == userMustBeInBlock && user.selector != null) {
        if (firstUser == null || user.dominates(firstUser)) {
          firstUser = user;
        }
      }
    }
    return firstUser;
  }

  /**
   * Tries to insert a type conversion instruction for [instruction]
   * instead of a type guard if we know an user will throw. Returns
   * whether it succeeded at adding a type conversion instruction.
   */
  bool tryTypeConversion(HInstruction instruction, HType speculativeType) {
    HInstruction firstUser =
        computeFirstDominatingUserWithSelector(instruction);
    if (firstUser is !HInvokeDynamic) return false;

    // If we have found a user with a selector, we find out if it
    // will throw [NoSuchMethodError] or [ArgumentError]. If it does,
    // then we change just add a [HTypeConversion] instruction and
    // avoid a bailout.
    Selector selector = firstUser.selector;
    if (!selector.isOperator()) return false;
    HInstruction receiver = firstUser.getDartReceiver(compiler);

    if (instruction == receiver) {
      // If the instruction on which we're speculating the
      // type is the receiver of the call, check if it will throw
      // [NoSuchMethodError] if [instruction] is not of the speculated
      // type.
      return checkReceiver(firstUser);
    } else if (!selector.isUnaryOperator()
               && instruction == firstUser.inputs[2]) {
      // If the instruction is a parameter of the call, we check if
      // the method will throw an [ArgumentError] if [instruction] is
      // not of the speculated type.
      return checkArgument(firstUser);
    }
    return false;
  }

  bool updateType(HInstruction instruction) {
    bool hasChanged = super.updateType(instruction);
    HType speculativeType = savedTypes[instruction];
    if (speculativeType == null
        || !speculativeType.isUseful()
        || speculativeType == instruction.instructionType) {
      return hasChanged;
    }

    if (!tryTypeConversion(instruction, speculativeType)
        && typeGuardWouldBeValuable(instruction, speculativeType)) {
      HInstruction insertionPoint;
      if (instruction is HPhi) {
        insertionPoint = instruction.block.first;
      } else if (instruction is HParameterValue) {
        // We insert the type guard at the end of the entry block
        // because if a parameter is live, it must be kept in the live
        // environment. Not doing so would mean we could visit a
        // parameter and remove it from the environment before
        // visiting a type guard.
        insertionPoint = instruction.block.last;
      } else {
        insertionPoint = instruction.next;
      }
      // If the previous instruction is also a type guard, then both
      // guards have the same environment, and can therefore share the
      // same state id.
      HBailoutTarget target;
      int state;
      if (insertionPoint.previous is HTypeGuard) {
        HTypeGuard other = insertionPoint.previous;
        target = other.bailoutTarget;
      } else {
        state = stateId++;
        target = new HBailoutTarget(state);
        insertionPoint.block.addBefore(insertionPoint, target);
      }
      HTypeGuard guard = new HTypeGuard(speculativeType, instruction, target);
      work.guards.add(guard);
      // By setting the type of the guard to the speculated type, we
      // help the analysis find valuable type guards. This however
      // requires to run a non-speculative type propagation again
      // after this analysis.
      guard.instructionType = speculativeType;
      instruction.block.rewrite(instruction, guard);
      insertionPoint.block.addBefore(insertionPoint, guard);
    }
    return hasChanged;
  }
}

/**
 * Computes the environment for each SSA instruction: visits the graph
 * in post-dominator order. Removes an instruction from the environment
 * and adds its inputs to the environment at the instruction's
 * definition.
 *
 * At the end of the computation, insert type guards in the graph.
 */
class SsaEnvironmentBuilder extends HBaseVisitor implements OptimizationPhase {
  final Compiler compiler;
  final String name = 'SsaEnvironmentBuilder';

  final Map<HBailoutTarget, Environment> capturedEnvironments;
  final Map<HBasicBlock, Environment> liveInstructions;
  Environment environment;
  /**
   * The set of current loop headers that dominate the current block.
   */
  Set<HBasicBlock> loopMarkers;

  SsaEnvironmentBuilder(Compiler this.compiler)
    : capturedEnvironments = new Map<HBailoutTarget, Environment>(),
      liveInstructions = new Map<HBasicBlock, Environment>(),
      loopMarkers = new Set<HBasicBlock>();


  void visitGraph(HGraph graph) {
    visitPostDominatorTree(graph);
    if (!liveInstructions[graph.entry].isEmpty) {
      compiler.internalError('Bailout environment computation',
          node: compiler.currentElement.parseNode(compiler));
    }
    updateLoopMarkers();
    insertCapturedEnvironments();
  }

  void updateLoopMarkers() {
    // If the block is a loop header, we need to merge the loop
    // header's live instructions into every environment that contains
    // the loop marker.
    // For example with the following loop (read the example in
    // reverse):
    //
    // while (true) { <-- (4) update the marker with the environment
    //   use(x);      <-- (3) environment = {x}
    //   bailout;     <-- (2) has the marker when computed
    // }              <-- (1) create a loop marker
    //
    // The bailout instruction first captures the marker, but it
    // will be replaced by the live environment at the loop entry,
    // in this case {x}.
    capturedEnvironments.forEach((ignoredInstruction, env) {
      env.loopMarkers.forEach((HBasicBlock header) {
        env.addAll(liveInstructions[header]);
      });
      env.loopMarkers.clear();
    });
  }

  void visitBasicBlock(HBasicBlock block) {
    environment = new Environment();

    // Add to the environment the live instructions of its successor, as well as
    // the inputs of the phis of the successor that flow from this block.
    for (int i = 0; i < block.successors.length; i++) {
      HBasicBlock successor = block.successors[i];
      Environment successorEnv = liveInstructions[successor];
      if (successorEnv != null) {
        environment.addAll(successorEnv);
      } else {
        // If we haven't computed the liveInstructions of that successor, we
        // know it must be a loop header.
        assert(successor.isLoopHeader());
        assert(!block.isLoopHeader());
        loopMarkers.add(successor);
      }

      int index = successor.predecessors.indexOf(block);
      for (HPhi phi = successor.phis.first; phi != null; phi = phi.next) {
        environment.add(phi.inputs[index]);
      }
    }

    if (block.isLoopHeader()) {
      loopMarkers.remove(block);
    }

    // If the block is a loop header, we're adding all [loopMarkers]
    // after removing it from the list of [loopMarkers], because
    // it will just recompute the loop phis.
    environment.loopMarkers.addAll(loopMarkers);

    // Iterate over all instructions to remove an instruction from the
    // environment and add its inputs.
    HInstruction instruction = block.last;
    while (instruction != null) {
      instruction.accept(this);
      instruction = instruction.previous;
    }

    // We just remove the phis from the environment. The inputs of the
    // phis will be put in the environment of the predecessors.
    for (HPhi phi = block.phis.first; phi != null; phi = phi.next) {
      environment.remove(phi);
    }

    // Finally save the liveInstructions of that block.
    liveInstructions[block] = environment;
  }

  void visitBailoutTarget(HBailoutTarget target) {
    visitInstruction(target);
    capturedEnvironments[target] = new Environment.from(environment);
  }

  void visitInstruction(HInstruction instruction) {
    environment.remove(instruction);
    for (int i = 0, len = instruction.inputs.length; i < len; i++) {
      environment.add(instruction.inputs[i]);
    }
  }

  /**
   * Stores all live variables in the bailout target and the guards.
   */
  void insertCapturedEnvironments() {
    capturedEnvironments.forEach((HBailoutTarget target, Environment env) {
      assert(target.inputs.length == 0);
      target.inputs.addAll(env.lives);
      // TODO(floitsch): we should add the bailout-target's input variables
      // as input to the guards only in the optimized version. The
      // non-optimized version does not use the bailout guards and it is
      // unnecessary to keep the variables alive until the check.
      for (HTypeGuard guard in target.usedBy) {
        // A type-guard initially only has two inputs: the guarded instruction
        // and the bailout-target. Only after adding the environment is it
        // allowed to have more inputs.
        assert(guard.inputs.length == 2);
        guard.inputs.addAll(env.lives);
      }
      for (HInstruction live in env.lives) {
        live.usedBy.add(target);
        live.usedBy.addAll(target.usedBy);
      }
    });
  }
}

/**
 * Propagates bailout information to blocks that need it. This visitor
 * is run before codegen, to know which blocks have to deal with
 * bailouts.
 */
class SsaBailoutPropagator extends HBaseVisitor {
  final Compiler compiler;
  /**
   * A list to propagate bailout information to blocks that start a
   * guarded or labeled list of statements. Currently, these blocks
   * are:
   *    - first block of a then branch,
   *    - first block of an else branch,
   *    - a loop header,
   *    - labeled block.
   */
  final List<HBasicBlock> blocks;

  /**
   * The current subgraph we are visiting.
   */
  SubGraph subGraph;

  /**
   * The current block information we are visiting.
   */
  HBlockInformation currentBlockInformation;

  /**
   * Max number of arguments to the bailout (not counting the state).
   */
  int bailoutArity;
  /**
   * A map from variables to their names.  These are the names in the
   * unoptimized (bailout) version of the function.  Their names could be
   * different in the optimized version.
   */
  VariableNames variableNames;
  /**
   * Maps from the variable names to their positions in the argument list of the
   * bailout instruction.  Because of the way the variable allocator works,
   * several variables can end up with the same name (if their live ranges do
   * not overlap), therefore they can have the same position in the bailout
   * argument list
   */
  Map<String, int> parameterNames;

  /**
   * If set to true, the graph has either multiple bailouts in
   * different places, or a bailout inside an if or a loop. For such a
   * graph, the code generator will emit a generic switch.
   */
  bool hasComplexBailoutTargets = false;

  /**
   * The first type guard in the graph.
   */
  HBailoutTarget firstBailoutTarget;

  /**
   * If set, it is the first block in the graph where we generate
   * code. Blocks before this one are dead code in the bailout
   * version.
   */

  SsaBailoutPropagator(this.compiler, this.variableNames)
      : blocks = <HBasicBlock>[],
        bailoutArity = 0,
        parameterNames = new Map<String, int>();

  void visitGraph(HGraph graph) {
    subGraph = new SubGraph(graph.entry, graph.exit);
    visitBasicBlock(graph.entry);
    if (!blocks.isEmpty) {
      compiler.internalError('Bailout propagation',
          node: compiler.currentElement.parseNode(compiler));
    }
  }

  /**
   * Returns true if we can visit the given [blockFlow]. False
   * otherwise. Currently, try/catch and switch are not in bailout
   * methods, so this method only deals with loops and labeled blocks.
   * If [blockFlow] is a labeled block or a loop, we also visit the
   * continuation of the block flow.
   */
  bool handleBlockFlow(HBlockFlow blockFlow) {
    HBlockInformation body = blockFlow.body;

    // We reach here again when starting to visit a subgraph. Just
    // return to visiting the block.
    if (currentBlockInformation == body) return false;

    HBlockInformation oldInformation = currentBlockInformation;
    if (body is HLabeledBlockInformation) {
      currentBlockInformation = body;
      HLabeledBlockInformation info = body;
      visitStatements(info.body, newFlow: true);
    } else if (body is HLoopBlockInformation) {
      currentBlockInformation = body;
      HLoopBlockInformation info = body;
      if (info.initializer != null) {
        visitExpression(info.initializer);
      }
      blocks.add(info.loopHeader);
      if (!info.isDoWhile()) {
        visitExpression(info.condition);
      }
      visitStatements(info.body, newFlow: false);
      if (info.isDoWhile()) {
        visitExpression(info.condition);
      }
      if (info.updates != null) {
        visitExpression(info.updates);
      }
      blocks.removeLast();
    } else {
      assert(body is! HTryBlockInformation);
      assert(body is! HSwitchBlockInformation);
      // [HIfBlockInformation] is handled by visitIf.
      return false;
    }

    currentBlockInformation = oldInformation;
    if (blockFlow.continuation != null) {
      visitBasicBlock(blockFlow.continuation);
    }
    return true;
  }

  void visitBasicBlock(HBasicBlock block) {
    // Abort traversal if we are leaving the currently active sub-graph.
    if (!subGraph.contains(block)) return;

    HBlockFlow blockFlow = block.blockFlow;
    if (blockFlow != null && handleBlockFlow(blockFlow)) return;

    HInstruction instruction = block.first;
    while (instruction != null) {
      instruction.accept(this);
      instruction = instruction.next;
    }
  }

  void visitExpression(HSubExpressionBlockInformation info) {
    visitSubGraph(info.subExpression);
  }

  /**
   * Visit the statements in [info]. If [newFlow] is true, we add the
   * first block of [statements] to the list of [blocks].
   */
  void visitStatements(HSubGraphBlockInformation info, {bool newFlow}) {
    SubGraph graph = info.subGraph;
    if (newFlow) blocks.add(graph.start);
    visitSubGraph(graph);
    if (newFlow) blocks.removeLast();
  }

  void visitSubGraph(SubGraph graph) {
    SubGraph oldSubGraph = subGraph;
    subGraph = graph;
    visitBasicBlock(graph.start);
    subGraph = oldSubGraph;
  }

  void visitIf(HIf instruction) {
    int preVisitedBlocks = 0;
    HIfBlockInformation info = instruction.blockInformation.body;
    visitStatements(info.thenGraph, newFlow: true);
    preVisitedBlocks++;
    visitStatements(info.elseGraph, newFlow: true);
    preVisitedBlocks++;

    HBasicBlock joinBlock = instruction.joinBlock;
    if (joinBlock != null
        && !identical(joinBlock.dominator, instruction.block)) {
      // The join block is dominated by a block in one of the branches.
      // The subgraph traversal never reached it, so we visit it here
      // instead.
      visitBasicBlock(joinBlock);
    }

    // Visit all the dominated blocks that are not part of the then or else
    // branches, and is not the join block.
    // Depending on how the then/else branches terminate
    // (e.g., return/throw/break) there can be any number of these.
    List<HBasicBlock> dominated = instruction.block.dominatedBlocks;
    int dominatedCount = dominated.length;
    for (int i = preVisitedBlocks; i < dominatedCount; i++) {
      HBasicBlock dominatedBlock = dominated[i];
      visitBasicBlock(dominatedBlock);
    }
  }

  void visitGoto(HGoto goto) {
    HBasicBlock block = goto.block;
    HBasicBlock successor = block.successors[0];
    if (identical(successor.dominator, block)) {
      visitBasicBlock(block.successors[0]);
    }
  }

  void visitLoopBranch(HLoopBranch branch) {
    // For a do-while loop, the body has already been visited.
    if (!branch.isDoWhile()) {
      visitBasicBlock(branch.block.dominatedBlocks[0]);
    }
  }

  visitBailoutTarget(HBailoutTarget target) {
    int inputLength = target.inputs.length;
    for (HInstruction input in target.inputs) {
      String inputName = variableNames.getName(input);
      int position = parameterNames[inputName];
      if (position == null) {
        position = parameterNames[inputName] = bailoutArity++;
      }
    }

    if (blocks.isEmpty) {
      // If [currentBlockInformation] is not null, we are in the
      // middle of a loop/labeled block and this is too complex to handle for
      // now.
      if (firstBailoutTarget == null && currentBlockInformation == null) {
        firstBailoutTarget = target;
      } else {
        hasComplexBailoutTargets = true;
      }
    } else {
      hasComplexBailoutTargets = true;
      blocks.forEach((HBasicBlock block) {
        block.bailoutTargets.add(target);
      });
    }
  }
}
