using System.Text.Json;
using OrderProcessing.Domain;

namespace OrderProcessing.Services;

public interface IOrderJsonSerializer
{
    Order? Deserialize(string json);
    string Serialize(Order order);
}

public sealed class OrderJsonSerializer : IOrderJsonSerializer
{
    private static readonly JsonSerializerOptions OutputOptions = new()
    {
        WriteIndented = true,
        MaxDepth = 64
    };

    public Order? Deserialize(string json)
    {
        ArgumentNullException.ThrowIfNull(json);
        return JsonSerializer.Deserialize<Order>(json, OutputOptions);
    }

    public string Serialize(Order order)
    {
        ArgumentNullException.ThrowIfNull(order);
        return JsonSerializer.Serialize(order, OutputOptions);
    }
}
