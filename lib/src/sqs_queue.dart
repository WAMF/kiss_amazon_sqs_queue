import 'dart:async';
import 'dart:convert';
import 'package:aws_sqs_api/sqs-2012-11-05.dart';
import 'package:kiss_queue/kiss_queue.dart';

/// Amazon SQS implementation of the Queue interface
class SqsQueue<T, S> implements Queue<T, S> {
  final SQS _sqs;
  final String _queueUrl;
  final QueueConfiguration _configuration;
  final Queue<T, S>? _deadLetterQueue;
  final String Function()? _idGenerator;
  final MessageSerializer<T, S>? _serializer;
  final Map<String, QueueMessage<T>> _inFlightMessages = {};
  final Map<String, String> _receiptHandles = {};
  final Map<String, int> _messageReceiveCounts = {};

  SqsQueue(
    this._sqs,
    this._queueUrl,
    this._configuration, {
    Queue<T, S>? deadLetterQueue,
    String Function()? idGenerator,
    MessageSerializer<T, S>? serializer,
  }) : _deadLetterQueue = deadLetterQueue,
       _idGenerator = idGenerator,
       _serializer = serializer;

  @override
  QueueConfiguration get configuration => _configuration;

  @override
  Queue<T, S>? get deadLetterQueue => _deadLetterQueue;

  @override
  String Function()? get idGenerator => _idGenerator;

  @override
  MessageSerializer<T, S>? get serializer => _serializer;

  @override
  Future<void> enqueue(QueueMessage<T> message) async {
    try {
      // Serialize the payload to a Map format
      S serializedPayload;
      if (_serializer != null) {
        serializedPayload = _serializer.serialize(message.payload);
      } else {
        // Wrap simple JSON-serializable values in a map
        try {
          // Test if payload can be JSON encoded
          jsonEncode(message.payload);
          serializedPayload = message.payload as S;
        } catch (e) {
          throw ArgumentError(
            'Cannot serialize payload of type ${message.payload.runtimeType}. Please provide a MessageSerializer.',
          );
        }
      }
      final messageBody = jsonEncode(serializedPayload);
      await _sqs.sendMessage(
        queueUrl: _queueUrl,
        messageBody: messageBody,
        messageAttributes: {
          'CreatedAt': MessageAttributeValue(
            stringValue: message.createdAt.toIso8601String(),
            dataType: 'String',
          ),
        },
      );
    } catch (e) {
      rethrow; // Let the actual error bubble up for better debugging
    }
  }

  @override
  Future<void> enqueuePayload(T payload) async {
    await enqueue(QueueMessage.create(payload));
  }

  @override
  Future<QueueMessage<T>?> dequeue() async {
    try {
      // Convert milliseconds to seconds, minimum 1 second for SQS (it doesn't support sub-second timeouts)
      final visibilityTimeoutSeconds =
          (_configuration.visibilityTimeout.inMilliseconds / 1000).ceil().clamp(
            1,
            43200,
          );

      final response = await _sqs.receiveMessage(
        queueUrl: _queueUrl,
        maxNumberOfMessages: 1,
        waitTimeSeconds: 0,
        visibilityTimeout: visibilityTimeoutSeconds,
        messageAttributeNames: ['All'],
        attributeNames: [QueueAttributeName.all],
      );

      if (response.messages == null || response.messages!.isEmpty) {
        return null;
      }

      final sqsMessage = response.messages!.first;
      final messageData = jsonDecode(sqsMessage.body!);

      T payload;
      if (_serializer != null) {
        // Use the serializer to deserialize the payload
        final payloadData = messageData as S?;
        if (payloadData == null) {
          throw ArgumentError('No payload data found in message');
        }

        payload = _serializer.deserialize(payloadData);
      } else {
        // Extract the value from the wrapped format
        final payloadData = messageData as S?;
        if (payloadData == null) {
          throw ArgumentError('No payload data found in message');
        }
        payload = payloadData as T;
      }
      final id = sqsMessage.messageId!;

      final message = QueueMessage<T>(
        id: id,
        payload: payload,
        createdAt:
            sqsMessage.attributes?[MessageSystemAttributeName.sentTimestamp] !=
                null
            ? DateTime.fromMillisecondsSinceEpoch(
                int.parse(
                  sqsMessage.attributes![MessageSystemAttributeName
                      .sentTimestamp]!,
                ),
              )
            : DateTime.now(),
        processedAt:
            sqsMessage.attributes?[MessageSystemAttributeName
                    .approximateFirstReceiveTimestamp] !=
                null
            ? DateTime.fromMillisecondsSinceEpoch(
                int.parse(
                  sqsMessage.attributes![MessageSystemAttributeName
                      .approximateFirstReceiveTimestamp]!,
                ),
              )
            : null,
        acknowledgedAt: null, // Set when acknowledge() is called
      );

      // Store the receipt handle for acknowledgment/rejection
      _receiptHandles[id] = sqsMessage.receiptHandle!;
      _inFlightMessages[id] = message;

      // Get receive count from SQS system attributes
      final receiveCountStr = sqsMessage
          .attributes?[MessageSystemAttributeName.approximateReceiveCount];
      final receiveCount = receiveCountStr != null
          ? int.tryParse(receiveCountStr) ?? 1
          : 1;
      _messageReceiveCounts[id] = receiveCount;

      return message;
    } catch (e) {
      rethrow; // Let the actual error bubble up for debugging
    }
  }

  @override
  Future<void> acknowledge(String messageId) async {
    try {
      final receiptHandle = _receiptHandles[messageId];
      if (receiptHandle == null) {
        throw MessageNotFoundError(messageId);
      }

      await _sqs.deleteMessage(
        queueUrl: _queueUrl,
        receiptHandle: receiptHandle,
      );

      // Only clean up state after successful SQS operation
      _receiptHandles.remove(messageId);
      _inFlightMessages.remove(messageId);
      _messageReceiveCounts.remove(messageId);
    } catch (e) {
      if (e is MessageNotFoundError) rethrow;
      rethrow; // Let the actual SQS error bubble up for better debugging
    }
  }

  @override
  Future<QueueMessage<T>?> reject(
    String messageId, {
    bool requeue = true,
  }) async {
    try {
      final message = _inFlightMessages[messageId];
      final receiptHandle = _receiptHandles[messageId];

      if (message == null || receiptHandle == null) {
        throw MessageNotFoundError(messageId);
      }

      final receiveCount = _messageReceiveCounts[messageId] ?? 1;

      // Increment receive count for our tracking since SQS doesn't track rejections properly
      final newReceiveCount = receiveCount + 1;
      _messageReceiveCounts[messageId] = newReceiveCount;

      if (requeue && newReceiveCount < _configuration.maxReceiveCount) {
        // Change visibility timeout to make message immediately available
        await _sqs.changeMessageVisibility(
          queueUrl: _queueUrl,
          receiptHandle: receiptHandle,
          visibilityTimeout: 0,
        );

        // Clean up current state - message will get new receipt handle when dequeued again
        _receiptHandles.remove(messageId);
        _inFlightMessages.remove(messageId);
        // Keep the message receive count for tracking across requeues

        return message;
      } else {
        // Max retries reached or no requeue requested
        // Delete from main queue
        await _sqs.deleteMessage(
          queueUrl: _queueUrl,
          receiptHandle: receiptHandle,
        );

        // Send to dead letter queue if available and max retries reached
        if (_deadLetterQueue != null &&
            newReceiveCount >= _configuration.maxReceiveCount) {
          await _deadLetterQueue.enqueue(message);
        }

        // Clean up state after successful SQS operations
        _receiptHandles.remove(messageId);
        _inFlightMessages.remove(messageId);
        _messageReceiveCounts.remove(messageId);
      }

      return message;
    } catch (e) {
      if (e is MessageNotFoundError) rethrow;
      rethrow; // Let the actual SQS error bubble up for better debugging
    }
  }

  @override
  void dispose() {
    _inFlightMessages.clear();
    _receiptHandles.clear();
    _messageReceiveCounts.clear();
  }
}

/// Amazon SQS implementation of QueueFactory
class SqsQueueFactory<T, S> implements QueueFactory<T, S> {
  final SQS _sqs;
  final MessageSerializer<T, S>? _serializer;
  final String Function()? _idGenerator;
  final Map<String, Queue<T, S>> _queueCache = {};
  final QueueConfiguration? _configuration;

  SqsQueueFactory({
    required SQS sqs,
    MessageSerializer<T, S>? serializer,
    String Function()? idGenerator,
    QueueConfiguration? configuration,
  }) : _sqs = sqs,
       _serializer = serializer,
       _idGenerator = idGenerator,
       _configuration = configuration;

  @override
  Future<Queue<T, S>> createQueue(
    String queueName, {
    QueueConfiguration? configuration,
    Queue<T, S>? deadLetterQueue,
  }) async {
    try {
      // Check cache first to early out
      if (_queueCache.containsKey(queueName)) {
        throw QueueAlreadyExistsError(queueName);
      }

      // Check if queue already exists on AWS
      try {
        await _sqs.getQueueUrl(queueName: queueName);
        // If we get here, the queue exists on AWS
        throw QueueAlreadyExistsError(queueName);
      } catch (e) {
        // Queue doesn't exist on AWS, continue with creation
        // (getQueueUrl throws when queue doesn't exist)
      }

      // Prepare the configuration attributes
      final config =
          configuration ?? _configuration ?? QueueConfiguration.defaultConfig;
      final attributes = <QueueAttributeName, String>{};

      // Set visibility timeout (minimum 1 second for SQS)
      final visibilityTimeoutSeconds =
          (config.visibilityTimeout.inMilliseconds / 1000).ceil().clamp(
            1,
            43200,
          );
      attributes[QueueAttributeName.visibilityTimeout] =
          visibilityTimeoutSeconds.toString();

      // Set message retention period if specified (minimum 60 seconds, maximum 14 days for SQS)
      if (config.messageRetentionPeriod != null) {
        final messageRetentionSeconds = config.messageRetentionPeriod!.inSeconds
            .clamp(
              60, // 1 minute minimum
              1209600, // 14 days maximum
            );
        attributes[QueueAttributeName.messageRetentionPeriod] =
            messageRetentionSeconds.toString();
      }

      // Create the queue
      final createResponse = await _sqs.createQueue(
        queueName: queueName,
        attributes: attributes,
      );
      String queueUrl = createResponse.queueUrl!;

      // Create the queue object
      final queue = SqsQueue<T, S>(
        _sqs,
        queueUrl,
        config,
        deadLetterQueue: deadLetterQueue,
        idGenerator: _idGenerator,
        serializer: _serializer,
      );

      // Cache the queue instance
      _queueCache[queueName] = queue;
      return queue;
    } catch (e) {
      if (e is QueueAlreadyExistsError) rethrow;
      rethrow; // Let other errors bubble up for better debugging
    }
  }

  @override
  Future<void> deleteQueue(String queueName) async {
    try {
      final response = await _sqs.getQueueUrl(queueName: queueName);
      final queueUrl = response.queueUrl!;

      await _sqs.deleteQueue(queueUrl: queueUrl);

      // Remove from cache
      _queueCache.remove(queueName);
    } catch (e) {
      // Map AWS exceptions to kiss_queue exceptions
      throw QueueDoesNotExistError(queueName);
    }
  }

  @override
  Future<Queue<T, S>> getQueue(String queueName) async {
    try {
      // Check cache first
      if (_queueCache.containsKey(queueName)) {
        return _queueCache[queueName]!;
      }

      // Try to get the queue URL from SQS
      final response = await _sqs.getQueueUrl(queueName: queueName);
      final queueUrl = response.queueUrl!;

      // Get the actual queue configuration from SQS
      final attributesResponse = await _sqs.getQueueAttributes(
        queueUrl: queueUrl,
        attributeNames: [
          QueueAttributeName.visibilityTimeout,
          QueueAttributeName.messageRetentionPeriod,
        ],
      );

      // Parse the attributes into a QueueConfiguration
      final attributes = attributesResponse.attributes ?? {};

      final visibilityTimeoutSeconds =
          int.tryParse(
            attributes[QueueAttributeName.visibilityTimeout] ?? '30',
          ) ??
          30;

      final messageRetentionSeconds = int.tryParse(
        attributes[QueueAttributeName.messageRetentionPeriod] ?? '0',
      );

      final config = QueueConfiguration(
        maxReceiveCount: QueueConfiguration
            .defaultConfig
            .maxReceiveCount, // We handle this in our logic
        visibilityTimeout: Duration(seconds: visibilityTimeoutSeconds),
        messageRetentionPeriod:
            messageRetentionSeconds != null && messageRetentionSeconds > 0
            ? Duration(seconds: messageRetentionSeconds)
            : null,
      );

      final queue = SqsQueue<T, S>(
        _sqs,
        queueUrl,
        config,
        serializer: _serializer,
        idGenerator: _idGenerator,
      );

      // Cache the queue instance
      _queueCache[queueName] = queue;
      return queue;
    } catch (e) {
      // Map AWS exceptions to kiss_queue exceptions
      throw QueueDoesNotExistError(queueName);
    }
  }

  @override
  Future<void> dispose() async {
    // Clear queue cache but don't close the SQS client as it might be shared
    // across multiple factory instances in test scenarios
    _queueCache.clear();
    // Note: Not calling _sqs.close() to avoid "Client is already closed" errors
    // in test scenarios where multiple factories might share the same SQS client
  }
}
