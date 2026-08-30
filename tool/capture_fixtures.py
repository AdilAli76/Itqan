"""يلتقط ردوداً حقيقية من الخادم المحلي ويحفظها كعيّنات لجولة اللقطات.

لماذا عيّنات ملتقطة لا بيانات مكتوبة يدوياً: الشكل الذي أكتبه بيدي يعكس
ما أظنّه لا ما يُرسله الخادم فعلاً — وهذا بالضبط أصل العطل الذي كسر تسعة
مستهلكين حين تغيّر عقد نقاط النهاية. العيّنة الملتقطة تحمل الشكل الحقيقي،
فتكشف أي انفصال بين الخادم والواجهة عند أول تشغيل.

التشغيل (والخادم يعمل على المنفذ 5000):
    python tool/capture_fixtures.py

يكتب test/support/fixtures/*.json — ملفات نصّية تُراجَع في Git، فيظهر أي
تغيّر في عقد الـAPI ضمن الفروقات بدل أن يمرّ صامتاً.
"""
import base64
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')

SETTINGS = 'backend/KineticEnterprise.Api/appsettings.Development.json'
BASE = 'http://localhost:5000/api'
OUT = 'test/support/fixtures'

# المسارات التي تستدعيها الشاشات فعلياً — مستخرجة من ملفات data/.
PATHS = [
    '/organizations/me',
    '/permissions/me',
    '/permissions/catalog',
    '/permissions/matrix',
    '/branches',
    '/products/inventory?page=1&pageSize=50',
    # شريط الصلاحية على شاشة نقطة البيع — راجع posExpiryAlertProvider.
    '/products/expiry-alerts?withinDays=30&limit=10',
    # نشرات الأدوية — إصدار الصيدليات (شاشة مالك المنصّة).
    '/medicine-reference?page=1&pageSize=50',
    # دفتر الوصفات — إصدار الصيدليات.
    '/prescriptions?page=1&pageSize=50',
    # تقرير إعادة الطلب.
    '/reports/reorder?windowDays=90&coverageDays=14&onlyBelowThreshold=true',
    '/categories',
    '/suppliers',
    '/customers?page=1&pageSize=50',
    '/sponsors',
    '/invoices?page=1&pageSize=50',
    '/wallet-cards?page=1&pageSize=50',
    '/purchase-orders',
    '/stock-transfers',
    '/stock-counts',
    '/notifications',
    '/audit-log?page=1&pageSize=50',
    '/audit-log/entity-tables',
    '/users',
    '/users/login-history',
    '/reports/sales-summary',
    '/reports/inventory-summary',
    '/reports/debt-aging',
    '/reports/inventory-valuation',
    '/insights',
    '/license/me',
    '/organizations/me/settings',
    '/organizations/me/barcode-template',
    '/platform-settings',
    '/platform/organizations',
]


def token(cfg, user_id, org_id):
    def b64(b):
        return base64.urlsafe_b64encode(b).rstrip(b'=').decode()

    now = int(time.time())
    payload = {
        'sub': user_id,
        'organization_id': org_id,
        'role': 'super_admin',
        'is_platform_admin': 'True',
        'iss': cfg['Jwt']['Issuer'],
        'aud': cfg['Jwt']['Audience'],
        'exp': now + 900,
        'iat': now,
    }
    header = b64(json.dumps({'alg': 'HS256', 'typ': 'JWT'}, separators=(',', ':')).encode())
    body = b64(json.dumps(payload, separators=(',', ':')).encode())
    sig = hmac.new(cfg['Jwt']['Key'].encode(), f'{header}.{body}'.encode(), hashlib.sha256).digest()
    return f'{header}.{body}.{b64(sig)}'


def slug(path):
    """اسم ملف مشتقّ من المسار — بلا معاملات الاستعلام."""
    clean = path.split('?')[0].strip('/')
    return clean.replace('/', '_') or 'root'


def main():
    if not os.path.exists(SETTINGS):
        print('لا ملف إعدادات تطوير — شغّل tool/run_local.ps1 -SetupOnly أولاً')
        return 1
    cfg = json.load(open(SETTINGS, encoding='utf-8-sig'))

    user_id = os.environ.get('TOUR_USER_ID', 'cb146af1-51c9-4a50-9202-475bd5c1a036')
    org_id = os.environ.get('TOUR_ORG_ID', '3be3ba8b-3053-4267-8b06-fb6d2bc64981')
    tok = token(cfg, user_id, org_id)

    os.makedirs(OUT, exist_ok=True)
    index = {}
    ok = fail = 0

    for path in PATHS:
        req = urllib.request.Request(BASE + path)
        req.add_header('Authorization', 'Bearer ' + tok)
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                data = json.loads(r.read().decode() or 'null')
            name = slug(path)
            with open(os.path.join(OUT, name + '.json'), 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            index[path.split('?')[0]] = name + '.json'
            size = len(data) if isinstance(data, (list, dict)) else 0
            print(f'  ✓ {path:<44} {size} عنصراً')
            ok += 1
        except urllib.error.HTTPError as e:
            print(f'  ✗ {path:<44} HTTP {e.code}')
            fail += 1
        except Exception as e:
            print(f'  ✗ {path:<44} {str(e)[:60]}')
            fail += 1

    with open(os.path.join(OUT, '_index.json'), 'w', encoding='utf-8') as f:
        json.dump(index, f, ensure_ascii=False, indent=2)

    print(f'\nالتُقط {ok} · فشل {fail} · الوجهة {OUT}/')
    return 0 if fail == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
