import 'package:flutter/material.dart';

class BottomActionArea extends StatelessWidget {
  const BottomActionArea({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: child,
      ),
    );
  }
}
