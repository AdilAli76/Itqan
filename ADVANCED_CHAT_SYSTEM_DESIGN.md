# 💬 نظام الدردشة المتقدم - تصميم شامل

**التاريخ:** 2026-09-12  
**الإصدار:** 2.0  
**الحالة:** جاهز للتطوير

---

## 🎯 الرؤية

```
بناء نظام دردشة احترافي يربط المدير بجميع الفروع
مع ميزات متقدمة للإدارة والتنسيق والتنويهات الذكية
```

---

## 📋 المحتويات

1. المتطلبات الوظيفية
2. قاعدة البيانات
3. البنية المعمارية
4. APIs التفصيلية
5. واجهات المستخدم
6. الأمان والأداء
7. خطة التطوير

---

## ✅ المتطلبات الوظيفية

### المتطلبات الأساسية:

```
REQ-001: إرسال واستقبال الرسائل النصية
REQ-002: دعم المرفقات (ملفات، صور، إلخ)
REQ-003: تنظيم الرسائل في قنوات
REQ-004: إشعارات فورية
REQ-005: البحث والفلترة
```

### المتطلبات المتقدمة:

```
REQ-101: الردود على الرسائل (Thread)
REQ-102: التفاعلات (Reactions)
REQ-103: الرسائل المثبتة
REQ-104: التصعيد التلقائي
REQ-105: التكامل مع الفواتير والطلبات
REQ-106: التنويهات الذكية
REQ-107: حالة الكتابة (Typing Indicator)
REQ-108: آخر نشاط (Last Seen)
```

---

## 🗄️ قاعدة البيانات

### 1. جدول القنوات

```sql
CREATE TABLE chat_channels (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    organization_id UNIQUEIDENTIFIER NOT NULL,
    name NVARCHAR(255) NOT NULL,
    display_name NVARCHAR(255),
    description NVARCHAR(MAX),
    channel_type NVARCHAR(50) NOT NULL, -- 'direct', 'group', 'broadcast'
    category NVARCHAR(50), -- 'general', 'sales', 'inventory', 'support', 'admin'
    
    -- الأعضاء والإعدادات
    owner_id UNIQUEIDENTIFIER NOT NULL,
    is_private BIT DEFAULT 0,
    is_archived BIT DEFAULT 0,
    archive_date DATETIME2,
    
    -- الإحصائيات
    total_messages INT DEFAULT 0,
    unread_count INT DEFAULT 0,
    last_message_at DATETIME2,
    
    -- الأيقونة والخلفية
    icon_url NVARCHAR(MAX),
    color NVARCHAR(10), -- #FF6B6B
    
    -- الأعضاء المطلوبين (للقنوات الخاصة)
    required_members JSON, -- [user_ids]
    
    created_by UNIQUEIDENTIFIER,
    created_at DATETIME2 DEFAULT GETUTCDATE(),
    updated_at DATETIME2 DEFAULT GETUTCDATE(),
    is_deleted BIT DEFAULT 0,
    
    CONSTRAINT PK_channels PRIMARY KEY (id),
    CONSTRAINT UQ_channel_name UNIQUE (name, organization_id) WHERE is_deleted = 0,
    CONSTRAINT FK_channel_owner FOREIGN KEY (owner_id) REFERENCES users(id)
);

-- فهرسة للأداء
CREATE INDEX IX_channels_org ON chat_channels(organization_id) WHERE is_deleted = 0;
CREATE INDEX IX_channels_category ON chat_channels(category, organization_id) WHERE is_deleted = 0;
CREATE INDEX IX_channels_archived ON chat_channels(is_archived) WHERE is_deleted = 0;
```

### 2. جدول أعضاء القنوات

```sql
CREATE TABLE channel_members (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    channel_id UNIQUEIDENTIFIER NOT NULL,
    user_id UNIQUEIDENTIFIER NOT NULL,
    
    -- الدور والصلاحيات
    role NVARCHAR(50), -- 'member', 'moderator', 'admin'
    
    -- الإخطارات
    notification_level NVARCHAR(50), -- 'all', 'mentions', 'none'
    is_muted BIT DEFAULT 0,
    
    -- الحالة
    last_read_message_id UNIQUEIDENTIFIER,
    last_read_at DATETIME2,
    last_activity_at DATETIME2,
    
    -- الأرشفة
    is_archived BIT DEFAULT 0,
    
    joined_at DATETIME2 DEFAULT GETUTCDATE(),
    left_at DATETIME2,
    
    CONSTRAINT PK_members PRIMARY KEY (id),
    CONSTRAINT FK_member_channel FOREIGN KEY (channel_id) REFERENCES chat_channels(id),
    CONSTRAINT FK_member_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT UQ_channel_member UNIQUE (channel_id, user_id)
);

CREATE INDEX IX_members_user ON channel_members(user_id) WHERE left_at IS NULL;
CREATE INDEX IX_members_unread ON channel_members(channel_id, last_read_at) WHERE is_muted = 0;
```

### 3. جدول الرسائل

```sql
CREATE TABLE chat_messages (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    channel_id UNIQUEIDENTIFIER NOT NULL,
    sender_id UNIQUEIDENTIFIER NOT NULL,
    
    -- نوع الرسالة
    message_type NVARCHAR(50), -- 'text', 'file', 'image', 'system', 'alert'
    content NVARCHAR(MAX) NOT NULL,
    
    -- الذكر (@mention)
    mentions JSON, -- [{user_id, name}]
    
    -- الربط بالكيانات
    linked_entity JSON, -- {type: 'invoice', id: 'xxx', ref: 'INV-001'}
    
    -- المرفقات
    attachments JSON, -- [{id, filename, size, url, type, uploaded_at}]
    
    -- الحالة
    is_pinned BIT DEFAULT 0,
    pinned_by UNIQUEIDENTIFIER,
    pinned_at DATETIME2,
    
    is_edited BIT DEFAULT 0,
    edited_by UNIQUEIDENTIFIER,
    edited_at DATETIME2,
    
    is_deleted BIT DEFAULT 0,
    deleted_by UNIQUEIDENTIFIER,
    deleted_at DATETIME2,
    
    -- التفاعلات
    reactions_summary JSON, -- {emoji: count}
    
    -- الخيوط
    reply_count INT DEFAULT 0,
    last_reply_at DATETIME2,
    
    created_at DATETIME2 DEFAULT GETUTCDATE(),
    
    CONSTRAINT PK_messages PRIMARY KEY (id),
    CONSTRAINT FK_message_channel FOREIGN KEY (channel_id) REFERENCES chat_channels(id),
    CONSTRAINT FK_message_sender FOREIGN KEY (sender_id) REFERENCES users(id)
);

CREATE INDEX IX_messages_channel ON chat_messages(channel_id, created_at DESC) WHERE is_deleted = 0;
CREATE INDEX IX_messages_pinned ON chat_messages(channel_id) WHERE is_pinned = 1 AND is_deleted = 0;
```

### 4. جدول الردود

```sql
CREATE TABLE chat_replies (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    parent_message_id UNIQUEIDENTIFIER NOT NULL,
    sender_id UNIQUEIDENTIFIER NOT NULL,
    
    content NVARCHAR(MAX) NOT NULL,
    mentions JSON,
    attachments JSON,
    
    is_edited BIT DEFAULT 0,
    edited_at DATETIME2,
    
    is_deleted BIT DEFAULT 0,
    deleted_at DATETIME2,
    
    reactions_summary JSON,
    
    created_at DATETIME2 DEFAULT GETUTCDATE(),
    
    CONSTRAINT FK_reply_message FOREIGN KEY (parent_message_id) REFERENCES chat_messages(id)
);

CREATE INDEX IX_replies_parent ON chat_replies(parent_message_id) WHERE is_deleted = 0;
```

### 5. جدول التفاعلات

```sql
CREATE TABLE message_reactions (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    message_id UNIQUEIDENTIFIER NOT NULL,
    user_id UNIQUEIDENTIFIER NOT NULL,
    emoji NVARCHAR(10) NOT NULL,
    created_at DATETIME2 DEFAULT GETUTCDATE(),
    
    CONSTRAINT FK_reaction_message FOREIGN KEY (message_id) REFERENCES chat_messages(id),
    CONSTRAINT FK_reaction_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT UQ_reaction UNIQUE (message_id, user_id, emoji)
);
```

### 6. جدول حالة القراءة

```sql
CREATE TABLE message_read_status (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    message_id UNIQUEIDENTIFIER NOT NULL,
    user_id UNIQUEIDENTIFIER NOT NULL,
    read_at DATETIME2,
    
    CONSTRAINT FK_read_message FOREIGN KEY (message_id) REFERENCES chat_messages(id),
    CONSTRAINT UQ_read_status UNIQUE (message_id, user_id)
);
```

### 7. جدول المؤشرات (Indicators)

```sql
CREATE TABLE chat_indicators (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    channel_id UNIQUEIDENTIFIER NOT NULL,
    user_id UNIQUEIDENTIFIER NOT NULL,
    
    is_typing BIT DEFAULT 0,
    typing_at DATETIME2,
    
    last_seen_at DATETIME2,
    
    CONSTRAINT UQ_indicator UNIQUE (channel_id, user_id)
);
```

---

## 🏗️ البنية المعمارية

### Stack التقنية:

```
Frontend:
├─ React / Vue.js
├─ WebSocket.io (Real-time)
├─ Redux / Pinia (State Management)
└─ Material-UI / Tailwind (UI)

Backend:
├─ .NET Core 8.0
├─ SignalR (Real-time WebSocket)
├─ Entity Framework Core
└─ SQL Server

Infrastructure:
├─ Docker / Kubernetes
├─ Redis (Caching)
├─ Message Queue (RabbitMQ)
└─ CDN (للملفات)
```

### المعمارية:

```
┌─────────────────────────────────────────────────────┐
│                   Client (Flutter/Web)              │
├─────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────┐  │
│  │         WebSocket / REST API                 │  │
│  └──────────────────┬───────────────────────────┘  │
└─────────────────────┼─────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│              API Gateway / Load Balancer            │
├─────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────┐  │
│  │      SignalR Hub (Real-time)                │  │
│  ├──────────────────────────────────────────────┤  │
│  │      Chat API Controllers                    │  │
│  ├──────────────────────────────────────────────┤  │
│  │      Notification Service                    │  │
│  ├──────────────────────────────────────────────┤  │
│  │      File Upload Service                     │  │
│  └──────────────────┬───────────────────────────┘  │
└─────────────────────┼─────────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
    ┌────────┐  ┌─────────┐  ┌─────────┐
    │SQL DB  │  │  Redis  │  │  S3/CDN │
    └────────┘  └─────────┘  └─────────┘
```

---

## 🔌 APIs التفصيلية

### إدارة القنوات:

```
POST /api/v1/chat/channels
{
  "name": "sales-team",
  "displayName": "فريق المبيعات",
  "description": "قناة تنسيق فريق المبيعات",
  "category": "sales",
  "isPrivate": false,
  "requiredMembers": ["user1", "user2"]
}

GET /api/v1/chat/channels
  ?category=sales
  &archived=false
  &sort=-lastMessageAt
  &limit=20
  &offset=0

GET /api/v1/chat/channels/{channelId}
PUT /api/v1/chat/channels/{channelId}
DELETE /api/v1/chat/channels/{channelId}

POST /api/v1/chat/channels/{channelId}/members
DELETE /api/v1/chat/channels/{channelId}/members/{userId}
PUT /api/v1/chat/channels/{channelId}/members/{userId}
  {role: 'moderator', notificationLevel: 'mentions'}

POST /api/v1/chat/channels/{channelId}/archive
POST /api/v1/chat/channels/{channelId}/unarchive
```

### إدارة الرسائل:

```
POST /api/v1/chat/channels/{channelId}/messages
{
  "content": "مرحباً بالجميع",
  "messageType": "text",
  "mentions": ["@أحمد", "@فاطمة"],
  "linkedEntity": {
    "type": "invoice",
    "id": "inv123",
    "ref": "INV-2026-001"
  }
}

GET /api/v1/chat/channels/{channelId}/messages
  ?limit=50
  &before=timestamp
  &search=keyword

GET /api/v1/chat/messages/{messageId}
PUT /api/v1/chat/messages/{messageId}
DELETE /api/v1/chat/messages/{messageId}

POST /api/v1/chat/messages/{messageId}/pin
DELETE /api/v1/chat/messages/{messageId}/pin
```

### الردود والتفاعلات:

```
POST /api/v1/chat/messages/{messageId}/replies
{
  "content": "شكراً على المعلومة",
  "mentions": ["@أحمد"]
}

GET /api/v1/chat/messages/{messageId}/replies

POST /api/v1/chat/messages/{messageId}/react
{
  "emoji": "👍"
}

DELETE /api/v1/chat/messages/{messageId}/react/{emoji}
```

### حالة القراءة والمؤشرات:

```
POST /api/v1/chat/channels/{channelId}/mark-as-read
{
  "lastReadMessageId": "msg123"
}

POST /api/v1/chat/channels/{channelId}/typing-indicator
{
  "isTyping": true
}

GET /api/v1/chat/channels/{channelId}/unread-count
GET /api/v1/chat/unread-summary
```

### البحث والإشعارات:

```
GET /api/v1/chat/search
  ?q=keyword
  &channels=channel1,channel2
  &from=user1
  &after=date
  &before=date

GET /api/v1/chat/notifications
  ?limit=20
  &unreadOnly=true

POST /api/v1/chat/notifications/{id}/mark-as-read
```

---

## 🎨 واجهات المستخدم

### 1. قائمة القنوات:

```
┌─────────────────────────────────┐
│ 💬 الدردشة                      │
├─────────────────────────────────┤
│ [🔍 البحث...]                   │
│ [➕ قناة جديدة]                 │
├─────────────────────────────────┤
│ القنوات المفضلة:               │
│ ☆ [📌] عام (5 جديد)            │
│ ☆ [💼] مبيعات (12 جديد)        │
│                                 │
│ جميع القنوات:                   │
│ ☆ [📦] مخزون (3 جديد)          │
│ ☆ [⚙️] إدارية                  │
│ ☆ [🆘] دعم العملاء            │
│                                 │
│ [↕️ أرشيف]                      │
└─────────────────────────────────┘
```

### 2. نافذة الرسائل:

```
┌──────────────────────────────────────────┐
│ 📌 عام                     [⋯]           │
├──────────────────────────────────────────┤
│                                          │
│ [10 سبتمبر، 2:30 PM]                   │
│ 👤 أحمد محمد                            │
│ مرحباً بالجميع! 👋                      │
│ [❤️ 3] [👍 5] [😂 1]                   │
│ [📌 Pin]  [💬 Reply]  [⋯]              │
│                                          │
│ 👤 فاطمة علي       2:35 PM              │
│ ⤿ Reply to أحمد                        │
│ شكراً! كيف حالك؟                        │
│ [❤️ 1]  [💬 Reply]                     │
│                                          │
│ [البحث] [🔔] [أفراد] [⋯]               │
├──────────────────────────────────────────┤
│ [@ mention]  [📎 attach]  [😊]          │
│ [اكتب الرسالة...]              [📤]    │
└──────────────────────────────────────────┘
```

### 3. الإشعارات:

```
🔔 @ أحمد mentioned you in #مبيعات
💬 New message from فاطمة
📌 Pinned message from أحمد in #عام
⚠️ Alert: High-priority issue in #support
```

---

## 🔒 الأمان والأداء

### الأمان:

```
✅ JWT Authentication
✅ Role-based Access Control (RBAC)
✅ Message Encryption (E2E)
✅ File Virus Scanning
✅ XSS/CSRF Protection
✅ SQL Injection Prevention
✅ Rate Limiting
✅ DDoS Protection
```

### الأداء:

```
⚡ WebSocket Connection Pooling
⚡ Message Caching (Redis)
⚡ Database Query Optimization
⚡ Lazy Loading Messages
⚡ Image Optimization
⚡ CDN for File Delivery
⚡ Compression (Gzip/Brotli)
⚡ Target: <100ms message delivery
```

---

## 📅 خطة التطوير (4 أسابيع)

### الأسبوع 1: الأساسيات
```
✅ قاعدة البيانات
✅ WebSocket Setup
✅ APIs الأساسية
```

### الأسبوع 2: الواجهة
```
✅ قائمة القنوات
✅ نافذة الرسائل
✅ إرسال الرسائل
```

### الأسبوع 3: الميزات المتقدمة
```
✅ الردود والتفاعلات
✅ المرفقات
✅ البحث
✅ الإشعارات
```

### الأسبوع 4: الاختبار والتحسينات
```
✅ اختبار الأداء
✅ اختبار الأمان
✅ تحسينات الواجهة
✅ التوثيق
```

---

## 🎯 مؤشرات النجاح

```
✅ جميع الرسائل تُسلم في <100ms
✅ الإشعارات تصل في الوقت الفعلي
✅ دعم 10,000+ مستخدم متزامن
✅ توفر 99.9%
✅ رضا المستخدم 4.8/5
```

---

*تم الإعداد بواسطة فريق التطوير*  
*النسخة: 2.0 | التاريخ: 2026-09-12*
