using OrderProcessing.Domain;

namespace OrderProcessing.Infrastructure;

public sealed class OrderSearchCriteria
{
    public string? CustomerId { get; init; }
    public string? Status { get; init; }
    public decimal? MinimumTotal { get; init; }
    public decimal? MaximumTotal { get; init; }
    public DateTime? CreatedFrom { get; init; }
    public DateTime? CreatedTo { get; init; }
}

public interface IOrderRepository
{
    void Add(Order order);
    IReadOnlyList<Order> Search(OrderSearchCriteria criteria);
}

public sealed class InMemoryOrderRepository : IOrderRepository
{
    private readonly List<Order> _orders = new();
    private readonly object _sync = new();

    public void Add(Order order)
    {
        ArgumentNullException.ThrowIfNull(order);
        lock (_sync)
        {
            _orders.Add(order);
        }
    }

    public IReadOnlyList<Order> Search(OrderSearchCriteria criteria)
    {
        ArgumentNullException.ThrowIfNull(criteria);
        if (criteria.MinimumTotal.HasValue && criteria.MaximumTotal.HasValue &&
            criteria.MinimumTotal.Value > criteria.MaximumTotal.Value)
            throw new ArgumentException("Minimum total cannot exceed maximum total.", nameof(criteria));
        if (criteria.CreatedFrom.HasValue && criteria.CreatedTo.HasValue &&
            criteria.CreatedFrom.Value > criteria.CreatedTo.Value)
            throw new ArgumentException("Created-from cannot be after created-to.", nameof(criteria));

        lock (_sync)
        {
            return _orders.Where(order =>
                (criteria.CustomerId is null || string.Equals(order.CustomerId, criteria.CustomerId, StringComparison.OrdinalIgnoreCase)) &&
                (criteria.Status is null || string.Equals(order.Status, criteria.Status, StringComparison.OrdinalIgnoreCase)) &&
                (criteria.MinimumTotal is null || order.Total >= criteria.MinimumTotal) &&
                (criteria.MaximumTotal is null || order.Total <= criteria.MaximumTotal) &&
                (criteria.CreatedFrom is null || order.CreatedUtc >= criteria.CreatedFrom) &&
                (criteria.CreatedTo is null || order.CreatedUtc <= criteria.CreatedTo)).ToList();
        }
    }
}
