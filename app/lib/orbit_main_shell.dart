import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'llm_integration_screen.dart';

/// Horizontal [PageView] plus bottom tabs: Voice (page 0) and LLM (page 1).
class OrbitMainShell extends StatefulWidget {
  const OrbitMainShell({
    super.key,
    this.userName,
    required this.interests,
  });

  final String? userName;
  final List<String> interests;

  @override
  State<OrbitMainShell> createState() => _OrbitMainShellState();
}

class _OrbitMainShellState extends State<OrbitMainShell> {
  static const _tabBarColor = Color(0xFF0B1020);
  static const _pageAnim = Duration(milliseconds: 280);

  final _pageController = PageController();
  var _pageIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: _pageAnim,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.userName;
    return Column(
      children: [
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _pageIndex = i),
            children: [
              OrbitHomeScreen(
                userName: user,
                interests: widget.interests,
              ),
              LlmIntegrationScreen(userName: user),
            ],
          ),
        ),
        Material(
          color: _tabBarColor,
          elevation: 8,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: _TabChip(
                      label: 'Voice',
                      icon: Icons.graphic_eq_rounded,
                      selected: _pageIndex == 0,
                      onTap: () => _goToPage(0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TabChip(
                      label: 'LLM',
                      icon: Icons.smart_toy_outlined,
                      selected: _pageIndex == 1,
                      onTap: () => _goToPage(1),
                      accent: theme.colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? theme.colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.12),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: selected ? color : Colors.white54),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? Colors.white : Colors.white54,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
