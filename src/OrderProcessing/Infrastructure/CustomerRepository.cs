using OrderProcessing.Domain;

namespace OrderProcessing.Infrastructure;

public interface ICustomerRepository
{
    Customer? Get(string customerId);
}

public sealed class CustomerRepository : ICustomerRepository
{
    private readonly Dictionary<string, Customer> _customers = new(StringComparer.OrdinalIgnoreCase)
    {
        ["C001"] = new Customer { Id = "C001", Name = "Acme Retail", Tier = "Gold" },
        ["C002"] = new Customer { Id = "C002", Name = "Small Shop", Tier = "Standard" },
        ["C003"] = new Customer { Id = "C003", Name = "Export Co", Tier = "Gold", IsTaxExempt = true }
    };

    public Customer? Get(string customerId)
    {
        ArgumentNullException.ThrowIfNull(customerId);
        _customers.TryGetValue(customerId, out var customer);
        return customer;
    }
}
