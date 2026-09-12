using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Models;
using KineticEnterprise.Api.Services;

namespace KineticEnterprise.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[RequireModule("inventory")]
public class InventoriesController : ControllerBase
{
    private readonly InventoryService _inventoryService;
    private readonly InventoryAlertService _alertService;
    private readonly IHttpContextAccessor _httpContextAccessor;

    public InventoriesController(InventoryService inventoryService, InventoryAlertService alertService,
        IHttpContextAccessor httpContextAccessor)
    {
        _inventoryService = inventoryService;
        _alertService = alertService;
        _httpContextAccessor = httpContextAccessor;
    }

    private Guid GetOrganizationId()
    {
        var org = _httpContextAccessor.HttpContext?.Items["OrganizationId"] as string;
        return string.IsNullOrEmpty(org) ? Guid.Empty : Guid.Parse(org);
    }

    private Guid? GetUserId()
    {
        var user = _httpContextAccessor.HttpContext?.Items["UserId"] as string;
        return string.IsNullOrEmpty(user) ? null : Guid.Parse(user);
    }

    // ============================================================================
    // Batch Management
    // ============================================================================

    [HttpPost("batches")]
    [RequirePermission("create_batch")]
    public async Task<ActionResult<object>> CreateBatch([FromBody] CreateBatchRequest request)
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        try
        {
            var batch = await _inventoryService.CreateBatchAsync(orgId, request);
            return CreatedAtAction(nameof(GetBatch), new { id = batch.Id }, batch);
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet("batches/{id}")]
    [RequirePermission("view_batch")]
    public async Task<ActionResult<object>> GetBatch(Guid id)
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        var batch = await _inventoryService.GetBatchAsync(id, orgId);
        if (batch == null)
            return NotFound();

        var movements = await _inventoryService.GetBatchMovementsAsync(id, orgId);
        var serials = await _inventoryService.GetSerialNumbersAsync(id, orgId);

        return Ok(new
        {
            batch.Id,
            batch.ProductId,
            batch.BatchNumber,
            batch.ManufacturingDate,
            batch.ExpiryDate,
            batch.QuantityReceived,
            batch.QuantityAvailable,
            batch.WarehouseId,
            batch.CostPerUnit,
            batch.QualityStatus,
            batch.CreatedAt,
            batch.UpdatedAt,
            SerialNumbers = serials,
            RecentMovements = movements,
            TotalValue = batch.QuantityAvailable * batch.CostPerUnit
        });
    }

    [HttpGet("products/{productId}/batches")]
    [RequirePermission("view_batch")]
    public async Task<ActionResult<List<ProductBatchDto>>> GetProductBatches(Guid productId)
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        var batches = await _inventoryService.GetBatchesByProductAsync(productId, orgId);
        return Ok(batches);
    }

    [HttpPut("batches/{id}")]
    [RequirePermission("edit_batch")]
    public async Task<ActionResult<object>> UpdateBatch(Guid id, [FromBody] UpdateBatchRequest request)
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        try
        {
            var batch = await _inventoryService.UpdateBatchAsync(id, orgId, request);
            return Ok(batch);
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpDelete("batches/{id}")]
    [RequirePermission("delete_batch")]
    public async Task<IActionResult> DeleteBatch(Guid id)
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        try
        {
            await _inventoryService.DeleteBatchAsync(id, orgId);
            return NoContent();
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    // ============================================================================
    // Serial Numbers
    // ============================================================================

    [HttpPost("batches/{batchId}/serials")]
    [RequirePermission("create_serial")]
    public async Task<IActionResult> AddSerialNumbers(Guid batchId, [FromBody] AddSerialNumbersRequest request)
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        try
        {
            await _inventoryService.AddSerialNumbersAsync(orgId, batchId, request.SerialNumbers, request.Barcodes);
            return Ok(new { message = "Serial numbers added successfully" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet("batches/{batchId}/serials")]
    [RequirePermission("view_serial")]
    public async Task<ActionResult<List<SerialNumberDto>>> GetSerialNumbers(Guid batchId)
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        try
        {
            var serials = await _inventoryService.GetSerialNumbersAsync(batchId, orgId);
            return Ok(serials);
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    // ============================================================================
    // Batch Movements
    // ============================================================================

    [HttpPost("batches/{batchId}/movements")]
    [RequirePermission("record_movement")]
    public async Task<IActionResult> RecordMovement(Guid batchId, [FromBody] RecordBatchMovementRequest request)
    {
        var orgId = GetOrganizationId();
        var userId = GetUserId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        try
        {
            await _inventoryService.RecordBatchMovementAsync(orgId, batchId, request.MovementType,
                request.Quantity, request.ReferenceType, request.ReferenceId,
                request.FromWarehouseId, request.ToWarehouseId, request.Notes, userId);
            return Ok(new { message = "Movement recorded successfully" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet("batches/{batchId}/movements")]
    [RequirePermission("view_movement")]
    public async Task<ActionResult<List<BatchMovementDto>>> GetBatchMovements(Guid batchId, [FromQuery] int limit = 50)
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        try
        {
            var movements = await _inventoryService.GetBatchMovementsAsync(batchId, orgId, limit);
            return Ok(movements);
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    // ============================================================================
    // Stock Transfers
    // ============================================================================

    [HttpPost("transfers")]
    [RequirePermission("create_transfer")]
    public async Task<ActionResult<object>> CreateTransfer([FromBody] CreateStockTransferRequest request)
    {
        var orgId = GetOrganizationId();
        var userId = GetUserId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        try
        {
            var transfer = await _inventoryService.CreateTransferAsync(orgId, request, userId);
            return CreatedAtAction(nameof(GetTransfer), new { id = transfer.Id }, transfer);
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet("transfers/{id}")]
    [RequirePermission("view_transfer")]
    public async Task<ActionResult<object>> GetTransfer(Guid id)
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        var transfer = await _inventoryService.GetTransferAsync(id, orgId);
        if (transfer == null)
            return NotFound();

        return Ok(transfer);
    }

    [HttpPost("transfers/{id}/receive")]
    [RequirePermission("receive_transfer")]
    public async Task<IActionResult> ReceiveTransfer(Guid id)
    {
        var orgId = GetOrganizationId();
        var userId = GetUserId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        try
        {
            await _inventoryService.ReceiveTransferAsync(id, orgId, userId);
            return Ok(new { message = "Transfer received successfully" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    // ============================================================================
    // Inventory Reports
    // ============================================================================

    [HttpGet("valuation")]
    [RequirePermission("view_reports")]
    public async Task<ActionResult<InventoryValuationSummaryDto>> GetValuation()
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        var valuation = await _inventoryService.GetInventoryValuationAsync(orgId);
        return Ok(valuation);
    }

    [HttpGet("expiring")]
    [RequirePermission("view_reports")]
    public async Task<ActionResult<List<ExpiringProductsDto>>> GetExpiringProducts([FromQuery] int days = 30)
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        var expiring = await _inventoryService.GetExpiringProductsAsync(orgId, days);
        return Ok(expiring);
    }

    [HttpGet("low-stock")]
    [RequirePermission("view_reports")]
    public async Task<ActionResult<List<LowStockProductsDto>>> GetLowStock()
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        var lowStock = await _inventoryService.GetLowStockProductsAsync(orgId);
        return Ok(lowStock);
    }

    [HttpGet("slow-moving")]
    [RequirePermission("view_reports")]
    public async Task<ActionResult<List<SlowMovingProductsDto>>> GetSlowMoving([FromQuery] int days = 90)
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        var slowMoving = await _inventoryService.GetSlowMovingProductsAsync(orgId, days);
        return Ok(slowMoving);
    }

    // ============================================================================
    // Alerts
    // ============================================================================

    [HttpGet("alerts")]
    [RequirePermission("view_alerts")]
    public async Task<ActionResult<List<InventoryAlertDto>>> GetAlerts([FromQuery] QueryAlertsRequest? request = null)
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        request ??= new QueryAlertsRequest();
        var alerts = await _alertService.QueryAlertsAsync(orgId, request);
        return Ok(alerts);
    }

    [HttpPost("alerts/{alertId}/resolve")]
    [RequirePermission("manage_alerts")]
    public async Task<IActionResult> ResolveAlert(Guid alertId)
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        try
        {
            await _alertService.ResolveAlertAsync(alertId, orgId);
            return Ok(new { message = "Alert resolved" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpPost("alert-rules")]
    [RequirePermission("manage_alerts")]
    public async Task<IActionResult> CreateAlertRule([FromBody] CreateAlertRuleRequest request)
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        try
        {
            await _alertService.CreateAlertRuleAsync(orgId, request);
            return Ok(new { message = "Alert rule created" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet("alert-rules")]
    [RequirePermission("manage_alerts")]
    public async Task<ActionResult<List<InventoryAlertRule>>> GetAlertRules()
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        var rules = await _alertService.GetAlertRulesAsync(orgId);
        return Ok(rules);
    }

    [HttpDelete("alert-rules/{ruleId}")]
    [RequirePermission("manage_alerts")]
    public async Task<IActionResult> DisableAlertRule(Guid ruleId)
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        try
        {
            await _alertService.DisableAlertRuleAsync(ruleId, orgId);
            return NoContent();
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    // ============================================================================
    // Dashboard
    // ============================================================================

    [HttpGet("dashboard")]
    [RequirePermission("view_dashboard")]
    public async Task<ActionResult<InventoryDashboardDto>> GetDashboard()
    {
        var orgId = GetOrganizationId();
        if (orgId == Guid.Empty)
            return Unauthorized();

        var dashboard = await _alertService.GetInventoryDashboardAsync(orgId);
        return Ok(dashboard);
    }
}
