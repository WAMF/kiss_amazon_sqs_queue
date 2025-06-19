#!/bin/bash

# runTests.sh - Start LocalStack and run tests
# Usage: 
#   ./runTests.sh           - Run tests automatically (default)
#   ./runTests.sh manual    - Start LocalStack and wait for manual testing
#   ./runTests.sh stop      - Stop LocalStack containers
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to cleanup on exit
cleanup() {
    print_status "Cleaning up..."
    docker-compose down --remove-orphans
}

# Check command line argument
MODE="${1:-auto}"

case "$MODE" in
    "stop")
        print_status "Stopping LocalStack..."
        docker-compose down --remove-orphans
        print_status "LocalStack stopped."
        exit 0
        ;;
    "manual")
        print_status "Starting LocalStack in manual mode..."
        print_warning "LocalStack will keep running until you stop it manually."
        print_warning "Use './runTests.sh stop' to stop LocalStack when done."
        ;;
    "auto"|"")
        print_status "Starting LocalStack in automatic mode..."
        # Trap cleanup function on script exit (only in auto mode)
        trap cleanup EXIT
        ;;
    "help"|"-h"|"--help")
        echo "runTests.sh - LocalStack SQS Testing Script"
        echo
        echo "Usage: $0 [MODE]"
        echo
        echo "Modes:"
        echo "  auto     - Start LocalStack, run tests, and cleanup automatically (default)"
        echo "  manual   - Start LocalStack and keep it running for manual testing"
        echo "  stop     - Stop LocalStack containers"
        echo "  help     - Show this help message"
        echo
        echo "Examples:"
        echo "  $0               # Run tests automatically"
        echo "  $0 auto          # Same as above"
        echo "  $0 manual        # Start LocalStack for manual testing"
        echo "  $0 stop          # Stop LocalStack"
        exit 0
        ;;
    *)
        print_error "Invalid mode: $MODE"
        print_error "Usage: $0 [auto|manual|stop|help]"
        print_error "Use '$0 help' for more information."
        exit 1
        ;;
esac

print_status "Starting LocalStack..."

# Check if docker-compose exists
if ! command -v docker-compose &> /dev/null; then
    print_error "docker-compose is not installed or not in PATH"
    exit 1
fi

# Start LocalStack in the background
docker-compose up -d

print_status "Waiting for LocalStack to be ready..."

# Wait for LocalStack to be healthy
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
    # Check if container is still running
    if ! docker-compose ps localstack | grep -q "Up"; then
        print_error "LocalStack container stopped unexpectedly!"
        print_error "Container logs:"
        docker-compose logs localstack | tail -20
        exit 1
    fi
    
    # Check if LocalStack is responding on port 4566
    if curl -f -s http://localhost:4566/_localstack/health > /dev/null 2>&1; then
        print_status "LocalStack is responding!"
        # Give it a few more seconds to fully initialize SQS
        sleep 3
        break
    fi
    
    attempt=$((attempt + 1))
    if [ $((attempt % 10)) -eq 0 ]; then
        print_warning "Still waiting for LocalStack... (attempt $attempt/$max_attempts)"
        print_warning "Container status:"
        docker-compose ps localstack
    else
        print_warning "Waiting for LocalStack... (attempt $attempt/$max_attempts)"
    fi
    sleep 2
done

if [ $attempt -eq $max_attempts ]; then
    print_error "LocalStack failed to start after $max_attempts attempts"
    print_error "Final container status:"
    docker-compose ps localstack
    print_error "Recent logs:"
    docker-compose logs localstack | tail -30
    exit 1
fi

# Give LocalStack more time to fully initialize all services
print_status "Verifying SQS service is ready..."
sleep 5

# Test if SQS is actually responding to list queues request
if aws --endpoint-url=http://localhost:4566 --region=us-east-1 sqs list-queues > /dev/null 2>&1; then
    print_status "SQS service verified!"
else
    print_warning "AWS CLI not available or SQS not ready, continuing anyway..."
fi

if [ "$MODE" = "manual" ]; then
    print_status "LocalStack is ready for manual testing!"
    echo
    print_status "To run tests manually, use:"
    echo -e "  ${GREEN}dart test test/local_sqs_test.dart${NC}"
    echo
    print_status "To run individual tests, use:"
    echo -e "  ${GREEN}dart test test/local_sqs_test.dart --plain-name 'test name here'${NC}"
    echo
    print_status "LocalStack endpoints:"
    echo -e "  SQS: ${GREEN}http://localhost:4566${NC}"
    echo -e "  Health: ${GREEN}curl http://localhost:4566/_localstack/health${NC}"
    echo
    print_warning "LocalStack will keep running in the background."
    print_warning "Use './runTests.sh stop' to stop when finished."
    exit 0
else
    print_status "Running tests automatically..."
    
    # Run Dart tests
    if dart test test/local_sqs_test.dart; then
        print_status "All tests passed!"
        exit_code=0
    else
        print_error "Tests failed!"
        exit_code=1
    fi
    
    # Cleanup will be called automatically due to trap
    exit $exit_code
fi 
