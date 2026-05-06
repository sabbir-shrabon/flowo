import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/app_drawer.dart';
import '../providers/navigation_provider.dart';
import '../theme/app_theme.dart';

class MainShell extends ConsumerStatefulWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isLargeDesktop = width >= 1200;
    final isDesktop = width >= 900;

    // Forced open on very wide screens
    final isSidebarOpen = isLargeDesktop || ref.watch(sidebarOpenProvider);

    // Listen for manual toggle to open drawer on mobile
    ref.listen(sidebarOpenProvider, (prev, next) {
      if (!isDesktop && next) {
        _scaffoldKey.currentState?.openDrawer();
      }
    });

    final content = Column(
      children: [
        // Main content
        Expanded(child: widget.child),
      ],
    );

    if (isDesktop) {
      return Scaffold(
        key: _scaffoldKey,
        body: Row(
          children: [
            // Sidebar with transition
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: isSidebarOpen ? 280 : 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  width: 280,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: context.colors.border),
                      ),
                    ),
                    child: const AppDrawer(isPermanent: true),
                  ),
                ),
              ),
            ),
            // Content area
            Expanded(child: content),
          ],
        ),
      );
    }

    // Mobile layout
    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(),
      onDrawerChanged: (isOpen) {
        // Sync provider state when drawer is closed via swipe/tap-outside
        if (!isOpen) {
          ref.read(sidebarOpenProvider.notifier).state = false;
        }
      },
      body: content,
    );
  }
}
