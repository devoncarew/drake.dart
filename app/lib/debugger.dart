
library drake.debugger;

import 'dart:async';

import 'bootstrap.dart';
import 'chrome_socket.dart';
import 'debugger_vm.dart';

Future<VmConnection> connectVm(String host, int port) {
  return ChromeSocket.create(ChromeSocketType.TCP).then((ChromeSocket socket) {
    return socket.connect(host, port);
  }).then((ChromeSocket socket) {
    return new VmConnection(
        createVmStreamTransformer().bind(socket.readStream),
        convertStringToIntSink(socket.writeSink));
  });
}

class DebuggerBar extends BAlert {
  VmConnection connection;

  BButton runButton;
  BButton stepInButton;
  BButton stepOverButton;
  BButton stepOutButton;
  BButton terminateButton;

  DebuggerBar(this.connection) {
    runButton = add(new BButton().buttonMini());
    runButton.addElement(createIcon('icon-play'));
    hookButton(runButton, () => connection.resume(connection.mainIsolate));

    add(new BSpan('&nbsp;&nbsp;'));

    // TODO: tooltips
    stepInButton = add(new BButton().buttonMini());
    stepInButton.addElement(createIcon('icon-arrow-down'));
    hookButton(stepInButton, () => connection.stepInto(connection.mainIsolate));

    stepOverButton = add(new BButton().buttonMini());
    stepOverButton.addElement(createIcon('icon-share-alt'));
    hookButton(stepOverButton, () => connection.stepOver(connection.mainIsolate));

    stepOutButton = add(new BButton().buttonMini());
    stepOutButton.addElement(createIcon('icon-arrow-up'));
    hookButton(stepOutButton, () => connection.stepOut(connection.mainIsolate));

    add(new BSpan('&nbsp;&nbsp;'));

    terminateButton = add(new BButton().buttonMini());
    terminateButton.addElement(createIcon('icon-stop'));
    hookButton(terminateButton, () => connection.close());

    _updateButtons();

    connection.onEvent.listen(
        handleDebuggerEvent,
        onDone: () => close());
  }

  void hookButton(BButton button, var action) {
    button.element.onClick.listen((_) {
      if (!button.isDisabled) {
        action();
      }
    });
  }

  void _updateButtons() {
    if (connection.mainIsolate != null) {
      runButton.disabled(!connection.mainIsolate.paused);
      stepInButton.disabled(!connection.mainIsolate.paused);
      stepOverButton.disabled(!connection.mainIsolate.paused);
      stepOutButton.disabled(!connection.mainIsolate.paused);
    }

    terminateButton.disabled(connection.closed);
  }

  void handleDebuggerEvent(VmEvent event) {
    if (event is VmPausedEvent) {
      _updateButtons();
    }
  }
}
