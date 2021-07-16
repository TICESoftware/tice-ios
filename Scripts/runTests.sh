#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'

if [ ! -f server.pid ] && [ ! -f cnc_server.pid ]
then
  echo "Server not running. Aborting."
  exit 1;
fi

SERVER_PORT=$(cat server.port)
CNC_SERVER_PORT=$(cat cnc_server.port)

SERVER_ADDRESS="http://localhost:${SERVER_PORT}"
WS_SERVER_ADDRESS="ws://localhost:${SERVER_PORT}"
CNC_SERVER_ADDRESS="http://localhost:${CNC_SERVER_PORT}"

echo "Running tests with…"
echo "\tServer at ${SERVER_ADDRESS}"
echo "\tWebsocket at ${WS_SERVER_ADDRESS}"
echo "\tCnC at ${CNC_SERVER_ADDRESS}"

# Set address for Tests
/usr/libexec/PlistBuddy -c "Set :SERVER_ADDRESS ${SERVER_ADDRESS}" TICETests/Info.plist
/usr/libexec/PlistBuddy -c "Set :WS_SERVER_ADDRESS ${WS_SERVER_ADDRESS}" TICETests/Info.plist

# Set address for UITests
/usr/libexec/PlistBuddy -c "Set :SERVER_ADDRESS ${SERVER_ADDRESS}" TICEUITests/Info.plist
/usr/libexec/PlistBuddy -c "Set :WS_SERVER_ADDRESS ${WS_SERVER_ADDRESS}" TICEUITests/Info.plist
/usr/libexec/PlistBuddy -c "Set :CNC_SERVER_ADDRESS ${CNC_SERVER_ADDRESS}" TICEUITests/Info.plist

bundle exec fastlane tests
TEST_RESULT=$?

echo "Testing finished with exit code $TEST_RESULT.\n"

if [[ $TEST_RESULT -ne 0 ]]
then
  echo "${RED}Testing failed. Exiting with $TEST_RESULT.${RESET}"
  exit $TEST_RESULT
else
  echo "${GREEN}Testing succeeded.${RESET}"
  exit 0;
fi

echo ""