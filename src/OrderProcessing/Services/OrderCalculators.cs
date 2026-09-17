using OrderProcessing.Domain;

namespace OrderProcessing.Services;

public interface IPricingService
{
    decimal CalculateSubtotal(IEnumerable<OrderLine> lines);
}

public sealed class PricingService : IPricingService
{
    public decimal CalculateSubtotal(IEnumerable<OrderLine> lines)
    {
        ArgumentNullException.ThrowIfNull(lines);

        decimal subtotal = 0m;
        foreach (var line in lines)
        {
            line.LineTotal = Math.Round(
                line.Quantity * line.UnitPrice,
                2,
                MidpointRounding.ToEven);
            subtotal += line.LineTotal;
        }
        return subtotal;
    }
}

public sealed record PromotionResult(decimal Discount, IReadOnlyList<string> AppliedPromotions);

public interface IPromotionService
{
    PromotionResult Calculate(Customer customer, decimal subtotal, IEnumerable<OrderLine> lines);
}

public sealed class PromotionService : IPromotionService
{
    public PromotionResult Calculate(Customer customer, decimal subtotal, IEnumerable<OrderLine> lines)
    {
        ArgumentNullException.ThrowIfNull(customer);
        ArgumentNullException.ThrowIfNull(lines);

        decimal discount = 0m;
        var promotions = new List<string>();
        if (customer.Tier == "Gold" && subtotal >= 500m)
        {
            discount += subtotal * 0.05m;
            promotions.Add("GOLD-5");
        }
        if (lines.Any(x => x.Quantity >= 10))
        {
            discount += 20m;
            promotions.Add("BULK-20");
        }
        if (subtotal >= 2000m)
        {
            discount += 100m;
            promotions.Add("ORDER-100");
        }
        return new PromotionResult(Math.Min(discount, subtotal), promotions);
    }
}

public interface IShippingService
{
    decimal Calculate(string shippingCountry, decimal merchandiseAfterDiscount);
}

public sealed class ShippingService : IShippingService
{
    public decimal Calculate(string shippingCountry, decimal merchandiseAfterDiscount)
    {
        ArgumentNullException.ThrowIfNull(shippingCountry);
        return shippingCountry.Equals("ZA", StringComparison.OrdinalIgnoreCase)
            ? (merchandiseAfterDiscount >= 750m ? 0m : 85m)
            : 350m;
    }
}

public interface ITaxService
{
    decimal Calculate(Customer customer, decimal taxableAmount);
}

public sealed class TaxService : ITaxService
{
    public decimal Calculate(Customer customer, decimal taxableAmount)
    {
        ArgumentNullException.ThrowIfNull(customer);
        return customer.IsTaxExempt
            ? 0m
            : Math.Round(taxableAmount * 0.15m, 2, MidpointRounding.ToEven);
    }
}

public interface ILoyaltyPointsService
{
    int Calculate(Customer customer, decimal merchandiseAfterDiscount);
}

public sealed class LoyaltyPointsService : ILoyaltyPointsService
{
    public int Calculate(Customer customer, decimal merchandiseAfterDiscount)
    {
        ArgumentNullException.ThrowIfNull(customer);
        var multiplier = string.Equals(customer.Tier, "Gold", StringComparison.Ordinal) ? 2 : 1;
        var wholeTenRandUnits = decimal.Floor(merchandiseAfterDiscount / 10m);
        return checked(decimal.ToInt32(wholeTenRandUnits) * multiplier);
    }
}
