using System.Text.Json;
using OrderProcessing.Domain;
using OrderProcessing.Infrastructure;

namespace OrderProcessing.Services;

public sealed class OrderProcessor
{
    private readonly IOrderJsonSerializer _serializer;
    private readonly IOrderValidationService _validation;
    private readonly ICustomerRepository _customers;
    private readonly IPricingService _pricing;
    private readonly IPromotionService _promotions;
    private readonly IShippingService _shipping;
    private readonly ITaxService _tax;
    private readonly ILoyaltyPointsService _loyalty;
    private readonly IOrderRepository _orders;

    public OrderProcessor() : this(new OrderJsonSerializer(), new OrderValidationService(), new CustomerRepository(), new PricingService(), new PromotionService(), new ShippingService(), new TaxService(), new LoyaltyPointsService(), new InMemoryOrderRepository()) { }

    public OrderProcessor(IOrderJsonSerializer serializer, IOrderValidationService validation,
        ICustomerRepository customers, IPricingService pricing, IPromotionService promotions,
        IShippingService shipping, ITaxService tax, ILoyaltyPointsService loyalty, IOrderRepository orders)
    {
        _serializer = serializer ?? throw new ArgumentNullException(nameof(serializer));
        _validation = validation ?? throw new ArgumentNullException(nameof(validation));
        _customers = customers ?? throw new ArgumentNullException(nameof(customers));
        _pricing = pricing ?? throw new ArgumentNullException(nameof(pricing));
        _promotions = promotions ?? throw new ArgumentNullException(nameof(promotions));
        _shipping = shipping ?? throw new ArgumentNullException(nameof(shipping));
        _tax = tax ?? throw new ArgumentNullException(nameof(tax));
        _loyalty = loyalty ?? throw new ArgumentNullException(nameof(loyalty));
        _orders = orders ?? throw new ArgumentNullException(nameof(orders));
    }

    public string Process(string json)
    {
        if (string.IsNullOrWhiteSpace(json)) throw new ArgumentException("Order JSON is required.", nameof(json));
        Order? order;
        try { order = _serializer.Deserialize(json); }
        catch (JsonException ex) { throw new ArgumentException("Invalid order JSON.", nameof(json), ex); }
        if (order == null) throw new ArgumentException("Order could not be deserialized.", nameof(json));

        _validation.ValidateHeader(order);
        var customer = _customers.Get(order.CustomerId) ?? throw new InvalidOperationException("Customer was not found.");
        _validation.ValidateLines(order);
        var subtotal = _pricing.CalculateSubtotal(order.Lines);
        var promotion = _promotions.Calculate(customer, subtotal, order.Lines);
        order.AppliedPromotions.AddRange(promotion.AppliedPromotions);
        var merchandiseAfterDiscount = subtotal - promotion.Discount;
        var shipping = _shipping.Calculate(order.ShippingCountry, merchandiseAfterDiscount);
        var taxableAmount = merchandiseAfterDiscount + shipping;
        var tax = _tax.Calculate(customer, taxableAmount);

        order.Discount = Math.Round(promotion.Discount, 2, MidpointRounding.ToEven);
        order.ShippingCost = Math.Round(shipping, 2, MidpointRounding.ToEven);
        order.Tax = tax;
        order.Total = Math.Round(taxableAmount + tax, 2, MidpointRounding.ToEven);
        order.LoyaltyPoints = _loyalty.Calculate(customer, merchandiseAfterDiscount);
        order.Status = order.Total >= 5000m ? "ManualReview" : "Approved";
        var result = _serializer.Serialize(order);
        _orders.Add(order);
        return result;
    }
}
