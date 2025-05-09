import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';

import 'enums.dart';
import 'types.dart';

// Based on appinio_swiper: 2.1.1 (23.04.2024)
class DynamicStackCardSwiper<T> extends StatefulWidget {
  /// The transition widget builder that builds a wrapping card for the given item.
  final ItemWidgetBuilder<T> cardBuilder;

  /// This callback is called when user cancels the swipe before reaching threshold
  final void Function(SwiperActivity activity)? onSwipeCancelled;

  /// Background cards count
  final int backgroundCardCount;

  /// The amount to scale each successive background card down by,
  ///
  /// The difference in scale for each background card is a fixed amount
  /// relative to the original card.
  ///
  /// Defaults to .9.
  final double backgroundCardScale;

  /// The amount to offset each successive background card relative to the card
  /// before it.
  ///
  /// Defaults to offsetting each card down by 40 dp.
  final Offset? backgroundCardOffset;

  /// A controller that provides programmatic control of the swiper and notifies
  /// on swiper state changes.
  final DynamicStackCardSwiperController<T>? controller;

  /// The duration of swipe animations.
  ///
  /// Swipe animations start after the user lifts their finger or when a drag
  /// is triggered by [DynamicStackCardSwiperController].
  final Duration duration;

  /// A callback that is called with the card's [SwiperPosition] whenever the
  /// position changes.
  final void Function(SwiperPosition position)? onCardPositionChanged;

  /// The maximum angle the card reaches while horizontally swiping.
  ///
  /// Cards lean in the direction of the swipe to sell their physicality. Set
  /// this to 0 to disable the lean.
  final double maxAngle;

  /// Sets whether the card should angle in the opposite direction when it is
  /// dragged from the bottom half.
  ///
  /// Defaults to true.
  final bool invertAngleOnBottomDrag;

  /// What swipe directions to allow.
  ///
  /// Swipes triggered by a controller are always allowed and are not affected
  /// by [swipeOptions].
  final SwipeOptions swipeOptions;

  /// The minimum distance a user has to pan the card before triggering a swipe
  /// animation.
  ///
  /// If a pan is less than [threshold] the card will animate back to it's
  /// original position and the card stack will not change.
  final double threshold;

  /// Set to true to disable swiping.
  final bool isDisabled;

  /// Function that is called to check if an item can be swiped in a given
  /// direction
  final bool Function(T, AxisDirection)? canItemBeSwiped;

  /// Callback that fires with the current item and the swipe direction when
  /// a swipe occurred in a direction item cannot be swiped to.
  ///
  /// See [canItemBeSwiped] for more details.
  final void Function(T, AxisDirection)? onSwipeUnauthorized;

  /// Callback that fires with the new swiping activity (eg a user swipes or
  /// the controller triggers a programmatic swipe).
  ///
  /// See [SwiperActivity] for a list of activities.
  final OnSwipe<T>? onSwipeBegin;

  /// Callback that fires with a swipe activity after the activity is complete.
  ///
  /// See [SwiperActivity] for a list of activities.
  final OnSwipe<T>? onSwipeEnd;

  /// Function that is called when the card stack runs out of cards.
  final VoidCallback? onEnd;

  /// Function that is called when a user attempts to swipe but swiping is
  /// disabled.
  final VoidCallback? onTapDisabled;

  /// The default direction in which the card gets swiped when triggered by
  /// controller.
  ///
  /// Defaults to [AxisDirection.right].
  final AxisDirection defaultDirection;

  const DynamicStackCardSwiper({
    super.key,
    required this.cardBuilder,
    this.controller,
    this.duration = const Duration(milliseconds: 200),
    this.maxAngle = 15,
    this.invertAngleOnBottomDrag = true,
    this.threshold = 50,
    this.backgroundCardCount = 1,
    this.backgroundCardScale = .9,
    this.backgroundCardOffset,
    this.isDisabled = false,
    this.canItemBeSwiped,
    this.onSwipeUnauthorized,
    this.swipeOptions = const SwipeOptions.all(),
    this.onTapDisabled,
    this.onSwipeBegin,
    this.onSwipeEnd,
    this.onCardPositionChanged,
    this.onEnd,
    this.defaultDirection = AxisDirection.right,
    this.onSwipeCancelled,
  })  : assert(maxAngle >= 0),
        assert(threshold > 0);

  @override
  State createState() => _DynamicStackCardSwiperState<T>();
}

class _DynamicStackCardSwiperState<T> extends State<DynamicStackCardSwiper<T>>
    with TickerProviderStateMixin {
  static const _defaultBackgroundCardOffset = Offset(0, 40);

  final List<T> items = [];

  double get _effectiveScaleIncrement => 1 - widget.backgroundCardScale;

  Offset get _effectiveOffset => widget.backgroundCardOffset ?? _defaultBackgroundCardOffset;

  SwiperActivity? _swipeActivity;

  // The future associated with the current swipe activity.
  Future<bool>? _previousActivityFuture;

  AnimationController get _defaultAnimation => AnimationController(
        vsync: this,
        duration: widget.duration,
      );

  late final SwiperPosition _position = SwiperPosition(
    cardSize: MediaQuery.sizeOf(context),
    threshold: widget.threshold,
    maxAngleRadians: widget.maxAngle,
    invertAngleOnBottomDrag: widget.invertAngleOnBottomDrag,
  );

  bool _canItemBeSwiped(T item, AxisDirection direction) =>
      (widget.canItemBeSwiped?.call(item, direction) ?? true);

  Future<void> _onSwipe(AxisDirection direction, {required bool forced}) async {
    if (forced || _canItemBeSwiped(items.last, direction)) {
      final Swipe swipe = Swipe(
        _defaultAnimation,
        begin: _position._offset,
        end: _directionToTarget(direction),
      );
      await _startActivity(swipe);
    } else {
      widget.onSwipeUnauthorized?.call(items.last, direction);
      if (_position._offset != Offset.zero) {
        _onSwipeCancelled(context);
      }
    }
  }

  // Moves the card back to starting position when a drag finished without
  // having reached the threshold.
  void _onSwipeCancelled(BuildContext context) async {
    final CancelSwipe cancelSwipe = CancelSwipe(
      _defaultAnimation,
      begin: _position._offset,
    );
    await _startActivity(cancelSwipe);
    widget.onSwipeCancelled?.call(cancelSwipe);
  }

  Future<void> _onAddCardOnTop(T item, AxisDirection direction) async {
    items.add(item);
    final AddCardOnTop addCardOnTop = AddCardOnTop(
      _defaultAnimation,
      begin: _directionToTarget(direction),
    );
    await _startActivity(addCardOnTop);
  }

  Future<void> _startActivity(SwiperActivity newActivity) async {
    final int? previousIndex = switch (newActivity) {
      Swipe() => items.length - 1,
      AddCardOnTop() => items.length > 1 ? items.length - 2 : null,
      CancelSwipe() => items.length - 1,
      DrivenActivity() => items.length - 1,
    };
    final SwiperActivity? oldActivity = _swipeActivity;
    if (oldActivity != null) {
      // Cancel the existing animation and wait for it to clean up.
      oldActivity.animation.stop();
      await _previousActivityFuture;
    }
    final int? targetIndex = switch (newActivity) {
      Swipe() => items.length > 1 ? items.length - 2 : null,
      AddCardOnTop() => items.length - 1,
      CancelSwipe() => items.length - 1,
      DrivenActivity() => items.length - 1,
    };
    _swipeActivity = newActivity;
    newActivity.animation.addListener(() {
      _position.offset = newActivity.currentOffset;
      setState(() {});
    });
    widget.onSwipeBegin?.call(previousIndex != null ? items[previousIndex] : null,
        targetIndex != null ? items[targetIndex] : null, newActivity);
    _previousActivityFuture =
        newActivity.animation.forward().orCancel.then((_) => false).onError((error, stackTrace) {
      if (error is TickerCanceled) {
        return true;
      }
      throw error!;
    }).then((wasCancelled) {
      newActivity.animation.dispose();
      _swipeActivity = null;
      _position._rotationPosition = null;
      _swipeActivity = null;
      if (!wasCancelled && newActivity is! DrivenActivity) {
        _position._offset = Offset.zero;
      }
      return wasCancelled;
    });
    await _previousActivityFuture;
    T? previousItem;
    if (newActivity is Swipe) {
      previousItem = items.removeLast();
    } else if (previousIndex != null) {
      previousItem = items[previousIndex];
    }
    widget.onSwipeEnd
        ?.call(previousItem, targetIndex != null ? items[targetIndex] : null, newActivity);

    if (items.isEmpty) {
      widget.onEnd?.call();
    }

    setState(() {});
  }

  Future<void> _animateTo(
    Offset target, {
    required Duration duration,
    required Curve curve,
  }) async {
    final DrivenActivity newActivity = DrivenActivity(
      AnimationController(
        vsync: this,
        duration: duration,
      ),
      curve: curve,
      begin: _position.offset,
      end: target,
    );
    await _startActivity(newActivity);
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      // Attach the controller after the frame because `_attach` uses `position`
      // which isn't valid until after `initState` has finished.
      widget.controller?._attach(this);
    });
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _swipeActivity?.animation.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DynamicStackCardSwiper<T> oldWidget) {
    if (oldWidget.threshold != widget.threshold ||
        oldWidget.maxAngle != widget.maxAngle ||
        oldWidget.invertAngleOnBottomDrag != widget.invertAngleOnBottomDrag) {
      _position._updateFromWidgetState(widget);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(this);
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void didChangeDependencies() {
    _position._cardSize = MediaQuery.of(context).size;
    super.didChangeDependencies();
  }

  void _insertCardAt(T item, int index) {
    setState(() {
      if (index < 0) {
        // Add to the top of the stack
        items.add(item);
      } else if (index >= items.length) {
        // Add to the bottom of the stack
        items.insert(0, item);
      } else {
        // Add at the specified index
        items.insert(index, item);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container();
    }

    // Use the clamp to ensure we don't go past 1.
    final double maxProgressToThreshold = max(
      _position._offsetRelativeToSize.dx.abs(),
      _position._offsetRelativeToSize.dy.abs(),
    ).clamp(0, 1);
    final int effectiveBackgroundCardCount = _effectiveBackgroundCardCount();
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        if (effectiveBackgroundCardCount > 0)
          _BackgroundCards(
            position: _position,
            indices: List.generate(
              effectiveBackgroundCardCount,
              (index) => items.length - 2 - index,
            ),
            builder: (context, index) => widget.cardBuilder.call(context, items[index]),
            scaleIncrement: _effectiveScaleIncrement,
            offsetIncrement: _effectiveOffset,
            initialEffectFactor: 1 - maxProgressToThreshold,
            fadeLastItem: effectiveBackgroundCardCount > widget.backgroundCardCount,
          ),
        Transform.translate(
          offset: _position.offset,
          child: GestureDetector(
            child: Transform.rotate(
              angle: _position.angleRadians,
              alignment: _position._rotationAlignment ?? Alignment.bottomCenter,
              child: widget.cardBuilder.call(context, items.last),
            ),
            onTap: () {
              if (widget.isDisabled) {
                widget.onTapDisabled?.call();
              }
            },
            onPanStart: (tapInfo) {
              if (widget.isDisabled) {
                return;
              }
              _position._rotationPosition = tapInfo.localPosition;
            },
            onPanUpdate: (tapInfo) {
              if (widget.isDisabled) {
                return;
              }
              setState(() {
                final swipeOption = widget.swipeOptions;

                final Offset tapDelta = tapInfo.delta;
                double dx = 0;
                double dy = 0;
                if (swipeOption.up && tapDelta.dy < 0) {
                  dy = tapDelta.dy;
                } else if (swipeOption.down && tapInfo.delta.dy > 0) {
                  dy = tapDelta.dy;
                }
                if (swipeOption.left && tapDelta.dx < 0) {
                  dx = tapDelta.dx;
                } else if (swipeOption.right && tapInfo.delta.dx > 0) {
                  dx = tapDelta.dx;
                }
                _position.offset += Offset(dx, dy);
              });
              _onSwiping();
            },
            onPanEnd: (tapInfo) async {
              if (widget.isDisabled) {
                return;
              }

              return _onPanEnd();
            },
          ),
        ),
      ],
    );
  }

  int _effectiveBackgroundCardCount() {
    // Use one extra card so cards entering the stack can fade in smoothly.
    final int effectiveCardCount = widget.backgroundCardCount + 1;
    final int remaining = items.length - 1;
    return remaining.clamp(0, effectiveCardCount);
  }

  Future<void> _onSwiping() async {
    widget.onCardPositionChanged?.call(_position);
  }

  Offset _directionToTarget(AxisDirection direction) {
    final Size size = MediaQuery.sizeOf(context);
    return switch (direction) {
      AxisDirection.up => Offset(0, -size.height),
      AxisDirection.down => Offset(0, size.height),
      AxisDirection.left => Offset(-size.width, 0),
      AxisDirection.right => Offset(size.width, 0),
    };
  }

  Future<void> _onPanEnd() async {
    // TODO: Use a ballistic simulation to determine if the swipe should be
    // triggered or not.
    // See the snapping behavior from `DraggableScrollableSheet`.
    if (_position._offsetRelativeToThreshold.dx.abs() < 1 &&
        _position._offsetRelativeToThreshold.dy.abs() < 1) {
      return _onSwipeCancelled(context);
    }
    await _onSwipe(_position.offset.toAxisDirection(), forced: false);
  }

  Future<void> _onSwipeDefault({required bool forced}) async {
    return _onSwipe(widget.defaultDirection, forced: forced);
  }
}

class _BackgroundCards extends StatelessWidget {
  const _BackgroundCards({
    required this.position,
    required this.indices,
    required this.builder,
    required this.scaleIncrement,
    required this.offsetIncrement,
    required this.initialEffectFactor,
    required this.fadeLastItem,
  });

  final SwiperPosition position;

  // The indices in the original card stack. This is a list instead of a start
  // and count because it may be non-contiguous if `loop` is true.
  final List<int> indices;
  final IndexedWidgetBuilder builder;
  final double scaleIncrement;
  final Offset offsetIncrement;
  final double initialEffectFactor;
  final bool fadeLastItem;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: position,
      builder: (context, child) {
        return Stack(
          children: indices
              .asMap()
              .map((j, index) {
                final double effectFactor = initialEffectFactor + j;
                final Offset offset = offsetIncrement * effectFactor;
                final double scale = 1 - (effectFactor * scaleIncrement);
                if (scale <= 0) {
                  return MapEntry(j, null);
                }
                return MapEntry(
                  j,
                  Opacity(
                    opacity:
                        fadeLastItem && j == indices.length - 1 ? min(1, position.progress) : 1,
                    child: Transform.translate(
                      offset: offset,
                      child: Transform.scale(
                        scale: scale,
                        child: builder(context, index),
                      ),
                    ),
                  ),
                );
              })
              .values
              .nonNulls
              .toList()
              .reversed
              .toList(),
        );
      },
    );
  }
}

/// A controller used to control a [DynamicStackCardSwiper],
///
/// The controller notifies listeners when a swipe starts and for each tick of a
/// swipe animation.
class DynamicStackCardSwiperController<T> extends ChangeNotifier {
  _DynamicStackCardSwiperState<T>? _attachedSwiper;

  /// The current activity of the swiper.
  ///
  /// This is non null when:
  /// 1. The user has finished their drag while manually swiping.
  /// 2. A programmatic swipe is triggered from this controller.
  SwiperActivity? get swipeActivity {
    return _attachedSwiper?._swipeActivity;
  }

  /// The position of the swiper.
  SwiperPosition? get position {
    return _attachedSwiper?._position;
  }

  /// The current size of the stack.
  int? get size {
    return _attachedSwiper?.items.length;
  }

  /// The current stack.
  ///
  /// You can consider inserting items manually from there, but the widget
  /// will not display them until next event, and there will not be any
  /// animation inserting them. Still it can be useful if you wish, for example,
  /// to insert items at the very bottom of the stack before user reaches it;
  /// you should just pay attention to the [backgroundCardCount] you are using,
  /// so visual doesn't end up jumping weirdly on next event.
  List<T>? get items {
    return _attachedSwiper?.items;
  }

  /// The current position of the card, as a result of a user drag and/or a
  /// swipe animation.
  ///
  /// This is 0 when there is no active swipe. It increments up to 1 during an
  /// active swipe and then resets to 0 when the swipe is complete.
  Offset? get swipeProgress {
    return position?._offsetRelativeToSize;
  }

  /// Swipe the card in the default direction.
  ///
  /// Set [force] to false if [DynamicStackCardSwiper.canItemBeSwiped] condition
  /// should be verified.
  ///
  /// The default direction is set by the attached [DynamicStackCardSwiper] widget.
  Future<void> swipeDefault({bool force = true}) async {
    _assertIsAttached();
    await _attachedSwiper!._onSwipeDefault(forced: force);
    notifyListeners();
  }

  /// Swipe the card to the left side.
  ///
  /// Set [force] to false if [DynamicStackCardSwiper.canItemBeSwiped] condition
  /// should be verified.
  Future<void> swipeLeft({bool force = true}) async {
    _assertIsAttached();
    await _attachedSwiper!._onSwipe(AxisDirection.left, forced: force);
    notifyListeners();
  }

  /// Swipe the card to the right side.
  ///
  /// Set [force] to false if [DynamicStackCardSwiper.canItemBeSwiped] condition
  /// should be verified.
  Future<void> swipeRight({bool force = true}) async {
    _assertIsAttached();
    // ignore: unawaited_futures
    _attachedSwiper!._onSwipe(AxisDirection.right, forced: force);
    notifyListeners();
  }

  /// Swipe the card to the top.
  ///
  /// Set [force] to false if [DynamicStackCardSwiper.canItemBeSwiped] condition
  /// should be verified.
  Future<void> swipeUp({bool force = true}) async {
    _assertIsAttached();
    await _attachedSwiper!._onSwipe(AxisDirection.up, forced: force);
    notifyListeners();
  }

  /// Swipe the card to the bottom.
  ///
  /// Set [force] to false if [DynamicStackCardSwiper.canItemBeSwiped] condition
  /// should be verified.
  Future<void> swipeDown({bool force = true}) async {
    _assertIsAttached();
    await _attachedSwiper!._onSwipe(AxisDirection.down, forced: force);
    notifyListeners();
  }

  /// Add a new card on top of the stack
  Future<void> addCardOnTop(T item, AxisDirection direction) async {
    _assertIsAttached();
    await _attachedSwiper!._onAddCardOnTop(item, direction);
    notifyListeners();
  }

  void insertCardAt(T item, int index) {
    _assertIsAttached();
    _attachedSwiper!._insertCardAt(item, index);
    notifyListeners();
  }
  void removeAll() {
    _assertIsAttached();
    items?.clear();
    notifyListeners();
  }

  /// Animate the card at the top of the stack to the specified offset.
  ///
  /// The card will not reset or snap at the end of the animation-it is up to
  /// the caller to animate the card back to the center.
  Future<void> animateTo(
    Offset target, {
    required Duration duration,
    required Curve curve,
  }) async {
    _assertIsAttached();
    await _attachedSwiper!._animateTo(
      target,
      duration: duration,
      curve: curve,
    );
  }

  void _attach(_DynamicStackCardSwiperState<T> swiper) {
    assert(
      _attachedSwiper == null,
      'Controller can only be attached to one swiper widget at a time.',
    );
    _attachedSwiper = swiper;
    swiper._position.addListener(notifyListeners);
  }

  void _detach() {
    _attachedSwiper?._position.removeListener(notifyListeners);
    _attachedSwiper = null;
  }

  void _assertIsAttached() {
    assert(_attachedSwiper != null, 'Controller must be attached.');
  }
}

/// The position of the swiper.
///
/// This includes the offset and rotations applied to the top card.
/// You can use this position to coordinate custom animations with
/// the swiper state.
///
/// The swiper position is exposed by [DynamicStackCardSwiperController].
class SwiperPosition with ChangeNotifier {
  SwiperPosition({
    required Size cardSize,
    required double threshold,
    required double maxAngleRadians,
    required bool invertAngleOnBottomDrag,
  })  : _cardSize = cardSize,
        _threshold = threshold,
        _maxAngle = maxAngleRadians,
        _invertAngleOnBottomDrag = invertAngleOnBottomDrag;

  set offset(Offset newOffset) {
    _offset = newOffset;
    notifyListeners();
  }

  /// The offset of the card on the top of the stack.
  Offset get offset => _offset;

  /// The rotation angle of the card in degrees.
  ///
  /// This is 0 when [progress] is 0 and negative or positive
  /// [DynamicStackCardSwiper.maxAngle] when [progress] is 1.
  ///
  /// A negative angle indicated counterclockwise rotation, positive clockwise.
  double get angle {
    // If we allow inverting the direction and the user is dragging from the
    // bottom half of the card, angle in the opposite direction.
    final direction =
        _invertAngleOnBottomDrag && _rotationAlignment != null && _rotationAlignment!.y > 0
            ? -1
            : 1;
    return (direction * _maxAngle * (_offset.dx / _cardSize.width)).clamp(-_maxAngle, _maxAngle);
  }

  /// The rotation angle of the card in radians.
  ///
  /// See [angle].
  double get angleRadians => angle * (pi / 180);

  /// The current swiping progress of the top card.
  ///
  /// This is 0 when the card is centered and 1 when it is swiped offscreen and
  /// about to be dismissed.
  double get progress => max(
        _offsetRelativeToSize.dx.abs(),
        _offsetRelativeToSize.dy.abs(),
      );

  /// The current swiping progress relative to the swiping threshold.
  ///
  /// This is 0 when the card is centered and greater than 1 when it is swiped
  /// past the threshold at which a card will swipe off screen instead of
  /// returning to the center.
  double get progressRelativeToThreshold {
    final Offset offset = _offsetRelativeToThreshold;
    if (offset.dx.abs() > offset.dy) {
      return offset.dx;
    }
    return offset.dy;
  }

  /// The pixel size of the top card.
  ///
  /// This can be used to convert offsets relative to the card size.
  Size get cardSize => _cardSize;

  // When the user starts a pan we save the point they tapped. We then rotate
  // the card around this point as they swipe.
  // By rotating around the point of their tap we ensure that their finger
  // stays in the same local position relative to the card.
  Offset? _rotationPosition;

  Alignment? get _rotationAlignment => _rotationPosition?.toAlignment(cardSize);

  // All variables are private so that they can be updated without allowing
  // external packages to modify them.
  Offset _offset = Offset.zero;

  Size _cardSize;

  double _threshold;

  double _maxAngle;

  bool _invertAngleOnBottomDrag;

  Offset get _offsetRelativeToSize => Offset(
        _offset.dx / _cardSize.width,
        _offset.dy / _cardSize.height,
      );

  Offset get _offsetRelativeToThreshold => Offset(
        _offset.dx / _threshold,
        _offset.dy / _threshold,
      );

  void _updateFromWidgetState(DynamicStackCardSwiper widget) {
    _threshold = widget.threshold;
    _maxAngle = widget.maxAngle;
    _invertAngleOnBottomDrag = widget.invertAngleOnBottomDrag;
    notifyListeners();
  }
}
