using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Dapr.Workflow;
using WorkflowService.Models;

namespace WorkflowService.Activities;

/// <summary>
/// Calls Claude via the Dapr Conversation API to assess fraud risk before payment.
/// Returns a risk score (0-100) — the workflow decides the rejection threshold.
/// Fetches order history to give the LLM context for velocity/pattern detection.
/// The Dapr sidecar handles the API key — this activity never sees it.
/// </summary>
public class CheckFraudActivity : WorkflowActivity<(OrderRequest Order, InventoryReservation Reservation), FraudCheckResult>
{
    private readonly ILogger<CheckFraudActivity> _logger;
    private readonly IHttpClientFactory _httpClientFactory;

    public CheckFraudActivity(ILogger<CheckFraudActivity> logger, IHttpClientFactory httpClientFactory)
    {
        _logger = logger;
        _httpClientFactory = httpClientFactory;
    }

    public override async Task<FraudCheckResult> RunAsync(
        WorkflowActivityContext context,
        (OrderRequest Order, InventoryReservation Reservation) input)
    {
        var (order, reservation) = input;
        var totalAmount = (reservation.UnitPrice ?? 0) * order.Quantity;

        _logger.LogInformation("Checking fraud for order {OrderId}: {Product} x{Qty} = ${Total}",
            order.OrderId, reservation.ProductName ?? order.ProductId, order.Quantity, totalAmount);

        // Fetch order history for context
        var orderHistory = await FetchOrderHistory();

        var prompt = BuildPrompt(order, reservation, totalAmount, orderHistory);

        try
        {
            var client = _httpClientFactory.CreateClient();
            var daprPort = Environment.GetEnvironmentVariable("DAPR_HTTP_PORT") ?? "3500";

            var response = await client.PostAsJsonAsync(
                $"http://localhost:{daprPort}/v1.0-alpha1/conversation/anthropic-llm/converse",
                new { inputs = new[] { new { content = prompt } } });

            if (!response.IsSuccessStatusCode)
            {
                var errorBody = await response.Content.ReadAsStringAsync();
                _logger.LogWarning("Conversation API returned {Status}: {Body}. Approving by default.",
                    response.StatusCode, errorBody);
                return new FraudCheckResult(order.OrderId, Score: 0, RiskLevel: "unknown",
                    Reasoning: "Fraud check unavailable — approved by default");
            }

            var responseBody = await response.Content.ReadAsStringAsync();
            _logger.LogInformation("Conversation API response: {Response}", responseBody);

            // Parse the Conversation API response envelope
            using var doc = JsonDocument.Parse(responseBody);
            var outputText = doc.RootElement
                .GetProperty("outputs")
                .EnumerateArray()
                .First()
                .GetProperty("result")
                .GetString() ?? "";

            // Strip markdown code fences if present
            var jsonText = outputText.Trim();
            if (jsonText.StartsWith("```"))
            {
                var lines = jsonText.Split('\n');
                jsonText = string.Join('\n', lines.Skip(1).TakeWhile(l => !l.TrimStart().StartsWith("```")));
            }

            var fraudJson = JsonDocument.Parse(jsonText);
            var score = fraudJson.RootElement.GetProperty("score").GetInt32();
            score = Math.Clamp(score, 0, 100);
            var reasoning = fraudJson.RootElement.GetProperty("reasoning").GetString() ?? "";

            var riskLevel = score switch
            {
                < 40 => "low",
                < 70 => "medium",
                < 80 => "high",
                _ => "critical"
            };

            _logger.LogInformation("Fraud check for order {OrderId}: score={Score}, risk={Risk}, reason={Reason}",
                order.OrderId, score, riskLevel, reasoning);

            return new FraudCheckResult(order.OrderId, score, riskLevel, reasoning);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Fraud check failed for order {OrderId}. Approving by default.", order.OrderId);
            return new FraudCheckResult(order.OrderId, Score: 0, RiskLevel: "unknown",
                Reasoning: "Fraud check error — approved by default");
        }
    }

    private string BuildPrompt(OrderRequest order, InventoryReservation reservation,
        decimal totalAmount, List<JsonElement> orderHistory)
    {
        var sb = new StringBuilder();

        sb.AppendLine("You are a fraud detection system for an e-commerce store. Analyze this order and");
        sb.AppendLine("return a fraud risk score from 0 (no risk) to 100 (certain fraud).");
        sb.AppendLine();
        sb.AppendLine("## New Order Under Review");
        sb.AppendLine($"- Customer: {order.CustomerName}");
        sb.AppendLine($"- Email: {order.CustomerEmail}");
        sb.AppendLine($"- Product: {reservation.ProductName ?? order.ProductId}");
        if (!string.IsNullOrEmpty(reservation.ProductCategory))
            sb.AppendLine($"- Category: {reservation.ProductCategory}");
        sb.AppendLine($"- Quantity: {order.Quantity}");
        sb.AppendLine($"- Unit Price: ${reservation.UnitPrice ?? 0:F2}");
        sb.AppendLine($"- Total: ${totalAmount:F2}");
        if (!string.IsNullOrEmpty(order.ShippingAddress))
            sb.AppendLine($"- Shipping Address: {order.ShippingAddress}");

        if (orderHistory.Count > 0)
        {
            sb.AppendLine();
            sb.AppendLine($"## Order History ({orderHistory.Count} previous orders)");

            foreach (var hist in orderHistory)
            {
                var hCustomer = hist.TryGetProperty("customerName", out var cn) ? cn.GetString() : "unknown";
                var hEmail = hist.TryGetProperty("customerEmail", out var ce) ? ce.GetString() : "unknown";
                var hProduct = hist.TryGetProperty("productName", out var pn) ? pn.GetString() : "unknown";
                var hCategory = hist.TryGetProperty("productCategory", out var pc) ? pc.GetString() : null;
                var hQty = hist.TryGetProperty("quantity", out var q) ? q.ToString() : "?";
                var hTotal = hist.TryGetProperty("total", out var t) ? t.ToString() : "?";
                var hStatus = hist.TryGetProperty("status", out var s) ? s.GetString() : "unknown";
                var hTimestamp = hist.TryGetProperty("orderTimestamp", out var ts) ? ts.GetString() : null;
                var hAddress = hist.TryGetProperty("shippingAddress", out var sa) ? sa.GetString() : null;

                sb.Append($"- {hCustomer} ({hEmail}): {hProduct}");
                if (!string.IsNullOrEmpty(hCategory))
                    sb.Append($" [{hCategory}]");
                sb.Append($" x{hQty}, ${hTotal}, status={hStatus}");
                if (!string.IsNullOrEmpty(hTimestamp))
                    sb.Append($", time={hTimestamp}");
                if (!string.IsNullOrEmpty(hAddress))
                    sb.Append($", addr={hAddress}");
                sb.AppendLine();
            }
        }

        sb.AppendLine();
        sb.AppendLine("## Analysis Instructions");
        sb.AppendLine("Consider:");
        sb.AppendLine("- Does the email look legitimate or disposable/temporary?");
        sb.AppendLine("- Is the quantity unusually large?");
        sb.AppendLine("- Product category risk: gift cards and electronics are high-fraud; office supplies are low-fraud");
        sb.AppendLine("- Has this customer/email ordered before? How frequently?");
        sb.AppendLine("- Does the shipping address look like a real residential/business address?");
        sb.AppendLine("- Are there multiple orders in a short time from the same customer?");
        sb.AppendLine("- Does anything about this combination of factors seem suspicious?");
        sb.AppendLine();
        sb.AppendLine("Respond with ONLY a JSON object (no markdown, no explanation):");
        sb.AppendLine("{\"score\": 42, \"reasoning\": \"brief explanation of risk factors\"}");
        sb.AppendLine();
        sb.AppendLine("score must be an integer 0-100.");

        return sb.ToString();
    }

    private async Task<List<JsonElement>> FetchOrderHistory()
    {
        try
        {
            var client = _httpClientFactory.CreateClient();
            var daprPort = Environment.GetEnvironmentVariable("DAPR_HTTP_PORT") ?? "3500";

            var response = await client.GetAsync(
                $"http://localhost:{daprPort}/v1.0/invoke/order-service/method/orders");

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("Failed to fetch order history: {Status}", response.StatusCode);
                return new List<JsonElement>();
            }

            var body = await response.Content.ReadAsStringAsync();
            var orders = JsonDocument.Parse(body);

            if (orders.RootElement.ValueKind != JsonValueKind.Array)
                return new List<JsonElement>();

            return orders.RootElement.EnumerateArray().ToList();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to fetch order history for fraud context");
            return new List<JsonElement>();
        }
    }
}
