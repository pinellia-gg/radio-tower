import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:radio_tower/l10n/app_localizations.dart';
import 'package:radio_tower/manger/AssetRes.dart';
import 'package:window_manager/window_manager.dart';

const double _titleBarHeight = 40;

class AppWindowFrame extends StatelessWidget {
  const AppWindowFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return child;
    }

    return VirtualWindowFrame(
      child: Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (context) {
              return _AppWindowFrameContent(child: child);
            },
          ),
        ],
      ),
    );
  }
}

class _AppWindowFrameContent extends StatelessWidget {
  const _AppWindowFrameContent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [const _AppWindowTitleBar(), Expanded(child: child)],
      ),
    );
  }
}

class _AppWindowTitleBar extends StatefulWidget {
  const _AppWindowTitleBar();

  @override
  State<_AppWindowTitleBar> createState() => _AppWindowTitleBarState();
}

class _AppWindowTitleBarState extends State<_AppWindowTitleBar>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshMaximizedState());
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _refreshMaximizedState() async {
    try {
      final isMaximized = await windowManager.isMaximized();
      if (mounted) {
        setState(() {
          _isMaximized = isMaximized;
        });
      }
    } catch (_) {
      return;
    }
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _refreshMaximizedState();
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() {
        _isMaximized = true;
      });
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() {
        _isMaximized = false;
      });
    }
  }

  @override
  void onWindowRestore() {
    unawaited(_refreshMaximizedState());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      height: _titleBarHeight,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Container(
                height: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Image.asset(
                      AssetRes.IC_LAUNCHER,
                      width: 18,
                      height: 18,
                      filterQuality: FilterQuality.medium,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        l10n.appTitle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _WindowControlButton(
            tooltip: l10n.minimize,
            icon: Icons.remove,
            onPressed: () {
              unawaited(windowManager.minimize());
            },
          ),
          _WindowControlButton(
            tooltip: _isMaximized ? l10n.restore : l10n.maximize,
            icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
            onPressed: () {
              unawaited(_toggleMaximize());
            },
          ),
          _WindowControlButton(
            tooltip: l10n.close,
            icon: Icons.close,
            isClose: true,
            onPressed: () {
              unawaited(windowManager.close());
            },
          ),
        ],
      ),
    );
  }
}

class _WindowControlButton extends StatefulWidget {
  const _WindowControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor =
        _isHovered
            ? (widget.isClose
                ? const Color(0xFFC42B1C)
                : colorScheme.onSurface.withValues(alpha: 0.08))
            : Colors.transparent;
    final iconColor =
        widget.isClose && _isHovered
            ? Colors.white
            : colorScheme.onSurface.withValues(alpha: 0.82);

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() {
            _isHovered = true;
          });
        },
        onExit: (_) {
          setState(() {
            _isHovered = false;
          });
        },
        child: SizedBox(
          width: 46,
          height: _titleBarHeight,
          child: Material(
            color: backgroundColor,
            child: InkWell(
              onTap: widget.onPressed,
              child: Center(
                child: Icon(widget.icon, size: 16, color: iconColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
