using System.Text.Json;
using OrderProcessing.Domain;
using OrderProcessing.Services;

namespace OrderProcessing.Tests;

public sealed class OrderProcessorTests
{
    private readonly OrderProcessor _processor = new();

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Process_MissingInput_ThrowsArgumentException(string? json)
    {
        var exception = Assert.Throws<ArgumentException>(() => _processor.Process(json!));
        Assert.Equal("json", exception.ParamName);
        Assert.StartsWith("Order JSON is required.", exception.Message);
    }

    [Fact]
    public void Process_InvalidJson_WrapsJsonException()
    {
        var exception = Assert.Throws<ArgumentException>(() => _processor.Process("{ invalid"));
        Assert.Equal("json", exception.ParamName);
        Assert.IsType<JsonException>(exception.InnerException);
    }

    [Fact]
    public void Process_JsonNull_ThrowsDeserializationException() =>
        Assert.StartsWith("Order could not be deserialized.",
            Assert.Throws<ArgumentException>(() => _processor.Process("null")).Message);

    [Theory]
    [InlineData("", "C002", "Order ID is required.")]
    [InlineData("O-1", "", "Customer ID is required.")]
    [InlineData("O-1", "UNKNOWN", "Customer was not found.")]
    public void Process_InvalidHeader_Throws(string id, string customerId, string message)
    {
        var exception = Assert.Throws<InvalidOperationException>(() =>
            _processor.Process(TestOrders.Json(TestOrders.Order(id, customerId))));
        Assert.Equal(message, exception.Message);
    }

    [Fact]
    public void Process_NoLines_Throws() => Assert.Equal("Order must contain at least one line.",
        Assert.Throws<InvalidOperationException>(() =>
            _processor.Process(TestOrders.Json(TestOrders.Order(lines: [])))).Message);

    [Theory]
    [InlineData("", 1, 10, "Line SKU is required.")]
    [InlineData("SKU", 0, 10, "Line quantity must be greater than zero.")]
    [InlineData("SKU", -1, 10, "Line quantity must be greater than zero.")]
    [InlineData("SKU", 1, -0.01, "Line price cannot be negative.")]
    public void Process_InvalidLine_Throws(string sku, int quantity, double price, string message)
    {
        var exception = Assert.Throws<InvalidOperationException>(() => _processor.Process(
            TestOrders.Json(TestOrders.Order(lines: [TestOrders.Line(sku, quantity, (decimal)price)]))));
        Assert.Equal(message, exception.Message);
    }

    [Fact]
    public void Process_BasicOrder_CalculatesObservableAmounts()
    {
        var result = Process(lines: [TestOrders.Line("SKU", 1, 500m)]);
        Assert.Equal(500m, result.Lines.Single().LineTotal);
        Assert.Equal(0m, result.Discount);
        Assert.Equal(85m, result.ShippingCost);
        Assert.Equal(87.75m, result.Tax);
        Assert.Equal(672.75m, result.Total);
        Assert.Equal("Approved", result.Status);
    }

    [Fact]
    public void Process_MultipleDecimalLines_RoundsLinesBeforeSubtotal()
    {
        var result = Process(lines: [TestOrders.Line("A", 3, 10.005m), TestOrders.Line("B", 2, 20.004m)]);
        Assert.Equal([30.02m, 40.01m], result.Lines.Select(x => x.LineTotal));
        Assert.Equal(23.25m, result.Tax);
        Assert.Equal(178.28m, result.Total);
    }

    [Theory]
    [InlineData(499.99, 0, false)]
    [InlineData(500, 25, true)]
    [InlineData(1000, 50, true)]
    public void Process_GoldDiscount_HasInclusiveThreshold(double price, double discount, bool applied)
    {
        var result = Process("C001", lines: [TestOrders.Line("SKU", 1, (decimal)price)]);
        Assert.Equal((decimal)discount, result.Discount);
        Assert.Equal(applied, result.AppliedPromotions.Contains("GOLD-5"));
    }

    [Theory]
    [InlineData(9, 0, false)]
    [InlineData(10, 20, true)]
    [InlineData(11, 20, true)]
    public void Process_BulkDiscount_HasInclusiveThreshold(int quantity, double discount, bool applied)
    {
        var result = Process(lines: [TestOrders.Line("SKU", quantity, 30m)]);
        Assert.Equal((decimal)discount, result.Discount);
        Assert.Equal(applied, result.AppliedPromotions.Contains("BULK-20"));
    }

    [Theory]
    [InlineData(1999.99, 0, false)]
    [InlineData(2000, 100, true)]
    [InlineData(2000.01, 100, true)]
    public void Process_OrderDiscount_HasInclusiveThreshold(double price, double discount, bool applied)
    {
        var result = Process(lines: [TestOrders.Line("SKU", 1, (decimal)price)]);
        Assert.Equal((decimal)discount, result.Discount);
        Assert.Equal(applied, result.AppliedPromotions.Contains("ORDER-100"));
    }

    [Fact]
    public void Process_DiscountExceedingSubtotal_IsCapped()
    {
        var result = Process(lines: [TestOrders.Line("SKU", 10, 1m)]);
        Assert.Equal(10m, result.Discount);
        Assert.Equal(97.75m, result.Total);
    }

    [Theory]
    [InlineData(749.99, 85)]
    [InlineData(750, 0)]
    [InlineData(750.01, 0)]
    public void Process_ZaShipping_HasInclusiveFreeThreshold(double price, double shipping) =>
        Assert.Equal((decimal)shipping, Process(lines: [TestOrders.Line("SKU", 1, (decimal)price)]).ShippingCost);

    [Fact]
    public void Process_InternationalOrder_ChargesInternationalShipping() =>
        Assert.Equal(350m, Process(country: "US", lines: [TestOrders.Line("SKU", 1, 1000m)]).ShippingCost);

    [Fact]
    public void Process_NormalCustomer_TaxesMerchandiseAndShipping() =>
        Assert.Equal(27.75m, Process(lines: [TestOrders.Line("SKU", 1, 100m)]).Tax);

    [Fact]
    public void Process_TaxExemptCustomer_HasNoTax()
    {
        var result = Process("C003", lines: [TestOrders.Line("SKU", 1, 100m)]);
        Assert.Equal(0m, result.Tax);
        Assert.Equal(185m, result.Total);
    }

    [Fact]
    public void Process_FractionalTax_RoundsToTwoDecimals()
    {
        var result = Process(lines: [TestOrders.Line("SKU", 1, 1.01m)]);
        Assert.Equal(12.90m, result.Tax);
        Assert.Equal(98.91m, result.Total);
    }

    [Theory]
    [InlineData(5368.41, "Approved", 4999.99)]
    [InlineData(5368.42, "ManualReview", 5000)]
    [InlineData(5368.43, "ManualReview", 5000.01)]
    public void Process_Status_HasInclusiveManualReviewThreshold(double price, string status, double total)
    {
        var result = Process("C003", lines: [TestOrders.Line("SKU", 1, (decimal)price)]);
        Assert.Equal((decimal)total, result.Total);
        Assert.Equal(status, result.Status);
    }

    private Order Process(string customerId = "C002", string country = "ZA", List<OrderLine>? lines = null) =>
        JsonSerializer.Deserialize<Order>(_processor.Process(TestOrders.Json(
            TestOrders.Order(customerId: customerId, country: country, lines: lines))))!;
}
