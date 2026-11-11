# WSU SmartTransit – Flutter app

One Flutter app, built from *WSU SmartTransit – Phase 1 Engineering Design*. The signed-in user's highest role picks the experience:

| Role | Experience |
|---|---|
| Student | Apply for transport (route resolved from the academic-year residence assignment), track application status, QR transport pass, route timetable, notifications + service alerts |
| Driver | Assigned trips, bus selection, QR scan / manual code entry, server-side boarding verification, **offline scan queue + sync**, scan history |
| Transport Officer | Review / approve / reject applications, view routes, residences, trips, buses, post service alerts, limited audit log |
| Transport Manager | Everything above + manage routes, residences, **academic-year route assignments** (history kept), trips, buses, usage dashboard, scan log |
| Super Admin | Everything above + users & roles, full audit log, session revocation |

Security features from the design doc: MFA prompt for privileged roles, lockout after 5 failed logins, tokens in the platform keystore (`flutter_secure_storage`), refresh-token rotation on 401, permission-driven UI (the server stays authoritative), audit logging (mock backend).

## Run it

```bash
cd smarttransit_app
flutter create --platforms=android,ios .   # generates platform folders (keeps lib/ and pubspec.yaml)
flutter pub get
flutter run                                # runs against the built-in mock backend
flutter test                               # business-rule tests for the mock backend
```

**Camera permission** (driver QR scanning):
- Android: add `<uses-permission android:name="android.permission.CAMERA"/>` to `android/app/src/main/AndroidManifest.xml`; set `minSdkVersion 21` or higher.
- iOS: add `NSCameraUsageDescription` to `ios/Runner/Info.plist`.

Requires Flutter 3.27+ (Dart 3.3+).

### Demo accounts (mock mode)
| Account | Password | Notes |
|---|---|---|
| student1@wsu.ac.za | Student#123 | no application yet – try applying |
| student2@wsu.ac.za | Student#123 | has an active Southernwood pass (code `DEMO-PASS-S2`) |
| driver@wsu.ac.za | Driver#123 | assigned to Southernwood + Town trips |
| officer@wsu.ac.za | Officer#123 | MFA code `123456` |
| manager@wsu.ac.za | Manager#123 | MFA code `123456` |
| admin@wsu.ac.za | Admin#123 | MFA code `123456` |

End-to-end demo: student1 applies → officer approves → student1's Pass tab shows the QR → driver enters the pass code (or scans the QR from another device) on a Town trip. Residences and times in the mock data are **sample data** – only the four route names and Langham House come from the document.

## Connect to the real backend

```bash
flutter run --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=https://your-host/api/v1
```

`HttpRepository` (lib/data/http_repository.dart) expects JSON with the column names from the Phase 1 schema:

| Purpose | Endpoint |
|---|---|
| Auth | `POST /auth/login` `{email,password,mfa_code?}` → `{access_token, refresh_token, user:{user_id,email,first_name,last_name,roles:[…],student_number?}, permissions:[…]}`; MFA needed → error `code: "MFA_REQUIRED"` · `POST /auth/refresh` · `POST /auth/logout` · `GET /auth/me` |
| Config | `GET/POST/PATCH /routes`, `/residences`, `/trips`, `/buses` · `GET/POST /route-residence-assignments?academic_year=` |
| Applications | `GET /applications?status=` · `GET /applications?mine=true` · `POST /applications {residence_id}` · `PATCH /applications/:id/approve` · `PATCH /applications/:id/reject {rejection_reason}` |
| Pass | `GET /passes/me` (returns `pass_token`, route/residence names; 404 `NOT_FOUND` if none) |
| Driver | `GET /drivers/me/trips` · `POST /scans {token,trip_id,bus_id,scanned_at,client_id}` → `{status: ACCEPTED|REJECTED|DUPLICATE, message, student_name}` (dedupe on `client_id`) · `GET /scans?mine=true` |
| Other | `/service-alerts`, `/notifications`, `/reports/usage`, `/users`, `/audit-logs`, `/sessions` |

Endpoints not named in the design document (`/auth/me`, `/passes/me`, `/drivers/me/trips`, `/notifications`, `/applications?mine=true`, `/users`, `/audit-logs`, `/sessions`) are my assumptions; adjust `http_repository.dart` to match your API. The QR payload is `WSUST:<pass_token>`; the server stores only `pass_token_hash`.

## Layout
```
lib/
  core/      config, theme, permission codes (role → permission mirror), formatting
  models/    domain classes matching the schema
  data/      Repository interface · MockRepository · HttpRepository
  state/     AppState (session + offline scan queue)
  screens/   login, student/, driver/, admin/, shared/
test/        mock-backend tests: workflow, RBAC, MFA, lockout, history, scans
```

## Not in this phase (per the design doc)
Signed offline authorisation dataset (the driver app queues scans offline but still needs a connection to *verify*), NFC/card scanning, email notifications, push, student self-registration/password reset, route-level driver assignment UI.
