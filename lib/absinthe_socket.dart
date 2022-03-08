library absinthe_socket;

import 'package:phoenix_wings/phoenix_wings.dart';

/// An Absinthe Socket
class AbsintheSocket {
  String endpoint;
  late AbsintheSocketOptions socketOptions;
  late PhoenixSocket _phoenixSocket;
  PhoenixChannel? _absintheChannel;
  Map<String, Notifier> _notifiers = {};
  List<Notifier> _queuedPushes = [];
  late NotifierPushHandler subscriptionHandler;
  late NotifierPushHandler unsubscriptionHandler;

  static _onError(Map? response) {
    print("onError");
    print(response.toString());
  }

  static Function(Map?) _onSubscriptionSucceed(Notifier notifier) {
    return (Map? response) {
      print("response");
      print(response.toString());
      notifier.subscriptionId = response?["subscriptionId"];
    };
  }

  _onUnsubscriptionSucceed(Notifier notifier) {
    return (Map response) {
      print("unsubscription response");
      print(response.toString());
      notifier.cancel();
      _notifiers.remove(notifier);
    };
  }

  static _onTimeout(Map? response) {
    print("onTimeout");
  }

  AbsintheSocket(
    this.endpoint, {
    AbsintheSocketOptions? options,
  }) {
    this.socketOptions = options ?? AbsintheSocketOptions();
    subscriptionHandler = NotifierPushHandler(
        onError: _onError, onTimeout: _onTimeout, onSucceed: _onSubscriptionSucceed);
    unsubscriptionHandler = NotifierPushHandler(
        onError: _onError, onTimeout: _onTimeout, onSucceed: _onUnsubscriptionSucceed);
    _phoenixSocket = PhoenixSocket(endpoint,
        socketOptions:
            PhoenixSocketOptions(params: socketOptions.params..addAll({"vsn": "2.0.0"})));
    _connect();
  }

  _connect() async {
    await _phoenixSocket.connect();
    _phoenixSocket.onMessage(_onMessage);
    _absintheChannel = _phoenixSocket.channel("__absinthe__:control", {});
    _absintheChannel?.join()?.receive("ok", _sendQueuedPushes);
  }

  disconnect() {
    _phoenixSocket.disconnect();
  }

  _sendQueuedPushes(_) {
    _queuedPushes.forEach((notifier) {
      _pushRequest(notifier);
    });
    _queuedPushes = [];
  }

  void cancel(Notifier notifier) {
    unsubscribe(notifier);
  }

  void unsubscribe(Notifier notifier) {
    PhoenixPush? phoenixPush = _absintheChannel?.push(
      event: "unsubscribe",
      payload: {"subscriptionId": notifier.subscriptionId},
    );

    if (phoenixPush != null) {
      _handlePush(
        phoenixPush,
        _createPushHandler(unsubscriptionHandler, notifier),
      );
    }
  }

  Notifier send(GqlRequest request, String notifierKey, {Observer? observer}) {
    if (_notifiers.containsKey(notifierKey)) {
      _pushRequest(_notifiers[notifierKey]!);
      return _notifiers[notifierKey]!;
    }

    Notifier notifier = Notifier(request: request, observer: observer);

    _notifiers[notifierKey] = notifier;

    _pushRequest(notifier);
    return notifier;
  }

  _onMessage(PhoenixMessage message) {
    String? subscriptionId = message.topic;

    _notifiers.forEach((key, value) {
      if (value.subscriptionId == subscriptionId) {
        return value.notify(message.payload?["result"] ?? {});
      }
    });
  }

  _pushRequest(Notifier notifier) {
    if (_absintheChannel == null) {
      _queuedPushes.add(notifier);
    } else {
      PhoenixPush? phoenixPush =
          _absintheChannel?.push(event: "doc", payload: {"query": notifier.request.operation});

      if (phoenixPush != null) {
        _handlePush(
          phoenixPush,
          _createPushHandler(subscriptionHandler, notifier),
        );
      }
    }
  }

  _handlePush(PhoenixPush push, PushHandler handler) {
    push
        .receive("ok", handler.onSucceed)
        .receive("error", handler.onError)
        .receive("timeout", handler.onTimeout);
  }

  PushHandler _createPushHandler(NotifierPushHandler notifierPushHandler, Notifier notifier) {
    return _createEventHandler(notifier, notifierPushHandler);
  }

  _createEventHandler(Notifier notifier, NotifierPushHandler notifierPushHandler) {
    return PushHandler(
      onError: notifierPushHandler.onError,
      onSucceed: notifierPushHandler.onSucceed(notifier),
      onTimeout: notifierPushHandler.onTimeout,
    );
  }
}

class AbsintheSocketOptions {
  Map<String, String> params = {};

  AbsintheSocketOptions({Map<String, String>? params}) {
    this.params = params ?? {};
  }
}

class Notifier<Result> {
  GqlRequest request;
  Observer<Result>? observer;
  String? subscriptionId;

  Notifier({required this.request, this.observer});

  void observe(Observer<Result> theObserver) => observer = theObserver;
  void notify(Map? result) => observer?.onResult(result);
  void cancel() => observer?.onCancel();
}

class Observer<Result> {
  Function onAbort;
  Function onCancel;
  Function onError;
  Function onStart;
  Function onResult;

  Observer({
    required this.onAbort,
    required this.onCancel,
    required this.onError,
    required this.onStart,
    required this.onResult,
  });
}

class GqlRequest {
  String operation;

  GqlRequest({required this.operation});
}

class NotifierPushHandler<Response> {
  Function(Map?) onError;
  Function(Notifier) onSucceed;
  Function(Map?) onTimeout;

  NotifierPushHandler({
    required this.onError,
    required this.onSucceed,
    required this.onTimeout,
  });
}

class PushHandler<Response> {
  Function(Map?) onError;
  Function(Map?) onSucceed;
  Function(Map?) onTimeout;

  PushHandler({
    required this.onError,
    required this.onSucceed,
    required this.onTimeout,
  });
}
