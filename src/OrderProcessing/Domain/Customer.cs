namespace OrderProcessing.Domain;

public class Customer
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Tier { get; set; } = "Standard";
    public bool IsTaxExempt { get; set; }
}
