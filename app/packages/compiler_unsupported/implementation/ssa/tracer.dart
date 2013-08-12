// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library tracer;

import 'dart:async' show EventSink;

import 'ssa.dart';
import '../js_backend/js_backend.dart';
import '../dart2jslib.dart';

const bool GENERATE_SSA_TRACE = false;
const String SSA_TRACE_FILTER = null;

class HTracer extends HGraphVisitor implements Tracer {
  Compiler compiler;
  JavaScriptItemCompilationContext context;
  int indent = 0;
  final EventSink<String> output;
  final bool enabled = GENERATE_SSA_TRACE;
  bool traceActive = false;

  HTracer(this.output);

  void close() {
    if (enabled) output.close();
  }

  void traceCompilation(String methodName,
                        JavaScriptItemCompilationContext compilationContext,
                        Compiler compiler) {
    if (!enabled) return;
    this.context = compilationContext;
    this.compiler = compiler;
    traceActive =
        SSA_TRACE_FILTER == null || methodName.contains(SSA_TRACE_FILTER);
    if (!traceActive) return;
    tag("compilation", () {
      printProperty("name", methodName);
      printProperty("method", methodName);
      printProperty("date", new DateTime.now().millisecondsSinceEpoch);
    });
  }

  void traceGraph(String name, HGraph graph) {
    if (!traceActive) return;
    tag("cfg", () {
      printProperty("name", name);
      visitDominatorTree(graph);
    });
  }

  void addPredecessors(HBasicBlock block) {
    if (block.predecessors.isEmpty) {
      printEmptyProperty("predecessors");
    } else {
      addIndent();
      add("predecessors");
      for (HBasicBlock predecessor in block.predecessors) {
        add(' "B${predecessor.id}"');
      }
      add("\n");
    }
  }

  void addSuccessors(HBasicBlock block) {
    if (block.successors.isEmpty) {
      printEmptyProperty("successors");
    } else {
      addIndent();
      add("successors");
      for (HBasicBlock successor in block.successors) {
        add(' "B${successor.id}"');
      }
      add("\n");
    }
  }

  void addInstructions(HInstructionStringifier stringifier,
                       HInstructionList list) {
    for (HInstruction instruction = list.first;
         instruction != null;
         instruction = instruction.next) {
      int bci = 0;
      int uses = instruction.usedBy.length;
      String changes = instruction.sideEffects.hasSideEffects() ? '!' : ' ';
      String depends = instruction.sideEffects.dependsOnSomething() ? '?' : '';
      addIndent();
      String temporaryId = stringifier.temporaryId(instruction);
      String instructionString = stringifier.visit(instruction);
      add("$bci $uses $temporaryId $instructionString $changes $depends <|@\n");
    }
  }

  void visitBasicBlock(HBasicBlock block) {
    HInstructionStringifier stringifier =
        new HInstructionStringifier(context, block, compiler);
    assert(block.id != null);
    tag("block", () {
      printProperty("name", "B${block.id}");
      printProperty("from_bci", -1);
      printProperty("to_bci", -1);
      addPredecessors(block);
      addSuccessors(block);
      printEmptyProperty("xhandlers");
      printEmptyProperty("flags");
      if (block.dominator != null) {
        printProperty("dominator", "B${block.dominator.id}");
      }
      tag("states", () {
        tag("locals", () {
          printProperty("size", 0);
          printProperty("method", "None");
          block.forEachPhi((phi) {
            String phiId = stringifier.temporaryId(phi);
            StringBuffer inputIds = new StringBuffer();
            for (int i = 0; i < phi.inputs.length; i++) {
              inputIds.write(stringifier.temporaryId(phi.inputs[i]));
              inputIds.write(" ");
            }
            println("${phi.id} $phiId [ $inputIds]");
          });
        });
      });
      tag("HIR", () {
        addInstructions(stringifier, block.phis);
        addInstructions(stringifier, block);
      });
    });
  }

  void tag(String tagName, Function f) {
    println("begin_$tagName");
    indent++;
    f();
    indent--;
    println("end_$tagName");
  }

  void println(String string) {
    addIndent();
    add(string);
    add("\n");
  }

  void printEmptyProperty(String propertyName) {
    println(propertyName);
  }

  void printProperty(String propertyName, var value) {
    if (value is num) {
      println("$propertyName $value");
    } else {
      println('$propertyName "$value"');
    }
  }

  void add(String string) {
    output.add(string);
  }

  void addIndent() {
    for (int i = 0; i < indent; i++) {
      add("  ");
    }
  }
}

class HInstructionStringifier implements HVisitor<String> {
  final Compiler compiler;
  final JavaScriptItemCompilationContext context;
  final HBasicBlock currentBlock;

  HInstructionStringifier(this.context, this.currentBlock, this.compiler);

  visit(HInstruction node) => node.accept(this);

  String temporaryId(HInstruction instruction) {
    String prefix;
    HType type = instruction.instructionType;
    if (type.isExtendableArray(compiler)) {
      prefix = 'e';
    } else if (type.isFixedArray(compiler)) {
      prefix = 'f';
    } else if (type.isMutableArray(compiler)) {
      prefix = 'm';
    } else if (type.isReadableArray(compiler)) {
      prefix = 'a';
    } else if (type.isString(compiler)) {
      prefix = 's';
    } else if (type.isIndexable(compiler)) {
      prefix = 'r';
    } else if (type == HType.BOOLEAN) {
      prefix = 'b';
    } else if (type == HType.INTEGER) {
      prefix = 'i';
    } else if (type == HType.DOUBLE) {
      prefix = 'd';
    } else if (type == HType.NUMBER) {
      prefix = 'n';
    } else if (type == HType.UNKNOWN) {
      prefix = 'v';
    } else if (type == HType.CONFLICTING) {
      prefix = 'c';
    } else if (type == HType.NULL) {
      prefix = 'u';
    } else {
      prefix = 'U';
    }
    return "$prefix${instruction.id}";
  }

  String visitBailoutTarget(HBailoutTarget node) {
    StringBuffer envBuffer = new StringBuffer();
    List<HInstruction> inputs = node.inputs;
    for (int i = 0; i < inputs.length; i++) {
      envBuffer.write(" ${temporaryId(inputs[i])}");
    }
    String on = node.isEnabled ? "enabled" : "disabled";
    return "BailoutTarget($on): id: ${node.state} env: $envBuffer";
  }

  String visitBoolify(HBoolify node) {
    return "Boolify: ${temporaryId(node.inputs[0])}";
  }

  String handleInvokeBinary(HInvokeBinary node, String op) {
    String left = temporaryId(node.left);
    String right= temporaryId(node.right);
    return '$left $op $right';
  }

  String visitAdd(HAdd node) => handleInvokeBinary(node, '+');

  String visitBitAnd(HBitAnd node) => handleInvokeBinary(node, '&');

  String visitBitNot(HBitNot node) {
    String operand = temporaryId(node.operand);
    return "~$operand";
  }

  String visitBitOr(HBitOr node) => handleInvokeBinary(node, '|');

  String visitBitXor(HBitXor node) => handleInvokeBinary(node, '^');

  String visitBoundsCheck(HBoundsCheck node) {
    String lengthId = temporaryId(node.length);
    String indexId = temporaryId(node.index);
    return "Bounds check: length = $lengthId, index = $indexId";
  }

  String visitBreak(HBreak node) {
    HBasicBlock target = currentBlock.successors[0];
    if (node.label != null) {
      return "Break ${node.label.labelName}: (B${target.id})";
    }
    return "Break: (B${target.id})";
  }

  String visitConstant(HConstant constant) => "Constant ${constant.constant}";

  String visitContinue(HContinue node) {
    HBasicBlock target = currentBlock.successors[0];
    if (node.label != null) {
      return "Continue ${node.label.labelName}: (B${target.id})";
    }
    return "Continue: (B${target.id})";
  }

  String visitDivide(HDivide node) => handleInvokeBinary(node, '/');

  String visitExit(HExit node) => "exit";

  String visitFieldGet(HFieldGet node) {
    String fieldName = node.element.name.slowToString();
    return 'field get ${temporaryId(node.receiver)}.$fieldName';
  }

  String visitFieldSet(HFieldSet node) {
    String valueId = temporaryId(node.value);
    String fieldName = node.element.name.slowToString();
    return 'field set ${temporaryId(node.receiver)}.$fieldName to $valueId';
  }

  String visitLocalGet(HLocalGet node) {
    String localName = node.element.name.slowToString();
    return 'local get ${temporaryId(node.local)}.$localName';
  }

  String visitLocalSet(HLocalSet node) {
    String valueId = temporaryId(node.value);
    String localName = node.element.name.slowToString();
    return 'local set ${temporaryId(node.local)}.$localName to $valueId';
  }

  String visitGoto(HGoto node) {
    HBasicBlock target = currentBlock.successors[0];
    return "Goto: (B${target.id})";
  }

  String visitGreater(HGreater node) => handleInvokeBinary(node, '>');
  String visitGreaterEqual(HGreaterEqual node) {
    handleInvokeBinary(node, '>=');
  }
  String visitIdentity(HIdentity node) => handleInvokeBinary(node, '===');

  String visitIf(HIf node) {
    HBasicBlock thenBlock = currentBlock.successors[0];
    HBasicBlock elseBlock = currentBlock.successors[1];
    String conditionId = temporaryId(node.inputs[0]);
    return "If ($conditionId): (B${thenBlock.id}) else (B${elseBlock.id})";
  }

  String visitGenericInvoke(String invokeType, String functionName,
                            List<HInstruction> arguments) {
    StringBuffer argumentsString = new StringBuffer();
    for (int i = 0; i < arguments.length; i++) {
      if (i != 0) argumentsString.write(", ");
      argumentsString.write(temporaryId(arguments[i]));
    }
    return "$invokeType: $functionName($argumentsString)";
  }

  String visitIndex(HIndex node) {
    String receiver = temporaryId(node.receiver);
    String index = temporaryId(node.index);
    return "Index: $receiver[$index]";
  }

  String visitIndexAssign(HIndexAssign node) {
    String receiver = temporaryId(node.receiver);
    String index = temporaryId(node.index);
    String value = temporaryId(node.value);
    return "IndexAssign: $receiver[$index] = $value";
  }

  String visitInterceptor(HInterceptor node) {
    String value = temporaryId(node.inputs[0]);
    return "Intercept: $value";
  }

  String visitInvokeClosure(HInvokeClosure node)
      => visitInvokeDynamic(node, "closure");

  String visitInvokeDynamic(HInvokeDynamic invoke, String kind) {
    String receiver = temporaryId(invoke.receiver);
    String name = invoke.selector.name.slowToString();
    String target = "($kind) $receiver.$name";
    int offset = HInvoke.ARGUMENTS_OFFSET;
    List arguments = invoke.inputs.sublist(offset);
    return visitGenericInvoke("Invoke", target, arguments);
  }

  String visitInvokeDynamicMethod(HInvokeDynamicMethod node)
      => visitInvokeDynamic(node, "method");
  String visitInvokeDynamicGetter(HInvokeDynamicGetter node)
      => visitInvokeDynamic(node, "get");
  String visitInvokeDynamicSetter(HInvokeDynamicSetter node)
      => visitInvokeDynamic(node, "set");

  String visitInvokeStatic(HInvokeStatic invoke) {
    String target = invoke.element.name.slowToString();
    return visitGenericInvoke("Invoke", target, invoke.inputs);
  }

  String visitInvokeSuper(HInvokeSuper invoke) {
    String target = invoke.element.name.slowToString();
    int offset = HInvoke.ARGUMENTS_OFFSET + 1;
    List arguments = invoke.inputs.sublist(offset);
    return visitGenericInvoke("Invoke super", target, arguments);
  }

  String visitInvokeConstructorBody(HInvokeConstructorBody invoke) {
    String target = invoke.element.name.slowToString();
    return visitGenericInvoke("Invoke constructor body", target, invoke.inputs);
  }

  String visitForeign(HForeign foreign) {
    return visitGenericInvoke("Foreign", "${foreign.codeAst}", foreign.inputs);
  }

  String visitForeignNew(HForeignNew node) {
    return visitGenericInvoke("New",
                              "${node.element.name.slowToString()}",
                              node.inputs);
  }

  String visitLess(HLess node) => handleInvokeBinary(node, '<');
  String visitLessEqual(HLessEqual node) => handleInvokeBinary(node, '<=');

  String visitLiteralList(HLiteralList node) {
    StringBuffer elementsString = new StringBuffer();
    for (int i = 0; i < node.inputs.length; i++) {
      if (i != 0) elementsString.write(", ");
      elementsString.write(temporaryId(node.inputs[i]));
    }
    return "Literal list: [$elementsString]";
  }

  String visitLoopBranch(HLoopBranch branch) {
    HBasicBlock bodyBlock = currentBlock.successors[0];
    HBasicBlock exitBlock = currentBlock.successors[1];
    String conditionId = temporaryId(branch.inputs[0]);
    return "While ($conditionId): (B${bodyBlock.id}) then (B${exitBlock.id})";
  }

  String visitMultiply(HMultiply node) => handleInvokeBinary(node, '*');

  String visitNegate(HNegate node) {
    String operand = temporaryId(node.operand);
    return "-$operand";
  }

  String visitNot(HNot node) => "Not: ${temporaryId(node.inputs[0])}";

  String visitParameterValue(HParameterValue node) {
    return "p${node.sourceElement.name.slowToString()}";
  }

  String visitLocalValue(HLocalValue node) {
    return "l${node.sourceElement.name.slowToString()}";
  }

  String visitPhi(HPhi phi) {
    StringBuffer buffer = new StringBuffer();
    buffer.write("Phi(");
    for (int i = 0; i < phi.inputs.length; i++) {
      if (i > 0) buffer.write(", ");
      buffer.write(temporaryId(phi.inputs[i]));
    }
    buffer.write(")");
    return buffer.toString();
  }

  String visitReturn(HReturn node) => "Return ${temporaryId(node.inputs[0])}";

  String visitShiftLeft(HShiftLeft node) => handleInvokeBinary(node, '<<');

  String visitStatic(HStatic node)
      => "Static ${node.element.name.slowToString()}";

  String visitLazyStatic(HLazyStatic node)
      => "LazyStatic ${node.element.name.slowToString()}";

  String visitOneShotInterceptor(HOneShotInterceptor node)
      => visitInvokeDynamic(node, "one shot interceptor");

  String visitStaticStore(HStaticStore node) {
    String lhs = node.element.name.slowToString();
    return "Static $lhs = ${temporaryId(node.inputs[0])}";
  }

  String visitStringConcat(HStringConcat node) {
    var leftId = temporaryId(node.left);
    var rightId = temporaryId(node.right);
    return "StringConcat: $leftId + $rightId";
  }

  String visitStringify(HStringify node) {
    return "Stringify: ${node.inputs[0]}";
  }

  String visitSubtract(HSubtract node) => handleInvokeBinary(node, '-');

  String visitSwitch(HSwitch node) {
    StringBuffer buf = new StringBuffer();
    buf.write("Switch: (");
    buf.write(temporaryId(node.inputs[0]));
    buf.write(") ");
    for (int i = 1; i < node.inputs.length; i++) {
      buf.write(temporaryId(node.inputs[i]));
      buf.write(": B");
      buf.write(node.block.successors[i - 1].id);
      buf.write(", ");
    }
    buf.write("default: B");
    buf.write(node.block.successors.last.id);
    return buf.toString();
  }

  String visitThis(HThis node) => "this";

  String visitThrow(HThrow node) => "Throw ${temporaryId(node.inputs[0])}";

  String visitThrowExpression(HThrowExpression node) {
    return "ThrowExpression ${temporaryId(node.inputs[0])}";
  }

  String visitExitTry(HExitTry node) {
    return "Exit try";
  }

  String visitTry(HTry node) {
    List<HBasicBlock> successors = currentBlock.successors;
    String tryBlock = 'B${successors[0].id}';
    String catchBlock = 'none';
    if (node.catchBlock != null) {
      catchBlock = 'B${successors[1].id}';
    }

    String finallyBlock = 'none';
    if (node.finallyBlock != null) {
      finallyBlock = 'B${node.finallyBlock.id}';
    }

    return "Try: $tryBlock, Catch: $catchBlock, Finally: $finallyBlock, "
        "Join: B${successors.last.id}";
  }

  String visitTypeGuard(HTypeGuard node) {
    String type;
    HType guardedType = node.guardedType;
    if (guardedType.isExtendableArray(compiler)) {
      type = "extendable_array";
    } else if (guardedType.isMutableArray(compiler)) {
      type = "mutable_array";
    } else if (guardedType.isReadableArray(compiler)) {
      type = "readable_array";
    } else if (guardedType == HType.BOOLEAN) {
      type = "bool";
    } else if (guardedType == HType.INTEGER) {
      type = "integer";
    } else if (guardedType == HType.DOUBLE) {
      type = "double";
    } else if (guardedType == HType.NUMBER) {
      type = "number";
    } else if (guardedType.isString(compiler)) {
      type = "string";
    } else if (guardedType.isIndexable(compiler)) {
      type = "string_or_array";
    } else if (guardedType == HType.UNKNOWN) {
      type = 'unknown';
    } else {
      throw new CompilerCancelledException('Unexpected type guard: $type');
    }
    HInstruction guarded = node.guarded;
    HInstruction bailoutTarget = node.bailoutTarget;
    StringBuffer envBuffer = new StringBuffer();
    List<HInstruction> inputs = node.inputs;
    assert(inputs.length >= 2);
    assert(inputs[0] == guarded);
    assert(inputs[1] == bailoutTarget);
    for (int i = 2; i < inputs.length; i++) {
      envBuffer.write(" ${temporaryId(inputs[i])}");
    }
    String on = node.isEnabled ? "enabled" : "disabled";
    String guardedId = temporaryId(node.guarded);
    String bailoutId = temporaryId(node.bailoutTarget);
    return "TypeGuard($on): $guardedId is $type bailout: $bailoutId "
           "env: $envBuffer";
  }

  String visitIs(HIs node) {
    String type = node.typeExpression.toString();
    return "TypeTest: ${temporaryId(node.expression)} is $type";
  }

  String visitTypeConversion(HTypeConversion node) {
    assert(node.inputs.length <= 2);
    String otherInput = (node.inputs.length == 2)
        ? temporaryId(node.inputs[1])
        : '';
    return "TypeConversion: ${temporaryId(node.checkedInput)} to "
      "${node.instructionType} $otherInput";
  }

  String visitRangeConversion(HRangeConversion node) {
    return "RangeConversion: ${node.checkedInput}";
  }
}
