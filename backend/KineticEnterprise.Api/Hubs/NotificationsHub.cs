using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace KineticEnterprise.Api.Hubs;

/// <summary>
/// بديل SignalR لخاصية Realtime في Supabase. كل عميل يشترك في مجموعة
/// باسم organization_id الخاص به عند الاتصال، فيستقبل فقط تنبيهات منظمته
/// (تحديات إضافية غير موجودة في اشتراك Supabase المباشر على الجدول، تُحل
/// هنا يدوياً عبر Groups بدل الاعتماد على RLS وقت الاشتراك).
/// </summary>
[Authorize]
public class NotificationsHub : Hub
{
    public override async Task OnConnectedAsync()
    {
        var orgId = Context.User?.FindFirst("organization_id")?.Value;
        if (!string.IsNullOrEmpty(orgId))
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, orgId);
        }
        await base.OnConnectedAsync();
    }
}
