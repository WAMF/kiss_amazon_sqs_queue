import 'package:aws_sqs_api/sqs-2012-11-05.dart';
import 'package:kiss_amazon_sqs_queue/kiss_amazon_sqs_queue.dart';
import 'package:kiss_queue/kiss_queue.dart';

import 'example_model.dart';

void main() async {
  // Configure AWS credentials (in practice, use AWS IAM roles, environment variables, or AWS CLI)
  final sqs = SQS(
    region: 'us-east-1', // or your preferred AWS region
    credentials: AwsClientCredentials(
      accessKey: 'YOUR_ACCESS_KEY',
      secretKey: 'YOUR_SECRET_KEY',
    ),
  );

  // Create the SQS queue factory
  final sampleStringFactory = SqsQueueFactory<String, String>(sqs: sqs);

  try {
    // Create a queue with custom configuration
    final config = QueueConfiguration(
      maxReceiveCount: 3,
      visibilityTimeout: Duration(seconds: 30),
      messageRetentionPeriod: Duration(days: 14),
    );

    final queue = await sampleStringFactory.createQueue(
      'my-application-queue',
      configuration: config,
    );

    print('Queue created successfully!');

    // Enqueue some messages
    await queue.enqueue(QueueMessage.create('Hello, World!'));
    await queue.enqueue(QueueMessage.create('Processing task #1'));
    await queue.enqueue(QueueMessage.create('Processing task #2'));

    print('Enqueued 3 messages');

    // Process messages
    for (int i = 0; i < 3; i++) {
      final message = await queue.dequeue();
      if (message != null) {
        print('Received message: ${message.payload}');
        print('Message ID: ${message.id}');
        print('Created at: ${message.createdAt}');

        // Simulate processing
        await Future.delayed(Duration(milliseconds: 100));

        // Acknowledge successful processing
        await queue.acknowledge(message.id);
        print('Message acknowledged\n');
      }
    }

    // Example with dead letter queue
    final dlqQueue = await sampleStringFactory.createQueue('my-dlq');
    final mainQueue = await sampleStringFactory.createQueue(
      'main-queue-with-dlq',
      configuration: QueueConfiguration(maxReceiveCount: 2),
      deadLetterQueue: dlqQueue,
    );

    // Enqueue a message that will fail processing
    await mainQueue.enqueue(QueueMessage.create('Problematic message'));

    // Simulate failed processing
    final problematicMessage = await mainQueue.dequeue();
    if (problematicMessage != null) {
      print('Processing failed for: ${problematicMessage.payload}');
      // Reject with requeue
      await mainQueue.reject(problematicMessage.id, requeue: true);
    }

    // Try processing again (second failure)
    final retryMessage = await mainQueue.dequeue();
    if (retryMessage != null) {
      print('Retry processing failed for: ${retryMessage.payload}');
      // Reject again - this should send to DLQ since maxReceiveCount is 2
      await mainQueue.reject(retryMessage.id, requeue: true);
    }

    // Check dead letter queue
    final dlqMessage = await dlqQueue.dequeue();
    if (dlqMessage != null) {
      print('Message moved to DLQ: ${dlqMessage.payload}');
      await dlqQueue.acknowledge(dlqMessage.id);
    }

    final orderSerializer = OrderSerializer();
    final orderQueueFactory = SqsQueueFactory<Order, Map<String, dynamic>>(
      sqs: sqs,
      serializer: orderSerializer,
    );

    // Example with custom serializer for complex objects
    final orderQueue = await orderQueueFactory.createQueue(
      'order-processing-queue',
    );

    final order = Order('ORD-123', 'Customer A', 99.99);
    await orderQueue.enqueue(QueueMessage.create(order));

    final orderMessage = await orderQueue.dequeue();
    if (orderMessage != null) {
      print('Received order: ${orderMessage.payload}');
      await orderQueue.acknowledge(orderMessage.id);
    }

    print('\nExample completed successfully!');
  } catch (e) {
    print('Error: $e');
  }
}
