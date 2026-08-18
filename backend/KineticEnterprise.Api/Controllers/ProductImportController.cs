using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record ImportRowResult(int Row, string Name, string? Sku, string Action, string? Error);

public record ImportSummary(
    int TotalRows,
    int WillCreate,
    int WillUpdate,
    int WithErrors,
    bool Committed,
    List<ImportRowResult> Rows);

/// <summary>
/// استيراد كتالوج الأصناف من ملف إكسل أو CSV.
///
/// سبب وجوده: إدخال ألف صنف بثلاثة عشر حقلاً يدوياً = ثلاثة عشر ألف إدخال،
/// وهو وحده كان يمنع تسليم النظام لعميل حقيقي عنده كتالوج قائم.
///
/// يعمل على مرحلتين إلزامياً:
///   1. معاينة (dryRun=true): يُقرأ الملف ويُتحقَّق من كل صف ويُعاد التقرير
///      **بلا كتابة أي شيء**.
///   2. تنفيذ: بعد أن يرى المستخدم ماذا سيحدث بالضبط.
///
/// المرحلتان ليستا رفاهية: ملف فيه عمود سعر بمكان عمود التكلفة يقلب أسعار
/// كتالوج كامل، واكتشافه بعد الكتابة يعني استرجاع نسخة احتياطية.
/// </summary>
[ApiController]
[Route("api/products/import")]
[Authorize]
public class ProductImportController : ControllerBase
{
    private readonly AppDbContext _db;
    public ProductImportController(AppDbContext db) => _db = db;

    /// <summary>حد حجم الملف: 5 ميغابايت تكفي عشرات الآلاف من الصفوف.</summary>
    const long MaxFileBytes = 5 * 1024 * 1024;

    [HttpPost]
    [RequirePermission("inventory.manage")]
    [RequestSizeLimit(MaxFileBytes)]
    public async Task<ActionResult<ImportSummary>> Import(
        IFormFile file,
        [FromQuery] bool dryRun = true)
    {
        if (file is null || file.Length == 0)
        {
            return BadRequest(new { message = "لم يُرفَق ملف" });
        }
        if (file.Length > MaxFileBytes)
        {
            return BadRequest(new { message = "حجم الملف يتجاوز 5 ميغابايت" });
        }

        List<Dictionary<string, string>> rows;
        try
        {
            await using var stream = file.OpenReadStream();
            rows = SpreadsheetReader.Read(stream, file.FileName);
        }
        catch (NotSupportedException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (Exception)
        {
            return BadRequest(new { message = "تعذّرت قراءة الملف — تأكد أنه ‎.xlsx أو ‎.csv سليم" });
        }

        if (rows.Count == 0)
        {
            return BadRequest(new { message = "الملف فارغ أو لا يحوي سطر عناوين وصفوف بيانات" });
        }

        var orgId = Guid.Parse(User.FindFirstValue("organization_id")!);

        // الكتالوج الحالي مرة واحدة بدل استعلام لكل صف — ملف بألف صنف كان
        // سيُنتج ألفي استعلام.
        var existingBySku = await _db.Products
            .Where(p => !p.IsDeleted)
            .ToDictionaryAsync(p => p.Sku.ToLower(), p => p);

        var categories = await _db.ProductCategories.ToDictionaryAsync(c => c.Name.ToLower(), c => c.Id);
        var suppliers = await _db.Suppliers.Where(s => !s.IsDeleted)
            .ToDictionaryAsync(s => s.Name.ToLower(), s => s.Id);

        var results = new List<ImportRowResult>();
        var toCreate = new List<Product>();
        var toUpdate = new List<Product>();
        var seenSkus = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        for (var i = 0; i < rows.Count; i++)
        {
            var row = rows[i];
            var rowNumber = i + 2; // +1 لسطر العناوين، +1 لأن الترقيم يبدأ من 1

            var name = SpreadsheetReader.Value(row, "الاسم", "اسم الصنف", "الصنف", "name", "product");
            var sku = SpreadsheetReader.Value(row, "الرمز", "رمز الصنف", "sku", "code");
            var barcode = SpreadsheetReader.Value(row, "الباركود", "barcode");
            var salePrice = SpreadsheetReader.Number(
                SpreadsheetReader.Value(row, "سعر البيع", "السعر", "sale_price", "saleprice", "price"));
            var costPrice = SpreadsheetReader.Number(
                SpreadsheetReader.Value(row, "سعر التكلفة", "التكلفة", "cost_price", "costprice", "cost"));
            var reorder = SpreadsheetReader.Number(
                SpreadsheetReader.Value(row, "حد الطلب", "الحد الأدنى", "reorder_level", "reorder"));
            var unit = SpreadsheetReader.Value(row, "الوحدة", "unit", "unit_base") ?? "piece";
            var categoryName = SpreadsheetReader.Value(row, "التصنيف", "الفئة", "category");
            var supplierName = SpreadsheetReader.Value(row, "المورد", "المورّد", "supplier");
            var tracksStock = SpreadsheetReader.Boolean(
                SpreadsheetReader.Value(row, "يتبع المخزون", "tracks_stock", "trackstock")) ?? true;

            if (string.IsNullOrWhiteSpace(name))
            {
                results.Add(new ImportRowResult(rowNumber, "", sku, "خطأ", "اسم الصنف مفقود"));
                continue;
            }
            if (salePrice is null)
            {
                results.Add(new ImportRowResult(rowNumber, name, sku, "خطأ", "سعر البيع مفقود أو غير رقمي"));
                continue;
            }
            if (salePrice < 0 || (costPrice ?? 0) < 0)
            {
                results.Add(new ImportRowResult(rowNumber, name, sku, "خطأ", "سعر سالب"));
                continue;
            }

            // بلا رمز صريح يُشتق رمز ثابت من الاسم، وإلا استُورد نفس الملف
            // مرتين فتضاعف الكتالوج.
            var effectiveSku = string.IsNullOrWhiteSpace(sku) ? DeriveSku(name) : sku;

            if (!seenSkus.Add(effectiveSku))
            {
                results.Add(new ImportRowResult(rowNumber, name, effectiveSku, "خطأ", "رمز مكرَّر داخل الملف نفسه"));
                continue;
            }

            Guid? categoryId = null;
            if (categoryName is not null && !categories.TryGetValue(categoryName.ToLower(), out var cid))
            {
                results.Add(new ImportRowResult(rowNumber, name, effectiveSku, "خطأ",
                    $"التصنيف «{categoryName}» غير موجود — أنشئه أولاً"));
                continue;
            }
            else if (categoryName is not null)
            {
                categoryId = categories[categoryName.ToLower()];
            }

            Guid? supplierId = null;
            if (supplierName is not null && !suppliers.TryGetValue(supplierName.ToLower(), out _))
            {
                results.Add(new ImportRowResult(rowNumber, name, effectiveSku, "خطأ",
                    $"المورّد «{supplierName}» غير موجود — أنشئه أولاً"));
                continue;
            }
            else if (supplierName is not null)
            {
                supplierId = suppliers[supplierName.ToLower()];
            }

            if (existingBySku.TryGetValue(effectiveSku.ToLower(), out var existing))
            {
                results.Add(new ImportRowResult(rowNumber, name, effectiveSku, "تحديث", null));
                if (!dryRun)
                {
                    existing.Name = name;
                    existing.Barcode = barcode ?? existing.Barcode;
                    existing.SalePrice = salePrice.Value;
                    existing.CostPrice = costPrice ?? existing.CostPrice;
                    existing.ReorderLevel = reorder ?? existing.ReorderLevel;
                    existing.UnitBase = unit;
                    existing.CategoryId = categoryId ?? existing.CategoryId;
                    existing.SupplierId = supplierId ?? existing.SupplierId;
                    existing.TracksStock = tracksStock;
                    toUpdate.Add(existing);
                }
            }
            else
            {
                results.Add(new ImportRowResult(rowNumber, name, effectiveSku, "جديد", null));
                if (!dryRun)
                {
                    toCreate.Add(new Product
                    {
                        // OrganizationId من التوكن دائماً — وإلا رفضته
                        // BLOCK PREDICATE بصمت.
                        OrganizationId = orgId,
                        Sku = effectiveSku,
                        Name = name,
                        Barcode = barcode,
                        SalePrice = salePrice.Value,
                        CostPrice = costPrice ?? 0,
                        ReorderLevel = reorder ?? 0,
                        UnitBase = unit,
                        CategoryId = categoryId,
                        SupplierId = supplierId,
                        TracksStock = tracksStock,
                    });
                }
            }
        }

        var willCreate = results.Count(r => r.Action == "جديد");
        var willUpdate = results.Count(r => r.Action == "تحديث");
        var withErrors = results.Count(r => r.Action == "خطأ");

        if (!dryRun)
        {
            if (withErrors > 0)
            {
                // كل شيء أو لا شيء: استيراد نصف ملف يترك الكتالوج في حالة لا
                // يعرف صاحبه ما فيها، وإعادة المحاولة تضاعف ما نجح.
                return BadRequest(new
                {
                    message = $"الملف يحوي {withErrors} صفاً بأخطاء — صحّحها ثم أعد الاستيراد",
                    rows = results.Where(r => r.Action == "خطأ").Take(50),
                });
            }

            _db.Products.AddRange(toCreate);
            _db.LogAudit(orgId, CurrentUserId(), "products.imported", "products", null,
                newValues: new { Created = toCreate.Count, Updated = toUpdate.Count, File = file.FileName });
            await _db.SaveChangesAsync();
        }

        return new ImportSummary(
            results.Count, willCreate, willUpdate, withErrors, !dryRun,
            // الأخطاء أولاً: هي ما يحتاج المستخدم رؤيته، والقائمة قد تطول.
            results.OrderBy(r => r.Action == "خطأ" ? 0 : 1).Take(200).ToList());
    }

    /// <summary>
    /// قالب فارغ بالأعمدة المتوقَّعة — يُنزّله المستخدم ويملأه، فلا يخمّن
    /// أسماء الأعمدة ولا يفشل استيراده بسببها.
    /// </summary>
    [HttpGet("template")]
    [RequirePermission("inventory.manage")]
    public IActionResult Template()
    {
        var csv = "﻿" + // BOM حتى يفتح إكسل العربية بالترميز الصحيح
            "الاسم,الرمز,الباركود,سعر البيع,سعر التكلفة,حد الطلب,الوحدة,التصنيف,المورد,يتبع المخزون\r\n" +
            "مثال: أرز 5كغ,RICE-5,6221234567890,45,38,10,piece,,,نعم\r\n";

        return File(System.Text.Encoding.UTF8.GetBytes(csv), "text/csv", "قالب-استيراد-الأصناف.csv");
    }

    /// <summary>
    /// رمز ثابت مشتق من الاسم للصفوف التي لا رمز لها.
    ///
    /// الثبات هو المقصود: استيراد نفس الملف مرتين يجب أن يُحدِّث الأصناف لا
    /// أن يضاعفها. رمز عشوائي كان سيجعل كل استيراد يُنشئ كتالوجاً جديداً.
    /// </summary>
    static string DeriveSku(string name)
    {
        var cleaned = new string(name.Where(c => !char.IsWhiteSpace(c)).ToArray());
        var hash = System.Security.Cryptography.SHA256.HashData(
            System.Text.Encoding.UTF8.GetBytes(cleaned.ToLowerInvariant()));
        return "AUTO-" + Convert.ToHexString(hash)[..10];
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)
            ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
