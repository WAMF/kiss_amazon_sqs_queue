<!-- 
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages). 

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages). 
-->

# Amazon SQS Implementation for kiss_queue

This package provides an Amazon SQS backend implementation for the [kiss_queue](https://pub.dev/packages/kiss_queue) interface, allowing you to use Amazon SQS queues with the same simple API as other queue implementations.

## Features

- ✅ **Full kiss_queue Interface**: Implements all methods from the Queue interface
- ✅ **SQS Integration**: Uses the `aws_sqs_api` package for real SQS communication
- ✅ **Dead Letter Queue Support**: Automatic poison message handling
- ✅ **Message Serialization**: Built-in support for custom serializers
- ✅ **Visibility Timeout**: Configurable message processing windows
- ✅ **Test Coverage**: From the official kiss_queue test suite

## Installation

Add this package to your `pubspec.yaml`:

```yaml
dependencies:
  kiss_amazon_sqs_queue: ^0.0.1
```

## Quick Start

```dart
import 'package:aws_sqs_api/sqs-2012-11-05.dart';
import 'package:kiss_amazon_sqs_queue/kiss_amazon_sqs_queue.dart';
import 'package:kiss_queue/kiss_queue.dart';

void main() async {
  // Configure AWS SQS client
  final sqs = SQS(
    region: 'us-east-1',
    credentials: AwsClientCredentials(
      accessKey: 'YOUR_ACCESS_KEY',
      secretKey: 'YOUR_SECRET_KEY',
    ),
  );

  // Create the factory
  final factory = SqsQueueFactory(sqs);

  // Create a queue
  final queue = await factory.createQueue<String>('my-queue');

  // Use the queue
  await queue.enqueue(QueueMessage.create('Hello, SQS!'));
  final message = await queue.dequeue();
  
  if (message != null) {
    print('Received: ${message.payload}');
    await queue.acknowledge(message.id);
  }
}
```

## Configuration

```dart
// Create a queue with custom configuration
final config = QueueConfiguration(
  maxReceiveCount: 3,
  visibilityTimeout: Duration(seconds: 30),
  messageRetentionPeriod: Duration(days: 14),
);

final queue = await factory.createQueue<String>(
  'configured-queue',
  configuration: config,
);
```

## Dead Letter Queue

```dart
// Create a dead letter queue
final dlq = await factory.createQueue<String>('my-dlq');

// Create main queue with DLQ
final mainQueue = await factory.createQueue<String>(
  'main-queue',
  configuration: QueueConfiguration(maxReceiveCount: 2),
  deadLetterQueue: dlq,
);
```

## Custom Serialization

```dart
// Define a serializer for custom objects
class OrderSerializer implements MessageSerializer<Order, Map<String, dynamic>> {
  @override
  Map<String, dynamic> serialize(Order order) => order.toJson();

  @override
  Order deserialize(Map<String, dynamic> data) => Order.fromJson(data);
}

// Use with queue
final orderQueue = await factory.createQueue<Order>(
  'orders',
  serializer: OrderSerializer(),
);
```

## Testing

This implementation has been tested against the official kiss_queue test suite using LocalStack:

### LocalStack Testing (Real SQS API)
```bash
# Run tests with automatic LocalStack management
./runTests.sh

# Or run tests manually
./runTests.sh manual
dart test test/local_sqs_test.dart
./runTests.sh stop
```

### All Tests
```bash
# Run all tests (automatically manages LocalStack)
./runTests.sh
```

**Results**: 21/22 tests passing (95% compatibility)

### Passing Tests
- ✅ Basic enqueue/dequeue operations
- ✅ Message acknowledgment 
- ✅ Message rejection and requeuing
- ✅ Dead letter queue integration
- ✅ Custom ID generation
- ✅ Concurrent processing

### Known Limitations
- ⚠️ Message retention timeout not working as expected on Localstack test environment 

## AWS Setup

Make sure your AWS credentials have the following SQS permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:CreateQueue",
        "sqs:DeleteQueue", 
        "sqs:GetQueueUrl",
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility"
      ],
      "Resource": "*"
    }
  ]
}
```

## Development

### Prerequisites

For local testing with real SQS API:
- Docker and Docker Compose
- LocalStack (included via Docker)

### Quick Start

```bash
# Install dependencies
dart pub get

# Run all tests (includes LocalStack setup)
./runTests.sh

# Or run specific test types
dart test                # Unit tests only
./runTests.sh manual     # Start LocalStack for manual testing
```

### Manual Testing

```bash
# Install dependencies
dart pub get

# Run basic tests
dart test

# Start LocalStack and run real SQS tests automatically
./runTests.sh

# Or manage LocalStack manually
./runTests.sh manual
dart test test/local_sqs_test.dart
./runTests.sh stop

# Run with coverage
dart test --coverage=coverage

# Run example
dart run example/sqs_example.dart
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
