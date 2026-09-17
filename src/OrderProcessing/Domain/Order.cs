namespace OrderProcessing.Domain;

public class Order
{
    public string Id { get; set; } = string.Empty;
    public string CustomerId { get; set; } = string.Empty;
    public string Currency { get; set; } = "ZAR";
    public string ShippingCountry { get; set; } = "ZA";
    public DateTime CreatedUtc { get; set; }
    public List<OrderLine> Lines { get; set; } = new();
    public string Status { get; set; } = "Pending";
    public decimal ShippingCost { get; set; }
    public decimal Discount { get; set; }
    public decimal Tax { get; set; }
    public decimal Total { get; set; }
    public int LoyaltyPoints { get; set; }
    public List<string> AppliedPromotions { get; set; } = new();
}
