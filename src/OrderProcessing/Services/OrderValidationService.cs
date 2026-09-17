using OrderProcessing.Domain;

namespace OrderProcessing.Services;

public interface IOrderValidationService
{
    void ValidateHeader(Order order);
    void ValidateLines(Order order);
}

public sealed class OrderValidationService : IOrderValidationService
{
    public void ValidateHeader(Order order)
    {
        if (string.IsNullOrWhiteSpace(order.Id))
            throw new InvalidOperationException("Order ID is required.");
        if (string.IsNullOrWhiteSpace(order.CustomerId))
            throw new InvalidOperationException("Customer ID is required.");
    }

    public void ValidateLines(Order order)
    {
        if (order.Lines == null || order.Lines.Count == 0)
            throw new InvalidOperationException("Order must contain at least one line.");

        foreach (var line in order.Lines)
        {
            if (string.IsNullOrWhiteSpace(line.Sku))
                throw new InvalidOperationException("Line SKU is required.");
            if (line.Quantity <= 0)
                throw new InvalidOperationException("Line quantity must be greater than zero.");
            if (line.UnitPrice < 0)
                throw new InvalidOperationException("Line price cannot be negative.");
        }
    }
}
