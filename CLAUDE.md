# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Kinetic Enterprise** is a complete Arabic ERP system for sales, inventory, and financial management. It's a full-stack application with:
- **Frontend:** Flutter (Web, Android, iOS)
- **Backend:** ASP.NET Core (.NET 8) with SQL Server
- **Database:** SQL Server 2019+ with Row-Level Security via Security Policies
- **Real-time:** SignalR for instant notifications
- **Authentication:** JWT with WebAuthn (Passkeys) support

Key architectural decisions:
- **No external SaaS dependencies:** Everything runs on Windows Server with SQL Server
- **Dynamic branding:** Organizations control their colors/logo via database—zero code changes needed for multi-tenant deployment
- **Modular features:** Each feature (inventory, POS, customers, payroll, etc.) is completely isolated in both Flutter and .NET

## Build and Development Commands

### Flutter Frontend

```bash
# Get dependencies
flutter pub get

# Code generation (Freezed models, JSON serialization, routing)
flutter pub run build_runner build --delete-conflicting-outputs

# Run on Chrome (development)
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5001/api

# Run on Android
flutter run -d android --dart-define=API_BASE_URL=https://erp.example.com/api

# Build web release
flutter build web --release

# Build Android APK (release)
flutter build apk --release --dart-define=API_BASE_URL=https://erp.example.com/api

# Lint and analyze
dart analyze
dart fix --apply  # auto-fix lints

# Run unit tests (if any)
flutter test
```

### ASP.NET Core Backend

```bash
cd backend/KineticEnterprise.Api

# Restore NuGet packages
dotnet restore

# Run locally (HTTPS on localhost:5001)
dotnet run

# Watch mode (auto-reload on save)
dotnet watch run

# Build release
dotnet publish -c Release -o publish/

# Lint / analyze
dotnet format --verify-no-changes  # check only
dotnet format  # auto-fix

# Database migrations (if using EF Core Migrations)
dotnet ef migrations add MigrationName
dotnet ef database update
```

### Database

```bash
# Apply schema to SQL Server
# Run docs/DATABASE_SCHEMA_SQLSERVER.sql in SQL Server Management Studio
# Or from sqlcmd:
sqlcmd -S SERVER_NAME -i docs/DATABASE_SCHEMA_SQLSERVER.sql

# Verify connection from backend:
cd backend
dotnet run  # Logs will show if connection succeeds
```

## Architecture

### Frontend (Flutter) — `lib/`

**Structure:**
```
lib/
├── features/            # One folder per business module
│   ├── auth/            # Login, passkeys, JWT handling
│   ├── pos/             # Point of sale (cash checkout, wallet, returns)
│   ├── inventory/       # Stock management, transfers
│   ├── customers/       # Customer profiles, tags, balances
│   ├── invoices/        # Invoice history and reprints
│   ├── dashboard/       # Admin dashboards
│   └── [others]/        # Customers, payroll, accounting, etc.
├── core/
│   ├── auth/            # JWT token management, current user
│   ├── network/         # ApiClient (Dio + interceptors), offline queue
│   ├── router/          # GoRouter navigation, deep linking
│   ├── theme/           # Dynamic color system, AppTheme, BrandingProvider
│   ├── responsive/      # Breakpoints for mobile/tablet/desktop
│   ├── printing/        # Receipt printing, thermal printer integration
│   └── [others]/        # Shortcuts, feedback, auth providers
└── shared/
    └── widgets/         # Reusable UI: tables, cards, currency badge, dialog helpers
```

**Key Patterns:**

1. **State Management:** Riverpod (see `lib/core/auth/current_user.dart` for a reference provider)
   ```dart
   final myProvider = FutureProvider((ref) async { ... });
   final myState = StateNotifierProvider<MyNotifier, MyState>((_) => MyNotifier());
   ```

2. **Feature Structure:** Each feature folder contains:
   - `presentation/` — Screens and widgets
   - `data/` — Providers and API calls (use `ApiClient.instance.dio.get(...)`)
   - `models/` — Freezed models with JSON serialization

3. **API Calls:** Always use `ApiClient.instance.dio` (configured in `core/network/api_client.dart`):
   ```dart
   final response = await ApiClient.instance.dio.get('/endpoint', queryParameters: {...});
   ```

4. **Error Handling:** Wrap API calls in try-catch; show user-friendly errors via `ScaffoldMessenger` or dialogs

5. **Responsive Design:** Use `Breakpoints.isDesktop(context)` and `MediaQuery` to adapt layouts:
   ```dart
   final isDesktop = Breakpoints.isDesktop(context);
   return isDesktop ? horizontalLayout() : verticalLayout();
   ```

6. **Theme:** All colors come from `ref.read(brandingProvider)` — **never hardcode colors**:
   ```dart
   final branding = ref.read(brandingProvider).valueOrNull;
   color: branding?.primaryColor ?? AppColors.primary,
   ```

### Backend (.NET) — `backend/KineticEnterprise.Api/`

**Structure:**
```
KineticEnterprise.Api/
├── Controllers/         # API endpoints grouped by domain (e.g., InvoicesController, ProductsController)
├── Models/             # Entity definitions (Freezed-like classes, but in C#)
├── Data/               # DbContext, Security Policy helpers (RowLevelSecurityMiddleware)
├── Services/           # Business logic (e.g., WalletBalances for calculating customer balances)
├── Middleware/         # JWT auth, RLS, error handling, logging
├── Authorization/      # Permission checks (can('invoices.create'))
├── Hubs/              # SignalR hubs for real-time (NotificationsHub)
├── HostedServices/     # Background jobs (email, deductions, maintenance)
├── Program.cs          # Startup config, middleware pipeline, dependency injection
└── appsettings.json    # DB connection, JWT key, CORS, logging
```

**Key Patterns:**

1. **Controllers:** Inherit `ControllerBase`, decorate with `[ApiController]`, one domain per class:
   ```csharp
   [ApiController]
   [Route("api/[controller]")]
   public class InvoicesController(AppDbContext db, ICurrentUser user) : ControllerBase
   {
       [HttpGet("{id}")]
       public async Task<IActionResult> GetAsync(string id) { ... }
   }
   ```

2. **Row-Level Security:** Automatic via middleware—queries are filtered by `SESSION_CONTEXT('organization_id')` and `SESSION_CONTEXT('branch_id')`. No manual filtering needed.

3. **Async/Await:** All database calls must be async (`.ToListAsync()`, `.FirstOrDefaultAsync()`, etc.)

4. **DTOs:** Use C# records for request/response DTOs:
   ```csharp
   public record CreateInvoiceRequest(string CustomerId, List<LineItem> Lines);
   ```

5. **Validation:** Use `ModelState.IsValid` or throw `BadRequestObjectResult`

6. **Error Responses:** Return appropriate HTTP status codes (400 for validation, 404 for not found, 500 for server errors)

7. **SignalR:** Broadcast notifications to connected clients:
   ```csharp
   await _hubContext.Clients.Group(organizationId).SendAsync("InvoiceCreated", invoiceData);
   ```

### Database — `docs/DATABASE_SCHEMA_SQLSERVER.sql`

**Key Concepts:**

1. **Organization Isolation:** Every table has `organization_id` and (usually) `branch_id`
2. **Security Policies:** SQL Server automatically filters rows based on `SESSION_CONTEXT`:
   ```sql
   EXEC sp_set_session_context @key=N'organization_id', @value=@orgId;
   ```
3. **No Supabase RLS:** We use native SQL Server RLS—simpler, faster, more auditable

4. **Tables:** See `ARCHITECTURE.md` for complete domain model. Key tables:
   - `organizations` — Multi-tenancy
   - `users` — Staff accounts with WebAuthn credentials
   - `customers` — Customer profiles with tags, balances, categories
   - `products` — Inventory items with prices and stock
   - `invoices` / `invoice_lines` — Sales transactions
   - `wallet_transactions` — Customer account ledger
   - `permissions` — Role-based access control
   - Others: branches, expenses, payroll, audit logs, etc.

## Adding New Features

### 1. Add a Backend Endpoint

1. **Create/edit** `Controllers/YourDomainController.cs`:
   ```csharp
   [ApiController]
   [Route("api/your-domain")]
   public class YourDomainController(AppDbContext db, ICurrentUser user) : ControllerBase
   {
       [HttpGet]
       [Authorize]  // Require JWT
       public async Task<IActionResult> ListAsync()
       {
           var items = await db.YourEntities
               .Where(x => x.OrganizationId == user.OrganizationId)
               .ToListAsync();
           return Ok(items);
       }
   }
   ```

2. **Update `Program.cs`** if needed (add new services, Swagger docs, etc.)

3. **Test with Swagger:** Run the backend and visit `https://localhost:5001/swagger`

### 2. Add a Flutter Feature

1. **Create folder:** `lib/features/your_feature/`

2. **Add files:**
   ```
   your_feature/
   ├── presentation/
   │   └── your_feature_screen.dart
   ├── data/
   │   └── your_feature_providers.dart
   └── models/
       └── your_model.dart
   ```

3. **Define models** with Freezed (code generation):
   ```dart
   @freezed
   class Item with _$Item {
     const factory Item({
       required String id,
       required String name,
     }) = _Item;
     
     factory Item.fromJson(Map<String, dynamic> json) => _$ItemFromJson(json);
   }
   ```

4. **Create provider** to fetch data:
   ```dart
   final itemsProvider = FutureProvider((ref) async {
     final response = await ApiClient.instance.dio.get('/api/items');
     return (response.data as List).map((e) => Item.fromJson(e)).toList();
   });
   ```

5. **Build UI** with responsive widgets from `shared/widgets/`

6. **Update routing:** Add route in `core/router/app_router.dart`:
   ```dart
   GoRoute(path: '/your-feature', builder: (_, __) => YourFeatureScreen()),
   ```

### 3. Add Database Table

1. **Edit** `docs/DATABASE_SCHEMA_SQLSERVER.sql`
2. **Add table** with `organization_id`, `branch_id`, timestamps, audit fields
3. **Add Security Policy** to filter by org/branch
4. **Update Entity** in `backend/Models/Entities.cs` (or create new file)
5. **Update DbContext** in `backend/Data/AppDbContext.cs` to include the table:
   ```csharp
   public DbSet<YourEntity> YourEntities => Set<YourEntity>();
   ```
6. **Create migration** (if using EF Core): `dotnet ef migrations add AddYourEntity`
7. **Apply schema** to your database

## Deployment

### Windows Server IIS

1. **Publish Backend:**
   ```bash
   cd backend
   dotnet publish -c Release -o C:\kinetic\backend
   ```

2. **Configure IIS:**
   - Install ASP.NET Core Hosting Bundle
   - Create site pointing to `C:\kinetic\backend` (wwwroot)
   - Ensure `appsettings.Production.json` has correct DB connection + JWT key

3. **Publish Frontend:**
   ```bash
   flutter build web --release
   # Copy build/web/* to C:\kinetic\wwwroot (or IIS site folder)
   ```

4. **Verify:**
   ```powershell
   curl https://localhost/api/health
   ```

See `BUILD_AND_DEPLOY_INSTRUCTIONS.md` and `DEPLOYMENT.md` for detailed Windows server setup.

### Android Release Build

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://your-domain.com/api
```

Requires signing key in `android/key.properties` (create via `keytool`). See `DEPLOYMENT.md` section 4.1.

## Important Notes

### JWT & Authentication

- Backend issues JWT tokens (in `Authorization` header)
- Frontend stores token in secure storage (`flutter_secure_storage`)
- Middleware automatically validates and extracts `organization_id` / `branch_id` / `user_id`
- Passkeys (WebAuthn) supported—see `backend/Authorization/WebAuthn.cs`

### Real-time Updates

- SignalR Hub handles live notifications (new invoices, inventory alerts, etc.)
- Client connects via `signalr_netcore` after login
- Subscribe to groups by organization: `await connection.InvokeAsync("JoinOrganization", orgId)`

### Offline Queue

- POS can queue transactions when offline (network failure)
- See `core/network/offline_queue.dart` and `OfflineQueueNotifier`
- Automatically retries when connection restored

### Printing & Barcodes

- Thermal receipt printer integration in `core/printing/receipt_printer.dart`
- Barcode generation via `barcode` package
- PDF receipts via `pdf` + `printing` packages

### Multi-tenant & Branding

- All data is filtered by organization automatically (via Security Policy)
- Colors/logo come from `organizations` table → `BrandingProvider` in Flutter
- Adding a new customer/org requires **zero code changes**—just insert DB row

## Debugging & Troubleshooting

### Backend Won't Start

1. Check SQL Server is running: `sqlcmd -S (local) -Q "SELECT @@VERSION"`
2. Check appsettings.json connection string
3. Check JWT key is set: `appsettings.json` must have `"JwtSecretKey": "your-key"`

### Frontend API Calls Fail

1. Check `dart_define` API_BASE_URL is correct
2. Check backend is running and accessible
3. Check CORS in `Program.cs` allows Flutter app origin
4. Check JWT token is valid (log it in `ApiClient`)

### Database Permission Denied

- Verify user running backend has SQL Server login + db_owner role
- Check Security Policies are created (see `DATABASE_SCHEMA_SQLSERVER.sql`)

### Hot Reload Doesn't Work

```bash
flutter clean
flutter pub get
flutter run -d chrome
```

## Key Files Reference

| File | Purpose |
|------|---------|
| `lib/core/network/api_client.dart` | Dio setup, JWT injection, error handling |
| `lib/core/theme/app_theme.dart` | Color system, theming logic |
| `lib/core/router/app_router.dart` | Navigation routes, deep links |
| `backend/Program.cs` | Middleware, DI, database config |
| `backend/Data/AppDbContext.cs` | Entity model, RLS configuration |
| `docs/DATABASE_SCHEMA_SQLSERVER.sql` | Complete DB schema with Security Policies |
| `docs/ARCHITECTURE.md` | Full domain model and feature list |

## Performance Optimization Tips

1. **Flutter:** Use `LayoutBuilder` / `MediaQuery` sparingly; prefer `Breakpoints`
2. **Flutter:** Cache network responses in providers (use `cacheTime` parameter)
3. **Backend:** Use `.AsNoTracking()` for read-only queries
4. **Backend:** Index frequently queried columns (`organization_id`, `created_at`)
5. **Database:** Avoid N+1 queries; use `.Include()` in EF Core or joins in SQL
6. **Printing:** Cache logos locally to avoid re-downloading on every receipt

## Contributing Guidelines

- **Commits:** Use conventional commits (`feat:`, `fix:`, `refactor:`, `docs:`)
- **Code Style:** Follow Dart/C# conventions; use `dart analyze` and `dotnet format`
- **Testing:** Write unit tests for business logic; acceptance tests for APIs
- **PR Description:** Link to GitHub issues; describe what changed and why
- **Branches:** Feature branches from `main` (e.g., `feat/customer-tags`, `fix/printing-timeout`)
