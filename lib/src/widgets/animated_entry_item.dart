import 'dart:async';

import 'package:flutter/material.dart';

enum EntryAnimationDirection { vertical, horizontal, both }

class AnimatedEntryItem extends StatefulWidget {
  const AnimatedEntryItem({
    super.key,
    required this.itemKey,
    required this.index,
    required this.child,
    this.duration = const Duration(milliseconds: 420),
    this.initialOffset = 24,
    this.reboundOffset = 4,
    this.staggerDelay = const Duration(milliseconds: 42),
    this.direction = EntryAnimationDirection.horizontal,
    this.opacityTween,
  });

  final String itemKey;
  final int index;
  final Widget child;
  final Duration duration;
  final double initialOffset;
  final double reboundOffset;
  final Duration staggerDelay;
  final EntryAnimationDirection direction;
  final Tween<double>? opacityTween;

  @override
  State<AnimatedEntryItem> createState() => _AnimatedEntryItemState();
}

class _AnimatedEntryItemState extends State<AnimatedEntryItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _settle;
  late Animation<double> _rebound;
  late Animation<double> _opacity;
  Timer? _startTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);
    _setupAnimations();
    _start();
  }

  @override
  void didUpdateWidget(covariant AnimatedEntryItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemKey != widget.itemKey) {
      _setupAnimations();
      _start();
    }
  }

  void _setupAnimations() {
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _settle = Tween<double>(begin: widget.initialOffset, end: 0).animate(curve);
    _rebound = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0), weight: 58),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: widget.reboundOffset,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: widget.reboundOffset,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 24,
      ),
    ]).animate(_controller);
    _opacity = (widget.opacityTween ?? Tween(begin: 0.0, end: 1.0)).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.55, curve: Curves.easeOut),
      ),
    );
  }

  void _start() {
    _startTimer?.cancel();
    _controller.value = 0;
    final delay = widget.staggerDelay * widget.index;
    if (delay <= Duration.zero) {
      _controller.forward();
      return;
    }
    _startTimer = Timer(delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final offset = _settle.value - _rebound.value;
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: switch (widget.direction) {
              EntryAnimationDirection.vertical => Offset(0, offset),
              EntryAnimationDirection.horizontal => Offset(offset, 0),
              EntryAnimationDirection.both => Offset(offset, offset),
            },
            child: child,
          ),
        );
      },
    );
  }
}
