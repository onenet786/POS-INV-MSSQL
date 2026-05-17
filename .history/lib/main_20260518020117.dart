import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;

void main() {
  runApp(const InvProApp());
}

class InvProApp extends StatefulWidget {
  const InvProApp({super.key});

  @override
  State<InvProApp> createState() => _InvProAppState();
}

class _InvProAppState extends State<InvProApp> {
  final AppStore store = AppStore.seeded();
  bool isDark = false;
  bool showingSplash = true;
  AppUser? currentUser;
  Timer? syncTimer;
  Timer? splashTimer;

  @override
  void initState() {
    super.initState();
    unawaited(WindowMode.setLoginWindowMode());
    splashTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => showingSplash = false);
    });
    syncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (currentUser != null) unawaited(store.tryReconnectAndSync());
    });
  }

  @override
  void dispose() {
    syncTimer?.cancel();
    splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const schemeSeed = Color(0xFF0E7C66);
    return StoreScope(
      notifier: store,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'InvPro Enterprise',
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: schemeSeed),
          useMaterial3: true,
          visualDensity: VisualDensity.compact,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: schemeSeed,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          visualDensity: VisualDensity.compact,
        ),
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            child: showingSplash
                ? const SplashPage(key: ValueKey('splash'))
                : currentUser == null
                ? LoginPage(
                    key: const ValueKey('login'),
                    onLogin: (user) {
                      unawaited(
                        WindowMode.setWorkspaceWindowMode(
                          lockFrame: user.isCashier,
                        ),
                      );
                      setState(() => currentUser = user);
                    },
                  )
                : ShellPage(
                    key: const ValueKey('shell'),
                    user: currentUser!,
                    isDark: isDark,
                    onThemeChanged: () => setState(() => isDark = !isDark),
                    onLogout: () {
                      unawaited(WindowMode.setLoginWindowMode());
                      setState(() => currentUser = null);
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class WindowMode {
  static const _channel = MethodChannel('invpro/window');

  static Future<void> setLoginWindowMode() => _invoke('setLoginWindowMode');

  static Future<void> setWorkspaceWindowMode({required bool lockFrame}) =>
      _invoke('setWorkspaceWindowMode', {'lockFrame': lockFrame});

  static Future<void> _invoke(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } catch (_) {
      // Running tests or unsupported platforms can safely ignore window sizing.
    }
  }
}

class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required super.notifier, required super.child});

  static AppStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StoreScope>();
    return scope!.notifier!;
  }
}

class ApiClient {
  ApiClient({
    this.baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      // defaultValue: 'http://pos.flaura.pk:4100/api',
      defaultValue: 'http://192.168.85.235:4100/api',
    ),
  });

  final String baseUrl;
  String? token;
  HttpClient? _client;

  Future<Map<String, dynamic>> login(String email, String password) async {
    final data = await post('/auth/login', {
      'email': email,
      'password': password,
    }, auth: false);
    token = data['token']?.toString();
    return Map<String, dynamic>.from(data['user'] as Map);
  }

  Future<List<Map<String, dynamic>>> getList(String path) async {
    final response = await _request('GET', path);
    if (response is List)
      return response
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    return const [];
  }

  Future<Map<String, dynamic>> getMap(String path) async {
    final response = await _request('GET', path);
    return response is Map
        ? Map<String, dynamic>.from(response)
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final response = await _request('POST', path, body: body, auth: auth);
    return response is Map
        ? Map<String, dynamic>.from(response)
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _request('PUT', path, body: body);
    return response is Map
        ? Map<String, dynamic>.from(response)
        : <String, dynamic>{};
  }

  Future<void> delete(String path) async {
    await _request('DELETE', path);
  }

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    if (kIsWeb) throw UnsupportedError('API sync is disabled in web preview');
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    final request = await client.openUrl(method, Uri.parse('$baseUrl$path'));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (auth && token != null)
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    final decoded = text.isEmpty ? null : jsonDecode(text);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map ? decoded['message']?.toString() : null;
      throw HttpException(
        message ?? 'API request failed (${response.statusCode})',
        uri: Uri.parse('$baseUrl$path'),
      );
    }
    return decoded;
  }
}

class AppStore extends ChangeNotifier {
  AppStore.seeded()
    : products = [
        Product(
          id: 1,
          name: 'USB-C Charger 25W',
          sku: 'CHG-25W',
          barcode: '89010001',
          salePrice: 2800,
          purchasePrice: 1900,
          stock: 42,
          minStock: 12,
          category: 'Electronics',
          posPriority: 1,
        ),
        Product(
          id: 2,
          name: 'Bluetooth Headset Pro',
          sku: 'AUD-BT-PRO',
          barcode: '89010002',
          salePrice: 5500,
          purchasePrice: 3900,
          stock: 18,
          minStock: 8,
          category: 'Electronics',
          posPriority: 2,
        ),
        Product(
          id: 3,
          name: 'Pain Relief Tablets',
          sku: 'MED-PRT-20',
          barcode: '89010003',
          salePrice: 1200,
          purchasePrice: 780,
          stock: 6,
          minStock: 20,
          category: 'Pharmacy',
          posPriority: 3,
        ),
        Product(
          id: 4,
          name: 'Thermal Receipt Roll',
          sku: 'POS-ROLL-80',
          barcode: '89010004',
          salePrice: 360,
          purchasePrice: 230,
          stock: 120,
          minStock: 30,
          category: 'POS Supplies',
          posPriority: 4,
        ),
      ],
      customers = [
        Party(
          id: 1,
          name: 'Walk-in Customer',
          phone: '-',
          email: '',
          balance: 0,
        ),
        Party(
          id: 2,
          name: 'Metro Buyer',
          phone: '+92 300 1112223',
          email: 'buyer@metro.local',
          balance: 91000,
        ),
        Party(
          id: 3,
          name: 'Pharmacy Branch',
          phone: '+92 300 3334445',
          email: 'branch@pharmacy.local',
          balance: 24000,
        ),
      ],
      suppliers = [
        Party(
          id: 1,
          name: 'Tech World Supplies',
          phone: '+92 321 4455667',
          email: 'sales@techworld.local',
          balance: 42000,
        ),
        Party(
          id: 2,
          name: 'Medline Distribution',
          phone: '+92 322 8899001',
          email: 'orders@medline.local',
          balance: 18500,
        ),
      ],
      users = [
        AppUser(
          id: 1,
          name: 'System Admin',
          email: 'admin@invpro.local',
          role: 'Admin',
          active: true,
        ),
        AppUser(
          id: 2,
          name: 'Store Manager',
          email: 'manager@invpro.local',
          role: 'Manager',
          active: true,
        ),
        AppUser(
          id: 3,
          name: 'Front Cashier',
          email: 'cashier@invpro.local',
          role: 'Cashier',
          active: true,
        ),
      ],
      purchases = [
        PurchaseOrder(
          id: 1,
          supplier: 'Tech World Supplies',
          orderNo: 'PO-1001',
          status: 'Pending',
          total: 156000,
        ),
        PurchaseOrder(
          id: 2,
          supplier: 'Medline Distribution',
          orderNo: 'PO-1002',
          status: 'Received',
          total: 84000,
        ),
      ],
      expenses = [
        Expense(id: 1, title: 'Shop rent', category: 'Rent', amount: 65000),
        Expense(
          id: 2,
          title: 'Generator fuel',
          category: 'Utilities',
          amount: 9800,
        ),
      ],
      invoices = [
        Invoice(
          id: 1,
          number: 'INV-10490',
          customer: 'Pharmacy Branch',
          total: 12626,
          paid: 9000,
          method: 'Credit',
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ],
      movements = [
        StockMovement(
          id: 1,
          product: 'USB-C Charger 25W',
          type: 'In',
          quantity: 30,
          notes: 'Opening stock',
        ),
        StockMovement(
          id: 2,
          product: 'Pain Relief Tablets',
          type: 'Out',
          quantity: 14,
          notes: 'Sale adjustment',
        ),
      ] {
    _loadFromDisk();
  }

  final List<Product> products;
  final List<Party> customers;
  final List<Party> suppliers;
  final List<AppUser> users;
  final List<PurchaseOrder> purchases;
  final List<Expense> expenses;
  final List<Invoice> invoices;
  final Map<int, List<InvoiceLine>> invoiceLinesByInvoiceId = {};
  final List<StockMovement> movements;
  final List<SyncJob> pendingSyncJobs = [];
  String receiptPrinterName = '';
  BranchProfile activeBranch = const BranchProfile(
    id: 1,
    name: 'Main Branch',
    code: 'MAIN',
    type: 'Retail',
  );

  int _nextProductId = 10;
  int _nextPartyId = 10;
  int _nextUserId = 10;
  int _nextPurchaseId = 10;
  int _nextExpenseId = 10;
  int _nextInvoiceId = 10491;
  int _nextMovementId = 10;
  final ApiClient api = ApiClient();
  bool sqlConnected = false;
  String syncStatus = 'Local mode';
  final Map<String, int> roleIds = {};
  String? lastLoginEmail;
  String? lastLoginPassword;
  bool _syncing = false;

  File get _recordsFile {
    if (kIsWeb) return File('invpro_records.json');
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      final directory = Directory('$appData\\InvPro');
      if (!directory.existsSync()) directory.createSync(recursive: true);
      return File('${directory.path}\\records.json');
    }
    return File('invpro_records.json');
  }

  @override
  void notifyListeners() {
    _saveToDisk();
    super.notifyListeners();
  }

  void _loadFromDisk() {
    if (kIsWeb) return;
    final file = _recordsFile;
    if (!file.existsSync()) return;
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      products
        ..clear()
        ..addAll(_list(data['products']).map(_productFromJson));
      customers
        ..clear()
        ..addAll(_list(data['customers']).map(_partyFromJson));
      suppliers
        ..clear()
        ..addAll(_list(data['suppliers']).map(_partyFromJson));
      users
        ..clear()
        ..addAll(_list(data['users']).map(_userFromJson));
      purchases
        ..clear()
        ..addAll(_list(data['purchases']).map(_purchaseFromJson));
      expenses
        ..clear()
        ..addAll(_list(data['expenses']).map(_expenseFromJson));
      invoices
        ..clear()
        ..addAll(_list(data['invoices']).map(_invoiceFromJson));
      invoiceLinesByInvoiceId
        ..clear()
        ..addAll(_invoiceLinesMapFromJson(data['invoiceLinesByInvoiceId']));
      movements
        ..clear()
        ..addAll(_list(data['movements']).map(_movementFromJson));
      pendingSyncJobs
        ..clear()
        ..addAll(_list(data['pendingSyncJobs']).map(SyncJob.fromJson));
      lastLoginEmail = data['lastLoginEmail']?.toString();
      lastLoginPassword = data['lastLoginPassword']?.toString();
      receiptPrinterName = data['receiptPrinterName']?.toString() ?? '';
      activeBranch = BranchProfile.fromJson(
        Map<String, dynamic>.from((data['activeBranch'] as Map?) ?? const {}),
      );
      _refreshNextIds();
    } catch (_) {
      final backup = File('${file.path}.bad');
      if (backup.existsSync()) backup.deleteSync();
      file.renameSync(backup.path);
    }
  }

  void _saveToDisk() {
    if (kIsWeb) return;
    final data = {
      'products': products.map(_productToJson).toList(),
      'customers': customers.map(_partyToJson).toList(),
      'suppliers': suppliers.map(_partyToJson).toList(),
      'users': users.map(_userToJson).toList(),
      'purchases': purchases.map(_purchaseToJson).toList(),
      'expenses': expenses.map(_expenseToJson).toList(),
      'invoices': invoices.map(_invoiceToJson).toList(),
      'invoiceLinesByInvoiceId': invoiceLinesByInvoiceId.map(
        (key, value) =>
            MapEntry(key.toString(), value.map(_invoiceLineToJson).toList()),
      ),
      'movements': movements.map(_movementToJson).toList(),
      'pendingSyncJobs': pendingSyncJobs.map((job) => job.toJson()).toList(),
      'lastLoginEmail': lastLoginEmail,
      'lastLoginPassword': lastLoginPassword,
      'receiptPrinterName': receiptPrinterName,
      'activeBranch': activeBranch.toJson(),
    };
    _recordsFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(data),
    );
  }

  void _refreshNextIds() {
    _nextProductId = _nextAfter(products.map((item) => item.id), fallback: 10);
    _nextPartyId = _nextAfter([
      ...customers.map((item) => item.id),
      ...suppliers.map((item) => item.id),
    ], fallback: 10);
    _nextUserId = _nextAfter(users.map((item) => item.id), fallback: 10);
    _nextPurchaseId = _nextAfter(
      purchases.map((item) => item.id),
      fallback: 10,
    );
    _nextExpenseId = _nextAfter(expenses.map((item) => item.id), fallback: 10);
    _nextInvoiceId = _nextAfter(
      invoices.map((item) => item.id),
      fallback: 10491,
    );
    _nextMovementId = _nextAfter(
      movements.map((item) => item.id),
      fallback: 10,
    );
  }

  int _nextAfter(Iterable<int> ids, {required int fallback}) {
    if (ids.isEmpty) return fallback;
    return ids.reduce((a, b) => a > b ? a : b) + 1;
  }

  double get todaysSales => invoices
      .where((invoice) => _sameDate(invoice.createdAt, DateTime.now()))
      .fold(0.0, (sum, invoice) => sum + invoice.total);
  double get pendingDues =>
      customers.fold(0.0, (sum, party) => sum + party.balance) +
      invoices.fold(0.0, (sum, invoice) => sum + invoice.due);
  int get lowStockCount => products
      .where(
        (product) => product.stock > 0 && product.stock <= product.minStock,
      )
      .length;
  int get outOfStockCount =>
      products.where((product) => product.stock <= 0).length;

  Future<AppUser?> login(String email, String password) async {
    lastLoginEmail = email.trim();
    lastLoginPassword = password;
    _saveToDisk();
    try {
      final apiUser = await api.login(email.trim(), password);
      sqlConnected = true;
      syncStatus = 'Connected to SQL Server';
      final user = AppUser(
        id: _int(apiUser, 'id'),
        name: _string(apiUser, 'name'),
        email: _string(apiUser, 'email'),
        role: _string(apiUser, 'role', 'Cashier'),
        active: true,
        branchId: _int(apiUser, 'branchId', 1),
        branchType: _string(apiUser, 'branchType', 'Retail'),
      );
      activeBranch = BranchProfile(
        id: user.branchId ?? _int(apiUser, 'branchId', 1),
        name: _string(apiUser, 'branchName', 'Main Branch'),
        code: _string(apiUser, 'branchCode', 'MAIN'),
        type: user.branchType,
      );
      await _processPendingSyncJobs();
      await loadSqlData();
      await loadSettings();
      return user;
    } catch (error) {
      sqlConnected = false;
      syncStatus = 'Local mode: ${_shortError(error)}';
    }

    final normalizedEmail = email.trim().toLowerCase();
    final matches = users.where(
      (user) => user.email.toLowerCase() == normalizedEmail && user.active,
    );
    if (matches.isEmpty) return null;
    final user = matches.first;
    return password == user.defaultPassword ? user : null;
  }

  Future<void> loadSqlData() async {
    if (!sqlConnected) return;
    final roles = await api.getList('/users/roles');
    roleIds
      ..clear()
      ..addEntries(
        roles.map(
          (role) => MapEntry(_string(role, 'Name'), _int(role, 'RoleId')),
        ),
      );

    final apiProducts = await api.getList('/products');
    products
      ..clear()
      ..addAll(apiProducts.map(_apiProductFromJson));

    final apiCustomers = await api.getList('/customers');
    customers
      ..clear()
      ..addAll(apiCustomers.map(_apiCustomerFromJson));

    try {
      final reference = await api.getMap('/reference');
      final branches = _list(reference['branches']);
      final userBranch = branches.where(
        (branch) => _int(branch, 'BranchId') == activeBranch.id,
      );
      if (userBranch.isNotEmpty)
        activeBranch = BranchProfile.fromApi(userBranch.first);
    } catch (_) {}

    try {
      final apiSuppliers = await api.getList('/suppliers');
      suppliers
        ..clear()
        ..addAll(apiSuppliers.map(_apiSupplierFromJson));
    } catch (_) {}

    try {
      final apiUsers = await api.getList('/users');
      users
        ..clear()
        ..addAll(apiUsers.map(_apiUserFromJson));
    } catch (_) {}

    try {
      final apiInvoices = await api.getList('/invoices');
      invoices
        ..clear()
        ..addAll(apiInvoices.map(_apiInvoiceFromJson));
    } catch (_) {}

    _refreshNextIds();
    _saveToDisk();
    notifyListeners();
  }

  Future<void> loadSettings() async {
    if (!sqlConnected) return;
    try {
      final settings = await api.getMap('/settings');
      receiptPrinterName = _string(
        settings,
        'receiptPrinterName',
        receiptPrinterName,
      );
      _saveToDisk();
      notifyListeners();
    } catch (error) {
      _setSyncStatus('Printer settings load failed: ${_shortError(error)}');
    }
  }

  Future<void> saveReceiptPrinterName(String printerName) async {
    receiptPrinterName = printerName.trim();
    _saveToDisk();
    notifyListeners();
    if (!sqlConnected) {
      _setSyncStatus(
        receiptPrinterName.isEmpty
            ? 'Receipt printer cleared locally'
            : 'Receipt printer saved locally',
      );
      return;
    }
    try {
      await api.put('/settings/receipt-printer-name', {
        'value': receiptPrinterName,
      });
      _setSyncStatus(
        receiptPrinterName.isEmpty
            ? 'Receipt printer set to Windows default'
            : 'Receipt printer saved to SQL Server',
      );
    } catch (error) {
      _setSyncStatus(
        'Printer setting saved locally; SQL save failed: ${_shortError(error)}',
      );
    }
  }

  Future<void> saveActiveBranchType(String branchType) async {
    final normalizedType = branchType.toLowerCase().contains('restaurant')
        ? 'Restaurant'
        : 'Retail';
    activeBranch = activeBranch.copyWith(type: normalizedType);
    _saveToDisk();
    notifyListeners();
    if (!sqlConnected) {
      _setSyncStatus('Branch type saved locally');
      return;
    }
    try {
      await api.put('/reference/branches/${activeBranch.id}/type', {
        'branchTypeCode': normalizedType == 'Restaurant'
            ? 'RESTAURANT'
            : 'RETAIL',
      });
      await loadSqlData();
      _setSyncStatus('Branch type saved to SQL Server');
    } catch (error) {
      _setSyncStatus(
        'Branch type saved locally; SQL save failed: ${_shortError(error)}',
      );
    }
  }

  Future<void> tryReconnectAndSync() async {
    if (_syncing || pendingSyncJobs.isEmpty && sqlConnected) return;
    _syncing = true;
    try {
      if (!sqlConnected) {
        final email = lastLoginEmail;
        final password = lastLoginPassword;
        if (email == null || password == null) return;
        await api.login(email, password);
        sqlConnected = true;
      }
      await _processPendingSyncJobs();
      await loadSqlData();
    } catch (error) {
      sqlConnected = false;
      _setSyncStatus(
        'Waiting to sync ${pendingSyncJobs.length} record(s): ${_shortError(error)}',
      );
    } finally {
      _syncing = false;
    }
  }

  Future<void> _processPendingSyncJobs() async {
    if (!sqlConnected || pendingSyncJobs.isEmpty) return;
    final jobs = List<SyncJob>.of(pendingSyncJobs);
    var synced = 0;
    for (final job in jobs) {
      try {
        await _runSyncJob(job);
        pendingSyncJobs.removeWhere((item) => item.id == job.id);
        synced++;
        _saveToDisk();
      } catch (error) {
        sqlConnected = false;
        _setSyncStatus(
          'Sync paused after $synced record(s): ${_shortError(error)}',
        );
        rethrow;
      }
    }
    _setSyncStatus('Synced $synced pending record(s) to SQL Server');
  }

  Future<void> _runSyncJob(SyncJob job) async {
    switch (job.type) {
      case 'product':
        final product = _productFromJson(job.payload);
        await _syncProduct(
          product,
          isNew: job.action == 'create',
          queueOnFail: false,
        );
        break;
      case 'customer':
        final party = _partyFromJson(job.payload);
        await _syncParty(
          party,
          isCustomer: true,
          isNew: job.action == 'create',
          queueOnFail: false,
        );
        break;
      case 'supplier':
        final party = _partyFromJson(job.payload);
        await _syncParty(
          party,
          isCustomer: false,
          isNew: job.action == 'create',
          queueOnFail: false,
        );
        break;
      case 'user':
        final user = _userFromJson(job.payload);
        await _syncUser(
          user,
          isNew: job.action == 'create',
          queueOnFail: false,
        );
        break;
      case 'expense':
        final expense = _expenseFromJson(job.payload);
        await _syncExpense(expense, queueOnFail: false);
        break;
      case 'invoice':
        final invoice = _invoiceFromJson(
          Map<String, dynamic>.from(job.payload['invoice'] as Map),
        );
        final lines = _list(
          job.payload['lines'],
        ).map(_invoiceLineFromJson).toList();
        await _syncInvoice(invoice, lines, queueOnFail: false);
        break;
      case 'delete':
        await _deleteSql(_string(job.payload, 'path'), queueOnFail: false);
        break;
    }
  }

  void upsertProduct(Product product) {
    final index = products.indexWhere((item) => item.id == product.id);
    final isNew = index == -1;
    Product savedProduct;
    final normalizedProduct = _withProductCodes(
      product,
      nextId: isNew ? _nextProductId : product.id,
    );
    if (index == -1) {
      savedProduct = normalizedProduct.copyWith(id: _nextProductId++);
      products.add(savedProduct);
    } else {
      savedProduct = normalizedProduct;
      products[index] = savedProduct;
    }
    notifyListeners();
    final job = _job(
      'product',
      isNew ? 'create' : 'update',
      savedProduct.id,
      _productToJson(savedProduct),
    );
    if (sqlConnected) {
      unawaited(
        _syncProduct(savedProduct, isNew: isNew, queueOnFail: true, job: job),
      );
    } else {
      _enqueueSyncJob(job);
    }
  }

  void deleteProduct(int id) {
    products.removeWhere((product) => product.id == id);
    notifyListeners();
    final job = _job('delete', 'delete', id, {'path': '/products/$id'});
    if (sqlConnected) {
      unawaited(_deleteSql('/products/$id', queueOnFail: true, job: job));
    } else {
      _enqueueSyncJob(job);
    }
  }

  void upsertCustomer(Party party) => _upsertParty(customers, party);
  void upsertSupplier(Party party) => _upsertParty(suppliers, party);

  void _upsertParty(List<Party> list, Party party) {
    final index = list.indexWhere((item) => item.id == party.id);
    if (index == -1) {
      final savedParty = party.copyWith(id: _nextPartyId++);
      list.add(savedParty);
      final isCustomer = identical(list, customers);
      final job = _job(
        isCustomer ? 'customer' : 'supplier',
        'create',
        savedParty.id,
        _partyToJson(savedParty),
      );
      if (sqlConnected) {
        unawaited(
          _syncParty(
            savedParty,
            isCustomer: isCustomer,
            isNew: true,
            queueOnFail: true,
            job: job,
          ),
        );
      } else {
        _enqueueSyncJob(job);
      }
    } else {
      list[index] = party;
      final isCustomer = identical(list, customers);
      final job = _job(
        isCustomer ? 'customer' : 'supplier',
        'update',
        party.id,
        _partyToJson(party),
      );
      if (sqlConnected) {
        unawaited(
          _syncParty(
            party,
            isCustomer: isCustomer,
            isNew: false,
            queueOnFail: true,
            job: job,
          ),
        );
      } else {
        _enqueueSyncJob(job);
      }
    }
    notifyListeners();
  }

  void deleteParty(List<Party> list, int id) {
    list.removeWhere((party) => party.id == id);
    notifyListeners();
    final path =
        '${identical(list, customers) ? '/customers' : '/suppliers'}/$id';
    final job = _job('delete', 'delete', id, {'path': path});
    if (sqlConnected) {
      unawaited(_deleteSql(path, queueOnFail: true, job: job));
    } else {
      _enqueueSyncJob(job);
    }
  }

  void upsertUser(AppUser user) {
    final index = users.indexWhere((item) => item.id == user.id);
    final isNew = index == -1;
    AppUser savedUser;
    if (index == -1) {
      savedUser = user.copyWith(id: _nextUserId++);
      users.add(savedUser);
    } else {
      savedUser = user;
      users[index] = savedUser;
    }
    notifyListeners();
    final job = _job(
      'user',
      isNew ? 'create' : 'update',
      savedUser.id,
      _userToJson(savedUser),
    );
    if (sqlConnected) {
      unawaited(
        _syncUser(savedUser, isNew: isNew, queueOnFail: true, job: job),
      );
    } else {
      _enqueueSyncJob(job);
    }
  }

  void deleteUser(int id) {
    users.removeWhere((user) => user.id == id);
    notifyListeners();
    _setSyncStatus(
      'Users are disabled from edit screen; backend has no delete route.',
    );
  }

  void upsertPurchase(PurchaseOrder order) {
    final index = purchases.indexWhere((item) => item.id == order.id);
    if (index == -1) {
      purchases.add(order.copyWith(id: _nextPurchaseId++));
    } else {
      purchases[index] = order;
    }
    notifyListeners();
  }

  void receivePurchase(PurchaseOrder order) {
    upsertPurchase(order.copyWith(status: 'Received'));
  }

  Future<int> repairOrphanInvoiceStock() async {
    if (!sqlConnected) {
      _setSyncStatus('Connect to SQL before repairing stock');
      return 0;
    }
    try {
      final result = await api.post(
        '/inventory/repair-orphan-invoice-stock',
        {},
      );
      final repaired = _int(result, 'repaired');
      await loadSqlData();
      _setSyncStatus('Repaired $repaired orphan invoice stock movement(s)');
      return repaired;
    } catch (error) {
      _setSyncStatus('Stock repair failed: ${_shortError(error)}');
      return 0;
    }
  }

  void upsertExpense(Expense expense) {
    final index = expenses.indexWhere((item) => item.id == expense.id);
    if (index == -1) {
      expenses.add(expense.copyWith(id: _nextExpenseId++));
    } else {
      expenses[index] = expense;
    }
    notifyListeners();
    if (index == -1) {
      final savedExpense = expenses.last;
      final job = _job(
        'expense',
        'create',
        savedExpense.id,
        _expenseToJson(savedExpense),
      );
      if (sqlConnected) {
        unawaited(_syncExpense(savedExpense, queueOnFail: true, job: job));
      } else {
        _enqueueSyncJob(job);
      }
    }
  }

  void addStockMovement(StockMovement movement) {
    movements.insert(0, movement.copyWith(id: _nextMovementId++));
    final productIndex = products.indexWhere(
      (product) => product.name == movement.product,
    );
    if (productIndex != -1) {
      final product = products[productIndex];
      final signedQuantity = movement.type == 'Out'
          ? -movement.quantity
          : movement.quantity;
      products[productIndex] = product.copyWith(
        stock: (product.stock + signedQuantity).clamp(0, 999999).toDouble(),
      );
    }
    notifyListeners();
  }

  Invoice postInvoice({
    required String customer,
    required List<InvoiceLine> lines,
    required String method,
    required double paid,
    double tendered = 0,
    double discountAmount = 0,
  }) {
    final subtotal = lines.fold(0.0, (sum, line) => sum + line.total);
    final discount = discountAmount.clamp(0, subtotal).toDouble();
    final total = (subtotal - discount).clamp(0, 999999999).toDouble();
    final invoice = Invoice(
      id: _nextInvoiceId,
      number: 'INV-$_nextInvoiceId',
      customer: customer,
      total: total,
      paid: paid,
      tendered: tendered,
      discountAmount: discount,
      method: method,
      createdAt: DateTime.now(),
    );
    _nextInvoiceId++;
    invoices.insert(0, invoice);
    invoiceLinesByInvoiceId[invoice.id] = List<InvoiceLine>.of(lines);
    for (final line in lines) {
      final index = products.indexWhere(
        (product) => product.id == line.product.id,
      );
      if (index != -1) {
        final product = products[index];
        products[index] = product.copyWith(
          stock: (product.stock - line.quantity).clamp(0, 999999).toDouble(),
        );
      }
    }
    final customerIndex = customers.indexWhere(
      (party) => party.name == customer,
    );
    if (customerIndex != -1 && invoice.due > 0) {
      final party = customers[customerIndex];
      customers[customerIndex] = party.copyWith(
        balance: party.balance + invoice.due,
      );
    }
    notifyListeners();
    final job = _job('invoice', 'create', invoice.id, {
      'invoice': _invoiceToJson(invoice),
      'lines': lines.map(_invoiceLineToJson).toList(),
    });
    if (sqlConnected) {
      unawaited(_syncInvoice(invoice, lines, queueOnFail: true, job: job));
    } else {
      _enqueueSyncJob(job);
    }
    return invoice;
  }

  Future<void> _syncProduct(
    Product product, {
    required bool isNew,
    bool queueOnFail = false,
    SyncJob? job,
  }) async {
    try {
      final body = {
        'name': product.name,
        'unitId': 1,
        'sku': product.sku,
        'barcode': product.barcode,
        'salePrice': product.salePrice,
        'purchasePrice': product.purchasePrice,
        'stockQuantity': product.stock,
        'taxRate': 0,
        'minStockLevel': product.minStock,
        'posPriority': product.posPriority,
        'hasExpiry': false,
        'trackSerial': false,
        'isActive': true,
      };
      final row = isNew
          ? await api.post('/products', body)
          : await api.put('/products/${product.id}', body);
      _replaceProductId(product.id, _int(row, 'ProductId', product.id));
      _setSyncStatus('Saved product to SQL Server');
    } catch (error) {
      if (queueOnFail && job != null) _enqueueSyncJob(job);
      _setSyncStatus('SQL product save failed: ${_shortError(error)}');
      if (!queueOnFail) rethrow;
    }
  }

  Future<void> _syncParty(
    Party party, {
    required bool isCustomer,
    required bool isNew,
    bool queueOnFail = false,
    SyncJob? job,
  }) async {
    try {
      final path = isCustomer ? '/customers' : '/suppliers';
      final body = isCustomer
          ? {
              'name': party.name,
              'phone': _nullable(party.phone),
              'email': _nullable(party.email),
              'creditLimit': party.balance,
            }
          : {
              'name': party.name,
              'phone': _nullable(party.phone),
              'email': _nullable(party.email),
              'taxNumber': null,
            };
      final row = isNew
          ? await api.post(path, body)
          : await api.put('$path/${party.id}', body);
      final nextId = _int(
        row,
        isCustomer ? 'CustomerId' : 'SupplierId',
        party.id,
      );
      _replacePartyId(isCustomer ? customers : suppliers, party.id, nextId);
      _setSyncStatus(
        'Saved ${isCustomer ? 'customer' : 'supplier'} to SQL Server',
      );
    } catch (error) {
      if (queueOnFail && job != null) _enqueueSyncJob(job);
      _setSyncStatus('SQL party save failed: ${_shortError(error)}');
      if (!queueOnFail) rethrow;
    }
  }

  Future<void> _syncUser(
    AppUser user, {
    required bool isNew,
    bool queueOnFail = false,
    SyncJob? job,
  }) async {
    try {
      final roleId =
          roleIds[user.role] ??
          switch (user.role) {
            'Admin' => 1,
            'Manager' => 2,
            _ => 3,
          };
      if (isNew) {
        final row = await api.post('/users', {
          'fullName': user.name,
          'email': user.email,
          'password': user.defaultPassword,
          'roleId': roleId,
          'branchId': null,
        });
        final created = row['0'] is Map
            ? Map<String, dynamic>.from(row['0'] as Map)
            : row;
        _replaceUserId(user.id, _int(created, 'UserId', user.id));
      } else {
        await api.put('/users/${user.id}', {
          'fullName': user.name,
          'roleId': roleId,
          'isActive': user.active,
        });
        if (user.password.isNotEmpty) {
          await api.put('/users/${user.id}/password', {
            'password': user.password,
          });
        }
      }
      _setSyncStatus('Saved user to SQL Server');
    } catch (error) {
      if (queueOnFail && job != null) _enqueueSyncJob(job);
      _setSyncStatus('SQL user save failed: ${_shortError(error)}');
      if (!queueOnFail) rethrow;
    }
  }

  Future<bool> changeOwnPassword(
    AppUser user,
    String currentPassword,
    String newPassword,
  ) async {
    if (newPassword.length < 6) {
      _setSyncStatus('Password must be at least 6 characters');
      return false;
    }
    if (sqlConnected) {
      try {
        await api.put('/users/me/password', {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        });
        lastLoginEmail = user.email;
        lastLoginPassword = newPassword;
        _setSyncStatus('Password changed successfully');
        return true;
      } catch (error) {
        _setSyncStatus('Password change failed: ${_shortError(error)}');
        return false;
      }
    }

    final index = users.indexWhere(
      (item) =>
          item.id == user.id ||
          item.email.toLowerCase() == user.email.toLowerCase(),
    );
    if (index == -1 || users[index].defaultPassword != currentPassword) {
      _setSyncStatus('Current password is incorrect');
      return false;
    }
    users[index] = users[index].copyWith(password: newPassword);
    lastLoginEmail = user.email;
    lastLoginPassword = newPassword;
    notifyListeners();
    _setSyncStatus('Password changed locally');
    return true;
  }

  Future<void> _syncExpense(
    Expense expense, {
    bool queueOnFail = false,
    SyncJob? job,
  }) async {
    try {
      await api.post('/expenses', {
        'branchId': 1,
        'category': expense.category,
        'amount': expense.amount,
        'notes': expense.title,
        'expenseDate': DateTime.now().toIso8601String().substring(0, 10),
      });
      _setSyncStatus('Saved expense to SQL Server');
    } catch (error) {
      if (queueOnFail && job != null) _enqueueSyncJob(job);
      _setSyncStatus('SQL expense save failed: ${_shortError(error)}');
      if (!queueOnFail) rethrow;
    }
  }

  Future<void> _syncInvoice(
    Invoice invoice,
    List<InvoiceLine> lines, {
    bool queueOnFail = false,
    SyncJob? job,
  }) async {
    try {
      final row = await api.post('/invoices', {
        'branchId': 1,
        'warehouseId': 1,
        'customerId': _customerIdByName(invoice.customer),
        'discountAmount': invoice.discountAmount,
        'payments': invoice.paid > 0
            ? [
                {'method': invoice.method, 'amount': invoice.paid},
              ]
            : [],
        'items': [
          for (final line in lines)
            {
              'productId': line.product.id,
              'quantity': line.quantity,
              'unitPrice': line.product.salePrice,
              'discountAmount': 0,
              'taxAmount': 0,
            },
        ],
      });
      _replaceInvoice(
        invoice.id,
        invoice.copyWith(
          id: _int(row, 'invoiceId', invoice.id),
          number: _string(row, 'invoiceNo', invoice.number),
        ),
      );
      _setSyncStatus('Saved invoice to SQL Server');
    } catch (error) {
      if (queueOnFail && job != null) _enqueueSyncJob(job);
      _setSyncStatus('SQL invoice save failed: ${_shortError(error)}');
      if (!queueOnFail) rethrow;
    }
  }

  Future<void> _deleteSql(
    String path, {
    bool queueOnFail = false,
    SyncJob? job,
  }) async {
    try {
      await api.delete(path);
      _setSyncStatus('Deleted record from SQL Server');
    } catch (error) {
      if (queueOnFail && job != null) _enqueueSyncJob(job);
      _setSyncStatus('SQL delete failed: ${_shortError(error)}');
      if (!queueOnFail) rethrow;
    }
  }

  void _replaceProductId(int oldId, int newId) {
    final index = products.indexWhere((item) => item.id == oldId);
    if (index != -1 && oldId != newId)
      products[index] = products[index].copyWith(id: newId);
  }

  void _replacePartyId(List<Party> list, int oldId, int newId) {
    final index = list.indexWhere((item) => item.id == oldId);
    if (index != -1 && oldId != newId)
      list[index] = list[index].copyWith(id: newId);
  }

  void _replaceUserId(int oldId, int newId) {
    final index = users.indexWhere((item) => item.id == oldId);
    if (index != -1 && oldId != newId)
      users[index] = users[index].copyWith(id: newId);
  }

  void _replaceInvoice(int oldId, Invoice invoice) {
    final index = invoices.indexWhere((item) => item.id == oldId);
    if (index != -1) invoices[index] = invoice;
    if (oldId != invoice.id && invoiceLinesByInvoiceId.containsKey(oldId)) {
      invoiceLinesByInvoiceId[invoice.id] = invoiceLinesByInvoiceId.remove(
        oldId,
      )!;
    }
  }

  Future<List<InvoiceLine>> invoiceLinesFor(Invoice invoice) async {
    final localLines = invoiceLinesByInvoiceId[invoice.id];
    if (localLines != null && localLines.isNotEmpty) return localLines;
    if (!sqlConnected) return const [];
    final data = await api.getMap('/invoices/${invoice.id}');
    final lines = _list(data['items']).map(_apiInvoiceLineFromJson).toList();
    if (lines.isNotEmpty) {
      invoiceLinesByInvoiceId[invoice.id] = lines;
      _saveToDisk();
    }
    return lines;
  }

  int? _customerIdByName(String name) {
    final matches = customers.where(
      (party) => party.name == name && party.id > 0,
    );
    return matches.isEmpty ? null : matches.first.id;
  }

  SyncJob _job(
    String type,
    String action,
    int recordId,
    Map<String, dynamic> payload,
  ) {
    return SyncJob(
      id: '${type}_${action}_$recordId',
      type: type,
      action: action,
      recordId: recordId,
      payload: payload,
      createdAt: DateTime.now(),
    );
  }

  void _enqueueSyncJob(SyncJob job) {
    pendingSyncJobs.removeWhere((item) => item.id == job.id);
    pendingSyncJobs.add(job);
    _setSyncStatus('Queued ${pendingSyncJobs.length} record(s) for SQL sync');
  }

  void _setSyncStatus(String status) {
    syncStatus = status;
    _saveToDisk();
    super.notifyListeners();
  }
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

String _string(Map<String, dynamic> json, String key, [String fallback = '']) =>
    json[key]?.toString() ?? fallback;
int _int(Map<String, dynamic> json, String key, [int fallback = 0]) {
  final value = json[key];
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _double(Map<String, dynamic> json, String key, [double fallback = 0]) {
  final value = json[key];
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

bool _bool(Map<String, dynamic> json, String key, [bool fallback = false]) =>
    json[key] is bool ? json[key] as bool : fallback;

Product _productFromJson(Map<String, dynamic> json) {
  return Product(
    id: _int(json, 'id'),
    name: _string(json, 'name'),
    sku: _string(json, 'sku'),
    barcode: _string(json, 'barcode'),
    salePrice: _double(json, 'salePrice'),
    purchasePrice: _double(json, 'purchasePrice'),
    stock: _double(json, 'stock'),
    minStock: _double(json, 'minStock'),
    category: _string(json, 'category', 'General'),
    posPriority: _int(json, 'posPriority'),
  );
}

Map<String, dynamic> _productToJson(Product product) => {
  'id': product.id,
  'name': product.name,
  'sku': product.sku,
  'barcode': product.barcode,
  'salePrice': product.salePrice,
  'purchasePrice': product.purchasePrice,
  'stock': product.stock,
  'minStock': product.minStock,
  'category': product.category,
  'posPriority': product.posPriority,
};

Party _partyFromJson(Map<String, dynamic> json) {
  return Party(
    id: _int(json, 'id'),
    name: _string(json, 'name'),
    phone: _string(json, 'phone'),
    email: _string(json, 'email'),
    balance: _double(json, 'balance'),
  );
}

Map<String, dynamic> _partyToJson(Party party) => {
  'id': party.id,
  'name': party.name,
  'phone': party.phone,
  'email': party.email,
  'balance': party.balance,
};

AppUser _userFromJson(Map<String, dynamic> json) {
  return AppUser(
    id: _int(json, 'id'),
    name: _string(json, 'name'),
    email: _string(json, 'email'),
    role: _string(json, 'role', 'Cashier'),
    active: _bool(json, 'active', true),
    password: _string(json, 'password'),
    branchId: _int(json, 'branchId', 1),
    branchType: _string(json, 'branchType', 'Retail'),
  );
}

Map<String, dynamic> _userToJson(AppUser user) => {
  'id': user.id,
  'name': user.name,
  'email': user.email,
  'role': user.role,
  'active': user.active,
  'password': user.password,
  'branchId': user.branchId,
  'branchType': user.branchType,
};

PurchaseOrder _purchaseFromJson(Map<String, dynamic> json) {
  return PurchaseOrder(
    id: _int(json, 'id'),
    supplier: _string(json, 'supplier'),
    orderNo: _string(json, 'orderNo'),
    status: _string(json, 'status', 'Pending'),
    total: _double(json, 'total'),
  );
}

Map<String, dynamic> _purchaseToJson(PurchaseOrder order) => {
  'id': order.id,
  'supplier': order.supplier,
  'orderNo': order.orderNo,
  'status': order.status,
  'total': order.total,
};

Expense _expenseFromJson(Map<String, dynamic> json) {
  return Expense(
    id: _int(json, 'id'),
    title: _string(json, 'title'),
    category: _string(json, 'category'),
    amount: _double(json, 'amount'),
  );
}

Map<String, dynamic> _expenseToJson(Expense expense) => {
  'id': expense.id,
  'title': expense.title,
  'category': expense.category,
  'amount': expense.amount,
};

Invoice _invoiceFromJson(Map<String, dynamic> json) {
  return Invoice(
    id: _int(json, 'id'),
    number: _string(json, 'number'),
    customer: _string(json, 'customer'),
    total: _double(json, 'total'),
    paid: _double(json, 'paid'),
    tendered: _double(json, 'tendered'),
    discountAmount: _double(json, 'discountAmount'),
    method: _string(json, 'method'),
    createdAt: DateTime.tryParse(_string(json, 'createdAt')) ?? DateTime.now(),
  );
}

Map<String, dynamic> _invoiceToJson(Invoice invoice) => {
  'id': invoice.id,
  'number': invoice.number,
  'customer': invoice.customer,
  'total': invoice.total,
  'paid': invoice.paid,
  'tendered': invoice.tendered,
  'discountAmount': invoice.discountAmount,
  'method': invoice.method,
  'createdAt': invoice.createdAt.toIso8601String(),
};

InvoiceLine _invoiceLineFromJson(Map<String, dynamic> json) {
  return InvoiceLine(
    product: Product(
      id: _int(json, 'productId'),
      name: _string(json, 'productName'),
      sku: _string(json, 'sku'),
      barcode: _string(json, 'barcode'),
      salePrice: _double(json, 'salePrice'),
      purchasePrice: _double(json, 'purchasePrice'),
      stock: _double(json, 'stock'),
      minStock: _double(json, 'minStock'),
      category: _string(json, 'category'),
      posPriority: _int(json, 'posPriority'),
    ),
    quantity: _double(json, 'quantity'),
  );
}

Map<String, dynamic> _invoiceLineToJson(InvoiceLine line) => {
  'productId': line.product.id,
  'productName': line.product.name,
  'sku': line.product.sku,
  'barcode': line.product.barcode,
  'salePrice': line.product.salePrice,
  'purchasePrice': line.product.purchasePrice,
  'stock': line.product.stock,
  'minStock': line.product.minStock,
  'category': line.product.category,
  'posPriority': line.product.posPriority,
  'quantity': line.quantity,
};

Map<int, List<InvoiceLine>> _invoiceLinesMapFromJson(Object? value) {
  if (value is! Map) return {};
  final result = <int, List<InvoiceLine>>{};
  for (final entry in value.entries) {
    final invoiceId = int.tryParse(entry.key.toString());
    if (invoiceId == null) continue;
    result[invoiceId] = _list(entry.value).map(_invoiceLineFromJson).toList();
  }
  return result;
}

StockMovement _movementFromJson(Map<String, dynamic> json) {
  return StockMovement(
    id: _int(json, 'id'),
    product: _string(json, 'product'),
    type: _string(json, 'type', 'In'),
    quantity: _double(json, 'quantity'),
    notes: _string(json, 'notes'),
  );
}

Map<String, dynamic> _movementToJson(StockMovement movement) => {
  'id': movement.id,
  'product': movement.product,
  'type': movement.type,
  'quantity': movement.quantity,
  'notes': movement.notes,
};

Product _apiProductFromJson(Map<String, dynamic> json) {
  return Product(
    id: _int(json, 'ProductId'),
    name: _string(json, 'Name'),
    sku: _string(json, 'SKU'),
    barcode: _string(json, 'Barcode'),
    salePrice: _double(json, 'SalePrice'),
    purchasePrice: _double(json, 'PurchasePrice'),
    stock: _double(json, 'StockOnHand'),
    minStock: _double(json, 'MinStockLevel'),
    category: _string(json, 'CategoryName', 'General'),
    posPriority: _int(json, 'PosPriority'),
  );
}

Party _apiCustomerFromJson(Map<String, dynamic> json) {
  return Party(
    id: _int(json, 'CustomerId'),
    name: _string(json, 'Name'),
    phone: _string(json, 'Phone', '-'),
    email: _string(json, 'Email'),
    balance: _double(json, 'CreditLimit'),
  );
}

Party _apiSupplierFromJson(Map<String, dynamic> json) {
  return Party(
    id: _int(json, 'SupplierId'),
    name: _string(json, 'Name'),
    phone: _string(json, 'Phone', '-'),
    email: _string(json, 'Email'),
    balance: 0,
  );
}

AppUser _apiUserFromJson(Map<String, dynamic> json) {
  return AppUser(
    id: _int(json, 'UserId'),
    name: _string(json, 'FullName'),
    email: _string(json, 'Email'),
    role: _string(json, 'RoleName', 'Cashier'),
    active: _bool(json, 'IsActive', true),
    branchId: _int(json, 'BranchId', 1),
    branchType: _string(json, 'BranchTypeName', 'Retail'),
  );
}

Invoice _apiInvoiceFromJson(Map<String, dynamic> json) {
  return Invoice(
    id: _int(json, 'InvoiceId'),
    number: _string(json, 'InvoiceNo'),
    customer: _string(json, 'CustomerName', 'Walk-in Customer'),
    total: _double(json, 'Total'),
    paid: _double(json, 'PaidAmount'),
    tendered: _double(json, 'TenderedAmount', _double(json, 'PaidAmount')),
    discountAmount: _double(json, 'DiscountAmount'),
    method: 'SQL',
    createdAt: DateTime.tryParse(_string(json, 'CreatedAt')) ?? DateTime.now(),
  );
}

InvoiceLine _apiInvoiceLineFromJson(Map<String, dynamic> json) {
  return InvoiceLine(
    product: Product(
      id: _int(json, 'ProductId'),
      name: _string(json, 'ProductName'),
      sku: _string(json, 'SKU'),
      barcode: _string(json, 'Barcode'),
      salePrice: _double(json, 'UnitPrice'),
      purchasePrice: 0,
      stock: 0,
      minStock: 0,
      category: '',
      posPriority: 0,
    ),
    quantity: _double(json, 'Quantity'),
  );
}

String? _nullable(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty || trimmed == '-' ? null : trimmed;
}

String _shortError(Object error) {
  final text = error.toString().replaceFirst('HttpException: ', '');
  return text.length > 120 ? '${text.substring(0, 120)}...' : text;
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.barcode,
    required this.salePrice,
    required this.purchasePrice,
    required this.stock,
    required this.minStock,
    required this.category,
    this.posPriority = 0,
  });

  final int id;
  final String name;
  final String sku;
  final String barcode;
  final double salePrice;
  final double purchasePrice;
  final double stock;
  final double minStock;
  final String category;
  final int posPriority;

  Product copyWith({
    int? id,
    String? name,
    String? sku,
    String? barcode,
    double? salePrice,
    double? purchasePrice,
    double? stock,
    double? minStock,
    String? category,
    int? posPriority,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      salePrice: salePrice ?? this.salePrice,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      stock: stock ?? this.stock,
      minStock: minStock ?? this.minStock,
      category: category ?? this.category,
      posPriority: posPriority ?? this.posPriority,
    );
  }
}

Product _withProductCodes(Product product, {required int nextId}) {
  final sku = product.sku.trim().isEmpty
      ? _generateSku(product.name, product.category, nextId)
      : product.sku.trim();
  final barcode = product.barcode.trim().isEmpty
      ? _generateBarcode(nextId)
      : product.barcode.trim();
  return product.copyWith(sku: sku, barcode: barcode);
}

String _generateSku(String name, String category, int id) {
  final categoryPart = _codePart(category, fallback: 'GEN', length: 3);
  final namePart = _codePart(name, fallback: 'PRD', length: 4);
  return '$categoryPart-$namePart-${id.toString().padLeft(5, '0')}';
}

String _codePart(
  String value, {
  required String fallback,
  required int length,
}) {
  final cleaned = value
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
      .trim();
  if (cleaned.isEmpty) return fallback;
  final words = cleaned.split(RegExp(r'\s+'));
  final initials = words.map((word) => word[0]).join();
  final candidate = initials.length >= 2
      ? initials
      : cleaned.replaceAll(' ', '');
  return candidate.padRight(length, 'X').substring(0, length);
}

String _generateBarcode(int id) {
  final base =
      '896${DateTime.now().millisecondsSinceEpoch.toString().substring(5, 11)}${id.toString().padLeft(3, '0')}';
  final digits = base.substring(0, 12);
  return '$digits${_ean13CheckDigit(digits)}';
}

int _ean13CheckDigit(String first12Digits) {
  var sum = 0;
  for (var i = 0; i < first12Digits.length; i++) {
    final digit = int.tryParse(first12Digits[i]) ?? 0;
    sum += i.isEven ? digit : digit * 3;
  }
  return (10 - (sum % 10)) % 10;
}

class Party {
  const Party({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.balance,
  });

  final int id;
  final String name;
  final String phone;
  final String email;
  final double balance;

  Party copyWith({
    int? id,
    String? name,
    String? phone,
    String? email,
    double? balance,
  }) {
    return Party(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      balance: balance ?? this.balance,
    );
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
    this.password = '',
    this.branchId,
    this.branchType = 'Retail',
  });

  final int id;
  final String name;
  final String email;
  final String role;
  final bool active;
  final String password;
  final int? branchId;
  final String branchType;
  String get defaultPassword => password.isNotEmpty
      ? password
      : switch (role) {
          'Admin' => 'Admin@12345',
          'Manager' => 'Manager@12345',
          _ => 'Cashier@12345',
        };
  bool get isAdmin => role == 'Admin';
  bool get isManager => role == 'Manager';
  bool get isCashier => role == 'Cashier';
  bool get canManageUsers => isAdmin;
  bool get canManageFinance => isAdmin;
  bool get canManageCatalog => isAdmin || isManager;
  bool get canManageOperations => isAdmin || isManager;
  bool get canUsePos => isAdmin || isManager || isCashier;
  bool get canViewReports => isAdmin || isManager;

  AppUser copyWith({
    int? id,
    String? name,
    String? email,
    String? role,
    bool? active,
    String? password,
    int? branchId,
    String? branchType,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      active: active ?? this.active,
      password: password ?? this.password,
      branchId: branchId ?? this.branchId,
      branchType: branchType ?? this.branchType,
    );
  }
}

class BranchProfile {
  const BranchProfile({
    required this.id,
    required this.name,
    required this.code,
    required this.type,
  });

  final int id;
  final String name;
  final String code;
  final String type;

  bool get isRestaurant => type.toLowerCase().contains('restaurant');

  BranchProfile copyWith({int? id, String? name, String? code, String? type}) {
    return BranchProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      type: type ?? this.type,
    );
  }

  factory BranchProfile.fromJson(Map<String, dynamic> json) {
    return BranchProfile(
      id: _int(json, 'id', 1),
      name: _string(json, 'name', 'Main Branch'),
      code: _string(json, 'code', 'MAIN'),
      type: _string(json, 'type', 'Retail'),
    );
  }

  factory BranchProfile.fromApi(Map<String, dynamic> json) {
    return BranchProfile(
      id: _int(json, 'BranchId', 1),
      name: _string(json, 'Name', 'Main Branch'),
      code: _string(json, 'Code', 'MAIN'),
      type: _string(
        json,
        'BranchTypeName',
        _string(json, 'TypeName', 'Retail'),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'code': code,
    'type': type,
  };
}

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.supplier,
    required this.orderNo,
    required this.status,
    required this.total,
  });

  final int id;
  final String supplier;
  final String orderNo;
  final String status;
  final double total;

  PurchaseOrder copyWith({
    int? id,
    String? supplier,
    String? orderNo,
    String? status,
    double? total,
  }) {
    return PurchaseOrder(
      id: id ?? this.id,
      supplier: supplier ?? this.supplier,
      orderNo: orderNo ?? this.orderNo,
      status: status ?? this.status,
      total: total ?? this.total,
    );
  }
}

class Expense {
  const Expense({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
  });

  final int id;
  final String title;
  final String category;
  final double amount;

  Expense copyWith({int? id, String? title, String? category, double? amount}) {
    return Expense(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      amount: amount ?? this.amount,
    );
  }
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.product,
    required this.type,
    required this.quantity,
    required this.notes,
  });

  final int id;
  final String product;
  final String type;
  final double quantity;
  final String notes;

  StockMovement copyWith({
    int? id,
    String? product,
    String? type,
    double? quantity,
    String? notes,
  }) {
    return StockMovement(
      id: id ?? this.id,
      product: product ?? this.product,
      type: type ?? this.type,
      quantity: quantity ?? this.quantity,
      notes: notes ?? this.notes,
    );
  }
}

class InvoiceLine {
  const InvoiceLine({required this.product, required this.quantity});

  final Product product;
  final double quantity;
  double get total => product.salePrice * quantity;
}

class SyncJob {
  const SyncJob({
    required this.id,
    required this.type,
    required this.action,
    required this.recordId,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String action;
  final int recordId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  factory SyncJob.fromJson(Map<String, dynamic> json) {
    return SyncJob(
      id: _string(json, 'id'),
      type: _string(json, 'type'),
      action: _string(json, 'action'),
      recordId: _int(json, 'recordId'),
      payload: Map<String, dynamic>.from((json['payload'] as Map?) ?? const {}),
      createdAt:
          DateTime.tryParse(_string(json, 'createdAt')) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'action': action,
    'recordId': recordId,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
  };
}

class Invoice {
  const Invoice({
    required this.id,
    required this.number,
    required this.customer,
    required this.total,
    required this.paid,
    required this.method,
    required this.createdAt,
    this.tendered = 0,
    this.discountAmount = 0,
  });

  final int id;
  final String number;
  final String customer;
  final double total;
  final double paid;
  final double tendered;
  final double discountAmount;
  final String method;
  final DateTime createdAt;
  double get due => total - paid;
  double get changeDue => (tendered - total).clamp(0, 999999999).toDouble();

  Invoice copyWith({
    int? id,
    String? number,
    String? customer,
    double? total,
    double? paid,
    double? tendered,
    double? discountAmount,
    String? method,
    DateTime? createdAt,
  }) {
    return Invoice(
      id: id ?? this.id,
      number: number ?? this.number,
      customer: customer ?? this.customer,
      total: total ?? this.total,
      paid: paid ?? this.paid,
      tendered: tendered ?? this.tendered,
      discountAmount: discountAmount ?? this.discountAmount,
      method: method ?? this.method,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class ModuleDef {
  const ModuleDef({
    required this.title,
    required this.icon,
    required this.builder,
    required this.allowed,
  });

  final String title;
  final IconData icon;
  final WidgetBuilder builder;
  final bool Function(AppUser user) allowed;
}

class UserScope extends InheritedWidget {
  const UserScope({super.key, required this.user, required super.child});

  final AppUser user;

  static AppUser of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<UserScope>();
    return scope!.user;
  }

  @override
  bool updateShouldNotify(UserScope oldWidget) => oldWidget.user != user;
}

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 64, this.showText = true});

  final double size;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size.square(size),
          painter: _BrandMarkPainter(
            colors.primary,
            const Color(0xFF1B365D),
            const Color(0xFFF59E0B),
          ),
        ),
        if (showText) ...[
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'InvPro',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              Text(
                'POS-INV-MSSQL',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter(this.green, this.ink, this.gold);

  final Color green;
  final Color ink;
  final Color gold;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 64;
    final radius = Radius.circular(14 * scale);
    final rect = Offset.zero & size;
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [ink, green],
      ).createShader(rect);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), background);

    final shelfPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(16 * scale, 42 * scale)
      ..lineTo(16 * scale, 24 * scale)
      ..lineTo(30 * scale, 16 * scale)
      ..lineTo(48 * scale, 24 * scale)
      ..lineTo(48 * scale, 42 * scale)
      ..lineTo(16 * scale, 42 * scale);
    canvas.drawPath(path, shelfPaint);

    final barPaint = Paint()..color = gold;
    canvas.drawRRect(
      RRect.fromLTRBR(
        22 * scale,
        29 * scale,
        42 * scale,
        35 * scale,
        Radius.circular(3 * scale),
      ),
      barPaint,
    );
    canvas.drawCircle(
      Offset(48 * scale, 18 * scale),
      4.2 * scale,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter oldDelegate) =>
      oldDelegate.green != green ||
      oldDelegate.ink != ink ||
      oldDelegate.gold != gold;
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFC), Color(0xFFE8F4EF), Color(0xFFFFF7E6)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandLogo(size: 84),
              const SizedBox(height: 28),
              SizedBox(
                width: 180,
                child: LinearProgressIndicator(
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLogin});

  final ValueChanged<AppUser> onLogin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(text: 'admin@invpro.local');
  final password = TextEditingController(text: 'Admin@12345');
  bool obscure = true;
  bool loggingIn = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFC), Color(0xFFEAF5F0), Color(0xFFFFF5DE)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 8,
                shadowColor: const Color(0xFF0F172A).withValues(alpha: .12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: BrandLogo(size: 58)),
                      const SizedBox(height: 22),
                      Text(
                        'Sign in to continue',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Secure retail operations console',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: email,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.mail_outline),
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _login(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: password,
                        obscureText: obscure,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                          labelText: 'Password',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _login(),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: loggingIn ? null : _login,
                        icon: loggingIn
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(loggingIn ? 'Connecting...' : 'Login'),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('Admin'),
                            onPressed: () =>
                                _fill('admin@invpro.local', 'Admin@12345'),
                          ),
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('Manager'),
                            onPressed: () =>
                                _fill('manager@invpro.local', 'Manager@12345'),
                          ),
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('Cashier'),
                            onPressed: () =>
                                _fill('cashier@invpro.local', 'Cashier@12345'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _fill(String nextEmail, String nextPassword) {
    setState(() {
      email.text = nextEmail;
      password.text = nextPassword;
    });
  }

  Future<void> _login() async {
    setState(() => loggingIn = true);
    final store = StoreScope.of(context);
    final user = await store.login(email.text, password.text);
    if (!mounted) return;
    setState(() => loggingIn = false);
    if (user == null) {
      _showMessage(context, 'Invalid email, password, or disabled user');
      return;
    }
    _showMessage(context, store.syncStatus);
    widget.onLogin(user);
  }
}

class ShellPage extends StatefulWidget {
  const ShellPage({
    super.key,
    required this.user,
    required this.isDark,
    required this.onThemeChanged,
    required this.onLogout,
  });

  final AppUser user;
  final bool isDark;
  final VoidCallback onThemeChanged;
  final VoidCallback onLogout;

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int selected = 0;
  final allModules = <ModuleDef>[
    ModuleDef(
      title: 'Dashboard',
      icon: Icons.dashboard_outlined,
      builder: (_) => const DashboardView(),
      allowed: (_) => true,
    ),
    ModuleDef(
      title: 'POS',
      icon: Icons.point_of_sale_outlined,
      builder: (_) => const PosView(),
      allowed: (user) => user.canUsePos,
    ),
    ModuleDef(
      title: 'Products',
      icon: Icons.inventory_2_outlined,
      builder: (_) => const ProductsView(),
      allowed: (user) => user.canManageCatalog,
    ),
    ModuleDef(
      title: 'Inventory',
      icon: Icons.warehouse_outlined,
      builder: (_) => const InventoryView(),
      allowed: (user) => user.canManageOperations,
    ),
    ModuleDef(
      title: 'Purchases',
      icon: Icons.shopping_cart_checkout_outlined,
      builder: (_) => const PurchasesView(),
      allowed: (user) => user.canManageOperations,
    ),
    ModuleDef(
      title: 'Customers',
      icon: Icons.groups_outlined,
      builder: (_) => const PartiesView(kind: PartyKind.customer),
      allowed: (_) => true,
    ),
    ModuleDef(
      title: 'Suppliers',
      icon: Icons.local_shipping_outlined,
      builder: (_) => const PartiesView(kind: PartyKind.supplier),
      allowed: (user) => user.canManageOperations,
    ),
    ModuleDef(
      title: 'Finance',
      icon: Icons.account_balance_wallet_outlined,
      builder: (_) => const FinanceView(),
      allowed: (user) => user.canManageFinance,
    ),
    ModuleDef(
      title: 'Reports',
      icon: Icons.analytics_outlined,
      builder: (_) => const ReportsView(),
      allowed: (user) => user.canViewReports,
    ),
    ModuleDef(
      title: 'Users',
      icon: Icons.admin_panel_settings_outlined,
      builder: (_) => const UsersView(),
      allowed: (user) => user.canManageUsers,
    ),
    ModuleDef(
      title: 'Settings',
      icon: Icons.settings_outlined,
      builder: (_) => const SettingsView(),
      allowed: (user) => user.isAdmin,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final store = StoreScope.of(context);
    final cashierMode = widget.user.isCashier;
    final modules = cashierMode
        ? allModules.where((module) => module.title == 'POS').toList()
        : allModules.where((module) => module.allowed(widget.user)).toList();
    if (selected >= modules.length) selected = 0;
    return UserScope(
      user: widget.user,
      child: Scaffold(
        body: Row(
          children: [
            if (wide && !cashierMode)
              NavigationRail(
                extended: MediaQuery.sizeOf(context).width >= 1280,
                selectedIndex: selected,
                onDestinationSelected: (value) =>
                    setState(() => selected = value),
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Tooltip(
                    message: '${widget.user.name} (${widget.user.role})',
                    child: CircleAvatar(
                      child: Text(widget.user.role.substring(0, 1)),
                    ),
                  ),
                ),
                destinations: [
                  for (final module in modules)
                    NavigationRailDestination(
                      icon: Icon(module.icon),
                      label: Text(module.title),
                    ),
                ],
              ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    automaticallyImplyLeading: false,
                    title: Text(modules[selected].title),
                    actions: [
                      if (!cashierMode)
                        IconButton(
                          tooltip: 'Scan barcode',
                          onPressed: () =>
                              _showMessage(context, 'Barcode scan ready'),
                          icon: const Icon(Icons.qr_code_scanner_outlined),
                        ),
                      if (!cashierMode)
                        IconButton(
                          tooltip: 'Toggle theme',
                          onPressed: widget.onThemeChanged,
                          icon: Icon(
                            widget.isDark
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Tooltip(
                          message: store.syncStatus,
                          child: Chip(
                            avatar: Icon(
                              store.sqlConnected
                                  ? Icons.storage_outlined
                                  : Icons.save_outlined,
                              size: 18,
                            ),
                            label: Text(
                              store.pendingSyncJobs.isEmpty
                                  ? (store.sqlConnected ? 'SQL' : 'Local')
                                  : 'Sync ${store.pendingSyncJobs.length}',
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sync pending records',
                        onPressed: store.pendingSyncJobs.isEmpty
                            ? null
                            : () => unawaited(store.tryReconnectAndSync()),
                        icon: const Icon(Icons.cloud_sync_outlined),
                      ),
                      Chip(
                        avatar: const Icon(Icons.person_outline, size: 18),
                        label: Text(
                          cashierMode ? widget.user.name : widget.user.role,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Change password',
                        onPressed: () =>
                            _openChangePasswordDialog(context, widget.user),
                        icon: const Icon(Icons.lock_reset_outlined),
                      ),
                      IconButton(
                        tooltip: 'Logout',
                        onPressed: widget.onLogout,
                        icon: const Icon(Icons.logout),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverToBoxAdapter(
                      child: modules[selected].builder(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: wide || cashierMode
            ? null
            : SafeArea(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var index = 0; index < modules.length; index++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          child: ChoiceChip(
                            selected: selected == index,
                            avatar: Icon(modules[index].icon, size: 18),
                            label: Text(modules[index].title),
                            onSelected: (_) => setState(() => selected = index),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final money = intl.NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
    final recentInvoices = store.invoices
        .take(4)
        .map(
          (invoice) => [
            invoice.number,
            invoice.customer,
            invoice.due <= 0 ? 'Paid' : money.format(invoice.due),
          ],
        )
        .toList();
    final lowStock = store.products
        .where((product) => product.stock <= product.minStock)
        .take(4)
        .map(
          (product) => [
            product.name,
            product.stock.toStringAsFixed(0),
            product.category,
          ],
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            StatTile(
              label: "Today's sales",
              value: money.format(store.todaysSales),
              icon: Icons.payments_outlined,
              accent: const Color(0xFF0E7C66),
            ),
            StatTile(
              label: 'Low stock',
              value: '${store.lowStockCount}',
              icon: Icons.warning_amber_outlined,
              accent: const Color(0xFFD97706),
            ),
            StatTile(
              label: 'Out of stock',
              value: '${store.outOfStockCount}',
              icon: Icons.remove_shopping_cart_outlined,
              accent: const Color(0xFFDC2626),
            ),
            StatTile(
              label: 'Pending dues',
              value: money.format(store.pendingDues),
              icon: Icons.receipt_long_outlined,
              accent: const Color(0xFF2563EB),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ResponsiveColumns(
          left: DataPanel(
            title: 'Low stock products',
            rows: lowStock.isEmpty
                ? const [
                    ['No low stock items', '-', 'OK'],
                  ]
                : lowStock,
          ),
          right: DataPanel(
            title: 'Recent invoices',
            rows: recentInvoices.isEmpty
                ? const [
                    ['No invoices posted yet', '-', '-'],
                  ]
                : recentInvoices,
          ),
        ),
      ],
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 118,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: accent.withValues(alpha: .13),
                foregroundColor: accent,
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PosView extends StatefulWidget {
  const PosView({super.key});

  @override
  State<PosView> createState() => _PosViewState();
}

class _PosViewState extends State<PosView> {
  final search = TextEditingController();
  final amountPaid = TextEditingController();
  final searchFocus = FocusNode();
  final List<InvoiceLine> cart = [];
  String paymentMethod = 'Cash';
  String customer = 'Walk-in Customer';
  double discountAmount = 0;
  int selectedLineIndex = 0;

  @override
  void dispose() {
    search.dispose();
    amountPaid.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final money = intl.NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
    final subtotal = cart.fold(0.0, (sum, line) => sum + line.total);
    final discount = discountAmount.clamp(0, subtotal).toDouble();
    final total = (subtotal - discount).clamp(0, 999999999).toDouble();
    final paidInput = _num(amountPaid);
    final tendered = paymentMethod == 'Credit'
        ? 0.0
        : (paidInput <= 0 ? total : paidInput);
    final changeDue = paymentMethod == 'Credit'
        ? 0.0
        : (tendered - total).clamp(0, 999999999).toDouble();
    final balanceDue = paymentMethod == 'Credit'
        ? total
        : (total - tendered).clamp(0, 999999999).toDouble();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () =>
            unawaited(_openItemPicker(store)),
        const SingleActivator(LogicalKeyboardKey.f3): () => _addBySearch(store),
        const SingleActivator(LogicalKeyboardKey.f4): () =>
            unawaited(_openDiscountDialog(subtotal)),
        const SingleActivator(LogicalKeyboardKey.f6): () =>
            _changeSelectedQuantity(-1),
        const SingleActivator(LogicalKeyboardKey.f7): () =>
            _changeSelectedQuantity(1),
        const SingleActivator(LogicalKeyboardKey.f8): () {
          if (cart.isNotEmpty) _postInvoice(store, total, tendered);
        },
        const SingleActivator(LogicalKeyboardKey.f9): () {
          if (cart.isNotEmpty)
            _postInvoice(store, total, tendered, printAfterPost: true);
        },
        const SingleActivator(LogicalKeyboardKey.delete): _removeSelectedLine,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          search.clear();
          _focusSearch();
        },
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final tablet = constraints.maxWidth >= 700;
            final runsAndroid = !kIsWeb && Platform.isAndroid;
            final runsWindows = !kIsWeb && Platform.isWindows;
            final restaurantMenuMode =
                (kIsWeb || runsAndroid || runsWindows) &&
                tablet &&
                store.activeBranch.isRestaurant;
            final quickProducts = _posProducts(
              store,
              windowsDesktopOnly: runsWindows && wide,
              menuMode: restaurantMenuMode,
            );
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: wide
                      ? (constraints.maxWidth - 16) * .62
                      : constraints.maxWidth,
                  child: AppPanel(
                    title: 'Sell items',
                    horizontalScroll: false,
                    action: IconButton(
                      tooltip: 'Clear bill',
                      onPressed: cart.isEmpty ? null : _clearCart,
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                    child: Column(
                      children: [
                        if (!restaurantMenuMode) ...[
                          TextField(
                            controller: search,
                            focusNode: searchFocus,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(
                                Icons.qr_code_scanner_outlined,
                              ),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Pick item (F2)',
                                    onPressed: () =>
                                        unawaited(_openItemPicker(store)),
                                    icon: const Icon(Icons.list_alt_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Add item (F3)',
                                    onPressed: () => _addBySearch(store),
                                    icon: const Icon(
                                      Icons.add_shopping_cart_outlined,
                                    ),
                                  ),
                                ],
                              ),
                              labelText: 'Scan barcode, SKU, or product name',
                              border: const OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _addBySearch(store),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (restaurantMenuMode)
                          _RestaurantMenuGrid(
                            products: quickProducts,
                            money: money,
                            onAdd: _addProduct,
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final product in quickProducts)
                                ActionChip(
                                  avatar: const Icon(Icons.add, size: 18),
                                  label: Text(product.name),
                                  onPressed: product.stock <= 0
                                      ? null
                                      : () => _addProduct(product),
                                ),
                            ],
                          ),
                        if (!restaurantMenuMode) ...[
                          const SizedBox(height: 16),
                          _CartTable(
                            cart: cart,
                            money: money,
                            selectedLineIndex: selectedLineIndex,
                            onSelectLine: (index) =>
                                setState(() => selectedLineIndex = index),
                            onChangeQuantity: _changeLineQuantity,
                            onRemoveLine: _removeLine,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: wide
                      ? (constraints.maxWidth - 16) * .38
                      : constraints.maxWidth,
                  child: AppPanel(
                    title: 'Payment',
                    horizontalScroll: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (restaurantMenuMode) ...[
                          Text(
                            'Added items',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          _CartTable(
                            cart: cart,
                            money: money,
                            selectedLineIndex: selectedLineIndex,
                            onSelectLine: (index) =>
                                setState(() => selectedLineIndex = index),
                            onChangeQuantity: _changeLineQuantity,
                            onRemoveLine: _removeLine,
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                        ] else ...[
                          DropdownButtonFormField<String>(
                            initialValue: customer,
                            decoration: const InputDecoration(
                              labelText: 'Customer',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final party in store.customers)
                                DropdownMenuItem(
                                  value: party.name,
                                  child: Text(party.name),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => customer = value ?? customer),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TotalRow(
                          label: 'Subtotal',
                          value: money.format(subtotal),
                        ),
                        TotalRow(
                          label: 'Discount (F4)',
                          value: money.format(discount),
                          action: IconButton(
                            tooltip: 'Set discount (F4)',
                            onPressed: cart.isEmpty
                                ? null
                                : () =>
                                      unawaited(_openDiscountDialog(subtotal)),
                            icon: const Icon(Icons.percent_outlined),
                          ),
                        ),
                        const TotalRow(label: 'VAT/GST', value: 'PKR 0'),
                        const Divider(height: 28),
                        TotalRow(
                          label: 'Grand total',
                          value: money.format(total),
                          strong: true,
                        ),
                        const SizedBox(height: 16),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'Cash',
                              icon: Icon(Icons.payments_outlined),
                              label: Text('Cash'),
                            ),
                            ButtonSegment(
                              value: 'Card',
                              icon: Icon(Icons.credit_card),
                              label: Text('Card'),
                            ),
                            ButtonSegment(
                              value: 'Credit',
                              icon: Icon(Icons.schedule_outlined),
                              label: Text('Credit'),
                            ),
                          ],
                          selected: {paymentMethod},
                          onSelectionChanged: (value) {
                            setState(() {
                              paymentMethod = value.first;
                              if (paymentMethod == 'Credit') amountPaid.clear();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: amountPaid,
                          enabled: paymentMethod != 'Credit',
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.payments_outlined),
                            labelText: paymentMethod == 'Cash'
                                ? 'Cash received from customer'
                                : 'Amount paid by customer',
                            hintText: total > 0
                                ? total.toStringAsFixed(0)
                                : '0',
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        TotalRow(
                          label: 'Paid amount',
                          value: money.format(tendered),
                        ),
                        TotalRow(
                          label: paymentMethod == 'Credit'
                              ? 'Balance due'
                              : 'Return change',
                          value: money.format(
                            paymentMethod == 'Credit' ? balanceDue : changeDue,
                          ),
                          strong: changeDue > 0 || balanceDue > 0,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: cart.isEmpty
                              ? null
                              : () => _postInvoice(store, total, tendered),
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: const Text('Post invoice (F8)'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: cart.isEmpty
                              ? null
                              : () => _postInvoice(
                                  store,
                                  total,
                                  tendered,
                                  printAfterPost: true,
                                ),
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Post & print (F9)'),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => _openPrinterDialog(store),
                          icon: const Icon(Icons.settings_outlined),
                          label: Text(
                            store.receiptPrinterName.isEmpty
                                ? 'Printer: Windows default'
                                : 'Printer: ${store.receiptPrinterName}',
                          ),
                        ),
                        if (!restaurantMenuMode) ...[
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          Text(
                            'Recent invoices',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          for (final invoice in store.invoices.take(5))
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.receipt_long_outlined),
                              title: Text(invoice.number),
                              subtitle: Text(
                                '${invoice.customer}  |  ${money.format(invoice.total)}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Open PDF',
                                    onPressed: () => unawaited(
                                      _openInvoicePdf(store, invoice),
                                    ),
                                    icon: const Icon(
                                      Icons.picture_as_pdf_outlined,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Duplicate reprint',
                                    onPressed: () => unawaited(
                                      _reprintInvoice(store, invoice),
                                    ),
                                    icon: const Icon(Icons.print_outlined),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Product> _posProducts(
    AppStore store, {
    required bool windowsDesktopOnly,
    required bool menuMode,
  }) {
    if (!windowsDesktopOnly && !menuMode) return store.products;
    final products =
        store.products.where((product) => product.stock > 0).toList()..sort((
          a,
          b,
        ) {
          final priorityCompare = _priorityRank(a).compareTo(_priorityRank(b));
          if (priorityCompare != 0) return priorityCompare;
          return a.name.compareTo(b.name);
        });
    if (windowsDesktopOnly) return products.take(10).toList();
    if (menuMode)
      return products.where((product) => product.posPriority > 0).toList();
    return products;
  }

  int _priorityRank(Product product) =>
      product.posPriority <= 0 ? 999999 : product.posPriority;

  void _focusSearch() {
    searchFocus.requestFocus();
    search.selection = TextSelection(
      baseOffset: 0,
      extentOffset: search.text.length,
    );
  }

  void _clearCart() {
    setState(() {
      cart.clear();
      amountPaid.clear();
      discountAmount = 0;
      selectedLineIndex = 0;
    });
    _focusSearch();
  }

  void _changeSelectedQuantity(double delta) {
    if (cart.isEmpty) return;
    _changeLineQuantity(selectedLineIndex.clamp(0, cart.length - 1), delta);
  }

  void _changeLineQuantity(int index, double delta) {
    if (index < 0 || index >= cart.length) return;
    final line = cart[index];
    final nextQuantity = line.quantity + delta;
    if (nextQuantity < 1) {
      _removeLine(index);
      return;
    }
    if (nextQuantity > line.product.stock) {
      _showMessage(
        context,
        'Only ${line.product.stock.toStringAsFixed(0)} in stock',
      );
      return;
    }
    setState(() {
      selectedLineIndex = index;
      cart[index] = InvoiceLine(product: line.product, quantity: nextQuantity);
    });
  }

  void _removeSelectedLine() {
    if (cart.isEmpty) return;
    _removeLine(selectedLineIndex.clamp(0, cart.length - 1));
  }

  void _removeLine(int index) {
    if (index < 0 || index >= cart.length) return;
    setState(() {
      cart.removeAt(index);
      if (cart.isEmpty) {
        selectedLineIndex = 0;
        discountAmount = 0;
      } else {
        selectedLineIndex = selectedLineIndex.clamp(0, cart.length - 1);
      }
    });
  }

  Future<void> _openDiscountDialog(double subtotal) async {
    if (cart.isEmpty) return;
    final controller = TextEditingController(
      text: discountAmount.toStringAsFixed(0),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Set discount'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Discount amount',
              helperText:
                  'Maximum ${intl.NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0).format(subtotal)}',
            ),
            onSubmitted: (_) => Navigator.pop(
              dialogContext,
              double.tryParse(controller.text.trim()) ?? 0,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                double.tryParse(controller.text.trim()) ?? 0,
              ),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (value == null || !mounted) return;
    setState(() => discountAmount = value.clamp(0, subtotal).toDouble());
  }

  Future<void> _openItemPicker(AppStore store) async {
    final filter = TextEditingController(text: search.text.trim());
    final money = intl.NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
    Product? selected;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final term = filter.text.trim().toLowerCase();
            final products = store.products.where((product) {
              if (product.stock <= 0) return false;
              if (term.isEmpty) return true;
              return product.name.toLowerCase().contains(term) ||
                  product.sku.toLowerCase().contains(term) ||
                  product.barcode.toLowerCase().contains(term);
            }).toList()..sort((a, b) => a.name.compareTo(b.name));
            return AlertDialog(
              title: const Text('Select item'),
              content: SizedBox(
                width: 620,
                height: 520,
                child: Column(
                  children: [
                    TextField(
                      controller: filter,
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search by name, SKU, or barcode',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      onSubmitted: (_) {
                        if (products.isNotEmpty) {
                          selected = products.first;
                          Navigator.pop(dialogContext);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: products.isEmpty
                          ? const Center(child: Text('No available item found'))
                          : ListView.separated(
                              itemCount: products.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final product = products[index];
                                return ListTile(
                                  leading: const Icon(
                                    Icons.inventory_2_outlined,
                                  ),
                                  title: Text(product.name),
                                  subtitle: Text(
                                    '${product.sku}  |  Stock ${product.stock.toStringAsFixed(0)}  |  ${product.category}',
                                  ),
                                  trailing: Text(
                                    money.format(product.salePrice),
                                  ),
                                  onTap: () {
                                    selected = product;
                                    Navigator.pop(dialogContext);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
    filter.dispose();
    if (selected == null || !mounted) return;
    _addProduct(selected!);
    search.clear();
    _focusSearch();
  }

  void _addBySearch(AppStore store) {
    final term = search.text.trim().toLowerCase();
    if (term.isEmpty) return;
    final matches = store.products.where((product) {
      return product.name.toLowerCase().contains(term) ||
          product.sku.toLowerCase() == term ||
          product.barcode.toLowerCase() == term;
    });
    if (matches.isNotEmpty) {
      _addProduct(matches.first);
      search.clear();
    } else {
      _showMessage(context, 'Product not found');
    }
  }

  void _addProduct(Product product) {
    if (product.stock <= 0) {
      _showMessage(context, 'Item is out of stock');
      return;
    }
    final index = cart.indexWhere((line) => line.product.id == product.id);
    if (index != -1 && cart[index].quantity + 1 > product.stock) {
      setState(() => selectedLineIndex = index);
      _showMessage(
        context,
        'Only ${product.stock.toStringAsFixed(0)} in stock',
      );
      return;
    }
    setState(() {
      if (index == -1) {
        cart.add(InvoiceLine(product: product, quantity: 1));
        selectedLineIndex = cart.length - 1;
      } else {
        cart[index] = InvoiceLine(
          product: product,
          quantity: cart[index].quantity + 1,
        );
        selectedLineIndex = index;
      }
    });
  }

  void _postInvoice(
    AppStore store,
    double total,
    double tendered, {
    bool printAfterPost = false,
  }) {
    final lines = List<InvoiceLine>.of(cart);
    final paid = paymentMethod == 'Credit'
        ? 0.0
        : tendered.clamp(0, total).toDouble();
    final invoice = store.postInvoice(
      customer: customer,
      lines: lines,
      method: paymentMethod,
      paid: paid,
      tendered: paymentMethod == 'Credit' ? 0 : tendered,
      discountAmount: discountAmount,
    );
    setState(() {
      cart.clear();
      amountPaid.clear();
      discountAmount = 0;
      selectedLineIndex = 0;
    });
    if (printAfterPost) {
      unawaited(
        _printInvoiceDirect(
          context,
          invoice,
          lines,
          printerName: store.receiptPrinterName,
        ),
      );
    } else {
      _showMessage(context, 'Invoice ${invoice.number} posted');
    }
  }

  Future<void> _reprintInvoice(AppStore store, Invoice invoice) async {
    try {
      final lines = await store.invoiceLinesFor(invoice);
      if (!mounted) return;
      if (lines.isEmpty) {
        _showMessage(context, 'No item details found for ${invoice.number}');
        return;
      }
      await _printInvoiceDirect(
        context,
        invoice,
        lines,
        printerName: store.receiptPrinterName,
        duplicate: true,
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(context, 'Reprint failed: ${_shortError(error)}');
    }
  }

  Future<void> _openInvoicePdf(AppStore store, Invoice invoice) async {
    try {
      final lines = await store.invoiceLinesFor(invoice);
      if (!mounted) return;
      if (lines.isEmpty) {
        _showMessage(context, 'No item details found for ${invoice.number}');
        return;
      }
      await _exportInvoice(context, invoice, lines, printAfterExport: false);
    } catch (error) {
      if (!mounted) return;
      _showMessage(context, 'Invoice PDF failed: ${_shortError(error)}');
    }
  }

  Future<void> _openPrinterDialog(AppStore store) async {
    final controller = TextEditingController(text: store.receiptPrinterName);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Receipt printer'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.print_outlined),
              labelText: 'Windows printer name',
              helperText: 'Leave empty to use the Windows default printer',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => Navigator.pop(dialogContext, controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, ''),
              child: const Text('Use default'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (value == null || !mounted) return;
    await store.saveReceiptPrinterName(value);
    if (!mounted) return;
    _showMessage(context, store.syncStatus);
  }
}

class _CartTable extends StatelessWidget {
  const _CartTable({
    required this.cart,
    required this.money,
    required this.selectedLineIndex,
    required this.onSelectLine,
    required this.onChangeQuantity,
    required this.onRemoveLine,
  });

  final List<InvoiceLine> cart;
  final intl.NumberFormat money;
  final int selectedLineIndex;
  final ValueChanged<int> onSelectLine;
  final void Function(int index, double delta) onChangeQuantity;
  final ValueChanged<int> onRemoveLine;

  @override
  Widget build(BuildContext context) {
    if (cart.isEmpty) {
      return const SizedBox(
        height: 72,
        child: Center(child: Text('No items added')),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Item')),
          DataColumn(label: Text('Qty'), numeric: true),
          DataColumn(label: Text('Total'), numeric: true),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (var index = 0; index < cart.length; index++)
            _cartRow(context, index, cart[index]),
        ],
      ),
    );
  }

  DataRow _cartRow(BuildContext context, int index, InvoiceLine line) {
    return DataRow(
      selected: selectedLineIndex == index,
      onSelectChanged: (_) => onSelectLine(index),
      cells: [
        DataCell(
          SizedBox(
            width: 180,
            child: Text(
              line.product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Qty - (F6)',
                onPressed: () => onChangeQuantity(index, -1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  line.quantity.toStringAsFixed(0),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: 'Qty + (F7)',
                onPressed: () => onChangeQuantity(index, 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
        DataCell(Text(money.format(line.total))),
        DataCell(
          IconButton(
            tooltip: 'Remove item (Delete)',
            onPressed: () => onRemoveLine(index),
            icon: const Icon(Icons.close),
          ),
        ),
      ],
    );
  }
}

class _RestaurantMenuGrid extends StatelessWidget {
  const _RestaurantMenuGrid({
    required this.products,
    required this.money,
    required this.onAdd,
  });

  final List<Product> products;
  final intl.NumberFormat money;
  final ValueChanged<Product> onAdd;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const SizedBox(
        height: 96,
        child: Center(
          child: Text('No menu items configured for this branch type'),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        mainAxisExtent: 96,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return FilledButton.tonal(
          onPressed: product.stock <= 0 ? null : () => onAdd(product),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.all(10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.centerLeft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                money.format(product.salePrice),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}

class ProductsView extends StatelessWidget {
  const ProductsView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final user = _currentUser(context);
    final money = intl.NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
    return AppPanel(
      title: 'Product Management',
      action: FilledButton.icon(
        onPressed: user.canManageCatalog
            ? () => _openProductDialog(context)
            : null,
        icon: const Icon(Icons.add),
        label: const Text('New product'),
      ),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Product')),
          DataColumn(label: Text('SKU')),
          DataColumn(label: Text('POS priority'), numeric: true),
          DataColumn(label: Text('Stock'), numeric: true),
          DataColumn(label: Text('Price'), numeric: true),
          DataColumn(label: Text('Actions')),
        ],
        rows: [
          for (final product in store.products)
            DataRow(
              cells: [
                DataCell(Text(product.name)),
                DataCell(Text(product.sku)),
                DataCell(
                  Text(
                    product.posPriority <= 0
                        ? '-'
                        : product.posPriority.toString(),
                  ),
                ),
                DataCell(Text(product.stock.toStringAsFixed(0))),
                DataCell(Text(money.format(product.salePrice))),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Print barcode label',
                        onPressed: () => _printBarcodeLabel(context, product),
                        icon: const Icon(Icons.qr_code_2_outlined),
                      ),
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: user.canManageCatalog
                            ? () =>
                                  _openProductDialog(context, product: product)
                            : null,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: user.isAdmin
                            ? () => store.deleteProduct(product.id)
                            : null,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class InventoryView extends StatelessWidget {
  const InventoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final user = _currentUser(context);
    return ResponsiveColumns(
      left: AppPanel(
        title: 'Stock balances',
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: user.canManageOperations
                  ? () => _repairStock(context)
                  : null,
              icon: const Icon(Icons.healing_outlined),
              label: const Text('Repair stock'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: user.canManageOperations
                  ? () => _openStockDialog(context)
                  : null,
              icon: const Icon(Icons.sync_alt),
              label: const Text('Stock move'),
            ),
          ],
        ),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Product')),
            DataColumn(label: Text('Stock'), numeric: true),
            DataColumn(label: Text('Min'), numeric: true),
            DataColumn(label: Text('Status')),
          ],
          rows: [
            for (final product in store.products)
              DataRow(
                cells: [
                  DataCell(Text(product.name)),
                  DataCell(Text(product.stock.toStringAsFixed(0))),
                  DataCell(Text(product.minStock.toStringAsFixed(0))),
                  DataCell(
                    StatusPill(
                      label: product.stock <= product.minStock ? 'Low' : 'OK',
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      right: DataPanel(
        title: 'Stock formula',
        rows: [
          ['Entered stock', 'StockIn / Opening / Return', 'Added'],
          ['Sold stock', 'Posted invoices', 'Subtracted'],
          ['On-hold stock', 'Hold invoices', 'Subtracted'],
          ['Available stock', 'Entered - Sold - Hold', 'Current'],
        ],
      ),
    );
  }
}

class PurchasesView extends StatelessWidget {
  const PurchasesView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final user = _currentUser(context);
    final money = intl.NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
    return AppPanel(
      title: 'Purchase Management',
      action: FilledButton.icon(
        onPressed: user.canManageOperations
            ? () => _openPurchaseDialog(context)
            : null,
        icon: const Icon(Icons.add),
        label: const Text('New PO'),
      ),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Order')),
          DataColumn(label: Text('Supplier')),
          DataColumn(label: Text('Total'), numeric: true),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: [
          for (final order in store.purchases)
            DataRow(
              cells: [
                DataCell(Text(order.orderNo)),
                DataCell(Text(order.supplier)),
                DataCell(Text(money.format(order.total))),
                DataCell(StatusPill(label: order.status)),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: user.canManageOperations
                            ? () => _openPurchaseDialog(context, order: order)
                            : null,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Receive',
                        onPressed:
                            user.canManageOperations &&
                                order.status != 'Received'
                            ? () => store.receivePurchase(order)
                            : null,
                        icon: const Icon(Icons.download_done_outlined),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

enum PartyKind { customer, supplier }

class PartiesView extends StatelessWidget {
  const PartiesView({super.key, required this.kind});

  final PartyKind kind;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final user = _currentUser(context);
    final list = kind == PartyKind.customer ? store.customers : store.suppliers;
    final title = kind == PartyKind.customer
        ? 'Customer CRM'
        : 'Supplier Ledger';
    final button = kind == PartyKind.customer ? 'New customer' : 'New supplier';
    final money = intl.NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
    return AppPanel(
      title: title,
      action: FilledButton.icon(
        onPressed: _canEditParty(user, kind)
            ? () => _openPartyDialog(context, kind: kind)
            : null,
        icon: const Icon(Icons.add),
        label: Text(button),
      ),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Phone')),
          DataColumn(label: Text('Email')),
          DataColumn(label: Text('Balance'), numeric: true),
          DataColumn(label: Text('Actions')),
        ],
        rows: [
          for (final party in list)
            DataRow(
              cells: [
                DataCell(Text(party.name)),
                DataCell(Text(party.phone)),
                DataCell(Text(party.email.isEmpty ? '-' : party.email)),
                DataCell(Text(money.format(party.balance))),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: _canEditParty(user, kind)
                            ? () => _openPartyDialog(
                                context,
                                kind: kind,
                                party: party,
                              )
                            : null,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: user.isAdmin
                            ? () => store.deleteParty(list, party.id)
                            : null,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class FinanceView extends StatelessWidget {
  const FinanceView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final money = intl.NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
    final totalExpense = store.expenses.fold(
      0.0,
      (sum, expense) => sum + expense.amount,
    );
    return ResponsiveColumns(
      left: AppPanel(
        title: 'Expenses',
        action: FilledButton.icon(
          onPressed: () => _openExpenseDialog(context),
          icon: const Icon(Icons.add),
          label: const Text('New expense'),
        ),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Title')),
            DataColumn(label: Text('Category')),
            DataColumn(label: Text('Amount'), numeric: true),
            DataColumn(label: Text('Actions')),
          ],
          rows: [
            for (final expense in store.expenses)
              DataRow(
                cells: [
                  DataCell(Text(expense.title)),
                  DataCell(Text(expense.category)),
                  DataCell(Text(money.format(expense.amount))),
                  DataCell(
                    IconButton(
                      tooltip: 'Edit',
                      onPressed: () =>
                          _openExpenseDialog(context, expense: expense),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      right: AppPanel(
        title: 'Finance summary',
        child: Column(
          children: [
            TotalRow(
              label: 'Sales',
              value: money.format(
                store.invoices.fold(0.0, (sum, invoice) => sum + invoice.total),
              ),
            ),
            TotalRow(label: 'Expenses', value: money.format(totalExpense)),
            TotalRow(
              label: 'Receivables',
              value: money.format(store.pendingDues),
            ),
            const Divider(height: 28),
            TotalRow(
              label: 'Cash received',
              value: money.format(
                store.invoices.fold(0.0, (sum, invoice) => sum + invoice.paid),
              ),
              strong: true,
            ),
          ],
        ),
      ),
    );
  }
}

class ReportsView extends StatelessWidget {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    final reports = const [
      'Sales',
      'Purchases',
      'Profit',
      'Stock',
      'Low stock',
      'Expiry',
      'Barcode',
      'Tax',
      'Customers',
      'Suppliers',
      'Inventory valuation',
    ];
    final selectedReport = ValueNotifier<String>('Sales');
    return AppPanel(
      title: 'Reports & analytics',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Preview',
            onPressed: () => _showReportPreview(context, selectedReport.value),
            icon: const Icon(Icons.preview_outlined),
          ),
          IconButton(
            tooltip: 'PDF',
            onPressed: () =>
                _exportReport(context, selectedReport.value, ReportExport.pdf),
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            tooltip: 'Excel',
            onPressed: () => _exportReport(
              context,
              selectedReport.value,
              ReportExport.excel,
            ),
            icon: const Icon(Icons.table_view_outlined),
          ),
          IconButton(
            tooltip: 'Print',
            onPressed: () => _printReport(context, selectedReport.value),
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      child: ValueListenableBuilder<String>(
        valueListenable: selectedReport,
        builder: (context, selected, _) {
          final rows = _reportRows(StoreScope.of(context), selected);
          return SizedBox(
            width: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final report in reports)
                      ChoiceChip(
                        avatar: const Icon(Icons.analytics_outlined, size: 18),
                        label: Text('$report report'),
                        selected: selected == report,
                        onSelected: (_) => selectedReport.value = report,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '$selected preview',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _ReportTable(rows: rows),
              ],
            ),
          );
        },
      ),
    );
  }
}

class UsersView extends StatelessWidget {
  const UsersView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return AppPanel(
      title: 'User & Role Management',
      action: FilledButton.icon(
        onPressed: () => _openUserDialog(context),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('New user'),
      ),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Email')),
          DataColumn(label: Text('Role')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: [
          for (final user in store.users)
            DataRow(
              cells: [
                DataCell(Text(user.name)),
                DataCell(Text(user.email)),
                DataCell(Text(user.role)),
                DataCell(
                  StatusPill(label: user.active ? 'Active' : 'Disabled'),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: () => _openUserDialog(context, user: user),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: () => store.deleteUser(user.id),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final branch = store.activeBranch;
    final selectedType = branch.isRestaurant ? 'Restaurant' : 'Retail';
    return ResponsiveColumns(
      left: AppPanel(
        title: 'Branch settings',
        horizontalScroll: false,
        child: SizedBox(
          width: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.store_outlined),
                title: Text(branch.name),
                subtitle: Text('${branch.code}  |  ${branch.type}'),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'Retail',
                    icon: Icon(Icons.point_of_sale_outlined),
                    label: Text('Retail'),
                  ),
                  ButtonSegment(
                    value: 'Restaurant',
                    icon: Icon(Icons.restaurant_menu_outlined),
                    label: Text('Restaurant'),
                  ),
                ],
                selected: {selectedType},
                onSelectionChanged: (value) async {
                  await store.saveActiveBranchType(value.first);
                  if (!context.mounted) return;
                  _showMessage(context, store.syncStatus);
                },
              ),
            ],
          ),
        ),
      ),
      right: DataPanel(
        title: 'POS behavior',
        rows: const [
          ['Retail', 'Normal scan/search POS', 'All items'],
          ['Restaurant', 'Tablet menu POS', 'Priority items'],
          ['Windows desktop', 'Quick chips', 'Top 10 priority'],
        ],
      ),
    );
  }
}

class ResponsiveColumns extends StatelessWidget {
  const ResponsiveColumns({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 900;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: twoColumns
                  ? (constraints.maxWidth - 16) * .58
                  : constraints.maxWidth,
              child: left,
            ),
            SizedBox(
              width: twoColumns
                  ? (constraints.maxWidth - 16) * .42
                  : constraints.maxWidth,
              child: right,
            ),
          ],
        );
      },
    );
  }
}

class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.title,
    required this.child,
    this.action,
    this.horizontalScroll = true,
  });

  final String title;
  final Widget child;
  final Widget? action;
  final bool horizontalScroll;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 14),
            if (horizontalScroll)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: child,
              )
            else
              child,
          ],
        ),
      ),
    );
  }
}

class DataPanel extends StatelessWidget {
  const DataPanel({super.key, required this.title, required this.rows});

  final String title;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      title: title,
      child: SizedBox(
        width: 520,
        child: Column(
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(row[0], overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      child: Text(
                        row[1],
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row[2],
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReportTable extends StatelessWidget {
  const _ReportTable({required this.rows});

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return DataTable(
      columns: const [
        DataColumn(label: Text('Name')),
        DataColumn(label: Text('Quantity / Status')),
        DataColumn(label: Text('Amount / Detail')),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(Text(row[0])),
              DataCell(Text(row[1])),
              DataCell(Text(row[2])),
            ],
          ),
      ],
    );
  }
}

class TotalRow extends StatelessWidget {
  const TotalRow({
    super.key,
    required this.label,
    required this.value,
    this.strong = false,
    this.action,
  });

  final String label;
  final String value;
  final bool strong;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final style = strong
        ? Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
          ?action,
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = switch (label) {
      'Low' || 'Pending' || 'Disabled' => const Color(0xFFD97706),
      'Received' || 'Active' || 'OK' || 'Paid' => const Color(0xFF0E7C66),
      _ => Theme.of(context).colorScheme.primary,
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: .28)),
      backgroundColor: color.withValues(alpha: .10),
      label: Text(label),
    );
  }
}

enum ReportExport { pdf, excel }

AppUser _currentUser(BuildContext context) => UserScope.of(context);

bool _canEditParty(AppUser user, PartyKind kind) {
  return kind == PartyKind.customer ? user.canUsePos : user.canManageOperations;
}

List<List<String>> _reportRows(AppStore store, String report) {
  final money = intl.NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
  return switch (report) {
    'Sales' => [
      for (final invoice in store.invoices)
        [invoice.number, invoice.customer, money.format(invoice.total)],
    ],
    'Purchases' => [
      for (final order in store.purchases)
        [order.orderNo, order.status, money.format(order.total)],
    ],
    'Profit' => [
      [
        'Total sales',
        '${store.invoices.length} invoices',
        money.format(
          store.invoices.fold(0.0, (sum, invoice) => sum + invoice.total),
        ),
      ],
      [
        'Total expenses',
        '${store.expenses.length} entries',
        money.format(
          store.expenses.fold(0.0, (sum, expense) => sum + expense.amount),
        ),
      ],
      [
        'Estimated margin',
        'Sales - expenses',
        money.format(
          store.invoices.fold(0.0, (sum, invoice) => sum + invoice.total) -
              store.expenses.fold(0.0, (sum, expense) => sum + expense.amount),
        ),
      ],
    ],
    'Stock' => [
      for (final product in store.products)
        [product.name, product.stock.toStringAsFixed(0), product.category],
    ],
    'Low stock' => [
      for (final product in store.products.where(
        (item) => item.stock <= item.minStock,
      ))
        [
          product.name,
          product.stock.toStringAsFixed(0),
          'Min ${product.minStock.toStringAsFixed(0)}',
        ],
    ],
    'Expiry' => const [
      ['No expiry batches', '0', 'No batch expiry entered'],
    ],
    'Barcode' => [
      for (final product in store.products)
        [product.name, product.sku, product.barcode],
    ],
    'Tax' => [
      ['GST/VAT', '0%', money.format(0)],
    ],
    'Customers' => [
      for (final party in store.customers)
        [party.name, party.phone, money.format(party.balance)],
    ],
    'Suppliers' => [
      for (final party in store.suppliers)
        [party.name, party.phone, money.format(party.balance)],
    ],
    _ => [
      for (final product in store.products)
        [
          product.name,
          product.stock.toStringAsFixed(0),
          money.format(product.stock * product.purchasePrice),
        ],
    ],
  };
}

Future<void> _exportReport(
  BuildContext context,
  String report,
  ReportExport format,
) async {
  final rows = _reportRows(StoreScope.of(context), report);
  final safeName = _safeFileName(report, fallback: 'report');
  final directory = _ensureDirectory('reports');
  final extension = format == ReportExport.excel ? 'csv' : 'pdf';
  final file = File('${directory.path}/$safeName-report.$extension');
  if (format == ReportExport.excel) {
    final csvRows = [
      'Name,Quantity / Status,Amount / Detail',
      for (final row in rows) row.map(_csvCell).join(','),
    ];
    file.writeAsStringSync(csvRows.join('\n'));
    await _openFile(file);
  } else {
    _writeSimplePdf(
      file: file,
      title: '$report report',
      headings: const ['Name', 'Quantity / Status', 'Amount / Detail'],
      rows: rows,
    );
    await _openFile(file);
  }
  if (!context.mounted) return;
  _showMessage(
    context,
    '${format == ReportExport.excel ? 'Excel CSV' : 'PDF'} exported: ${file.path}',
  );
}

Future<void> _printReport(BuildContext context, String report) async {
  final rows = _reportRows(StoreScope.of(context), report);
  final directory = _ensureDirectory('reports');
  final file = File(
    '${directory.path}/${_safeFileName(report, fallback: 'report')}-print.html',
  );
  file.writeAsStringSync(_reportHtml(report, rows, autoPrint: true));
  await _openFile(file);
  if (!context.mounted) return;
  _showMessage(context, 'Printable report opened: ${file.path}');
}

String _reportHtml(
  String report,
  List<List<String>> rows, {
  required bool autoPrint,
}) {
  final htmlRows = rows
      .map(
        (row) =>
            '<tr>${row.map((cell) => '<td>${_html(cell)}</td>').join()}</tr>',
      )
      .join();
  return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>$report report</title>
  <style>
    body { font-family: Arial, sans-serif; padding: 24px; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #ccc; padding: 8px; text-align: left; }
    th { background: #eef6f3; }
  </style>
</head>
<body>
  <h1>$report report</h1>
  <table>
    <thead><tr><th>Name</th><th>Quantity / Status</th><th>Amount / Detail</th></tr></thead>
    <tbody>$htmlRows</tbody>
  </table>
  ${autoPrint ? '<script>window.addEventListener("load", () => window.print());</script>' : ''}
</body>
</html>
''';
}

String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';
String _html(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

Directory _ensureDirectory(String path) {
  final directory = Directory(path);
  if (!directory.existsSync()) directory.createSync(recursive: true);
  return directory;
}

String _safeFileName(String value, {required String fallback}) {
  final safe = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return safe.isEmpty ? fallback : safe;
}

Future<void> _openFile(File file) async {
  if (kIsWeb) return;
  final path = file.absolute.path;
  if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else {
    await Process.run('xdg-open', [path]);
  }
}

Future<void> _exportInvoice(
  BuildContext context,
  Invoice invoice,
  List<InvoiceLine> lines, {
  required bool printAfterExport,
}) async {
  final directory = _ensureDirectory('invoices');
  final safeName = _safeFileName(invoice.number, fallback: 'invoice');
  final pdfFile = File('${directory.path}/$safeName.pdf');
  final money = intl.NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
  _writeSimplePdf(
    file: pdfFile,
    title: 'Invoice ${invoice.number}',
    headings: const ['Item', 'Qty', 'Amount'],
    rows: [
      [
        'Customer',
        invoice.customer,
        intl.DateFormat('yyyy-MM-dd HH:mm').format(invoice.createdAt),
      ],
      for (final line in lines)
        [
          line.product.name,
          line.quantity.toStringAsFixed(0),
          money.format(line.total),
        ],
      if (invoice.discountAmount > 0)
        ['Discount', '', '-${money.format(invoice.discountAmount)}'],
      ['Payment', invoice.method, money.format(invoice.paid)],
      if (invoice.tendered > invoice.paid)
        ['Tendered', '', money.format(invoice.tendered)],
      if (invoice.changeDue > 0)
        ['Returned change', '', money.format(invoice.changeDue)],
      ['Grand total', '', money.format(invoice.total)],
      ['Due', '', money.format(invoice.due)],
    ],
  );
  if (printAfterExport) {
    await _printInvoiceDirect(
      context,
      invoice,
      lines,
      printerName: StoreScope.of(context).receiptPrinterName,
    );
  } else {
    await _openFile(pdfFile);
  }
  if (!context.mounted) return;
  _showMessage(context, 'Invoice ${invoice.number} saved: ${pdfFile.path}');
}

Future<void> _printInvoiceDirect(
  BuildContext context,
  Invoice invoice,
  List<InvoiceLine> lines, {
  required String printerName,
  bool duplicate = false,
}) async {
  final directory = _ensureDirectory('invoices');
  final safeName = _safeFileName(invoice.number, fallback: 'invoice');
  final receiptFile = File('${directory.path}/$safeName-receipt.txt');
  receiptFile.writeAsStringSync(
    _invoiceReceiptText(invoice, lines, duplicate: duplicate),
    encoding: utf8,
  );

  if (kIsWeb || !Platform.isWindows) {
    await _openFile(receiptFile);
    if (!context.mounted) return;
    _showMessage(context, 'Receipt opened: ${receiptFile.path}');
    return;
  }

  final scriptFile = File('${directory.path}/print-receipt.ps1');
  scriptFile.writeAsStringSync(r'''
param(
  [Parameter(Mandatory = $true)]
  [string]$ReceiptPath,
  [string]$PrinterName = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ReceiptPath) -or -not [System.IO.File]::Exists($ReceiptPath)) {
  throw "Receipt file was not found: $ReceiptPath"
}
Add-Type -AssemblyName System.Drawing
$script:receiptLines = [System.IO.File]::ReadAllLines($ReceiptPath)
$script:receiptFont = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Regular)
$doc = New-Object System.Drawing.Printing.PrintDocument
$doc.DocumentName = "POS Receipt"
if (-not [string]::IsNullOrWhiteSpace($PrinterName)) {
  $doc.PrinterSettings.PrinterName = $PrinterName
}
$paperHeight = [Math]::Max(500, [Math]::Min(3200, 90 + ($script:receiptLines.Length * 18)))
$doc.DefaultPageSettings.PaperSize = New-Object System.Drawing.Printing.PaperSize("3 inch thermal receipt", 300, $paperHeight)
$doc.DefaultPageSettings.Margins = New-Object System.Drawing.Printing.Margins(0, 0, 0, 0)
$doc.OriginAtMargins = $false
$script:index = 0
$doc.add_PrintPage({
  param($sender, $eventArgs)
  $eventArgs.Graphics.PageUnit = [System.Drawing.GraphicsUnit]::Display
  $x = $eventArgs.PageSettings.HardMarginX + 4
  $y = $eventArgs.PageSettings.HardMarginY + 4
  $lineHeight = $script:receiptFont.GetHeight($eventArgs.Graphics) + 5
  while ($script:index -lt $script:receiptLines.Length) {
    $eventArgs.Graphics.DrawString($script:receiptLines[$script:index], $script:receiptFont, [System.Drawing.Brushes]::Black, $x, $y)
    $y += $lineHeight
    $script:index++
    if ($y + $lineHeight -gt ($eventArgs.PageBounds.Height - 10)) {
      $eventArgs.HasMorePages = $true
      return
    }
  }
  $eventArgs.HasMorePages = $false
})
$doc.Print()
''', encoding: utf8);

  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    scriptFile.absolute.path,
    receiptFile.absolute.path,
    printerName.trim(),
  ]);

  if (!context.mounted) return;
  if (result.exitCode == 0) {
    final target = printerName.trim().isEmpty
        ? 'default printer'
        : printerName.trim();
    _showMessage(
      context,
      '${duplicate ? 'Duplicate receipt' : 'Receipt'} sent to $target',
    );
  } else {
    final stderr = result.stderr.toString().trim();
    final error = stderr.isNotEmpty ? stderr : 'Windows print command failed';
    _showMessage(context, 'Print failed: ${_shortError(error)}');
  }
}

String _invoiceReceiptText(
  Invoice invoice,
  List<InvoiceLine> lines, {
  required bool duplicate,
}) {
  const width = 32;
  final money = intl.NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
  final date = intl.DateFormat('yyyy-MM-dd HH:mm').format(invoice.createdAt);
  final buffer = StringBuffer();
  void line([String value = '']) =>
      buffer.writeln(value.length > width ? value.substring(0, width) : value);
  void rule() => line('-' * width);
  void pair(String left, String right) {
    final cleanLeft = left.length > width - 2
        ? left.substring(0, width - 2)
        : left;
    final space = (width - cleanLeft.length - right.length)
        .clamp(1, width)
        .toInt();
    line('$cleanLeft${' ' * space}$right');
  }

  line('POS-INV-MSSQL'.padLeft(22).padRight(width));
  if (duplicate) line('*** DUPLICATE REPRINT ***');
  rule();
  pair('Invoice', invoice.number);
  pair('Date', date);
  pair('Customer', invoice.customer);
  pair('Payment', invoice.method);
  rule();
  for (final item in lines) {
    for (final part in _wrapReceiptText(item.product.name, width)) {
      line(part);
    }
    final quantity = item.quantity.toStringAsFixed(0);
    pair(
      '$quantity x ${money.format(item.product.salePrice)}',
      money.format(item.total),
    );
  }
  rule();
  if (invoice.discountAmount > 0)
    pair('Discount', '-${money.format(invoice.discountAmount)}');
  if (invoice.tendered > invoice.paid)
    pair('Tendered', money.format(invoice.tendered));
  if (invoice.changeDue > 0) pair('Change', money.format(invoice.changeDue));
  pair('Paid', money.format(invoice.paid));
  pair('Due', money.format(invoice.due));
  rule();
  pair('GRAND TOTAL', money.format(invoice.total));
  rule();
  line('Thank you');
  line();
  line();
  return buffer.toString();
}

List<String> _wrapReceiptText(String text, int width) {
  final words = text
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  final lines = <String>[];
  var current = '';
  for (final word in words) {
    if (word.length > width) {
      if (current.isNotEmpty) {
        lines.add(current);
        current = '';
      }
      for (var index = 0; index < word.length; index += width) {
        lines.add(
          word.substring(index, (index + width).clamp(0, word.length).toInt()),
        );
      }
      continue;
    }
    final next = current.isEmpty ? word : '$current $word';
    if (next.length > width) {
      lines.add(current);
      current = word;
    } else {
      current = next;
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines.isEmpty ? [''] : lines;
}

void _writeSimplePdf({
  required File file,
  required String title,
  required List<String> headings,
  required List<List<String>> rows,
}) {
  final lines = <String>[
    title,
    '',
    headings.join('   |   '),
    '-' * 92,
    for (final row in rows) row.join('   |   '),
  ];
  const linesPerPage = 42;
  final pages = <List<String>>[];
  for (var index = 0; index < lines.length; index += linesPerPage) {
    pages.add(
      lines.sublist(index, (index + linesPerPage).clamp(0, lines.length)),
    );
  }

  final objects = <int, String>{};
  objects[1] = '<< /Type /Catalog /Pages 2 0 R >>';
  objects[3] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';
  final kids = <String>[];
  for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
    final pageObject = 4 + pageIndex * 2;
    final contentObject = pageObject + 1;
    kids.add('$pageObject 0 R');
    objects[pageObject] =
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents $contentObject 0 R >>';
    final content = _pdfContentStream(
      pages[pageIndex],
      pageIndex + 1,
      pages.length,
    );
    objects[contentObject] =
        '<< /Length ${latin1.encode(content).length} >>\nstream\n$content\nendstream';
  }
  objects[2] =
      '<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${pages.length} >>';

  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int, int>{};
  for (final objectNumber in objects.keys.toList()..sort()) {
    offsets[objectNumber] = latin1.encode(buffer.toString()).length;
    buffer.write('$objectNumber 0 obj\n${objects[objectNumber]}\nendobj\n');
  }
  final xrefOffset = latin1.encode(buffer.toString()).length;
  buffer.write('xref\n0 ${objects.length + 1}\n');
  buffer.write('0000000000 65535 f \n');
  for (var objectNumber = 1; objectNumber <= objects.length; objectNumber++) {
    buffer.write(
      '${offsets[objectNumber]!.toString().padLeft(10, '0')} 00000 n \n',
    );
  }
  buffer.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF',
  );
  file.writeAsBytesSync(latin1.encode(buffer.toString()));
}

String _pdfContentStream(List<String> lines, int pageNumber, int pageCount) {
  final content = StringBuffer(
    'BT\n/F1 16 Tf\n50 800 Td\n(${_pdfText(lines.firstOrNull ?? '')}) Tj\n/F1 9 Tf\n',
  );
  var firstLine = true;
  for (final line in lines.skip(1)) {
    final text = _pdfText(line.length > 110 ? line.substring(0, 110) : line);
    content.write('${firstLine ? '0 -24 Td' : 'T*'} ($text) Tj\n');
    firstLine = false;
  }
  content.write('/F1 8 Tf\n0 -24 Td\n(Page $pageNumber of $pageCount) Tj\nET');
  return content.toString();
}

String _pdfText(String value) {
  return value
      .replaceAll('\\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)')
      .replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
}

Future<void> _printBarcodeLabel(BuildContext context, Product product) async {
  final directory = _ensureDirectory('barcode-labels');
  final safeName = _safeFileName(product.sku, fallback: 'product');
  final file = File(
    '${directory.path}/${safeName.isEmpty ? 'product' : safeName}-label.html',
  );
  final barcodeSvg = _code39Svg(
    product.barcode.isEmpty ? product.sku : product.barcode,
  );
  final money = intl.NumberFormat.currency(symbol: 'PKR ', decimalDigits: 0);
  file.writeAsStringSync('''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>${_html(product.name)} barcode label</title>
  <style>
    @page { size: 50mm 30mm; margin: 2mm; }
    body { margin: 0; font-family: Arial, sans-serif; }
    .sheet { display: grid; grid-template-columns: repeat(2, 50mm); gap: 3mm; padding: 3mm; }
    .label { width: 50mm; height: 30mm; border: 1px dashed #bbb; box-sizing: border-box; padding: 2mm; overflow: hidden; }
    .name { font-size: 9px; font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .sku { font-size: 8px; margin-top: 1mm; }
    .barcode { margin-top: 1mm; }
    .price { font-size: 10px; font-weight: 700; text-align: right; }
    @media print { .label { border: 0; } }
  </style>
</head>
<body>
  <div class="sheet">
    ${List.filled(10, '''
    <div class="label">
      <div class="name">${_html(product.name)}</div>
      <div class="sku">SKU: ${_html(product.sku)}</div>
      <div class="barcode">$barcodeSvg</div>
      <div class="price">${_html(money.format(product.salePrice))}</div>
    </div>
    ''').join()}
  </div>
  <script>window.print();</script>
</body>
</html>
''');
  await _openFile(file);
  if (!context.mounted) return;
  _showMessage(context, 'Barcode label opened for printing: ${file.path}');
}

String _code39Svg(String value) {
  const patterns = {
    '0': 'nnnwwnwnn',
    '1': 'wnnwnnnnw',
    '2': 'nnwwnnnnw',
    '3': 'wnwwnnnnn',
    '4': 'nnnwwnnnw',
    '5': 'wnnwwnnnn',
    '6': 'nnwwwnnnn',
    '7': 'nnnwnnwnw',
    '8': 'wnnwnnwnn',
    '9': 'nnwwnnwnn',
    'A': 'wnnnnwnnw',
    'B': 'nnwnnwnnw',
    'C': 'wnwnnwnnn',
    'D': 'nnnnwwnnw',
    'E': 'wnnnwwnnn',
    'F': 'nnwnwwnnn',
    'G': 'nnnnnwwnw',
    'H': 'wnnnnwwnn',
    'I': 'nnwnnwwnn',
    'J': 'nnnnwwwnn',
    'K': 'wnnnnnnww',
    'L': 'nnwnnnnww',
    'M': 'wnwnnnnwn',
    'N': 'nnnnwnnww',
    'O': 'wnnnwnnwn',
    'P': 'nnwnwnnwn',
    'Q': 'nnnnnnwww',
    'R': 'wnnnnnwwn',
    'S': 'nnwnnnwwn',
    'T': 'nnnnwnwwn',
    'U': 'wwnnnnnnw',
    'V': 'nwwnnnnnw',
    'W': 'wwwnnnnnn',
    'X': 'nwnnwnnnw',
    'Y': 'wwnnwnnnn',
    'Z': 'nwwnwnnnn',
    '-': 'nwnnnnwnw',
    '.': 'wwnnnnwnn',
    ' ': 'nwwnnnwnn',
    '*': 'nwnnwnwnn',
  };
  final encoded =
      '*${value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9 .-]+'), '')}*';
  const narrow = 1.2;
  const wide = 3.0;
  const height = 42.0;
  var x = 0.0;
  final bars = StringBuffer();
  for (final char in encoded.characters) {
    final pattern = patterns[char] ?? patterns['-']!;
    for (var i = 0; i < pattern.length; i++) {
      final width = pattern[i] == 'w' ? wide : narrow;
      if (i.isEven)
        bars.write(
          '<rect x="${x.toStringAsFixed(1)}" y="0" width="${width.toStringAsFixed(1)}" height="$height" />',
        );
      x += width;
    }
    x += narrow;
  }
  return '<svg width="180" height="48" viewBox="0 0 ${x.toStringAsFixed(1)} 48" xmlns="http://www.w3.org/2000/svg"><g fill="#000">$bars</g></svg>';
}

Future<void> _openProductDialog(
  BuildContext context, {
  Product? product,
}) async {
  final store = StoreScope.of(context);
  final name = TextEditingController(text: product?.name ?? '');
  final sku = TextEditingController(text: product?.sku ?? '');
  final barcode = TextEditingController(text: product?.barcode ?? '');
  final category = TextEditingController(text: product?.category ?? 'General');
  final salePrice = TextEditingController(
    text: (product?.salePrice ?? 0).toStringAsFixed(0),
  );
  final purchasePrice = TextEditingController(
    text: (product?.purchasePrice ?? 0).toStringAsFixed(0),
  );
  final stock = TextEditingController(
    text: (product?.stock ?? 0).toStringAsFixed(0),
  );
  final minStock = TextEditingController(
    text: (product?.minStock ?? 0).toStringAsFixed(0),
  );
  final posPriority = TextEditingController(
    text: product == null || product.posPriority <= 0
        ? ''
        : product.posPriority.toString(),
  );
  await _showFormDialog(
    context,
    title: product == null ? 'New product' : 'Edit product',
    fields: [
      TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      TextField(
        controller: category,
        decoration: const InputDecoration(labelText: 'Category'),
      ),
      StatefulBuilder(
        builder: (context, setDialogState) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: sku,
                  decoration: const InputDecoration(labelText: 'SKU'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Generate SKU',
                onPressed: () => setDialogState(
                  () => sku.text = _generateSku(
                    name.text,
                    category.text,
                    product?.id ?? store._nextProductId,
                  ),
                ),
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
            ],
          );
        },
      ),
      StatefulBuilder(
        builder: (context, setDialogState) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: barcode,
                  decoration: const InputDecoration(labelText: 'Barcode'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Generate barcode',
                onPressed: () => setDialogState(
                  () => barcode.text = _generateBarcode(
                    product?.id ?? store._nextProductId,
                  ),
                ),
                icon: const Icon(Icons.qr_code_2_outlined),
              ),
            ],
          );
        },
      ),
      TextField(
        controller: salePrice,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Sale price'),
      ),
      TextField(
        controller: purchasePrice,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Purchase price'),
      ),
      TextField(
        controller: stock,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Stock'),
      ),
      TextField(
        controller: minStock,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Min stock'),
      ),
      TextField(
        controller: posPriority,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'POS priority',
          helperText:
              '1 is shown first; leave blank to hide from restaurant tablet menu',
        ),
      ),
    ],
    onSave: () {
      store.upsertProduct(
        Product(
          id: product?.id ?? 0,
          name: name.text.trim(),
          sku: sku.text.trim(),
          barcode: barcode.text.trim(),
          category: category.text.trim(),
          salePrice: _num(salePrice),
          purchasePrice: _num(purchasePrice),
          stock: _num(stock),
          minStock: _num(minStock),
          posPriority: int.tryParse(posPriority.text.trim()) ?? 0,
        ),
      );
    },
  );
}

Future<void> _openPartyDialog(
  BuildContext context, {
  required PartyKind kind,
  Party? party,
}) async {
  final store = StoreScope.of(context);
  final name = TextEditingController(text: party?.name ?? '');
  final phone = TextEditingController(text: party?.phone ?? '');
  final email = TextEditingController(text: party?.email ?? '');
  final balance = TextEditingController(
    text: (party?.balance ?? 0).toStringAsFixed(0),
  );
  await _showFormDialog(
    context,
    title: party == null ? 'New ${kind.name}' : 'Edit ${kind.name}',
    fields: [
      TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      TextField(
        controller: phone,
        decoration: const InputDecoration(labelText: 'Phone'),
      ),
      TextField(
        controller: email,
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      TextField(
        controller: balance,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Balance'),
      ),
    ],
    onSave: () {
      final next = Party(
        id: party?.id ?? 0,
        name: name.text.trim(),
        phone: phone.text.trim(),
        email: email.text.trim(),
        balance: _num(balance),
      );
      kind == PartyKind.customer
          ? store.upsertCustomer(next)
          : store.upsertSupplier(next);
    },
  );
}

Future<void> _openUserDialog(BuildContext context, {AppUser? user}) async {
  final store = StoreScope.of(context);
  final name = TextEditingController(text: user?.name ?? '');
  final email = TextEditingController(text: user?.email ?? '');
  final password = TextEditingController(text: user?.password ?? '');
  String role = user?.role ?? 'Cashier';
  bool active = user?.active ?? true;
  await _showFormDialog(
    context,
    title: user == null ? 'New user' : 'Edit user',
    fields: [
      TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      TextField(
        controller: email,
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      TextField(
        controller: password,
        obscureText: true,
        decoration: InputDecoration(
          labelText: user == null ? 'Password' : 'Reset password',
          helperText: user == null
              ? 'Leave blank to use role default password'
              : 'Leave blank to keep current password',
        ),
      ),
      StatefulBuilder(
        builder: (context, setDialogState) {
          return Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const ['Admin', 'Manager', 'Cashier']
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => role = value ?? role),
              ),
              SwitchListTile(
                value: active,
                onChanged: (value) => setDialogState(() => active = value),
                title: const Text('Active'),
              ),
            ],
          );
        },
      ),
    ],
    onSave: () => store.upsertUser(
      AppUser(
        id: user?.id ?? 0,
        name: name.text.trim(),
        email: email.text.trim(),
        role: role,
        active: active,
        password: password.text.trim(),
      ),
    ),
  );
}

Future<void> _openChangePasswordDialog(
  BuildContext context,
  AppUser user,
) async {
  final store = StoreScope.of(context);
  final currentPassword = TextEditingController();
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  await _showFormDialog(
    context,
    title: 'Change password',
    fields: [
      TextField(
        controller: currentPassword,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Current password'),
      ),
      TextField(
        controller: newPassword,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'New password'),
      ),
      TextField(
        controller: confirmPassword,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Confirm password'),
      ),
    ],
    onSave: () {
      if (newPassword.text != confirmPassword.text) {
        _showMessage(context, 'New password and confirmation do not match');
        return;
      }
      unawaited(
        store
            .changeOwnPassword(user, currentPassword.text, newPassword.text)
            .then((changed) {
              if (!context.mounted) return;
              _showMessage(
                context,
                changed ? 'Password changed' : store.syncStatus,
              );
            }),
      );
    },
  );
}

Future<void> _openPurchaseDialog(
  BuildContext context, {
  PurchaseOrder? order,
}) async {
  final store = StoreScope.of(context);
  final orderNo = TextEditingController(
    text:
        order?.orderNo ??
        'PO-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
  );
  final total = TextEditingController(
    text: (order?.total ?? 0).toStringAsFixed(0),
  );
  String supplier = order?.supplier ?? store.suppliers.first.name;
  await _showFormDialog(
    context,
    title: order == null ? 'New purchase order' : 'Edit purchase order',
    fields: [
      StatefulBuilder(
        builder: (context, setDialogState) {
          return DropdownButtonFormField<String>(
            initialValue: supplier,
            decoration: const InputDecoration(labelText: 'Supplier'),
            items: [
              for (final party in store.suppliers)
                DropdownMenuItem(value: party.name, child: Text(party.name)),
            ],
            onChanged: (value) =>
                setDialogState(() => supplier = value ?? supplier),
          );
        },
      ),
      TextField(
        controller: orderNo,
        decoration: const InputDecoration(labelText: 'Order no'),
      ),
      TextField(
        controller: total,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Total'),
      ),
    ],
    onSave: () => store.upsertPurchase(
      PurchaseOrder(
        id: order?.id ?? 0,
        supplier: supplier,
        orderNo: orderNo.text.trim(),
        status: order?.status ?? 'Pending',
        total: _num(total),
      ),
    ),
  );
}

Future<void> _openExpenseDialog(
  BuildContext context, {
  Expense? expense,
}) async {
  final store = StoreScope.of(context);
  final title = TextEditingController(text: expense?.title ?? '');
  final category = TextEditingController(text: expense?.category ?? 'General');
  final amount = TextEditingController(
    text: (expense?.amount ?? 0).toStringAsFixed(0),
  );
  await _showFormDialog(
    context,
    title: expense == null ? 'New expense' : 'Edit expense',
    fields: [
      TextField(
        controller: title,
        decoration: const InputDecoration(labelText: 'Title'),
      ),
      TextField(
        controller: category,
        decoration: const InputDecoration(labelText: 'Category'),
      ),
      TextField(
        controller: amount,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Amount'),
      ),
    ],
    onSave: () => store.upsertExpense(
      Expense(
        id: expense?.id ?? 0,
        title: title.text.trim(),
        category: category.text.trim(),
        amount: _num(amount),
      ),
    ),
  );
}

Future<void> _openStockDialog(BuildContext context) async {
  final store = StoreScope.of(context);
  String product = store.products.first.name;
  String type = 'In';
  final quantity = TextEditingController(text: '1');
  final notes = TextEditingController(text: 'Manual adjustment');
  await _showFormDialog(
    context,
    title: 'Stock movement',
    fields: [
      StatefulBuilder(
        builder: (context, setDialogState) {
          return Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: product,
                decoration: const InputDecoration(labelText: 'Product'),
                items: [
                  for (final item in store.products)
                    DropdownMenuItem(value: item.name, child: Text(item.name)),
                ],
                onChanged: (value) =>
                    setDialogState(() => product = value ?? product),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'In',
                    icon: Icon(Icons.add),
                    label: Text('In'),
                  ),
                  ButtonSegment(
                    value: 'Out',
                    icon: Icon(Icons.remove),
                    label: Text('Out'),
                  ),
                ],
                selected: {type},
                onSelectionChanged: (value) =>
                    setDialogState(() => type = value.first),
              ),
            ],
          );
        },
      ),
      TextField(
        controller: quantity,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Quantity'),
      ),
      TextField(
        controller: notes,
        decoration: const InputDecoration(labelText: 'Notes'),
      ),
    ],
    onSave: () => store.addStockMovement(
      StockMovement(
        id: 0,
        product: product,
        type: type,
        quantity: _num(quantity),
        notes: notes.text.trim(),
      ),
    ),
  );
}

Future<void> _repairStock(BuildContext context) async {
  final repaired = await StoreScope.of(context).repairOrphanInvoiceStock();
  if (!context.mounted) return;
  _showMessage(
    context,
    repaired == 0
        ? 'No deleted-invoice stock movements found'
        : 'Repaired $repaired stock movement(s)',
  );
}

Future<void> _showReportPreview(BuildContext context, String report) async {
  final rows = _reportRows(StoreScope.of(context), report);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$report report'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(child: _ReportTable(rows: rows)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> _showFormDialog(
  BuildContext context, {
  required String title,
  required List<Widget> fields,
  required VoidCallback onSave,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: field,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            onSave();
            Navigator.pop(context);
            _showMessage(context, '$title saved');
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

double _num(TextEditingController controller) =>
    double.tryParse(controller.text.trim()) ?? 0;

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
