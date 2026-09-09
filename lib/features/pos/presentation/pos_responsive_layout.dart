import 'package:flutter/material.dart';

class POSResponsiveLayout extends StatelessWidget {
  final Widget searchPanel;
  final Widget cartPanel;

  const POSResponsiveLayout({
    Key? key,
    required this.searchPanel,
    required this.cartPanel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isPortrait = size.height > size.width;
    final isSmallScreen = size.width < 600;
    final isMediumScreen = size.width >= 600 && size.width < 1200;
    final isLargeScreen = size.width >= 1200;

    if (isSmallScreen) {
      return _buildMobileLayout();
    } else if (isMediumScreen) {
      return _buildTabletLayout();
    } else {
      return _buildDesktopLayout();
    }
  }

  Widget _buildMobileLayout() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: const [
              Tab(icon: Icon(Icons.shopping_bag), text: 'المنتجات'),
              Tab(icon: Icon(Icons.shopping_cart), text: 'السلة'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: searchPanel,
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: cartPanel,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    return Column(
      children: [
        Expanded(
          flex: 1,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: searchPanel,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          flex: 1,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: cartPanel,
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: searchPanel,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: cartPanel,
          ),
        ),
      ],
    );
  }
}

class POSButtonGroup extends StatelessWidget {
  final List<POSButton> buttons;
  final Axis direction;
  final double spacing;

  const POSButtonGroup({
    Key? key,
    required this.buttons,
    this.direction = Axis.horizontal,
    this.spacing = 8,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    final buttonSize = isSmallScreen ? 56.0 : 48.0;
    final fontSize = isSmallScreen ? 14.0 : 12.0;

    if (direction == Axis.vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildButtons(buttonSize, fontSize)
            .expand((btn) => [btn, SizedBox(height: spacing)])
            .toList()
          ..removeLast(),
      );
    } else {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _buildButtons(buttonSize, fontSize)
              .expand((btn) => [btn, SizedBox(width: spacing)])
              .toList()
            ..removeLast(),
        ),
      );
    }
  }

  List<Widget> _buildButtons(double buttonSize, double fontSize) {
    return buttons
        .map((btn) => SizedBox(
              width: btn.fullWidth ? null : buttonSize,
              height: buttonSize,
              child: btn.isText
                  ? FilledButton(
                      onPressed: btn.onPressed,
                      child: Text(
                        btn.label,
                        style: TextStyle(fontSize: fontSize),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: btn.onPressed,
                      icon: Icon(btn.icon, size: 18),
                      label: Text(
                        btn.label,
                        style: TextStyle(fontSize: fontSize),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ))
        .toList();
  }
}

class POSButton {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool fullWidth;
  final bool isText;

  POSButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.fullWidth = false,
    this.isText = false,
  });

  POSButton.icon({
    required this.label,
    this.onPressed,
    required this.icon,
    this.fullWidth = false,
  }) : isText = false;

  POSButton.text({
    required this.label,
    this.onPressed,
    this.icon,
    this.fullWidth = false,
  }) : isText = true;
}

class POSGrid extends StatelessWidget {
  final List<Widget> children;
  final int? crossAxisCount;
  final double childAspectRatio;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  const POSGrid({
    Key? key,
    required this.children,
    this.crossAxisCount,
    this.childAspectRatio = 1,
    this.mainAxisSpacing = 8,
    this.crossAxisSpacing = 8,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    int columns = crossAxisCount ?? _getDefaultColumns(size.width);

    return GridView.count(
      crossAxisCount: columns,
      childAspectRatio: childAspectRatio,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: children,
    );
  }

  int _getDefaultColumns(double width) {
    if (width < 400) return 1;
    if (width < 600) return 2;
    if (width < 1000) return 3;
    return 4;
  }
}
