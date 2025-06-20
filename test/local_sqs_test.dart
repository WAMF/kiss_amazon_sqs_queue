import 'package:aws_sqs_api/sqs-2012-11-05.dart';
import 'package:kiss_amazon_sqs_queue/kiss_amazon_sqs_queue.dart';
import 'package:kiss_queue/kiss_queue.dart';
import 'package:kiss_queue_tests/kiss_queue_tests.dart';

// Order serializer that can properly serialize/deserialize Order objects
class OrderSerializer
    implements MessageSerializer<Order, Map<String, dynamic>> {
  @override
  Map<String, dynamic> serialize(Order order) {
    return {
      'orderId': order.orderId,
      'customerId': order.customerId,
      'amount': order.amount,
      'items': order.items,
    };
  }

  @override
  Order deserialize(Map<String, dynamic> data) {
    return Order(
      orderId: data['orderId'],
      customerId: data['customerId'],
      amount: data['amount'],
      items: List<String>.from(data['items']),
    );
  }
}

void main() {
  runQueueTests<SqsQueue<Order>, Map<String, dynamic>?>(
    implementationName: 'SQS Queue (LocalStack)',
    testConfig: TestConfig(
      messageRetentionPeriod: Duration(seconds: 10),
      visibilityTimeout: Duration(
        seconds: 2,
      ), // SQS minimum is 1 second, using 2 for safety
      visibilityTimeoutWait: Duration(
        seconds: 5,
      ), // Wait longer than visibility timeout
      maxReceiveCount: 3,
      operationDelay: Duration(milliseconds: 500), // More time for LocalStack
      consistencyDelay: Duration(milliseconds: 500), // More time for LocalStack
      profile: TimingProfile.loose,
    ),
    factoryProvider: () {
      // Create a new SQS client and factory for each test
      final sqs = SQS(
        region: 'us-east-1',
        credentials: AwsClientCredentials(accessKey: 'test', secretKey: 'test'),
        endpointUrl: 'http://localhost:4566', // LocalStack endpoint
      );

      return SqsQueueFactory(
        sqs: sqs,
        serializer: OrderSerializer(),
        configuration: QueueConfiguration(
          messageRetentionPeriod: Duration(seconds: 30), // Match test config
          visibilityTimeout: Duration(seconds: 2), // Match test config
          maxReceiveCount: 3,
        ),
      );
    },
    cleanup: (factory) async {
      await factory.dispose();
    },
  );
}
