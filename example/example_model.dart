// Example domain model
import 'package:kiss_queue/kiss_queue.dart';

class Order {
  final String id;
  final String customerName;
  final double amount;

  Order(this.id, this.customerName, this.amount);

  @override
  String toString() =>
      'Order(id: $id, customer: $customerName, amount: \$${amount.toStringAsFixed(2)})';

  Map<String, dynamic> toJson() => {
    'id': id,
    'customerName': customerName,
    'amount': amount,
  };

  static Order fromJson(Map<String, dynamic> json) =>
      Order(json['id'], json['customerName'], json['amount'].toDouble());
}

// Custom serializer for Order objects
class OrderSerializer
    implements MessageSerializer<Order, Map<String, dynamic>> {
  @override
  Map<String, dynamic> serialize(Order order) => order.toJson();

  @override
  Order deserialize(Map<String, dynamic> data) => Order.fromJson(data);
}
