namespace OrderProcessing.Infrastructure;

public class ExchangeRateService
{
    public decimal GetRate(string fromCurrency, string toCurrency)
    {
        if (string.Equals(fromCurrency, toCurrency, StringComparison.OrdinalIgnoreCase))
            return 1m;

        return (fromCurrency.ToUpperInvariant(), toCurrency.ToUpperInvariant()) switch
        {
            ("USD", "ZAR") => 18.50m,
            ("EUR", "ZAR") => 20.10m,
            ("GBP", "ZAR") => 23.75m,
            _ => throw new InvalidOperationException($"No exchange rate exists for {fromCurrency} to {toCurrency}.")
        };
    }
}
