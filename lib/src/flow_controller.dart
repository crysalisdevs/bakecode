part of bakecode;

/// A controller for handling execution of [Flow]s.
class FlowController {
  /// Creates a flow controller to handle the completion of a top-level flow.
  FlowController({
    @required Flow flow,
    RunContext parentContext,
  })  : assert(flow != null),
        next = flow,
        context = RunContext() // TODO: RunContext(inheritFrom: parentContext)
  {
    // Listen to flow state updates.
    _flowStateStreamController.stream.listen(onStateUpdated);

    // set this as the flow controller for the completer context.
    context.set({FlowController: this});
  }

  /// Holds the current [FlowState] of the controller.
  FlowState _currentState;

  /// [StreamController] for the [FlowState] of this controller.
  final _flowStateStreamController = StreamController<FlowState>();

  /// The sink of the [_flowStateStreamController].
  Sink<FlowState> get _stateSink => _flowStateStreamController.sink;

  /// The current [FlowState] of the controller.
  FlowState get state => _currentState;

  /// Starts or resumes the flow completer.
  ///
  /// Attempts to change the current flow state to [FlowState.Running].
  /// After this function has successfully completed, the [FlowController] shall
  /// attempt to complete the pending flow.
  ///
  /// If the flow has already completed or stopped, invoking this function can
  /// throw [StateError].
  @nonVirtual
  void start() {
    if (state == FlowState.Stopped || state == FlowState.Completed) {
      throw StateError("Flow cannot be started when currentState == $state.");
    }

    _updateState(FlowState.Running);
  }

  /// Pauses the flow completer until [start] is invoked.
  ///
  /// Attempts to change the current flow state to [FlowState.Paused].
  /// After this function has successfully completed, the [FlowController] shall
  /// not attempt to complete the pending flow, unless [start] is invoked.
  ///
  /// If the flow has already completed or stopped, invoking this function can
  /// throw [StateError].
  @nonVirtual
  void pause() {
    if (state == FlowState.Stopped || state == FlowState.Completed) {
      throw StateError("Flow cannot be paused when currentState == $state");
    }

    _updateState(FlowState.Paused);
  }

  /// Stops the flow completer from completing the flow forever.
  ///
  /// Attempts to change the current flow state to [FlowState.Stopped].
  /// After this function has successfully completed. the [FlowController] shall
  /// not anymore attempt to complete the pending flow. Completion of the
  /// pending flow cannot be resumed by invoking [start] as it can throw
  /// [StateError].
  ///
  /// If the flow has already completed, invoking this function can throw
  /// [StateError].
  @nonVirtual
  void stop() {
    if (state == FlowState.Completed) {
      throw StateError("Flow cannot be stopped when currentState == $state");
    }

    _updateState(FlowState.Stopped);
  }

  Future<void> get done => _ensureDone();

  Future<void> _ensureDone() async {
    if (state == FlowState.Completed || state == FlowState.Stopped) return;

    await _flowStateStreamController.done;

    return;
  }

  bool _diagnosticsEnabled = true;

  /// The run context for the flow completer to provide on invoking [Flow.run].
  RunContext context;

  /// The next flow that is to be completed.
  @protected
  @nonVirtual
  Flow next;

  /// Attempts to recursively complete the flow while the [state] is
  /// [FlowState.Running].
  ///
  /// If [next] evaluates to `null`, [FlowState.Completed] will be acheived by
  /// the controller. After this state has been acheived, invoking [start],
  /// [pause] or [stop] can cause to throw [StateError].
  @protected
  @nonVirtual
  Future<void> complete() async {
    while (state == FlowState.Running) {
      next = await next.run(context);

      if (next == null) {
        _updateState(FlowState.Completed);
        break;
      }
    }
  }

  /// Updates the flow [state] of the controller.
  void _updateState(FlowState state) => _stateSink.add(state);

  @protected
  @nonVirtual
  void onStateUpdated(FlowState state) {
    _currentState = state;

    if (state == FlowState.Running) {
      complete();
    }

    if (state == FlowState.Completed || state == FlowState.Stopped) {
      _stateSink.close();
    }
  }

  /// Gets the [FlowController] of the [context].
  static FlowController of(RunContext context) =>
      Provider.of<FlowController>(context);
}

FlowController runFlow(
  Flow flow, {
  bool diagnosticsEnabled = true,
}) =>
    FlowController(flow: flow)
      .._diagnosticsEnabled = diagnosticsEnabled
      ..start();

FlowController runSubFlow({
  @required Flow flow,
  @required RunContext parentContext,
}) {
  final controller = FlowController.of(parentContext);

  if (controller == null) {
    throw MissingFlowControllerException(
        'No FlowController attached to parentContext. Skipping runSubFlow(...).');
  }

  return FlowController(flow: flow, parentContext: parentContext)
    .._diagnosticsEnabled = controller._diagnosticsEnabled
    ..start();
}
