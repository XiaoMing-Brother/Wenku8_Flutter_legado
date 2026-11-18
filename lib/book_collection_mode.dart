/// A collection's presentation is independent from its current device budget.
/// Keep the requested mode when the runtime temporarily suppresses 3D effects.
enum BookCollectionMode {
  shelf,
  list,
  shelfList,
  shelfGrid,
  grid;

  bool get hasShelf => this == shelf || this == shelfList || this == shelfGrid;
  bool get showsCollection => this != shelf;
  bool get isGrid => this == shelfGrid || this == grid;

  /// `shelf` was the legacy storage value for a shelf with a list below it.
  /// New shelf-only layouts use `shelfOnly`, while explicit combined layouts
  /// keep their own names so they are not migrated back to shelf-only.
  String get storageValue => switch (this) {
    shelf => 'shelfOnly',
    shelfList => 'shelfList',
    _ => name,
  };

  String get label => switch (this) {
    shelf => '仅立体书架',
    list => '纯列表',
    shelfList => '立体书架 + 列表',
    shelfGrid => '立体书架 + 宫格',
    grid => '纯宫格',
  };

  static BookCollectionMode? tryParse(Object? value) => switch (value) {
    'list' => list,
    'shelf' || 'shelfList' => shelfList,
    'shelfOnly' => shelf,
    'shelfGrid' => shelfGrid,
    'grid' => grid,
    _ => null,
  };

  /// The shelf page defaults to the 3D shelf alone. Legacy `shelf` records
  /// described the previous shelf + list layout and are migrated to shelf-only.
  static BookCollectionMode parseShelfOrDefault(Object? value) =>
      value == null || value == 'shelf' ? shelf : tryParse(value) ?? shelf;

  static BookCollectionMode parseOrDefault(Object? value) =>
      tryParse(value) ?? shelfList;
}

enum AppStartPage {
  discovery,
  shelf,
  local;

  String get label => switch (this) {
    discovery => '发现',
    shelf => '书架',
    local => '本地',
  };

  static AppStartPage? tryParse(Object? value) => switch (value) {
    'discovery' => discovery,
    'shelf' => shelf,
    'local' => local,
    _ => null,
  };

  static AppStartPage parseOrDefault(Object? value) =>
      tryParse(value) ?? discovery;
}
