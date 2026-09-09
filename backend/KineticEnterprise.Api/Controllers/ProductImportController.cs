using System.Text.Json.Serialization;
using ClosedXML.Excel;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace KineticEnterprise.Api.Controllers;

/// استيراج منتجات من ملفات Excel
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class ProductImportController(AppDbContext db, ICurrentUser user) : ControllerBase
{
    [HttpPost("preview")]
    public async Task<IActionResult> PreviewAsync(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { error = "لا ملف تم رفعه" });

        try
        {
            using var stream = file.OpenReadStream();
            using var workbook = new XLWorkbook(stream);
            var worksheet = workbook.Worksheet(1);

            var rows = new List<dynamic>();
            int totalRows = 0;

            foreach (var row in worksheet.RowsUsed().Skip(1).Take(10))
            {
                var name = row.Cell(3).Value?.ToString()?.Trim();
                if (string.IsNullOrWhiteSpace(name)) continue;

                rows.Add(new
                {
                    productName = name,
                    barcode = row.Cell(4).Value?.ToString()?.Trim() ?? "",
                    stock = row.Cell(8).Value?.ToString()?.Trim() ?? "0",
                    costPrice = row.Cell(9).Value?.ToString()?.Trim() ?? "0",
                    sellingPrice = row.Cell(10).Value?.ToString()?.Trim() ?? "0",
                });
                totalRows++;
            }

            return Ok(new { totalRows = totalRows + 5, sampleRows = rows });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = $"خطأ: {ex.Message}" });
        }
    }

    [HttpPost("import")]
    public async Task<IActionResult> ImportAsync(IFormFile file)
    {
        if (file == null)
            return BadRequest(new { error = "لا ملف تم رفعه" });

        try
        {
            using var stream = file.OpenReadStream();
            using var workbook = new XLWorkbook(stream);
            var worksheet = workbook.Worksheet(1);

            int imported = 0;
            int updated = 0;

            foreach (var row in worksheet.RowsUsed().Skip(1))
            {
                var name = row.Cell(3).Value?.ToString()?.Trim();
                if (string.IsNullOrWhiteSpace(name)) continue;

                var barcode = row.Cell(4).Value?.ToString()?.Trim() ?? Guid.NewGuid().ToString();
                var stock = double.TryParse(row.Cell(8).Value?.ToString() ?? "0", out var s) ? s : 0;
                var cost = double.TryParse(row.Cell(9).Value?.ToString() ?? "0", out var c) ? c : 0;
                var price = double.TryParse(row.Cell(10).Value?.ToString() ?? "0", out var p) ? p : 0;

                var existing = await db.Products
                    .Where(pr => pr.OrganizationId == user.OrganizationId && pr.Barcode == barcode)
                    .FirstOrDefaultAsync();

                if (existing != null)
                {
                    existing.SellingPrice = price;
                    existing.CostPrice = cost;
                    updated++;
                }
                else
                {
                    await db.Products.AddAsync(new Product
                    {
                        Id = Guid.NewGuid().ToString(),
                        OrganizationId = user.OrganizationId,
                        Name = name,
                        Barcode = barcode,
                        SellingPrice = price,
                        CostPrice = cost,
                        Status = "active",
                    });
                    imported++;
                }
            }

            await db.SaveChangesAsync();
            return Ok(new { imported, updated, message = $"تم استيراج {imported} منتج وتحديث {updated}" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }
}
