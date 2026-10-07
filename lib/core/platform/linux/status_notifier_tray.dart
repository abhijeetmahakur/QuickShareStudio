import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

/// One entry of the tray menu. [label] null makes a separator.
class TrayMenuItem {
  const TrayMenuItem(this.id, this.label, {this.enabled = true});
  const TrayMenuItem.separator(this.id)
      : label = null,
        enabled = true;

  /// Positive; 0 is the menu root.
  final int id;
  final String? label;
  final bool enabled;

  bool get isSeparator => label == null;
}

/// A square icon in the ARGB32 (network byte order) layout the tray protocol expects.
class TrayPixmap {
  const TrayPixmap(this.size, this.argb);
  final int size;
  final Uint8List argb;

  DBusValue toDBus() => DBusStruct([DBusInt32(size), DBusInt32(size), DBusArray.byte(argb)]);
}

/// A system tray icon for Linux: the freedesktop StatusNotifierItem protocol with a
/// DBusMenu (what KDE Plasma, GNOME with the AppIndicator extension - Ubuntu's default -,
/// Cinnamon, XFCE and LXQt show). Pure D-Bus, so no extra native library has to be installed.
///
/// [start] returns false when the desktop has no tray host; it registers later on its own
/// if one appears (for example after enabling the GNOME extension).
class StatusNotifierTray {
  StatusNotifierTray({
    required this.id,
    required this.title,
    required this.tooltip,
    required this.pixmaps,
    required this._menu,
    required this.onActivate,
    required this.onMenuItem,
    this.onHostChanged,
    this._client,
  });

  static const watcherName = 'org.kde.StatusNotifierWatcher';
  static const _itemPath = '/StatusNotifierItem';
  static const _menuPath = '/MenuBar';

  final String id;
  final String title;
  String tooltip;
  final List<TrayPixmap> pixmaps;
  List<TrayMenuItem> _menu;
  final VoidCallback onActivate;
  final void Function(int id) onMenuItem;

  /// Called with true when a tray host shows the icon, false when it goes away.
  final void Function(bool visible)? onHostChanged;

  DBusClient? _client;
  bool _ownsClient = false;
  _ItemObject? _item;
  _MenuObject? _menuObject;
  StreamSubscription<DBusNameOwnerChangedEvent>? _watcherSub;
  String? _busName;
  bool _registered = false;

  bool get isVisible => _registered;

  Future<bool> start() async {
    try {
      if (_client == null) {
        _client = DBusClient.session();
        _ownsClient = true;
      }
      final client = _client!;
      _busName = 'org.kde.StatusNotifierItem-$pid-1';
      await client.requestName(_busName!, flags: {DBusRequestNameFlag.doNotQueue});
      _item = _ItemObject(this);
      _menuObject = _MenuObject(this);
      await client.registerObject(_item!);
      await client.registerObject(_menuObject!);
      _watcherSub = client.nameOwnerChanged.where((e) => e.name == watcherName).listen((e) {
        if (e.newOwner != null) {
          unawaited(_register());
        } else {
          _setRegistered(false);
        }
      });
      return await _register();
    } catch (e) {
      debugPrint('[QuickShare] Tray unavailable: $e');
      return false;
    }
  }

  Future<bool> _register() async {
    final client = _client;
    if (client == null || _busName == null) return false;
    try {
      if (!await client.nameHasOwner(watcherName)) {
        _setRegistered(false);
        return false;
      }
      await client.callMethod(
        destination: watcherName,
        path: DBusObjectPath('/StatusNotifierWatcher'),
        interface: watcherName,
        name: 'RegisterStatusNotifierItem',
        values: [DBusString(_busName!)],
        replySignature: DBusSignature(''),
      );
      _setRegistered(true);
      return true;
    } catch (e) {
      debugPrint('[QuickShare] Tray host refused the icon: $e');
      _setRegistered(false);
      return false;
    }
  }

  void _setRegistered(bool value) {
    if (_registered == value) return;
    _registered = value;
    onHostChanged?.call(value);
  }

  /// Replaces the menu (for example to switch "Pause receiving" / "Resume receiving").
  Future<void> setMenu(List<TrayMenuItem> menu) async {
    _menu = menu;
    await _menuObject?.layoutChanged();
  }

  Future<void> setTooltip(String text) async {
    tooltip = text;
    await _item?.emitSignal(_ItemObject.interface, 'NewToolTip');
  }

  Future<void> stop() async {
    await _watcherSub?.cancel();
    final client = _client;
    if (client == null) return;
    try {
      if (_item != null) await client.unregisterObject(_item!);
      if (_menuObject != null) await client.unregisterObject(_menuObject!);
      if (_busName != null) await client.releaseName(_busName!);
    } catch (_) {}
    if (_ownsClient) await client.close();
    _client = null;
    _setRegistered(false);
  }
}

DBusIntrospectArgument _in(String type, String name) =>
    DBusIntrospectArgument(DBusSignature(type), DBusArgumentDirection.in_, name: name);
DBusIntrospectArgument _out(String type, String name) =>
    DBusIntrospectArgument(DBusSignature(type), DBusArgumentDirection.out, name: name);

/// org.kde.StatusNotifierItem at /StatusNotifierItem.
class _ItemObject extends DBusObject {
  _ItemObject(this.tray) : super(DBusObjectPath(StatusNotifierTray._itemPath));

  static const interface = 'org.kde.StatusNotifierItem';
  final StatusNotifierTray tray;

  DBusValue get _pixmaps => DBusArray(DBusSignature('(iiay)'), [for (final p in tray.pixmaps) p.toDBus()]);
  DBusValue get _noPixmaps => DBusArray(DBusSignature('(iiay)'));

  Map<String, DBusValue> get _properties => {
        'Category': const DBusString('ApplicationStatus'),
        'Id': DBusString(tray.id),
        'Title': DBusString(tray.title),
        'Status': const DBusString('Active'),
        'WindowId': const DBusInt32(0),
        'IconThemePath': const DBusString(''),
        'IconName': const DBusString(''),
        'IconPixmap': _pixmaps,
        'OverlayIconName': const DBusString(''),
        'OverlayIconPixmap': _noPixmaps,
        'AttentionIconName': const DBusString(''),
        'AttentionIconPixmap': _noPixmaps,
        'AttentionMovieName': const DBusString(''),
        'ToolTip': DBusStruct([const DBusString(''), _noPixmaps, DBusString(tray.title), DBusString(tray.tooltip)]),
        'ItemIsMenu': const DBusBoolean(false),
        'Menu': DBusObjectPath(StatusNotifierTray._menuPath),
      };

  @override
  List<DBusIntrospectInterface> introspect() => [
        DBusIntrospectInterface(
          interface,
          methods: [
            DBusIntrospectMethod('ContextMenu', args: [_in('i', 'x'), _in('i', 'y')]),
            DBusIntrospectMethod('Activate', args: [_in('i', 'x'), _in('i', 'y')]),
            DBusIntrospectMethod('SecondaryActivate', args: [_in('i', 'x'), _in('i', 'y')]),
            DBusIntrospectMethod('Scroll', args: [_in('i', 'delta'), _in('s', 'orientation')]),
            DBusIntrospectMethod('ProvideXdgActivationToken', args: [_in('s', 'token')]),
          ],
          signals: [
            DBusIntrospectSignal('NewTitle'),
            DBusIntrospectSignal('NewIcon'),
            DBusIntrospectSignal('NewAttentionIcon'),
            DBusIntrospectSignal('NewOverlayIcon'),
            DBusIntrospectSignal('NewToolTip'),
            DBusIntrospectSignal('NewStatus', args: [_out('s', 'status')]),
          ],
          properties: [
            for (final e in _properties.entries)
              DBusIntrospectProperty(e.key, e.value.signature, access: DBusPropertyAccess.read),
          ],
        ),
      ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != interface) return DBusMethodErrorResponse.unknownInterface();
    switch (methodCall.name) {
      case 'Activate':
      case 'SecondaryActivate':
        tray.onActivate();
        return DBusMethodSuccessResponse();
      case 'ContextMenu':
      case 'Scroll':
      case 'ProvideXdgActivationToken':
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = interface == _ItemObject.interface ? _properties[name] : null;
    return value == null ? DBusMethodErrorResponse.unknownProperty() : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      DBusGetAllPropertiesResponse(interface == _ItemObject.interface ? _properties : {});
}

/// com.canonical.dbusmenu at /MenuBar: a flat menu under the root item 0.
class _MenuObject extends DBusObject {
  _MenuObject(this.tray) : super(DBusObjectPath(StatusNotifierTray._menuPath));

  static const interface = 'com.canonical.dbusmenu';
  final StatusNotifierTray tray;
  int _revision = 1;

  Map<String, DBusValue> get _properties => {
        'Version': const DBusUint32(3),
        'TextDirection': const DBusString('ltr'),
        'Status': const DBusString('normal'),
        'IconThemePath': DBusArray.string(const []),
      };

  Map<String, DBusValue> _itemProperties(TrayMenuItem item) => item.isSeparator
      ? {'type': const DBusString('separator'), 'visible': const DBusBoolean(true)}
      : {
          'label': DBusString(item.label!),
          'enabled': DBusBoolean(item.enabled),
          'visible': const DBusBoolean(true),
        };

  DBusValue _node(int id, Map<String, DBusValue> props, List<DBusValue> children) => DBusStruct([
        DBusInt32(id),
        DBusDict.stringVariant(props),
        DBusArray.variant(children),
      ]);

  DBusValue _layout(int parentId) {
    if (parentId == 0) {
      return _node(0, {'children-display': const DBusString('submenu')}, [
        for (final item in tray._menu) _node(item.id, _itemProperties(item), const []),
      ]);
    }
    final item = tray._menu.where((m) => m.id == parentId).firstOrNull;
    return _node(parentId, item == null ? const {} : _itemProperties(item), const []);
  }

  Future<void> layoutChanged() async {
    _revision++;
    await emitSignal(interface, 'LayoutUpdated', [DBusUint32(_revision), const DBusInt32(0)]);
  }

  @override
  List<DBusIntrospectInterface> introspect() => [
        DBusIntrospectInterface(
          interface,
          methods: [
            DBusIntrospectMethod('GetLayout', args: [
              _in('i', 'parentId'),
              _in('i', 'recursionDepth'),
              _in('as', 'propertyNames'),
              _out('u', 'revision'),
              _out('(ia{sv}av)', 'layout'),
            ]),
            DBusIntrospectMethod('GetGroupProperties', args: [
              _in('ai', 'ids'),
              _in('as', 'propertyNames'),
              _out('a(ia{sv})', 'properties'),
            ]),
            DBusIntrospectMethod('GetProperty', args: [_in('i', 'id'), _in('s', 'name'), _out('v', 'value')]),
            DBusIntrospectMethod('Event', args: [_in('i', 'id'), _in('s', 'eventId'), _in('v', 'data'), _in('u', 'timestamp')]),
            DBusIntrospectMethod('EventGroup', args: [_in('a(isvu)', 'events'), _out('ai', 'idErrors')]),
            DBusIntrospectMethod('AboutToShow', args: [_in('i', 'id'), _out('b', 'needUpdate')]),
            DBusIntrospectMethod('AboutToShowGroup', args: [_in('ai', 'ids'), _out('ai', 'updatesNeeded'), _out('ai', 'idErrors')]),
          ],
          signals: [
            DBusIntrospectSignal('ItemsPropertiesUpdated', args: [_out('a(ia{sv})', 'updatedProps'), _out('a(ias)', 'removedProps')]),
            DBusIntrospectSignal('LayoutUpdated', args: [_out('u', 'revision'), _out('i', 'parent')]),
            DBusIntrospectSignal('ItemActivationRequested', args: [_out('i', 'id'), _out('u', 'timestamp')]),
          ],
          properties: [
            for (final e in _properties.entries)
              DBusIntrospectProperty(e.key, e.value.signature, access: DBusPropertyAccess.read),
          ],
        ),
      ];

  void _clicked(int id, String eventId) {
    if (eventId == 'clicked' && tray._menu.any((m) => m.id == id && !m.isSeparator && m.enabled)) {
      tray.onMenuItem(id);
    }
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != interface) return DBusMethodErrorResponse.unknownInterface();
    final args = methodCall.values;
    switch (methodCall.name) {
      case 'GetLayout':
        return DBusMethodSuccessResponse([DBusUint32(_revision), _layout(args[0].asInt32())]);
      case 'GetGroupProperties':
        final ids = args[0].asInt32Array().toList();
        final items = ids.isEmpty ? tray._menu : tray._menu.where((m) => ids.contains(m.id));
        return DBusMethodSuccessResponse([
          DBusArray(DBusSignature('(ia{sv})'), [
            for (final item in items) DBusStruct([DBusInt32(item.id), DBusDict.stringVariant(_itemProperties(item))]),
          ]),
        ]);
      case 'GetProperty':
        final item = tray._menu.where((m) => m.id == args[0].asInt32()).firstOrNull;
        final value = item == null ? null : _itemProperties(item)[args[1].asString()];
        if (value == null) return DBusMethodErrorResponse.invalidArgs('Unknown menu property');
        return DBusMethodSuccessResponse([DBusVariant(value)]);
      case 'Event':
        _clicked(args[0].asInt32(), args[1].asString());
        return DBusMethodSuccessResponse();
      case 'EventGroup':
        for (final event in args[0].asArray()) {
          final fields = event.asStruct();
          _clicked(fields[0].asInt32(), fields[1].asString());
        }
        return DBusMethodSuccessResponse([DBusArray.int32(const [])]);
      case 'AboutToShow':
        return DBusMethodSuccessResponse([const DBusBoolean(false)]);
      case 'AboutToShowGroup':
        return DBusMethodSuccessResponse([DBusArray.int32(const []), DBusArray.int32(const [])]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = interface == _MenuObject.interface ? _properties[name] : null;
    return value == null ? DBusMethodErrorResponse.unknownProperty() : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      DBusGetAllPropertiesResponse(interface == _MenuObject.interface ? _properties : {});
}
