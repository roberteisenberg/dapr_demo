using System.Net.Http.Json;
using System.Text.Json;
using Dapr.Workflow;
using WorkflowService.Models;

namespace WorkflowService.Activities;

/// <summary>
/// Calls Claude via the Dapr Conversation API to assess fraud risk before payment.
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

        var prompt = $"""
            Analyze this e-commerce order for fraud risk:

            Customer: {order.CustomerName}
            Email: {order.CustomerEmail}
            Product: {reservation.ProductName ?? order.ProductId}
            Quantity: {order.Quantity}
            Unit Price: ${reservation.UnitPrice ?? 0:F2}
            Total: ${totalAmount:F2}

            Assess whether this order appears suspicious. Consider:
            - Does the email look legitimate?
            - Is the quantity unusually large?
            - Does anything seem off about this order?

            Respond with ONLY a JSON object (no markdown, no explanation):
            {{"approved": true, "riskLevel": "low", "reasoning": "brief explanation"}}

            riskLevel must be "low", "medium", or "high".
            Set approved=false only for high risk orders.
            """;

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
                return new FraudCheckResult(order.OrderId, Approved: true, RiskLevel: "unknown",
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
            var approved = fraudJson.RootElement.GetProperty("approved").GetBoolean();
            var riskLevel = fraudJson.RootElement.GetProperty("riskLevel").GetString() ?? "unknown";
            var reasoning = fraudJson.RootElement.GetProperty("reasoning").GetString() ?? "";

            _logger.LogInformation("Fraud check for order {OrderId}: approved={Approved}, risk={Risk}, reason={Reason}",
                order.OrderId, approved, riskLevel, reasoning);

            return new FraudCheckResult(order.OrderId, approved, riskLevel, reasoning);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Fraud check failed for order {OrderId}. Approving by default.", order.OrderId);
            return new FraudCheckResult(order.OrderId, Approved: true, RiskLevel: "unknown",
                Reasoning: "Fraud check error — approved by default");
        }
    }
}
