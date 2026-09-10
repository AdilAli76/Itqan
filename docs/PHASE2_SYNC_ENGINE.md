# Phase 2: Sync Engine — محرك المزامنة
**هدف:** تطبيق Delta Sync pattern لمزامنة البيانات بين القاعدة المحلية والسيرفر

---

## 📐 البنية المعمارية

### Delta Sync Pattern
```
┌─────────────────────────────────────────┐
│     Local SQLite Database               │
│  (sqflite - persistent storage)         │
└────────────┬────────────────────────────┘
             │
    ┌────────▼──────────────┐
    │   Sync Engine         │
    │  (Pull/Push/Conflict) │
    └────────┬──────────────┘
             │
    ┌────────▼────────────────────┐
    │   Pending Changes Log       │
    │  (Track modifications)      │
    └────────┬────────────────────┘
             │
    ┌────────▼──────────────────────────┐
    │   Backend API (ASP.NET Core)      │
    │   /api/sync/pull                  │
    │   /api/sync/push                  │
    │   /api/sync/conflicts (resolve)   │
    └───────────────────────────────────┘
```

---

## 🔄 المراحل الأربع

### 1. **Pull Sync** (تحميل من السيرفر)
```
تحميل جديد/محدّث من السيرفر
  ↓
تطبيق محلياً في SQLite
  ↓
تحديث timestamp آخر مزامنة
```

**الملفات المطلوبة:**
- `lib/features/sync/models/sync_models.dart` - نماذج البيانات
- `lib/features/sync/services/pull_sync_service.dart`

### 2. **Push Sync** (رفع التغييرات)
```
تجميع التغييرات المحلية
  ↓
إرسال للسيرفر
  ↓
حذف من pending changes
  ↓
تحديث local revisions
```

**الملفات المطلوبة:**
- `lib/features/sync/services/push_sync_service.dart`

### 3. **Conflict Resolution**
```
كشف التضارب (same record، different versions)
  ↓
تطبيق strategy (LOCAL_WINS, REMOTE_WINS, MERGE, MANUAL)
  ↓
إرسال القرار للسيرفر
```

**الملفات المطلوبة:**
- `lib/features/sync/models/conflict_models.dart`
- `lib/features/sync/services/conflict_service.dart`

### 4. **Offline Queue**
```
تخزين التغييرات أثناء بدون انترنت
  ↓
عند العودة للاتصال → Push تلقائي
```

**الملفات المطلوبة:**
- `lib/features/sync/services/offline_queue_service.dart`

---

## 📦 نماذج البيانات (Sync Models)

### SyncMetadata
```dart
{
  'entityType': 'products',  // products, invoices, etc
  'lastPullTime': DateTime,
  'lastPushTime': DateTime,
  'pullVersion': int,        // Latest version from server
  'pushVersion': int,        // Latest version pushed
}
```

### PendingChange
```dart
{
  'id': UUID,
  'entityType': 'products',
  'entityId': 'PRD-123',
  'operation': 'CREATE|UPDATE|DELETE',
  'data': {...},           // The actual change
  'timestamp': DateTime,
  'status': 'PENDING|SYNCED|FAILED',
  'retryCount': int,
}
```

### ConflictLog
```dart
{
  'id': UUID,
  'entityType': 'invoices',
  'entityId': 'INV-456',
  'localVersion': int,
  'remoteVersion': int,
  'localData': {...},
  'remoteData': {...},
  'resolution': 'PENDING|RESOLVED',
  'strategy': 'LOCAL_WINS|REMOTE_WINS|MERGE|MANUAL',
  'resolvedData': {...},
}
```

---

## 🛠️ الخدمات الأساسية

### 1. PullSyncService
```dart
class PullSyncService {
  /// تحميل التحديثات من السيرفر
  Future<SyncResult> pullUpdates(
    String entityType,
    int? sinceVersion,
  );
  
  /// تطبيق التحديثات محلياً
  Future<void> applyChanges(List<Change> changes);
}
```

### 2. PushSyncService
```dart
class PushSyncService {
  /// جمع التغييرات المعلقة
  Future<List<PendingChange>> getPendingChanges();
  
  /// إرسالها للسيرفر
  Future<SyncResult> pushChanges(
    List<PendingChange> changes,
  );
}
```

### 3. ConflictService
```dart
class ConflictService {
  /// كشف التضاربات
  Future<List<Conflict>> detectConflicts();
  
  /// حل التضارب
  Future<void> resolveConflict(
    String conflictId,
    ConflictResolutionStrategy strategy,
  );
}
```

### 4. OfflineQueueService
```dart
class OfflineQueueService {
  /// إضافة تغيير للطابور
  Future<void> queueChange(PendingChange change);
  
  /// تطبيق الطابور عند العودة للاتصال
  Future<void> processPendingQueue();
}
```

---

## 📊 جدول SQL للمزامنة

### sync_metadata
```sql
CREATE TABLE sync_metadata (
  entity_type TEXT PRIMARY KEY,
  last_pull_time DATETIME,
  last_push_time DATETIME,
  pull_version INTEGER DEFAULT 0,
  push_version INTEGER DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### pending_changes
```sql
CREATE TABLE pending_changes (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL,  -- CREATE|UPDATE|DELETE
  data TEXT NOT NULL,        -- JSON
  timestamp DATETIME NOT NULL,
  status TEXT DEFAULT 'PENDING',
  retry_count INTEGER DEFAULT 0,
  
  UNIQUE(entity_type, entity_id, operation)
);
```

### conflict_log
```sql
CREATE TABLE conflict_log (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  local_version INTEGER,
  remote_version INTEGER,
  local_data TEXT,
  remote_data TEXT,
  resolution TEXT DEFAULT 'PENDING',
  strategy TEXT,
  resolved_data TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

---

## 🔌 API Endpoints (Backend)

### Pull
```
GET /api/sync/pull/:entityType?sinceVersion=100
Response:
{
  "version": 105,
  "changes": [
    {
      "id": "PRD-123",
      "operation": "UPDATE",
      "data": {...},
      "timestamp": "2026-09-10T12:00:00Z"
    }
  ],
  "hasMore": false
}
```

### Push
```
POST /api/sync/push
Body:
{
  "changes": [
    {
      "entityType": "products",
      "entityId": "PRD-123",
      "operation": "UPDATE",
      "data": {...}
    }
  ]
}

Response:
{
  "successful": ["PRD-123"],
  "conflicts": [
    {
      "entityId": "INV-456",
      "localVersion": 1,
      "remoteVersion": 2,
      "remoteData": {...}
    }
  ]
}
```

### Resolve Conflict
```
POST /api/sync/conflicts/resolve
Body:
{
  "conflictId": "CNF-789",
  "strategy": "LOCAL_WINS",
  "resolvedData": {...}
}
```

---

## 📱 Riverpod Providers

```dart
// Sync state management
final syncStateProvider = StateNotifierProvider<
  SyncStateNotifier,
  SyncState
>((ref) => SyncStateNotifier());

// Pull sync service
final pullSyncServiceProvider = Provider(
  (ref) => PullSyncService(ref.watch(apiClientProvider)),
);

// Push sync service
final pushSyncServiceProvider = Provider(
  (ref) => PushSyncService(ref.watch(apiClientProvider)),
);

// Offline queue
final offlineQueueProvider = StateNotifierProvider<
  OfflineQueueNotifier,
  List<PendingChange>
>((ref) => OfflineQueueNotifier());

// Conflict resolver
final conflictResolverProvider = Provider(
  (ref) => ConflictService(ref.watch(localDbProvider)),
);
```

---

## 🚀 خطوات التنفيذ

### Week 1: Data Models & Database
- [ ] إنشاء sync_models.dart
- [ ] إضافة جداول الـ sync للـ sqflite
- [ ] Migrations و versioning

### Week 2: Pull & Push Services
- [ ] تطبيق PullSyncService
- [ ] تطبيق PushSyncService
- [ ] اختبار المزامنة الأساسية

### Week 3: Conflict Resolution
- [ ] تطبيق ConflictService
- [ ] Detect conflicts logic
- [ ] Resolution strategies

### Week 4: Offline Queue & Testing
- [ ] OfflineQueueService
- [ ] Background sync مع workmanager
- [ ] Integration testing

---

## ✅ Checklist Phase 2

- [ ] Sync models defined
- [ ] Database schema updated
- [ ] Pull service working
- [ ] Push service working
- [ ] Conflict detection + resolution
- [ ] Offline queue + background sync
- [ ] API integration tests
- [ ] End-to-end sync test
- [ ] Documentation complete
- [ ] Tag: v1.8.0 released

---

**الخطوة التالية:** ابدأ بإنشاء `sync_models.dart` و `database_migrations.dart`
