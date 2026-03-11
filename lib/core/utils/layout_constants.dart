/// Centralized spacing and layout values for consistent UI.
/// Use from details_screen, discover_carousel, and other layout code.
class LayoutConstants {
  LayoutConstants._();

  // Spacing
  static const double spacingXs = 8;
  static const double spacingSm = 12;
  static const double spacingMd = 16;
  static const double spacingLg = 24;

  // Details screen SliverAppBar
  static const double detailsExpandedHeightMobile = 400;
  static const double detailsExpandedHeightDesktop = 300;

  // Discover carousel: use same breakpoint as [ResponsiveBreakpoints.desktopBreakpoint]
  static const double discoverCarouselDesktopBreakpoint = 900;

  // Carousel hero aspect ratio (e.g. 16/9)
  static const double carouselHeroAspectRatio = 16 / 9;

  // Border Radius
  static const double radiusSm = 4;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 16;
  static const double radiusXxl = 24;
  static const double radiusPill = 50;

  // Content constraints
  static const double contentMaxWidth = 800;
}
