import 'package:flutter/material.dart';
import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';

/// Lightweight placeholder for tools that aren't wired yet (UI-only build).
class ComingSoonScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  const ComingSoonScreen({super.key, required this.title, this.icon = Icons.auto_awesome});

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(title: Text(title, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800))),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 96, width: 96,
              decoration: BoxDecoration(color: c.redSoft, shape: BoxShape.circle),
              child: Icon(icon, size: 46, color: c.red),
            ),
            const SizedBox(height: 20),
            Text(title, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 20)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                Strings.of(context).thisToolIsComingSoonTo,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted, fontSize: 14, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
