# Testing with LocalStack

This directory contains tests for the Amazon SQS implementation using LocalStack for local AWS service emulation.

## Setup LocalStack

### Option 1: Docker (Recommended)

```bash
# Start LocalStack with SQS service
docker run --rm -it -p 4566:4566 -p 4510-4559:4510-4559 localstack/localstack
```

### Option 2: Docker Compose

Create a `docker-compose.yml` file:

```yaml
version: '3.8'
services:
  localstack:
    container_name: localstack_sqs_test
    image: localstack/localstack
    ports:
      - "4566:4566"
      - "4510-4559:4510-4559"
    environment:
      - SERVICES=sqs
      - DEBUG=1
      - DATA_DIR=/tmp/localstack/data
    volumes:
      - "./tmp/localstack:/tmp/localstack"
      - "/var/run/docker.sock:/var/run/docker.sock"
```

Then run:
```bash
docker-compose up
```

### Option 3: pip install

```bash
pip install localstack
localstack start
```

## Running Tests

### Test with LocalStack

1. **Start LocalStack** (using any method above)

2. **Verify LocalStack is running**:
   ```bash
   curl http://localhost:4566/health
   ```

3. **Run the LocalStack tests**:
   ```bash
   dart test test/local_sqs_test.dart
   ```

### Test Files

- `local_sqs_test.dart` - Tests against LocalStack SQS (requires LocalStack running)
- `sqs_implementation_tester.dart` - Tests with in-memory mock (no external dependencies)
- `kiss_amazon_sqs_queue_test.dart` - Basic unit tests
- `sqs_implementation_test.dart` - Simple interface tests

## Expected Results

When running against LocalStack, you should expect similar results to the mock tests:
- Most basic queue operations should pass
- Performance tests will be slower than in-memory but still fast
- Some advanced features (like automatic message expiration) may behave differently

## Troubleshooting

### LocalStack not responding
- Check if port 4566 is available: `lsof -i :4566`
- Verify LocalStack is running: `curl http://localhost:4566/health`
- Check Docker logs: `docker logs localstack_sqs_test`

### Connection refused errors
- Ensure LocalStack is fully started (can take 30-60 seconds)
- Try restarting LocalStack
- Check firewall settings

### SQS permissions errors
- LocalStack uses fake credentials, so any valid-looking credentials work
- The test uses `accessKey: 'test', secretKey: 'test'` which should work fine 
